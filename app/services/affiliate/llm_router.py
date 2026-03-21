"""
LLM Fallback Router for Affiliate Content Generation.

Routes requests through multiple free-tier LLM providers with automatic
fallback when rate-limited or errored. Priority order:
  1. Groq (fastest inference)
  2. Cerebras (fast, generous free tier)
  3. Google Gemini Flash (massive quota)
  4. Cohere Command-R (good Vietnamese support)
  5. HuggingFace Serverless (free, rate-limited)
  6. Ollama Local (unlimited, never fails)
"""

import os
import json
import logging
import aiohttp
import asyncio
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class LLMProvider:
    """Configuration for a single LLM provider."""
    name: str
    api_url: str
    api_key_env: str  # Environment variable name for API key
    model: str
    headers_fn: callable = None  # Function to generate headers
    body_fn: callable = None     # Function to generate request body
    parse_fn: callable = None    # Function to parse response
    enabled: bool = True
    max_tokens: int = 2048
    timeout: int = 30  # seconds


class LLMRouter:
    """
    Multi-provider LLM router with automatic fallback.

    Usage:
        router = LLMRouter()
        result = await router.generate("Viết kịch bản review sản phẩm...")
    """

    def __init__(self):
        self.providers: List[LLMProvider] = []
        self._setup_providers()
        logger.info(f"LLMRouter initialized with {len([p for p in self.providers if p.enabled])} active providers")

    def _setup_providers(self):
        """Configure all available LLM providers."""

        # --- Provider 1: Groq ---
        groq_key = os.getenv("GROQ_API_KEY", "")
        self.providers.append(LLMProvider(
            name="Groq",
            api_url="https://api.groq.com/openai/v1/chat/completions",
            api_key_env="GROQ_API_KEY",
            model=os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile"),
            enabled=bool(groq_key),
        ))

        # --- Provider 2: Cerebras ---
        cerebras_key = os.getenv("CEREBRAS_API_KEY", "")
        self.providers.append(LLMProvider(
            name="Cerebras",
            api_url="https://api.cerebras.ai/v1/chat/completions",
            api_key_env="CEREBRAS_API_KEY",
            model=os.getenv("CEREBRAS_MODEL", "llama3.1-8b"),
            enabled=bool(cerebras_key),
        ))

        # --- Provider 3: Google Gemini ---
        gemini_key = os.getenv("GEMINI_API_KEY", "")
        self.providers.append(LLMProvider(
            name="Gemini",
            api_url="https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
            api_key_env="GEMINI_API_KEY",
            model=os.getenv("GEMINI_MODEL", "gemini-2.0-flash"),
            enabled=bool(gemini_key),
            max_tokens=4096,
        ))

        # --- Provider 4: Cohere ---
        cohere_key = os.getenv("COHERE_API_KEY", "")
        self.providers.append(LLMProvider(
            name="Cohere",
            api_url="https://api.cohere.com/v2/chat",
            api_key_env="COHERE_API_KEY",
            model=os.getenv("COHERE_MODEL", "command-r"),
            enabled=bool(cohere_key),
        ))

        # --- Provider 5: HuggingFace ---
        hf_key = os.getenv("HF_API_KEY", "")
        self.providers.append(LLMProvider(
            name="HuggingFace",
            api_url="https://api-inference.huggingface.co/models/{model}",
            api_key_env="HF_API_KEY",
            model=os.getenv("HF_MODEL", "Qwen/Qwen2.5-72B-Instruct"),
            enabled=bool(hf_key),
            timeout=60,
        ))

        # --- Provider 6: Ollama (Local, always available) ---
        ollama_url = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
        self.providers.append(LLMProvider(
            name="Ollama",
            api_url=f"{ollama_url}/api/chat",
            api_key_env="",  # No key needed
            model=os.getenv("OLLAMA_AFFILIATE_MODEL", "qwen2.5:7b"),
            enabled=True,  # Always enabled as final fallback
            timeout=120,  # Local can be slower
        ))

    async def generate(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        temperature: float = 0.8,
        max_tokens: int = 2048,
    ) -> Dict[str, Any]:
        """
        Generate text using fallback chain.

        Returns:
            {
                "text": "generated content",
                "provider": "provider_name",
                "model": "model_used",
                "error": None  # or error message if all failed
            }
        """
        errors = []

        for provider in self.providers:
            if not provider.enabled:
                continue

            try:
                logger.info(f"[LLMRouter] Trying {provider.name} ({provider.model})...")
                text = await self._call_provider(
                    provider, prompt, system_prompt, temperature, max_tokens
                )

                if text:
                    logger.info(f"[LLMRouter] ✅ Success with {provider.name}")
                    return {
                        "text": text,
                        "provider": provider.name,
                        "model": provider.model,
                        "error": None,
                    }

            except Exception as e:
                error_msg = f"{provider.name}: {str(e)}"
                logger.warning(f"[LLMRouter] ❌ {error_msg}")
                errors.append(error_msg)
                continue

        # All providers failed
        return {
            "text": None,
            "provider": None,
            "model": None,
            "error": f"All providers failed: {'; '.join(errors)}",
        }

    async def _call_provider(
        self,
        provider: LLMProvider,
        prompt: str,
        system_prompt: Optional[str],
        temperature: float,
        max_tokens: int,
    ) -> Optional[str]:
        """Call a specific provider and return generated text."""

        api_key = os.getenv(provider.api_key_env, "") if provider.api_key_env else ""

        if provider.name == "Gemini":
            return await self._call_gemini(provider, prompt, system_prompt, api_key, temperature, max_tokens)
        elif provider.name == "Cohere":
            return await self._call_cohere(provider, prompt, system_prompt, api_key, temperature, max_tokens)
        elif provider.name == "HuggingFace":
            return await self._call_huggingface(provider, prompt, system_prompt, api_key, temperature, max_tokens)
        elif provider.name == "Ollama":
            return await self._call_ollama(provider, prompt, system_prompt, temperature, max_tokens)
        else:
            # OpenAI-compatible (Groq, Cerebras)
            return await self._call_openai_compatible(provider, prompt, system_prompt, api_key, temperature, max_tokens)

    async def _call_openai_compatible(
        self, provider: LLMProvider, prompt: str,
        system_prompt: Optional[str], api_key: str,
        temperature: float, max_tokens: int,
    ) -> Optional[str]:
        """Call OpenAI-compatible APIs (Groq, Cerebras)."""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": provider.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": False,
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                provider.api_url, json=payload, headers=headers,
                timeout=aiohttp.ClientTimeout(total=provider.timeout),
            ) as resp:
                if resp.status != 200:
                    error = await resp.text()
                    raise Exception(f"HTTP {resp.status}: {error[:200]}")
                data = await resp.json()
                return data["choices"][0]["message"]["content"]

    async def _call_gemini(
        self, provider: LLMProvider, prompt: str,
        system_prompt: Optional[str], api_key: str,
        temperature: float, max_tokens: int,
    ) -> Optional[str]:
        """Call Google Gemini API."""
        url = provider.api_url.format(model=provider.model) + f"?key={api_key}"

        contents = []
        if system_prompt:
            contents.append({"role": "user", "parts": [{"text": system_prompt}]})
            contents.append({"role": "model", "parts": [{"text": "Understood."}]})
        contents.append({"role": "user", "parts": [{"text": prompt}]})

        payload = {
            "contents": contents,
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_tokens,
            },
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                url, json=payload,
                headers={"Content-Type": "application/json"},
                timeout=aiohttp.ClientTimeout(total=provider.timeout),
            ) as resp:
                if resp.status != 200:
                    error = await resp.text()
                    raise Exception(f"HTTP {resp.status}: {error[:200]}")
                data = await resp.json()
                return data["candidates"][0]["content"]["parts"][0]["text"]

    async def _call_cohere(
        self, provider: LLMProvider, prompt: str,
        system_prompt: Optional[str], api_key: str,
        temperature: float, max_tokens: int,
    ) -> Optional[str]:
        """Call Cohere API (v2)."""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": provider.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": False,
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                provider.api_url, json=payload, headers=headers,
                timeout=aiohttp.ClientTimeout(total=provider.timeout),
            ) as resp:
                if resp.status != 200:
                    error = await resp.text()
                    raise Exception(f"HTTP {resp.status}: {error[:200]}")
                data = await resp.json()
                return data["message"]["content"][0]["text"]

    async def _call_huggingface(
        self, provider: LLMProvider, prompt: str,
        system_prompt: Optional[str], api_key: str,
        temperature: float, max_tokens: int,
    ) -> Optional[str]:
        """Call HuggingFace Inference API."""
        url = provider.api_url.format(model=provider.model)

        full_prompt = prompt
        if system_prompt:
            full_prompt = f"{system_prompt}\n\n{prompt}"

        payload = {
            "inputs": full_prompt,
            "parameters": {
                "temperature": temperature,
                "max_new_tokens": max_tokens,
                "return_full_text": False,
            },
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                url, json=payload, headers=headers,
                timeout=aiohttp.ClientTimeout(total=provider.timeout),
            ) as resp:
                if resp.status != 200:
                    error = await resp.text()
                    raise Exception(f"HTTP {resp.status}: {error[:200]}")
                data = await resp.json()
                if isinstance(data, list) and len(data) > 0:
                    return data[0].get("generated_text", "")
                return None

    async def _call_ollama(
        self, provider: LLMProvider, prompt: str,
        system_prompt: Optional[str],
        temperature: float, max_tokens: int,
    ) -> Optional[str]:
        """Call local Ollama API."""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": provider.model,
            "messages": messages,
            "stream": False,
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens,
            },
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                provider.api_url, json=payload,
                timeout=aiohttp.ClientTimeout(total=provider.timeout),
            ) as resp:
                if resp.status != 200:
                    error = await resp.text()
                    raise Exception(f"HTTP {resp.status}: {error[:200]}")
                data = await resp.json()
                return data["message"]["content"]

    def get_status(self) -> List[Dict[str, Any]]:
        """Get status of all providers."""
        return [
            {
                "name": p.name,
                "model": p.model,
                "enabled": p.enabled,
                "has_key": bool(os.getenv(p.api_key_env, "")) if p.api_key_env else True,
            }
            for p in self.providers
        ]


# Singleton
llm_router = LLMRouter()
