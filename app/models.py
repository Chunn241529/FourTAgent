from sqlalchemy import Column, Integer, String, JSON, DateTime, ForeignKey
from sqlalchemy.orm import declarative_base
from sqlalchemy.sql import func  # SỬA: Sử dụng func.now() thay vì datetime.utcnow
from app.db import Base


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    username = Column(String, unique=True, nullable=False)
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    verified_devices = Column(JSON, nullable=False, default=[])
    gender = Column(String, nullable=True)


class Task(Base):
    __tablename__ = "tasks"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    task_name = Column(String, nullable=False)
    due_date = Column(String, nullable=True)
    priority = Column(String, nullable=False, default="medium")
    tags = Column(String, nullable=False, default="")
    original_query = Column(String, nullable=False)
    created_at = Column(DateTime, default=func.now())  # SỬA: Dùng func.now()


class Conversation(Base):
    __tablename__ = "conversations"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=func.now())  # SỬA: Dùng func.now()
    title = Column(String, nullable=True)
    summary = Column(String, nullable=True)  # Hierarchical memory: conversation summary


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    conversation_id = Column(Integer, ForeignKey("conversations.id"), nullable=False)
    content = Column(String, nullable=False)
    role = Column(String, nullable=False)
    timestamp = Column(DateTime, default=func.now())
    embedding = Column(JSON)
    tool_name = Column(String, nullable=True)
    tool_call_id = Column(String, nullable=True)
    tool_calls = Column(JSON, nullable=True)  # Store assistant's tool calls


class MessageFeedback(Base):
    """Stores user feedback (like/dislike) for AI messages to improve LLM"""

    __tablename__ = "message_feedback"
    id = Column(Integer, primary_key=True)
    message_id = Column(
        Integer, ForeignKey("chat_messages.id"), nullable=False, unique=True
    )
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    feedback_type = Column(String, nullable=False)  # "like" or "dislike"
    created_at = Column(DateTime, default=func.now())
