"""
Conversation Summary Service

Manages conversation summarization for hierarchical memory system.
Generates and updates summaries to enable infinite context retention.
"""

import logging
from sqlalchemy.orm import Session
from app.models import (
    ChatMessage as ModelChatMessage,
    Conversation as ModelConversation,
)
import ollama

logger = logging.getLogger(__name__)


class ConversationSummaryService:

    @staticmethod
    def should_update_summary(conversation_id: int, db: Session) -> bool:
        """
        Check if conversation summary should be updated.
        Update every 8 messages after reaching 15.
        """
        message_count = (
            db.query(ModelChatMessage)
            .filter(ModelChatMessage.conversation_id == conversation_id)
            .count()
        )

        # Update at 15, 23, 31, ... messages
        if message_count >= 15 and (message_count % 8 == 0):
            return True
        return False

    @staticmethod
    def generate_summary(conversation_id: int, db: Session) -> str:
        """
        Generate a fresh summary of the entire conversation.
        Used for first-time summary generation.
        """
        try:
            # Load all messages
            messages = (
                db.query(ModelChatMessage)
                .filter(ModelChatMessage.conversation_id == conversation_id)
                .order_by(ModelChatMessage.timestamp.asc())
                .all()
            )

            if not messages:
                return ""

            # Format messages for summarization
            conversation_text = "\\n".join(
                [
                    f"{msg.role.upper()}: {msg.content[:500]}"  # Limit each message
                    for msg in messages
                ]
            )

            # Truncate if too long
            if len(conversation_text) > 10000:
                conversation_text = conversation_text[:10000] + "\\n...[truncated]"

            # Generate summary using LLM
            system_prompt = "You are a conversation summarizer. Create concise, informative summaries."
            user_prompt = f"""
Summarize this conversation concisely. Focus on:
- Main topics discussed
- Key facts and information
- Important decisions or outcomes

Conversation:
{conversation_text}

Format your summary as:
**Main Topics**: [...]
**Key Facts**: [...]
**Decisions**: [...]

Keep it under 400 words.
"""

            response = ollama.chat(
                model="Lumina:latest",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                options={"temperature": 0.3},
            )

            summary = response["message"]["content"].strip()
            logger.info(
                f"Generated summary for conversation {conversation_id}: {len(summary)} chars"
            )
            return summary

        except Exception as e:
            logger.error(f"Error generating summary: {e}")
            return ""

    @staticmethod
    def update_summary_incremental(
        conversation_id: int, new_messages: list, db: Session
    ) -> str:
        """
        Update existing summary with new messages.
        More efficient than regenerating from scratch.
        """
        try:
            # Get existing summary
            conversation = db.query(ModelConversation).get(conversation_id)
            old_summary = conversation.summary if conversation.summary else ""

            # If no existing summary, generate fresh one
            if not old_summary:
                return ConversationSummaryService.generate_summary(conversation_id, db)

            # Format new messages
            new_text = "\\n".join(
                [f"{msg.role.upper()}: {msg.content[:500]}" for msg in new_messages]
            )

            # Update summary
            system_prompt = (
                "You are a conversation summarizer. Update summaries efficiently."
            )
            user_prompt = f"""
Existing Summary:
{old_summary}

New Messages:
{new_text}

Update the summary to incorporate new information. Maintain the same format:
**Main Topics**: [...]
**Key Facts**: [...]
**Decisions**: [...]

Keep it concise, under 400 words.
"""

            response = ollama.chat(
                model="qwen3:4b-q4_K_M",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                options={"temperature": 0.3},
            )

            summary = response["message"]["content"].strip()
            logger.info(
                f"Updated summary for conversation {conversation_id}: {len(summary)} chars"
            )
            return summary

        except Exception as e:
            logger.error(f"Error updating summary: {e}")
            return old_summary  # Return old summary if update fails
