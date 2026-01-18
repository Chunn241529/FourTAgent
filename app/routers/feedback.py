from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import MessageFeedback, ChatMessage as ModelChatMessage
from app.schemas import FeedbackCreate, FeedbackResponse
from app.routers.task import get_current_user
from app.services.preference_service import PreferenceService

router = APIRouter(prefix="/feedback", tags=["feedback"])


@router.post("/", response_model=FeedbackResponse)
def create_or_update_feedback(
    feedback: FeedbackCreate,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit or update feedback (like/dislike) for a message"""
    # Validate feedback_type
    if feedback.feedback_type not in ("like", "dislike"):
        raise HTTPException(400, "feedback_type must be 'like' or 'dislike'")

    # Check message exists and belongs to user's conversation
    message = (
        db.query(ModelChatMessage)
        .filter(ModelChatMessage.id == feedback.message_id)
        .first()
    )
    if not message:
        raise HTTPException(404, "Message not found")

    # Check if feedback already exists
    existing = (
        db.query(MessageFeedback)
        .filter(
            MessageFeedback.message_id == feedback.message_id,
            MessageFeedback.user_id == user_id,
        )
        .first()
    )

    if existing:
        # Update existing feedback
        old_type = existing.feedback_type
        existing.feedback_type = feedback.feedback_type
        db.commit()
        db.refresh(existing)

        # Update preference index based on feedback change
        if feedback.feedback_type == "like" and old_type != "like":
            PreferenceService.add_preference(feedback.message_id, user_id, db)
        elif feedback.feedback_type == "dislike" and old_type == "like":
            PreferenceService.remove_preference(feedback.message_id, user_id, db)

        return existing
    else:
        # Create new feedback
        new_feedback = MessageFeedback(
            message_id=feedback.message_id,
            user_id=user_id,
            feedback_type=feedback.feedback_type,
        )
        db.add(new_feedback)
        db.commit()
        db.refresh(new_feedback)

        # Add to preference index if liked
        if feedback.feedback_type == "like":
            PreferenceService.add_preference(feedback.message_id, user_id, db)

        return new_feedback


@router.get("/{message_id}", response_model=FeedbackResponse)
def get_feedback(
    message_id: int,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get feedback for a specific message"""
    feedback = (
        db.query(MessageFeedback)
        .filter(
            MessageFeedback.message_id == message_id,
            MessageFeedback.user_id == user_id,
        )
        .first()
    )
    if not feedback:
        raise HTTPException(404, "Feedback not found")
    return feedback


@router.delete("/{message_id}")
def delete_feedback(
    message_id: int,
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove feedback for a message"""
    feedback = (
        db.query(MessageFeedback)
        .filter(
            MessageFeedback.message_id == message_id,
            MessageFeedback.user_id == user_id,
        )
        .first()
    )
    if not feedback:
        raise HTTPException(404, "Feedback not found")

    db.delete(feedback)
    db.commit()
    return {"message": "Feedback deleted"}
