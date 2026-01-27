import sys
import os
import json
import logging

# Add project root to path
sys.path.append(os.getcwd())

# Mock configuration if needed
logging.basicConfig(level=logging.INFO)

try:
    from app.services.tool_service import ToolService
except ImportError:
    print("Error: Could not import ToolService. Make sure you are in the project root.")
    sys.exit(1)


def test_tools():
    print("Initializing ToolService...")
    tool_service = ToolService()

    print("\n--- Testing create_file ---")
    test_file = "test_tool_verify.txt"
    content = "Hello from verification script!"
    result = tool_service.execute_tool(
        "create_file", {"path": test_file, "content": content}
    )
    print(f"Result: {result}")

    print("\n--- Testing read_file ---")
    result = tool_service.execute_tool("read_file", {"path": test_file})
    print(f"Result: {result}")

    print("\n--- Testing search_file ---")
    result = tool_service.execute_tool("search_file", {"query": "test_tool_verify"})
    print(f"Result: {result}")

    # Cleanup
    try:
        home = os.path.expanduser("~")
        path = os.path.join(home, "Downloads", test_file)
        if os.path.exists(path):
            os.remove(path)
            print(f"\nCleaned up: {path}")
    except Exception as e:
        print(f"Cleanup failed: {e}")


if __name__ == "__main__":
    test_tools()
