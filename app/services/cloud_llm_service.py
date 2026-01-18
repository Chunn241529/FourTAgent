"""
Cloud LLM Service for fallback when local Ollama is overloaded.

Supports Groq API with streaming responses.
"""

import os
import json
import logging
import aiohttp
from typing import List, Dict, Any, Optional, AsyncGenerator

logger = logging.getLogger(__name__)


class CloudLLMService:
    """
    Cloud LLM service using Groq API for fast inference.

    Groq provides extremely fast inference at low cost.
    Models: llama-3.3-70b-versatile, mixtral-8x7b-32768, etc.
    """

    GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"

    def __init__(self):
        self.api_key = os.getenv("GROQ_API_KEY")
        self.default_model = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
        self.enabled = bool(self.api_key)

        if self.enabled:
            logger.info(f"CloudLLMService initialized with model: {self.default_model}")
        else:
            logger.warning("CloudLLMService disabled: GROQ_API_KEY not set")

    def is_available(self) -> bool:
        """Check if cloud service is available."""
        return self.enabled

    async def stream_chat(
        self,
        messages: List[Dict[str, Any]],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 4096,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Stream chat completion from Groq API.

        Args:
            messages: Chat messages in OpenAI format
            model: Model name (default: llama-3.3-70b-versatile)
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate

        Yields:
            Response chunks in Ollama-compatible format
        """
        if not self.enabled:
            raise RuntimeError("Cloud LLM service not configured. Set GROQ_API_KEY.")

        model = model or self.default_model

        # Convert messages to Groq format (OpenAI compatible)
        groq_messages = []
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")

            # Skip tool messages for now (Groq handles differently)
            if role == "tool":
                role = "assistant"
                content = f"[Tool Result]: {content}"

            groq_messages.append({"role": role, "content": content})

        payload = {
            "model": model,
            "messages": groq_messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": True,
        }

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.GROQ_API_URL,
                    json=payload,
                    headers=headers,
                ) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        logger.error(
                            f"Groq API error: {response.status} - {error_text}"
                        )
                        yield {
                            "message": {
                                "content": f"[Cloud API Error: {response.status}]"
                            }
                        }
                        return

                    # Stream response
                    async for line in response.content:
                        line = line.decode("utf-8").strip()

                        if not line or line == "data: [DONE]":
                            continue

                        if line.startswith("data: "):
                            try:
                                data = json.loads(line[6:])

                                # Extract content delta
                                choices = data.get("choices", [])
                                if choices:
                                    delta = choices[0].get("delta", {})
                                    content = delta.get("content", "")

                                    if content:
                                        # Yield in Ollama-compatible format
                                        yield {
                                            "message": {
                                                "content": content,
                                            }
                                        }

                            except json.JSONDecodeError:
                                continue

                    # Signal completion
                    yield {"done": True}

        except aiohttp.ClientError as e:
            logger.error(f"Groq API connection error: {e}")
            yield {"message": {"content": f"[Cloud API Connection Error: {str(e)}]"}}
        except Exception as e:
            logger.error(f"Unexpected error in CloudLLMService: {e}")
            yield {"message": {"content": f"[Cloud API Error: {str(e)}]"}}


# Global instance
cloud_llm_service = CloudLLMService()
