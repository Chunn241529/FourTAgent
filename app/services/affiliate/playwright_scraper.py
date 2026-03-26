"""
Playwright-based scraper implementation for Shopee and TikTok.

Uses API interception (network response capture) as the primary strategy
instead of brittle CSS selectors — Shopee/TikTok frequently change their
DOM structure, but internal API contracts change far less often.

Fallback: generic DOM parsing with broad selectors.
"""

import os
import re
import json
import asyncio
import logging
import random
import tempfile
import urllib.parse
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)


class PlaywrightScraper:
    """
    Browser automation scraper using Playwright.

    Primary strategy: intercept XHR/Fetch API responses from the page
    to capture structured JSON data directly from the platform's backend.

    Fallback: generic DOM parsing for cases where API interception fails.

    Features:
        - Browser session reuse via connection pool
        - Extended timeouts for slow-loading platforms (Douyin, TikTok)
        - Watermark-aware video extraction
        - Stealth automation to avoid detection
    """

    # Class-level browser pool for reuse across instances
    _pool: Dict[str, "_BrowserInstance"] = {}
    _pool_lock: asyncio.Lock = None

    def __init__(self, proxy: Optional[str] = None, headless: bool = True, pool_key: str = "default"):
        self.proxy = proxy
        self.headless = headless
        self.pool_key = pool_key
        self._page = None

    @classmethod
    def _get_lock(cls) -> asyncio.Lock:
        if cls._pool_lock is None:
            cls._pool_lock = asyncio.Lock()
        return cls._pool_lock

    async def _ensure_browser(self):
        """Lazily initialize Playwright browser with session reuse."""
        async with self._get_lock():
            # Reuse existing browser instance for this pool key
            if self.pool_key in self._pool:
                inst = self._pool[self.pool_key]
                if inst.browser and inst.context:
                    try:
                        # Verify browser is still alive
                        await inst.browser.connect(timeout=5000)
                        self._browser = inst.browser
                        self._context = inst.context
                        self._playwright = inst.playwright
                        return
                    except Exception:
                        # Browser died, clean up and recreate
                        try:
                            await inst.browser.close()
                        except Exception:
                            pass
                        del self._pool[self.pool_key]

            from playwright.async_api import async_playwright
            p = await async_playwright().start()

            launch_args = {
                "headless": self.headless,
                "args": [
                    "--disable-blink-features=AutomationControlled",
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                    "--single-process",
                ],
            }

            if self.proxy:
                launch_args["proxy"] = {"server": self.proxy}

            browser = await p.chromium.launch(**launch_args)

            context = await browser.new_context(
                viewport={"width": 1366, "height": 768},
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/131.0.0.0 Safari/537.36"
                ),
                locale="vi-VN",
                timezone_id="Asia/Ho_Chi_Minh",
            )

            # Stealth injection
            await context.add_init_script("""
                Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
                Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
                Object.defineProperty(navigator, 'languages', { get: () => ['vi-VN', 'vi', 'en-US', 'en'] });
                window.chrome = { runtime: {} };
                delete navigator.__proto__.webdriver;
            """)

            class _BrowserInstance:
                def __init__(self, playwright, browser, context):
                    self.playwright = playwright
                    self.browser = browser
                    self.context = context

            self._pool[self.pool_key] = _BrowserInstance(p, browser, context)
            self._playwright = p
            self._browser = browser
            self._context = context
            logger.info(f"[PlaywrightScraper] Browser initialized for pool '{self.pool_key}'")

    async def close(self):
        """Close page (not browser - browser is pooled for reuse)."""
        if self._page:
            await self._page.close()
            self._page = None

    async def close_pool(self):
        """Close all browsers in the pool. Call on app shutdown."""
        async with self._get_lock():
            for inst in list(self._pool.values()):
                try:
                    await inst.browser.close()
                except Exception:
                    pass
            self._pool.clear()
            logger.info("[PlaywrightScraper] Browser pool closed")

    # ─── SHOPEE ────────────────────────────────────────────
    #
    # Strategy: navigate to search page, intercept the internal
    # search API response (shopee.vn/api/v4/search/search_items)
    # which returns clean JSON. Fallback to DOM parsing.
    #

    async def scrape_shopee_search(
        self,
        keyword: str,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        """
        Search and scrape products from Shopee.
        Uses API interception as primary method.
        """
        await self._ensure_browser()
        page = await self._context.new_page()
        products = []
        api_data: List[Dict] = []

        # --- Strategy 1: Intercept Shopee search API ---
        async def on_response(response):
            try:
                url = response.url
                if (
                    "api/v4/search" in url or
                    "api/v2/search_items" in url or
                    "/api/v4/recommend" in url or
                    "/api/v4/item" in url
                ):
                    if response.status == 200:
                        try:
                            body = await response.json()
                            items = (
                                body.get("items") or
                                body.get("data", {}).get("items") or
                                body.get("item") or
                                []
                            )
                            if isinstance(items, list):
                                api_data.extend(items)
                                logger.info(f"[Shopee] Intercepted {len(items)} items from API")
                        except Exception:
                            pass
            except Exception:
                pass

        page.on("response", on_response)

        try:
            encoded_keyword = urllib.parse.quote(keyword)
            search_url = f"https://shopee.vn/search?keyword={encoded_keyword}"
            logger.info(f"[Shopee] Navigating to: {search_url}")

            await page.goto(search_url, wait_until="domcontentloaded", timeout=30000)

            # Wait for content to load and APIs to fire
            await asyncio.sleep(random.uniform(4.0, 6.0))

            # Scroll to trigger lazy loading
            for _ in range(4):
                await page.evaluate("window.scrollBy(0, 600)")
                await asyncio.sleep(random.uniform(0.8, 1.5))

            # Wait a bit more for any remaining API calls
            await asyncio.sleep(2.0)

            # --- Parse intercepted API data ---
            if api_data:
                for i, item in enumerate(api_data[:limit]):
                    parsed = self._parse_shopee_api_item(item, i)
                    if parsed:
                        products.append(parsed)
                logger.info(f"[Shopee] Parsed {len(products)} products from API interception")

            # --- Strategy 2: Fallback to DOM parsing ---
            if not products:
                logger.info("[Shopee] API interception empty, falling back to DOM parsing")
                products = await self._shopee_dom_fallback(page, limit)

            logger.info(f"[Shopee] Total: {len(products)} products for '{keyword}'")

        except Exception as e:
            logger.error(f"[Shopee] Scrape error: {e}", exc_info=True)
        finally:
            page.remove_listener("response", on_response)
            await page.close()

        return products

    def _parse_shopee_api_item(self, item: Dict, index: int) -> Optional[Dict]:
        """Parse a single item from Shopee's internal API response."""
        try:
            # Shopee API can wrap data in item_basic or directly
            basic = item.get("item_basic") or item

            name = basic.get("name", "")
            if not name:
                return None

            # Price is in cents (VND * 100000)
            price_raw = basic.get("price", 0)
            price_max = basic.get("price_max", price_raw)
            price = price_raw / 100000 if price_raw > 100000 else price_raw

            original_price_raw = basic.get("price_before_discount", 0)
            original_price = original_price_raw / 100000 if original_price_raw > 100000 else original_price_raw

            # Images: Shopee stores hash IDs
            images = basic.get("images", [])
            image_urls = [
                f"https://down-vn.img.susercontent.com/file/{img}"
                for img in images if img
            ]

            video_info_list = basic.get("video_info_list", [])
            video_urls = []
            for v in video_info_list:
                df = v.get("default_format", {})
                if df and df.get("url"):
                    video_urls.append(df.get("url"))
                elif v.get("formats"):
                    fmt = v.get("formats")[0]
                    if fmt and fmt.get("url"):
                        video_urls.append(fmt.get("url"))

            item_id = str(basic.get("itemid", ""))
            shop_id = str(basic.get("shopid", ""))

            discount = basic.get("raw_discount", 0)

            return {
                "product_id": f"shopee_{shop_id}_{item_id}" if item_id else f"shopee_search_{index}",
                "platform": "shopee",
                "name": name,
                "price": price,
                "original_price": original_price if original_price > 0 else None,
                "discount_percent": discount if discount > 0 else None,
                "rating": basic.get("item_rating", {}).get("rating_star"),
                "sold_count": basic.get("historical_sold") or basic.get("sold"),
                "image_urls": image_urls,
                "video_urls": video_urls,
                "affiliate_link": f"https://shopee.vn/product/{shop_id}/{item_id}" if item_id else "",
                "shop_name": basic.get("shop_name", ""),
                "category": str(basic.get("catid", "")),
            }
        except Exception as e:
            logger.debug(f"[Shopee] Failed to parse API item: {e}")
            return None

    async def _shopee_dom_fallback(self, page, limit: int) -> List[Dict]:
        """Fallback: parse products from DOM using broad, adaptive selectors."""
        products = []
        try:
            raw_products = await page.evaluate("""() => {
                // Strategy: find all links that look like product links
                const productLinks = document.querySelectorAll('a[href*="/product/"], a[href*="-i."]');
                const seen = new Set();
                const results = [];

                productLinks.forEach(link => {
                    const href = link.href || '';
                    if (seen.has(href) || !href) return;
                    seen.add(href);

                    // Walk up to find the product card container
                    let card = link;
                    for (let i = 0; i < 5; i++) {
                        if (card.parentElement) card = card.parentElement;
                    }

                    // Extract text content from the card
                    const allText = card.innerText || '';
                    const lines = allText.split('\\n').map(l => l.trim()).filter(Boolean);

                    // Find image
                    const img = card.querySelector('img');
                    const imgSrc = img ? (img.src || img.dataset.src || '') : '';

                    // Find price-like text (contains ₫ or đ or numbers with dots)
                    const priceLine = lines.find(l => /[₫đ]|\\d{1,3}(\\.\\d{3})+/.test(l)) || '';

                    // Product name is usually the longest non-price text
                    const nameCandidates = lines.filter(l =>
                        l.length > 10 && !/[₫đ]/.test(l) && !/^\\d/.test(l) && !/^Đã bán/.test(l)
                    );
                    const name = nameCandidates.sort((a, b) => b.length - a.length)[0] || '';

                    // Sold count
                    const soldLine = lines.find(l => /bán|sold/i.test(l)) || '';

                    if (name) {
                        results.push({
                            name: name,
                            price_text: priceLine,
                            image_url: imgSrc,
                            link: href,
                            sold_text: soldLine,
                        });
                    }
                });
                return results;
            }""")

            for i, raw in enumerate(raw_products[:limit]):
                if raw.get("name"):
                    products.append({
                        "product_id": f"shopee_dom_{i}_{hash(raw['name']) % 100000}",
                        "platform": "shopee",
                        "name": raw["name"],
                        "price": self._parse_price(raw.get("price_text", "")),
                        "image_urls": [raw["image_url"]] if raw.get("image_url") else [],
                        "affiliate_link": raw.get("link", ""),
                        "sold_count": self._parse_sold(raw.get("sold_text", "")),
                    })

            logger.info(f"[Shopee] DOM fallback found {len(products)} products")
        except Exception as e:
            logger.error(f"[Shopee] DOM fallback error: {e}", exc_info=True)

        return products

    async def scrape_shopee_url(self, url: str) -> Optional[Dict[str, Any]]:
        """Scrape a single product from its Shopee URL."""
        await self._ensure_browser()
        page = await self._context.new_page()
        product_data = None
        shop_id, item_id = None, None

        # ─── Extract shop_id and item_id from URL ───
        # Try /product/{shop_id}/{item_id} format first (most common)
        item_match = re.search(r'/product/(\d+)/(\d+)', url)
        if item_match:
            shop_id, item_id = item_match.group(1), item_match.group(2)
        else:
            # Fall back to -i.{shop_id}.{item_id} format
            item_match = re.search(r'-i\.(\d+)\.(\d+)', url)
            if item_match:
                shop_id, item_id = item_match.group(1), item_match.group(2)

        # ─── Clean URL of tracking parameters ───
        parsed = urllib.parse.urlparse(url)
        allowed_params = {'sp', 'search', 'keyword'}
        clean_params = {k: v[0] for k, v in urllib.parse.parse_qs(parsed.query).items() if k in allowed_params}
        clean_path = parsed.path
        if clean_params:
            clean_url = f"{parsed.scheme}://{parsed.netloc}{clean_path}?{urllib.parse.urlencode(clean_params)}"
        else:
            clean_url = f"{parsed.scheme}://{parsed.netloc}{clean_path}"

        logger.info(f"[Shopee] URL scrape: shop_id={shop_id}, item_id={item_id}, url={clean_url}")

        # ─── Broader API interception ───
        async def on_response(response):
            nonlocal product_data
            try:
                if response.status == 200:
                    body = await response.json()
                    if isinstance(body, dict):
                        # Check various Shopee API response structures
                        if body.get('data', {}).get('item') or body.get('item'):
                            item = body.get('data', {}).get('item') or body.get('item') or body
                            if item.get('name'):
                                product_data = item
                        elif 'items' in body and len(body.get('items', [])) > 0:
                            items = body.get('items', [])
                            if items[0].get('name') or items[0].get('item_basic', {}).get('name'):
                                product_data = items[0].get('item_basic') or items[0]
                        elif body.get('name'):
                            product_data = body
            except Exception:
                pass

        page.on("response", on_response)

        try:
            # Try direct API call first (most reliable when we have IDs)
            if shop_id and item_id:
                api_url = f"https://shopee.vn/api/v4/item/get?itemid={item_id}&shopid={shop_id}"
                logger.info(f"[Shopee] Trying direct API: {api_url}")
                try:
                    headers = {
                        "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
                        "Referer": f"https://shopee.vn/product/{shop_id}/{item_id}",
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                        "X-Requested-With": "XMLHttpRequest",
                    }
                    api_response = await page.request.get(api_url, headers=headers, timeout=15000)
                    if api_response.ok:
                        api_data = await api_response.json()
                        # Shopee may return data under 'item' or 'data' or directly at root
                        item = api_data.get("data") or api_data.get("item") or api_data
                        if item and (item.get("name") or item.get("itemid")):
                            product_data = item
                            images_count = len(item.get("images", []))
                            logger.info(f"[Shopee] Direct API succeeded, images count: {images_count}")
                        else:
                            # Check if images are at root level
                            if api_data.get("images"):
                                product_data = api_data
                                logger.info(f"[Shopee] Direct API returned data at root level, images: {len(api_data.get('images', []))}")
                            else:
                                logger.info(f"[Shopee] Direct API response keys: {list(api_data.keys()) if isinstance(api_data, dict) else 'not a dict'}")
                    else:
                        error_body = await api_response.text()
                        logger.error(f"[Shopee] Direct API failed with status {api_response.status}, body: {error_body[:500]}")
                except Exception as e:
                    logger.debug(f"[Shopee] Direct API failed: {e}")

            # Navigate to page if API didn't get product data
            if not product_data:
                await page.goto(clean_url, wait_until="networkidle", timeout=30000)
                await asyncio.sleep(random.uniform(1.0, 2.0))

                # Scroll to trigger lazy content
                for _ in range(5):
                    await page.evaluate("window.scrollBy(0, 500)")
                    await asyncio.sleep(0.5)
                await asyncio.sleep(1.5)
                await page.evaluate("window.scrollTo(0, 0)")

            # ─── Parse product data if captured ───
            if product_data:
                basic = product_data.get("item") or product_data
                images = basic.get("images", [])
                image_urls = [f"https://down-vn.img.susercontent.com/file/{img}" for img in images if img]

                price_raw = basic.get("price", 0)
                price = price_raw / 100000 if price_raw > 100000 else price_raw

                video_info_list = basic.get("video_info_list", [])
                video_urls = []
                for v in video_info_list:
                    df = v.get("default_format", {})
                    if df and df.get("url"):
                        video_urls.append(df.get("url"))
                    elif v.get("formats"):
                        fmt = v.get("formats")[0]
                        if fmt and fmt.get("url"):
                            video_urls.append(fmt.get("url"))

                resolved_item_id = basic.get("itemid") or item_id or str(hash(url))
                resolved_shop_id = basic.get("shopid") or shop_id or ""

                return {
                    "product_id": f"shopee_{resolved_shop_id}_{resolved_item_id}" if resolved_shop_id else str(resolved_item_id),
                    "platform": "shopee",
                    "name": basic.get("name", ""),
                    "price": price,
                    "image_urls": image_urls,
                    "video_urls": video_urls,
                    "rating": basic.get("item_rating", {}).get("rating_star"),
                    "sold_count": basic.get("historical_sold"),
                    "description": (basic.get("description") or "")[:500],
                    "shop_name": basic.get("shop_name", ""),
                    "affiliate_link": url,
                }

            # ─── Enhanced DOM fallback ───
            logger.info("[Shopee] URL: API interception empty, trying DOM")
            data = await page.evaluate("""() => {
                // Try JSON-LD structured data first
                const jsonLd = document.querySelector('script[type="application/ld+json"]');
                if (jsonLd) {
                    try {
                        const data = JSON.parse(jsonLd.textContent);
                        if (data.name) return { name: data.name, price: data.offers?.price };
                    } catch(e) {}
                }

                // Try window.__INITIAL_STATE__
                if (window.__INITIAL_STATE__) {
                    try {
                        const state = JSON.parse(window.__INITIAL_STATE__);
                        const str = JSON.stringify(state);
                        const nameMatch = str.match(/"name"\\s*:\\s*"([^"]+)"/);
                        if (nameMatch) return { name: nameMatch[1] };
                    } catch(e) {}
                }

                // Try window.__RENDER_DATA__
                if (window.__RENDER_DATA__) {
                    try {
                        const str = JSON.stringify(window.__RENDER_DATA__);
                        const nameMatch = str.match(/"name"\\s*:\\s*"([^"]+)"/);
                        if (nameMatch) return { name: nameMatch[1] };
                    } catch(e) {}
                }

                // Broad DOM selectors
                const getText = sel => {
                    const el = document.querySelector(sel);
                    return el ? el.innerText.trim() : '';
                };
                const name = getText('h1')
                    || getText('[data-testid="product-title"]')
                    || getText('.pdp-product-title')
                    || getText('[class*="product-title"]')
                    || getText('[class*="title"]')
                    || getText('[class*="name"]')
                    || getText('.product-detail-page h1')
                    || getText('main h1')
                    || getText('[itemprop="name"]')
                    || document.querySelector('h1')?.innerText?.trim();

                // Find images - check dataset.src first (lazy loaded), then src
                const imgs = [...document.querySelectorAll('img')]
                    .map(i => i.dataset.src || i.dataset.original || i.src)
                    .filter(src => src &&
                        (src.includes('susercontent') || src.includes('shopee')) &&
                        !src.includes('deo.shopeemobile.com') &&
                        !src.includes('1c8bdaaf45e1fd48') &&
                        src.length > 100
                    )
                    .slice(0, 10);

                // Extract price from page text
                const allText = document.body.innerText;
                const pricePatterns = [
                    /[₫đ]\\s*[\\d.,]+/g,
                    /[\\d.,]+\\s*[₫đ]/g,
                    /Giá\\s*:?\\s*[₫đ]?\\s*[\\d.,]+/gi
                ];
                let price_text = '';
                for (const pattern of pricePatterns) {
                    const match = allText.match(pattern);
                    if (match) { price_text = match[0]; break; }
                }

                return {
                    name: name || '',
                    price_text: price_text,
                    image_urls: imgs,
                };
            }""")

            if data and data.get("name"):
                resolved_item_id = item_id if item_id else str(hash(url))
                return {
                    "product_id": f"shopee_{shop_id}_{resolved_item_id}" if shop_id else str(resolved_item_id),
                    "platform": "shopee",
                    "name": data["name"],
                    "price": self._parse_price(data.get("price_text", "")),
                    "image_urls": data.get("image_urls", []),
                    "affiliate_link": url,
                }

        except Exception as e:
            logger.error(f"[Shopee] URL scrape error: {e}", exc_info=True)
        finally:
            page.remove_listener("response", on_response)
            await page.close()

        return None

    # ─── TIKTOK SHOP ──────────────────────────────────────

    async def scrape_tiktok_search(
        self,
        keyword: str,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        """Search and scrape products from TikTok Shop via API interception."""
        await self._ensure_browser()
        page = await self._context.new_page()
        products = []
        api_data: List[Dict] = []

        async def on_response(response):
            try:
                url = response.url
                if ("api" in url and ("search" in url or "product" in url or "recommend" in url)):
                    if response.status == 200:
                        try:
                            body = await response.json()
                            # TikTok APIs have various structures
                            items = (
                                body.get("data", {}).get("products") or
                                body.get("data", {}).get("items") or
                                body.get("products") or
                                body.get("items") or
                                []
                            )
                            if isinstance(items, list) and items:
                                api_data.extend(items)
                        except Exception:
                            pass
            except Exception:
                pass

        page.on("response", on_response)

        try:
            encoded_keyword = urllib.parse.quote(keyword)
            search_url = f"https://www.tiktok.com/search?q={encoded_keyword}%20shop"
            logger.info(f"[TikTok] Navigating to: {search_url}")

            await page.goto(search_url, wait_until="domcontentloaded", timeout=30000)
            await asyncio.sleep(random.uniform(4.0, 6.0))

            # Scroll to trigger loading
            for _ in range(3):
                await page.evaluate("window.scrollBy(0, 600)")
                await asyncio.sleep(random.uniform(0.8, 1.5))

            await asyncio.sleep(2.0)

            # Parse API data
            if api_data:
                for i, item in enumerate(api_data[:limit]):
                    parsed = self._parse_tiktok_api_item(item, i)
                    if parsed:
                        products.append(parsed)

            # Fallback to DOM
            if not products:
                logger.info("[TikTok] API empty, falling back to DOM")
                products = await self._tiktok_dom_fallback(page, limit)

            logger.info(f"[TikTok] Found {len(products)} products for '{keyword}'")

        except Exception as e:
            logger.error(f"[TikTok] Scrape error: {e}", exc_info=True)
        finally:
            page.remove_listener("response", on_response)
            await page.close()

        return products

    def _parse_tiktok_api_item(self, item: Dict, index: int) -> Optional[Dict]:
        """Parse TikTok Shop API item."""
        try:
            name = item.get("title") or item.get("name") or ""
            if not name:
                return None

            price = item.get("price", {})
            if isinstance(price, dict):
                price_val = float(price.get("original_price", 0)) / 100
            else:
                price_val = float(price) if price else 0

            images = item.get("images") or item.get("cover") or []
            if isinstance(images, str):
                images = [images]
            elif isinstance(images, list):
                images = [
                    (img.get("url") or img) if isinstance(img, dict) else str(img)
                    for img in images
                ]
                
            video_urls = []
            video = item.get("video")
            if video:
                play_urls = video.get("play_addr", {}).get("url_list", [])
                if play_urls:
                    video_urls.append(play_urls[0])
                elif video.get("play_addr_h264", {}).get("url_list"):
                    video_urls.append(video.get("play_addr_h264")["url_list"][0])

            return {
                "product_id": f"tiktok_{item.get('id', index)}",
                "platform": "tiktok",
                "name": name,
                "price": price_val,
                "image_urls": images[:5],
                "video_urls": video_urls,
                "affiliate_link": item.get("url") or item.get("link") or "",
                "sold_count": item.get("sold_count"),
            }
        except Exception as e:
            logger.debug(f"[TikTok] Parse API item error: {e}")
            return None

    async def _tiktok_dom_fallback(self, page, limit: int) -> List[Dict]:
        """Fallback: parse TikTok products from DOM."""
        products = []
        try:
            raw_products = await page.evaluate("""() => {
                // Look for any product-like cards
                const cards = document.querySelectorAll(
                    '[class*="ProductCard"], [class*="product-card"], ' +
                    '[class*="ProductItem"], [class*="product_item"], ' +
                    '[data-e2e*="product"], [data-e2e*="search-card"]'
                );
                const results = [];
                cards.forEach(card => {
                    try {
                        const nameEl = card.querySelector(
                            '[class*="title"], [class*="name"], [class*="Title"], h3, h4'
                        );
                        const priceEl = card.querySelector('[class*="price"], [class*="Price"]');
                        const imgEl = card.querySelector('img');
                        const linkEl = card.querySelector('a');

                        if (nameEl && nameEl.innerText.trim()) {
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
                if raw.get("name"):
                    products.append({
                        "product_id": f"tiktok_dom_{i}_{hash(raw['name']) % 100000}",
                        "platform": "tiktok",
                        "name": raw["name"],
                        "price": self._parse_price(raw.get("price_text", "")),
                        "image_urls": [raw["image_url"]] if raw.get("image_url") else [],
                        "affiliate_link": raw.get("link", ""),
                    })
            return products[:limit]

        except Exception as e:
            logger.error(f"[TikTok] DOM fallback error: {e}", exc_info=True)
            return products

    async def scrape_douyin_with_cookies(self, url: str, timeout: float = 20.0) -> dict:
        """
        Scrape Douyin video by getting cookies from browser, then using yt-dlp.

        Args:
            url: Douyin video URL
            timeout: Max seconds to wait for page load

        Returns:
            dict with cookies, cookie_file path, and video_url
        """
        logger.info(f"[Playwright] Getting cookies for {url}")
        await self._ensure_browser()
        page = await self._context.new_page()

        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=int(timeout * 1000))
            await asyncio.sleep(5.0)  # Wait for JS to set cookies

            # Extract cookies from both possible domains
            cookies = await self._context.cookies(['https://www.douyin.com', 'https://douyin.com'])

            # Write to temp file in Netscape format
            cookie_file = tempfile.mktemp(suffix='.txt')
            self._write_netscape_cookies(cookies, cookie_file)

            logger.info(f"[Playwright] Extracted {len(cookies)} cookies for Douyin")

            return {
                'cookie_file': cookie_file,
                'cookies': cookies,
                'video_url': url,
            }
        finally:
            await page.close()

    def _write_netscape_cookies(self, cookies: List[dict], path: str):
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

    async def scrape_generic_fallback(self, url: str, timeout: float = 15.0) -> dict:
        """
        Fallback for generic links when yt-dlp fails.
        Opens the URL in playwright, waits for media responses, and extracts video source.

        Args:
            url: The video page URL
            timeout: Max seconds to wait for video URL detection (default 15s, was 5s)

        Returns:
            dict with title, video_url, watermark_removed, and detected_platform
        """
        logger.info(f"[Playwright] Running generic fallback for {url} (timeout={timeout}s)")
        await self._ensure_browser()

        page = None
        detected_platform = "unknown"
        try:
            page = await self._context.new_page()
            import re

            # Detect platform early
            if "douyin" in url.lower():
                detected_platform = "douyin"
            elif "tiktok" in url.lower():
                detected_platform = "tiktok"
            elif "kuaishou" in url.lower():
                detected_platform = "kuaishou"

            video_url_future: asyncio.Future = asyncio.Future()
            video_urls_found: List[str] = []

            # Extract video IDs for interception patterns
            douyin_vid = None
            tiktok_vid = None
            m = re.search(r'douyin\.com/video/(\d+)', url)
            if m:
                douyin_vid = m.group(1)
            m = re.search(r'tiktok\.com/.*?/video/(\d+)', url)
            if m:
                tiktok_vid = m.group(1)

            async def handle_response(response):
                r_url = response.url
                resource = response.request.resource_type
                if resource not in ("media", "fetch", "xhr", "websocket"):
                    return

                try:
                    if douyin_vid:
                        # Douyin: watch for aweme/v1/play or video stream URLs
                        # Also includes Douyin CDN domains (v.douyinvod.com, v26.douyinvod.com, etc.)
                        douyin_cdn_pattern = "douyinvod.com" in r_url or "aweme/v1/play" in r_url
                        if (douyin_cdn_pattern or "aweme/v1/play" in r_url or douyin_vid in r_url or ".mp4" in r_url) and not video_url_future.done():
                            if response.status == 200:
                                video_urls_found.append(r_url)
                                if len(video_urls_found) == 1:
                                    video_url_future.set_result(r_url)
                    elif tiktok_vid:
                        # TikTok: watch for video stream URLs
                        if (tiktok_vid in r_url or ".mp4" in r_url or "video" in r_url) and not video_url_future.done():
                            if response.status == 200:
                                video_urls_found.append(r_url)
                                if len(video_urls_found) == 1:
                                    video_url_future.set_result(r_url)
                    else:
                        # Generic: any MP4 or video_info response
                        if (".mp4" in r_url or "video_info" in r_url) and not video_url_future.done():
                            if response.status == 200:
                                video_url_future.set_result(r_url)
                except Exception:
                    pass

            page.on("response", handle_response)

            # Also watch for console messages that might contain video URLs
            async def handle_console(msg):
                if msg.type == "debug":
                    text = msg.text
                    if ".mp4" in text or "video_url" in text or "playAddr" in text:
                        if not video_url_future.done():
                            # Try to extract URL from console text
                            m2 = re.search(r'https?://[^\s"\'<>]+\.mp4[^\s"\'<>]*', text)
                            if m2:
                                video_url_future.set_result(m2.group(0))

            page.on("console", handle_console)

            # Use networkidle for Douyin since it loads videos dynamically
            wait_strategy = "networkidle" if detected_platform == "douyin" else "domcontentloaded"
            await page.goto(url, wait_until=wait_strategy, timeout=int(timeout * 1000))

            # For Douyin, wait for JS to execute and interact with page to trigger video player
            if detected_platform == "douyin":
                await asyncio.sleep(3.0)
                # Scroll down to bring video player into view
                await page.evaluate("window.scrollBy(0, 300)")
                await asyncio.sleep(1.0)

            # Wait for video streaming URL detection with the specified timeout
            try:
                video_url = await asyncio.wait_for(video_url_future, timeout=timeout)
            except asyncio.TimeoutError:
                video_url = None
                logger.info(f"[Playwright] Video URL detection timed out after {timeout}s")

            # If no video URL captured via network, try DOM extraction
            if not video_url:
                try:
                    # Try to find <video> element with src or poster
                    video_element = await page.query_selector("video")
                    if video_element:
                        video_url = await video_element.get_attribute("src")
                        if not video_url:
                            # Maybe video is in a source element
                            source = await video_element.query_selector("source")
                            if source:
                                video_url = await source.get_attribute("src")
                except Exception:
                    pass

            # Try extracting from page's JavaScript state (common for Douyin/TikTok)
            if not video_url:
                try:
                    js_data = await page.evaluate(r"""() => {
                        // Douyin/TikTok often embed video data in window.__INITIAL_STATE__ or similar
                        const scripts = document.querySelectorAll('script');
                        for (const s of scripts) {
                            const text = s.textContent || '';
                            // Look for video URL patterns
                            const mp4Match = text.match(/https?:\/\/[^"']+\.mp4/);
                            if (mp4Match) return mp4Match[0];
                            const playAddrMatch = text.match(/"playAddr":"([^"]+)"/);
                            if (playAddrMatch) {
                                try { return decodeURIComponent(playAddrMatch[1]); } catch(e) {}
                            }
                            const urlMatch = text.match(/"url":"(https?:\/\/[^"]+)"/);
                            if (urlMatch) return urlMatch[1];
                        }
                        // Try _ROUTER_DATA or __NEXT_DATA__
                        const nextData = document.getElementById('__NEXT_DATA__');
                        if (nextData) {
                            try {
                                const data = JSON.parse(nextData.textContent);
                                const jsonStr = JSON.stringify(data);
                                const mp4Match = jsonStr.match(/https?:\\/\\/[^"']+\\.mp4/);
                                if (mp4Match) return mp4Match[0];
                            } catch(e) {}
                        }
                        return null;
                    }""")
                    if js_data:
                        video_url = js_data
                except Exception:
                    pass

            title = await page.title()

            if video_url and video_url.startswith("//"):
                video_url = "https:" + video_url

            # For Douyin, the captured URL often contains watermark parameters
            # We flag it so the caller knows watermark removal may be needed
            watermark_removed = False
            if detected_platform == "douyin" and video_url:
                # Douyin stream URLs may have wm=1 parameter (watermark)
                # or lack the parameter entirely if we got a clean URL
                watermark_removed = "wm=1" not in video_url and "watermark" not in video_url.lower()

            return {
                "title": title or "Unknown Video",
                "video_url": video_url or url,
                "watermark_removed": watermark_removed,
                "detected_platform": detected_platform,
            }

        except Exception as e:
            logger.error(f"[Playwright] Generic fallback failed: {e}")
            return {"title": "Unknown Video", "video_url": url, "watermark_removed": False, "detected_platform": "unknown"}
        finally:
            if page:
                await page.close()

    # ─── Helpers ───────────────────────────────────────────

    def _parse_price(self, text: str) -> float:
        """Parse price from Vietnamese format text."""
        if not text:
            return 0.0
        # Remove currency symbols and dots as thousands separator
        cleaned = re.sub(r'[₫đĐ\s.]', '', text)
        # Find first number sequence
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
