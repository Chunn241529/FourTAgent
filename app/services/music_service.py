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

            return json.dumps({"results": entries}, ensure_ascii=False)

        except Exception as e:
            logger.error(f"Music search error: {e}")
            return json.dumps({"results": [], "error": str(e)})

    def play_music(self, url_or_query: str) -> str:
        """
        Play music using mpv.
        If input is not a URL, it searches first and plays the first result.
        """
        logger.info(f"Request to play: {url_or_query}")

        # Stop existing playback if any
        self.stop_music()

        target_url = url_or_query
        title = "Music"

        # If not a URL, search first
        if not url_or_query.startswith(("http://", "https://")):
            search_res = json.loads(self.search_music(url_or_query, max_results=1))
            if not search_res.get("results"):
                return "No music found for query."
            target_url = search_res["results"][0]["url"]
            title = search_res["results"][0]["title"]

        try:
            # Check for mpv again
            if not shutil.which("mpv"):
                return "Error: 'mpv' player is not installed. Please install it to play music."

            # Start mpv process
            # --no-video for audio only focus (though mpv might show album art window, which is fine)
            # --force-window=immediate to show window if desired, or --no-terminal to suppress output
            self.current_process = subprocess.Popen(
                ["mpv", "--no-video", target_url],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            return f"Playing: {title}"

        except Exception as e:
            logger.error(f"Playback error: {e}")
            return f"Error playing music: {str(e)}"

    def stop_music(self) -> str:
        """Stop current music playback."""
        if self.current_process:
            self.current_process.terminate()
            self.current_process = None
            return "Music stopped."
        return "No music playing."


# Global instance
music_service = MusicService()
