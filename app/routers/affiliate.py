"""
Affiliate Automation API Router.

Endpoints for the Flutter UI to interact with the affiliate
automation pipeline (scrape, generate content, render video, smart reup).
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import FileResponse
from app.utils import verify_jwt
from pydantic import BaseModel
from typing import Optional, List
import os
import uuid
import time
import logging
import json

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/affiliate", tags=["affiliate"])

# Lazy-init services to avoid import overhead at startup
_llm_router = None
_scraper = None
_content_gen = None
_media_engine = None
_reup_service = None


def _get_llm_router():
    global _llm_router
    if _llm_router is None:
        from app.services.affiliate.llm_router import LLMRouter
        _llm_router = LLMRouter()
    return _llm_router


def _get_scraper():
    global _scraper
    if _scraper is None:
        from app.services.affiliate.scraper import ProductScraper
        _scraper = ProductScraper()
    return _scraper


def _get_content_gen():
    global _content_gen
    if _content_gen is None:
        from app.services.affiliate.content_generator import ContentGenerator
        _content_gen = ContentGenerator()
    return _content_gen


def _get_media_engine():
    global _media_engine
    if _media_engine is None:
        from app.services.affiliate.media_engine import MediaEngine
        _media_engine = MediaEngine()
    return _media_engine


def _get_reup_service():
    global _reup_service
    if _reup_service is None:
        from app.services.affiliate.smart_reup import SmartReupService
        _reup_service = SmartReupService()
    return _reup_service


# --- Request/Response Models ---

class ScrapeRequest(BaseModel):
    platform: str = "shopee"  # "shopee" | "tiktok"
    keyword: Optional[str] = None
    url: Optional[str] = None
    limit: int = 10


class GenerateScriptRequest(BaseModel):
    product_id: str  # hash_id from scraper
    style: str = "genz"
    duration: str = "30s"
    custom_prompt: Optional[str] = None


class RenderVideoRequest(BaseModel):
    product_id: str
    script_text: str
    use_tts: bool = False
    voice_id: Optional[str] = None
    bgm_index: Optional[int] = None
    duration_per_image: float = 3.0


class SmartReupRequest(BaseModel):
    transforms: Optional[List[str]] = None  # None = default set


# In-memory job tracking (production would use Redis/DB)
_jobs: dict = {}


# --- Endpoints ---

@router.get("/status")
async def get_status(user_id: int = Depends(verify_jwt)):
    """Get status of all LLM providers and services."""
    llm = _get_llm_router()
    reup = _get_reup_service()
    comfyui_ok = await reup.check_comfyui_status()

    return {
        "llm_providers": llm.get_status(),
        "comfyui_available": comfyui_ok,
    }


@router.post("/scrape")
async def scrape_products(request: ScrapeRequest, user_id: int = Depends(verify_jwt)):
    """Scrape products from Shopee/TikTok."""
    scraper = _get_scraper()

    if request.platform == "shopee":
        products = await scraper.scrape_shopee(
            keyword=request.keyword, url=request.url, limit=request.limit,
        )
    elif request.platform == "tiktok":
        products = await scraper.scrape_tiktok(
            keyword=request.keyword, url=request.url, limit=request.limit,
        )
    else:
        raise HTTPException(400, f"Unsupported platform: {request.platform}")

    # Save products
    for p in products:
        scraper.save_product(p)

    return {"products": [p.to_dict() for p in products], "count": len(products)}


@router.get("/products")
async def list_products(user_id: int = Depends(verify_jwt)):
    """List all saved/scraped products."""
    scraper = _get_scraper()
    return {"products": scraper.list_saved_products()}


@router.post("/generate-script")
async def generate_script(request: GenerateScriptRequest, user_id: int = Depends(verify_jwt)):
    """Generate viral review script for a product."""
    scraper = _get_scraper()
    gen = _get_content_gen()

    # Find product from storage
    products = scraper.list_saved_products()
    product_data = None
    for p in products:
        if p.get("product_id") == request.product_id or p.get("hash_id") == request.product_id:
            from app.services.affiliate.scraper import ProductData
            product_data = ProductData(**{k: v for k, v in p.items() if k != "hash_id"})
            break

    if not product_data:
        raise HTTPException(404, f"Product not found: {request.product_id}")

    result = await gen.generate_script(
        product=product_data,
        style=request.style,
        duration=request.duration,
        custom_prompt=request.custom_prompt,
    )

    if result["error"]:
        raise HTTPException(500, f"Generation failed: {result['error']}")

    return result


@router.post("/render-video")
async def render_video(
    request: RenderVideoRequest,
    background_tasks: BackgroundTasks,
    user_id: int = Depends(verify_jwt),
):
    """
    Start video render job (runs in background).
    Returns a job_id to track progress.
    """
    job_id = uuid.uuid4().hex[:12]
    _jobs[job_id] = {
        "status": "pending",
        "progress": 0,
        "output_path": None,
        "error": None,
        "created_at": time.time(),
    }

    background_tasks.add_task(
        _render_video_task, job_id, request, user_id,
    )

    return {"job_id": job_id, "status": "pending"}


async def _render_video_task(job_id: str, request: RenderVideoRequest, user_id: int):
    """Background task for video rendering."""
    try:
        _jobs[job_id]["status"] = "processing"
        engine = _get_media_engine()
        scraper = _get_scraper()

        # Find product images
        products = scraper.list_saved_products()
        product = None
        for p in products:
            if p.get("product_id") == request.product_id:
                product = p
                break

        if not product:
            _jobs[job_id]["error"] = "Product not found"
            _jobs[job_id]["status"] = "failed"
            return

        # Download images
        image_urls = product.get("image_urls", [])
        img_dir = os.path.join("storage", "affiliate", "media", request.product_id)
        images = await engine.download_images(image_urls, img_dir)

        if not images:
            _jobs[job_id]["error"] = "No images available"
            _jobs[job_id]["status"] = "failed"
            return

        _jobs[job_id]["progress"] = 30

        # Optional TTS
        tts_path = None
        if request.use_tts and request.script_text:
            try:
                from app.services.tts_service import tts_service
                audio_bytes = tts_service.synthesize(
                    request.script_text, request.voice_id, user_id=user_id,
                )
                if audio_bytes:
                    tts_path = os.path.join(img_dir, "tts_audio.wav")
                    with open(tts_path, "wb") as f:
                        f.write(audio_bytes)
            except Exception as e:
                logger.warning(f"TTS failed, rendering without voice: {e}")

        _jobs[job_id]["progress"] = 50

        # BGM
        bgm_path = None
        if request.bgm_index is not None:
            bgm_list = engine.list_bgm()
            if 0 <= request.bgm_index < len(bgm_list):
                bgm_path = bgm_list[request.bgm_index]

        # Render
        output_path = os.path.join("storage", "affiliate", "output", f"{job_id}.mp4")
        result = await engine.render_video(
            images=images,
            script_text=request.script_text,
            output_path=output_path,
            use_tts=request.use_tts,
            tts_audio_path=tts_path,
            bgm_path=bgm_path,
            duration_per_image=request.duration_per_image,
        )

        if result:
            _jobs[job_id]["output_path"] = result
            _jobs[job_id]["status"] = "done"
            _jobs[job_id]["progress"] = 100
        else:
            _jobs[job_id]["error"] = "Render failed"
            _jobs[job_id]["status"] = "failed"

    except Exception as e:
        _jobs[job_id]["error"] = str(e)
        _jobs[job_id]["status"] = "failed"
        logger.error(f"Render job {job_id} failed: {e}", exc_info=True)


@router.get("/jobs/{job_id}")
async def get_job_status(job_id: str, user_id: int = Depends(verify_jwt)):
    """Check status of a background render job."""
    if job_id not in _jobs:
        raise HTTPException(404, "Job not found")
    return _jobs[job_id]


@router.get("/jobs/{job_id}/download")
async def download_job_result(job_id: str, user_id: int = Depends(verify_jwt)):
    """Download the rendered video from a completed job."""
    if job_id not in _jobs:
        raise HTTPException(404, "Job not found")

    job = _jobs[job_id]
    if job["status"] != "done" or not job["output_path"]:
        raise HTTPException(400, "Job not complete or failed")

    return FileResponse(job["output_path"], media_type="video/mp4", filename=f"affiliate_{job_id}.mp4")


@router.post("/smart-reup")
async def smart_reup_upload(
    file: UploadFile = File(...),
    transforms: str = Form("metadata,mirror,crop,speed,pitch"),
    background_tasks: BackgroundTasks = None,
    user_id: int = Depends(verify_jwt),
):
    """Upload a video for smart reup processing."""
    reup = _get_reup_service()

    # Save uploaded file
    upload_dir = os.path.join("storage", "affiliate", "reup", "uploads")
    os.makedirs(upload_dir, exist_ok=True)
    upload_path = os.path.join(upload_dir, f"{uuid.uuid4().hex[:12]}_{file.filename}")

    with open(upload_path, "wb") as f:
        content = await file.read()
        f.write(content)

    transform_list = [t.strip() for t in transforms.split(",") if t.strip()]

    result = await reup.process_video(
        input_path=upload_path,
        transforms=transform_list,
    )

    if result["error"]:
        raise HTTPException(500, f"Smart reup failed: {result['error']}")

    return result


@router.get("/smart-reup/transforms")
async def list_transforms(user_id: int = Depends(verify_jwt)):
    """List available smart reup transforms."""
    reup = _get_reup_service()
    return {"transforms": reup.list_transforms()}


@router.get("/llm-providers")
async def list_llm_providers(user_id: int = Depends(verify_jwt)):
    """List all configured LLM providers and their status."""
    llm = _get_llm_router()
    return {"providers": llm.get_status()}
