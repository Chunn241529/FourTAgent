"""
Voice Agent Service - Parallel audio streaming for chat responses.
Uses vieneu-TTS for Vietnamese text-to-speech with real-time streaming.
"""

import asyncio
import base64
import re
import io
import numpy as np
import soundfile as sf
from typing import AsyncGenerator, Optional, List
from concurrent.futures import ThreadPoolExecutor

try:
    from vieneu import Vieneu
except ImportError:
    Vieneu = None

# Constants
SAMPLE_RATE = 24000
DEFAULT_VOICE = "Doan"  # Default voice as specified by user

# Thread pool for running sync TTS in async context
_executor = ThreadPoolExecutor(max_workers=2)


class VoiceAgentService:
    """Service for parallel voice synthesis in chat responses."""

    _instance = None
    _tts = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._initialize_tts()
        return cls._instance

    @classmethod
    def _initialize_tts(cls):
        """Initialize TTS engine (singleton)."""
        if Vieneu is None:
            print("[VoiceAgent] vieneu not installed. Voice agent disabled.")
            return

        try:
            print("[VoiceAgent] Initializing TTS engine...")
            cls._tts = Vieneu()
            print("[VoiceAgent] TTS engine ready.")
        except Exception as e:
            print(f"[VoiceAgent] Failed to initialize TTS: {e}")
            cls._tts = None

    @property
    def is_available(self) -> bool:
        """Check if TTS engine is available."""
        return self._tts is not None

    def _split_into_sentences(self, text: str) -> List[str]:
        """Split text into sentences for streaming."""
        # Split by sentence endings: . ! ? or newlines
        # Keep sentences that are meaningful (> 2 chars)
        sentences = re.split(r"(?<=[.!?។\n])\s+", text)
        return [s.strip() for s in sentences if len(s.strip()) > 2]

    def _synthesize_sync(
        self, text: str, voice_id: str = DEFAULT_VOICE
    ) -> Optional[bytes]:
        """Synchronous TTS synthesis for a single sentence."""
        if not self._tts:
            return None

        try:
            # Get voice data
            voice_data = None
            try:
                voice_data = self._tts.get_preset_voice(voice_id)
            except Exception:
                # Fall back to default voice
                try:
                    voice_data = self._tts.get_preset_voice(DEFAULT_VOICE)
                except Exception:
                    pass

            # Infer
            result = self._tts.infer(text=text, voice=voice_data)

            # Extract audio array
            audio = result[1] if isinstance(result, tuple) else result
            if audio is None or len(audio) == 0:
                return None

            audio = np.array(audio).flatten().astype(np.float32)

            # Convert to WAV bytes
            with io.BytesIO() as bio:
                sf.write(bio, audio, SAMPLE_RATE, format="WAV")
                return bio.getvalue()

        except Exception as e:
            print(f"[VoiceAgent] Synthesis error: {e}")
            return None

    async def synthesize_sentence_async(
        self, text: str, voice_id: str = DEFAULT_VOICE
    ) -> Optional[bytes]:
        """Async wrapper for single sentence synthesis."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(
            _executor, self._synthesize_sync, text, voice_id
        )

    async def stream_audio_chunks(
        self,
        full_text: str,
        voice_id: str = DEFAULT_VOICE,
    ) -> AsyncGenerator[dict, None]:
        """
        Stream audio chunks sentence by sentence.
        Yields: {"audio": base64_encoded_wav, "sentence": text}
        """
        if not self.is_available:
            return

        sentences = self._split_into_sentences(full_text)

        for sentence in sentences:
            audio_bytes = await self.synthesize_sentence_async(sentence, voice_id)

            if audio_bytes:
                yield {
                    "audio": base64.b64encode(audio_bytes).decode("utf-8"),
                    "sentence": sentence,
                }

    async def synthesize_parallel_with_text(
        self,
        text_generator: AsyncGenerator[str, None],
        voice_id: str = DEFAULT_VOICE,
        buffer_sentences: int = 1,
    ) -> AsyncGenerator[dict, None]:
        """
        Synthesize audio in parallel with text generation.

        This method receives text chunks from LLM and:
        1. Accumulates text until a complete sentence is found
        2. Immediately starts TTS for completed sentences
        3. Yields both text and audio events

        Yields:
            {"type": "text", "content": str}
            {"type": "audio", "audio": base64, "sentence": str}
        """
        if not self.is_available:
            # Just pass through text if TTS not available
            async for text_chunk in text_generator:
                yield {"type": "text", "content": text_chunk}
            return

        text_buffer = ""
        pending_tts_tasks = []
        sentence_pattern = re.compile(r"[.!?។\n]")

        async for text_chunk in text_generator:
            # Yield text immediately
            yield {"type": "text", "content": text_chunk}

            text_buffer += text_chunk

            # Check for complete sentences
            while True:
                match = sentence_pattern.search(text_buffer)
                if not match:
                    break

                # Extract complete sentence
                end_idx = match.end()
                sentence = text_buffer[:end_idx].strip()
                text_buffer = text_buffer[end_idx:].strip()

                if len(sentence) > 2:
                    # Start TTS task in background
                    task = asyncio.create_task(
                        self.synthesize_sentence_async(sentence, voice_id)
                    )
                    pending_tts_tasks.append((task, sentence))

            # Check if any TTS tasks are done
            still_pending = []
            for task, sentence in pending_tts_tasks:
                if task.done():
                    try:
                        audio_bytes = task.result()
                        if audio_bytes:
                            yield {
                                "type": "audio",
                                "audio": base64.b64encode(audio_bytes).decode("utf-8"),
                                "sentence": sentence,
                            }
                    except Exception as e:
                        print(f"[VoiceAgent] TTS task error: {e}")
                else:
                    still_pending.append((task, sentence))
            pending_tts_tasks = still_pending

        # Process remaining buffer
        if text_buffer.strip():
            sentence = text_buffer.strip()
            if len(sentence) > 2:
                audio_bytes = await self.synthesize_sentence_async(sentence, voice_id)
                if audio_bytes:
                    yield {
                        "type": "audio",
                        "audio": base64.b64encode(audio_bytes).decode("utf-8"),
                        "sentence": sentence,
                    }

        # Wait for remaining TTS tasks
        for task, sentence in pending_tts_tasks:
            try:
                audio_bytes = await task
                if audio_bytes:
                    yield {
                        "type": "audio",
                        "audio": base64.b64encode(audio_bytes).decode("utf-8"),
                        "sentence": sentence,
                    }
            except Exception as e:
                print(f"[VoiceAgent] TTS task error: {e}")


# Singleton instance
voice_agent = VoiceAgentService()
