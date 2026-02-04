import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from typing import List, Dict, Any, Union
import json
import ollama

# NOTE: We don't import web_search/web_fetch from ollama anymore
# Using our own custom implementations (safe_web_search, safe_web_fetch) instead
# Using our own custom implementations (safe_web_search, safe_web_fetch) instead
from app.services.music_service import music_service
import os
import glob
from pathlib import Path
from app.services.image_generation_service import image_generation_service

logger = logging.getLogger(__name__)


# Global Caches to optimize search/fetch
GLOBAL_URL_CACHE = set()
GLOBAL_CONTENT_STORAGE = {}


def fallback_web_search(query: str, max_results: int = 3) -> str:
    """
    Fast web search using DuckDuckGo.
    Returns JSON string with search results.
    """
    try:
        import ddgs

        logger.info(f"DuckDuckGo search for: {query}")

        results = []
        with ddgs.DDGS() as ddg_client:
            search_results = ddg_client.text(query, max_results=max_results)

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
    Uses GLOBAL_URL_CACHE to prevent re-fetching.
    """
    try:
        # Check cache first
        if url in GLOBAL_URL_CACHE and url in GLOBAL_CONTENT_STORAGE:
            logger.info(f"Using cached content for: {url}")
            return GLOBAL_CONTENT_STORAGE[url]

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

        # Limit to reasonable size (reduced for faster processing)
        if len(cleaned_text) > 8000:
            cleaned_text = cleaned_text[:8000] + "\n\n...[Content truncated]"

        # Cache the result (Simple LRU-like: if big, clear half)
        if len(GLOBAL_URL_CACHE) > 50:
            # Prevent memory leak by clearing old cache
            # Ideally we'd remove oldest, but for simple global set/dict, clearing or partial clear is fine
            logger.info(
                "Global URL Cache hit limit (50), clearing cache to free memory."
            )
            GLOBAL_URL_CACHE.clear()
            GLOBAL_CONTENT_STORAGE.clear()

        GLOBAL_URL_CACHE.add(url)
        GLOBAL_CONTENT_STORAGE[url] = cleaned_text

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


def read_file_server(path: str) -> str:
    """
    Read content of a local file.
    """
    try:
        # Normalize path
        user_home = os.path.expanduser("~")
        if path.startswith("~/"):
            path = path.replace("~/", f"{user_home}/")

        # Security check: prevent directory traversal issues if needed,
        # but for local tool we assume trusted user.

        if not os.path.exists(path):
            return f"Error: File not found at {path}"

        if not os.path.isfile(path):
            return f"Error: Path {path} is not a file"

        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        return content
    except Exception as e:
        logger.error(f"Error reading file {path}: {e}")
        return f"Error reading file: {str(e)}"


def search_file_server(query: str, directory: str = None) -> str:
    """
    Search for files matching query (glob pattern or name substring).
    """
    try:
        user_home = os.path.expanduser("~")
        search_roots = [
            os.path.join(user_home, "Documents"),
            os.path.join(user_home, "Downloads"),
            os.path.join(user_home, "Desktop"),
        ]

        if directory:
            if directory.startswith("~/"):
                directory = directory.replace("~/", f"{user_home}/")
            search_roots = [directory]

        results = []

        # Simple glob if query contains wildcard
        pattern = query if "*" in query else f"*{query}*"

        for root in search_roots:
            if not os.path.exists(root):
                continue

            # Use os.walk for recursive search
            for dirpath, dirnames, filenames in os.walk(root):
                # Check filenames
                for filename in filenames:
                    if (
                        query.lower() in filename.lower()
                    ):  # Simple substring match case-insensitive
                        results.append(os.path.join(dirpath, filename))
                    elif Path(filename).match(query):  # Glob match
                        results.append(os.path.join(dirpath, filename))

                if len(results) > 20:  # Limit results
                    break

            if len(results) > 20:
                break

        if not results:
            return "No files found matching the query."

        return json.dumps(
            {"files": results[:20]}, ensure_ascii=False
        )  # Return proper JSON list

    except Exception as e:
        logger.error(f"Error searching file {query}: {e}")
        return f"Error searching files: {str(e)}"


def create_file_server(path: str, content: str) -> str:
    """
    Create a file with content.
    """
    try:
        user_home = os.path.expanduser("~")

        # Determine path
        target_path = path
        if "/" not in path:
            # Default to Downloads if no path specified
            target_path = os.path.join(user_home, "Downloads", path)
        elif path.startswith("~/"):
            target_path = path.replace("~/", f"{user_home}/")

        # Ensure dir exists
        directory = os.path.dirname(target_path)
        if directory and not os.path.exists(directory):
            os.makedirs(directory, exist_ok=True)

        with open(target_path, "w", encoding="utf-8") as f:
            f.write(content)

        return f"Success: File created at {target_path}"

    except Exception as e:
        logger.error(f"Error creating file {path}: {e}")
        return f"Error creating file: {str(e)}"


from app.services.music_queue_service import music_queue_service

# ... (imports)


class ToolService:
    def __init__(self, max_workers: int = 4):
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.tools_map = {
            "web_search": safe_web_search,
            "web_fetch": safe_web_fetch,
            "search_music": music_service.search_music,
            "play_music": music_service.play_music,
            "stop_music": music_queue_service.stop_music,  # Use queue service for client command
            "add_to_queue": music_queue_service.add_to_queue,
            "next_music": music_queue_service.next_music,
            "previous_music": music_queue_service.previous_music,
            "pause_music": music_queue_service.pause_music,
            "resume_music": music_queue_service.resume_music,
            "get_current_playing": music_queue_service.get_current_playing,
            "read_file": read_file_server,
            "search_file": search_file_server,
            "create_file": create_file_server,
            "generate_image": self._generate_image_sync,
        }

    def _generate_image_sync(
        self,
        prompt: str = "",
        description: str = "",
        size: str = "768x768",
        seed: int = None,
    ) -> str:
        """
        Synchronous wrapper for async image generation.
        Runs the async function in a new event loop.
        'prompt' is the new parameter (English SD tags from LLM).
        'description' kept for backward compatibility.
        Returns full result (chat_service will filter for LLM).
        """
        # Use prompt if provided, else fallback to description
        sd_prompt = prompt if prompt else description

        try:
            # Run async function in sync context
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                result = loop.run_until_complete(
                    image_generation_service.generate_image_direct(
                        sd_prompt, size, seed=seed
                    )
                )
            finally:
                loop.close()

            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            logger.error(f"Error in generate_image: {e}")
            return json.dumps({"error": str(e)}, ensure_ascii=False)

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
                    "description": "Search the web for information. Use this when you need current news, facts, technical documentation, or knowledge outside your training data. Prefer English keywords for technical/international topics.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Search keywords (e.g., 'Python install Ubuntu', 'today news').",
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
                    "description": "Fetch content from a specific URL to read its details. Useful when a search result looks promising but needs full reading.",
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
            {
                "type": "function",
                "function": {
                    "name": "search_music",
                    "description": "Search for music tracks. Returns a list of tracks with titles and URLs. REQUIRED step before playing music unless you already have a URL.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Keywords (e.g., 'Lạc Trôi', 'Chill music')",
                            }
                        },
                        "required": ["query"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "play_music",
                    "description": "Play a specific YouTube URL. Call this immediately if you find a high-confidence match from `search_music`. This replaces the current track.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "url": {
                                "type": "string",
                                "description": "The YouTube video URL to play",
                            }
                        },
                        "required": ["url"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "add_to_queue",
                    "description": "Add a music track to the queue instead of playing immediately.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "url": {
                                "type": "string",
                                "description": "The YouTube video URL to add",
                            }
                        },
                        "required": ["url"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "stop_music",
                    "description": "Stop playback and clear the standard music player.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "pause_music",
                    "description": "Pause playback.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "resume_music",
                    "description": "Resume playback.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "next_music",
                    "description": "Skip to next track.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "previous_music",
                    "description": "Go back to previous track.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "get_current_playing",
                    "description": "Get information about the currently playing track (title, artist, duration). Use this to know what's playing now.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "read_file",
                    "description": "Read content of a local file. Use this when you need to analyze, summarize, or explain a specific file found via `search_file`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Full path to the file.",
                            }
                        },
                        "required": ["path"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "search_file",
                    "description": "Search for files on the user's system (Linux). Useful for finding documents, code, or data.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Filename pattern (e.g., '*.pdf', 'budget_report').",
                            },
                        },
                        "required": ["query"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "create_file",
                    "description": "Create a new file with content. Useful for saving notes, code, or reports.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Filename or Path.",
                            },
                            "content": {
                                "type": "string",
                                "description": "Content to write.",
                            },
                        },
                        "required": ["path", "content"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "deep_search",
                    "description": "Perform in-depth research on a complex topic. Generates a detailed report from multiple sources. Use only for complex requests.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "topic": {
                                "type": "string",
                                "description": "Topic to research.",
                            }
                        },
                        "required": ["topic"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "generate_image",
                    "description": "Generate an image using Stable Diffusion. You MUST convert the user's description into a detailed, ENGLISH, comma-separated tag-based prompt suitable for Stable Diffusion. After success, respond naturally without showing file paths - just confirm the image was created.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "prompt": {
                                "type": "string",
                                "description": "ENGLISH comma-separated tags for Stable Diffusion. IMPORTANT: Start with quantity prefix like '1girl', '1boy', '1cat', '2dogs', etc. Example: '1girl, solo, long hair, blue eyes, school uniform, smile, standing, cherry blossom, outdoors, masterpiece, best quality, highly detailed'. Always include: 1) quantity prefix (1girl/1cat/etc), 2) subject details, 3) quality tags (masterpiece, best quality). Translate non-English to English.",
                            },
                            "size": {
                                "type": "string",
                                "description": "Image size. Use '512x512' for small, '768x768' for medium/default, '1024x1024' for large. If user says 'lớn'/'big'/'high quality' use 1024x1024.",
                            },
                            "seed": {
                                "type": "integer",
                                "description": "Optional seed for reproducibility. System uses this automatically for edits.",
                            },
                        },
                        "required": ["prompt"],
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
