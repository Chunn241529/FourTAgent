"""
Image Generation Service - ComfyUI Integration
Handles image generation using ComfyUI workflow API.
"""

import json
import logging
import random
import aiohttp
import asyncio
import os
import re
from typing import Optional, Tuple


logger = logging.getLogger(__name__)

# ComfyUI Configuration
COMFYUI_HOST = os.getenv("COMFYUI_HOST", "http://localhost:8188")
COMFYUI_OUTPUT_DIR = os.getenv("COMFYUI_OUTPUT_DIR", "/home/trung/ComfyUI/output")

# Model choices
MODEL_DEFAULT = "4t_inpaint.safetensors"
MODEL_2D_3D = "4t_2d_3d.safetensors"

# Default negative prompt (Updated from new workflow)
DEFAULT_NEGATIVE_PROMPT = "(deformed iris, deformed pupils), text, cropped, out of frame, worst quality, low quality, jpeg artifacts, ugly, duplicate, morbid, mutilated, extra fingers, mutated hands, poorly drawn hands, poorly drawn face, mutation, deformed, blurry, dehydrated, bad anatomy, bad proportions, extra limbs, cloned face, disfigured, gross proportions, malformed limbs, missing arms, missing legs, extra arms, extra legs, fused fingers, too many fingers, long neck, UnrealisticDream"

# Keywords that suggest 2D/3D style
KEYWORDS_2D_3D = [
    "2d",
    "3d",
    "anime",
    "cartoon",
    "manga",
    "illustration",
    "digital art",
    "cel shaded",
    "toon",
    "pixar",
    "disney",
    "character design",
    "concept art",
    "game art",
    "chibi",
    "stylized",
    "low poly",
    "voxel",
    "render",
    "blender",
    "cgi",
    # Vietnamese keywords
    "hoạt hình",
    "vẽ",
    "tranh vẽ",
    "minh họa",
]

# Keywords that indicate realistic image (override 2D/3D detection)
KEYWORDS_REALISTIC = [
    "realistic",
    "photorealistic",
    "photo",
    "photograph",
    "real",
    "lifelike",
]

# Keywords that should be blocked
KEYWORDS_BLACKLIST = [
    "nsfw",
    "nude",
    "naked",
    "sex",
    "porn",
    "hentai",
    "xxx",
    "blood",
    "gore",
    "violence",
    "kill",
    "suicide",
    "drug",
    # Add more keywords here
]


class ImageGenerationService:
    """Service for generating images using ComfyUI."""

    def __init__(self):
        self.client_id = "lumina_ai_" + str(random.randint(10000, 99999))

    def cleanup_vram(self):
        """Clean up VRAM after generation."""
        import gc

        gc.collect()
        try:
            import torch

            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                torch.cuda.ipc_collect()
                logger.info("VRAM cleanup completed (torch.cuda.empty_cache)")
        except ImportError:
            pass
        except Exception as e:
            logger.warning(f"VRAM cleanup failed: {e}")

    def validate_prompt(self, prompt: str) -> bool:
        """Check if prompt contains blacklisted keywords."""
        prompt_lower = prompt.lower()
        for keyword in KEYWORDS_BLACKLIST:
            if keyword in prompt_lower:
                logger.warning(
                    f"Blocked blacklisted keyword: {keyword} in prompt: {prompt}"
                )
                return False
        return True

    def is_2d_3d_content(self, prompt: str) -> bool:
        """
        Detect if the prompt is related to 2D/3D style content.

        Args:
            prompt: The generated or user prompt

        Returns:
            True if 2D/3D style detected (and not realistic)
        """
        prompt_lower = prompt.lower()

        # If realistic keywords found, use default model (not 2D/3D)
        for keyword in KEYWORDS_REALISTIC:
            if keyword in prompt_lower:
                logger.info(
                    f"Detected realistic keyword: {keyword}, using default model"
                )
                return False

        # Check for 2D/3D keywords
        for keyword in KEYWORDS_2D_3D:
            if keyword in prompt_lower:
                logger.info(f"Detected 2D/3D keyword: {keyword}")
                return True
        return False

    def parse_size(self, size: str) -> Tuple[int, int]:
        """
        Parse size string like '512x512' into (width, height).

        Args:
            size: Size string in format 'WIDTHxHEIGHT'

        Returns:
            Tuple of (width, height)
        """
        try:
            parts = size.lower().split("x")
            width = int(parts[0])
            height = int(parts[1]) if len(parts) > 1 else width
            # Clamp to reasonable values
            width = max(256, min(1024, width))
            height = max(256, min(1024, height))
            return width, height
        except Exception:
            return 512, 512

    def build_workflow(
        self,
        prompt: str,
        width: int = 512,
        height: int = 512,
        seed: Optional[int] = None,
    ) -> Tuple[dict, int]:
        """
        Build ComfyUI workflow JSON.
        Using optimized workflow with Lumina_Gen and LoRA stack.
        """
        if seed is None:
            seed = random.randint(1, 2**53)

        # Using Lumina_Gen for all requests as per new workflow
        # Can still keep 2D/3D logic if we want specific prompts, but checkpoint is fixed provided in request.
        # Checkpoint name from request: "Lumina_Gen.safetensors"
        ckpt_name = "Lumina_Gen.safetensors"

        logger.info(f"Building workflow with checkpoint: {ckpt_name}")

        workflow = {
            "client_id": self.client_id,
            "prompt": {
                "3": {
                    "inputs": {
                        "seed": seed,
                        "steps": 6,
                        "cfg": 1.5,
                        "sampler_name": "dpmpp_sde",
                        "scheduler": "karras",
                        "denoise": 1,
                        "model": ["19", 0],
                        "positive": ["6", 0],
                        "negative": ["7", 0],
                        "latent_image": ["5", 0],
                    },
                    "class_type": "KSampler",
                    "_meta": {"title": "KSampler"},
                },
                "4": {
                    "inputs": {"ckpt_name": ckpt_name},
                    "class_type": "CheckpointLoaderSimple",
                    "_meta": {"title": "Load Checkpoint"},
                },
                "5": {
                    "inputs": {"width": width, "height": height, "batch_size": 1},
                    "class_type": "EmptyLatentImage",
                    "_meta": {"title": "Empty Latent Image"},
                },
                "6": {
                    "inputs": {"text": prompt, "clip": ["19", 1]},
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode (Prompt)"},
                },
                "7": {
                    "inputs": {
                        "text": DEFAULT_NEGATIVE_PROMPT,
                        "clip": ["19", 1],
                    },
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode (Negative)"},
                },
                "8": {
                    "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
                    "class_type": "VAEDecode",
                    "_meta": {"title": "VAE Decode"},
                },
                "9": {
                    "inputs": {"filename_prefix": "Lumina", "images": ["8", 0]},
                    "class_type": "SaveImage",
                    "_meta": {"title": "Save Image"},
                },
                "19": {
                    "inputs": {
                        "lora_01": "add_detail.safetensors",
                        "strength_01": 1,
                        "lora_02": "None",
                        "strength_02": 1,
                        "lora_03": "None",
                        "strength_03": 1,
                        "lora_04": "None",
                        "strength_04": 1,
                        "model": ["4", 0],
                        "clip": ["4", 1],
                    },
                    "class_type": "Lora Loader Stack (rgthree)",
                    "_meta": {"title": "Lora Loader Stack (rgthree)"},
                },
            },
        }

        return workflow, seed

    async def submit_to_comfyui(self, workflow: dict) -> dict:
        """
        Submit workflow to ComfyUI and wait for result.

        Args:
            workflow: ComfyUI workflow dictionary

        Returns:
            Dictionary with image info or error
        """
        try:
            async with aiohttp.ClientSession() as session:
                # Submit prompt
                async with session.post(
                    f"{COMFYUI_HOST}/prompt",
                    json=workflow,
                    timeout=aiohttp.ClientTimeout(total=120),
                ) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        logger.error(f"ComfyUI error: {error_text}")
                        return {"error": f"ComfyUI rejected request: {error_text}"}

                    result = await response.json()
                    prompt_id = result.get("prompt_id")
                    logger.info(f"Submitted to ComfyUI, prompt_id: {prompt_id}")

                # Poll for completion
                max_attempts = 60  # 60 seconds timeout
                for attempt in range(max_attempts):
                    await asyncio.sleep(1)

                    async with session.get(
                        f"{COMFYUI_HOST}/history/{prompt_id}"
                    ) as hist_response:
                        if hist_response.status == 200:
                            history = await hist_response.json()

                            if prompt_id in history:
                                outputs = history[prompt_id].get("outputs", {})

                                # Find SaveImage output (node 9)
                                if "9" in outputs:
                                    images = outputs["9"].get("images", [])
                                    if images:
                                        image_info = images[0]
                                        filename = image_info.get("filename", "")
                                        subfolder = image_info.get("subfolder", "")

                                        # Build full path
                                        if subfolder:
                                            image_path = os.path.join(
                                                COMFYUI_OUTPUT_DIR, subfolder, filename
                                            )
                                        else:
                                            image_path = os.path.join(
                                                COMFYUI_OUTPUT_DIR, filename
                                            )

                                        logger.info(f"Image generated: {image_path}")

                                        # Read image and convert to base64
                                        image_base64 = None
                                        try:
                                            with open(image_path, "rb") as img_file:
                                                import base64

                                                image_base64 = base64.b64encode(
                                                    img_file.read()
                                                ).decode("utf-8")
                                                logger.info(
                                                    f"Image encoded to base64, size: {len(image_base64)} chars"
                                                )
                                        except Exception as e:
                                            logger.error(
                                                f"Failed to read image file: {e}"
                                            )

                                        return {
                                            "success": True,
                                            "image_path": image_path,
                                            "filename": filename,
                                            "prompt_id": prompt_id,
                                            "image_base64": image_base64,
                                        }

                return {"error": "Timeout waiting for image generation"}

        except aiohttp.ClientError as e:
            logger.error(f"ComfyUI connection error: {e}")
            return {"error": f"Cannot connect to ComfyUI: {str(e)}"}
        except Exception as e:
            logger.error(f"Image generation error: {e}")
            return {"error": str(e)}

    async def generate_image(self, description: str, size: str = "768x768") -> dict:
        """
        Legacy entry point using direct generation.
        Argument is named 'description' but acts as prompt if called by updated logic,
        or raw text if called by legacy code (though quality might suffer without Main LLM processing).
        """
        logger.info(f"Generate image (legacy wrapper): {description[:50]}...")
        return await self.generate_image_direct(description, size)

    async def generate_image_direct(
        self, prompt: str, size: str = "768x768", seed: Optional[int] = None
    ) -> dict:
        """
        Generate image using prompt directly (no LLM prompt generation).
        Used when main chat LLM already generates English SD prompt.

        Args:
            prompt: English comma-separated tags from main LLM
            size: Image size (e.g., "512x512")
            seed: Optional seed for reproducibility

        Returns:
            Dictionary with generation result
        """
        logger.info(
            f"Generate image direct: prompt={prompt[:100]}..., size={size}, seed={seed}"
        )

        if not self.validate_prompt(prompt):
            return {"success": False, "error": "Prompt contains restricted keywords"}

        try:
            # Step 1: Parse size
            width, height = self.parse_size(size)

            # Step 2: Build workflow (returns workflow AND the seed used)
            workflow, used_seed = self.build_workflow(prompt, width, height, seed=seed)

            # Step 3: Submit to ComfyUI
            result = await self.submit_to_comfyui(workflow)

            # Add info to result
            if result.get("success"):
                result["generated_prompt"] = prompt
                result["size"] = f"{width}x{height}"
                result["seed"] = used_seed
                result["message"] = (
                    f"Đã tạo xong ảnh! (size: {width}x{height}, seed: {used_seed})"
                )

            return result
        finally:
            # Always clean up VRAM
            self.cleanup_vram()


# Singleton instance
image_generation_service = ImageGenerationService()
