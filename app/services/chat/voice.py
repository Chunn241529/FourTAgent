import logging
import random
from typing import List, Tuple

logger = logging.getLogger(__name__)

# Cache for voice fillers: {(text, voice_id): audio_bytes}
_filler_cache = {}

# Track last used filler index to avoid repetition
_last_filler_index = -1

# List of filler phrases to rotate
FILLER_PHRASES = [
    "Ok, được rồi, đợi em chút nhé",
    "Được rồi, đợi em chút nhé",
    "Đợi em một chút nhé",
]


def get_random_filler() -> str:
    """Get a random filler that's different from the last one used"""
    global _last_filler_index

    if len(FILLER_PHRASES) <= 1:
        return FILLER_PHRASES[0] if FILLER_PHRASES else ""

    # Get available indices (excluding the last used one)
    available_indices = [
        i for i in range(len(FILLER_PHRASES)) if i != _last_filler_index
    ]

    # Pick a random index from available ones
    new_index = random.choice(available_indices)
    _last_filler_index = new_index

    return FILLER_PHRASES[new_index]


async def warmup_fillers():
    """Pre-generate fillers for all voices to avoid latency"""
    from app.services.tts_service import tts_service

    logger.info("Starting filler warmup...")

    try:
        voices = tts_service.list_voices()

        # Loop through all available voices
        for voice in voices:
            voice_id = voice["id"]

            # Loop through all filler phrases
            for filler_text in FILLER_PHRASES:
                cache_key = (filler_text, voice_id)

                # Check if already cached
                if cache_key not in _filler_cache:
                    try:
                        # logger.info(f"Warming up filler '{filler_text}' for voice: {voice_id}")
                        audio = tts_service.synthesize(filler_text, voice_id=voice_id)
                        if audio:
                            _filler_cache[cache_key] = audio
                    except Exception as e:
                        logger.warning(f"Failed to warmup voice {voice_id}: {e}")

        logger.info(f"Filler warmup complete. Cached {len(_filler_cache)} items.")

    except Exception as e:
        logger.error(f"Warmup process failed: {e}")
