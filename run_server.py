#!/usr/bin/env python3
"""
Server Runner with Hot Restart Support.
Press R + Enter to restart the server.
Press Q + Enter to quit.
"""
import subprocess
import sys
import os
import threading
import signal

# Server command
SERVER_CMD = [
    sys.executable,
    "-m",
    "uvicorn",
    "app.main:app",
    "--host",
    "0.0.0.0",
    "--port",
    "8000",
    "--reload",
]


class ServerRunner:
    def __init__(self):
        self.process = None
        self.running = True

    def start_server(self):
        """Start the uvicorn server subprocess."""
        print("\n🚀 Starting server...")
        print("=" * 50)
        print("  R + Enter  →  Restart Server")
        print("  Q + Enter  →  Quit")
        print("=" * 50)

        self.process = subprocess.Popen(
            SERVER_CMD,
            cwd=os.path.dirname(os.path.abspath(__file__)),
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        return self.process

    def stop_server(self):
        """Stop the current server process."""
        if self.process:
            print("\n⏹️  Stopping server...")
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None

    def restart_server(self):
        """Restart the server."""
        self.stop_server()
        self.start_server()
        print("\n🔄 Server restarted!\n")

    def input_listener(self):
        """Listen for keyboard input in a separate thread."""
        while self.running:
            try:
                cmd = input().strip().lower()
                if cmd == "r":
                    self.restart_server()
                elif cmd == "q":
                    self.running = False
                    self.stop_server()
                    print("\n👋 Goodbye!")
                    os._exit(0)
            except EOFError:
                break
            except KeyboardInterrupt:
                break

    def run(self):
        """Main run loop."""
        # Start input listener thread
        input_thread = threading.Thread(target=self.input_listener, daemon=True)
        input_thread.start()

        # Start server
        self.start_server()

        try:
            # Wait for the server process
            while self.running and self.process:
                self.process.wait()
                if self.running:
                    # If server crashed, show message
                    print(
                        "\n⚠️  Server stopped unexpectedly. Press R to restart or Q to quit."
                    )
                    while self.running and not self.process:
                        # Wait for restart command
                        import time

                        time.sleep(0.5)
        except KeyboardInterrupt:
            print("\n\n🛑 Interrupted by user.")
            self.stop_server()


if __name__ == "__main__":
    runner = ServerRunner()
    runner.run()
