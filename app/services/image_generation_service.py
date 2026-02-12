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

# Default negative prompt
DEFAULT_NEGATIVE_PROMPT = "text, cropped, out of frame, worst quality, low quality, jpeg artifacts, ugly, duplicate, morbid, mutilated, extra fingers, mutated hands, poorly drawn hands, poorly drawn face, mutation, deformed, blurry, dehydrated, bad anatomy, bad proportions, extra limbs, cloned face, disfigured, gross proportions, malformed limbs, missing arms, missing legs, extra arms, extra legs, fused fingers, too many fingers, long neck"

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
    "hoạt hình",
    "vẽ",
    "tranh vẽ",
    "minh họa",
]

# Keywords that indicate realistic image
KEYWORDS_REALISTIC = [
    "realistic",
    "photorealistic",
    "photo",
    "photograph",
    "real",
    "lifelike",
]

# Keywords for blocking
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
]


class ImageGenerationService:
    """Service for generating images using ComfyUI."""

    def __init__(self):
        self.client_id = "lumina_ai_" + str(random.randint(10000, 99999))

    async def cleanup_vram(self):
        """Clean up VRAM after generation."""
        import gc

        gc.collect()
        try:
            import torch

            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                torch.cuda.ipc_collect()
                logger.info("Local VRAM cleanup completed")
        except ImportError:
            pass
        except Exception as e:
            logger.warning(f"Local VRAM cleanup failed: {e}")

        try:
            async with aiohttp.ClientSession() as session:
                url = f"{COMFYUI_HOST}/api/easyuse/cleangpu"
                async with session.post(url, timeout=5) as response:
                    if response.status == 200:
                        logger.info("ComfyUI VRAM cleanup requested successfully")
        except Exception as e:
            logger.warning(f"Failed to request ComfyUI VRAM cleanup: {e}")

    def validate_prompt(self, prompt: str) -> bool:
        """Check if prompt contains blacklisted keywords."""
        prompt_lower = prompt.lower()
        for keyword in KEYWORDS_BLACKLIST:
            if keyword in prompt_lower:
                logger.warning(f"Blocked blacklisted keyword: {keyword}")
                return False
        return True

    def is_2d_3d_content(self, prompt: str) -> bool:
        """Detect 2D/3D content."""
        prompt_lower = prompt.lower()
        for keyword in KEYWORDS_REALISTIC:
            if keyword in prompt_lower:
                return False
        for keyword in KEYWORDS_2D_3D:
            if keyword in prompt_lower:
                return True
        return False

    def parse_size(self, size: str) -> Tuple[int, int]:
        """Parse size string."""
        try:
            size_lower = size.lower().strip()
            if size_lower == "square":
                return 768, 768
            if size_lower == "landscape":
                return 768, 512
            if size_lower == "portrait":
                return 512, 768
            parts = size_lower.split("x")
            width = max(256, min(1024, int(parts[0])))
            height = max(256, min(1024, int(parts[1]))) if len(parts) > 1 else width
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
        """Build ComfyUI workflow JSON v2.0."""
        if seed is None:
            seed = random.randint(1, 2**53)

        prompt_lower = prompt.lower()

        # Keywords for detection
        keywords_animal = [
            "cat",
            "dog",
            "animal",
            "creature",
            "bird",
            "fish",
            "tiger",
            "lion",
            "wolf",
            "bear",
            "pet",
            "dragon",
            "horse",
            "cow",
            "pig",
            "sheep",
            "monkey",
            "elephant",
            "mèo",
            "chó",
            "thú",
            "động vật",
        ]
        keywords_1girl = ["1girl", "1 girl"]
        keywords_person = [
            "girl",
            "woman",
            "female",
            "lady",
            "sister",
            "mother",
            "aunt",
            "gái",
            "nữ",
            "cô",
            "boy",
            "man",
            "male",
            "brother",
            "father",
            "uncle",
            "trai",
            "nam",
            "anh",
            "ông",
            "bà",
            "person",
            "human",
            "people",
            "người",
        ]
        keywords_anime = [
            "anime",
            "2d",
            "manga",
            "cartoon",
            "illustration",
            "hoạt hình",
            "tranh vẽ",
        ]
        keywords_3d = ["3d", "render", "blender", "c4d", "unreal", "cgi"]

        is_animal = any(k in prompt_lower for k in keywords_animal)
        has_person = any(k in prompt_lower for k in keywords_person) or any(
            k in prompt_lower for k in keywords_1girl
        )
        is_1girl = any(k in prompt_lower for k in keywords_1girl)
        is_anime_style = any(k in prompt_lower for k in keywords_anime) or any(
            k in prompt_lower for k in keywords_3d
        )

        # Determine Checkpoint (Switch model for 2D/3D)
        if is_anime_style:
            ckpt_name = "Lumina_2D.safetensors"
            steps = 12
            cfg = 7.0
        else:
            ckpt_name = "Lumina_Real.safetensors"
            steps = 6
            cfg = 1.5

        logger.info(
            f"Building workflow with checkpoint: {ckpt_name}, steps: {steps}, cfg: {cfg}"
        )

        # Inject positive anatomy prompt (masterpiece addition)
        current_prompt = (
            prompt
            + ", (perfect hands, perfect fingers, correct anatomy:1.2), masterpiece, best quality"
        )

        # LoRA stack logic
        stack_39_config = [{"name": "None", "strength": 0.0}] * 4
        if not is_animal:
            slot_idx = 0
            if has_person:
                stack_39_config[0] = {
                    "name": "detailed_eye.safetensors",
                    "strength": 0.8,
                }
                stack_39_config[1] = {
                    "name": None,
                    "strength": 0.8,
                }
                slot_idx = 2
                if is_1girl:
                    stack_39_config[slot_idx] = {
                        "name": "girl_face.safetensors",
                        "strength": 0.8,
                    }

        negative_prompt = "embedding:easynegative, (worst quality, low quality:1.4), (nude, naked, nsfw:1.2), bad hands, bad fingers, extra fingers, missing fingers, fused fingers, deformed fingers, mutated hands, malformed hands, poorly drawn hands, incorrect hand anatomy, broken fingers, twisted fingers, long fingers, short fingers, duplicate fingers, extra limbs, malformed limbs, bad proportions, disfigured, mutation, ugly hands, blurry hands, low detail hands, cropped hands, out of frame hands"

        workflow = {
            "client_id": self.client_id,
            "extra_data": {"extra_pnginfo": {"workflow": {}}},
            "prompt": {
                "3": {
                    "inputs": {
                        "seed": seed,
                        "steps": steps,
                        "cfg": cfg,
                        "sampler_name": "dpmpp_sde",
                        "scheduler": "karras",
                        "denoise": 1,
                        "model": ["39", 0],
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
                    "inputs": {
                        "text": current_prompt,
                        "clip": ["39", 1],
                    },
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode (Prompt)"},
                },
                "7": {
                    "inputs": {
                        "text": negative_prompt,
                        "clip": ["39", 1],
                    },
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode (Negative)"},
                },
                "8": {
                    "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
                    "class_type": "VAEDecode",
                    "_meta": {"title": "VAE Decode"},
                },
                "39": {
                    "inputs": {
                        "lora_01": stack_39_config[0]["name"],
                        "strength_01": stack_39_config[0].get("strength", 0.0),
                        "lora_02": stack_39_config[1]["name"],
                        "strength_02": stack_39_config[1].get("strength", 0.0),
                        "lora_03": stack_39_config[2]["name"],
                        "strength_03": stack_39_config[2].get("strength", 0.0),
                        "lora_04": stack_39_config[3]["name"],
                        "strength_04": stack_39_config[3].get("strength", 0.0),
                        "model": ["4", 0],
                        "clip": ["4", 1],
                    },
                    "class_type": "Lora Loader Stack (rgthree)",
                    "_meta": {"title": "Lora Loader Stack (rgthree)"},
                },
                "40": {
                    "inputs": {"upscale_model": ["41", 0], "image": ["8", 0]},
                    "class_type": "ImageUpscaleWithModel",
                    "_meta": {"title": "Upscale Image (using Model)"},
                },
                "41": {
                    "inputs": {"model_name": "RealESRGAN_x2.pth"},
                    "class_type": "UpscaleModelLoader",
                    "_meta": {"title": "Load Upscale Model"},
                },
                "42": {
                    "inputs": {
                        "filename_prefix": "Lumina_",
                        "with_workflow": True,
                        "metadata_extra": '{\n  "Title": "Image generated by Lumina AI",\n  "Software": "Lumina AI App",\n  "Category": "StableDiffusion",\n}',
                        "image": ["40", 0],
                    },
                    "class_type": "Save image with extra metadata [Crystools]",
                    "_meta": {"title": "🪛 Save image with extra metadata"},
                },
            },
        }
        return workflow, seed

    async def submit_to_comfyui(self, workflow: dict) -> dict:
        """Submit workflow and wait for result."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{COMFYUI_HOST}/prompt",
                    json=workflow,
                    timeout=aiohttp.ClientTimeout(total=120),
                ) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        return {"error": f"ComfyUI rejected request: {error_text}"}
                    result = await response.json()
                    prompt_id = result.get("prompt_id")

                for _ in range(60):
                    await asyncio.sleep(1)
                    async with session.get(f"{COMFYUI_HOST}/history/{prompt_id}") as hr:
                        if hr.status == 200:
                            history = await hr.json()
                            if prompt_id in history:
                                outputs = history[prompt_id].get("outputs", {})
                                if "42" in outputs:
                                    img = outputs["42"]["images"][0]
                                    img_path = os.path.join(
                                        COMFYUI_OUTPUT_DIR,
                                        img.get("subfolder", ""),
                                        img["filename"],
                                    )

                                    with open(img_path, "rb") as f:
                                        import base64

                                        encoded = base64.b64encode(f.read()).decode(
                                            "utf-8"
                                        )

                                    return {
                                        "success": True,
                                        "image_path": img_path,
                                        "image_base64": encoded,
                                        "prompt_id": prompt_id,
                                    }
            return {"error": "Timeout"}
        except Exception as e:
            return {"error": str(e)}

    async def generate_image(self, description: str, size: str = "768x768") -> dict:
        return await self.generate_image_direct(description, size)

    async def generate_image_direct(
        self, prompt: str, size: str = "768x768", seed: Optional[int] = None
    ) -> dict:
        if not self.validate_prompt(prompt):
            return {"success": False, "error": "Restricted keywords"}
        try:
            width, height = self.parse_size(size)
            workflow, used_seed = self.build_workflow(prompt, width, height, seed=seed)
            result = await self.submit_to_comfyui(workflow)
            if result.get("success"):
                result.update(
                    {
                        "generated_prompt": prompt,
                        "size": f"{width}x{height}",
                        "seed": used_seed,
                        "message": f"Đã tạo xong ảnh! ({width}x{height}, seed: {used_seed})",
                    }
                )
            return result
        finally:
            await self.cleanup_vram()


image_generation_service = ImageGenerationService()
