"""
Playwright-based scraper implementation for Shopee and TikTok.

Handles actual browser automation for scraping product data
from e-commerce platforms. Supports proxy rotation.
"""

import os
import re
import json
import asyncio
import logging
import random
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)


class PlaywrightScraper:
    """
    Browser automation scraper using Playwright.

    Supports:
    - Shopee product search & detail pages
    - TikTok Shop product search & detail pages
    - Proxy rotation for anti-bot evasion
    """

    def __init__(self, proxy: Optional[str] = None, headless: bool = True):
        """
        Args:
            proxy: Proxy URL (e.g., "http://user:pass@host:port")
            headless: Run browser in headless mode
        """
        self.proxy = proxy
        self.headless = headless
        self._browser = None
        self._context = None

    async def _ensure_browser(self):
        """Lazily initialize Playwright browser."""
        if self._browser is not None:
            return

        try:
            from playwright.async_api import async_playwright
            self._playwright = await async_playwright().start()

            launch_args = {
                "headless": self.headless,
                "args": [
                    "--disable-blink-features=AutomationControlled",
                    "--no-sandbox",
                ],
            }

            if self.proxy:
                launch_args["proxy"] = {"server": self.proxy}

            self._browser = await self._playwright.chromium.launch(**launch_args)

            # Create context with realistic viewport and user agent
            self._context = await self._browser.new_context(
                viewport={"width": 1366, "height": 768},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36"
                ),
                locale="vi-VN",
            )

            # Inject stealth scripts to bypass bot detection
            await self._context.add_init_script("""
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                Object.defineProperty(navigator, 'languages', { get: () => ['vi-VN', 'vi', 'en-US', 'en'] });
                window.chrome = { runtime: {} };
            """)

            logger.info("[PlaywrightScraper] Browser initialized")

        except ImportError:
            raise RuntimeError(
                "Playwright not installed. Run:\n"
                "  pip install playwright\n"
                "  playwright install chromium"
            )

    async def close(self):
        """Close browser and cleanup."""
        if self._browser:
            await self._browser.close()
            self._browser = None
        if hasattr(self, '_playwright') and self._playwright:
            await self._playwright.stop()

    # ─── SHOPEE ────────────────────────────────────────────

    async def scrape_shopee_search(
        self,
        keyword: str,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        """
        Search and scrape products from Shopee.

        Args:
            keyword: Search keyword
            limit: Max number of products to return

        Returns:
            List of raw product data dicts
        """
        await self._ensure_browser()
        page = await self._context.new_page()
        products = []

        try:
            search_url = f"https://shopee.vn/search?keyword={keyword}"
            logger.info(f"[Shopee] Navigating to: {search_url}")

            await page.goto(search_url, wait_until="networkidle", timeout=30000)

            # Wait for product grid to load
            await page.wait_for_selector(
                "[data-sqe='item'],.shopee-search-item-result__item",
                timeout=15000,
            )

            # Random delay to mimic human behavior
            await asyncio.sleep(random.uniform(1.5, 3.0))

            # Scroll down to trigger lazy-load
            for _ in range(3):
                await page.evaluate("window.scrollBy(0, 800)")
                await asyncio.sleep(random.uniform(0.5, 1.0))

            # Extract product cards via JavaScript
            raw_products = await page.evaluate("""() => {
                const items = document.querySelectorAll('[data-sqe="item"], .shopee-search-item-result__item');
                const results = [];
                items.forEach(item => {
                    try {
                        const nameEl = item.querySelector('.ie3A\\\\+n, .Cve6sh, [data-sqe="name"]');
                        const priceEl = item.querySelector('.ZEgDH9, .vioxXd, [class*="price"]');
                        const imgEl = item.querySelector('img');
                        const linkEl = item.querySelector('a');
                        const soldEl = item.querySelector('.OwmBnn, [class*="sold"]');
                        const ratingEl = item.querySelector('[class*="rating"]');

                        if (nameEl) {
                            results.push({
                                name: nameEl.innerText.trim(),
                                price_text: priceEl ? priceEl.innerText.trim() : '',
                                image_url: imgEl ? (imgEl.src || imgEl.dataset.src) : '',
                                link: linkEl ? linkEl.href : '',
                                sold_text: soldEl ? soldEl.innerText.trim() : '',
                                rating_text: ratingEl ? ratingEl.innerText.trim() : '',
                            });
                        }
                    } catch(e) {}
                });
                return results;
            }""")

            # Parse and normalize data
            for i, raw in enumerate(raw_products[:limit]):
                product = self._parse_shopee_product(raw, i)
                if product:
                    products.append(product)

            logger.info(f"[Shopee] Found {len(products)} products for '{keyword}'")

        except Exception as e:
            logger.error(f"[Shopee] Scrape error: {e}", exc_info=True)
        finally:
            await page.close()

        return products

    async def scrape_shopee_url(self, url: str) -> Optional[Dict[str, Any]]:
        """Scrape a single product from its Shopee URL."""
        await self._ensure_browser()
        page = await self._context.new_page()

        try:
            await page.goto(url, wait_until="networkidle", timeout=30000)
            await asyncio.sleep(random.uniform(2.0, 4.0))

            # Extract product detail
            data = await page.evaluate("""() => {
                const name = document.querySelector('[class*="product-title"], .qaNIZv, h1')?.innerText?.trim();
                const priceEl = document.querySelector('[class*="pqTWkA"], [class*="price"]');
                const images = [...document.querySelectorAll('.ZPN9uB img, [class*="product-image"] img')].map(i => i.src || i.dataset.src).filter(Boolean);
                const ratingEl = document.querySelector('[class*="rating"]');
                const soldEl = document.querySelector('[class*="sold"]');
                const descEl = document.querySelector('.f7AU53, [class*="product-detail"]');
                const shopEl = document.querySelector('.eiMwuU, [class*="shop-name"]');

                return {
                    name: name || '',
                    price_text: priceEl ? priceEl.innerText.trim() : '',
                    image_urls: images,
                    rating_text: ratingEl ? ratingEl.innerText.trim() : '',
                    sold_text: soldEl ? soldEl.innerText.trim() : '',
                    description: descEl ? descEl.innerText.substring(0, 500) : '',
                    shop_name: shopEl ? shopEl.innerText.trim() : '',
                };
            }""")

            if data and data.get("name"):
                # Extract item ID from URL
                item_match = re.search(r'i\.(\d+)\.(\d+)', url)
                item_id = f"{item_match.group(1)}_{item_match.group(2)}" if item_match else str(hash(url))

                return {
                    "product_id": item_id,
                    "platform": "shopee",
                    "name": data["name"],
                    "price": self._parse_price(data.get("price_text", "")),
                    "image_urls": data.get("image_urls", []),
                    "rating": self._parse_float(data.get("rating_text", "")),
                    "sold_count": self._parse_sold(data.get("sold_text", "")),
                    "description": data.get("description", ""),
                    "shop_name": data.get("shop_name", ""),
                    "affiliate_link": url,
                }

        except Exception as e:
            logger.error(f"[Shopee] URL scrape error: {e}", exc_info=True)
        finally:
            await page.close()

        return None

    def _parse_shopee_product(self, raw: Dict, index: int) -> Optional[Dict]:
        """Parse raw Shopee product data into standardized format."""
        if not raw.get("name"):
            return None

        return {
            "product_id": f"shopee_search_{index}_{hash(raw['name']) % 100000}",
            "platform": "shopee",
            "name": raw["name"],
            "price": self._parse_price(raw.get("price_text", "")),
            "image_urls": [raw["image_url"]] if raw.get("image_url") else [],
            "rating": self._parse_float(raw.get("rating_text", "")),
            "sold_count": self._parse_sold(raw.get("sold_text", "")),
            "affiliate_link": raw.get("link", ""),
        }

    # ─── TIKTOK SHOP ──────────────────────────────────────

    async def scrape_tiktok_search(
        self,
        keyword: str,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        """
        Search and scrape products from TikTok Shop.

        TikTok Shop is more restricted, so this is best-effort.
        """
        await self._ensure_browser()
        page = await self._context.new_page()
        products = []

        try:
            search_url = f"https://www.tiktok.com/search?q={keyword}%20shop"
            logger.info(f"[TikTok] Navigating to: {search_url}")

            await page.goto(search_url, wait_until="networkidle", timeout=30000)
            await asyncio.sleep(random.uniform(3.0, 5.0))

            # TikTok Shop uses dynamic rendering - try to extract product cards
            raw_products = await page.evaluate("""() => {
                const items = document.querySelectorAll('[class*="ProductCard"], [class*="product-card"]');
                const results = [];
                items.forEach(item => {
                    try {
                        const nameEl = item.querySelector('[class*="title"], [class*="name"]');
                        const priceEl = item.querySelector('[class*="price"]');
                        const imgEl = item.querySelector('img');
                        const linkEl = item.querySelector('a');

                        if (nameEl) {
                            results.push({
                                name: nameEl.innerText.trim(),
                                price_text: priceEl ? priceEl.innerText.trim() : '',
                                image_url: imgEl ? (imgEl.src || imgEl.dataset.src) : '',
                                link: linkEl ? linkEl.href : '',
                            });
                        }
                    } catch(e) {}
                });
                return results;
            }""")

            for i, raw in enumerate(raw_products[:limit]):
                product = {
                    "product_id": f"tiktok_search_{i}_{hash(raw.get('name', '')) % 100000}",
                    "platform": "tiktok",
                    "name": raw.get("name", ""),
                    "price": self._parse_price(raw.get("price_text", "")),
                    "image_urls": [raw["image_url"]] if raw.get("image_url") else [],
                    "affiliate_link": raw.get("link", ""),
                }
                if product["name"]:
                    products.append(product)

            logger.info(f"[TikTok] Found {len(products)} products for '{keyword}'")

        except Exception as e:
            logger.error(f"[TikTok] Scrape error: {e}", exc_info=True)
        finally:
            await page.close()

        return products

    # ─── Helpers ───────────────────────────────────────────

    def _parse_price(self, text: str) -> float:
        """Parse price from Vietnamese format text."""
        if not text:
            return 0.0
        # Remove currency symbols and dots as thousands separator
        cleaned = re.sub(r'[₫đĐ\s.]', '', text)
        # Find first number
        match = re.search(r'[\d,]+', cleaned)
        if match:
            try:
                return float(match.group().replace(',', '.'))
            except ValueError:
                pass
        return 0.0

    def _parse_float(self, text: str) -> Optional[float]:
        """Parse a float from text."""
        if not text:
            return None
        match = re.search(r'[\d.,]+', text)
        if match:
            try:
                return float(match.group().replace(',', '.'))
            except ValueError:
                pass
        return None

    def _parse_sold(self, text: str) -> Optional[int]:
        """Parse sold count from text like 'Đã bán 1,2k'."""
        if not text:
            return None
        text = text.lower().replace('.', '').replace(',', '.')
        match = re.search(r'([\d.]+)\s*k', text)
        if match:
            return int(float(match.group(1)) * 1000)
        match = re.search(r'([\d]+)', text)
        if match:
            return int(match.group(1))
        return None
