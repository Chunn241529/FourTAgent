import os
import sys

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.services.tts_service import TTSService


def test_tts_service():
    print("Initializing TTSService...")
    try:
        service = TTSService()
    except Exception as e:
        print(f"Failed to initialize service: {e}")
        return

    print("\nTesting list_voices...")
    voices = service.list_voices()
    print(f"Found {len(voices)} voices.")
    for v in voices:
        print(f" - {v['id']}: {v['description']}")

    if not voices:
        print("No voices found. Skipping synthesis test with specific voice.")
        voice_id = None
    else:
        voice_id = voices[0]["id"]

    print(f"\nTesting synthesis with voice_id='{voice_id}'...")
    text = "Xin chào. Hôm nay trời đẹp quá! Bạn có khỏe không? Chúng ta hãy cùng đi chơi nhé."
    audio = service.synthesize(text, voice_id)

    if audio:
        output_file = "test_output.wav"
        with open(output_file, "wb") as f:
            f.write(audio)
        print(f"Synthesis successful. Saved to {output_file}")
        print(f"Audio size: {len(audio)} bytes")
    else:
        print("Synthesis failed.")


if __name__ == "__main__":
    test_tts_service()
