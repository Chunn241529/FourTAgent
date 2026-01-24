import os
import sys
import re
import numpy as np
import io
import soundfile as sf
import tempfile
import json
import uuid
import time
from typing import Optional, List, Union, Dict

# Update import to include FastVieNeuTTS if available, or dynamic import
try:
    from vieneu import Vieneu, FastVieNeuTTS
except ImportError:
    from vieneu import Vieneu

    FastVieNeuTTS = None

try:
    import whisper
except ImportError:
    import subprocess

    subprocess.check_call([sys.executable, "-m", "pip", "install", "openai-whisper"])
    import whisper

SAMPLE_RATE = 24000
MAX_TEXT_LENGTH = 5000

# Environment variables
TTS_MODE = os.getenv("TTS_MODE", "local")  # "local", "remote", "fast" (lmdeploy)
TTS_REMOTE_URL = os.getenv("TTS_REMOTE_URL", "http://localhost:23333/v1")
TTS_REMOTE_MODEL_ID = os.getenv("TTS_REMOTE_MODEL_ID", "pnnbao-ump/VieNeu-TTS")


class TTSService:
    def __init__(self):
        self.mode = TTS_MODE
        self.tts = None
        self.asr_model = None
        self._initialize()

    def _initialize(self):
        print(f"Initializing TTS Service in {self.mode} mode...")

        # Load Whisper for ASR (used for custom voice reference text)
        print("Loading Whisper model (base)...")
        try:
            self.asr_model = whisper.load_model("base")
            print("Whisper model loaded.")
        except Exception as e:
            print(f"Failed to load Whisper: {e}")

        if self.mode == "remote":
            # Remote mode (lightweight, connects to server)
            self.tts = Vieneu(
                mode="remote", api_base=TTS_REMOTE_URL, model_name=TTS_REMOTE_MODEL_ID
            )
        elif self.mode == "fast":
            if FastVieNeuTTS is None:
                print(
                    "FastVieNeuTTS not available (lmdeploy installed?). Falling back to standard Vieneu."
                )
                self.tts = Vieneu()
            else:
                print("Loading FastVieNeuTTS with lmdeploy...")
                try:
                    self.tts = FastVieNeuTTS()
                except Exception as e:
                    print(
                        f"Failed to load FastVieNeuTTS: {e}. Falling back to standard Vieneu."
                    )
                    self.tts = Vieneu()
        else:
            # Local mode (loads model into memory)
            self.tts = Vieneu()
        print("TTS Service initialized.")

    def list_voices(self, user_id: Optional[int] = None) -> List[dict]:
        """
        Returns a list of available voice presets and custom voices for the user.
        Format: [{"id": "voice_id", "description": "Description", "type": "preset"|"custom"}]
        """
        try:
            # 1. Preset voices
            voices = self.tts.list_preset_voices()
            # voices is a list of tuples: (description, voice_id)
            result = [
                {"id": v_id, "description": desc, "type": "preset"}
                for desc, v_id in voices
            ]

            # 2. Custom voices
            if user_id:
                custom_voices = self._get_custom_voices(user_id)
                for v_id, data in custom_voices.items():
                    result.append(
                        {
                            "id": v_id,
                            "description": data.get("name", "Custom Voice"),
                            "type": "custom",
                            "created_at": data.get("created_at"),
                        }
                    )

            return result
        except Exception as e:
            print(f"Error listing voices: {e}")
            return []

    def create_custom_voice(
        self, user_id: int, name: str, audio_bytes: bytes
    ) -> Optional[dict]:
        """Create a new custom voice from audio bytes."""
        try:
            voice_id = str(uuid.uuid4())
            timestamp = int(time.time())

            # Storage paths
            storage_dir = f"storage/voices/{user_id}"
            os.makedirs(storage_dir, exist_ok=True)

            filename = f"{voice_id}.wav"
            file_path = f"{storage_dir}/{filename}"

            # Save audio file
            with open(file_path, "wb") as f:
                f.write(audio_bytes)

            # Transcribe audio to get reference text
            ref_text = ""
            if self.asr_model:
                try:
                    print("Transcribing audio for reference text...")
                    result = self.asr_model.transcribe(file_path, language="vi")
                    ref_text = result["text"].strip()
                    print(f"Transcribed text: {ref_text}")
                except Exception as e:
                    print(f"Error transcribing audio: {e}")
            else:
                print("Whisper model not available. Using empty reference text.")

            # Update metadata
            metadata_path = f"{storage_dir}/voices.json"
            voices_data = {}
            if os.path.exists(metadata_path):
                try:
                    with open(metadata_path, "r") as f:
                        voices_data = json.load(f)
                except json.JSONDecodeError:
                    pass

            voice_entry = {
                "name": name,
                "filename": filename,
                "created_at": timestamp,
                "ref_text": ref_text,
            }
            voices_data[voice_id] = voice_entry

            with open(metadata_path, "w") as f:
                json.dump(voices_data, f, indent=2)

            return {
                "id": voice_id,
                "description": name,
                "type": "custom",
                "created_at": timestamp,
                "ref_text": ref_text,
            }
        except Exception as e:
            print(f"Error creating custom voice: {e}")
            return None

    def _get_custom_voices(self, user_id: int) -> Dict:
        """Helper to load custom voices metadata."""
        metadata_path = f"storage/voices/{user_id}/voices.json"
        if not os.path.exists(metadata_path):
            return {}
        try:
            with open(metadata_path, "r") as f:
                return json.load(f)
        except Exception:
            return {}

    def synthesize(
        self, text: str, voice_id: Optional[str] = None, user_id: Optional[int] = None
    ) -> Union[bytes, None]:
        """
        Synthesize text to speech using a specific voice ID or default.
        Returns audio bytes (WAV format).
        """
        try:
            voice_data = None
            ref_audio_path = None
            ref_text = None

            if len(text) > MAX_TEXT_LENGTH:
                raise ValueError(
                    f"Text length exceeds {MAX_TEXT_LENGTH} characters limit."
                )

            if voice_id:
                # Check if it's a preset voice
                # We can't easily check validity without listing, but get_preset_voice throws or returns default?
                # Actually, Vieneu.get_preset_voice might fail if invalid.
                # Let's try to get it as preset first.

                # Hack: Check if UUID-like, assume custom? Or check list.
                # Better: Check custom voices first if user_id is provided.
                is_custom = False
                if user_id:
                    custom_voices = self._get_custom_voices(user_id)
                    if voice_id in custom_voices:
                        is_custom = True
                        voice_entry = custom_voices[voice_id]
                        ref_audio_path = (
                            f"storage/voices/{user_id}/{voice_entry['filename']}"
                        )
                        ref_text = voice_entry.get("ref_text")

                if not is_custom:
                    try:
                        voice_data = self.tts.get_preset_voice(voice_id)
                    except Exception:
                        # fallback or error? If not found in custom and not found in preset (implied by try),
                        # it might be an invalid ID.
                        pass

            # Use long text inference
            # If ref_audio_path is set (custom voice), it will be used.
            # If voice_data is set (preset voice), it will be used.
            audio_array = self._infer_long_text(
                text, voice_data=voice_data, ref_audio=ref_audio_path, ref_text=ref_text
            )

            if audio_array is None:
                return None

            return self._audio_to_bytes(audio_array)
        except Exception as e:
            print(f"Error synthesizing text: {e}")
            return None

    def clone_voice(
        self, text: str, reference_audio_path: str, reference_text: Optional[str] = None
    ) -> Union[bytes, None]:
        """
        Clone voice from a reference audio file.
        """
        try:
            if len(text) > MAX_TEXT_LENGTH:
                raise ValueError(
                    f"Text length exceeds {MAX_TEXT_LENGTH} characters limit."
                )

            # Use long text inference for cloning too
            audio_array = self._infer_long_text(
                text, ref_audio=reference_audio_path, ref_text=reference_text
            )

            if audio_array is None:
                return None

            return self._audio_to_bytes(audio_array)
        except Exception as e:
            print(f"Error cloning voice: {e}")
            return None

    def _split_text_smart(self, text: str) -> List[str]:
        """Split text into sentences intelligently."""
        # Split by . ! ? or newline, keeping the delimiter if possible
        return [s.strip() for s in re.split(r"(?<=[.!?\n])\s+", text) if s.strip()]

    def _infer_long_text(
        self, text: str, voice_data=None, ref_audio=None, ref_text=None
    ):
        """Infer long text by chunking."""
        sentences = self._split_text_smart(text)
        full_audio = []
        silence = np.zeros(int(SAMPLE_RATE * 0.3), dtype=np.float32)

        print(f"Processing {len(sentences)} sentences...")
        for i, sentence in enumerate(sentences):
            if len(sentence) < 2:
                continue  # Skip too short sentences

            try:
                result = self.tts.infer(
                    text=sentence,
                    voice=voice_data,
                    ref_audio=ref_audio,
                    ref_text=ref_text,
                )

                # result can be (sr, audio) or just audio depending on version
                chunk = result[1] if isinstance(result, tuple) else result

                if chunk is not None and len(chunk) > 0:
                    chunk = np.array(chunk).flatten().astype(np.float32)
                    full_audio.append(chunk)
                    full_audio.append(silence)
            except Exception as e:
                print(f"Error processing sentence {i+1}: {e}")

        if not full_audio:
            return None

        return np.concatenate(full_audio)

    def _audio_to_bytes(self, audio_array: np.ndarray) -> bytes:
        """Helper to convert numpy audio array to WAV bytes."""
        # Use soundfile to write numpy array to bytes
        with io.BytesIO() as bio:
            sf.write(bio, audio_array, SAMPLE_RATE, format="WAV")
            return bio.getvalue()
