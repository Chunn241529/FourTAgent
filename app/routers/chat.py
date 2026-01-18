from fastapi import APIRouter, Depends, HTTPException, File, UploadFile, Body
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from app.db import get_db
from app.models import (
    ChatMessage as ModelChatMessage,
    Conversation as ModelConversation,
    User,
)
from app.schemas import ChatMessageIn
from app.routers.task import get_current_user
from app.services.chat_service import ChatService
from app.services.file_service import FileService
from app.services.queue_service import queue_service
from app.services.cloud_llm_service import cloud_llm_service
import logging
import asyncio
import json
from datetime import datetime
from typing import Optional, Union

logger = logging.getLogger(__name__)

router = APIRouter()


async def queued_chat_stream(
    message_in: ChatMessageIn,
    file: Optional[Union[UploadFile, str]],
    conversation_id: Optional[int],
    user_id: int,
    db: Session,
):
    """
    Wrapper that manages queue for chat requests.
    Acquires semaphore before processing, with cloud fallback on timeout.
    """
    queue_stats = queue_service.get_stats()

    # Emit queue status if overloaded
    if queue_stats["is_overloaded"]:
        position = queue_stats["queue_length"] + 1
        yield f"data: {json.dumps({'queue_status': {'position': position, 'message': f'Đang xếp hàng... Vị trí: {position}'}}, separators=(',', ':'))}\n\n"

    # Try to acquire semaphore
    try:
        acquired = await asyncio.wait_for(
            queue_service._semaphore.acquire(), timeout=queue_service.queue_timeout
        )
    except asyncio.TimeoutError:
        # Timeout - cloud fallback not implemented for full chat yet
        yield f"data: {json.dumps({'error': 'Server đang bận, vui lòng thử lại sau.'}, separators=(',', ':'))}\n\n"
        yield f"data: [DONE]\n\n"
        return

    try:
        # Clear queue status
        yield f"data: {json.dumps({'queue_status': {'position': 0, 'message': 'Đang xử lý...'}}, separators=(',', ':'))}\n\n"

        # Call the actual chat service
        response = await ChatService.chat_with_rag(
            message=message_in,
            file=file,
            conversation_id=conversation_id,
            user_id=user_id,
            db=db,
        )

        # Stream the response
        async for chunk in response.body_iterator:
            yield chunk

    finally:
        queue_service._semaphore.release()
        logger.debug("Released queue semaphore")


@router.post("/send", response_class=StreamingResponse)
async def chat(
    message: str = Body(..., embed=True),
    file: Optional[Union[UploadFile, str]] = Body(None, embed=True),
    conversation_id: Optional[int] = None,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Endpoint chính cho chat với RAG và file processing"""

    # Wrap message in ChatMessageIn for service compatibility
    message_in = ChatMessageIn(message=message)

    # Use queued stream wrapper for concurrency control
    return StreamingResponse(
        queued_chat_stream(
            message_in=message_in,
            file=file,
            conversation_id=conversation_id,
            user_id=user_id,
            db=db,
        ),
        media_type="text/event-stream",
    )


@router.get("/queue-stats")
async def get_queue_stats(user_id: int = Depends(get_current_user)):
    """Get current queue statistics"""
    return queue_service.get_stats()
