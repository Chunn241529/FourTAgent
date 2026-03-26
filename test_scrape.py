import asyncio
import logging
import sys

logging.basicConfig(level=logging.DEBUG, stream=sys.stdout)
from app.services.affiliate.scraper import ProductScraper

async def main():
    scraper = ProductScraper()
    print("Scraping Shopee URL...")
    url = "https://shopee.vn/product/166012674/10433602524"
    results = await scraper.scrape_shopee(url=url, limit=1)
    print(f"Results: {results}")

if __name__ == "__main__":
    asyncio.run(main())
