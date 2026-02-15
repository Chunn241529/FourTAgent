import json
import faiss
import logging
from fastapi import APIRouter, Depends, HTTPException
import numpy as np
from sqlalchemy.orm import Session
from typing import List, Optional

from app.db import get_db
from app.models import (
    ChatMessage as ModelChatMessage,
    Conversation as ModelConversation,
    MessageFeedback,
    User,
)
from app.schemas import ChatMessage, ChatMessageUpdate
from app.routers.task import get_current_user
from app.services.embedding_service import EmbeddingService
from app.services.rag_service import RAGService

router = APIRouter(prefix="/messages", tags=["messages"])
embedding_service = EmbeddingService()
rag_service = RAGService()
logger = logging.getLogger(__name__)


def _parse_message_fields(msg: ModelChatMessage, feedback: Optional[str] = None) -> dict:
    """Helper to parse JSON fields from message model"""
    msg_dict = msg.__dict__.copy()
    
    if msg.embedding and isinstance(msg.embedding, str):
        try:
            msg_dict["embedding"] = json.loads(msg.embedding)
        except (json.JSONDecodeError, TypeError, ValueError):
            msg_dict["embedding"] = None

    if msg.generated_images and isinstance(msg.generated_images, str):
        try:
            msg_dict["generated_images"] = json.loads(msg.generated_images)
        except (json.JSONDecodeError, TypeError, ValueError):
            msg_dict["generated_images"] = []

    if msg.deep_search_updates and isinstance(msg.deep_search_updates, str):
        try:
            msg_dict["deep_search_updates"] = json.loads(msg.deep_search_updates)
        except (json.JSONDecodeError, TypeError, ValueError):
            msg_dict["deep_search_updates"] = []

    if feedback:
        msg_dict["feedback"] = feedback
        
    return msg_dict


def _rebuild_faiss_index(db: Session, user_id: int, conversation_id: int) -> bool:
    """Rebuild FAISS index for a conversation. Returns True if successful."""
    try:
        index, _ = rag_service.load_faiss(user_id, conversation_id)
        all_messages = (
            db.query(ModelChatMessage)
            .filter(ModelChatMessage.conversation_id == conversation_id)
            .all()
        )
        embs = []
        for m in all_messages:
            if m.embedding:
                try:
                    if isinstance(m.embedding, str):
                        emb_data = json.loads(m.embedding)
                    elif isinstance(m.embedding, list):
                        emb_data = m.embedding
                    else:
                        continue
                    embs.append(emb_data)
                except (json.JSONDecodeError, TypeError, ValueError):
                    continue
        
        index.reset()
        if len(embs) > 0:
            index.add(np.array(embs, dtype="float32"))
        faiss.write_index(index, rag_service.get_faiss_path(user_id, conversation_id))
        return True
    except Exception as e:
        logger.warning(f"Error rebuilding FAISS index: {e}")
        return False


@router.get(
    "/conversations/{conversation_id}/messages", response_model=List[ChatMessage]
)
def get_messages(
    conversation_id: int,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
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

    messages = (
        db.query(ModelChatMessage)
        .filter(
            ModelChatMessage.conversation_id == conversation_id
        )
        .order_by(ModelChatMessage.timestamp.asc())
        .all()
    )

    message_ids = [msg.id for msg in messages]
    feedbacks = (
        db.query(MessageFeedback)
        .filter(
            MessageFeedback.message_id.in_(message_ids),
            MessageFeedback.user_id == user_id,
        )
        .all()
    )
    feedback_map = {f.message_id: f.feedback_type for f in feedbacks}

    result = []
    for msg in messages:
        feedback = feedback_map.get(msg.id)
        msg_dict = _parse_message_fields(msg, feedback)
        result.append(ChatMessage(**msg_dict))

    return result


@router.post("/conversations/{conversation_id}/messages", response_model=ChatMessage)
def create_message(
    conversation_id: int,
    content: str,
    role: str = "assistant",
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create a new message in a conversation (used for saving partial responses)"""
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

    # Create embedding for the message with error handling
    embedding = None
    emb_json = None
    try:
        embedding = EmbeddingService.get_embedding(content)
        if embedding is not None and not np.all(embedding == 0):
            emb_json = json.dumps(embedding.tolist())
    except Exception as e:
        logger.warning(f"Failed to create embedding for message: {e}")

    # Create and save the message
    message = ModelChatMessage(
        user_id=user_id,
        conversation_id=conversation_id,
        content=content,
        role=role,
        embedding=emb_json,
    )
    db.add(message)
    db.commit()
    db.refresh(message)

    # Update FAISS index
    try:
        if embedding is not None and not np.all(embedding == 0):
            index, _ = rag_service.load_faiss(user_id, conversation_id)
            index.add(np.array([embedding]))
            faiss.write_index(
                index, rag_service.get_faiss_path(user_id, conversation_id)
            )
    except Exception as e:
        logger.warning(f"FAISS update error: {e}")

    msg_dict = _parse_message_fields(message)
    return ChatMessage(**msg_dict)


@router.get("/{id}", response_model=ChatMessage)
def get_message(
    id: int, user_id: int = Depends(get_current_user), db: Session = Depends(get_db)
):
    message = (
        db.query(ModelChatMessage)
        .filter(ModelChatMessage.id == id, ModelChatMessage.user_id == user_id)
        .first()
    )
    if not message:
        raise HTTPException(404, "Message not found or not authorized")

    msg_dict = _parse_message_fields(message)
    return ChatMessage(**msg_dict)


@router.put("/{id}", response_model=ChatMessage)
def update_message(
    id: int,
    msg_update: ChatMessageUpdate,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    message = (
        db.query(ModelChatMessage)
        .filter(ModelChatMessage.id == id, ModelChatMessage.user_id == user_id)
        .first()
    )
    if not message:
        raise HTTPException(404, "Message not found or not authorized")

    if msg_update.content is not None:
        message.content = msg_update.content
        # Create new embedding with error handling
        try:
            new_embedding = embedding_service.get_embedding(
                msg_update.content, max_length=1024
            )
            if new_embedding is not None and not np.all(new_embedding == 0):
                message.embedding = json.dumps(new_embedding.tolist())
        except Exception as e:
            logger.warning(f"Failed to create embedding on update: {e}")

        # Rebuild FAISS index using helper
        _rebuild_faiss_index(db, user_id, message.conversation_id)

    db.commit()
    db.refresh(message)
    msg_dict = _parse_message_fields(message)
    return ChatMessage(**msg_dict)


@router.delete("/{id}")
def delete_message(
    id: int, user_id: int = Depends(get_current_user), db: Session = Depends(get_db)
):
    message = (
        db.query(ModelChatMessage)
        .filter(ModelChatMessage.id == id, ModelChatMessage.user_id == user_id)
        .first()
    )
    if not message:
        raise HTTPException(404, "Message not found or not authorized")

    conversation_id = message.conversation_id
    db.delete(message)
    db.commit()

    # Rebuild FAISS index using helper
    _rebuild_faiss_index(db, user_id, conversation_id)

    return {"message": "Message deleted"}
