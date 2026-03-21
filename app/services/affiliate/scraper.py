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
        if "shopee" in url.lower():
            results = await self.scrape_shopee(url=url, limit=1)
        elif "tiktok" in url.lower():
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
