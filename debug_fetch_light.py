import requests
from bs4 import BeautifulSoup
import logging

# Mock logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

url = "https://ollama.com/library/qwen3.5"
print(f"Fetching {url}...")

try:
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }

    response = requests.get(url, headers=headers, timeout=10)
    response.raise_for_status()

    soup = BeautifulSoup(response.content, "html.parser")

    # Remove unwanted tags
    for tag in soup(
        [
            "script",
            "style",
            "nav",
            "footer",
            "header",
            "aside",
            "iframe",
            "noscript",
        ]
    ):
        tag.decompose()

    # Try to find main content
    main_content = soup.find("main") or soup.find("article") or soup.find("body")

    if main_content:
        # Extract text from various content tags
        content_tags = main_content.find_all(
            [
                "p",
                "h1",
                "h2",
                "h3",
                "h4",
                "h5",
                "h6",
                "li",
                "ul",
                "ol",
                "table",
                "tr",
                "td",
                "th",
                "pre",
                "code",
                "blockquote",
                "dl",
                "dt",
                "dd",
                "div",
            ]
        )

        text_parts = []
        for tag in content_tags:
            text = tag.get_text(strip=True)
            if text and len(text) > 10:
                if tag.name in ["h1", "h2", "h3"]:
                    text_parts.append(f"\n## {text}\n")
                elif tag.name == "code" and tag.parent.name == "pre":
                    text_parts.append(f"\n```\n{text}\n```\n")
                elif tag.name == "blockquote":
                    text_parts.append(f"\n> {text}\n")
                elif tag.name in ["table", "tr"]:
                    text_parts.append(f"[Table] {text}")
                else:
                    text_parts.append(text)

        text_content = "\n".join(text_parts)
    else:
        text_content = soup.get_text(strip=True)

    # Clean up excessive whitespace
    lines = [line.strip() for line in text_content.split("\n") if line.strip()]
    cleaned_text = "\n".join(lines)

    # Simulate tool_service logic
    if not cleaned_text or len(cleaned_text) < 50:
        print(
            f"[System: No readable text content found at {url}. The page might be empty, require login, or contain mostly Javascript/Images.]"
        )
    else:
        if len(cleaned_text) > 8000:
            cleaned_text = cleaned_text[:8000] + "\n\n...[Content truncated]"
        print(f"--- START CONTENT ({len(cleaned_text)} chars) ---")
        print(cleaned_text[:500] + "...")
        print("--- END CONTENT ---")

except Exception as e:
    print(f"Error: {e}")
