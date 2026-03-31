"""
AI Generate Router - Stateless text generation without history/conversation
"""

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, logger
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


# === Image Studio Endpoints (separate LLM for prompt translation) ===

IMAGE_STUDIO_SYSTEM = """You are a Flux 2 editing assistant.
User will provide 1 or 2 images and an instruction in Vietnamese.

RULES:
- Describe the change simply and directly
- Keep it short (1-5 words)
- Do NOT add quality tags
- Do NOT wrap in quotes or code blocks
- Just output the exact change description

ONE IMAGE: describe what to change in that image
TWO IMAGES: image1=model/person, image2=product to apply. User wants to put img2's clothes/product onto img1.

EXAMPLES:
Input: 'đổi tóc vàng' → Output: change hair to blonde
Input: 'đổi đồ ảnh 2 sang ảnh 1' → Output: change clothes
Input: 'đổi áo này' → Output: change shirt
Input: 'thay bộ đồ' → Output: change clothes
Input: 'làm tóc ngắn' → Output: short hair
Input: 'bỏ kính' → Output: remove glasses

Reply with ONLY the result prompt."""


@router.post("/image/edit/studio")
async def edit_image_studio(
    prompt: str = Form(..., description="Description of the changes to make"),
    image1: UploadFile = File(..., description="Primary image to edit"),
    image2: Optional[UploadFile] = File(None, description="Optional second reference image"),
    user_id: int = Depends(get_current_user)
):
    """
    Edit image for Image Studio - uses separate LLM cloud for prompt translation.
    Fast, no history/RAG, optimized for UI response time.
    """
    import logging
    import uuid
    from app.services.chat.chat_llm_router import chat_llm_router

    logger = logging.getLogger(__name__)

    try:
        # Step 1: Save uploaded images
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
            logger.info(f"[ImageStudio] Saved image: {file_path}")
            return file_path

        img1_path = save_upload(image1)
        img2_path = save_upload(image2) if image2 and image2.filename else None
        logger.info(f"[ImageStudio] img1={img1_path}, img2={img2_path}")
        logger.info(f"[ImageStudio] user_prompt='{prompt}'")

        # Step 2: Translate prompt using Lumina-small via Ollama directly (fast)
        logger.info(f"[ImageStudio] Translating prompt via Lumina-small...")
        from app.services.chat.chat_llm_router import chat_llm_router
        flux_prompt = await chat_llm_router.generate_simple_ollama(
            prompt=prompt,
            system_prompt=IMAGE_STUDIO_SYSTEM,
            temperature=0.2,
            max_tokens=450,
        )
        logger.info(f"[ImageStudio] LLM raw output: '{flux_prompt}'")

        if not flux_prompt:
            flux_prompt = prompt  # Fallback to original if LLM fails
            logger.warning(f"[ImageStudio] LLM failed, using original prompt: '{flux_prompt}'")

        # Clean up LLM output
        flux_prompt = flux_prompt.strip()
        if flux_prompt.startswith("```"):
            flux_prompt = "\n".join(flux_prompt.split("\n")[1:-1])
        flux_prompt = flux_prompt.strip('"').strip("'")
        logger.info(f"[ImageStudio] FINAL flux_prompt='{flux_prompt}'")

        # Step 3: Call edit with translated prompt
        result = await image_generation_service.edit_image_direct(
            image1_path=img1_path,
            image2_path=img2_path,
            prompt=flux_prompt,
            user_id=user_id
        )

        if result.get("error"):
            raise HTTPException(status_code=500, detail=result["error"])

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in edit_image_studio: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/image/studio")
async def generate_image_studio(
    description: str = Form(..., description="Description of the image to generate"),
    size: str = Form("768x768", description="Image size"),
    user_id: int = Depends(get_current_user)
):
    """
    Generate image for Image Studio - uses separate LLM cloud for prompt translation.
    Fast, no history/RAG, optimized for UI response time.
    """
    from app.services.chat.chat_llm_router import chat_llm_router

    IMAGE_GEN_SYSTEM = """You are an expert AI image prompt engineer for Flux 2.
Create a SINGLE high-quality English prompt for Flux 2 image generation.

Rules:
- Output comma-separated English tags/phrases ONLY, no explanations
- Start with the main subject, then style, then quality tags
- Keep it concise (under 60 words)
- Do NOT wrap in quotes or code blocks
- Do NOT add anything extra - just output the exact prompt

Examples:
Input: 'con mèo dễ thương trong vườn hoa'
Output: cute cat sitting in a flower garden, soft natural lighting, vibrant colors

Input: 'cyberpunk city at night'
Output: cyberpunk city at night, neon lights, rain reflections, futuristic buildings

Reply with ONLY the result prompt, nothing else."""

    try:
        logger.info(f"[ImageStudio] Translating generation prompt via Lumina-small: {description}")

        from app.services.chat.chat_llm_router import chat_llm_router
        flux_prompt = await chat_llm_router.generate_simple_ollama(
            prompt=description,
            system_prompt=IMAGE_GEN_SYSTEM,
            temperature=0.3,
            max_tokens=500,
        )
        if not flux_prompt:
            flux_prompt = description

        # Clean up
        flux_prompt = flux_prompt.strip()
        if flux_prompt.startswith("```"):
            flux_prompt = "\n".join(flux_prompt.split("\n")[1:-1])
        flux_prompt = flux_prompt.strip('"').strip("'")
        logger.info(f"[ImageStudio] Translated Flux2 generation prompt: {flux_prompt}")

        result = await image_generation_service.generate_image_direct(
            prompt=flux_prompt,
            size=size,
            user_id=user_id
        )

        if result.get("error"):
            raise HTTPException(status_code=500, detail=result["error"])

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in generate_image_studio: {e}", exc_info=True)
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
