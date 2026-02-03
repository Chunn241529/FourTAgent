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


# === Image Generation ===

from pydantic import Field
from app.services.image_generation_service import image_generation_service


class ImageGenerateRequest(BaseModel):
    description: str = Field(..., description="Description of the image to generate")
    size: Optional[str] = Field(
        "768x768", description="Image size like '512x512', '768x768', '1024x1024'"
    )


@router.post("/image")
async def generate_image(request: ImageGenerateRequest):
    """
    Generate an image using ComfyUI with LLM-enhanced prompts.
    Returns the generated image path and prompt info.
    """
    try:
        result = await image_generation_service.generate_image(
            description=request.description, size=request.size or "512x512"
        )

        if result.get("error"):
            raise HTTPException(status_code=500, detail=result["error"])

        return result

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/image/view/{filename}")
async def view_generated_image(filename: str):
    """
    Serve a generated image from ComfyUI output directory.
    This proxies the image so the client doesn't need direct access to ComfyUI.
    """
    from fastapi.responses import FileResponse
    import os
    import logging

    logger = logging.getLogger(__name__)

    # Get output directory from environment or default
    output_dir = os.getenv("COMFYUI_OUTPUT_DIR", "/home/trung/ComfyUI/output")
    logger.info(f"[IMAGE VIEW] Requested: {filename}, output_dir: {output_dir}")

    # Security: prevent path traversal
    safe_filename = os.path.basename(filename)
    image_path = os.path.join(output_dir, safe_filename)

    logger.info(f"[IMAGE VIEW] Looking for: {image_path}")

    if not os.path.exists(image_path):
        logger.error(f"[IMAGE VIEW] File not found: {image_path}")
        # List files in output dir for debugging
        if os.path.exists(output_dir):
            files = os.listdir(output_dir)[:10]
            logger.info(f"[IMAGE VIEW] Files in {output_dir}: {files}")
        raise HTTPException(status_code=404, detail=f"Image not found: {safe_filename}")

    # Determine content type
    content_type = "image/png"
    if safe_filename.lower().endswith(".jpg") or safe_filename.lower().endswith(
        ".jpeg"
    ):
        content_type = "image/jpeg"
    elif safe_filename.lower().endswith(".webp"):
        content_type = "image/webp"

    logger.info(f"[IMAGE VIEW] Serving: {image_path}")
    return FileResponse(image_path, media_type=content_type)
