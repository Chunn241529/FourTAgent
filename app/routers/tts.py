from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import StreamingResponse, FileResponse
from app.services.tts_service import TTSService
from app.schemas import TTSRequest
from app.utils import verify_jwt
import os
import tempfile
import io

router = APIRouter(prefix="/tts", tags=["tts"])

# Initialize service (could also be dependency injected if preferred)
tts_service = TTSService()


import uuid
import time


@router.get("/voices")
async def list_voices(user_id: int = Depends(verify_jwt)):
    """List available voice presets and custom user voices."""
    return tts_service.list_voices(user_id=user_id)


@router.post("/voices")
async def create_voice(
    name: str = Form(...),
    files: UploadFile = File(...),
    user_id: int = Depends(verify_jwt),
):
    """Create a new custom voice from an uploaded audio sample."""
    content = await files.read()
    result = tts_service.create_custom_voice(user_id, name, content)

    if not result:
        raise HTTPException(status_code=500, detail="Failed to create custom voice")

    return result


@router.post("/synthesize")
async def synthesize(request: TTSRequest, user_id: int = Depends(verify_jwt)):
    """Convert text to speech and save to storage."""
    audio_bytes = tts_service.synthesize(
        request.text, request.voice_id, user_id=user_id
    )
    if not audio_bytes:
        raise HTTPException(status_code=500, detail="TTS synthesis failed")

    # Save to storage
    voice_dir = f"storage/voice/{user_id}"
    os.makedirs(voice_dir, exist_ok=True)

    filename = f"{int(time.time())}_{uuid.uuid4().hex[:8]}.wav"
    file_path = f"{voice_dir}/{filename}"

    with open(file_path, "wb") as f:
        f.write(audio_bytes)

    return FileResponse(file_path, media_type="audio/wav", filename=filename)


@router.post("/clone")
async def clone_voice(
    text: str = Form(...),
    reference_audio: UploadFile = File(...),
    reference_text: str = Form(None),
    user_id: int = Depends(verify_jwt),
):
    """Clone voice from uploaded audio sample and save output."""
    # Save uploaded file temporarily
    with tempfile.NamedTemporaryFile(
        delete=False, suffix=os.path.splitext(reference_audio.filename)[1]
    ) as tmp:
        content = await reference_audio.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        audio_bytes = tts_service.clone_voice(text, tmp_path, reference_text)
        if not audio_bytes:
            raise HTTPException(status_code=500, detail="Voice cloning failed")

        # Save to storage
        voice_dir = f"storage/voice/{user_id}"
        os.makedirs(voice_dir, exist_ok=True)

        filename = f"clone_{int(time.time())}_{uuid.uuid4().hex[:8]}.wav"
        file_path = f"{voice_dir}/{filename}"

        with open(file_path, "wb") as f:
            f.write(audio_bytes)

        return FileResponse(file_path, media_type="audio/wav", filename=filename)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
