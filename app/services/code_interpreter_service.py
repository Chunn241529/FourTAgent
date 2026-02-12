import subprocess
import logging
import sys
import tempfile
import os

logger = logging.getLogger(__name__)


class CodeInterpreterService:
    @staticmethod
    def execute_python(code: str) -> dict:
        """
        Execute arbitrary Python code in a separate process.
        Returns a dict with 'success', 'output', and 'error'.
        """
        logger.info("Executing Python code via subprocess...")

        # Create a temporary file to hold the code
        # We use delete=False because Windows can't execute open files,
        # and it's generally safer to close before executing on all platforms.
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".py", delete=False, encoding="utf-8"
        ) as temp_file:
            temp_file.write(code)
            temp_file_path = temp_file.name

        try:
            # Run the temporary file in a separate python process
            # Capture stdout and stderr
            result = subprocess.run(
                [sys.executable, temp_file_path],
                capture_output=True,
                text=True,
                timeout=30,  # Timeout after 30 seconds to prevent infinite loops
            )

            output = result.stdout
            error = result.stderr

            success = result.returncode == 0

            return {
                "success": success,
                "output": output,
                "error": error if error else None,
            }

        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "output": "",
                "error": "Execution timed out after 30 seconds.",
            }
        except Exception as e:
            logger.error(f"Code execution failed: {e}")
            return {"success": False, "output": "", "error": str(e)}
        finally:
            # Clean up the temporary file
            if os.path.exists(temp_file_path):
                try:
                    os.remove(temp_file_path)
                except:
                    pass
