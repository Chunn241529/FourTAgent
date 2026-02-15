import logging
import json
import numpy as np
import faiss
from typing import List, Dict, Any, Optional, Union
from datetime import datetime
from sqlalchemy.orm import Session
from fastapi import HTTPException
from app.models import (
    ChatMessage as ModelChatMessage,
    Conversation as ModelConversation,
    User,
)
from app.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)


def get_hierarchical_memory(
    db: Session, conversation_id: int, current_query: str, user_id: int
) -> tuple:
    """
    Get hierarchical memory: summary + semantic + working memory.
    Returns: (summary: str, messages: List[Dict], working_messages: List[Dict])
    """

    # 1. Get conversation summary
    conversation = db.query(ModelConversation).get(conversation_id)
    summary = conversation.summary if conversation and conversation.summary else ""

    # 0. Closure Detection: If user is ending conversation, minimize context
    closure_keywords = [
        "cảm ơn",
        "thank",
        "tạm biệt",
        "bye",
        "hẹn gặp lại",
        "kết thúc",
    ]
    is_closure = len(current_query.split()) < 6 and any(
        kw in current_query.lower() for kw in closure_keywords
    )

    if is_closure:
        logger.info("Closure detected, resetting working and semantic memory")
        return summary, [], []

    # 2. Working memory (last 10 messages for better flow)
    working_memory = (
        db.query(ModelChatMessage)
        .filter(ModelChatMessage.conversation_id == conversation_id)
        .order_by(ModelChatMessage.timestamp.desc())
        .limit(10)
        .all()
    )
    working_memory = list(reversed(working_memory))  # Chronological order
    working_ids = {msg.id for msg in working_memory}

    # 3. Semantic memory (top 5 relevant, excluding working memory)
    semantic_messages = []
    try:
        # Generate query embedding
        query_emb = EmbeddingService.get_embedding(current_query)

        # Get candidate messages (exclude working memory, limit to last 500 for performance)
        candidates = (
            db.query(ModelChatMessage)
            .filter(
                ModelChatMessage.conversation_id == conversation_id,
                ModelChatMessage.embedding.isnot(None),
            )
            .order_by(ModelChatMessage.timestamp.desc())
            .limit(500)
            .all()
        )

        # Filter out working memory in Python (faster than IN clause for large lists if needed,
        # but here working_ids is small)
        candidates = [m for m in candidates if m.id not in working_ids]

        if candidates:
            # Prepare embeddings for FAISS
            valid_candidates = []
            emb_list = []

            for msg in candidates:
                try:
                    emb = np.array(json.loads(msg.embedding), dtype="float32")
                    if emb.shape[0] == EmbeddingService.DIM:
                        emb_list.append(emb)
                        valid_candidates.append(msg)
                except (json.JSONDecodeError, TypeError, ValueError, AttributeError):
                    logger.warning(f"Skipping message {msg.id} due to invalid embedding")
                    continue

            if emb_list:
                emb_array = np.array(emb_list)
                faiss.normalize_L2(emb_array)

                index = faiss.IndexFlatIP(EmbeddingService.DIM)
                index.add(emb_array)

                # Query
                q_emb = query_emb.astype("float32").reshape(1, -1)
                faiss.normalize_L2(q_emb)

                D, I = index.search(q_emb, k=min(5, len(valid_candidates)))

                # Filter by threshold
                threshold = 0.45  # Slightly lower than 0.5 to be more inclusive
                for score, idx in zip(D[0], I[0]):
                    if score >= threshold and idx >= 0:
                        semantic_messages.append(valid_candidates[idx])

                logger.info(
                    f"Semantic memory: {len(semantic_messages)} relevant messages (threshold={threshold})"
                )
    except Exception as e:
        logger.warning(f"Error getting semantic memory: {e}")
        # Return empty list to ensure semantic_messages is always a list

    # 4. Return components separately
    logger.info(
        f"Hierarchical memory: summary={bool(summary)}, semantic={len(semantic_messages)}, working={len(working_memory)}"
    )

    return summary, semantic_messages, working_memory


def get_or_create_conversation(
    db: Session, user_id: int, conversation_id: Optional[int]
):
    """Lấy hoặc tạo conversation"""
    if conversation_id is not None:
        conversation = (
            db.query(ModelConversation)
            .filter(
                ModelConversation.id == conversation_id,
                ModelConversation.user_id == user_id,
            )
            .first()
        )
        if not conversation:
            raise HTTPException(404, "Conversation not found or not authorized")
        return conversation, False
    else:
        conversation = ModelConversation(user_id=user_id, created_at=datetime.utcnow())
        db.add(conversation)
        db.flush()
        return conversation, True


def save_message_to_db(
    db: Session,
    user_id: int,
    conversation_id: int,
    msg: Dict[str, Any],
    embedding: Optional[List[float]] = None,
    generated_images: Optional[List[str]] = None,
    thinking: Optional[str] = None,
):
    """Helper to save a message to DB"""
    try:
        content = msg.get("content", "")
        role = msg.get("role", "assistant")
        tool_name = msg.get("tool_name") or msg.get("name")
        tool_call_id = msg.get("tool_call_id")
        tool_calls = msg.get("tool_calls")

        emb_json = None
        if embedding:
            emb_json = json.dumps(embedding)
        elif role in ["user", "assistant"] and content and len(content) > 10:
            try:
                emb = EmbeddingService.get_embedding(content)
                emb_json = json.dumps(emb.tolist())
            except:
                pass

        # Handle tool_calls field - standardizing to JSON string
        tool_calls_json = None
        if tool_calls:
            if isinstance(tool_calls, str):
                tool_calls_json = tool_calls
            else:
                tool_calls_json = json.dumps(tool_calls)

        db_msg = ModelChatMessage(
            user_id=user_id,
            conversation_id=conversation_id,
            content=str(content),
            role=role,
            embedding=emb_json,
            tool_name=tool_name,
            tool_call_id=tool_call_id,
            tool_calls=tool_calls_json,
            generated_images=(
                json.dumps(generated_images) if generated_images else None
            ),
            thinking=thinking,
        )
        db.add(db_msg)
        db.commit()
        return db_msg
    except Exception as e:
        logger.error(f"Error saving message to DB: {e}")
        db.rollback()
        return None


def update_message_generated_images(db: Session, message_id: int, images: List[str]):
    try:
        msg = (
            db.query(ModelChatMessage).filter(ModelChatMessage.id == message_id).first()
        )
        if msg:
            msg.generated_images = json.dumps(images)
            db.commit()
            logger.info(f"Updated message {message_id} with {len(images)} images")
    except Exception as e:
        logger.error(f"Error updating message images: {e}")


def update_message_deep_search_logs(db: Session, message_id: int, logs: List[str]):
    try:
        msg = (
            db.query(ModelChatMessage).filter(ModelChatMessage.id == message_id).first()
        )
        if msg:
            # Store cleaned logs or raw SSE strings?
            # Raw SSE strings are what UI expects in deepSearchUpdates list
            msg.deep_search_updates = json.dumps(logs)
            db.commit()
    except Exception as e:
        logger.error(f"Error updating deep search logs: {e}")


def update_message_code_executions(
    db: Session, message_id: int, executions: List[Dict]
):
    try:
        msg = (
            db.query(ModelChatMessage).filter(ModelChatMessage.id == message_id).first()
        )
        if msg:
            # Append to existing if any? Or replace?
            # Since this is run once per turn, replacing/setting is fine.
            msg.code_executions = json.dumps(executions)
            db.commit()
            logger.info(
                f"Updated message {message_id} with {len(executions)} code executions"
            )
    except Exception as e:
        logger.error(f"Error updating message code executions: {e}")


def update_merged_message(
    db: Session,
    message_id: int,
    new_msg_data: Dict[str, Any],
    thinking: Optional[str] = None,
) -> Optional[ModelChatMessage]:
    """
    Updates an existing assistant message by determining if we should append content
    (for multi-step tool use) or just update fields.
    """
    try:
        msg = (
            db.query(ModelChatMessage).filter(ModelChatMessage.id == message_id).first()
        )
        if not msg:
            return None

        # Append content if new content exists
        new_content = new_msg_data.get("content")
        if new_content:
            if msg.content:
                msg.content += "\n" + new_content
            else:
                msg.content = new_content

        # Append thinking if new thinking exists
        if thinking:
            if msg.thinking:
                msg.thinking += "\n\n" + thinking
            else:
                msg.thinking = thinking

        # Merge tool calls if new ones exist
        new_tool_calls = new_msg_data.get("tool_calls")
        if new_tool_calls:
            existing_calls = []
            if msg.tool_calls:
                # Check type because it might be string or list/dict
                if isinstance(msg.tool_calls, str):
                    try:
                        existing_calls = json.loads(msg.tool_calls)
                    except:
                        existing_calls = []
                elif isinstance(msg.tool_calls, list):
                    existing_calls = msg.tool_calls

            # Append new calls
            if existing_calls is None:
                existing_calls = []

            if isinstance(existing_calls, list):
                # Dedup? No, usually distinct calls.
                existing_calls.extend(new_tool_calls)
                msg.tool_calls = json.dumps(existing_calls)  # Save as JSON string

        db.commit()
        db.refresh(msg)
        return msg
    except Exception as e:
        logger.error(f"Error merging message: {e}")
        return None
