import logging
import subprocess
import json
import shutil
from typing import List, Dict, Optional
import yt_dlp

logger = logging.getLogger(__name__)


class MusicService:
    def __init__(self):
        self.current_process: Optional[subprocess.Popen] = None
        self._check_dependencies()

    def _check_dependencies(self):
        """Check if mpv is installed."""
        if not shutil.which("mpv"):
            logger.warning("mpv is not installed. Music playback will not work.")

    def search_music(self, query: str, max_results: int = 5) -> str:
        """
        Search for music using yt-dlp.
        Returns a JSON string of results.
        """
        logger.info(f"Searching music for: {query}")
        try:
            ydl_opts = {
                "default_search": "ytsearch",
                "quiet": True,
                "extract_flat": True,
                "noplaylist": True,
                "limit": max_results,
                "nocheckcertificate": True,
                "ignoreerrors": True,
                "extractor_args": {"youtube": {"player_client": ["android", "ios"]}},
            }

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                # ytsearch<N>:query syntax for N results
                search_query = f"ytsearch{max_results}:{query}"
                result = ydl.extract_info(search_query, download=False)

            entries = []
            if "entries" in result:
                for entry in result["entries"]:
                    entries.append(
                        {
                            "title": entry.get("title", "Unknown"),
                            "url": entry.get("url", ""),
                            "duration": entry.get("duration", 0),
                            "channel": entry.get("channel", "Unknown"),
                        }
                    )

            logger.info(
                f"Music search found {len(entries)} results: {json.dumps(entries[:2], ensure_ascii=False)}..."
            )
            return json.dumps({"results": entries}, ensure_ascii=False)

        except Exception as e:
            logger.error(f"Music search error: {e}")
            return json.dumps({"results": [], "error": str(e)})

    def play_music(self, url: str) -> str:
        """
        Get stream URL and metadata for client-side playback.
        Accepts a YouTube video URL (from search_music results) and extracts the audio stream URL.
        Returns JSON with url, title, thumbnail for the Flutter app to play.
        """
        logger.info(f"Getting stream URL for: {url}")

        if not url.startswith(("http://", "https://")):
            return json.dumps(
                {"error": "Invalid URL. Use search_music first to get video URLs."}
            )

        try:
            # Get actual stream URL and thumbnail using yt-dlp
            ydl_opts = {
                "quiet": True,
                "format": "bestaudio/best",
                "noplaylist": True,
                "nocheckcertificate": True,
                "ignoreerrors": True,
                "extractor_args": {"youtube": {"player_client": ["android", "ios"]}},
            }

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)

                if info is None:
                    return json.dumps(
                        {
                            "error": "Unable to extract video information. The video might be restricted or unavailable."
                        }
                    )

                stream_url = info.get("url", url)
                title = info.get("title", "Unknown")
                thumbnail = info.get("thumbnail", "")
                duration = info.get("duration", 0)

            logger.info(f"Stream URL extracted for: {title}")

            return json.dumps(
                {
                    "action": "play_music",
                    "url": stream_url,
                    "title": title,
                    "thumbnail": thumbnail,
                    "duration": duration,
                },
                ensure_ascii=False,
            )

        except Exception as e:
            logger.error(f"Error getting music URL: {e}")
            return json.dumps({"error": str(e)})

    def stop_music(self) -> str:
        """Stop current music playback."""
        if self.current_process:
            self.current_process.terminate()
            self.current_process = None
            return "Music stopped."
        return "No music playing."


# Global instance
music_service = MusicService()
