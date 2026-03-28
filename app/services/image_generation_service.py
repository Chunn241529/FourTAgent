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
COMFYUI_INPUT_DIR = os.getenv(
    "COMFYUI_INPUT_DIR", COMFYUI_OUTPUT_DIR.replace("output", "input")
)

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

    async def cleanup_all_vram(self):
        """Aggressively clean up ComfyUI VRAM and unload Ollama models to prevent OOM."""
        logger.info("Starting aggressive VRAM cleanup before image generation...")
        await self.cleanup_vram()

        # Unload Ollama models
        try:
            models_to_unload = [
                "Lumina:latest",
                "Lumina-small:latest",
                "qwen3-vl:8b-instruct",
            ]
            async with aiohttp.ClientSession() as session:
                ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434")
                for model in models_to_unload:
                    try:
                        payload = {"model": model, "keep_alive": 0}
                        async with session.post(
                            f"{ollama_host}/api/generate", json=payload, timeout=2
                        ) as resp:
                            if resp.status == 200:
                                logger.info(
                                    f"Ollama model {model} unloaded to free VRAM"
                                )
                    except Exception as e:
                        logger.debug(f"Failed to unload {model}: {e}")
        except Exception as e:
            logger.warning(f"Ollama cleanup failed: {e}")

        await self.cleanup_all_ram()

    async def cleanup_all_ram(self):
        """Aggressively clean up system RAM (CPU) to prevent Out of Memory."""
        import gc
        import ctypes

        # 1. Force python Garbage Collection
        collected = gc.collect()
        logger.info(f"Python GC collected {collected} objects.")

        # 2. Release unused libc memory back to the OS
        try:
            libc = ctypes.CDLL("libc.so.6")
            libc.malloc_trim(0)
            logger.info("Executed malloc_trim(0) to release RAM back to OS")
        except Exception as e:
            logger.debug(f"malloc_trim not supported/failed: {e}")

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
        keywords_girl = [
            "1girl",
            "1 girl",
            "girl",
            "woman",
            "female",
            "lady",
            "sister",
            "mother",
            "aunt",
            "grandmother",
            "daughter",
            "gái",
            "nữ",
            "cô",
            "bà",
            "chị",
            "em",
            "mẹ",
            "dì",
        ]
        keywords_person = [
            "boy",
            "man",
            "male",
            "brother",
            "father",
            "uncle",
            "grandfather",
            "son",
            "trai",
            "nam",
            "anh",
            "ông",
            "bố",
            "chú",
            "bác",
            "person",
            "human",
            "people",
            "người",
        ]
        # Merge girl keywords into person check for general person detection
        all_person_keywords = keywords_girl + keywords_person

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

        # Specific checks
        is_girl = any(k in prompt_lower for k in keywords_girl)
        has_person = any(k in prompt_lower for k in all_person_keywords)
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
        current_prompt = prompt + ", masterpiece, best quality"

        # LoRA stack logic
        stack_39_config = [{"name": "None", "strength": 0.0}] * 4

        if is_animal:
            # Rule: Animal -> No LoRA
            pass
        elif is_girl:
            # Rule: Girl -> detailed_eye + girl_face
            stack_39_config[0] = {
                "name": "detailed_eye.safetensors",
                "strength": 0.8,
            }
            stack_39_config[1] = {
                "name": "girl_face.safetensors",
                "strength": 0.8,
            }
        elif has_person:
            # Rule: Man/Other Person -> detailed_eye
            stack_39_config[0] = {
                "name": "detailed_eye.safetensors",
                "strength": 0.8,
            }
        elif is_anime_style:
            # Rule: 2D/Anime/3D -> detailed_eye (+ Lumina_2D selected above)
            stack_39_config[0] = {
                "name": "detailed_eye.safetensors",
                "strength": 0.8,
            }

        negative_prompt = "embedding:easynegative, (worst quality, low quality:1.4), (nude, naked, nsfw:1.2), bad hands, bad fingers, extra fingers, missing fingers, fused fingers, deformed fingers, mutated hands, malformed hands, poorly drawn hands, incorrect hand anatomy, broken fingers, twisted fingers, long fingers, short fingers, duplicate fingers, extra limbs, malformed limbs, bad proportions, disfigured, mutation, ugly hands, blurry hands, low detail hands, cropped hands, out of frame hands"

        workflow = {
            # "client_id": self.client_id,
            # "extra_data": {"extra_pnginfo": {"workflow": {}}},
            # "prompt": {
            #     "3": {
            #         "inputs": {
            #             "seed": seed,
            #             "steps": steps,
            #             "cfg": cfg,
            #             "sampler_name": "dpmpp_sde",
            #             "scheduler": "karras",
            #             "denoise": 1,
            #             "model": ["39", 0],
            #             "positive": ["6", 0],
            #             "negative": ["7", 0],
            #             "latent_image": ["5", 0],
            #         },
            #         "class_type": "KSampler",
            #         "_meta": {"title": "KSampler"},
            #     },
            #     "4": {
            #         "inputs": {"ckpt_name": ckpt_name},
            #         "class_type": "CheckpointLoaderSimple",
            #         "_meta": {"title": "Load Checkpoint"},
            #     },
            #     "5": {
            #         "inputs": {"width": width, "height": height, "batch_size": 1},
            #         "class_type": "EmptyLatentImage",
            #         "_meta": {"title": "Empty Latent Image"},
            #     },
            #     "6": {
            #         "inputs": {
            #             "text": current_prompt,
            #             "clip": ["39", 1],
            #         },
            #         "class_type": "CLIPTextEncode",
            #         "_meta": {"title": "CLIP Text Encode (Prompt)"},
            #     },
            #     "7": {
            #         "inputs": {
            #             "text": negative_prompt,
            #             "clip": ["39", 1],
            #         },
            #         "class_type": "CLIPTextEncode",
            #         "_meta": {"title": "CLIP Text Encode (Negative)"},
            #     },
            #     "8": {
            #         "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
            #         "class_type": "VAEDecode",
            #         "_meta": {"title": "VAE Decode"},
            #     },
            #     "39": {
            #         "inputs": {
            #             "lora_01": stack_39_config[0]["name"],
            #             "strength_01": stack_39_config[0].get("strength", 0.0),
            #             "lora_02": stack_39_config[1]["name"],
            #             "strength_02": stack_39_config[1].get("strength", 0.0),
            #             "lora_03": stack_39_config[2]["name"],
            #             "strength_03": stack_39_config[2].get("strength", 0.0),
            #             "lora_04": stack_39_config[3]["name"],
            #             "strength_04": stack_39_config[3].get("strength", 0.0),
            #             "model": ["4", 0],
            #             "clip": ["4", 1],
            #         },
            #         "class_type": "Lora Loader Stack (rgthree)",
            #         "_meta": {"title": "Lora Loader Stack (rgthree)"},
            #     },
            #     "40": {
            #         "inputs": {"upscale_model": ["41", 0], "image": ["8", 0]},
            #         "class_type": "ImageUpscaleWithModel",
            #         "_meta": {"title": "Upscale Image (using Model)"},
            #     },
            #     "41": {
            #         "inputs": {"model_name": "RealESRGAN_x2.pth"},
            #         "class_type": "UpscaleModelLoader",
            #         "_meta": {"title": "Load Upscale Model"},
            #     },
            #     "42": {
            #         "inputs": {
            #             "filename_prefix": "Lumina_",
            #             "with_workflow": True,
            #             "metadata_extra": '{\n  "Title": "Image generated by Lumina AI",\n  "Software": "Lumina AI App",\n  "Category": "StableDiffusion",\n}',
            #             "image": ["40", 0],
            #         },
            #         "class_type": "Save image with extra metadata [Crystools]",
            #         "_meta": {"title": "🪛 Save image with extra metadata"},
            #     },
            # },
            "client_id": self.client_id,
            "prompt": {
                "76": {
                    "inputs": {"value": current_prompt},
                    "class_type": "PrimitiveStringMultiline",
                    "_meta": {"title": "Prompt"},
                },
                "78": {
                    "inputs": {
                        "filename_prefix": "Flux2-Klein",
                        "images": ["77:82", 0],
                    },
                    "class_type": "SaveImage",
                    "_meta": {"title": "Save Image"},
                },
                "77:80": {
                    "inputs": {"sampler_name": "euler"},
                    "class_type": "KSamplerSelect",
                    "_meta": {"title": "KSamplerSelect"},
                },
                "77:81": {
                    "inputs": {
                        "noise": ["77:86", 0],
                        "guider": ["77:90", 0],
                        "sampler": ["77:80", 0],
                        "sigmas": ["77:93", 0],
                        "latent_image": ["77:83", 0],
                    },
                    "class_type": "SamplerCustomAdvanced",
                    "_meta": {"title": "SamplerCustomAdvanced"},
                },
                "77:82": {
                    "inputs": {"samples": ["77:81", 0], "vae": ["77:89", 0]},
                    "class_type": "VAEDecode",
                    "_meta": {"title": "VAE Decode"},
                },
                "77:83": {
                    "inputs": {
                        "width": ["77:84", 0],
                        "height": ["77:85", 0],
                        "batch_size": 1,
                    },
                    "class_type": "EmptyFlux2LatentImage",
                    "_meta": {"title": "Empty Flux 2 Latent"},
                },
                "77:84": {
                    "inputs": {"value": width},
                    "class_type": "PrimitiveInt",
                    "_meta": {"title": "Width"},
                },
                "77:85": {
                    "inputs": {"value": height},
                    "class_type": "PrimitiveInt",
                    "_meta": {"title": "Height"},
                },
                "77:86": {
                    "inputs": {
                        "noise_seed": seed,
                    },
                    "class_type": "RandomNoise",
                    "_meta": {"title": "RandomNoise"},
                },
                "77:87": {
                    "inputs": {
                        "unet_name": "tinflux2Klein4B_4bFp8.safetensors",
                        "weight_dtype": "default",
                    },
                    "class_type": "UNETLoader",
                    "_meta": {"title": "Load Diffusion Model"},
                },
                "77:88": {
                    "inputs": {
                        "clip_name": "qwen_3_4b.safetensors",
                        "type": "flux2",
                        "device": "default",
                    },
                    "class_type": "CLIPLoader",
                    "_meta": {"title": "Load CLIP"},
                },
                "77:89": {
                    "inputs": {"vae_name": "flux2-vae.safetensors"},
                    "class_type": "VAELoader",
                    "_meta": {"title": "Load VAE"},
                },
                "77:90": {
                    "inputs": {
                        "cfg": 1,
                        "model": ["77:87", 0],
                        "positive": ["77:92", 0],
                        "negative": ["77:91", 0],
                    },
                    "class_type": "CFGGuider",
                    "_meta": {"title": "CFGGuider"},
                },
                "77:91": {
                    "inputs": {"conditioning": ["77:92", 0]},
                    "class_type": "ConditioningZeroOut",
                    "_meta": {"title": "ConditioningZeroOut"},
                },
                "77:92": {
                    "inputs": {"text": ["76", 0], "clip": ["77:88", 0]},
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode (Positive Prompt)"},
                },
                "77:93": {
                    "inputs": {
                        "steps": 4,
                        "width": ["77:84", 0],
                        "height": ["77:85", 0],
                    },
                    "class_type": "Flux2Scheduler",
                    "_meta": {"title": "Flux2Scheduler"},
                },
            },
        }
        return workflow, seed

    async def submit_to_comfyui(self, workflow: dict, user_id: int = None) -> dict:
        """Submit workflow and wait for result. Copy output to user's cloud folder."""
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
                                # Dynamically find the output node containing images
                                img = None
                                for node_id, node_output in outputs.items():
                                    if (
                                        "images" in node_output
                                        and len(node_output["images"]) > 0
                                    ):
                                        img = node_output["images"][0]
                                        break

                                if img:
                                    img_path = os.path.join(
                                        COMFYUI_OUTPUT_DIR,
                                        img.get("subfolder", ""),
                                        img["filename"],
                                    )

                                    # Copy to user's cloud output folder
                                    final_filename = img["filename"]
                                    final_path = img_path
                                    if user_id is not None:
                                        import shutil

                                        user_output_dir = f"/home/trung/Documents/4T_task/user_data/cloud/{user_id}/output"
                                        os.makedirs(user_output_dir, exist_ok=True)
                                        final_path = os.path.join(
                                            user_output_dir, final_filename
                                        )
                                        shutil.copy2(img_path, final_path)
                                        logger.info(
                                            f"Image copied to user cloud: {final_path}"
                                        )

                                    with open(final_path, "rb") as f:
                                        import base64

                                        encoded = base64.b64encode(f.read()).decode(
                                            "utf-8"
                                        )

                                    return {
                                        "success": True,
                                        "image_path": final_path,
                                        "image_filename": final_filename,
                                        "image_base64": encoded,
                                        "prompt_id": prompt_id,
                                    }
            return {"error": "Timeout"}
        except Exception as e:
            return {"error": str(e)}

    async def generate_image(
        self, description: str, size: str = "768x768", user_id: int = None
    ) -> dict:
        return await self.generate_image_direct(description, size, user_id=user_id)

    async def generate_image_direct(
        self,
        prompt: str,
        size: str = "768x768",
        seed: Optional[int] = None,
        user_id: int = None,
    ) -> dict:
        if not self.validate_prompt(prompt):
            return {"success": False, "error": "Restricted keywords"}
        try:
            # Free VRAM before starting
            await self.cleanup_all_vram()

            # Step 1: LLM generates proper Flux2 prompt from user description
            import ollama as _ollama

            loop = asyncio.get_event_loop()

            lumina_system = (
                "You are an expert AI image prompt engineer for Stable Diffusion (Flux 2 architecture). "
                "The user will describe an image they want (possibly in Vietnamese). "
                "Your job is to create a SINGLE high-quality English prompt for Flux 2 image generation.\n\n"
                "Rules:\n"
                "- Output comma-separated English tags/phrases ONLY, no explanations\n"
                "- Start with the main subject, then style, then quality tags\n"
                "- Include quality boosters: masterpiece, best quality, highly detailed\n"
                "- Include relevant style tags: lighting, composition, art style\n"
                "- Keep it concise (under 80 words)\n"
                "- Do NOT wrap in quotes or code blocks\n\n"
                "Examples:\n"
                "Input: 'con mèo dễ thương trong vườn hoa'\n"
                "Output: cute cat sitting in a flower garden, soft natural lighting, vibrant colors, "
                "masterpiece, best quality, highly detailed, bokeh background\n\n"
                "Input: 'cyberpunk city at night'\n"
                "Output: cyberpunk city at night, neon lights, rain reflections, futuristic buildings, "
                "dark atmosphere, cinematic lighting, masterpiece, best quality, highly detailed, 8k"
            )

            def run_lumina_gen():
                return _ollama.chat(
                    model="Lumina:latest",
                    messages=[
                        {"role": "system", "content": lumina_system},
                        {"role": "user", "content": prompt},
                    ],
                )

            logger.info(f"Generating Flux2 prompt via Lumina from: '{prompt}'")
            lumina_response = await loop.run_in_executor(None, run_lumina_gen)
            flux_prompt = lumina_response.get("message", {}).get("content", "").strip()

            # Clean up LLM output
            if flux_prompt.startswith("```"):
                flux_prompt = "\n".join(flux_prompt.split("\n")[1:-1])
            flux_prompt = flux_prompt.strip('"').strip("'")
            logger.info(f"Final Flux2 generation prompt: {flux_prompt}")

            # Free VRAM after Ollama, before ComfyUI
            await self.cleanup_all_vram()

            width, height = self.parse_size(size)
            workflow, used_seed = self.build_workflow(
                flux_prompt, width, height, seed=seed
            )
            result = await self.submit_to_comfyui(workflow, user_id=user_id)
            if result.get("success"):
                result.update(
                    {
                        "generated_prompt": flux_prompt,
                        "original_prompt": prompt,
                        "size": f"{width}x{height}",
                        "seed": used_seed,
                        "message": f"Đã tạo xong ảnh! ({width}x{height}, seed: {used_seed})",
                    }
                )
            return result
        finally:
            await self.cleanup_vram()

    def _build_edit_workflow(
        self, flux_prompt: str, image1: str, image2: str, seed: Optional[int] = None
    ) -> dict:
        if seed is None:
            seed = random.randint(1, 2**53)

        return {
            "client_id": self.client_id,
            "prompt": {
                "76": {
                    "inputs": {"image": image1},
                    "class_type": "LoadImage",
                    "_meta": {"title": "Load image 1"},
                },
                "81": {
                    "inputs": {"image": image2},
                    "class_type": "LoadImage",
                    "_meta": {"title": "Load Image 2"},
                },
                "94": {
                    "inputs": {
                        "filename_prefix": "__lumina_edit__",
                        "images": ["92:104", 0],
                    },
                    "class_type": "SaveImage",
                    "_meta": {"title": "Save Image"},
                },
                "92:102": {
                    "inputs": {"sampler_name": "euler"},
                    "class_type": "KSamplerSelect",
                    "_meta": {"title": "KSamplerSelect"},
                },
                "92:103": {
                    "inputs": {
                        "noise": ["92:105", 0],
                        "guider": ["92:114", 0],
                        "sampler": ["92:102", 0],
                        "sigmas": ["92:115", 0],
                        "latent_image": ["92:109", 0],
                    },
                    "class_type": "SamplerCustomAdvanced",
                    "_meta": {"title": "SamplerCustomAdvanced"},
                },
                "92:104": {
                    "inputs": {"samples": ["92:103", 0], "vae": ["92:107", 0]},
                    "class_type": "VAEDecode",
                    "_meta": {"title": "VAE Decode"},
                },
                "92:105": {
                    "inputs": {"noise_seed": seed},
                    "class_type": "RandomNoise",
                    "_meta": {"title": "RandomNoise"},
                },
                "92:106": {
                    "inputs": {
                        "unet_name": "tinflux2Klein4B_4bFp8.safetensors",
                        "weight_dtype": "default",
                    },
                    "class_type": "UNETLoader",
                    "_meta": {"title": "Load Diffusion Model"},
                },
                "92:108": {
                    "inputs": {"image": ["92:110", 0]},
                    "class_type": "GetImageSize",
                    "_meta": {"title": "Get Image Size"},
                },
                "92:111": {
                    "inputs": {
                        "clip_name": "qwen_3_4b.safetensors",
                        "type": "flux2",
                        "device": "default",
                    },
                    "class_type": "CLIPLoader",
                    "_meta": {"title": "Load CLIP"},
                },
                "92:115": {
                    "inputs": {
                        "steps": 4,
                        "width": ["92:108", 0],
                        "height": ["92:108", 1],
                    },
                    "class_type": "Flux2Scheduler",
                    "_meta": {"title": "Flux2Scheduler"},
                },
                "92:114": {
                    "inputs": {
                        "cfg": 1,
                        "model": ["92:106", 0],
                        "positive": ["92:122", 0],
                        "negative": ["92:124", 0],
                    },
                    "class_type": "CFGGuider",
                    "_meta": {"title": "CFGGuider"},
                },
                "92:109": {
                    "inputs": {
                        "width": ["92:108", 0],
                        "height": ["92:108", 1],
                        "batch_size": 1,
                    },
                    "class_type": "EmptyFlux2LatentImage",
                    "_meta": {"title": "Empty Flux 2 Latent"},
                },
                "92:110": {
                    "inputs": {
                        "upscale_method": "nearest-exact",
                        "megapixels": 1,
                        "resolution_steps": 1,
                        "image": ["76", 0],
                    },
                    "class_type": "ImageScaleToTotalPixels",
                    "_meta": {"title": "ImageScaleToTotalPixels"},
                },
                "92:127": {
                    "inputs": {"pixels": ["92:85", 0], "vae": ["92:107", 0]},
                    "class_type": "VAEEncode",
                    "_meta": {"title": "VAE Encode"},
                },
                "92:85": {
                    "inputs": {
                        "upscale_method": "nearest-exact",
                        "megapixels": 1,
                        "resolution_steps": 1,
                        "image": ["81", 0],
                    },
                    "class_type": "ImageScaleToTotalPixels",
                    "_meta": {"title": "ImageScaleToTotalPixels"},
                },
                "92:107": {
                    "inputs": {"vae_name": "flux2-vae.safetensors"},
                    "class_type": "VAELoader",
                    "_meta": {"title": "Load VAE"},
                },
                "92:124": {
                    "inputs": {"conditioning": ["92:126", 0], "latent": ["92:123", 0]},
                    "class_type": "ReferenceLatent",
                    "_meta": {"title": "ReferenceLatent"},
                },
                "92:123": {
                    "inputs": {"pixels": ["92:110", 0], "vae": ["92:107", 0]},
                    "class_type": "VAEEncode",
                    "_meta": {"title": "VAE Encode"},
                },
                "92:122": {
                    "inputs": {"conditioning": ["92:125", 0], "latent": ["92:123", 0]},
                    "class_type": "ReferenceLatent",
                    "_meta": {"title": "ReferenceLatent"},
                },
                "92:113": {
                    "inputs": {"text": flux_prompt, "clip": ["92:111", 0]},
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode (Positive Prompt)"},
                },
                "92:87": {
                    "inputs": {"text": "", "clip": ["92:111", 0]},
                    "class_type": "CLIPTextEncode",
                    "_meta": {"title": "CLIP Text Encode ( Negative Prompt)"},
                },
                "92:125": {
                    "inputs": {"conditioning": ["92:113", 0], "latent": ["92:127", 0]},
                    "class_type": "ReferenceLatent",
                    "_meta": {"title": "ReferenceLatent"},
                },
                "92:126": {
                    "inputs": {"conditioning": ["92:87", 0], "latent": ["92:127", 0]},
                    "class_type": "ReferenceLatent",
                    "_meta": {"title": "ReferenceLatent"},
                },
            },
        }

    async def edit_image_direct(
        self,
        prompt: str,
        image1_path: str,
        image2_path: Optional[str] = None,
        user_id: int = None,
        seed: Optional[int] = None,
    ) -> dict:
        try:
            # Aggressively free up VRAM before heavy operations
            await self.cleanup_all_vram()

            import base64
            import shutil
            import ollama

            # Resolve paths
            user_input_dir = (
                f"/home/trung/Documents/4T_task/user_data/cloud/{user_id}/input"
                if user_id
                else ""
            )

            def resolve_path(p: str) -> Optional[str]:
                if not p:
                    return None
                if os.path.isabs(p) and os.path.exists(p):
                    return p
                if user_input_dir:
                    user_path = os.path.join(user_input_dir, p)
                    if os.path.exists(user_path):
                        return user_path
                return None

            img1_full = resolve_path(image1_path)
            if not img1_full:
                return {"success": False, "error": f"Image 1 not found: {image1_path}"}

            img2_full = resolve_path(image2_path) if image2_path else img1_full
            if image2_path and not img2_full:
                return {"success": False, "error": f"Image 2 not found: {image2_path}"}

            # Convert to base64 for vision analysis
            # --- VISION ANALYSIS REMOVED (caused over-generation/hallucination) ---

            loop = asyncio.get_event_loop()

            # Step 1: LLM translates user's edit instruction into Flux2-compatible edit prompt
            # Flux 2 Edit uses reference images + a prompt. The prompt tells Flux2 what the
            # RESULT should look like for the changed area. It should NOT describe the whole image.
            lumina_system = (
                "You are a Flux 2 image editing prompt specialist. "
                "The user provides reference image(s) and an editing instruction (possibly in Vietnamese). "
                "Flux 2 Edit works like inpainting — it keeps the reference image and only changes what "
                "the prompt describes.\n\n"
                "Your job: convert the user's editing instruction into a SHORT English prompt.\n\n"
                "CRITICAL RULES:\n"
                "- Describe ONLY the change, NOT the entire image\n"
                "- Use descriptive result phrases, not action verbs\n"
                "  GOOD: 'red shirt' (describes what should appear)\n"
                "  BAD: 'change the shirt to red' (action verb — Flux doesn't understand actions)\n"
                "- Keep it very short (5-15 words max)\n"
                "- Do NOT add quality tags (no 'masterpiece', 'best quality', '8k', etc.)\n"
                "- Do NOT describe parts of the image that should stay the same\n"
                "- Do NOT wrap in quotes or code blocks\n\n"
                "Examples:\n"
                "Input: 'Đổi màu áo thành đỏ' → Output: red shirt\n"
                "Input: 'Thêm kính mát' → Output: wearing sunglasses\n"
                "Input: 'Đổi nền thành bãi biển' → Output: beach background, sand, ocean\n"
                "Input: 'Đổi tóc thành màu vàng' → Output: blonde hair\n"
                "Input: 'Thêm mũ cowboy' → Output: wearing a cowboy hat\n"
                "Input: 'Remove the person' → Output: empty scene, no person\n\n"
                "Reply with ONLY the result prompt, nothing else."
            )
            lumina_msg = prompt

            def run_lumina():
                return ollama.chat(
                    model="Lumina:latest",
                    messages=[
                        {"role": "system", "content": lumina_system},
                        {"role": "user", "content": lumina_msg},
                    ],
                )

            logger.info("Translating user edit instruction via Lumina...")
            lumina_response = await loop.run_in_executor(None, run_lumina)
            flux_prompt = lumina_response.get("message", {}).get("content", "").strip()

            # Remove any markdown code blocks wrapper from AI output
            if flux_prompt.startswith("```"):
                flux_prompt = "\n".join(flux_prompt.split("\n")[1:-1])
            # Remove quotes if LLM wrapped in quotes
            flux_prompt = flux_prompt.strip('"').strip("'")
            logger.info(f"Final Flux2 edit prompt: {flux_prompt}")

            # Step 3: Copy to ComfyUI input directory
            os.makedirs(COMFYUI_INPUT_DIR, exist_ok=True)
            img1_filename = f"lumina_in_{random.randint(10000, 99999)}_{os.path.basename(img1_full)}"
            img2_filename = (
                img1_filename
                if img1_full == img2_full
                else f"lumina_in_{random.randint(10000, 99999)}_{os.path.basename(img2_full)}"
            )

            shutil.copy(img1_full, os.path.join(COMFYUI_INPUT_DIR, img1_filename))
            if img1_filename != img2_filename:
                shutil.copy(img2_full, os.path.join(COMFYUI_INPUT_DIR, img2_filename))

            workflow = self._build_edit_workflow(
                flux_prompt, img1_filename, img2_filename, seed
            )
            used_seed = workflow["prompt"]["92:105"]["inputs"]["noise_seed"]

            # Step 4: Run workflow
            logger.info(
                "Aggressively freeing VRAM after Ollama usage and before ComfyUI Flux2 generation..."
            )
            await self.cleanup_all_vram()

            logger.info("Submitting edit workflow to ComfyUI...")
            result = await self.submit_to_comfyui(workflow, user_id=user_id)
            if result.get("success"):
                result.update(
                    {
                        "generated_prompt": flux_prompt,
                        "seed": used_seed,
                        "message": f"Ảnh đã được chỉnh sửa xong! (Seed: {used_seed})",
                    }
                )
            return result

        except Exception as e:
            logger.error(f"Error in edit_image_direct: {e}", exc_info=True)
            return {"error": str(e)}
        finally:
            await self.cleanup_vram()


image_generation_service = ImageGenerationService()
