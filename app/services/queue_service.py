"""
Queue Service for managing concurrent LLM requests.

Uses asyncio Semaphore to limit concurrent Ollama requests,
preventing overload and enabling graceful fallback to cloud APIs.
"""

import asyncio
import os
import logging
from typing import Optional, Dict, Any, Callable, AsyncGenerator
from dataclasses import dataclass, field
from datetime import datetime
import uuid

logger = logging.getLogger(__name__)


@dataclass
class QueuedRequest:
    """Represents a request in the queue."""

    id: str
    created_at: datetime = field(default_factory=datetime.now)
    position: int = 0


class LLMQueueService:
    """
    Manages concurrent LLM requests with queue and fallback support.

    Features:
    - Semaphore-based concurrency limiting
    - Queue position tracking
    - Timeout handling
    - Cloud fallback when queue is full
    """

    _instance: Optional["LLMQueueService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return

        self.max_concurrent = int(os.getenv("MAX_CONCURRENT_LLM", "4"))
        self.queue_timeout = int(os.getenv("QUEUE_TIMEOUT", "60"))
        self.enable_cloud_fallback = (
            os.getenv("ENABLE_CLOUD_FALLBACK", "true").lower() == "true"
        )

        self._semaphore = asyncio.Semaphore(self.max_concurrent)
        self._queue: Dict[str, QueuedRequest] = {}
        self._active_count = 0
        self._total_processed = 0
        self._lock = asyncio.Lock()

        self._initialized = True
        logger.info(
            f"LLMQueueService initialized: max_concurrent={self.max_concurrent}, timeout={self.queue_timeout}s"
        )

    @property
    def queue_length(self) -> int:
        """Current number of requests waiting in queue."""
        return len(self._queue)

    @property
    def active_requests(self) -> int:
        """Current number of actively processing requests."""
        return self._active_count

    @property
    def is_overloaded(self) -> bool:
        """Check if system is overloaded (queue full)."""
        return self._active_count >= self.max_concurrent

    async def _add_to_queue(self) -> QueuedRequest:
        """Add a new request to the queue."""
        async with self._lock:
            request_id = str(uuid.uuid4())[:8]
            position = self.queue_length + self._active_count
            request = QueuedRequest(id=request_id, position=position)
            self._queue[request_id] = request
            logger.debug(f"Request {request_id} added to queue at position {position}")
            return request

    async def _remove_from_queue(self, request_id: str):
        """Remove a request from the queue."""
        async with self._lock:
            if request_id in self._queue:
                del self._queue[request_id]

    async def _increment_active(self):
        """Increment active request count."""
        async with self._lock:
            self._active_count += 1

    async def _decrement_active(self):
        """Decrement active request count."""
        async with self._lock:
            self._active_count -= 1
            self._total_processed += 1

    async def execute_with_queue(
        self,
        local_fn: Callable[[], AsyncGenerator],
        cloud_fn: Optional[Callable[[], AsyncGenerator]] = None,
        on_queue_position: Optional[Callable[[int], None]] = None,
    ) -> AsyncGenerator[str, None]:
        """
        Execute an LLM request with queue management and optional cloud fallback.

        Args:
            local_fn: Async generator function for local Ollama request
            cloud_fn: Optional async generator function for cloud fallback
            on_queue_position: Optional callback to report queue position

        Yields:
            Response chunks from either local or cloud LLM
        """
        queued_request = await self._add_to_queue()

        try:
            # Report initial queue position
            if on_queue_position:
                on_queue_position(queued_request.position)

            # Try to acquire semaphore with timeout
            try:
                acquired = await asyncio.wait_for(
                    self._semaphore.acquire(), timeout=self.queue_timeout
                )
            except asyncio.TimeoutError:
                # Timeout waiting for slot - try cloud fallback
                logger.warning(
                    f"Request {queued_request.id} timed out waiting for slot"
                )

                if self.enable_cloud_fallback and cloud_fn:
                    logger.info(
                        f"Falling back to cloud for request {queued_request.id}"
                    )
                    async for chunk in cloud_fn():
                        yield chunk
                    return
                else:
                    raise TimeoutError("Queue timeout and no cloud fallback available")

            try:
                await self._increment_active()

                # Report that we're now processing
                if on_queue_position:
                    on_queue_position(0)  # Position 0 = currently processing

                # Execute local request
                async for chunk in local_fn():
                    yield chunk

            finally:
                await self._decrement_active()
                self._semaphore.release()

        finally:
            await self._remove_from_queue(queued_request.id)

    def get_stats(self) -> Dict[str, Any]:
        """Get queue statistics."""
        return {
            "max_concurrent": self.max_concurrent,
            "active_requests": self._active_count,
            "queue_length": self.queue_length,
            "total_processed": self._total_processed,
            "is_overloaded": self.is_overloaded,
            "cloud_fallback_enabled": self.enable_cloud_fallback,
        }


# Global instance
queue_service = LLMQueueService()
