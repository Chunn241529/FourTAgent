import re
import sys
import logging

# Mock logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _clean_chunk(text: str) -> str:
    """
    Cleans RAG chunks to prevent hallucination of past tool usage.
    Removes:
    - <<<...>>> UI markers
    - Tool calls like generate_image(...), web_search(...)
    """
    try:
        # 1. Remove UI Markers
        text = re.sub(r"<<<.*?>>>", "", text)

        # 2. Mask Tool Calls (Simple Heuristic for common patterns)
        # Replace `generate_image(...)` with `[Image Generation History]`
        text = re.sub(
            r"generate_image\s*\(.*?\)",
            "[Image Generation History]",
            text,
            flags=re.DOTALL,
        )
        text = re.sub(
            r"web_search\s*\(.*?\)", "[Web Search History]", text, flags=re.DOTALL
        )
        text = re.sub(
            r"web_fetch\s*\(.*?\)", "[Web Fetch History]", text, flags=re.DOTALL
        )
        return text
    except Exception as e:
        logger.error(f"Error cleaning chunk: {e}")
        return text


def test_rag_cleaning():
    print("Testing RAG Cleaning Logic...")

    # Test Case 1: UI Markers
    text1 = "Here is an image: <<<TOOL:generate_image:cat>>>. Do you like it?"
    cleaned1 = _clean_chunk(text1)
    print(f"\n[Test 1] UI Markers:\nOriginal: {text1}\nCleaned:  {cleaned1}")
    assert "<<<" not in cleaned1, "Failed to remove UI markers"

    # Test Case 2: generate_image call
    text2 = 'I will generate an image now. generate_image(prompt="a blue cat", size="1024x1024")'
    cleaned2 = _clean_chunk(text2)
    print(f"\n[Test 2] generate_image:\nOriginal: {text2}\nCleaned:  {cleaned2}")
    assert "generate_image" not in cleaned2, "Failed to mask generate_image"
    assert "[Image Generation History]" in cleaned2, "Failed to insert placeholder"

    # Test Case 3: web_search call
    text3 = 'Searching for info... web_search(query="latest news")'
    cleaned3 = _clean_chunk(text3)
    print(f"\n[Test 3] web_search:\nOriginal: {text3}\nCleaned:  {cleaned3}")
    assert "web_search" not in cleaned3, "Failed to mask web_search"

    # Test Case 4: Complex/Multiline
    text4 = """
    Step 1: <<<Thinking...>>>
    Step 2: web_search(query="python regex")
    Step 3: Done.
    """
    cleaned4 = _clean_chunk(text4)
    print(f"\n[Test 4] Multiline:\nOriginal: {text4}\nCleaned:  {cleaned4}")
    assert "<<<" not in cleaned4
    assert "web_search" not in cleaned4

    print("\n✅ All RAG cleaning tests passed!")


if __name__ == "__main__":
    test_rag_cleaning()
