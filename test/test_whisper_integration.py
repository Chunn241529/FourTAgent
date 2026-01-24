import os
import sys
import shutil

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.services.tts_service import TTSService


def test_whisper_integration():
    print("Initializing TTSService (should load Whisper)...")
    try:
        service = TTSService()
    except Exception as e:
        print(f"Failed to init: {e}")
        return

    if not service.asr_model:
        print("Error: Whisper model not loaded!")
        return
    else:
        print("Whisper model loaded successfully.")

    user_id = 999
    voice_name = "Whisper Test Voice"

    # Clean up
    storage_dir = f"storage/voices/{user_id}"
    if os.path.exists(storage_dir):
        shutil.rmtree(storage_dir)

    print("\n1. Creating custom voice (Auto Transcribe)...")

    # We need a valid WAV file with speech to test transcription properly.
    # 'test_output.wav' from previous TTS test contains "Xin chào..."
    dummy_audio_path = "test_output.wav"
    if not os.path.exists(dummy_audio_path):
        print("Error: test_output.wav not found. Please run test_tts.py first.")
        # Try to synthesize via service if possible?
        # service.synthesize("Xin chào tôi là test", voice_id=service.list_voices()[0]['id']) ... but circular dep if we init service here.
        return

    with open(dummy_audio_path, "rb") as f:
        audio_bytes = f.read()

    voice_meta = service.create_custom_voice(user_id, voice_name, audio_bytes)

    if voice_meta:
        print(f"Created voice: {voice_meta['id']}")
        print(f"Ref Text: '{voice_meta.get('ref_text')}'")

        if voice_meta.get("ref_text"):
            print("SUCCESS: Reference text was generated!")
        else:
            print("FAILURE: Reference text is empty.")
    else:
        print("Failed to create voice.")
        return

    print("\n2. Synthesizing using generated ref_text...")
    # This verifies that synthesize picks up the ref_text from metadata
    try:
        audio = service.synthesize(
            "Test synthesis with whisper ref",
            voice_id=voice_meta["id"],
            user_id=user_id,
        )
        if audio:
            print(f"Synthesis successful. Audio size: {len(audio)} bytes")
        else:
            print("Synthesis failed.")
    except Exception as e:
        print(f"Synthesis threw exception: {e}")


if __name__ == "__main__":
    test_whisper_integration()
