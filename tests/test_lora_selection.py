import sys
import os
import json
from unittest.mock import MagicMock

# Add the project root to sys.path to import the service
sys.path.append("/home/trung/Documents/4T_task")

from app.services.image_generation_service import ImageGenerationService


def test_lora_selection():
    service = ImageGenerationService()

    test_cases = [
        {
            "name": "Animal prompt",
            "prompt": "a cute cat playing with a ball",
            "expected_loras": {
                "39": ["None", "None", "None", "None"],
                "43": ["None", "None", "None", "None"],
            },
        },
        {
            "name": "1 girl prompt (realistic)",
            "prompt": "1 girl, realistic style, high quality",
            "expected_loras": {
                "39": [
                    "betterhands.safetensors",
                    "betterfeets.safetensors",
                    "girl_face.safetensors",
                    "None",
                ],
                "43": ["None", "None", "None", "None"],
            },
        },
        {
            "name": "1 girl with 2D style",
            "prompt": "1 girl, anime style, colorful",
            "expected_loras": {
                "39": [
                    "betterhands.safetensors",
                    "betterfeets.safetensors",
                    "girl_face.safetensors",
                    "None",
                ],
                "43": ["2d.safetensors", "None", "None", "None"],
            },
        },
        {
            "name": "3D style prompt (no person)",
            "prompt": "a futuristic car, 3d render, octanerender",
            "expected_loras": {
                "39": ["None", "None", "None", "None"],
                "43": ["3d.safetensors", "None", "None", "None"],
            },
        },
        {
            "name": "Person (generic) with 3D style",
            "prompt": "a man standing, 3d model",
            "expected_loras": {
                "39": [
                    "betterhands.safetensors",
                    "betterfeets.safetensors",
                    "None",
                    "None",
                ],
                "43": ["3d.safetensors", "None", "None", "None"],
            },
        },
        {
            "name": "Vietnamese keywords - Animal",
            "prompt": "con mèo dễ thương",
            "expected_loras": {
                "39": ["None", "None", "None", "None"],
                "43": ["None", "None", "None", "None"],
            },
        },
    ]

    for case in test_cases:
        print(f"Testing: {case['name']}...")
        workflow, seed = service.build_workflow(case["prompt"])

        # Extract LoRAs from node 39 and 43
        node_39 = workflow["prompt"]["39"]["inputs"]
        node_43 = workflow["prompt"]["43"]["inputs"]

        actual_39 = [node_39[f"lora_0{i}"] for i in range(1, 5)]
        actual_43 = [node_43[f"lora_0{i}"] for i in range(1, 5)]

        assert (
            actual_39 == case["expected_loras"]["39"]
        ), f"Failed {case['name']} (node 39): Expected {case['expected_loras']['39']}, got {actual_39}"
        assert (
            actual_43 == case["expected_loras"]["43"]
        ), f"Failed {case['name']} (node 43): Expected {case['expected_loras']['43']}, got {actual_43}"
        print(f"  Result: Node 39: {actual_39}")
        print(f"  Result: Node 43: {actual_43}")
        print("  PASSED")


if __name__ == "__main__":
    try:
        test_lora_selection()
        print("\nAll tests passed successfully!")
    except Exception as e:
        print(f"\nTest failed: {e}")
        sys.exit(1)
