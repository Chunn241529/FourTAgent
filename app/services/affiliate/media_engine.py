"""
Media Engine for Affiliate Automation.

Renders product review videos by combining:
- Product images (downloaded from scraper)
- TTS audio (optional, from existing VieNeu TTS service)
- Subtitles/text overlays
- Background music (optional)
"""

import os
import logging
import aiohttp
import asyncio
import urllib.parse
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)

# Storage paths
MEDIA_STORAGE = os.path.join("storage", "affiliate", "media")
BGM_DIR = os.path.join("storage", "affiliate", "bgm")

# Valid image extensions
_VALID_IMG_EXT = {"jpg", "jpeg", "png", "gif", "webp", "bmp"}


class MediaEngine:
    """
    Video assembly engine for affiliate content.

    Usage:
        engine = MediaEngine()
        video_path = await engine.render_video(
            images=["img1.jpg", "img2.jpg"],
            script="Kịch bản review...",
            use_tts=True,
            audio_path=None,  # auto-generate via TTS if use_tts=True
        )
    """

    def __init__(self):
        os.makedirs(MEDIA_STORAGE, exist_ok=True)
        os.makedirs(BGM_DIR, exist_ok=True)

    @staticmethod
    def _get_image_ext(url: str) -> str:
        """Extract image extension from URL, defaulting to jpg."""
        try:
            path = urllib.parse.urlparse(url).path  # e.g. /file/abc123
            _, ext = os.path.splitext(path)  # ext = "" or ".png"
            ext = ext.lstrip(".").lower().split("?")[0]
            if ext in _VALID_IMG_EXT:
                return ext
        except Exception:
            pass
        return "jpg"

    async def download_images(
        self, image_urls: List[str], output_dir: str
    ) -> List[str]:
        """Download product images and return local file paths."""
        os.makedirs(output_dir, exist_ok=True)
        paths = []

        async with aiohttp.ClientSession() as session:
            for i, url in enumerate(image_urls):
                try:
                    async with session.get(url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                        if resp.status == 200:
                            content_type = resp.headers.get('Content-Type', '').lower()
                            if 'svg' in content_type:
                                logger.info(f"[MediaEngine] Skipping SVG image: {url}")
                                continue
                            
                            ext = self._get_image_ext(url)
                            filename = f"img_{i:03d}.{ext}"
                            filepath = os.path.join(output_dir, filename)
                            with open(filepath, "wb") as f:
                                f.write(await resp.read())
                            paths.append(filepath)
                except Exception as e:
                    logger.warning(f"[MediaEngine] Failed to download {url}: {e}")

        return paths

    async def render_video(
        self,
        images: List[str],
        script_text: str,
        output_path: str,
        use_tts: bool = False,
        tts_audio_path: Optional[str] = None,
        bgm_path: Optional[str] = None,
        duration_per_image: float = 3.0,
        resolution: tuple = (1080, 1920),  # 9:16 vertical
        fps: int = 30,
    ) -> Optional[str]:
        """
        Render a final video from images + audio + subtitles.

        Args:
            images: List of local image file paths
            script_text: Text for subtitles overlay
            output_path: Where to save the output MP4
            use_tts: Whether TTS audio was used
            tts_audio_path: Path to TTS audio file (if use_tts=True)
            bgm_path: Path to background music file (optional)
            duration_per_image: Seconds per image slide
            resolution: Output video resolution (width, height)
            fps: Output FPS

        Returns:
            Path to rendered video or None on failure
        """
        try:
            # Import moviepy lazily to avoid import errors if not installed
            from moviepy import (
                ImageClip, AudioFileClip, CompositeVideoClip,
                CompositeAudioClip, TextClip, concatenate_videoclips,
            )

            if not images:
                logger.error("[MediaEngine] No images provided for video render")
                return None

            width, height = resolution
            clips = []

            for img_path in images:
                if not os.path.exists(img_path):
                    continue

                clip = (
                    ImageClip(img_path)
                    .resized(height=height)
                    .with_duration(duration_per_image)
                )

                # Center crop to target resolution (ensure even dimensions for libx264)
                if clip.w > width:
                    clip = clip.cropped(
                        x_center=clip.w / 2,
                        width=width,
                    )

                # Ensure dimensions are divisible by 2 (libx264 requirement)
                if clip.w % 2 != 0:
                    clip = clip.resized(width=clip.w - 1)
                if clip.h % 2 != 0:
                    clip = clip.resized(height=clip.h - 1)

                clips.append(clip)

            if not clips:
                logger.error("[MediaEngine] No valid image clips created")
                return None

            # Concatenate image clips
            video = concatenate_videoclips(clips, method="compose")

            # Add subtitle overlay
            if script_text:
                # Split text into chunks for subtitle timing
                words = script_text.split()
                # estimate chunk size based on video duration instead of len(clips)
                total_duration = video.duration if video.duration else (len(images) * duration_per_image)
                chunks_count = max(1, int(total_duration / 2)) # roughly 2 secs per chunk
                chunk_size = max(1, len(words) // chunks_count)
                
                txt_clips = []
                for i in range(chunks_count):
                    start_word = i * chunk_size
                    end_word = min((i + 1) * chunk_size, len(words))
                    subtitle_text = " ".join(words[start_word:end_word])
                    
                    if subtitle_text:
                        txt_clip = (
                            TextClip(
                                font="Arial",
                                text=subtitle_text,
                                font_size=42,
                                color="white",
                                stroke_color="black",
                                stroke_width=2,
                                size=(width - 80, None),
                                method="caption",
                            )
                            .with_position(("center", height - 300))
                            .with_duration(2.0)
                            .with_start(i * 2.0)
                        )
                        txt_clips.append(txt_clip)

                video = CompositeVideoClip([video] + txt_clips)

            # Add audio
            audio_clips = []

            if use_tts and tts_audio_path and os.path.exists(tts_audio_path):
                tts_audio = AudioFileClip(tts_audio_path)
                # Match video duration
                if tts_audio.duration > video.duration:
                    tts_audio = tts_audio.subclipped(0, video.duration)
                audio_clips.append(tts_audio)

            if bgm_path and os.path.exists(bgm_path):
                bgm = AudioFileClip(bgm_path)
                if bgm.duration > video.duration:
                    bgm = bgm.subclipped(0, video.duration)
                # Lower BGM volume if TTS is present
                volume = 0.15 if use_tts else 0.5
                bgm = bgm.with_effects([bgm.fx.volumex(volume)])
                audio_clips.append(bgm)

            if audio_clips:
                final_audio = CompositeAudioClip(audio_clips)
                video = video.with_audio(final_audio)

            # Render output
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            video.write_videofile(
                output_path,
                fps=fps,
                codec="libx264",
                audio_codec="aac",
                threads=4,
                logger=None,  # Suppress moviepy's verbose logging
            )

            logger.info(f"[MediaEngine] ✅ Video rendered: {output_path}")
            return output_path

        except ImportError:
            logger.error("[MediaEngine] moviepy not installed. Run: pip install moviepy")
            return None
        except Exception as e:
            logger.error(f"[MediaEngine] Render failed: {e}", exc_info=True)
            return None

    def list_bgm(self) -> List[str]:
        """List available background music files."""
        if not os.path.exists(BGM_DIR):
            return []
        return [
            os.path.join(BGM_DIR, f)
            for f in os.listdir(BGM_DIR)
            if f.endswith((".mp3", ".wav", ".ogg"))
        ]
