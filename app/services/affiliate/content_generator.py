"""
AI Content Generator for Affiliate Automation.

Uses LLMRouter to generate viral scripts, captions, and hashtags
for product review videos.
"""

import logging
import json
from typing import Optional, Dict, Any, List
from .llm_router import llm_router
from .scraper import ProductData

logger = logging.getLogger(__name__)

# Prompt templates
SYSTEM_PROMPT_VIRAL = """Bạn là chuyên gia KOC (Key Opinion Consumer) hàng đầu TikTok/Shopee Video Việt Nam.
Nhiệm vụ: Tạo kịch bản review sản phẩm cực viral, ngôn ngữ GenZ, dễ hiểu.
Quy tắc:
- Hook mạnh trong 3 giây đầu (gây tò mò, shock nhẹ, đặt câu hỏi)
- Nêu vấn đề → Giới thiệu sản phẩm giải quyết → Kết quả thực tế
- Kết thúc bằng CTA (Call to Action) mạnh: click link, bấm giỏ hàng
- Dùng emoji phù hợp, ngôn ngữ tự nhiên như đang nói chuyện
- Output bằng tiếng Việt
"""

SCRIPT_PROMPT_TEMPLATE = """Viết kịch bản review ngắn {duration} cho sản phẩm sau:

📦 Tên: {name}
💰 Giá: {price:,.0f}đ {discount_info}
⭐ Rating: {rating}
🛒 Đã bán: {sold_count}
📝 Mô tả: {description}

Yêu cầu:
- Style: {style}
- Kịch bản gồm: [HOOK] [NỘI DUNG] [CTA]
- Output JSON format:
{{
  "hook": "câu hook 3 giây đầu",
  "body": "nội dung chính",
  "cta": "kêu gọi hành động",
  "full_script": "kịch bản đầy đủ để đọc",
  "caption": "caption đăng kèm video",
  "hashtags": ["#hashtag1", "#hashtag2", ...]
}}
"""


class ContentGenerator:
    """
    Generate viral affiliate content using multi-LLM fallback.

    Usage:
        gen = ContentGenerator()
        result = await gen.generate_script(product_data, style="genz")
    """

    STYLES = {
        "genz": "GenZ trẻ trung, hài hước, dùng tiếng lóng",
        "formal": "Chuyên nghiệp, đáng tin cậy, review chi tiết",
        "storytelling": "Kể chuyện, chia sẻ trải nghiệm cá nhân",
        "comparison": "So sánh với sản phẩm khác, phân tích ưu nhược",
    }

    DURATIONS = {
        "15s": "15 giây (khoảng 40-50 từ)",
        "30s": "30 giây (khoảng 80-100 từ)",
        "60s": "60 giây (khoảng 150-180 từ)",
    }

    async def generate_script(
        self,
        product: ProductData,
        style: str = "genz",
        duration: str = "30s",
        custom_prompt: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Generate a viral review script for a product.

        Args:
            product: Product data from scraper
            style: Script style (genz, formal, storytelling, comparison)
            duration: Target video duration (15s, 30s, 60s)
            custom_prompt: Optional custom instructions

        Returns:
            {
                "script": { hook, body, cta, full_script, caption, hashtags },
                "provider": "which LLM was used",
                "model": "model name",
                "error": None or error message
            }
        """
        style_desc = self.STYLES.get(style, self.STYLES["genz"])
        duration_desc = self.DURATIONS.get(duration, self.DURATIONS["30s"])

        # Build discount info string
        discount_info = ""
        if product.original_price and product.discount_percent:
            discount_info = f"(giảm {product.discount_percent:.0f}% từ {product.original_price:,.0f}đ)"

        prompt = SCRIPT_PROMPT_TEMPLATE.format(
            duration=duration_desc,
            name=product.name,
            price=product.price,
            discount_info=discount_info,
            rating=product.rating or "N/A",
            sold_count=product.sold_count or "N/A",
            description=product.description or "Không có mô tả",
            style=style_desc,
        )

        if custom_prompt:
            prompt += f"\n\nYêu cầu bổ sung: {custom_prompt}"

        result = await llm_router.generate(
            prompt=prompt,
            system_prompt=SYSTEM_PROMPT_VIRAL,
            temperature=0.85,
            max_tokens=1500,
        )

        # Parse JSON from LLM response
        script_data = None
        if result["text"]:
            script_data = self._parse_script_json(result["text"])

        return {
            "script": script_data,
            "provider": result["provider"],
            "model": result["model"],
            "error": result["error"],
            "raw_text": result["text"],
        }

    async def generate_caption(
        self,
        product: ProductData,
        platform: str = "tiktok",
    ) -> Dict[str, Any]:
        """Generate optimized caption + hashtags for a specific platform."""
        prompt = f"""Viết caption {platform} viral cho sản phẩm "{product.name}" giá {product.price:,.0f}đ.
Yêu cầu:
- Ngắn gọn, gây tò mò
- Kèm emoji
- 5-8 hashtags phù hợp trending
Output JSON: {{"caption": "...", "hashtags": [...]}}"""

        result = await llm_router.generate(
            prompt=prompt,
            system_prompt="Bạn là chuyên gia content TikTok/Shopee Việt Nam.",
            temperature=0.9,
            max_tokens=500,
        )

        parsed = None
        if result["text"]:
            parsed = self._parse_script_json(result["text"])

        return {
            "data": parsed,
            "provider": result["provider"],
            "error": result["error"],
        }

    def _parse_script_json(self, text: str) -> Optional[Dict]:
        """Try to parse JSON from LLM response, handling common issues."""
        # Try direct parse
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Try extracting JSON block from markdown code fence
        import re
        json_match = re.search(r'```(?:json)?\s*\n?(.*?)\n?```', text, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group(1))
            except json.JSONDecodeError:
                pass

        # Try finding JSON object in text
        brace_start = text.find('{')
        brace_end = text.rfind('}')
        if brace_start != -1 and brace_end != -1:
            try:
                return json.loads(text[brace_start:brace_end + 1])
            except json.JSONDecodeError:
                pass

        # Return raw text as fallback
        logger.warning("[ContentGenerator] Failed to parse JSON from LLM response")
        return {"full_script": text, "raw": True}
