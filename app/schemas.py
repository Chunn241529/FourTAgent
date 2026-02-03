from pydantic import BaseModel
from typing import Optional, List, Union
from datetime import datetime


class UserRegister(BaseModel):
    username: str
    email: str
    password: str
    gender: Optional[str]  # Thêm trường gender, có thể là "male", "female", hoặc None


class UserLogin(BaseModel):
    username_or_email: str
    password: str
    device_id: Optional[str] = None


class VerifyCode(BaseModel):
    code: str


class ResetPassword(BaseModel):
    reset_token: str
    new_password: str


class ChangePassword(BaseModel):
    current_password: str
    new_password: str


class UpdateProfile(BaseModel):
    username: Optional[str] = None
    gender: Optional[str] = None


class TaskPrompt(BaseModel):
    prompt: str


class Task(BaseModel):
    id: int
    user_id: int
    task_name: str
    due_date: Optional[str]
    priority: str
    tags: str
    original_query: str
    created_at: datetime

    class Config:
        from_attributes = True


class TaskUpdate(BaseModel):
    task_name: Optional[str]
    due_date: Optional[str]
    priority: Optional[str]
    tags: Optional[str]
    original_query: Optional[str]


class ConversationCreate(BaseModel):
    pass


class Conversation(BaseModel):
    id: int
    user_id: int
    created_at: datetime
    title: Optional[str] = None
    summary: Optional[str] = None

    class Config:
        from_attributes = True


class ConversationUpdate(BaseModel):
    pass


class ChatMessageIn(BaseModel):
    message: str
    voice_enabled: Optional[bool] = False
    voice_id: Optional[str] = None


class ChatMessage(BaseModel):
    id: int
    user_id: int
    conversation_id: int
    content: str
    role: str
    timestamp: datetime
    embedding: Optional[Union[list, dict]]
    feedback: Optional[str] = None  # "like", "dislike", or None
    tool_name: Optional[str] = None
    tool_call_id: Optional[str] = None
    tool_calls: Optional[Union[list, dict, str]] = None  # Can be list, dict or json str
    generated_images: Optional[Union[list, str]] = None  # List of base64 images
    thinking: Optional[str] = None  # AI thinking content
    deep_search_updates: Optional[Union[list, str]] = None  # Deep search logs

    class Config:
        from_attributes = True


class ChatMessageUpdate(BaseModel):
    content: Optional[str]


class FeedbackCreate(BaseModel):
    message_id: int
    feedback_type: str  # "like" or "dislike"


class FeedbackResponse(BaseModel):
    id: int
    message_id: int
    user_id: int
    feedback_type: str
    created_at: datetime

    class Config:
        from_attributes = True


class TTSRequest(BaseModel):
    text: str
    voice_id: Optional[str] = None
