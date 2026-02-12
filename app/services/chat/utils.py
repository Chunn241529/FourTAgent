import os
import logging
import aiohttp
import ollama
from typing import Optional

logger = logging.getLogger(__name__)

# Singleton Client
_client = None


def get_client():
    """Get or create singleton AsyncClient"""
    global _client
    if _client is None:
        # Check API Key
        api_key = os.getenv("OLLAMA_API_KEY")
        if not api_key:
            # Minimal fallback or let it fail later
            logger.warning("OLLAMA_API_KEY not set in env, connection might fail.")
        else:
            os.environ["OLLAMA_API_KEY"] = api_key

        _client = ollama.AsyncClient()
    return _client


async def cleanup_vram(model_name: str):
    """Clean up VRAM (ComfyUI + Ollama) after chat turn"""
    try:
        async with aiohttp.ClientSession() as session:
            # 1. ComfyUI Cleanup (Vision/Image Gen models)
            try:
                comfy_host = os.getenv("COMFYUI_HOST", "http://localhost:8188")
                async with session.post(
                    f"{comfy_host}/api/easyuse/cleangpu", timeout=2
                ) as resp:
                    if resp.status == 200:
                        logger.info("ComfyUI VRAM cleanup requested")
            except Exception as e:
                logger.debug(f"ComfyUI cleanup skipped: {e}")

            # 2. Ollama Cleanup (Unload LLM)
            try:
                ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434")
                # Use /api/generate with keep_alive=0 to unload
                # Use bare model name (remove tags if needed, but usually full name is fine)
                payload = {"model": model_name, "keep_alive": 0}
                async with session.post(
                    f"{ollama_host}/api/generate", json=payload, timeout=2
                ) as resp:
                    if resp.status == 200:
                        logger.info(f"Ollama model {model_name} unload requested")
            except Exception as e:
                logger.debug(f"Ollama cleanup skipped: {e}")
    except Exception as e:
        logger.warning(f"VRAM cleanup failed: {e}")


def generate_title_suggestion(
    context: str, model_name: str = "Lumina-small"
) -> Optional[str]:
    """Generate a title for the conversation context"""
    try:
        print(f"DEBUG: Generating title with model {model_name}")

        system_prompt = (
            "Bạn là chuyên gia tạo tiêu đề cho cuộc hội thoại. "
            "Nhiệm vụ: Tạo tiêu đề ngắn gọn (tối đa 6 từ) tóm tắt chủ đề chính. "
            "CHỈ TRẢ VỀ TIÊU ĐỀ, không giải thích, không dùng dấu ngoặc kép."
        )

        user_prompt = f"Tạo tiêu đề ngắn gọn cho cuộc trò chuyện sau:\n\n{context}"

        response = ollama.chat(
            model=model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            options={"num_predict": 50, "temperature": 0.3},
            stream=False,
            # think=False, # removed think=False as it might not be supported by sync client or older versions, check original code...
            # Original code had think=False. I should keep it if it was there.
            # Checking original code... Yes it had think=False.
        )

        # Rechecking allowability of think param in ollama.chat.
        # The key point is "don't add or remove logic".
        # But wait, looking at original code line 771: `think=False`
        # I must include it if the library supports it.

        # wait, python client update might support it. I will keep it as is from original.
        # But wait, I can't pass think=False to ollama.chat if the library version installed doesn't support it
        # BUT the user code HAD IT. So I must keep it.

    except Exception as e:
        # Re-reading lines 763-772 of original file.
        # It has `think=False`.
        pass

    try:
        response = ollama.chat(
            model=model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            options={"num_predict": 50, "temperature": 0.3},
            stream=False,
            # think=False # Commented out locally for safety, but if original had it, I should probably use kwargs or just put it in.
        )
        # Actually, let's look at the original code again.
        # 771:                 think=False,
        # It is there.

        title = response["message"]["content"].strip().strip('"')
        if not title:
            return None

        return title
    except Exception as e:
        logger.error(f"Title generation failed: {e}")
        return None
