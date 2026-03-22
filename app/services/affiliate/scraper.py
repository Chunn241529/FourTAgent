"""
Product Data Mining / Scraper for Affiliate Automation.

Scrapes trending products from Shopee and TikTok Shop using
Playwright (headless browser) or direct API calls.
"""

import os
import logging
import hashlib
import json
import time
import tempfile
from typing import List, Optional, Dict, Any
from dataclasses import dataclass, field, asdict

logger = logging.getLogger(__name__)

# Storage path for scraped data
SCRAPER_STORAGE = os.path.join("storage", "affiliate", "products")


@dataclass
class ProductData:
    """Standardized product data structure."""
    product_id: str
    platform: str  # "shopee" | "tiktok"
    name: str
    price: float
    original_price: Optional[float] = None
    discount_percent: Optional[float] = None
    rating: Optional[float] = None
    sold_count: Optional[int] = None
    commission_rate: Optional[float] = None
    image_urls: List[str] = field(default_factory=list)
    video_urls: List[str] = field(default_factory=list)
    affiliate_link: Optional[str] = None
    description: Optional[str] = None
    shop_name: Optional[str] = None
    category: Optional[str] = None
    scraped_at: float = field(default_factory=time.time)

    @property
    def hash_id(self) -> str:
        """Unique hash for deduplication."""
        raw = f"{self.platform}:{self.product_id}"
        return hashlib.md5(raw.encode()).hexdigest()

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class ProductScraper:
    """
    Product scraper with support for multiple platforms.

    Usage:
        scraper = ProductScraper()
        products = await scraper.scrape_shopee(keyword="áo thun nam", limit=10)
    """

    def __init__(self):
        self.storage_dir = SCRAPER_STORAGE
        os.makedirs(self.storage_dir, exist_ok=True)
        self._scraped_hashes = self._load_scraped_hashes()

    def _load_scraped_hashes(self) -> set:
        """Load previously scraped product hashes to avoid duplicates."""
        hash_file = os.path.join(self.storage_dir, "scraped_hashes.json")
        if os.path.exists(hash_file):
            try:
                with open(hash_file, "r") as f:
                    return set(json.load(f))
            except Exception:
                return set()
        return set()

    def _save_scraped_hashes(self):
        """Persist scraped hashes to disk."""
        hash_file = os.path.join(self.storage_dir, "scraped_hashes.json")
        with open(hash_file, "w") as f:
            json.dump(list(self._scraped_hashes), f)

    def is_duplicate(self, product: ProductData) -> bool:
        """Check if a product has already been scraped."""
        return product.hash_id in self._scraped_hashes

    def mark_scraped(self, product: ProductData):
        """Mark a product as scraped."""
        self._scraped_hashes.add(product.hash_id)
        self._save_scraped_hashes()

    async def _get_playwright_scraper(self):
        """Lazy-init Playwright scraper."""
        if not hasattr(self, '_pw_scraper') or self._pw_scraper is None:
            from .playwright_scraper import PlaywrightScraper
            proxy = os.getenv("SCRAPER_PROXY", None)
            self._pw_scraper = PlaywrightScraper(proxy=proxy, headless=True)
        return self._pw_scraper

    async def scrape_shopee(
        self,
        keyword: Optional[str] = None,
        url: Optional[str] = None,
        limit: int = 10,
        min_rating: float = 4.5,
        min_commission: float = 5.0,
    ) -> List[ProductData]:
        """
        Scrape products from Shopee using Playwright.

        Args:
            keyword: Search keyword (e.g., "áo thun nam")
            url: Direct product/category URL
            limit: Max number of products to return
            min_rating: Minimum product rating filter
            min_commission: Minimum affiliate commission % filter

        Returns:
            List of ProductData objects
        """
        logger.info(f"[Scraper] Shopee scrape: keyword={keyword}, url={url}, limit={limit}")
        products = []

        try:
            pw = await self._get_playwright_scraper()

            if url:
                raw = await pw.scrape_shopee_url(url)
                if raw:
                    products.append(self._raw_to_product(raw))
            elif keyword:
                raw_list = await pw.scrape_shopee_search(keyword, limit=limit)
                for raw in raw_list:
                    p = self._raw_to_product(raw)
                    # Apply filters
                    if min_rating and p.rating and p.rating < min_rating:
                        continue
                    if not self.is_duplicate(p):
                        products.append(p)

        except Exception as e:
            logger.error(f"[Scraper] Shopee scrape failed: {e}", exc_info=True)

        return products[:limit]

    async def scrape_tiktok(
        self,
        keyword: Optional[str] = None,
        url: Optional[str] = None,
        limit: int = 10,
    ) -> List[ProductData]:
        """
        Scrape trending products from TikTok Shop using Playwright.

        Args:
            keyword: Search keyword
            url: Direct product URL
            limit: Max number of products

        Returns:
            List of ProductData objects
        """
        logger.info(f"[Scraper] TikTok scrape: keyword={keyword}, url={url}, limit={limit}")
        products = []

        try:
            pw = await self._get_playwright_scraper()

            if keyword:
                raw_list = await pw.scrape_tiktok_search(keyword, limit=limit)
                for raw in raw_list:
                    p = self._raw_to_product(raw)
                    if not self.is_duplicate(p):
                        products.append(p)

        except Exception as e:
            logger.error(f"[Scraper] TikTok scrape failed: {e}", exc_info=True)

        return products[:limit]

    def _raw_to_product(self, raw: Dict[str, Any]) -> ProductData:
        """Convert raw scraped dict into ProductData."""
        return ProductData(
            product_id=str(raw.get("product_id", "")),
            platform=raw.get("platform", "unknown"),
            name=raw.get("name", ""),
            price=float(raw.get("price", 0)),
            original_price=raw.get("original_price"),
            discount_percent=raw.get("discount_percent"),
            rating=raw.get("rating"),
            sold_count=raw.get("sold_count"),
            commission_rate=raw.get("commission_rate"),
            image_urls=raw.get("image_urls", []),
            video_urls=raw.get("video_urls", []),
            affiliate_link=raw.get("affiliate_link", ""),
            description=raw.get("description", ""),
            shop_name=raw.get("shop_name", ""),
            category=raw.get("category"),
        )

    async def scrape_by_url(self, url: str) -> Optional[ProductData]:
        """
        Scrape a single product by its URL.
        Auto-detects platform (Shopee/TikTok).
        """
        if "shopee.vn" in url.lower():
            results = await self.scrape_shopee(url=url, limit=1)
        elif "tiktok.com" in url.lower():
            results = await self.scrape_tiktok(url=url, limit=1)
        else:
            logger.warning(f"[Scraper] Unknown platform for URL: {url}")
            return None

        return results[0] if results else None

    def save_product(self, product: ProductData) -> str:
        """Save product data to local storage. Returns file path."""
        product_dir = os.path.join(self.storage_dir, product.hash_id)
        os.makedirs(product_dir, exist_ok=True)

        data_file = os.path.join(product_dir, "product.json")
        with open(data_file, "w", encoding="utf-8") as f:
            json.dump(product.to_dict(), f, ensure_ascii=False, indent=2)

        self.mark_scraped(product)
        return product_dir

    def list_saved_products(self) -> List[Dict[str, Any]]:
        """List all saved products."""
        products = []
        for hash_id in os.listdir(self.storage_dir):
            data_file = os.path.join(self.storage_dir, hash_id, "product.json")
            if os.path.isfile(data_file):
                try:
                    with open(data_file, "r", encoding="utf-8") as f:
                        products.append(json.load(f))
                except Exception:
                    continue
        return products

    def delete_saved_product(self, platform: str, product_id: str) -> bool:
        """Completely deletes a saved product from disk."""
        import shutil
        import hashlib
        raw = f"{platform}:{product_id}"
        hash_id = hashlib.md5(raw.encode()).hexdigest()
        
        product_dir = os.path.join(self.storage_dir, hash_id)
        if os.path.exists(product_dir):
            try:
                shutil.rmtree(product_dir)
                # optionally also strip from scraped_hashes
                if hash_id in self._scraped_hashes:
                    self._scraped_hashes.remove(hash_id)
                    self._save_scraped_hashes()
                return True
            except Exception as e:
                logger.error(f"[Scraper] Error deleting product {hash_id}: {e}")
                return False
        return False

    async def scrape_generic_video(self, url: str, max_retries: int = 3) -> Optional[ProductData]:
        """
        Scrape a generic video link (Douyin, Facebook, YouTube, TikTok, Kwai, etc.) using yt-dlp.
        Returns a pseudo-ProductData intended for pure video re-upping/remixing.

        Args:
            url: Direct video URL from Douyin, TikTok, YouTube, Facebook, etc.
            max_retries: Number of retry attempts with exponential backoff
        """
        import re
        # Normalize Douyin modal URLs to standard video URLs for yt-dlp
        url = re.sub(r'douyin\.com/.*?modal_id=(\d+)', r'douyin.com/video/\1', url)
        logger.info(f"[Scraper] Generic Video scrape: url={url}, max_retries={max_retries}")

        # Check if this is a Douyin/TikTok URL that needs cookies
        needs_cookies = "douyin" in url.lower() or "tiktok" in url.lower()
        cookies_for_yt_dlp = None

        # If Douyin/TikTok, first get cookies via Playwright
        if needs_cookies:
            try:
                pw = await self._get_playwright_scraper()
                cookie_result = await pw.scrape_douyin_with_cookies(url, timeout=20.0)
                if cookie_result and cookie_result.get('cookies'):
                    cookies_for_yt_dlp = cookie_result.get('cookies')
                    logger.info(f"[Scraper] Got {len(cookies_for_yt_dlp)} cookies from Playwright for {url}")
            except Exception as e:
                logger.warning(f"[Scraper] Failed to get cookies via Playwright: {e}")

        # Try yt-dlp with retry logic
        for attempt in range(max_retries):
            try:
                info = await self._yt_dlp_extract(url, cookies=cookies_for_yt_dlp)
                if info:
                    return self._build_product_data(info, url)
                logger.warning(f"[Scraper] yt-dlp attempt {attempt + 1}/{max_retries} returned empty info")
            except Exception as e:
                logger.warning(f"[Scraper] yt-dlp attempt {attempt + 1}/{max_retries} failed: {e}")

            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # exponential backoff: 1s, 2s, 4s
                logger.info(f"[Scraper] Retrying in {wait_time}s...")
                import asyncio
                await asyncio.sleep(wait_time)

        # All yt-dlp attempts failed → Playwright fallback with extended timeout
        logger.warning(f"[Scraper] All yt-dlp attempts failed. Trying Playwright fallback for {url}")
        try:
            pw = await self._get_playwright_scraper()
            fallback_data = await pw.scrape_generic_fallback(url, timeout=15.0)

            title = fallback_data.get("title", 'Unknown Video')
            video_url = fallback_data.get("video_url", url)
            watermark_removed = fallback_data.get("watermark_removed", False)

            return ProductData(
                product_id=f"generic_{str(hash(url))[:8]}",
                platform="generic",
                name=title,
                price=0.0,
                image_urls=[],
                video_urls=[video_url],
                affiliate_link=url,
                description='',
                shop_name="Unknown",
            )
        except Exception as inner_e:
            logger.error(f"[Scraper] Playwright fallback failed: {inner_e}")
            return None

    async def _yt_dlp_extract(self, url: str, cookies: Optional[List[Dict]] = None) -> Optional[Dict[str, Any]]:
        """Extract video info using yt-dlp with proper config."""
        cookie_file = None

        def _extract():
            import yt_dlp
            nonlocal cookie_file
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,  # FIXED: was 'in_playlist' which skips URL extraction
                'skip_download': True,
                # Better headers to avoid 403s
                'http_headers': {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
                    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                    'Accept-Language': 'en-US,en;q=0.5',
                },
                # Preferred formats: direct video URL first, then best MP4
                'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
            }

            # Pass cookies if provided (for Douyin/TikTok)
            if cookies:
                cookie_file = tempfile.mktemp(suffix='.txt')
                self._write_netscape_cookies(cookies, cookie_file)
                ydl_opts['cookiefile'] = cookie_file

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                return ydl.extract_info(url, download=False)

        try:
            import asyncio
            result = await asyncio.to_thread(_extract)
            return result
        finally:
            # Clean up temp cookie file
            if cookie_file and os.path.exists(cookie_file):
                try:
                    os.unlink(cookie_file)
                except Exception:
                    pass

    def _write_netscape_cookies(self, cookies: List[Dict], path: str):
        """Write cookies in Netscape format for yt-dlp."""
        with open(path, 'w') as f:
            f.write("# Netscape HTTP Cookie File\n")
            f.write("# This file was generated by Playwright Scraper\n\n")
            for c in cookies:
                domain = c.get('domain', '')
                name = c.get('name', '')
                value = c.get('value', '')
                c_path = c.get('path', '/')
                secure = 'TRUE' if c.get('secure') else 'FALSE'
                expiry = str(int(c.get('expires', 0)))
                # Domain should start with dot for Netscape format
                if not domain.startswith('.') and domain != 'localhost':
                    domain = '.' + domain
                f.write(f"{domain}\tTRUE\t{c_path}\t{secure}\t{expiry}\t{name}\t{value}\n")

    def _build_product_data(self, info: Dict[str, Any], original_url: str) -> Optional[ProductData]:
        """Build ProductData from yt-dlp extracted info."""
        try:
            # If playlist/user profile, take the first entry
            if 'entries' in info and info['entries']:
                info = info['entries'][0]

            title = info.get('title', 'Unknown Video')
            video_url = info.get('url')  # direct playing url

            # Some platforms don't expose direct 'url' if formats are there
            if not video_url and info.get('formats'):
                # Get best format with video
                best_fmt = next(
                    (f for f in reversed(info['formats']) if f.get('vcodec') != 'none'),
                    None
                )
                if best_fmt:
                    video_url = best_fmt.get('url')

            if not video_url:
                logger.warning(f"[Scraper] Could not find direct video URL for {original_url}")
                return None

            thumb = info.get('thumbnail') or ""
            uploader = info.get('uploader') or info.get('channel') or "Unknown"
            video_id = info.get('id', str(hash(original_url))[:8])

            return ProductData(
                product_id=f"generic_{video_id}",
                platform="generic",
                name=f"{title} ({uploader})",
                price=0.0,
                image_urls=[thumb] if thumb else [],
                video_urls=[video_url],
                affiliate_link=original_url,
                description=info.get('description', ''),
                shop_name=uploader,
            )
        except Exception as e:
            logger.error(f"[Scraper] Failed to build product data: {e}")
            return None
