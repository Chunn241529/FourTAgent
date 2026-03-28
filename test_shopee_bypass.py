#!/usr/bin/env python3
"""
Test script for Shopee bypass with proxy rotation and enhanced headers.

Usage:
    # Without proxy (not recommended for production)
    python test_shopee_bypass.py

    # With single proxy
    python test_shopee_bypass.py --proxy "http://proxy-ip:port"

    # With proxy list for rotation
    python test_shopee_bypass.py --proxies "http://proxy1:port" "http://proxy2:port" "http://proxy3:port"

    # Headless mode (recommended for servers)
    python test_shopee_bypass.py --headless

    # Visible mode (for debugging)
    python test_shopee_bypass.py --visible
"""

import asyncio
import logging
import argparse
import sys
from typing import List, Optional

# Setup path to import from app
sys.path.insert(0, '/home/trung/Documents/4T_task')

from app.services.affiliate.playwright_scraper import PlaywrightScraper

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)


async def test_search(
    keyword: str,
    proxies: Optional[List[str]] = None,
    proxy: Optional[str] = None,
    headless: bool = True,
    limit: int = 10
):
    """Test Shopee search with given parameters."""
    
    logger.info(f"Testing Shopee search: '{keyword}'")
    logger.info(f"  - Headless: {headless}")
    logger.info(f"  - Proxy count: {len(proxies) if proxies else 1 if proxy else 0}")
    logger.info(f"  - Limit: {limit}")

    # Initialize scraper with proxy settings
    scraper = PlaywrightScraper(
        proxy=proxy,
        proxies=proxies,
        headless=headless,
        pool_key="test"
    )

    try:
        # Perform search
        products = await scraper.scrape_shopee_search(keyword=keyword, limit=limit)
        
        if products:
            logger.info(f"✓ Successfully found {len(products)} products!")
            logger.info("\nFirst 3 products:")
            for i, product in enumerate(products[:3], 1):
                logger.info(f"\n  {i}. {product.get('name', 'N/A')[:50]}")
                logger.info(f"     Price: {product.get('price', 'N/A')}")
                logger.info(f"     Shop: {product.get('shop_name', 'N/A')}")
                logger.info(f"     Rating: {product.get('rating', 'N/A')}")
                logger.info(f"     Sold: {product.get('sold_count', 'N/A')}")
        else:
            logger.warning("✗ No products found. Possible reasons:")
            logger.warning("  - API blocked by Shopee (may need proxy)")
            logger.warning("  - API structure changed")
            logger.warning("  - Check logs above for error details")
        
        return products
        
    except Exception as e:
        logger.error(f"✗ Error during search: {e}", exc_info=True)
        return []
    
    finally:
        # Close browser pool
        await scraper.close_pool()


async def test_url_scrape(
    url: str,
    proxy: Optional[str] = None,
    proxies: Optional[List[str]] = None,
    headless: bool = True
):
    """Test Shopee product URL scrape."""
    
    logger.info(f"Testing Shopee URL scrape: {url}")
    
    scraper = PlaywrightScraper(
        proxy=proxy,
        proxies=proxies,
        headless=headless,
        pool_key="test_url"
    )

    try:
        product = await scraper.scrape_shopee_url(url)
        
        if product:
            logger.info("✓ Successfully scraped product!")
            logger.info(f"  Name: {product.get('name', 'N/A')[:60]}")
            logger.info(f"  Price: {product.get('price', 'N/A')}")
            logger.info(f"  Images: {len(product.get('image_urls', []))}")
            logger.info(f"  Rating: {product.get('rating', 'N/A')}")
            logger.info(f"  Sold: {product.get('sold_count', 'N/A')}")
        else:
            logger.warning("✗ Failed to scrape product. Possible reasons:")
            logger.warning("  - URL format not recognized")
            logger.warning("  - Product doesn't exist")
            logger.warning("  - Blocked by Shopee")
        
        return product
        
    except Exception as e:
        logger.error(f"✗ Error during URL scrape: {e}", exc_info=True)
        return None
    
    finally:
        await scraper.close_pool()


async def main():
    parser = argparse.ArgumentParser(
        description="Test Shopee scraper with proxy rotation and enhanced headers"
    )
    parser.add_argument(
        "--keyword",
        type=str,
        default="iphone",
        help="Keyword to search (default: 'iphone')"
    )
    parser.add_argument(
        "--url",
        type=str,
        default=None,
        help="Product URL to scrape (if provided, tests URL scraping instead of search)"
    )
    parser.add_argument(
        "--proxy",
        type=str,
        default=None,
        help="Single proxy URL (format: http://ip:port or socks5://ip:port)"
    )
    parser.add_argument(
        "--proxies",
        type=str,
        nargs="+",
        default=None,
        help="Multiple proxies for rotation (format: http://ip:port ...)"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Number of products to scrape (default: 10)"
    )
    parser.add_argument(
        "--visible",
        action="store_true",
        help="Run in visible mode (not headless) for debugging"
    )
    
    args = parser.parse_args()
    headless = not args.visible
    
    logger.info("=" * 70)
    logger.info("SHOPEE SCRAPER - PROXY BYPASS TEST")
    logger.info("=" * 70)
    logger.info("\nConfiguration:")
    logger.info(f"  Headless mode: {headless}")
    logger.info(f"  Single proxy: {args.proxy if args.proxy else 'None'}")
    logger.info(f"  Proxy rotation: {len(args.proxies) if args.proxies else 0} proxies")
    logger.info("=" * 70)
    
    try:
        if args.url:
            # Test URL scraping
            await test_url_scrape(
                url=args.url,
                proxy=args.proxy,
                proxies=args.proxies,
                headless=headless
            )
        else:
            # Test search
            await test_search(
                keyword=args.keyword,
                proxy=args.proxy,
                proxies=args.proxies,
                headless=headless,
                limit=args.limit
            )
    
    except KeyboardInterrupt:
        logger.warning("\nTest interrupted by user")
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
    
    logger.info("\nTest complete!")


if __name__ == "__main__":
    asyncio.run(main())
