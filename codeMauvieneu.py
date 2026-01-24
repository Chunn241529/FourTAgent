# @title 🧠 2. Khởi tạo Engine (Tự sửa lỗi thiếu thư viện)
import os
import sys
import subprocess
import warnings
import numpy as np
import re
import soundfile as sf
from IPython.display import Audio, display, clear_output
from google.colab import files
from pydub import AudioSegment

# --- TỰ ĐỘNG SỬA LỖI THIẾU THƯ VIỆN ---
try:
    import whisper
except ImportError:
    print("🔧 Đang cài đặt openai-whisper (mất khoảng 20s)...")
    # Cài đặt im lặng
    subprocess.run("pip install openai-whisper numpy<2.0", shell=True)
    # Reload lại module
    import site
    site.main()
    import whisper
    print("✅ Đã cài xong Whisper!")

from vieneu import Vieneu

# Tắt warning
warnings.filterwarnings("ignore")
SAMPLE_RATE = 24000

print("⏳ Đang khởi tạo model TTS & Whisper...")
try:
    # 1. Load TTS
    if 'tts' not in globals():
        tts = Vieneu()

    # 2. Load Whisper
    if 'asr_model' not in globals():
        print("   ...Đang tải Whisper AI (để tự nghe giọng)...")
        asr_model = whisper.load_model("base")

    print(f"✅ Hệ thống sẵn sàng (TTS + Whisper Auto)")
except Exception as e:
    print(f"❌ Lỗi load model: {e}")

# --- Các hàm xử lý (Giữ nguyên) ---
def split_text_smart(text):
    return [s.strip() for s in re.split(r'(?<=[.!?\n])\s+', text) if s.strip()]

def infer_long_text(text, voice_data=None, ref_audio=None, ref_text=None):
    sentences = split_text_smart(text)
    full_audio = []
    silence = np.zeros(int(SAMPLE_RATE * 0.3), dtype=np.float32)

    print(f"🔄 Đang xử lý {len(sentences)} câu...")
    for i, sentence in enumerate(sentences):
        if len(sentence) < 2: continue
        print(f"   Reading ({i+1}/{len(sentences)}): {sentence[:30]}...")
        try:
            result = tts.infer(sentence, voice=voice_data, ref_audio=ref_audio, ref_text=ref_text)
            chunk = result[1] if isinstance(result, tuple) else result

            if chunk is not None and len(chunk) > 0:
                chunk = np.array(chunk).flatten().astype(np.float32)
                full_audio.append(chunk)
                full_audio.append(silence)
        except Exception as e:
            print(f"⚠️ Lỗi câu {i+1}: {e}")

    if not full_audio: return None
    return np.concatenate(full_audio)

# --- Wrapper Functions ---
def run_preset(text, voice_index):
    voices = tts.list_preset_voices()
    if voice_index < 0 or voice_index >= len(voices): voice_index = 0
    desc, name = voices[voice_index]
    print(f"🎙️ Giọng: {desc}")

    audio_data = infer_long_text(text, voice_data=tts.get_preset_voice(name))
    if audio_data is not None:
        sf.write("output_preset.wav", audio_data, SAMPLE_RATE)
        display(Audio("output_preset.wav", autoplay=True))

def run_clone_auto(text):
    print("\n📂 Upload file giọng mẫu...")
    uploaded = files.upload()
    if not uploaded: return
    filename = list(uploaded.keys())[0]

    do_cut = input("✂️ Cắt file? (y/n): ").lower()
    final_ref = filename
    if do_cut == 'y':
        try:
            s = float(input("Start (s): "))
            e = float(input("End (s): "))
            audio = AudioSegment.from_file(filename)
            extract = audio[s*1000:e*1000]
            extract.export("ref_sample.wav", format="wav")
            final_ref = "ref_sample.wav"
        except: pass

    print("🎧 AI đang nghe file mẫu...")
    try:
        # Tự động transcribe
        result = asr_model.transcribe(final_ref, language='vi')
        detected_text = result['text'].strip()
        print(f"📝 AI nghe được: \"{detected_text}\"")
        if not detected_text: detected_text = "Xin chào tôi là người việt nam"
    except Exception as e:
        print(f"⚠️ Lỗi Whisper: {e}. Dùng text mặc định.")
        detected_text = "Xin chào"

    audio_data = infer_long_text(text, ref_audio=final_ref, ref_text=detected_text)

    if audio_data is not None:
        sf.write("output_clone.wav", audio_data, SAMPLE_RATE)
        display(Audio("output_clone.wav", autoplay=True))
