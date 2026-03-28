"""
Chat LLM Fallback Router - Streaming Multi-Provider Router for Chat.

Unlike affiliate's LLMRouter (non-streaming, text-only), this router handles:
- Streaming responses (SSE-compatible async generators)
- Tool calling (converts between provider formats)
- Image/Vision inputs (base64)
- Thinking/reasoning tokens

Fallback chain (cloud-first, Ollama last):
  1. Groq (OpenAI-compatible)      → Streaming + Tools (fastest)
  2. Gemini (Google API)           → Streaming + Function Calling + Vision
  3. Cerebras (OpenAI-compatible)  → Streaming + Tools
  4. Cohere (v2 API)               → Streaming, text-only (no tools)
  5. Ollama (local, last resort)   → Full features (native)

All providers normalize their responses to Ollama-compatible chunk format,
so downstream code in chat_service.py needs ZERO changes.
"""

import os
import json
import logging
import aiohttp
import asyncio
from typing import List, Dict, Any, Optional, Union, AsyncGenerator
from dataclasses import dataclass

import ollama

logger = logging.getLogger(__name__)


# ============================================================
# Model Mapping: Ollama model name → cloud provider model name
# ============================================================

# Cloud provider model IDs (fixed — Lumina is Ollama-exclusive, NOT a cloud key)
CLOUD_MODELS = {
    "groq": "openai/gpt-oss-120b",
    "gemini": "gemini-2.0-flash",
    "cerebras": "gpt-oss-120b",
}


def _get_cloud_model(ollama_model: str, provider_name: str) -> str:
    """Get the cloud model ID for a given provider."""
    return CLOUD_MODELS.get(provider_name.lower(), "")


# ============================================================
# Tool Format Converters
# ============================================================


def _ollama_tools_to_openai(tools: Optional[List[Dict]]) -> Optional[List[Dict]]:
    """
    Convert Ollama tool definitions to OpenAI function calling format.
    Ollama tools: [{"type": "function", "function": {"name": ..., "description": ..., "parameters": ...}}]
    OpenAI tools: Same format (Ollama already uses OpenAI-compatible format).
    """
    if not tools:
        return None
    # Ollama tool format is already OpenAI-compatible
    return tools


def _ollama_tools_to_gemini(tools: Optional[List[Dict]]) -> Optional[List[Dict]]:
    """
    Convert Ollama tool definitions to Gemini function declarations format.
    Gemini: [{"function_declarations": [{"name": ..., "description": ..., "parameters": ...}]}]
    """
    if not tools:
        return None

    declarations = []
    for tool in tools:
        func = tool.get("function", {})
        decl = {
            "name": func.get("name", ""),
            "description": func.get("description", ""),
        }
        params = func.get("parameters")
        if params:
            decl["parameters"] = params
        declarations.append(decl)

    return [{"function_declarations": declarations}]


# ============================================================
# Message Format Converters
# ============================================================


def _ollama_messages_to_openai(messages: List[Dict]) -> List[Dict]:
    """
    Convert Ollama message format to OpenAI-compatible format.
    Main differences:
    - Ollama uses 'images' field for vision, OpenAI uses content array with image_url
    - Ollama tool messages have 'tool_name', OpenAI has 'name'
    """
    converted = []
    for msg in messages:
        new_msg = {"role": msg["role"], "content": msg.get("content", "")}

        # Handle images → convert to OpenAI multimodal format
        if "images" in msg and msg["images"]:
            content_parts = []
            if msg.get("content"):
                content_parts.append({"type": "text", "text": msg["content"]})
            for img_b64 in msg["images"]:
                content_parts.append(
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{img_b64}"},
                    }
                )
            new_msg["content"] = content_parts

        # Handle tool calls in assistant messages
        if msg.get("role") == "assistant" and msg.get("tool_calls"):
            openai_tool_calls = []
            for i, tc in enumerate(msg["tool_calls"]):
                func = tc.get("function", {})
                args = func.get("arguments", {})
                # OpenAI expects arguments as JSON string
                if isinstance(args, dict):
                    args = json.dumps(args)
                openai_tool_calls.append(
                    {
                        "id": tc.get("id", f"call_{i}"),
                        "type": "function",
                        "function": {
                            "name": func.get("name", ""),
                            "arguments": args,
                        },
                    }
                )
            new_msg["tool_calls"] = openai_tool_calls
            # OpenAI requires content to be null or string when tool_calls present
            if not new_msg.get("content"):
                new_msg["content"] = None

        # Handle tool response messages
        if msg.get("role") == "tool":
            new_msg["tool_call_id"] = msg.get("tool_call_id", "call_0")
            new_msg["name"] = msg.get("tool_name") or msg.get("name", "unknown")
            # Remove empty tool_call_id to avoid API errors
            if not new_msg["tool_call_id"]:
                new_msg["tool_call_id"] = "call_0"

        converted.append(new_msg)

    return converted


def _ollama_messages_to_gemini(messages: List[Dict]) -> tuple:
    """
    Convert Ollama messages to Gemini API format.
    Returns: (system_instruction, contents)

    Gemini uses different structure:
    - system_instruction is separate
    - contents: [{"role": "user"|"model", "parts": [{"text": ...}]}]
    - function calls/responses have special parts
    """
    system_instruction = None
    contents = []

    for msg in messages:
        role = msg.get("role", "user")

        if role == "system":
            system_instruction = msg.get("content", "")
            continue

        # Map roles: Ollama/OpenAI "assistant" → Gemini "model"
        gemini_role = "model" if role == "assistant" else "user"

        parts = []

        # Handle text content
        if msg.get("content"):
            parts.append({"text": msg["content"]})

        # Handle images
        if "images" in msg and msg["images"]:
            for img_b64 in msg["images"]:
                parts.append(
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": img_b64,
                        }
                    }
                )

        # Handle tool calls (assistant → function call)
        if role == "assistant" and msg.get("tool_calls"):
            for tc in msg["tool_calls"]:
                func = tc.get("function", {})
                args = func.get("arguments", {})
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        args = {}
                parts.append(
                    {"functionCall": {"name": func.get("name", ""), "args": args}}
                )

        # Handle tool response
        if role == "tool":
            tool_name = msg.get("tool_name") or msg.get("name", "unknown")
            content = msg.get("content", "")
            # Try to parse as JSON for structured response
            try:
                response_data = json.loads(content)
            except (json.JSONDecodeError, TypeError):
                response_data = {"result": content}
            parts.append(
                {
                    "functionResponse": {
                        "name": tool_name,
                        "response": response_data,
                    }
                }
            )
            gemini_role = "user"  # Gemini expects function responses from "user" side

        if parts:
            contents.append({"role": gemini_role, "parts": parts})

    return system_instruction, contents


# ============================================================
# Provider Implementations (Streaming)
# ============================================================


async def _stream_ollama(
    messages: List[Dict],
    tools: Optional[List[Dict]],
    model: str,
    temperature: float,
    num_ctx: int,
    think: Union[str, bool],
) -> AsyncGenerator[Dict[str, Any], None]:
    """Stream from Ollama (primary). Returns native Ollama format."""
    from app.services.chat.utils import get_client

    client = get_client()
    options = {"temperature": temperature, "num_ctx": num_ctx}

    stream = await client.chat(
        model=model,
        messages=messages,
        tools=tools,
        stream=True,
        options=options,
        think=think,
    )

    async for chunk in stream:
        yield chunk


async def _stream_openai_compatible(
    api_url: str,
    api_key: str,
    messages: List[Dict],
    tools: Optional[List[Dict]],
    model: str,
    temperature: float,
    provider_name: str,
    timeout: int = 60,
    think: Union[str, bool] = False,
) -> AsyncGenerator[Dict[str, Any], None]:
    """
    Stream from OpenAI-compatible APIs (Groq, Cerebras).
    Normalizes response chunks to Ollama format.
    """
    openai_messages = _ollama_messages_to_openai(messages)
    openai_tools = _ollama_tools_to_openai(tools)

    payload = {
        "model": model,
        "messages": openai_messages,
        "temperature": temperature,
        "max_tokens": 8192,
        "stream": True,
    }

    # Handle Reasoning Flags for compatible models (e.g. gpt-oss-120b)
    if model in ("openai/gpt-oss-120b", "gpt-oss-120b"):
        bool_think = think if isinstance(think, bool) else (str(think).lower() == "true")
        if bool_think:
            payload["include_reasoning"] = True
            payload["reasoning_effort"] = "high"
        else:
            payload["include_reasoning"] = False

    if openai_tools:
        payload["tools"] = openai_tools

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    # Track accumulated tool calls across stream chunks
    accumulated_tool_calls: Dict[int, Dict] = {}

    async with aiohttp.ClientSession() as session:
        async with session.post(
            api_url,
            json=payload,
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                error_text = await resp.text()
                raise Exception(
                    f"{provider_name} HTTP {resp.status}: {error_text[:300]}"
                )

            # Read SSE lines properly using readline()
            buffer = ""
            while True:
                raw = await resp.content.readline()
                if not raw:
                    break
                buffer += raw.decode("utf-8")
                # Process complete lines from buffer
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()

                    if not line or line == "data: [DONE]":
                        continue

                    if not line.startswith("data: "):
                        continue

                    try:
                        data = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue

                    choices = data.get("choices", [])
                    if not choices:
                        continue

                    delta = choices[0].get("delta", {})
                    finish_reason = choices[0].get("finish_reason")

                    # Build Ollama-compatible chunk
                    ollama_chunk = {"message": {}}

                    # Content
                    content = delta.get("content")
                    if content:
                        ollama_chunk["message"]["content"] = content

                    # Tool calls (streamed incrementally in OpenAI format)
                    if "tool_calls" in delta:
                        for tc_delta in delta["tool_calls"]:
                            idx = tc_delta.get("index", 0)
                            if idx not in accumulated_tool_calls:
                                accumulated_tool_calls[idx] = {
                                    "function": {
                                        "name": "",
                                        "arguments": "",
                                    },
                                    "id": tc_delta.get("id", f"call_{idx}"),
                                }

                            if "function" in tc_delta:
                                if "name" in tc_delta["function"]:
                                    accumulated_tool_calls[idx]["function"][
                                        "name"
                                    ] += tc_delta["function"]["name"]
                                if "arguments" in tc_delta["function"]:
                                    accumulated_tool_calls[idx]["function"][
                                        "arguments"
                                    ] += tc_delta["function"]["arguments"]

                    # Reasoning/thinking tokens (some providers support this)
                    reasoning_content = delta.get("reasoning_content") or delta.get(
                        "reasoning"
                    )
                    if reasoning_content:
                        ollama_chunk["message"]["reasoning_content"] = reasoning_content
                        # Also track for fallback
                        if not content:
                            # Some reasoning models send reasoning but no content
                            # We still need to yield so frontend shows thinking state
                            pass

                    # Emit content chunks immediately
                    if content:
                        yield ollama_chunk
                    elif reasoning_content:
                        # Yield reasoning with proper chunk structure so downstream processes it correctly
                        ollama_chunk["message"]["reasoning_content"] = reasoning_content
                        yield ollama_chunk

                    # On finish, emit accumulated tool calls
                    if finish_reason == "tool_calls" or (
                        finish_reason == "stop" and accumulated_tool_calls
                    ):
                        if accumulated_tool_calls:
                            # Convert accumulated args from JSON string to dict
                            final_tool_calls = []
                            for tc in accumulated_tool_calls.values():
                                args_str = tc["function"]["arguments"]
                                try:
                                    args = json.loads(args_str)
                                except json.JSONDecodeError:
                                    args = {}
                                final_tool_calls.append(
                                    {
                                        "function": {
                                            "name": tc["function"]["name"],
                                            "arguments": args,
                                        }
                                    }
                                )

                            yield {
                                "message": {
                                    "tool_calls": final_tool_calls,
                                    "content": "",
                                }
                            }
                            accumulated_tool_calls.clear()

    # Final done signal
    yield {"done": True, "message": {"content": ""}}


async def _stream_gemini(
    api_key: str,
    messages: List[Dict],
    tools: Optional[List[Dict]],
    model: str,
    temperature: float,
    timeout: int = 60,
    think: Union[str, bool] = False,
) -> AsyncGenerator[Dict[str, Any], None]:
    """
    Stream from Google Gemini API.
    Normalizes response chunks to Ollama format.
    """
    system_instruction, contents = _ollama_messages_to_gemini(messages)
    gemini_tools = _ollama_tools_to_gemini(tools)

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key={api_key}"

    payload: Dict[str, Any] = {
        "contents": contents,
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": 8192,
        },
    }

    if system_instruction:
        payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}

    if gemini_tools:
        payload["tools"] = gemini_tools

    async with aiohttp.ClientSession() as session:
        async with session.post(
            url,
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                error_text = await resp.text()
                raise Exception(f"Gemini HTTP {resp.status}: {error_text[:300]}")

            # Read SSE lines properly using readline()
            buffer = ""
            while True:
                raw = await resp.content.readline()
                if not raw:
                    break
                buffer += raw.decode("utf-8")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()

                    if not line or not line.startswith("data: "):
                        continue

                    try:
                        data = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue

                    candidates = data.get("candidates", [])
                    if not candidates:
                        continue

                    candidate = candidates[0]
                    content = candidate.get("content", {})
                    parts = content.get("parts", [])

                    for part in parts:
                        # Text content
                        if "text" in part:
                            yield {"message": {"content": part["text"]}}

                        # Function call
                        if "functionCall" in part:
                            fc = part["functionCall"]
                            yield {
                                "message": {
                                    "tool_calls": [
                                        {
                                            "function": {
                                                "name": fc.get("name", ""),
                                                "arguments": fc.get("args", {}),
                                            }
                                        }
                                    ],
                                    "content": "",
                                }
                            }

                        # Thinking/reasoning (Gemini 2.0 thinking models)
                        if "thought" in part:
                            yield {
                                "message": {"think": part["thought"]},
                                "think": part["thought"],
                            }

    # Final done signal
    yield {"done": True, "message": {"content": ""}}


async def _stream_cohere(
    api_key: str,
    messages: List[Dict],
    model: str,
    temperature: float,
    timeout: int = 60,
    think: Union[str, bool] = False,
) -> AsyncGenerator[Dict[str, Any], None]:
    """
    Stream from Cohere API (v2). Text-only, no tool support.
    Normalizes to Ollama format.
    """
    # Convert messages - strip tool/image content for text-only
    cohere_messages = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        # Skip tool messages entirely
        if role == "tool":
            continue

        # Strip images, add text note
        if "images" in msg and msg["images"]:
            content = f"[User attached an image]\n{content}"

        # Skip assistant messages with only tool calls
        if role == "assistant" and msg.get("tool_calls") and not content:
            continue

        cohere_messages.append({"role": role, "content": content})

    payload = {
        "model": model,
        "messages": cohere_messages,
        "temperature": temperature,
        "max_tokens": 4096,
        "stream": True,
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(
            "https://api.cohere.com/v2/chat",
            json=payload,
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=timeout),
        ) as resp:
            if resp.status != 200:
                error_text = await resp.text()
                raise Exception(f"Cohere HTTP {resp.status}: {error_text[:300]}")

            # Read SSE lines properly using readline()
            buffer = ""
            while True:
                raw = await resp.content.readline()
                if not raw:
                    break
                buffer += raw.decode("utf-8")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()

                    if not line or not line.startswith("data: "):
                        continue

                    if line == "data: [DONE]":
                        break

                    try:
                        data = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue

                    event_type = data.get("type", "")

                    # Content delta
                    if event_type == "content-delta":
                        delta = data.get("delta", {})
                        text = delta.get("message", {}).get("content", {}).get("text", "")
                        if text:
                            yield {"message": {"content": text}}

    # Final done signal
    yield {"done": True, "message": {"content": ""}}


# ============================================================
# Provider Configuration
# ============================================================


@dataclass
class ChatProvider:
    """Configuration for a chat LLM provider."""

    name: str
    enabled: bool
    supports_tools: bool
    supports_vision: bool
    api_key_env: str  # env var name for API key
    timeout: int = 60


def _get_providers() -> List[ChatProvider]:
    """Build the ordered list of providers. Cloud-first, Ollama last."""
    return [
        # --- Cloud providers first (primary) ---
        ChatProvider(
            name="Groq",
            enabled=bool(os.getenv("GROQ_API_KEY", "")),
            supports_tools=True,
            supports_vision=False,
            api_key_env="GROQ_API_KEY",
            timeout=60,
        ),
        ChatProvider(
            name="Gemini",
            enabled=bool(os.getenv("GEMINI_API_KEY", "")),
            supports_tools=True,
            supports_vision=True,
            api_key_env="GEMINI_API_KEY",
            timeout=60,
        ),
        ChatProvider(
            name="Cerebras",
            enabled=bool(os.getenv("CEREBRAS_API_KEY", "")),
            supports_tools=True,
            supports_vision=False,
            api_key_env="CEREBRAS_API_KEY",
            timeout=60,
        ),
        ChatProvider(
            name="Cohere",
            enabled=bool(os.getenv("COHERE_API_KEY", "")),
            supports_tools=False,  # Text-only fallback
            supports_vision=False,
            api_key_env="COHERE_API_KEY",
            timeout=60,
        ),
        # --- Ollama local (last resort) ---
        ChatProvider(
            name="Ollama",
            enabled=True,  # Always enabled as final fallback
            supports_tools=True,
            supports_vision=True,
            api_key_env="",
            timeout=120,
        ),
    ]


# ============================================================
# Main Router
# ============================================================


class ChatLLMRouter:
    """
    Multi-provider LLM router for Chat with STREAMING support.

    Streams Ollama-compatible chunks regardless of which provider is used.
    Downstream code needs zero changes.
    """

    def __init__(self):
        self.providers = _get_providers()
        active = [p.name for p in self.providers if p.enabled]
        logger.info(f"[ChatLLMRouter] Initialized with providers: {active}")

    def refresh_providers(self):
        """Re-check env vars and update provider availability."""
        self.providers = _get_providers()

    async def _classify_needs_tools(
        self, messages: List[Dict], tools: Optional[List[Dict]]
    ) -> bool:
        """Extract last user message and classify via standalone function."""
        if not tools:
            return False

        # Extract last user message only — no history, no RAG
        last_user_msg = ""
        for msg in reversed(messages):
            if msg.get("role") == "user":
                content = msg.get("content", "")
                if isinstance(content, str):
                    last_user_msg = content
                elif isinstance(content, list):
                    last_user_msg = " ".join(
                        p.get("text", "") for p in content if isinstance(p, dict)
                    )
                break

        if not last_user_msg:
            return False

        # Standalone classification — only raw message, no history/RAG
        prompt = (
            'Classify if this user message needs an external tool to answer.\n'
            'Tools: web_search, generate_image, edit_image, execute_code, read_file, create_file.\n\n'
            'Rules:\n'
            '- Greeting, chitchat, knowledge questions → false\n'
            '- Real-time info (weather, price, news, current events) → true\n'
            '- Image generation/editing requests → true\n'
            '- Web search, file operations, code execution → true\n\n'
            f'Message: "{last_user_msg}"\n\n'
            'Reply ONLY with valid JSON: {"is_tool": true} or {"is_tool": false}'
        )

        try:
            import asyncio
            import json as _json

            def _call():
                return ollama.chat(
                    model="Lumina-small",
                    messages=[{"role": "user", "content": prompt}],
                    options={"temperature": 0.0, "num_ctx": 1024, "num_predict": 20},
                    format="json",
                )

            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, _call)

            # Extract content (handle object or dict response)
            raw = ""
            if hasattr(response, 'message'):
                raw = getattr(response.message, 'content', '') or ''
            elif isinstance(response, dict):
                raw = response.get("message", {}).get("content", "")
            else:
                raw = str(response)

            raw = raw.strip()
            logger.info(f"[ToolClassifier] Lumina-small raw: {repr(raw)}")

            if not raw:
                logger.warning("[ToolClassifier] Empty response → default false")
                return False

            # Parse JSON
            try:
                data = _json.loads(raw)
                result = bool(data.get("is_tool", False))
                logger.info(f"[ToolClassifier] Parsed: is_tool={result}")
                return result
            except _json.JSONDecodeError:
                lower = raw.lower()
                result = '"is_tool": true' in lower or '"is_tool":true' in lower
                logger.info(f"[ToolClassifier] JSON parse failed, text fallback: is_tool={result}")
                return result

        except Exception as e:
            logger.warning(f"[ToolClassifier] Classification failed: {e} → default false")
            return False

    async def stream_chat(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        model: str = "Lumin-New",
        temperature: float = 0.2,
        num_ctx: int = 16384,
        think: Union[str, bool] = False,
        force_ollama: bool = False,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Stream chat with intelligent routing via Lumina-small classification.

        Routing logic:
        1. force_ollama=True → Ollama directly (tool-call continuation)
        2. force_ollama=False → Lumina-small classifies the message:
           - Needs tools → Ollama (Lumina) with tools
           - No tools    → Cloud FIRST (Groq → Gemini → Cerebras), Ollama fallback
        """
        errors = []

        # ── Force Ollama: used when caller knows tools are needed ──
        if force_ollama:
            logger.info("[ChatRouter] force_ollama=True → routing directly to Ollama (Lumina)")
            ollama_provider = next((p for p in self.providers if p.name == "Ollama"), None)
            if ollama_provider:
                try:
                    async for chunk in self._call_provider(
                        ollama_provider, messages, tools, model, temperature, num_ctx, think
                    ):
                        yield chunk
                    logger.info("[ChatRouter] ✅ Completed with Ollama (force)")
                    return
                except Exception as e:
                    error_msg = f"Ollama: {str(e)[:200]}"
                    logger.error(f"[ChatRouter] ❌ {error_msg}")
                    errors.append(error_msg)

            yield {
                "message": {
                    "content": f"⚠️ Ollama không khả dụng. Vui lòng kiểm tra server Ollama.\n\nChi tiết: {'; '.join(errors)}"
                },
                "done": True,
            }
            return

        # ── Classification gate: Lumina-small decides routing ──
        needs_tools = await self._classify_needs_tools(messages, tools)

        if needs_tools:
            # ── Route to Ollama with tools ──
            logger.info("[ChatRouter] Classification: NEEDS TOOLS → routing to Ollama (Lumina)")
            ollama_provider = next((p for p in self.providers if p.name == "Ollama"), None)
            if ollama_provider:
                try:
                    async for chunk in self._call_provider(
                        ollama_provider, messages, tools, model, temperature, num_ctx, think
                    ):
                        yield chunk
                    logger.info("[ChatRouter] ✅ Completed with Ollama (tools)")
                    return
                except Exception as e:
                    error_msg = f"Ollama: {str(e)[:200]}"
                    logger.warning(f"[ChatRouter] ❌ {error_msg}")
                    errors.append(error_msg)
                    # Fall through to cloud as backup

        # ── Route to Cloud (no tools, text-only fast path) ──
        logger.info("[ChatRouter] Classification: NO TOOLS → routing to Cloud providers")
        for provider in self.providers:
            if not provider.enabled:
                continue
            # Cloud providers: no tools (pure text, fast)
            # Ollama: also no tools here (classification said not needed)
            pass_tools = None

            try:
                logger.info(f"[ChatRouter] Trying {provider.name}...")

                async for chunk in self._call_provider(
                    provider, messages, pass_tools, model, temperature, num_ctx, think
                ):
                    yield chunk

                logger.info(f"[ChatRouter] ✅ Completed with {provider.name}")
                return

            except Exception as e:
                error_msg = f"{provider.name}: {str(e)[:200]}"
                logger.warning(f"[ChatRouter] ❌ {error_msg}")
                errors.append(error_msg)
                continue

        # All providers failed
        logger.error(f"[ChatRouter] All providers failed: {errors}")
        yield {
            "message": {
                "content": f"⚠️ Xin lỗi, tất cả các LLM providers đều không khả dụng. Vui lòng thử lại sau.\n\nChi tiết: {'; '.join(errors)}"
            },
            "done": True,
        }

    async def _call_provider(
        self,
        provider: ChatProvider,
        messages: List[Dict],
        tools: Optional[List[Dict]],
        model: str,
        temperature: float,
        num_ctx: int,
        think: Union[str, bool],
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """Route to the correct provider implementation."""

        if provider.name == "Ollama":
            async for chunk in _stream_ollama(
                messages, tools, model, temperature, num_ctx, think
            ):
                yield chunk

        elif provider.name in ("Groq", "Cerebras"):
            api_keys = [k.strip() for k in os.getenv(provider.api_key_env, "").split(",") if k.strip()]
            if not api_keys:
                raise Exception(f"{provider.name} API key not configured")

            api_url = {
                "Groq": "https://api.groq.com/openai/v1/chat/completions",
                "Cerebras": "https://api.cerebras.ai/v1/chat/completions",
            }[provider.name]

            cloud_model = _get_cloud_model(model, provider.name)

            last_exception = None
            for key in api_keys:
                try:
                    async for chunk in _stream_openai_compatible(
                        api_url=api_url,
                        api_key=key,
                        messages=messages,
                        tools=tools,
                        model=cloud_model,
                        temperature=temperature,
                        provider_name=provider.name,
                        timeout=provider.timeout,
                        think=think,
                    ):
                        yield chunk
                    return  # Success
                except Exception as e:
                    last_exception = e
                    err_str = str(e)
                    if "429" in err_str or "quota" in err_str.lower() or "limit" in err_str.lower():
                        logger.warning(f"[ChatRouter] {provider.name} key rate limited, falling back to next key. Err: {err_str[:100]}")
                        continue
                    else:
                        raise e
            if last_exception:
                raise last_exception
            raise Exception("No valid API keys")

        elif provider.name == "Gemini":
            api_keys = [k.strip() for k in os.getenv(provider.api_key_env, "").split(",") if k.strip()]
            if not api_keys:
                raise Exception("Gemini API key not configured")

            cloud_model = _get_cloud_model(model, "Gemini")

            last_exception = None
            for key in api_keys:
                try:
                    async for chunk in _stream_gemini(
                        api_key=key,
                        messages=messages,
                        tools=tools,
                        model=cloud_model,
                        temperature=temperature,
                        timeout=provider.timeout,
                        think=think,
                    ):
                        yield chunk
                    return
                except Exception as e:
                    last_exception = e
                    err_str = str(e)
                    if "429" in err_str or "quota" in err_str.lower() or "limit" in err_str.lower():
                        logger.warning(f"[ChatRouter] Gemini key rate limited, falling back to next. Err: {err_str[:100]}")
                        continue
                    else:
                        raise e
            if last_exception:
                raise last_exception
            raise Exception("No valid API keys")

        elif provider.name == "Cohere":
            api_keys = [k.strip() for k in os.getenv(provider.api_key_env, "").split(",") if k.strip()]
            if not api_keys:
                raise Exception("Cohere API key not configured")

            cloud_model = _get_cloud_model(model, "Cohere")

            last_exception = None
            for key in api_keys:
                try:
                    async for chunk in _stream_cohere(
                        api_key=key,
                        messages=messages,
                        model=cloud_model,
                        temperature=temperature,
                        timeout=provider.timeout,
                        think=think,
                    ):
                        yield chunk
                    return
                except Exception as e:
                    last_exception = e
                    err_str = str(e)
                    if "429" in err_str or "quota" in err_str.lower() or "limit" in err_str.lower():
                        logger.warning(f"[ChatRouter] Cohere key rate limited, falling back to next. Err: {err_str[:100]}")
                        continue
                    else:
                        raise e
            if last_exception:
                raise last_exception
            raise Exception("No valid API keys")

        else:
            raise Exception(f"Unknown provider: {provider.name}")

    async def generate_simple(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        temperature: float = 0.3,
        max_tokens: int = 100,
    ) -> Optional[str]:
        """
        Non-streaming simple text generation with fallback.
        Used for title generation and other simple tasks.
        """
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        errors = []

        for provider in self.providers:
            if not provider.enabled:
                continue

            try:
                result_text = ""

                async for chunk in self._call_provider(
                    provider=provider,
                    messages=messages,
                    tools=None,
                    model="Lumina-small",  # Use small model for simple tasks
                    temperature=temperature,
                    num_ctx=4096,
                    think=False,
                ):
                    content = chunk.get("message", {}).get("content", "")
                    if content:
                        result_text += content

                if result_text.strip():
                    return result_text.strip()

            except Exception as e:
                errors.append(f"{provider.name}: {str(e)[:100]}")
                continue

        logger.error(f"[ChatRouter] generate_simple failed: {errors}")
        return None

    def get_status(self) -> List[Dict[str, Any]]:
        """Get status of all providers."""
        return [
            {
                "name": p.name,
                "enabled": p.enabled,
                "supports_tools": p.supports_tools,
                "supports_vision": p.supports_vision,
                "has_key": bool(os.getenv(p.api_key_env, ""))
                if p.api_key_env
                else True,
            }
            for p in self.providers
        ]


# Singleton instance
chat_llm_router = ChatLLMRouter()
