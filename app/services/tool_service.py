import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from typing import List, Dict, Any, Union
import json
import ollama
from sqlalchemy.orm import Session

# NOTE: We don't import web_search/web_fetch from ollama anymore
# Using our own custom implementations (safe_web_search, safe_web_fetch) instead
# Using our own custom implementations (safe_web_search, safe_web_fetch) instead
from app.services.music_service import music_service
import os
import glob
from pathlib import Path
from app.services.image_generation_service import image_generation_service
from app.services.code_interpreter_service import CodeInterpreterService
from app.services.cloud_file_service import CloudFileService
from app.services.cloud_file_service import CloudFileService

logger = logging.getLogger(__name__)


from app.services.embedding_service import EmbeddingService
import numpy as np

# Global Caches to optimize search/fetch
GLOBAL_URL_CACHE = set()
GLOBAL_CONTENT_STORAGE = {}


def cosine_similarity(v1: np.ndarray, v2: np.ndarray) -> float:
    """Tính độ tương đồng cosine giữa hai vector"""
    if np.all(v1 == 0) or np.all(v2 == 0):
        return 0.0
    return float(np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2)))


def fallback_web_search(query: str, max_results: int = 5) -> str:
    """
    Fast web search using DuckDuckGo with Semantic Ranking.
    Returns JSON string with search results.
    """
    try:
        import ddgs

        logger.info(f"DuckDuckGo search for: {query}")

        # Get query embedding for semantic search
        query_embedding = EmbeddingService.get_embedding(query)

        raw_results = []
        # Fetch more results to filter down
        with ddgs.DDGS() as ddg_client:
            search_results = ddg_client.text(query, max_results=max_results * 3)

            for result in search_results:
                title = result.get("title", "No Title")
                href = result.get("href", "#")
                body = result.get("body", "")

                # Semantic Scoring
                content_for_embedding = f"{title}. {body}"
                doc_embedding = EmbeddingService.get_embedding(content_for_embedding)
                score = cosine_similarity(query_embedding, doc_embedding)

                raw_results.append(
                    {"title": title, "href": href, "body": body, "score": score}
                )

        if not raw_results:
            return "No results found."

        # Sort by semantic score descending
        raw_results.sort(key=lambda x: x["score"], reverse=True)
        top_results = raw_results[:max_results]

        # Format as Markdown for LLM readability
        markdown_results = ""
        for i, result in enumerate(top_results):
            markdown_results += f"## {result['title']} (Score: {result['score']:.2f})\n"
            markdown_results += f"URL: {result['href']}\n"
            markdown_results += f"Content: {result['body']}\n"
            markdown_results += "---\n"

        return markdown_results

    except Exception as e:
        logger.error(f"DuckDuckGo search error: {e}")
        return f"Error searching: {str(e)}"


def fallback_web_fetch(url: str, query: str = None) -> str:
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

        from bs4 import BeautifulSoup

        logger.info(f"Using fallback fetch for: {url}")

        response = None
        try:
            # Try using cloudscraper to bypass Cloudflare and other bot protections
            import cloudscraper

            scraper = cloudscraper.create_scraper(
                browser={"browser": "chrome", "platform": "windows", "desktop": True}
            )
            response = scraper.get(url, timeout=15)
        except ImportError:
            # Fallback to requests with robust headers if cloudscraper is not installed
            import requests

            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.5",
                "Accept-Encoding": "gzip, deflate, br",
                "DNT": "1",
                "Connection": "keep-alive",
                "Upgrade-Insecure-Requests": "1",
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
                "Sec-Fetch-User": "?1",
                "Cache-Control": "max-age=0",
            }
            response = requests.get(url, headers=headers, timeout=15)

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

        if query:
            # Semantic filtering if a query is provided
            logger.info(f"Filtering fetch results semantically for query: {query}")
            query_embedding = EmbeddingService.get_embedding(query)

            # Group lines into small chunks (e.g. 3 lines) to preserve local context
            chunks = []
            current_chunk = []
            for line in lines:
                current_chunk.append(line)
                if (
                    len(current_chunk) >= 5
                    or line.startswith("## ")
                    or line.startswith("```")
                ):
                    chunks.append("\\n".join(current_chunk))
                    current_chunk = []
            if current_chunk:
                chunks.append("\\n".join(current_chunk))

            scored_chunks = []
            for chunk in chunks:
                if len(chunk.strip()) > 30:  # Only score meaningful chunks
                    chunk_embedding = EmbeddingService.get_embedding(chunk)
                    score = cosine_similarity(query_embedding, chunk_embedding)
                    if score > 0.45:  # Relevance threshold
                        scored_chunks.append((score, chunk))

            # Sort chunks by relevance and keep top N
            scored_chunks.sort(key=lambda x: x[0], reverse=True)
            top_chunks = [
                c[1] for c in scored_chunks[:15]
            ]  # Keep top 15 most relevant chunks

            # Maintain original order if possible (simplified here by just joining top hits)
            cleaned_text = "\\n\\n...\\n\\n".join(top_chunks)
            if not cleaned_text:
                cleaned_text = (
                    "Nội dung trang web không có thông tin liên quan đến câu hỏi theo đánh giá ngữ nghĩa. Dưới đây là phần đầu trang:\\n"
                    + "\\n".join(lines[:20])
                )
        else:
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


def safe_web_fetch(url: str, query: str = None) -> str:
    """
    Web fetch using BeautifulSoup4 for clean text extraction, with optional semantic filtering.
    """
    return fallback_web_fetch(url, query)


def read_file_server(path: str, user_id: int = None) -> str:
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


from app.services.canvas_service import canvas_service


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
            "get_current_playing": music_queue_service.get_current_playing,
            # Legacy/Unsafe tools - potentially deprecate or restrict?
            # For now keeping them but adding cloud tools
            # Legacy/Unsafe tools - Redirected to Cloud for security/consistency
            "read_file": read_file_server,
            "search_file": self._cloud_search_file_wrapper,
            "create_file": self._cloud_create_file_wrapper,  # Create still cloud for safety? Or local? Let's keep create cloud for now unless asked.
            # New Cloud Tools
            "cloud_list_files": self._cloud_list_files_wrapper,
            "cloud_read_file": self._cloud_read_file_wrapper,
            "cloud_create_file": self._cloud_create_file_wrapper,
            "cloud_delete_file": self._cloud_delete_file_wrapper,
            "cloud_create_folder": self._cloud_create_folder_wrapper,
            "generate_image": self._generate_image_sync,
            "create_canvas": self._create_canvas_wrapper,
            "update_canvas": self._update_canvas_wrapper,
            "read_canvas": self._read_canvas_wrapper,
            "execute_python": CodeInterpreterService.execute_python,
        }

    # --- Cloud File Wrappers ---
    def _get_user_id(self, user_id: int = None):
        if user_id is None:
            raise ValueError("User ID required for cloud file operations")
        return user_id

    def _cloud_list_files_wrapper(self, directory: str = "/", user_id: int = None):
        try:
            uid = self._get_user_id(user_id)
            files = CloudFileService.list_files(uid, directory)
            return json.dumps(files, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"error": str(e)}, ensure_ascii=False)

    def _cloud_search_file_wrapper(
        self, query: str, directory: str = None, user_id: int = None
    ):
        try:
            uid = self._get_user_id(user_id)
            # If directory is provided, it's ignored for now as search is recursive from root,
            # or we could filter results. For simplicity, ignore directory arg or assume it's part of query.
            files = CloudFileService.search_files(uid, query)
            return json.dumps(files, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"error": str(e)}, ensure_ascii=False)

    def _cloud_read_file_wrapper(self, path: str, user_id: int = None):
        try:
            uid = self._get_user_id(user_id)
            content = CloudFileService.read_file(uid, path)
            return content  # Return raw content string
        except Exception as e:
            return f"Error: {str(e)}"

    def _cloud_create_file_wrapper(self, path: str, content: str, user_id: int = None):
        try:
            uid = self._get_user_id(user_id)
            result = CloudFileService.create_file(uid, path, content)
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"error": str(e)}, ensure_ascii=False)

    def _cloud_delete_file_wrapper(self, path: str, user_id: int = None):
        try:
            uid = self._get_user_id(user_id)
            # Try file delete first, then folder delete if needed?
            # User asked for "delete (all)", so let's check path type or try both?
            # Service has separate methods. Let's expose both or a smart delete?
            # For header simplicity, let's try delete_file, if 'IsADirectory', try delete_folder
            try:
                result = CloudFileService.delete_file(uid, path)
            except BlockingIOError:
                # Directory not empty
                raise ValueError(
                    f"Directory {path} is not empty. Use cloud_delete_folder? Or we assume this tool deletes files only?"
                )
            except IsADirectoryError:
                # It's a directory, use delete_folder (recursive)
                result = CloudFileService.delete_folder(uid, path)

            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"error": str(e)}, ensure_ascii=False)

    def _cloud_create_folder_wrapper(self, path: str, user_id: int = None):
        try:
            uid = self._get_user_id(user_id)
            result = CloudFileService.create_folder(uid, path)
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"error": str(e)}, ensure_ascii=False)

    def _create_canvas_wrapper(
        self,
        title: str,
        content: str,
        type: str = "markdown",
        user_id: int = None,
        db: Session = None,
    ):
        if user_id is None:
            return json.dumps(
                {"error": "User ID required for canvas operations"}, ensure_ascii=False
            )
        result = canvas_service.create_canvas(user_id, title, content, type, db)
        if result:
            return json.dumps(
                {"success": True, "canvas": {"id": result.id, "title": result.title}},
                ensure_ascii=False,
            )
        return json.dumps({"error": "Failed to create canvas"}, ensure_ascii=False)

    def _update_canvas_wrapper(
        self,
        canvas_id: int,
        content: str = None,
        title: str = None,
        user_id: int = None,
        db: Session = None,
    ):
        if user_id is None:
            return json.dumps(
                {"error": "User ID required for canvas operations"}, ensure_ascii=False
            )
        result = canvas_service.update_canvas(canvas_id, user_id, content, title, db)
        if result:
            return json.dumps(
                {
                    "success": True,
                    "message": "Canvas updated",
                    "canvas": {"id": result.id, "title": result.title},
                },
                ensure_ascii=False,
            )
        return json.dumps(
            {"error": "Failed to update canvas or not found"}, ensure_ascii=False
        )

    def _read_canvas_wrapper(
        self, canvas_id: int, user_id: int = None, db: Session = None
    ):
        if user_id is None:
            return json.dumps(
                {"error": "User ID required for canvas operations"}, ensure_ascii=False
            )
        result = canvas_service.get_canvas(canvas_id, user_id, db)
        if result:
            return json.dumps(
                {
                    "id": result.id,
                    "title": result.title,
                    "content": result.content,
                    "type": result.type,
                },
                ensure_ascii=False,
            )
        return json.dumps({"error": "Canvas not found"}, ensure_ascii=False)

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
                    "description": "Search the web for information. PROACTIVELY use this for any query needing current/external data (news, facts, docs, errors). Do not hesitate.",
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
                            },
                            "query": {
                                "type": "string",
                                "description": "Optional original question or query to filter the extracted content (e.g., 'What are the main features mentioned here?').",
                            },
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
                    "name": "cloud_list_files",
                    "description": "List files and directories in your secure cloud storage. Use this to see what files you have access to.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "directory": {
                                "type": "string",
                                "description": "Directory to list (default: '/')",
                            }
                        },
                        "required": [],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "cloud_read_file",
                    "description": "Read the content of a file from your cloud storage.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path to the file (relative to cloud root, e.g., 'notes/plan.txt')",
                            }
                        },
                        "required": ["path"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "cloud_create_file",
                    "description": "Create or overwrite a file in your cloud storage with new content.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path to the file (e.g., 'reports/feb.txt')",
                            },
                            "content": {
                                "type": "string",
                                "description": "The content to write to the file.",
                            },
                        },
                        "required": ["path", "content"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "cloud_delete_file",
                    "description": "Delete a file or directory from your cloud storage. BE CAREFUL: Deleting a directory is recursive.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path to delete.",
                            }
                        },
                        "required": ["path"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "cloud_create_folder",
                    "description": "Create a new directory in your cloud storage.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path for the new folder.",
                            }
                        },
                        "required": ["path"],
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
                    "description": "Generate an image using Stable Diffusion. ONLY use when user EXPLICITLY asks to create, draw, or generate an image. Do NOT use this for informational queries. You MUST convert the user's description into a detailed, ENGLISH, comma-separated tag-based prompt suitable for Stable Diffusion. After success, respond naturally without showing file paths - just confirm the image was created.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "prompt": {
                                "type": "string",
                                "description": "ENGLISH comma-separated tags for Stable Diffusion. IMPORTANT: Start with quantity prefix like '1girl', '1boy', '1cat', '2dogs', etc. Example: '1girl, solo, long hair, blue eyes, school uniform, smile, standing, cherry blossom, outdoors, masterpiece, best quality, highly detailed'. Always include: 1) quantity prefix (1girl/1boy/1cat/etc), 2) subject details, 3) quality tags (masterpiece, best quality). Translate non-English to English.",
                            },
                            "size": {
                                "type": "string",
                                "description": "Image size. Options: 'square' (768x768, default), 'landscape' (768x512), 'portrait' (512x768). Use 'square' for general purpose, 'landscape' for scenery, 'portrait' for people/characters. If user asks for 1024 or 'large', you can also specific '1024x1024'.",
                            },
                            "seed": {
                                "type": "integer",
                                "description": "Optional seed number. To EDIT an image, use the SAME SEED from the previous result and modify the prompt.",
                            },
                        },
                        "required": ["prompt"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "create_canvas",
                    "description": "Create a new canvas. USE ONLY when explicitly requested (e.g. 'create canvas') or for very long artifacts user wants to save.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "title": {
                                "type": "string",
                                "description": "Title of the canvas",
                            },
                            "content": {
                                "type": "string",
                                "description": "The full content (Markdown or Code).",
                            },
                            "type": {
                                "type": "string",
                                "description": "Type of content: 'markdown' or 'code' (default: markdown)",
                                "enum": ["markdown", "code"],
                            },
                        },
                        "required": ["title", "content"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "update_canvas",
                    "description": "Update an existing canvas content.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "canvas_id": {
                                "type": "integer",
                                "description": "ID of the canvas to update",
                            },
                            "content": {
                                "type": "string",
                                "description": "New content (optional)",
                            },
                            "title": {
                                "type": "string",
                                "description": "New title (optional)",
                            },
                        },
                        "required": ["canvas_id"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "read_canvas",
                    "description": "Read content of a canvas.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "canvas_id": {
                                "type": "integer",
                                "description": "ID of the canvas to read",
                            },
                        },
                        "required": ["canvas_id"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "execute_python",
                    "description": "Execute Python code. Use this for calculations, data processing, date/time logic, or any task where code is more accurate than LLM generation. The code runs in a temporary file. STDOUT and STDERR are captured.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "code": {
                                "type": "string",
                                "description": "Valid Python code to execute.",
                            }
                        },
                        "required": ["code"],
                    },
                },
            },
        ]

    def execute_tool(
        self,
        tool_name: str,
        args: Union[str, Dict[str, Any]],
        context: Dict[str, Any] = None,
    ) -> Dict[str, Any]:
        """Execute a tool by name with arguments and optional context"""
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

            # Inject context into args if needed (e.g. user_id for canvas tools)
            if context and isinstance(tool_args, dict):
                if "user_id" in context:
                    # Check if tool needs user_id (simple check by name for now)
                    if tool_name in [
                        "create_canvas",
                        "update_canvas",
                        "read_canvas",
                        "list_canvases",
                        "delete_canvas",
                        "delete_canvas",
                        "read_file",
                        "create_file",
                        "search_file",
                        "cloud_list_files",
                        "cloud_read_file",
                        "cloud_create_file",
                        "cloud_delete_file",
                        "cloud_create_folder",
                    ]:
                        tool_args["user_id"] = context["user_id"]

                if "db" in context:
                    if tool_name in [
                        "create_canvas",
                        "update_canvas",
                        "read_canvas",
                    ]:
                        tool_args["db"] = context["db"]

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
        self,
        tool_name: str,
        args: Union[str, Dict[str, Any]],
        context: Dict[str, Any] = None,
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

            # Inject context into args if needed
            if context and isinstance(tool_args, dict):
                if "user_id" in context:
                    if tool_name in [
                        "create_canvas",
                        "update_canvas",
                        "read_canvas",
                        "list_canvases",
                        "delete_canvas",
                        "delete_canvas",
                        "read_file",
                        "create_file",
                        "search_file",
                        "cloud_list_files",
                        "cloud_read_file",
                        "cloud_create_file",
                        "cloud_delete_file",
                        "cloud_create_folder",
                    ]:
                        tool_args["user_id"] = context["user_id"]

                if "db" in context:
                    if tool_name in [
                        "create_canvas",
                        "update_canvas",
                        "read_canvas",
                    ]:
                        tool_args["db"] = context["db"]

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
