import whisper
import os
import shutil
from fastapi import UploadFile


class STTService:
    _instance = None
    _model = None
    _model_name = "small"  # Can be "tiny", "base", "small", "medium", "large"

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def _load_model(self):
        if self._model is None:
            print(f"[STT] Loading Whisper model '{self._model_name}'...")
            try:
                self._model = whisper.load_model(self._model_name)
                print(f"[STT] Whisper model loaded successfully.")
            except Exception as e:
                print(f"[STT] Failed to load Whisper model: {e}")
                raise e

    async def transcribe(self, file: UploadFile) -> str:
        self._load_model()

        # Save temp file
        temp_filename = f"temp_{file.filename}"
        try:
            with open(temp_filename, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)

            # Transcribe
            print(f"[STT] Transcribing {temp_filename}...")
            result = self._model.transcribe(temp_filename, language="vi")
            text = result["text"].strip()
            print(f"[STT] Result: {text}")

            return text

        except Exception as e:
            print(f"[STT] Transcription error: {e}")
            return ""
        finally:
            # Cleanup
            if os.path.exists(temp_filename):
                os.remove(temp_filename)


stt_service = STTService()
