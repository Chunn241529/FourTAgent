"""
Affiliate Automation API Router.

Endpoints for the Flutter UI to interact with the affiliate
automation pipeline (scrape, generate content, render video, smart reup).
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import FileResponse
from app.utils import verify_jwt
from pydantic import BaseModel
from typing import Optional, List, Dict
import os
import uuid
import time
import asyncio
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

class GenerateAIVideoRequest(BaseModel):
    prompt: str
    image_url: Optional[str] = None
    model_image_url: Optional[str] = None
    model: str = "kling" # kling, veo, wan
    api_key: str


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


async def _download_and_save_video(v_url: str, pid: str, uid: int, job_id: str):
    """Background task to download generic video with progress tracking."""
    try:
        from app.services.cloud_file_service import CloudFileService
        import aiohttp

        _jobs[job_id] = {
            "status": "processing",
            "progress": 10,
            "output_path": None,
            "error": None,
            "created_at": time.time(),
        }

        filename = f"reup_{pid}.mp4"
        cloud_path = f"/Affiliate/Videos/{filename}"
        CloudFileService.create_file(uid, cloud_path, "")
        secure_path = CloudFileService._get_secure_path(uid, cloud_path)

        os.makedirs(os.path.dirname(secure_path), exist_ok=True)

        _jobs[job_id]["progress"] = 30

        async with aiohttp.ClientSession() as session:
            async with session.get(v_url, timeout=aiohttp.ClientTimeout(total=300)) as resp:
                if resp.status == 200:
                    total_size = resp.content_length or 0
                    downloaded = 0
                    with open(secure_path, "wb") as f:
                        async for chunk in resp.content.iter_chunked(8192):
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0:
                                pct = 30 + int(60 * downloaded / total_size)
                                _jobs[job_id]["progress"] = min(pct, 90)

                    _jobs[job_id]["output_path"] = cloud_path
                    _jobs[job_id]["status"] = "done"
                    _jobs[job_id]["progress"] = 100
                    logger.info(f"Successfully downloaded generic video to {cloud_path}")
                else:
                    _jobs[job_id]["status"] = "failed"
                    _jobs[job_id]["error"] = f"HTTP {resp.status}"
                    logger.error(f"Failed to download video: {resp.status}")
    except asyncio.TimeoutError:
        _jobs[job_id]["status"] = "failed"
        _jobs[job_id]["error"] = "Download timeout (>300s)"
        logger.error(f"Timeout downloading video {v_url}")
    except Exception as e:
        _jobs[job_id]["status"] = "failed"
        _jobs[job_id]["error"] = str(e)
        logger.error(f"Error downloading generic video: {e}")

@router.post("/scrape")
async def scrape_products(
    request: ScrapeRequest, 
    background_tasks: BackgroundTasks,
    user_id: int = Depends(verify_jwt)
):
    """Scrape products from Shopee/TikTok."""
    scraper = _get_scraper()

    if request.platform == "shopee":
        products = await scraper.scrape_shopee(
            keyword=request.keyword,
            url=request.url,
            limit=request.limit,
        )
    elif request.platform == "tiktok":
        products = await scraper.scrape_tiktok(
            keyword=request.keyword,
            url=request.url,
            limit=request.limit,
        )
    elif request.platform == "generic":
        if not request.url:
            raise HTTPException(400, "URL is required for generic video scraping.")
        generic_p = await scraper.scrape_generic_video(request.url)
        products = [generic_p] if generic_p else []

        if generic_p and generic_p.video_urls:
            download_job_id = uuid.uuid4().hex[:12]
            background_tasks.add_task(
                _download_and_save_video,
                generic_p.video_urls[0],
                generic_p.product_id,
                user_id,
                download_job_id,
            )
            # Include download job info in response
            logger.info(f"[Scrape] Video download started as job {download_job_id}")
    else:
        raise HTTPException(400, f"Unsupported platform: {request.platform}")

    # Save products
    from app.services.cloud_file_service import CloudFileService
    for p in products:
        scraper.save_product(p)

    # Save to Cloud Docs - use hash of keyword/URL to avoid long filenames
    import hashlib
    kwargs_raw = request.keyword or request.url or ""
    kwargs_hash = hashlib.md5(kwargs_raw.encode()).hexdigest()[:16]
    try:
        CloudFileService.create_file(
            user_id,
            f"/Affiliate/Scraped/{request.platform}_{kwargs_hash}.json",
            json.dumps([p.to_dict() for p in products], ensure_ascii=False, indent=2)
        )
    except Exception as e:
        logger.warning(f"Could not save scraped products to cloud: {e}")

    return {
        "status": "success",
        "products": [p.to_dict() for p in products]
    }

@router.delete("/products/{platform}/{product_id}")
async def delete_product(platform: str, product_id: str, user_id: int = Depends(verify_jwt)):
    scraper = _get_scraper()
    success = scraper.delete_saved_product(platform, product_id)
    if not success:
        # Not raising 404 to avoid breaking client optimistic delete if already deleted
        logger.warning(f"Could not delete product {platform}:{product_id} or not found.")
    return {"status": "success"}

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

    from app.services.cloud_file_service import CloudFileService
    try:
        script_content = json.dumps(result.get("script", {}), ensure_ascii=False, indent=2)
        CloudFileService.create_file(
            user_id,
            f"/Affiliate/Scripts/{request.product_id}.json",
            script_content
        )
    except Exception as e:
        logger.warning(f"Could not save script to cloud: {e}")

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
        
        # Check source videos
        video_urls = product.get("video_urls", [])
        source_video = None
        if video_urls:
            v_url = video_urls[0]
            from app.services.cloud_file_service import CloudFileService
            cloud_path = f"/Affiliate/Videos/reup_{request.product_id}.mp4"
            secure_path = CloudFileService._get_secure_path(user_id, cloud_path)
            
            if os.path.exists(secure_path):
                source_video = secure_path
            else:
                os.makedirs(img_dir, exist_ok=True)
                tmp_video = os.path.join(img_dir, "source.mp4")
                import aiohttp
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(v_url) as resp:
                            if resp.status == 200:
                                with open(tmp_video, "wb") as f:
                                    async for chunk in resp.content.iter_chunked(8192):
                                        f.write(chunk)
                                source_video = tmp_video
                except Exception as e:
                    logger.error(f"Failed pulling source video: {e}")

        if not images and not source_video:
            _jobs[job_id]["error"] = "No images or video available"
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
            
            # Save to Cloud
            try:
                from app.services.cloud_file_service import CloudFileService
                import shutil
                cloud_path = f"/Affiliate/Videos/{job_id}.mp4"
                target_secure = CloudFileService._get_secure_path(user_id, cloud_path)
                os.makedirs(os.path.dirname(target_secure), exist_ok=True)
                shutil.copy(result, target_secure)
            except Exception as e:
                logger.warning(f"Could not save rendered video to cloud: {e}")
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


@router.get("/jobs/{job_id}/audio")
async def download_job_audio(job_id: str, user_id: int = Depends(verify_jwt)):
    """Download the extracted audio from a completed smart-reup job (only if strip_audio was selected)."""
    if job_id not in _jobs:
        raise HTTPException(404, "Job not found")

    job = _jobs[job_id]
    if job["status"] != "done":
        raise HTTPException(400, "Job not complete or failed")

    audio_path = job.get("audio_path")
    if not audio_path or not os.path.exists(audio_path):
        raise HTTPException(404, "Audio file not found (strip_audio may not have been selected)")

    return FileResponse(audio_path, media_type="audio/mpeg", filename=f"affiliate_{job_id}.mp3")


@router.post("/generate-ai-video")
async def generate_ai_video(
    request: GenerateAIVideoRequest,
    user_id: int = Depends(verify_jwt),
):
    """Start an AI video generation job."""
    from app.services.affiliate.ai_video_service import ai_video_service
    result = await ai_video_service.start_generation(
        prompt=request.prompt,
        image_path=request.image_url,
        model=request.model,
        api_key=request.api_key,
        model_image_path=request.model_image_url,
    )
    if result.get("error"):
        raise HTTPException(status_code=400, detail=result["error"])
    return result


@router.get("/ai-video-jobs/{job_id}/status")
async def check_ai_video_status(
    job_id: str,
    api_key: str,
    user_id: int = Depends(verify_jwt),
):
    """Check AI video job status and save to cloud if done."""
    from app.services.affiliate.ai_video_service import ai_video_service
    status = await ai_video_service.check_status(job_id, api_key)
    if status.get("error"):
        raise HTTPException(status_code=404, detail=status["error"])
    
    # If done, copy to cloud
    if status.get("status") == "success" and status.get("result_url"):
        from app.services.cloud_file_service import CloudFileService
        import shutil
        cloud_path = f"/Affiliate/AIVideo/{job_id}.mp4"
        try:
            target_secure = CloudFileService._get_secure_path(user_id, cloud_path)
            os.makedirs(os.path.dirname(target_secure), exist_ok=True)
            shutil.copy(status["result_url"], target_secure)
            status["cloud_url"] = cloud_path
        except Exception as e:
            logger.warning(f"Could not save AI video to cloud: {e}")
            pass
            
    return status


@router.post("/upload-model-image")
async def upload_model_image(
    file: UploadFile = File(...),
    user_id: int = Depends(verify_jwt),
):
    """Upload a custom model image to use in AI Video generation."""
    from app.services.cloud_file_service import CloudFileService
    import shutil
    import time
    
    filename = f"model_{int(time.time())}_{file.filename}"
    cloud_path = f"/Affiliate/Models/{filename}"
    
    try:
        # touch standard file entry
        CloudFileService.create_file(user_id, cloud_path, "")
        target_secure = CloudFileService._get_secure_path(user_id, cloud_path)
        os.makedirs(os.path.dirname(target_secure), exist_ok=True)
        with open(target_secure, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        return {"url": cloud_path, "status": "success"}
    except Exception as e:
        logger.error(f"Failed to upload model image: {e}")
        raise HTTPException(status_code=500, detail="Could not upload model image")


@router.post("/smart-reup")
async def smart_reup_upload(
    file: Optional[UploadFile] = File(None),
    source_path: Optional[str] = Form(None),
    product_id: Optional[str] = Form(None),
    transforms: str = Form("metadata,mirror,zoom,color,speed,pitch,recode,trim_end"),
    background_tasks: BackgroundTasks = None,
    user_id: int = Depends(verify_jwt),
):
    """Upload a video for smart reup processing (or use existing path/product_id)."""
    reup = _get_reup_service()

    upload_path = None

    if file:
        # Save uploaded file
        upload_dir = os.path.join("storage", "affiliate", "reup", "uploads")
        os.makedirs(upload_dir, exist_ok=True)
        upload_path = os.path.join(upload_dir, f"{uuid.uuid4().hex[:12]}_{file.filename}")

        with open(upload_path, "wb") as f:
            content = await file.read()
            f.write(content)
    elif source_path and os.path.exists(source_path):
        upload_path = source_path
    elif product_id:
        scraper = _get_scraper()
        products = scraper.list_saved_products()
        product = next((p for p in products if p.get("product_id") == product_id), None)
        if product and product.get("video_urls"):
            v_url = product["video_urls"][0]
            from app.services.cloud_file_service import CloudFileService
            cloud_path = f"/Affiliate/Videos/reup_{product_id}.mp4"
            secure_path = CloudFileService._get_secure_path(user_id, cloud_path)
            
            if os.path.exists(secure_path):
                upload_path = secure_path
            else:
                dl_dir = os.path.join("storage", "affiliate", "media", product_id)
                os.makedirs(dl_dir, exist_ok=True)
                tmp_video = os.path.join(dl_dir, "source_reup.mp4")
                import aiohttp
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(v_url) as resp:
                            if resp.status == 200:
                                with open(tmp_video, "wb") as f:
                                    async for chunk in resp.content.iter_chunked(8192):
                                        f.write(chunk)
                                upload_path = tmp_video
                except Exception as e:
                    logger.error(f"Failed pulling source video for reup: {e}")
                    
    if not upload_path:
        raise HTTPException(400, "Must provide file, valid source_path, or valid product_id with video")

    transform_list = [t.strip() for t in transforms.split(",") if t.strip()]
    transform_list = reup.reorder_transforms(transform_list)

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


# ─── Smart Reup Douyin ────────────────────────────────────────────────────────

class SmartReupDouyinRequest(BaseModel):
    url: Optional[str] = None
    transforms: Optional[List[str]] = None
    crop_settings: Optional[Dict[str, float]] = None  # top, right, bottom, left
    audio_mode: Optional[str] = "strip"  # "strip" | "shift"
    logo_removal: Optional[str] = "none"  # "none" | "manual" | "ai"


@router.post("/smart-reup-douyin")
async def smart_reup_douyin(
    background_tasks: BackgroundTasks,
    file: Optional[UploadFile] = File(None),
    url: Optional[str] = Form(None),
    transforms: Optional[str] = Form(None),  # comma-separated string
    crop_settings_json: Optional[str] = Form(None),  # JSON string
    audio_mode: Optional[str] = Form("strip"),
    logo_removal: Optional[str] = Form("none"),
    user_id: int = Depends(verify_jwt),
):
    """
    Smart Reup for Douyin: paste a Douyin URL or upload a local video,
    select transforms (including new flip_v, strip_audio, manual_crop, AI
    logo removal), and process in background.
    """
    if not url and not file:
        raise HTTPException(400, "Either url or file is required")

    # Parse transforms list
    transform_list = None
    if transforms:
        transform_list = [t.strip() for t in transforms.split(",") if t.strip()]

    # Reorder: strip_audio last, deduplicate mirror/flip_h
    from app.services.affiliate.smart_reup import SmartReupService
    transform_list = SmartReupService.reorder_transforms(transform_list) if transform_list else None

    # Parse crop_settings
    crop_settings = None
    if crop_settings_json:
        crop_settings = json.loads(crop_settings_json)

    # Save uploaded file if provided
    input_path = None
    if file:
        upload_dir = os.path.join("storage", "affiliate", "reup", "uploads")
        os.makedirs(upload_dir, exist_ok=True)
        input_path = os.path.join(upload_dir, f"{uuid.uuid4().hex[:12]}_{file.filename}")
        with open(input_path, "wb") as f:
            content = await file.read()
            f.write(content)

    job_id = uuid.uuid4().hex[:12]
    _jobs[job_id] = {
        "status": "pending",
        "progress": 0,
        "output_path": None,
        "error": None,
        "created_at": time.time(),
        "stages": [],
    }

    background_tasks.add_task(
        _smart_reup_douyin_task,
        job_id,
        url,
        input_path,
        transform_list,
        crop_settings,
        audio_mode,
        logo_removal,
        user_id,
    )

    return {"job_id": job_id, "status": "pending"}


async def _smart_reup_douyin_task(
    job_id: str,
    url: Optional[str],
    input_path: Optional[str],
    transform_list: Optional[List[str]],
    crop_settings: Optional[Dict[str, float]],
    audio_mode: str,
    logo_removal: str,
    user_id: int,
):
    """
    Background task for smart reup with full pipeline:
    1. Scrape/download video from Douyin URL (or use uploaded file)
    2. Chain FFmpeg transforms
    3. AI logo removal (if selected)
    4. Save output to cloud
    """
    try:
        _jobs[job_id]["status"] = "processing"
        _jobs[job_id]["stages"] = ["init", "scrape", "download", "transform", "ai_logo_removal", "assemble", "save"]
        _jobs[job_id]["progress"] = 5

        reup = _get_reup_service()
        scraper = _get_scraper()

        video_path = input_path

        # --- Stage 1: Scrape URL if provided ---
        if url:
            _jobs[job_id]["stages"] = ["init", "scrape", "download"]
            _jobs[job_id]["progress"] = 10
            product = await scraper.scrape_generic_video(url)
            if not product or not product.video_urls:
                _jobs[job_id]["error"] = "Failed to scrape video from URL"
                _jobs[job_id]["status"] = "failed"
                return

            _jobs[job_id]["progress"] = 20

            # --- Stage 2: Download video ---
            video_url = product.video_urls[0]
            download_dir = os.path.join("storage", "affiliate", "reup", "uploads")
            os.makedirs(download_dir, exist_ok=True)
            video_path = os.path.join(download_dir, f"src_{job_id}.mp4")

            async with aiohttp.ClientSession() as session:
                async with session.get(video_url, timeout=aiohttp.ClientTimeout(total=300)) as resp:
                    if resp.status != 200:
                        _jobs[job_id]["error"] = f"Download failed: HTTP {resp.status}"
                        _jobs[job_id]["status"] = "failed"
                        return
                    with open(video_path, "wb") as f:
                        async for chunk in resp.content.iter_chunked(8192):
                            f.write(chunk)

            _jobs[job_id]["progress"] = 35

        if not video_path or not os.path.exists(video_path):
            _jobs[job_id]["error"] = "No video file available"
            _jobs[job_id]["status"] = "failed"
            return

        # --- Stage 3: Apply FFmpeg transforms ---
        _jobs[job_id]["stages"] = ["init", "scrape", "download", "transform"]
        _jobs[job_id]["progress"] = 40

        if transform_list is None:
            transform_list = ["metadata", "mirror", "zoom", "color", "speed", "strip_audio", "trim_end"]

        output_dir = os.path.join("storage", "affiliate", "reup")
        os.makedirs(output_dir, exist_ok=True)

        current_path = video_path
        applied = []
        temp_job_id = job_id

        for i, transform_name in enumerate(transform_list):
            next_path = os.path.join(output_dir, f"{temp_job_id}_{transform_name}.mp4")

            if transform_name == "metadata":
                success = await reup._strip_metadata(current_path, next_path)
            elif transform_name == "mirror":
                success = await reup._mirror_video(current_path, next_path)
            elif transform_name == "flip_h":
                success = await reup._flip_horizontal_video(current_path, next_path)
            elif transform_name == "crop":
                if crop_settings:
                    success = await reup._manual_crop(current_path, next_path, crop_settings)
                else:
                    success = await reup._crop_rescale(current_path, next_path)
            elif transform_name == "strip_audio":
                # Extract audio to separate file before stripping
                if await reup._has_audio_stream(current_path):
                    audio_path = os.path.join(output_dir, f"reup_{job_id}.mp3")
                    extract_ok = await reup._extract_audio(current_path, audio_path)
                    if extract_ok:
                        _jobs[job_id]["audio_path"] = audio_path
                        # Save audio to cloud
                        try:
                            from app.services.cloud_file_service import CloudFileService
                            cloud_audio_path = f"/Affiliate/Videos/reup_{job_id}.mp3"
                            target_audio_secure = CloudFileService._get_secure_path(user_id, cloud_audio_path)
                            os.makedirs(os.path.dirname(target_audio_secure), exist_ok=True)
                            import shutil
                            shutil.copy2(audio_path, target_audio_secure)
                            _jobs[job_id]["audio_cloud_path"] = cloud_audio_path
                        except Exception as e:
                            logger.warning(f"Could not save audio to cloud: {e}")
                success = await reup._strip_audio(current_path, next_path)
            elif transform_name == "pitch":
                success = await reup._pitch_shift(current_path, next_path)
            elif transform_name == "color":
                success = await reup._color_shift(current_path, next_path)
            elif transform_name == "speed":
                success = await reup._speed_change(current_path, next_path)
            elif transform_name == "zoom":
                success = await reup._zoom_video(current_path, next_path)
            elif transform_name == "noise":
                success = await reup._add_noise(current_path, next_path)
            elif transform_name == "recode":
                success = await reup._recode_video(current_path, next_path)
            elif transform_name == "trim_end":
                success = await reup._trim_end(current_path, next_path)
            elif transform_name == "ai_filter":
                success = await reup._comfyui_transform(current_path, next_path)
            else:
                success = False

            if success:
                if current_path != video_path and os.path.exists(current_path):
                    os.remove(current_path)
                current_path = next_path
                applied.append(transform_name)
            else:
                logger.warning(f"[SmartReup] Transform '{transform_name}' failed, skipping")
                # Don't update current_path - the failed file is discarded
                # Next transform will use the previous successful file

            _jobs[job_id]["progress"] = min(40 + (i + 1) * 6, 70)

        _jobs[job_id]["progress"] = 70

        # --- Stage 4: AI logo removal ---
        if logo_removal == "ai":
            _jobs[job_id]["stages"].append("ai_logo_removal")
            _jobs[job_id]["progress"] = 75
            ai_output = os.path.join(output_dir, f"{job_id}_ailogo.mp4")
            ai_success = await reup._ai_logo_removal(current_path, ai_output)
            if ai_success:
                if current_path != video_path and os.path.exists(current_path):
                    os.remove(current_path)
                current_path = ai_output
                applied.append("ai_logo_removal")
            _jobs[job_id]["progress"] = 85

        # --- Stage 5: Assemble final output ---
        _jobs[job_id]["stages"].append("assemble")
        final_path = os.path.join(output_dir, f"reup_{job_id}.mp4")
        if current_path != video_path:
            import shutil
            shutil.move(current_path, final_path)
        else:
            import shutil
            shutil.copy2(current_path, final_path)

        await reup._inject_metadata(final_path)

        _jobs[job_id]["progress"] = 95

        # --- Stage 6: Save to cloud ---
        _jobs[job_id]["stages"].append("save")
        try:
            from app.services.cloud_file_service import CloudFileService
            cloud_path = f"/Affiliate/Videos/reup_{job_id}.mp4"
            target_secure = CloudFileService._get_secure_path(user_id, cloud_path)
            os.makedirs(os.path.dirname(target_secure), exist_ok=True)
            import shutil
            shutil.copy2(final_path, target_secure)
            _jobs[job_id]["cloud_path"] = cloud_path
        except Exception as e:
            logger.warning(f"Could not save reup video to cloud: {e}")

        # Cleanup source file if it was downloaded
        if video_path != input_path and os.path.exists(video_path):
            try:
                os.remove(video_path)
            except Exception:
                pass

        _jobs[job_id]["output_path"] = _jobs[job_id].get("cloud_path", final_path)
        _jobs[job_id]["transforms_applied"] = applied
        _jobs[job_id]["status"] = "done"
        _jobs[job_id]["progress"] = 100

    except Exception as e:
        _jobs[job_id]["error"] = str(e)
        _jobs[job_id]["status"] = "failed"
        logger.error(f"[_smart_reup_douyin_task] Job {job_id} failed: {e}", exc_info=True)
