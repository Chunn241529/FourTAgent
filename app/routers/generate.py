"""
AI Generate Router - Stateless text generation without history/conversation
"""

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import json

from ollama import AsyncClient

router = APIRouter(prefix="/generate", tags=["generate"])


class GenerateRequest(BaseModel):
    prompt: str
    system_prompt: Optional[str] = None
    model: Optional[str] = "Lumina:latest"
    temperature: Optional[float] = 0.7


@router.post("/stream")
async def generate_stream(request: GenerateRequest):
    """
    Generate text using LLM without saving to conversation history.
    Used for Studio features like translation and script generation.
    Returns SSE stream.
    """

    async def generate():
        try:
            client = AsyncClient()

            messages = []
            if request.system_prompt:
                messages.append({"role": "system", "content": request.system_prompt})
            messages.append({"role": "user", "content": request.prompt})

            stream = await client.chat(
                model=request.model,
                messages=messages,
                stream=True,
                options={"temperature": request.temperature},
                think=False,
            )

            async for chunk in stream:
                if chunk.get("message", {}).get("content"):
                    content = chunk["message"]["content"]
                    data = json.dumps({"content": content})
                    yield f"data: {data}\n\n"

            yield "data: [DONE]\n\n"

        except Exception as e:
            error_data = json.dumps({"error": str(e)})
            yield f"data: {error_data}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/")
async def generate_sync(request: GenerateRequest):
    """
    Generate text synchronously (non-streaming).
    Returns complete response.
    """
    try:
        client = AsyncClient()

        messages = []
        if request.system_prompt:
            messages.append({"role": "system", "content": request.system_prompt})
        messages.append({"role": "user", "content": request.prompt})

        response = await client.chat(
            model=request.model,
            messages=messages,
            stream=False,
            options={"temperature": request.temperature},
        )

        return {
            "content": response.get("message", {}).get("content", ""),
            "model": request.model,
            "done": True,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
