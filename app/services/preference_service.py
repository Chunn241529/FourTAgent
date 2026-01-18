"""
Preference Memory Service - Store and retrieve liked responses for RAG-based learning.

Stores preferred (liked) responses in a separate FAISS index per user.
When generating responses, retrieves similar good examples to inject as context.
"""

import faiss
import numpy as np
import json
import os
import logging
from typing import List, Optional, Tuple
from sqlalchemy.orm import Session

from app.models import ChatMessage as ModelChatMessage, MessageFeedback
from app.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)

PREFERENCE_DIR = "preference_indexes"
os.makedirs(PREFERENCE_DIR, exist_ok=True)


class PreferenceService:
    """Manage preference memory for RAG-based learning from feedback."""

    @staticmethod
    def get_preference_index_path(user_id: int) -> str:
        """Get path for user's preference FAISS index."""
        return os.path.join(PREFERENCE_DIR, f"preference_{user_id}.faiss")

    @staticmethod
    def get_preference_metadata_path(user_id: int) -> str:
        """Get path for user's preference metadata (query-response pairs)."""
        return os.path.join(PREFERENCE_DIR, f"preference_{user_id}_meta.json")

    @staticmethod
    def load_preference_index(user_id: int) -> Tuple[faiss.Index, List[dict]]:
        """Load or create preference FAISS index and metadata."""
        index_path = PreferenceService.get_preference_index_path(user_id)
        meta_path = PreferenceService.get_preference_metadata_path(user_id)

        # Load or create index
        if os.path.exists(index_path):
            index = faiss.read_index(index_path)
        else:
            index = faiss.IndexFlatIP(EmbeddingService.DIM)

        # Load or create metadata
        if os.path.exists(meta_path):
            with open(meta_path, "r", encoding="utf-8") as f:
                metadata = json.load(f)
        else:
            metadata = []

        return index, metadata

    @staticmethod
    def save_preference_index(
        user_id: int, index: faiss.Index, metadata: List[dict]
    ) -> None:
        """Save preference FAISS index and metadata."""
        index_path = PreferenceService.get_preference_index_path(user_id)
        meta_path = PreferenceService.get_preference_metadata_path(user_id)

        faiss.write_index(index, index_path)
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)

    @staticmethod
    def add_preference(message_id: int, user_id: int, db: Session) -> bool:
        """
        Add a liked response to preference index.
        Stores: the user's query + AI response pair.
        """
        try:
            # Get the liked message
            message = (
                db.query(ModelChatMessage)
                .filter(ModelChatMessage.id == message_id)
                .first()
            )
            if not message or message.role != "assistant":
                logger.warning(f"Message {message_id} not found or not assistant")
                return False

            # Get the preceding user message (the query)
            user_message = (
                db.query(ModelChatMessage)
                .filter(
                    ModelChatMessage.conversation_id == message.conversation_id,
                    ModelChatMessage.role == "user",
                    ModelChatMessage.timestamp < message.timestamp,
                )
                .order_by(ModelChatMessage.timestamp.desc())
                .first()
            )

            if not user_message:
                logger.warning(f"No user message found before message {message_id}")
                return False

            # Load current index
            index, metadata = PreferenceService.load_preference_index(user_id)

            # Check if already exists
            for m in metadata:
                if m.get("message_id") == message_id:
                    logger.info(f"Message {message_id} already in preferences")
                    return True

            # Generate embedding for the query
            query_embedding = EmbeddingService.get_embedding(user_message.content)
            query_embedding = query_embedding / (np.linalg.norm(query_embedding) + 1e-8)

            # Add to index
            index.add(np.array([query_embedding]).astype("float32"))
            metadata.append(
                {
                    "message_id": message_id,
                    "query": user_message.content[:500],  # Truncate for storage
                    "response": message.content[:1000],  # Truncate for storage
                }
            )

            # Save
            PreferenceService.save_preference_index(user_id, index, metadata)
            logger.info(
                f"Added preference: message_id={message_id}, total={len(metadata)}"
            )
            return True

        except Exception as e:
            logger.error(f"Error adding preference: {e}")
            return False

    @staticmethod
    def remove_preference(message_id: int, user_id: int, db: Session) -> bool:
        """Remove a response from preference index (when disliked or feedback deleted)."""
        try:
            index, metadata = PreferenceService.load_preference_index(user_id)

            # Find and remove from metadata
            new_metadata = [m for m in metadata if m.get("message_id") != message_id]

            if len(new_metadata) == len(metadata):
                # Not found
                return False

            # Rebuild index without the removed item
            new_index = faiss.IndexFlatIP(EmbeddingService.DIM)

            for m in new_metadata:
                # Re-fetch message to get embedding
                msg = (
                    db.query(ModelChatMessage)
                    .filter(ModelChatMessage.id == m["message_id"])
                    .first()
                )
                if msg:
                    user_msg = (
                        db.query(ModelChatMessage)
                        .filter(
                            ModelChatMessage.conversation_id == msg.conversation_id,
                            ModelChatMessage.role == "user",
                            ModelChatMessage.timestamp < msg.timestamp,
                        )
                        .order_by(ModelChatMessage.timestamp.desc())
                        .first()
                    )
                    if user_msg:
                        emb = EmbeddingService.get_embedding(user_msg.content)
                        emb = emb / (np.linalg.norm(emb) + 1e-8)
                        new_index.add(np.array([emb]).astype("float32"))

            PreferenceService.save_preference_index(user_id, new_index, new_metadata)
            logger.info(f"Removed preference: message_id={message_id}")
            return True

        except Exception as e:
            logger.error(f"Error removing preference: {e}")
            return False

    @staticmethod
    def get_similar_preferences(
        query: str, user_id: int, top_k: int = 3, threshold: float = 0.6
    ) -> Optional[str]:
        """
        Find similar queries from preference index and return good response examples.
        Returns formatted string for injection into system prompt.
        """
        try:
            index, metadata = PreferenceService.load_preference_index(user_id)

            if index.ntotal == 0:
                return None

            # Generate query embedding
            query_emb = EmbeddingService.get_embedding(query)
            query_emb = query_emb / (np.linalg.norm(query_emb) + 1e-8)

            # Search
            k = min(top_k, index.ntotal)
            distances, indices = index.search(
                np.array([query_emb]).astype("float32"), k
            )

            # Filter by threshold and collect results
            results = []
            for dist, idx in zip(distances[0], indices[0]):
                if idx >= 0 and dist >= threshold and idx < len(metadata):
                    results.append(metadata[idx])

            if not results:
                return None

            # Format for prompt injection
            examples = []
            for r in results:
                examples.append(f"Q: {r['query'][:200]}\nA: {r['response'][:300]}")

            return "\n---\n".join(examples)

        except Exception as e:
            logger.error(f"Error getting preferences: {e}")
            return None
