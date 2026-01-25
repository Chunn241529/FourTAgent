from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime

from app.db import get_db
from app.models import (
    Conversation as ModelConversation,
    User,
    ChatMessage as ModelChatMessage,
)
from app.schemas import Conversation, ConversationCreate
from app.routers.task import get_current_user
from app.services.rag_service import RAGService

router = APIRouter(prefix="/conversations", tags=["conversations"])
rag_service = RAGService()


@router.post("/", response_model=Conversation)
def create_conversation(
    user_id: int = Depends(get_current_user), db: Session = Depends(get_db)
):
    """Tạo conversation mới"""
    conversation = ModelConversation(user_id=user_id, created_at=datetime.utcnow())
    db.add(conversation)
    db.commit()
    db.refresh(conversation)
    return conversation


@router.get("/", response_model=List[Conversation])
def get_conversations(
    user_id: int = Depends(get_current_user), db: Session = Depends(get_db)
):
    """Lấy danh sách conversations của user"""
    conversations = (
        db.query(ModelConversation).filter(ModelConversation.user_id == user_id).all()
    )
    # Debug: Log full data
    for c in conversations:
        print(f"DEBUG GET /conversations: id={c.id}, title={c.title}")
    return conversations


@router.get("/{conversation_id}", response_model=Conversation)
def get_conversation(
    conversation_id: int,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lấy conversation theo ID"""
    conversation = (
        db.query(ModelConversation)
        .filter(
            ModelConversation.id == conversation_id,
            ModelConversation.user_id == user_id,
        )
        .first()
    )
    if not conversation:
        raise HTTPException(404, "Conversation not found")
    return conversation


@router.delete("/{conversation_id}")
def delete_conversation(
    conversation_id: int,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Xóa conversation"""
    conversation = (
        db.query(ModelConversation)
        .filter(
            ModelConversation.id == conversation_id,
            ModelConversation.user_id == user_id,
        )
        .first()
    )
    if not conversation:
        raise HTTPException(404, "Conversation not found")

    # Xóa tất cả messages trong conversation
    db.query(ModelChatMessage).filter(
        ModelChatMessage.conversation_id == conversation_id
    ).delete()

    # Xóa conversation
    db.delete(conversation)
    db.commit()

    # Xóa FAISS index trong thư mục faiss_indices
    rag_service.cleanup_faiss_index(user_id, conversation_id)

    return {"message": "Conversation deleted"}


@router.delete("/")
def delete_all_conversations(
    user_id: int = Depends(get_current_user), db: Session = Depends(get_db)
):
    """Xóa TẤT CẢ conversations của user"""
    try:
        # Lấy tất cả conversation IDs của user trước khi xóa
        conversations = (
            db.query(ModelConversation)
            .filter(ModelConversation.user_id == user_id)
            .all()
        )

        conversation_ids = [conv.id for conv in conversations]

        if not conversation_ids:
            return {"message": "No conversations found to delete"}

        # Xóa tất cả messages của user trong các conversations
        db.query(ModelChatMessage).filter(
            ModelChatMessage.user_id == user_id,
            ModelChatMessage.conversation_id.in_(conversation_ids),
        ).delete()

        # Xóa tất cả conversations của user
        deleted_count = (
            db.query(ModelConversation)
            .filter(ModelConversation.user_id == user_id)
            .delete()
        )

        db.commit()

        # Xóa tất cả FAISS indices trong thư mục faiss_indices
        faiss_deleted_count = rag_service.cleanup_all_user_faiss(user_id)

        return {
            "message": f"Successfully deleted {deleted_count} conversations and all associated messages",
            "deleted_conversations": deleted_count,
            "deleted_faiss_indices": faiss_deleted_count,
        }

    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Error deleting all conversations: {str(e)}")


@router.post("/{conversation_id}/generate-title")
def generate_title(
    conversation_id: int,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generate a title for the conversation using Lumina:latest-S model"""
    import ollama

    # Verify conversation ownership
    conversation = (
        db.query(ModelConversation)
        .filter(
            ModelConversation.id == conversation_id,
            ModelConversation.user_id == user_id,
        )
        .first()
    )

    if not conversation:
        raise HTTPException(404, "Conversation not found")

    # Skip if already has a title
    if conversation.title:
        return {"title": conversation.title}

    # Get first message (user's initial prompt)
    messages = (
        db.query(ModelChatMessage)
        .filter(ModelChatMessage.conversation_id == conversation_id)
        .order_by(ModelChatMessage.timestamp.asc())
        .limit(1)
        .all()
    )

    if not messages:
        return {"title": None, "reason": "No messages"}

    # Build context from messages
    context = "\n".join([f"{m.role}: {m.content[:200]}" for m in messages])
    print(
        f"DEBUG: Generating title for conv {conversation_id} with context len {len(context)}"
    )

    try:
        # Use Lumina:latest-S for fast title generation
        print("DEBUG: Calling Ollama 4T-Evaluate...")
        response = ollama.chat(
            model="Lumina-small:latest",
            messages=[
                {
                    "role": "user",
                    "content": f"""Tạo tiêu đề ngắn gọn (tối đa 6 từ) cho cuộc hội thoại này. Chỉ trả về tiêu đề, không giải thích, không ký tự đặc biệt.
                    Rules: 
                    - Cuộc hội thoại không nên có đại từ nhân xưng.
                    - Không sử dụng các từ như "tôi", "bạn", "chúng tôi", "chúng ta", "họ", "nó", "của tôi", "của bạn", "của chúng tôi", "của chúng ta", "của họ", "của nó", "của tôi", "của bạn", "của chúng tôi", "của chúng ta", "của họ", "của nó". 
              
                    Cuộc hội thoại:
                    {context}

                    Tiêu đề:""",
                }
            ],
            options={"num_predict": 30},
        )

        title = response["message"]["content"].strip().strip('"')
        print(f"DEBUG: Generated title: '{title}'")
        # Clean up title (remove quotes, etc)
        # title = title.strip("\"'").strip() # This line was replaced by the previous one

        # Limit length
        if len(title) > 50:
            title = title[:47] + "..."

        # Save to DB - Use explicit update to ensure persistence
        rows_updated = (
            db.query(ModelConversation)
            .filter(ModelConversation.id == conversation_id)
            .update({"title": title})
        )

        db.commit()

        print(f"DEBUG: Updated {rows_updated} rows with title '{title}'")

        if rows_updated == 0:
            print("DEBUG: WARNING - No rows updated!")
            return {"title": None, "error": "No rows updated"}

        return {"title": title}

    except Exception as e:
        print(f"DEBUG: Exception in generate_title: {e}")
        return {"title": None, "error": str(e)}
