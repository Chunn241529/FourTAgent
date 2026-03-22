"""
ComfyUI Workflow templates for Smart Reup.

Contains the JSON workflow definitions for video/image
transformation via ComfyUI API.
"""

import os
import json
import asyncio
import aiohttp
import logging
import uuid
import shutil
from typing import Optional, Dict, Any, List

logger = logging.getLogger(__name__)

COMFYUI_URL = os.getenv("COMFYUI_HOST", "http://127.0.0.1:8188")
COMFYUI_OUTPUT_DIR = os.getenv("COMFYUI_OUTPUT_DIR", "/tmp/comfyui_output")


# ─── Minimal img2img workflow for subtle visual alteration ───
# Uses very low denoise (0.05) to imperceptibly change pixel data
# enough to alter the visual hash without visible quality loss.

def build_img2img_workflow(
    input_image_path: str,
    denoise_strength: float = 0.05,
    checkpoint: str = "sd_xl_base_1.0.safetensors",
    positive_prompt: str = "high quality, sharp, detailed",
    negative_prompt: str = "blurry, low quality, watermark",
    seed: int = -1,
) -> Dict[str, Any]:
    """
    Build a ComfyUI img2img workflow JSON for subtle image alteration.

    This workflow:
    1. Loads a checkpoint model
    2. Loads the input image
    3. Encodes it to latent space via VAE
    4. Applies KSampler with very low denoise
    5. Decodes back to image
    6. Saves output

    The low denoise strength ensures the output looks identical
    to the human eye but has different pixel values (different hash).
    """
    if seed == -1:
        import random
        seed = random.randint(0, 2**32 - 1)

    workflow = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed,
                "steps": 4,
                "cfg": 1.5,
                "sampler_name": "euler",
                "scheduler": "normal",
                "denoise": denoise_strength,
                "model": ["4", 0],
                "positive": ["6", 0],
                "negative": ["7", 0],
                "latent_image": ["12", 0],
            },
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {
                "ckpt_name": checkpoint,
            },
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": positive_prompt,
                "clip": ["4", 1],
            },
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": negative_prompt,
                "clip": ["4", 1],
            },
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["3", 0],
                "vae": ["4", 2],
            },
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "reup",
                "images": ["8", 0],
            },
        },
        "11": {
            "class_type": "LoadImage",
            "inputs": {
                "image": os.path.basename(input_image_path),
            },
        },
        "12": {
            "class_type": "VAEEncode",
            "inputs": {
                "pixels": ["11", 0],
                "vae": ["4", 2],
            },
        },
    }

    return workflow


def build_inpaint_workflow(
    input_image_path: str,
    mask_image_path: str,
    denoise_strength: float = 0.7,
    checkpoint: str = "sd_xl_base_1.0.safetensors",
    positive_prompt: str = "high quality, sharp, clean background, no watermark, no text",
    negative_prompt: str = "watermark, text, logo, blurry, low quality",
    seed: int = -1,
) -> Dict[str, Any]:
    """
    Build a ComfyUI inpainting workflow JSON for logo/watermark removal.
    Requires a mask image where white = areas to regenerate.
    """
    if seed == -1:
        import random
        seed = random.randint(0, 2**32 - 1)

    workflow = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "seed": seed,
                "steps": 20,
                "cfg": 7.0,
                "sampler_name": "euler",
                "scheduler": "normal",
                "denoise": denoise_strength,
                "model": ["4", 0],
                "positive": ["6", 0],
                "negative": ["7", 0],
                "latent_image": ["2", 0],
            },
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {
                "ckpt_name": checkpoint,
            },
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": positive_prompt,
                "clip": ["4", 1],
            },
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": negative_prompt,
                "clip": ["4", 1],
            },
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["3", 0],
                "vae": ["4", 2],
            },
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "inpaint",
                "images": ["8", 0],
            },
        },
        "2": {
            "class_type": "VAEEncodeForInpaint",
            "inputs": {
                "pixels": ["11", 0],
                "mask": ["12", 0],
                "vae": ["4", 2],
            },
        },
        "11": {
            "class_type": "LoadImage",
            "inputs": {
                "image": os.path.basename(input_image_path),
            },
        },
        "12": {
            "class_type": "LoadImage",
            "inputs": {
                "image": os.path.basename(mask_image_path),
            },
        },
    }
    return workflow


class ComfyUIClient:
    """
    Client for interacting with ComfyUI's HTTP API.

    Supports:
    - Uploading images
    - Queuing workflows (prompts)
    - Polling for completion
    - Downloading results
    """

    def __init__(self, base_url: Optional[str] = None):
        self.base_url = base_url or COMFYUI_URL
        self.client_id = uuid.uuid4().hex[:12]

    async def is_available(self) -> bool:
        """Check if ComfyUI server is reachable."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{self.base_url}/system_stats",
                    timeout=aiohttp.ClientTimeout(total=5),
                ) as resp:
                    return resp.status == 200
        except Exception:
            return False

    async def upload_image(self, image_path: str) -> Optional[str]:
        """Upload an image to ComfyUI's input folder."""
        try:
            async with aiohttp.ClientSession() as session:
                data = aiohttp.FormData()
                data.add_field(
                    'image',
                    open(image_path, 'rb'),
                    filename=os.path.basename(image_path),
                    content_type='image/png',
                )

                async with session.post(
                    f"{self.base_url}/upload/image",
                    data=data,
                    timeout=aiohttp.ClientTimeout(total=30),
                ) as resp:
                    if resp.status == 200:
                        result = await resp.json()
                        return result.get("name")
                    else:
                        error = await resp.text()
                        logger.error(f"[ComfyUI] Upload failed: {resp.status} {error}")
                        return None
        except Exception as e:
            logger.error(f"[ComfyUI] Upload error: {e}")
            return None

    async def queue_prompt(self, workflow: Dict[str, Any]) -> Optional[str]:
        """Queue a workflow prompt and return the prompt_id."""
        try:
            payload = {
                "prompt": workflow,
                "client_id": self.client_id,
            }

            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.base_url}/prompt",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    if resp.status == 200:
                        result = await resp.json()
                        prompt_id = result.get("prompt_id")
                        logger.info(f"[ComfyUI] Queued prompt: {prompt_id}")
                        return prompt_id
                    else:
                        error = await resp.text()
                        logger.error(f"[ComfyUI] Queue failed: {resp.status} {error}")
                        return None
        except Exception as e:
            logger.error(f"[ComfyUI] Queue error: {e}")
            return None

    async def wait_for_completion(
        self, prompt_id: str, timeout: int = 120, poll_interval: float = 1.0
    ) -> bool:
        """Poll ComfyUI history until the prompt is complete."""
        elapsed = 0.0
        while elapsed < timeout:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(
                        f"{self.base_url}/history/{prompt_id}",
                        timeout=aiohttp.ClientTimeout(total=5),
                    ) as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            if prompt_id in data:
                                status = data[prompt_id].get("status", {})
                                if status.get("completed", False) or status.get("status_str") == "success":
                                    logger.info(f"[ComfyUI] Prompt {prompt_id} completed")
                                    return True
                                if status.get("status_str") == "error":
                                    logger.error(f"[ComfyUI] Prompt {prompt_id} failed")
                                    return False
            except Exception:
                pass

            await asyncio.sleep(poll_interval)
            elapsed += poll_interval

        logger.warning(f"[ComfyUI] Prompt {prompt_id} timed out after {timeout}s")
        return False

    async def get_output_images(self, prompt_id: str) -> List[str]:
        """Get output image paths from a completed prompt."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{self.base_url}/history/{prompt_id}",
                    timeout=aiohttp.ClientTimeout(total=5),
                ) as resp:
                    if resp.status != 200:
                        return []
                    data = await resp.json()

            if prompt_id not in data:
                return []

            outputs = data[prompt_id].get("outputs", {})
            image_paths = []

            for node_id, node_output in outputs.items():
                images = node_output.get("images", [])
                for img in images:
                    filename = img.get("filename")
                    subfolder = img.get("subfolder", "")
                    if filename:
                        full_path = os.path.join(COMFYUI_OUTPUT_DIR, subfolder, filename)
                        if os.path.exists(full_path):
                            image_paths.append(full_path)

            return image_paths

        except Exception as e:
            logger.error(f"[ComfyUI] Get output error: {e}")
            return []

    async def process_image(
        self,
        input_path: str,
        output_path: str,
        denoise: float = 0.05,
    ) -> bool:
        """
        Full pipeline: upload image → run img2img → download result.

        Args:
            input_path: Path to input image
            output_path: Where to save the processed image
            denoise: Denoise strength (lower = more subtle changes)

        Returns:
            True if successful
        """
        if not await self.is_available():
            logger.warning("[ComfyUI] Server not available")
            return False

        # Upload
        uploaded_name = await self.upload_image(input_path)
        if not uploaded_name:
            return False

        # Build and queue workflow
        workflow = build_img2img_workflow(
            input_image_path=uploaded_name,
            denoise_strength=denoise,
        )
        prompt_id = await self.queue_prompt(workflow)
        if not prompt_id:
            return False

        # Wait for completion
        success = await self.wait_for_completion(prompt_id, timeout=120)
        if not success:
            return False

        # Get output
        output_images = await self.get_output_images(prompt_id)
        if not output_images:
            logger.error("[ComfyUI] No output images found")
            return False

        # Copy first output to target path
        shutil.copy2(output_images[0], output_path)
        logger.info(f"[ComfyUI] Processed image saved to {output_path}")
        return True

    async def process_inpaint(
        self,
        input_path: str,
        mask_path: str,
        output_path: str,
        denoise: float = 0.7,
    ) -> bool:
        """
        Full pipeline for inpainting: upload image + mask → run inpaint workflow → save result.

        Args:
            input_path: Path to input image
            mask_path: Path to mask image (white = areas to regenerate)
            output_path: Where to save the processed image
            denoise: Denoise strength for inpainting

        Returns:
            True if successful
        """
        if not await self.is_available():
            logger.warning("[ComfyUI] Server not available for inpaint")
            return False

        # Upload image and mask
        uploaded_image = await self.upload_image(input_path)
        uploaded_mask = await self.upload_image(mask_path)
        if not uploaded_image or not uploaded_mask:
            logger.error("[ComfyUI] Failed to upload image or mask for inpaint")
            return False

        # Build and queue inpaint workflow
        workflow = build_inpaint_workflow(
            input_image_path=uploaded_image,
            mask_image_path=uploaded_mask,
            denoise_strength=denoise,
        )
        prompt_id = await self.queue_prompt(workflow)
        if not prompt_id:
            return False

        # Wait for completion (inpainting takes longer, use 180s timeout)
        success = await self.wait_for_completion(prompt_id, timeout=180)
        if not success:
            return False

        # Get output
        output_images = await self.get_output_images(prompt_id)
        if not output_images:
            logger.error("[ComfyUI] No output images found for inpaint")
            return False

        # Copy first output to target path
        shutil.copy2(output_images[0], output_path)
        logger.info(f"[ComfyUI] Inpainted image saved to {output_path}")
        return True


# Singleton
comfyui_client = ComfyUIClient()
