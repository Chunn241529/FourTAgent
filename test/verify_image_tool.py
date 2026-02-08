import sys
import os
import json
import asyncio
from unittest.mock import MagicMock, patch

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.services.tool_service import ToolService


async def test_generate_image_tool():
    print("Testing generate_image tool parameter parsing...")

    # Mock image_generation_service to avoid actual API calls
    with patch("app.services.tool_service.image_generation_service") as mock_service:
        # Setup mock return value
        mock_service.generate_image_direct.return_value = {
            "success": True,
            "message": "Image generated",
            "size": "1024x1024",
            "seed": 12345,
        }

        tool_service = ToolService()

        # Test case 1: Prompt with size
        args_str = json.dumps({"prompt": "a beautiful cat", "size": "1024x1024"})

        print(f"Executing tool with args: {args_str}")
        result = tool_service.execute_tool("generate_image", args_str)

        # Verify call arguments
        # Note: synchronous wrapper calls async/await
        # expected call on mock_service.generate_image_direct
        call_args = mock_service.generate_image_direct.call_args
        if call_args:
            args, kwargs = call_args
            print(f"Called with: args={args}, kwargs={kwargs}")

            # Check prompt
            assert (
                args[0] == "a beautiful cat"
            ), f"Expected prompt 'a beautiful cat', got {args[0]}"
            # Check size
            assert args[1] == "1024x1024", f"Expected size '1024x1024', got {args[1]}"

            print("✅ Test 1 Passed: size='1024x1024' correctly passed to service")
        else:
            print("❌ Test 1 Failed: Service not called")

        # Test case 2: Default size
        args_str_default = json.dumps({"prompt": "a dog"})

        print(f"Executing tool with args: {args_str_default}")
        result = tool_service.execute_tool("generate_image", args_str_default)

        call_args = mock_service.generate_image_direct.call_args
        if call_args:
            args, kwargs = call_args
            print(f"Called with: args={args}, kwargs={kwargs}")

            assert args[0] == "a dog"
            # Default in tool_service is 768x768
            assert (
                args[1] == "768x768"
            ), f"Expected default size '768x768', got {args[1]}"

            print("✅ Test 2 Passed: Default size '768x768' used when not specified")
        else:
            print("❌ Test 2 Failed: Service not called")


if __name__ == "__main__":
    asyncio.run(test_generate_image_tool())
