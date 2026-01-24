from app.services.music_service import music_service
import time

print("Searching for music 'lofi hip hop'...")
result = music_service.search_music("lofi hip hop", max_results=2)
print(f"Search result: {result}")

print("\nPlaying music (mock test if mpv missing, real if present)...")
# Note: This might make sound if mpv is installed!
play_res = music_service.play_music("lofi hip hop")
print(f"Play result: {play_res}")

time.sleep(5)

print("\nStopping music...")
stop_res = music_service.stop_music()
print(f"Stop result: {stop_res}")
