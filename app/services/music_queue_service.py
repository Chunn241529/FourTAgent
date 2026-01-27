import logging
import json
from typing import Dict, Any, Optional
from app.services.music_service import music_service

logger = logging.getLogger(__name__)


class MusicQueueService:
    def __init__(self):
        pass

    def add_to_queue(self, url: str) -> str:
        """
        Extracts stream info for a song and returns a JSON command to add it to the client's queue.
        """
        # Reuse play_music logic to get stream URL and metadata
        # We need to parse the JSON returned by play_music because it returns a string
        try:
            play_result_json = music_service.play_music(url)
            play_result = json.loads(play_result_json)

            if "error" in play_result:
                return play_result_json

            # return action: add_to_queue
            result = {
                "action": "add_to_queue",
                "item": {
                    "url": play_result.get("url"),
                    "title": play_result.get("title"),
                    "thumbnail": play_result.get("thumbnail"),
                    "duration": play_result.get("duration"),
                    "original_url": url,
                },
            }
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            logger.error(f"Error in add_to_queue: {e}")
            return json.dumps({"error": str(e)}, ensure_ascii=False)

    def next_music(self) -> str:
        """Returns command to skip to next track."""
        return json.dumps({"action": "next_music"}, ensure_ascii=False)

    def previous_music(self) -> str:
        """Returns command to go to previous track."""
        return json.dumps({"action": "previous_music"}, ensure_ascii=False)

    def pause_music(self) -> str:
        """Returns command to pause playback."""
        return json.dumps({"action": "pause_music"}, ensure_ascii=False)

    def resume_music(self) -> str:
        """Returns command to resume playback."""
        return json.dumps({"action": "resume_music"}, ensure_ascii=False)

    def stop_music(self) -> str:
        """Returns command to stop playback."""
        return json.dumps({"action": "stop_music"}, ensure_ascii=False)


# Global Access
music_queue_service = MusicQueueService()
