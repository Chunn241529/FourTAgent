"""
Affiliate Automation Service Package.

Modules:
- llm_router: Multi-provider LLM fallback routing (Groq, Gemini, Cerebras, Cohere, Ollama)
- scraper: Product data mining from Shopee/TikTok
- content_generator: AI-powered script/caption generation
- media_engine: Video assembly (MoviePy/FFmpeg)
- smart_reup: ComfyUI-based video transformation for anti-detection
"""

from .llm_router import LLMRouter
from .scraper import ProductScraper
from .content_generator import ContentGenerator
from .media_engine import MediaEngine
from .smart_reup import SmartReupService
