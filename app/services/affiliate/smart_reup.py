"""
Smart Reup Service using ComfyUI.

Transforms existing videos to bypass anti-duplicate detection
algorithms on TikTok and Shopee by:
1. Stripping all metadata/EXIF
2. Visual hash alteration (mirror, crop, AI filter via ComfyUI)
3. Audio evasion (pitch shift, tempo change)
"""

import os
import json
import logging
import subprocess
import aiohttp
import asyncio
import uuid
import time
from typing import Optional, Dict, Any, List

logger = logging.getLogger(__name__)

# ComfyUI configuration
COMFYUI_URL = os.getenv("COMFYUI_URL", "http://127.0.0.1:8188")
REUP_STORAGE = os.path.join("storage", "affiliate", "reup")


class SmartReupService:
    """
    Smart re-upload service using ComfyUI for video transformation.

    Pipeline:
    1. Strip metadata (FFmpeg/exiftool)
    2. Visual transformation (ComfyUI workflow or FFmpeg filters)
    3. Audio transformation (FFmpeg pitch/tempo shift)
    4. Inject new metadata

    Usage:
        service = SmartReupService()
        output = await service.process_video("input.mp4", transforms=["metadata", "visual", "audio"])
    """

    # Available transform operations
    TRANSFORMS = {
        "metadata": "Strip & replace EXIF/metadata",
        "mirror": "Horizontal flip (mirror)",
        "crop": "Slight crop & rescale (1-3%)",
        "color": "Color grade / brightness shift",
        "ai_filter": "AI style transfer via ComfyUI (subtle denoise)",
        "speed": "Slight speed change (+/- 1-2%)",
        "pitch": "Audio pitch shift",
        "overlay": "Add dynamic frame/border overlay",
        "pip": "Picture-in-Picture effect",
    }

    def __init__(self):
        os.makedirs(REUP_STORAGE, exist_ok=True)

    async def check_comfyui_status(self) -> bool:
        """Check if ComfyUI server is running."""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{COMFYUI_URL}/system_stats",
                    timeout=aiohttp.ClientTimeout(total=5),
                ) as resp:
                    return resp.status == 200
        except Exception:
            return False

    async def process_video(
        self,
        input_path: str,
        transforms: Optional[List[str]] = None,
        output_dir: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Process a video through the smart reup pipeline.

        Args:
            input_path: Path to input video file
            transforms: List of transform names to apply
                        Default: ["metadata", "mirror", "crop", "speed", "pitch"]
            output_dir: Output directory (default: REUP_STORAGE)

        Returns:
            {
                "output_path": "/path/to/output.mp4",
                "transforms_applied": [...],
                "error": None or error message
            }
        """
        if not os.path.exists(input_path):
            return {"output_path": None, "transforms_applied": [], "error": f"Input file not found: {input_path}"}

        if transforms is None:
            transforms = ["metadata", "mirror", "crop", "speed", "pitch"]

        output_dir = output_dir or REUP_STORAGE
        os.makedirs(output_dir, exist_ok=True)

        job_id = uuid.uuid4().hex[:12]
        current_path = input_path
        applied = []

        try:
            for transform in transforms:
                next_path = os.path.join(output_dir, f"{job_id}_{transform}.mp4")

                if transform == "metadata":
                    success = await self._strip_metadata(current_path, next_path)
                elif transform == "mirror":
                    success = await self._mirror_video(current_path, next_path)
                elif transform == "crop":
                    success = await self._crop_rescale(current_path, next_path)
                elif transform == "color":
                    success = await self._color_shift(current_path, next_path)
                elif transform == "speed":
                    success = await self._speed_change(current_path, next_path)
                elif transform == "pitch":
                    success = await self._pitch_shift(current_path, next_path)
                elif transform == "ai_filter":
                    success = await self._comfyui_transform(current_path, next_path)
                elif transform == "overlay":
                    success = await self._add_overlay(current_path, next_path)
                else:
                    logger.warning(f"[SmartReup] Unknown transform: {transform}")
                    continue

                if success:
                    # Clean up intermediate files (keep only final)
                    if current_path != input_path and os.path.exists(current_path):
                        os.remove(current_path)
                    current_path = next_path
                    applied.append(transform)
                else:
                    logger.warning(f"[SmartReup] Transform '{transform}' failed, skipping")

            # Rename final output
            final_path = os.path.join(output_dir, f"reup_{job_id}.mp4")
            if current_path != input_path:
                os.rename(current_path, final_path)
            else:
                final_path = input_path  # Nothing was applied

            # Inject new metadata
            if "metadata" in applied:
                await self._inject_metadata(final_path)

            return {
                "output_path": final_path,
                "transforms_applied": applied,
                "error": None,
            }

        except Exception as e:
            logger.error(f"[SmartReup] Pipeline error: {e}", exc_info=True)
            return {"output_path": None, "transforms_applied": applied, "error": str(e)}

    # --- FFmpeg-based transforms ---

    async def _run_ffmpeg(self, args: List[str]) -> bool:
        """Run FFmpeg command."""
        cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"] + args
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode != 0:
                logger.error(f"[SmartReup] FFmpeg error: {stderr.decode()}")
                return False
            return True
        except FileNotFoundError:
            logger.error("[SmartReup] FFmpeg not found. Please install FFmpeg.")
            return False

    async def _strip_metadata(self, input_path: str, output_path: str) -> bool:
        """Strip all metadata from video."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-map_metadata", "-1",
            "-fflags", "+bitexact",
            "-flags:v", "+bitexact",
            "-flags:a", "+bitexact",
            "-c", "copy",
            output_path,
        ])

    async def _mirror_video(self, input_path: str, output_path: str) -> bool:
        """Mirror (horizontal flip) the video."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", "hflip",
            "-c:a", "copy",
            output_path,
        ])

    async def _crop_rescale(self, input_path: str, output_path: str, percent: float = 2.0) -> bool:
        """Slightly crop and rescale to alter pixel hash."""
        # Crop 2% from each edge, then scale back to original size
        crop_factor = (100 - percent * 2) / 100
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", f"crop=iw*{crop_factor}:ih*{crop_factor},scale=iw/{crop_factor}:ih/{crop_factor}",
            "-c:a", "copy",
            output_path,
        ])

    async def _color_shift(self, input_path: str, output_path: str) -> bool:
        """Subtle color/brightness shift."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", "eq=brightness=0.03:contrast=1.02:saturation=1.05",
            "-c:a", "copy",
            output_path,
        ])

    async def _speed_change(self, input_path: str, output_path: str, factor: float = 1.02) -> bool:
        """Slight speed change (+2% by default)."""
        atempo = 1 / factor  # Inverse for audio
        return await self._run_ffmpeg([
            "-i", input_path,
            "-filter:v", f"setpts={1/factor}*PTS",
            "-filter:a", f"atempo={factor}",
            output_path,
        ])

    async def _pitch_shift(self, input_path: str, output_path: str) -> bool:
        """Subtle audio pitch shift using rubberband."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-af", "asetrate=44100*1.02,aresample=44100",
            "-c:v", "copy",
            output_path,
        ])

    async def _add_overlay(self, input_path: str, output_path: str) -> bool:
        """Add a subtle border/frame overlay."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", "pad=iw+20:ih+20:10:10:black",
            "-c:a", "copy",
            output_path,
        ])

    async def _inject_metadata(self, video_path: str) -> bool:
        """Inject realistic new metadata into the video."""
        temp = video_path + ".tmp.mp4"
        success = await self._run_ffmpeg([
            "-i", video_path,
            "-metadata", "creation_time=" + time.strftime("%Y-%m-%dT%H:%M:%S"),
            "-metadata", "encoder=Lavf60.16.100",
            "-c", "copy",
            temp,
        ])
        if success:
            os.replace(temp, video_path)
        return success

    # --- ComfyUI-based transforms ---

    async def _comfyui_transform(self, input_path: str, output_path: str) -> bool:
        """
        Send video frames to ComfyUI for AI-based transformation.
        Uses img2img with very low denoise strength (~0.05) to subtly
        alter pixel data without visible quality loss.
        """
        from .comfyui_workflow import comfyui_client

        if not await comfyui_client.is_available():
            logger.warning("[SmartReup] ComfyUI not available, skipping AI filter")
            return False

        try:
            # 1. Extract frames from video
            frames_dir = os.path.join(REUP_STORAGE, f"frames_{uuid.uuid4().hex[:8]}")
            os.makedirs(frames_dir, exist_ok=True)

            extract_ok = await self._run_ffmpeg([
                "-i", input_path,
                "-vf", "fps=1",  # 1 frame per second to keep manageable
                f"{frames_dir}/frame_%04d.png",
            ])
            if not extract_ok:
                return False

            # 2. Process each frame through ComfyUI
            processed_dir = os.path.join(REUP_STORAGE, f"processed_{uuid.uuid4().hex[:8]}")
            os.makedirs(processed_dir, exist_ok=True)

            frame_files = sorted([
                f for f in os.listdir(frames_dir) if f.endswith('.png')
            ])

            if not frame_files:
                logger.warning("[SmartReup] No frames extracted")
                return False

            logger.info(f"[SmartReup] Processing {len(frame_files)} frames through ComfyUI...")

            for frame_file in frame_files:
                input_frame = os.path.join(frames_dir, frame_file)
                output_frame = os.path.join(processed_dir, frame_file)

                success = await comfyui_client.process_image(
                    input_path=input_frame,
                    output_path=output_frame,
                    denoise=0.05,  # Very subtle - enough to change hash
                )

                if not success:
                    # If ComfyUI fails for a frame, copy original
                    import shutil
                    shutil.copy2(input_frame, output_frame)

            # 3. Reassemble frames into video (keeping original audio)
            reassemble_ok = await self._run_ffmpeg([
                "-framerate", "1",
                "-i", f"{processed_dir}/frame_%04d.png",
                "-i", input_path,
                "-map", "0:v",
                "-map", "1:a?",
                "-c:v", "libx264",
                "-c:a", "copy",
                "-pix_fmt", "yuv420p",
                "-shortest",
                output_path,
            ])

            # 4. Cleanup temp directories
            import shutil
            shutil.rmtree(frames_dir, ignore_errors=True)
            shutil.rmtree(processed_dir, ignore_errors=True)

            return reassemble_ok

        except Exception as e:
            logger.error(f"[SmartReup] ComfyUI transform failed: {e}", exc_info=True)
            return False

    def list_transforms(self) -> Dict[str, str]:
        """Return available transforms with descriptions."""
        return self.TRANSFORMS.copy()
