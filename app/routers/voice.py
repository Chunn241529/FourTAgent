from fastapi import APIRouter, UploadFile, File, HTTPException
from app.services.stt_service import stt_service


router = APIRouter(prefix="/voice", tags=["voice"])


@router.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    """
    Transcribe uploaded audio file to text.
    """
    if not file:
        raise HTTPException(status_code=400, detail="No file uploaded")

    try:
        text = await stt_service.transcribe(file)
        return {"text": text}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
