import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from typing import List, Dict, Any, Union
import json
import ollama

# NOTE: We don't import web_search/web_fetch from ollama anymore
# Using our own custom implementations (safe_web_search, safe_web_fetch) instead

logger = logging.getLogger(__name__)


def fallback_web_search(query: str, max_results: int = 10) -> str:
    """
    Fallback web search using DuckDuckGo when ollama web_search fails.
    Automatically translates Vietnamese queries to English for better results.
    Returns JSON string with search results.
    """
    try:
        import ddgs

        logger.info(f"Using DuckDuckGo fallback search for: {query}")

        # Translate to English if query contains Vietnamese
        # Simple heuristic: check for Vietnamese characters
        has_vietnamese = any(ord(c) > 127 for c in query)

        if has_vietnamese:
            try:
                # Use LLM to create concise English search query
                translate_response = ollama.chat(
                    model="4T-S",
                    messages=[
                        {
                            "role": "user",
                            "content": f"Convert this Vietnamese query to a concise English search query. Use keywords and important phrases only. Output ONLY the English query, no explanations:\n\n{query}",
                        }
                    ],
                    options={"temperature": 0.1},
                )
                english_query = (
                    translate_response["message"]["content"].strip().strip('"')
                )
                logger.info(f"Optimized query: {english_query}")
            except Exception as e:
                logger.warning(f"Query optimization failed: {e}, using original query")
                english_query = query
        else:
            # For English queries, still optimize to make them concise
            try:
                optimize_response = ollama.chat(
                    model="4T-S",
                    messages=[
                        {
                            "role": "user",
                            "content": f"Convert this to a concise search query. Use keywords and important phrases only. Output ONLY the optimized query, no explanations:\n\n{query}",
                        }
                    ],
                    options={"temperature": 0.1},
                )
                english_query = (
                    optimize_response["message"]["content"].strip().strip('"')
                )
                logger.info(f"Optimized query: {english_query}")
            except Exception as e:
                logger.warning(f"Query optimization failed: {e}, using original query")
                english_query = query

        results = []
        with ddgs.DDGS() as ddg_client:
            search_results = ddg_client.text(english_query, max_results=max_results)

            for result in search_results:
                results.append(
                    {
                        "title": result.get("title", ""),
                        "url": result.get("href", ""),
                        "content": result.get("body", ""),
                    }
                )

        return json.dumps({"results": results}, ensure_ascii=False)

    except Exception as e:
        logger.error(f"DuckDuckGo search error: {e}")
        return json.dumps({"results": [], "error": str(e)}, ensure_ascii=False)


def fallback_web_fetch(url: str) -> str:
    """
    Fallback web fetch using requests + BeautifulSoup when ollama web_fetch fails.
    Returns cleaned text content from the URL with quality extraction.
    """
    try:
        import requests
        from bs4 import BeautifulSoup

        logger.info(f"Using requests+BS4 fallback fetch for: {url}")

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
            # Include: paragraphs, headings, lists, tables, code blocks, blockquotes, definition lists
            content_tags = main_content.find_all(
                [
                    "p",
                    "h1",
                    "h2",
                    "h3",
                    "h4",
                    "h5",
                    "h6",  # Text and headings
                    "li",
                    "ul",
                    "ol",  # Lists
                    "table",
                    "tr",
                    "td",
                    "th",  # Tables
                    "pre",
                    "code",  # Code blocks
                    "blockquote",  # Quotes
                    "dl",
                    "dt",
                    "dd",  # Definition lists
                    "div",  # Some content might be in divs
                ]
            )

            text_parts = []
            for tag in content_tags:
                text = tag.get_text(strip=True)
                if text and len(text) > 10:  # Filter out very short snippets
                    # Add context for special tags
                    if tag.name in ["h1", "h2", "h3"]:
                        text_parts.append(f"\n## {text}\n")
                    elif tag.name == "code" and tag.parent.name == "pre":
                        text_parts.append(f"\n```\n{text}\n```\n")
                    elif tag.name == "blockquote":
                        text_parts.append(f"\n> {text}\n")
                    elif tag.name in ["table", "tr"]:
                        # Keep table structure hint
                        text_parts.append(f"[Table] {text}")
                    else:
                        text_parts.append(text)

            text_content = "\n".join(text_parts)
        else:
            text_content = soup.get_text(strip=True)

        # Clean up excessive whitespace
        lines = [line.strip() for line in text_content.split("\n") if line.strip()]
        cleaned_text = "\n".join(lines)

        # Limit to reasonable size (increased from 10k to 15k for richer content)
        if len(cleaned_text) > 15000:
            cleaned_text = cleaned_text[:15000] + "\n\n...[Content truncated]"

        return cleaned_text

    except Exception as e:
        logger.error(f"Fallback fetch error for {url}: {e}")
        return f"Error fetching content: {str(e)}"


def safe_web_search(query: str) -> str:
    """
    Web search using DuckDuckGo with Vietnamese translation support.
    """
    return fallback_web_search(query)


def safe_web_fetch(url: str) -> str:
    """
    Web fetch using BeautifulSoup4 for clean text extraction.
    """
    return fallback_web_fetch(url)


class ToolService:
    def __init__(self, max_workers: int = 4):
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.tools_map = {
            "web_search": safe_web_search,
            "web_fetch": safe_web_fetch,
        }

    def get_tools(self) -> List[Any]:
        """
        Return list of custom tool definitions for the model.
        Using our own implementations instead of ollama's.
        """
        return [
            {
                "type": "function",
                "function": {
                    "name": "web_search",
                    "description": "Search the web for information using DuckDuckGo. Returns a list of search results with titles, URLs, and snippets. IMPORTANT: Always use CONCISE ENGLISH KEYWORDS for the query (e.g., 'Python install Ubuntu' instead of 'How to install Python on Ubuntu').",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The search query in CONCISE ENGLISH KEYWORDS (e.g., 'machine learning tutorial', 'Python error fix')",
                            }
                        },
                        "required": ["query"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "web_fetch",
                    "description": "Fetch and extract clean text content from a URL using BeautifulSoup. Returns the main content of the page.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "url": {
                                "type": "string",
                                "description": "The URL to fetch content from",
                            }
                        },
                        "required": ["url"],
                    },
                },
            },
        ]

    def execute_tool(
        self, tool_name: str, args: Union[str, Dict[str, Any]]
    ) -> Dict[str, Any]:
        """Execute a tool by name with arguments"""
        try:
            if isinstance(args, str):
                try:
                    tool_args = json.loads(args)
                except json.JSONDecodeError:
                    # If args is a string but not JSON, it might be a direct string argument (unlikely for these tools but good for safety)
                    # However, web_search and web_fetch expect kwargs.
                    # Let's assume it's a malformed JSON or just pass as is if the tool supports it?
                    # For now, let's stick to the logic in chat_service which tries to load JSON.
                    tool_args = args
            else:
                tool_args = args

            if tool_name not in self.tools_map:
                return {"error": f"Tool {tool_name} not found", "result": None}

            tool_func = self.tools_map[tool_name]

            # Execute in thread pool
            future = self.executor.submit(tool_func, **tool_args)
            result = future.result()

            return {
                "error": None,
                "result": result,
                "tool_name": tool_name,
                "args": tool_args,
            }

        except Exception as e:
            logger.error(f"Error executing tool {tool_name}: {e}")
            return {"error": str(e), "result": None, "tool_name": tool_name}

    async def execute_tool_async(
        self, tool_name: str, args: Union[str, Dict[str, Any]]
    ) -> Dict[str, Any]:
        """Execute a tool asynchronously (using thread pool for sync underlying tools)"""
        try:
            if isinstance(args, str):
                try:
                    tool_args = json.loads(args)
                except json.JSONDecodeError:
                    tool_args = args
            else:
                tool_args = args

            if tool_name not in self.tools_map:
                return {"error": f"Tool {tool_name} not found", "result": None}

            tool_func = self.tools_map[tool_name]

            # Execute sync function in thread pool to avoid blocking event loop
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                self.executor, lambda: tool_func(**tool_args)
            )

            return {
                "error": None,
                "result": result,
                "tool_name": tool_name,
                "args": tool_args,
            }

        except Exception as e:
            logger.error(f"Error executing tool async {tool_name}: {e}")
            return {"error": str(e), "result": None, "tool_name": tool_name}
