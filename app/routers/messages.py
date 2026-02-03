import json
import faiss
from fastapi import APIRouter, Depends, HTTPException
import numpy as np
from sqlalchemy.orm import Session
from typing import List

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
            ModelChatMessage.conversation_id
            == conversation_id
            # Don't filter by user_id - we want both user and assistant messages
            # Authorization is already handled by checking conversation ownership above
        )
        .order_by(ModelChatMessage.timestamp.asc())
        .all()
    )

    # Get all feedback for this user's messages in this conversation
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
        msg_dict = msg.__dict__.copy()
        if msg.embedding and isinstance(msg.embedding, str):
            try:
                parsed_embedding = json.loads(msg.embedding)
                msg_dict["embedding"] = parsed_embedding
            except json.JSONDecodeError:
                msg_dict["embedding"] = None

        if msg.generated_images and isinstance(msg.generated_images, str):
            try:
                msg_dict["generated_images"] = json.loads(msg.generated_images)
            except json.JSONDecodeError:
                msg_dict["generated_images"] = []

        if msg.deep_search_updates and isinstance(msg.deep_search_updates, str):
            try:
                msg_dict["deep_search_updates"] = json.loads(msg.deep_search_updates)
            except json.JSONDecodeError:
                msg_dict["deep_search_updates"] = []

        # Add feedback status
        msg_dict["feedback"] = feedback_map.get(msg.id)

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

    # Create embedding for the message
    embedding = EmbeddingService.get_embedding(content)

    # Create and save the message
    message = ModelChatMessage(
        user_id=user_id,
        conversation_id=conversation_id,
        content=content,
        role=role,
        embedding=json.dumps(embedding.tolist()) if embedding is not None else None,
    )
    db.add(message)
    db.commit()
    db.refresh(message)

    # Update FAISS index
    try:
        index, _ = rag_service.load_faiss(user_id, conversation_id)
        if embedding is not None:
            index.add(np.array([embedding]))
            faiss.write_index(
                index, rag_service.get_faiss_path(user_id, conversation_id)
            )
    except Exception as e:
        print(f"FAISS update error: {e}")

    msg_dict = message.__dict__.copy()
    if msg_dict.get("embedding") and isinstance(msg_dict["embedding"], str):
        try:
            msg_dict["embedding"] = json.loads(msg_dict["embedding"])
        except json.JSONDecodeError:
            msg_dict["embedding"] = None

    if msg_dict.get("generated_images") and isinstance(
        msg_dict["generated_images"], str
    ):
        try:
            msg_dict["generated_images"] = json.loads(msg_dict["generated_images"])
        except json.JSONDecodeError:
            msg_dict["generated_images"] = []

    if msg_dict.get("deep_search_updates") and isinstance(
        msg_dict["deep_search_updates"], str
    ):
        try:
            msg_dict["deep_search_updates"] = json.loads(
                msg_dict["deep_search_updates"]
            )
        except json.JSONDecodeError:
            msg_dict["deep_search_updates"] = []

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

    msg_dict = message.__dict__
    if msg_dict["embedding"] and isinstance(msg_dict["embedding"], str):
        try:
            parsed_embedding = json.loads(msg_dict["embedding"])
            msg_dict["embedding"] = parsed_embedding
        except json.JSONDecodeError:
            msg_dict["embedding"] = None

    if msg.generated_images and isinstance(msg.generated_images, str):
        try:
            msg_dict["generated_images"] = json.loads(msg.generated_images)
        except json.JSONDecodeError:
            msg_dict["generated_images"] = []

    if msg.deep_search_updates and isinstance(msg.deep_search_updates, str):
        try:
            msg_dict["deep_search_updates"] = json.loads(msg.deep_search_updates)
        except json.JSONDecodeError:
            msg_dict["deep_search_updates"] = []

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
        new_embedding = embedding_service.get_embedding(
            msg_update.content, max_length=1024
        )
        message.embedding = json.dumps(new_embedding.tolist())

        index, _ = rag_service.load_faiss(user_id, message.conversation_id)
        all_messages = (
            db.query(ModelChatMessage)
            .filter(ModelChatMessage.conversation_id == message.conversation_id)
            .all()
        )
        embs = np.array([json.loads(m.embedding) for m in all_messages if m.embedding])

        index.reset()
        if len(embs) > 0:
            index.add(embs)
        faiss.write_index(
            index, rag_service.get_faiss_path(user_id, message.conversation_id)
        )

    db.commit()
    db.refresh(message)
    msg_dict = message.__dict__
    if msg_dict["embedding"] and isinstance(msg_dict["embedding"], str):
        try:
            parsed_embedding = json.loads(msg_dict["embedding"])
            msg_dict["embedding"] = parsed_embedding
        except json.JSONDecodeError:
            msg_dict["embedding"] = None

    if msg_dict.get("generated_images") and isinstance(
        msg_dict["generated_images"], str
    ):
        try:
            msg_dict["generated_images"] = json.loads(msg_dict["generated_images"])
        except json.JSONDecodeError:
            msg_dict["generated_images"] = []

    if msg_dict.get("deep_search_updates") and isinstance(
        msg_dict["deep_search_updates"], str
    ):
        try:
            msg_dict["deep_search_updates"] = json.loads(
                msg_dict["deep_search_updates"]
            )
        except json.JSONDecodeError:
            msg_dict["deep_search_updates"] = []

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

    db.delete(message)
    db.commit()

    index, _ = rag_service.load_faiss(user_id, message.conversation_id)
    embs = np.array(
        [
            json.loads(m.embedding)
            for m in db.query(ModelChatMessage)
            .filter(ModelChatMessage.conversation_id == message.conversation_id)
            .all()
            if m.embedding
        ]
    )

    index.reset()
    if len(embs) > 0:
        index.add(embs)
    faiss.write_index(
        index, rag_service.get_faiss_path(user_id, message.conversation_id)
    )

    return {"message": "Message deleted"}
