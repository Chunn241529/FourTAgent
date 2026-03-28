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
        "flip_h": "Horizontal flip (left-right)",
        "crop": "Scale 97% + pad (alters pixel hash)",
        "manual_crop": "Per-edge crop with user-specified percentages",
        "zoom": "Zoom in 3-5% to change composition (most effective for pHash)",
        "color": "Color grade / brightness shift (eq filter)",
        "noise": "Add subtle noise to alter pixel hash",
        "recode": "Re-encode at different quality to change compression artifacts",
        "ai_filter": "AI style transfer via ComfyUI (subtle denoise)",
        "speed": "Slight speed change (+/- 1-2%)",
        "pitch": "Audio pitch shift via rubberband",
        "strip_audio": "Remove audio track entirely",
        "overlay": "Add black border/padding",
        "pip": "Picture-in-Picture effect",
        "trim_end": "Cắt N giây cuối video (mặc định 4s)",
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
                        Default: ["metadata", "mirror", "zoom", "color", "speed", "pitch", "recode"]
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
            transforms = ["metadata", "mirror", "zoom", "color", "speed", "pitch"]
        else:
            transforms = self.reorder_transforms(transforms)

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
                elif transform == "flip_h":
                    success = await self._flip_horizontal_video(current_path, next_path)
                elif transform == "strip_audio":
                    success = await self._strip_audio(current_path, next_path)
                elif transform == "zoom":
                    success = await self._zoom_video(current_path, next_path)
                elif transform == "noise":
                    success = await self._add_noise(current_path, next_path)
                elif transform == "recode":
                    success = await self._recode_video(current_path, next_path)
                elif transform == "trim_end":
                    success = await self._trim_end(current_path, next_path)
                elif transform == "manual_crop":
                    # manual_crop requires crop_settings, handled separately in smart_reup_douyin_task
                    logger.warning("[SmartReup] manual_crop requires crop_settings, skipping")
                    continue
                elif transform == "ai_logo_removal":
                    # ai_logo_removal is handled separately in smart_reup_douyin_task
                    continue
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

    async def _run_ffmpeg(self, args: List[str], log_level: str = "error") -> bool:
        """Run FFmpeg command. log_level: 'error' or 'info' for debugging."""
        cmd = ["ffmpeg", "-y", "-hide_banner"]
        if log_level == "info":
            cmd += ["-loglevel", "info"]
        else:
            cmd += ["-loglevel", "error"]
        cmd += args
        logger.info(f"[SmartReup] FFmpeg cmd: {' '.join(cmd)}")
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            if proc.returncode != 0:
                err = stderr.decode()
                logger.error(f"[SmartReup] FFmpeg error (code {proc.returncode}): {err}")
                return False
            if log_level == "info":
                logger.info(f"[SmartReup] FFmpeg stdout: {stdout.decode()}")
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

    async def _flip_horizontal_video(self, input_path: str, output_path: str) -> bool:
        """Horizontal flip (left-right mirror)."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", "hflip",
            "-c:a", "copy",
            output_path,
        ])

    async def _crop_rescale(self, input_path: str, output_path: str, percent: float = 2.0) -> bool:
        """Scale down slightly to alter pixel hash. Uses scale+pad to maintain resolution."""
        crop_pct = 1.0 - (percent / 100.0)
        # Scale down then pad back to original size - changes pixel hash
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", f"scale=iw*{crop_pct}:ih*{crop_pct},pad=iw:ih:(ow-iw)/2:(oh-ih)/2",
            "-c:a", "copy",
            output_path,
        ])

    async def _manual_crop(
        self,
        input_path: str,
        output_path: str,
        crop_settings: Dict[str, float],
    ) -> bool:
        """
        Crop specific edges by percentage.
        crop_settings values are percentages (0-10) for top, right, bottom, left.
        """
        top_pct = crop_settings.get("top", 0)
        bottom_pct = crop_settings.get("bottom", 0)
        right_pct = crop_settings.get("right", 0)
        left_pct = crop_settings.get("left", 0)

        # Compute scaled dimensions from percentage crop, then pad to center
        # crop_w = iw * (1 - (left + right) / 100)
        # crop_h = ih * (1 - (top + bottom) / 100)
        w_expr = f"iw*(1-({left_pct}+{right_pct})/100)"
        h_expr = f"ih*(1-({top_pct}+{bottom_pct})/100)"
        x_expr = f"({w_expr})/2"
        y_expr = f"({h_expr})/2"
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", f"crop={w_expr}:{h_expr}:{x_expr}:{y_expr}",
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

    async def _zoom_video(self, input_path: str, output_path: str, scale: float = 1.04) -> bool:
        """
        Zoom in slightly (default 4%) and center crop back to original size.
        This is one of the most effective techniques for bypassing pHash.
        """
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", f"scale={scale}*iw:{scale}*ih:force_original_aspect_ratio=increase,crop=iw:ih",
            "-c:a", "copy",
            output_path,
        ])

    async def _add_noise(self, input_path: str, output_path: str) -> bool:
        """
        Add subtle Gaussian noise to alter pixel hash.
        noise=alls=0.3:all=random adds very subtle noise.
        """
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", "noise=alls=1:allf=t",
            "-c:a", "copy",
            output_path,
        ])

    async def _recode_video(self, input_path: str, output_path: str, crf: int = 23) -> bool:
        """
        Re-encode the video at a different quality to change compression artifacts.
        Using a different CRF and preset changes the bitstream enough to alter pHash.
        """
        return await self._run_ffmpeg([
            "-i", input_path,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", str(crf),
            "-c:a", "copy",
            output_path,
        ])

    async def _speed_change(self, input_path: str, output_path: str, factor: float = 1.02) -> bool:
        """Slight speed change (+2% by default). Video-only if no audio."""
        has_audio = await self._has_audio_stream(input_path)
        if has_audio:
            return await self._run_ffmpeg([
                "-i", input_path,
                "-filter:v", f"setpts={1/factor}*PTS",
                "-af", f"atempo={factor}",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "18",
                "-c:a", "aac",
                "-b:a", "192k",
                output_path,
            ])
        else:
            # No audio - just change video speed
            return await self._run_ffmpeg([
                "-i", input_path,
                "-filter:v", f"setpts={1/factor}*PTS",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "18",
                output_path,
            ])

    async def _pitch_shift(self, input_path: str, output_path: str, semitones: float = 1.5) -> bool:
        """
        Subtle audio pitch shift by semitones. Skips if no audio stream.
        Uses actual sample rate from input instead of hardcoded 44100.
        """
        if not await self._has_audio_stream(input_path):
            logger.info("[SmartReup] No audio stream, skipping pitch shift")
            # Copy file as-is since there's nothing to pitch-shift
            return await self._run_ffmpeg([
                "-i", input_path,
                "-c:v", "copy",
                output_path,
            ])
        sample_rate = await self._get_audio_sample_rate(input_path)
        ratio = 2 ** (semitones / 12)
        return await self._run_ffmpeg([
            "-i", input_path,
            "-af", f"asetrate={sample_rate}*{ratio},aresample={sample_rate}",
            "-c:v", "copy",
            output_path,
        ])

    async def _trim_end(self, input_path: str, output_path: str, seconds: float = 4.0) -> bool:
        """
        Cắt N giây cuối video.
        Lấy duration bằng ffprobe, rồi dùng -t để giới hạn thời lượng.
        """
        duration = await self._get_video_duration(input_path)
        if duration <= seconds:
            logger.warning(f"[SmartReup] Video too short ({duration:.1f}s) to trim {seconds}s, skipping")
            return await self._run_ffmpeg([
                "-i", input_path,
                "-c", "copy",
                output_path,
            ])
        new_duration = duration - seconds
        return await self._run_ffmpeg([
            "-i", input_path,
            "-t", f"{new_duration:.3f}",
            "-c", "copy",
            output_path,
        ])

    async def _strip_audio(self, input_path: str, output_path: str) -> bool:
        """Remove audio track entirely."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-an",
            "-c:v", "copy",
            output_path,
        ])

    async def _extract_audio(self, input_path: str, output_path: str) -> bool:
        """Extract audio track to a separate file (mp3)."""
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vn",
            "-c:a", "libmp3lame",
            "-q:a", "2",
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
                "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
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

    async def _blur_region(
        self,
        input_path: str,
        output_path: str,
        x: int,
        y: int,
        w: int,
        h: int,
    ) -> bool:
        """
        Apply heavy boxblur to a rectangular region (e.g., subtitle area).
        Uses split/overlay to apply blur only to the specified region.
        """
        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", f"split=2[bg][vid];[vid]crop={w}:{h}:{x}:{y},boxblur=25[blurred];[bg][blurred]overlay={x}:{y}:enable='between(t,0,99999)'",
            "-c:a", "copy",
            output_path,
        ])

    async def _burn_subtitles(
        self,
        input_path: str,
        output_path: str,
        subtitle_path: str,
        style: Optional[Dict[str, Any]] = None,
    ) -> bool:
        """
        Burn subtitles from SRT/ASS file into the video using FFmpeg.
        style: optional dict with 'font_size', 'font_color', 'position' (top/bottom)
        """
        import subprocess as sp

        if style is None:
            style = {}

        font_size = style.get("font_size", 18)
        font_color = style.get("font_color", "white")
        position = style.get("position", "bottom")

        # Convert color name to ASS format
        color_map = {
            "white": "&H00FFFFFF",
            "yellow": "&H00FFFF00",
            "red": "&H000000FF",
            "green": "&H000FF00",
        }
        ass_color = color_map.get(font_color.lower(), "&H00FFFFFF")

        # Position: force_style
        force_style = f"FontSize={font_size},PrimaryColour={ass_color}"
        if position == "top":
            force_style += ",Alignment=10"  # top center
        else:
            force_style += ",Alignment=2"  # bottom center

        # Build filter complex
        vf = f"subtitles='{subtitle_path}':force_style='{force_style}'"

        return await self._run_ffmpeg([
            "-i", input_path,
            "-vf", vf,
            "-c:a", "copy",
            output_path,
        ])

    def _generate_srt_from_text(self, text: str, duration: float, output_path: str) -> str:
        """
        Generate a simple SRT file from plain text.
        Splits text into sentences, assigns equal duration to each.
        Returns path to generated SRT file.
        """
        import re

        # Split into sentences
        sentences = re.split(r'(?<=[.!?])\s+', text.strip())
        sentences = [s.strip() for s in sentences if s.strip()]

        if not sentences:
            sentences = [text.strip()]

        num_chunks = len(sentences)
        chunk_duration = duration / num_chunks

        srt_content = []
        for i, sentence in enumerate(sentences):
            start = self._seconds_to_srt_time(i * chunk_duration)
            end = self._seconds_to_srt_time((i + 1) * chunk_duration)
            srt_content.append(f"{i + 1}\n{start} --> {end}\n{sentence}\n")

        srt_path = output_path if output_path else os.path.join(REUP_STORAGE, f"auto_subtitle_{uuid.uuid4().hex[:8]}.srt")
        with open(srt_path, "w", encoding="utf-8") as f:
            f.write("\n".join(srt_content))

        return srt_path

    def _seconds_to_srt_time(self, seconds: float) -> str:
        """Convert seconds to SRT time format: HH:MM:SS,mmm"""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        millis = int((seconds - int(seconds)) * 1000)
        return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"

    async def _ai_logo_removal(self, input_path: str, output_path: str) -> bool:
        """
        Extract frames -> generate mask for watermark areas -> inpaint via ComfyUI -> reassemble.
        For simplicity, creates a heuristic mask covering the bottom-right corner
        (common Douyin watermark location). In production, use SAM or AI-assisted
        watermark detection for precise masks.
        """
        from .comfyui_workflow import comfyui_client

        if not await comfyui_client.is_available():
            logger.warning("[SmartReup] ComfyUI not available for logo removal")
            return False

        try:
            frames_dir = os.path.join(REUP_STORAGE, f"logo_frames_{uuid.uuid4().hex[:8]}")
            os.makedirs(frames_dir, exist_ok=True)

            # Extract all frames at original fps
            extract_ok = await self._run_ffmpeg([
                "-i", input_path,
                f"{frames_dir}/frame_%04d.png",
            ])
            if not extract_ok:
                return False

            processed_dir = os.path.join(REUP_STORAGE, f"logo_processed_{uuid.uuid4().hex[:8]}")
            os.makedirs(processed_dir, exist_ok=True)

            frame_files = sorted([f for f in os.listdir(frames_dir) if f.endswith('.png')])
            if not frame_files:
                return False

            # For each frame: create a mask image and inpaint
            for frame_file in frame_files:
                frame_path = os.path.join(frames_dir, frame_file)
                processed_path = os.path.join(processed_dir, frame_file)

                # Create a simple mask (bottom-right 15% x 8% region - common Douyin logo spot)
                mask_path = self._create_watermark_mask(frame_path, frames_dir)

                success = await comfyui_client.process_inpaint(
                    input_path=frame_path,
                    mask_path=mask_path,
                    output_path=processed_path,
                    denoise=0.7,
                )
                if not success:
                    import shutil
                    shutil.copy2(frame_path, processed_path)

            # Get original fps from input video
            fps = await self._get_video_fps(input_path)

            # Reassemble video
            reassemble_ok = await self._run_ffmpeg([
                "-framerate", str(fps),
                "-i", f"{processed_dir}/frame_%04d.png",
                "-i", input_path,
                "-map", "0:v",
                "-map", "1:a?",
                "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                "-c:v", "libx264",
                "-c:a", "copy",
                "-pix_fmt", "yuv420p",
                "-shortest",
                output_path,
            ])

            import shutil
            shutil.rmtree(frames_dir, ignore_errors=True)
            shutil.rmtree(processed_dir, ignore_errors=True)

            return reassemble_ok

        except Exception as e:
            logger.error(f"[SmartReup] AI logo removal failed: {e}", exc_info=True)
            return False

    def _create_watermark_mask(self, frame_path: str, out_dir: str) -> str:
        """
        Create a mask image for the watermark region.
        Returns path to the mask PNG.
        """
        from PIL import Image, ImageDraw

        img = Image.open(frame_path)
        w, h = img.size

        # Douyin watermark is typically bottom-right
        mask = Image.new("L", (w, h), 0)  # black = keep, white = inpaint
        mask_draw = ImageDraw.Draw(mask)

        # Bottom-right region: 15% from right, 8% from bottom
        x1 = int(w * 0.85)
        y1 = int(h * 0.92)
        x2 = w
        y2 = h
        mask_draw.rectangle([x1, y1, x2, y2], fill=255)

        mask_path = os.path.join(out_dir, f"mask_{os.path.basename(frame_path)}")
        mask.save(mask_path)
        return mask_path

    async def _get_video_dimensions(self, input_path: str) -> tuple[int, int]:
        """Get width and height of a video file using ffprobe."""
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=s=0:p=0", input_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            parts = stdout.decode().strip().split(',')
            w = int(parts[0])
            h = int(parts[1])
            return (w, h)
        except Exception:
            return (1920, 1080)  # Default fallback

    async def _get_video_fps(self, input_path: str) -> float:
        """Get FPS of a video file using ffprobe."""
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=r_frame_rate",
            "-of", "csv=p=0", input_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            fps_str = stdout.decode().strip().split('\n')[0]
            # Handle fraction format like "30000/1001"
            if '/' in fps_str:
                num, denom = fps_str.split('/')
                return float(num) / float(denom)
            return float(fps_str)
        except Exception:
            return 30.0  # Default fallback

    async def _has_audio_stream(self, input_path: str) -> bool:
        """Check if video file has an audio stream."""
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=codec_type",
            "-of", "csv=p=0", input_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            return "audio" in stdout.decode().lower()
        except Exception:
            return False

    async def _get_audio_sample_rate(self, input_path: str) -> int:
        """Get audio sample rate of a video file using ffprobe."""
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate",
            "-of", "csv=p=0", input_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            rate_str = stdout.decode().strip().split('\n')[0]
            return int(rate_str)
        except Exception:
            return 44100  # Default fallback

    async def _get_video_duration(self, input_path: str) -> float:
        """Get duration of a video file in seconds using ffprobe."""
        cmd = [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0", input_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await proc.communicate()
            return float(stdout.decode().strip().split('\n')[0])
        except Exception:
            return 0.0

    def list_transforms(self) -> Dict[str, str]:
        """Return available transforms with descriptions."""
        return self.TRANSFORMS.copy()

    @staticmethod
    def reorder_transforms(transforms: List[str]) -> List[str]:
        """
        Reorder transforms to ensure correct pipeline order:
        - strip_audio always runs last (after speed/pitch which need audio)
        - trim_end runs before strip_audio but after visual transforms
        - mirror and flip_h are treated as the same operation (deduplicated)
        """
        result = []
        seen = set()
        strip_audio = None
        trim_end = None

        # mirror and flip_h are the same hflip operation
        EQUIVALENT_GROUPS = {"mirror": "hflip_group", "flip_h": "hflip_group"}

        for t in transforms:
            if t == "strip_audio":
                strip_audio = t
                continue
            if t == "trim_end":
                trim_end = t
                continue

            # Check equivalence groups
            group_key = EQUIVALENT_GROUPS.get(t, t)
            if group_key in seen:
                continue
            seen.add(group_key)
            result.append(t)

        # trim_end before strip_audio, both at end
        if trim_end:
            result.append(trim_end)
        if strip_audio:
            result.append(strip_audio)
        return result
