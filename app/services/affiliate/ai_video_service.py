import logging
import asyncio
import uuid
import time
import os
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

class AIVideoService:
    """
    Service to interface with AI Video Generation Providers (Kling, Veo, Wan).
    Currently implemented as a mock that simulates the API calls and delays,
    returning a valid response structure.
    """
    
    SUPPORTED_MODELS = ["kling", "veo", "wan"]
    
    def __init__(self):
        # In-memory mock job storage
        self.mock_jobs = {}

    async def start_generation(
        self,
        prompt: str,
        image_path: Optional[str] = None,
        model: str = "kling",
        api_key: str = "",
        model_image_path: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Starts an AI video generation job.
        
        Args:
            prompt: Formatted prompt (e.g. from LLM ai_video_prompt)
            image_path: Optional path to an initial image
            model: 'kling', 'veo', or 'wan'
            api_key: The user's API Key
            model_image_path: Optional path to a custom model image
            
        Returns:
            Dict containing 'job_id' and 'status'
        """
        logger.info(f"[AIVideoService] Starting generation with model={model}, prompt={prompt[:30]}...")
        if image_path:
            logger.info(f"[AIVideoService] Using product image at {image_path}")
        if model_image_path:
            logger.info(f"[AIVideoService] Using custom model image at {model_image_path}")

        if not api_key:
            return {"error": "API Key is required to use AI Video Generation."}
            
        if model not in self.SUPPORTED_MODELS:
            return {"error": f"Unsupported model: {model}"}

        logger.info(f"[{model.upper()}] Starting video generation. Prompt: {prompt[:50]}...")
        
        # Simulated API Call
        await asyncio.sleep(1) # Network latency
        
        job_id = f"{model}_{uuid.uuid4().hex[:8]}"
        self.mock_jobs[job_id] = {
            "status": "processing",
            "progress": 0,
            "created_at": time.time(),
            "model": model,
            "result_url": None
        }
        
        return {
            "job_id": job_id,
            "status": "processing",
            "error": None
        }

    async def check_status(self, job_id: str, api_key: str) -> Dict[str, Any]:
        """
        Checks the status of a video generation job.
        
        Returns:
            Dict containing 'status' ('processing', 'success', 'failed'), 
            'progress' (0-100), and 'result_url' if successful.
        """
        if job_id not in self.mock_jobs:
            return {"error": "Job not found"}
            
        job = self.mock_jobs[job_id]
        
        # Simulate progress over time (approx 20 seconds to complete)
        elapsed = time.time() - job["created_at"]
        
        if elapsed > 20: # Done
            job["status"] = "success"
            job["progress"] = 100
            # Return a dummy sample video URL or local path
            # For demonstration, we create a dummy mp4 in affiliate outputs
            output_dir = os.path.join("storage", "affiliate", "output")
            os.makedirs(output_dir, exist_ok=True)
            dummy_path = os.path.join(output_dir, f"{job_id}.mp4")
            
            # Touch an empty file just so it exists if needed
            if not os.path.exists(dummy_path):
                with open(dummy_path, "wb") as f:
                    # Write a minimal MP4 header or just empty
                    f.write(b"") 
                    
            job["result_url"] = dummy_path
            
        elif elapsed > 10:
            job["progress"] = 75
        elif elapsed > 5:
            job["progress"] = 40
        else:
            job["progress"] = 10
            
        return {
            "job_id": job_id,
            "status": job["status"],
            "progress": job["progress"],
            "result_url": job["result_url"],
            "error": None
        }

# Global singleton
ai_video_service = AIVideoService()
