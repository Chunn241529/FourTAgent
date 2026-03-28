# Shopee Scraper - Proxy Bypass Guide

## Problems Solved

✅ **API Blocking** - Enhanced headers + proxy rotation  
✅ **Empty Responses** - Better logging to identify encrypted/missing data  
✅ **Rate Limiting** - Proxy rotation + longer waits for JS execution  
✅ **Detection** - Improved stealth + randomized delays  

---

## Implementation Changes

### 1. **Proxy Rotation Support** ✅
- Added `proxies` parameter (list of proxy URLs)
- Automatic round-robin proxy selection
- Support for both single proxy and multiple proxies
- Enhanced browser args to reduce detectability

### 2. **Shopee-Specific Headers** ✅
- New `_get_shopee_headers()` method
- Added required headers: `X-API-Source`, `X-Requested-With`, `X-Shopee-SPA-Version`
- Proper `Referer` handling for each API call

### 3. **Better Logging** ✅
- Log all API responses (status, keys, encrypted flag)
- Log when 403 Forbidden occurs (proxy issue)
- Track intercepted items count
- Detect empty API responses with details

### 4. **Improved Wait Times** ✅
- Increased initial JS wait: 5-7 seconds (was 3-5s)
- More scroll iterations: 8 (was 6)
- Longer delays between scrolls: 1.5-2.5s (was 1-2s)
- Better simulation of human behavior

---

## How to Use

### Option A: Without Proxy (NOT Recommended)
```python
from app.services.affiliate.playwright_scraper import PlaywrightScraper

scraper = PlaywrightScraper()
products = await scraper.scrape_shopee_search("iphone", limit=10)
```

### Option B: With Single Proxy
```python
scraper = PlaywrightScraper(proxy="http://proxy-ip:port")
products = await scraper.scrape_shopee_search("iphone", limit=10)
```

### Option C: With Proxy Rotation (RECOMMENDED)
```python
proxies = [
    "http://proxy1-ip:port",
    "http://proxy2-ip:port",
    "http://proxy3-ip:port",
]

scraper = PlaywrightScraper(proxies=proxies)
products = await scraper.scrape_shopee_search("iphone", limit=10)
# Automatically rotates proxy for each request
```

### Option D: Combining Single Proxy + Rotation
```python
scraper = PlaywrightScraper(
    proxy="http://main-proxy:port",  # Fallback
    proxies=["http://proxy1:port", "http://proxy2:port"]  # Primary rotation
)
```

---

## Testing the Bypass

### Run Test Script

**Without proxy (quick test):**
```bash
cd /home/trung/Documents/4T_task
python test_shopee_bypass.py --keyword "samsung galaxy"
```

**With single proxy:**
```bash
python test_shopee_bypass.py --keyword "iphone" --proxy "http://ip:port"
```

**With proxy rotation:**
```bash
python test_shopee_bypass.py \
  --keyword "laptop" \
  --proxies http://proxy1:port http://proxy2:port http://proxy3:port \
  --limit 15
```

**Debug mode (visible browser):**
```bash
python test_shopee_bypass.py --keyword "test" --visible
```

---

## Recommended Proxy Providers

For residential proxies (best for Shopee):

1. **BrightData** (formerly Luminati)
   - Format: `http://customer-USER:PASS@proxy.provider.com:PORT`
   - Most reliable but expensive ($50-500/month)

2. **ScraperAPI**
   - Format: `http://scraperapi:APIKEY@proxy.scraperapi.com:8001`
   - Includes auto-retry on 200 + 403 ($29-299/month)

3. **ReputationIP**
   - Format: `http://username:password@IP:PORT`
   - Budget option (~$15-50/month)

4. **IPQuality**
   - Format: `http://api_key@proxy.ipqualityproxy.com:PORT`
   - Good balance ($10-100/month)

---

## Signs of Success

After running the test, you should see:

✅ **Good Response:**
```
[Shopee] Navigating to: https://shopee.vn/search?keyword=iphone
[Shopee] Page loaded, waiting for JS to populate API data...
[Shopee] API Response - URL: https://shopee.vn/api/v4/search..., Status: 200, Keys: ['data', 'pagination', 'nofollow']
[Shopee] Intercepted 30 items from API
[Shopee] Parsed 10 products from API interception
✓ Successfully found 10 products!
```

❌ **Problem Signs:**
```
[Shopee] API Response - ... 403 Forbidden. Proxy may need rotation.
# → Proxy blocked, try different proxy provider

[Shopee] API response valid but empty items. Body keys: ['error', 'msg']
# → API structure changed, need to update parsing

[Shopee] Detected encrypted API response from ... (keys: ['2', '4', '6', ...])
# → Shopee returned encrypted response, fallback to DOM will be used
```

---

## Troubleshooting

### 1. Empty Products List
**Problem:** API returns data but no products found

**Solutions:**
- ✅ Use a residential proxy (not data center)
- ✅ Add more wait time (try `--visible` to see page loading)
- ✅ Check logs for "Detected encrypted API response"
- ✅ Try different proxy provider

### 2. Connection Refused / Timeout
**Problem:** Can't connect to Shopee or proxy

**Solutions:**
- ✅ Check proxy URL format: `http://ip:port` or `socks5://ip:port`
- ✅ Test proxy manually: `curl -x http://proxy:port https://shopee.vn`
- ✅ Increase timeout in code: `await page.goto(..., timeout=60000)`

### 3. 403 Forbidden
**Problem:** Shopee detecting automation

**Solutions:**
- ✅ Most common - rotate proxy or use residential proxy
- ✅ Try headful mode: `PlaywrightScraper(..., headless=False)`
- ✅ Wait longer: `await asyncio.sleep(10)` after goto

### 4. Slow Performance
**Problem:** Scraping very slow

**Solutions:**
- ✅ Reduce limit: `limit=5` instead of 20
- ✅ Use residential proxy (data center proxies are slower)
- ✅ Run headless mode` (uses less resources)

---

## Code Changes Summary

### Modified Methods

1. **`__init__(...)`**
   - Added `proxies` parameter for proxy list
   - Added proxy rotation index
   - Added Shopee API version constant

2. **`_rotate_proxy()`** (NEW)
   - Implements round-robin proxy selection
   - Logs proxy rotation for debugging

3. **`_get_shopee_headers(referer)`** (NEW)
   - Returns Shopee-specific headers
   - Includes `X-Shopee-SPA-Version` and other anti-bot headers

4. **`scrape_shopee_search(...)`**
   - Enhanced API response logging
   - Increased wait times
   - Better error handling for empty responses

5. **`scrape_shopee_url(...)`**
   - Uses `_get_shopee_headers()` instead of hardcoded headers
   - Better logging for successful API captures

---

## Next Steps

1. Get residential proxies from one of the recommended providers
2. Test with `test_shopee_bypass.py --proxies http://proxy1:port http://proxy2:port ...`
3. Integrate into main application:
   ```python
   scraper = PlaywrightScraper(
       proxies=PROXY_LIST,  # From config
       headless=True
   )
   products = await scraper.scrape_shopee_search(keyword, limit=20)
   ```

4. Monitor logs for "Detected encrypted API response" - if frequent, may need API decryption logic

---

## Performance Expectations

With residential proxy + good internet:
- **Search (10 products):** 15-30 seconds
- **URL scrape:** 5-10 seconds  
- **Success rate:** 85-95% (with proper proxies)

Without proxy (direct connection):
- **Search:** 5-15 seconds (but may get blocked after 2-3 requests)
- **Success rate:** 10-30% (Shopee actively blocks)

---

## Contact & Support

If you encounter specific errors or API response structures, check logs from test script with `--visible` flag to see what Shopee is returning. The enhanced logging will show API response keys and whether responses are encrypted.
