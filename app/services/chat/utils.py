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
    """Generate a title for the conversation context (with cloud fallback)"""
    # Try Ollama first
    try:
        logger.info(f"Generating title with Ollama model {model_name}")

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
            options={"num_predict": 150, "temperature": 0.3},
            stream=False,
            think=False,
        )

        if "message" not in response or "content" not in response["message"]:
            logger.error(f"Invalid Ollama response format: {response}")
            raise Exception("Invalid Ollama response")

        title = response["message"]["content"].strip().strip('"')
        if not title:
            logger.warning("Ollama returned empty title")
            raise Exception("Empty title from Ollama")

        return title

    except Exception as e:
        logger.warning(f"Title generation with Ollama failed: {e}, trying cloud fallback...")
        return _generate_title_cloud_fallback(context)


def _generate_title_cloud_fallback(context: str) -> Optional[str]:
    """Fallback title generation using cloud LLM providers."""
    import asyncio

    system_prompt = (
        "Bạn là chuyên gia tạo tiêu đề cho cuộc hội thoại. "
        "Nhiệm vụ: Tạo tiêu đề ngắn gọn (tối đa 6 từ) tóm tắt chủ đề chính. "
        "CHỈ TRẢ VỀ TIÊU ĐỀ, không giải thích, không dùng dấu ngoặc kép."
    )
    user_prompt = f"Tạo tiêu đề ngắn gọn cho cuộc trò chuyện sau:\n\n{context}"

    try:
        from app.services.chat.chat_llm_router import chat_llm_router

        # Run async generate_simple in a new event loop
        # (safe because this function is called from asyncio.to_thread)
        loop = asyncio.new_event_loop()
        try:
            title = loop.run_until_complete(
                chat_llm_router.generate_simple(
                    prompt=user_prompt,
                    system_prompt=system_prompt,
                    temperature=0.3,
                    max_tokens=50,
                )
            )
        finally:
            loop.close()

        if title:
            title = title.strip().strip('"')
            logger.info(f"Title generated via cloud fallback: {title}")
            return title

    except Exception as e:
        logger.error(f"Cloud fallback title generation also failed: {e}")

    return None

