import ollama
import numpy as np
import logging
from typing import List
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

logger = logging.getLogger(__name__)

_embedding_lock = threading.Lock()


class EmbeddingService:
    DIM = 2560  # qwen3-embedding:4b output dimension
    MAX_WORKERS = 4  # Max concurrent embedding requests

    @staticmethod
    def get_embedding(text: str, max_length: int = 1024) -> np.ndarray:
        """Tạo embedding cho text"""
        try:
            if len(text) > max_length:
                text = text[:max_length]
            with _embedding_lock:
                resp = ollama.embeddings(model="qwen3-embedding:4b", prompt=text)
            return np.array(resp["embedding"])
        except Exception as e:
            logger.error(f"Lỗi khi tạo embedding từ Ollama: {e}")
            return np.zeros(EmbeddingService.DIM)

    @staticmethod
    def _get_embedding_safe(text: str, max_length: int = 1024) -> np.ndarray:
        """Wrapper for thread-safe embedding generation"""
        return EmbeddingService.get_embedding(text, max_length)

    @staticmethod
    def get_embeddings_batch(
        texts: List[str], max_length: int = 1024
    ) -> List[np.ndarray]:
        """Tạo embeddings cho batch texts sử dụng parallel processing"""
        if not texts:
            return []
        
        embeddings = [np.zeros(EmbeddingService.DIM)] * len(texts)
        
        with ThreadPoolExecutor(max_workers=EmbeddingService.MAX_WORKERS) as executor:
            future_to_idx = {
                executor.submit(EmbeddingService._get_embedding_safe, text, max_length): idx
                for idx, text in enumerate(texts)
            }
            
            for future in as_completed(future_to_idx):
                idx = future_to_idx[future]
                try:
                    embeddings[idx] = future.result()
                except Exception as e:
                    logger.warning(f"Failed to get embedding for text {idx}: {e}")
                    
        return embeddings
