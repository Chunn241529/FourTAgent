import sys
import os

# Add app to path
sys.path.append(os.getcwd())

from app.services.tool_service import safe_web_fetch

url = "https://ollama.com/library/qwen3.5"
print(f"Fetching {url}...")
try:
    content = safe_web_fetch(url)
    print(f"--- START CONTENT ({len(content)} chars) ---")
    print(content)
    print("--- END CONTENT ---")
except Exception as e:
    print(f"Error: {e}")
