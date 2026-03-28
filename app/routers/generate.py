"""
AI Generate Router - Stateless text generation without history/conversation
"""

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import json
import os
import shutil
from pathlib import Path

from ollama import AsyncClient
from app.routers.task import get_current_user

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
async def generate_image(request: ImageGenerateRequest, user_id: int = Depends(get_current_user)):
    """
    Generate an image using ComfyUI with LLM-enhanced prompts.
    Returns the generated image path and prompt info.
    """
    try:
        result = await image_generation_service.generate_image(
            description=request.description, size=request.size or "512x512", user_id=user_id
        )

        if result.get("error"):
            raise HTTPException(status_code=500, detail=result["error"])

        return result

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/image/edit")
async def edit_image(
    prompt: str = Form(..., description="Description of the changes to make"),
    image1: UploadFile = File(..., description="Primary image to edit"),
    image2: Optional[UploadFile] = File(None, description="Optional second reference image"),
    user_id: int = Depends(get_current_user)
):
    """
    Edit uploaded image(s) using ComfyUI with LLM-enhanced prompts.
    Accepts 1 or 2 images. Saves to user's cloud input directory before processing.
    """
    import logging
    import uuid
    logger = logging.getLogger(__name__)
    
    try:
        cloud_dir = os.path.join(
            "/home/trung/Documents/4T_task/user_data/cloud", 
            str(user_id), 
            "input"
        )
        os.makedirs(cloud_dir, exist_ok=True)
        
        def save_upload(upload: UploadFile) -> str:
            safe_filename = os.path.basename(upload.filename)
            base_name, ext = os.path.splitext(safe_filename)
            unique_filename = f"{base_name}_{uuid.uuid4().hex[:8]}{ext}"
            file_path = os.path.join(cloud_dir, unique_filename)
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(upload.file, buffer)
            logger.info(f"Saved uploaded image to: {file_path}")
            return file_path
        
        # Save image1 (required)
        img1_path = save_upload(image1)
        
        # Save image2 (optional)
        img2_path = None
        if image2 is not None and image2.filename:
            img2_path = save_upload(image2)
            
        # Call the edit image service
        result = await image_generation_service.edit_image_direct(
            image1_path=img1_path,
            image2_path=img2_path,
            prompt=prompt,
            user_id=user_id
        )

        if result.get("error"):
            raise HTTPException(status_code=500, detail=result["error"])

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error editing image: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/image/view/{filename}")
async def view_generated_image(filename: str):
    """
    Serve a generated image. Searches user cloud output dirs first, then ComfyUI output.
    """
    from fastapi.responses import FileResponse
    import os
    import logging
    import glob

    logger = logging.getLogger(__name__)

    # Security: prevent path traversal
    safe_filename = os.path.basename(filename)
    
    # 1. Search user cloud output directories first
    cloud_base = "/home/trung/Documents/4T_task/user_data/cloud"
    if os.path.exists(cloud_base):
        for user_dir in os.listdir(cloud_base):
            candidate = os.path.join(cloud_base, user_dir, "output", safe_filename)
            if os.path.exists(candidate):
                logger.info(f"[IMAGE VIEW] Found in user cloud: {candidate}")
                return FileResponse(candidate, media_type=_guess_media_type(safe_filename))

    # 2. Fallback to ComfyUI output directory
    output_dir = os.getenv("COMFYUI_OUTPUT_DIR", "/home/trung/ComfyUI/output")
    image_path = os.path.join(output_dir, safe_filename)

    if os.path.exists(image_path):
        logger.info(f"[IMAGE VIEW] Found in ComfyUI output: {image_path}")
        return FileResponse(image_path, media_type=_guess_media_type(safe_filename))

    logger.error(f"[IMAGE VIEW] File not found anywhere: {safe_filename}")
    raise HTTPException(status_code=404, detail=f"Image not found: {safe_filename}")


def _guess_media_type(filename: str) -> str:
    lower = filename.lower()
    if lower.endswith((".jpg", ".jpeg")):
        return "image/jpeg"
    elif lower.endswith(".webp"):
        return "image/webp"
    return "image/png"
