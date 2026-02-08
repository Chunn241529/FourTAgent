from fastapi import APIRouter, Depends, HTTPException, File, UploadFile, Body, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from app.db import get_db
from app.models import (
    ChatMessage as ModelChatMessage,
    Conversation as ModelConversation,
    User,
)
from app.schemas import ChatMessageIn
from app.routers.task import get_current_user
from app.services.chat_service import ChatService
from app.services.file_service import FileService
from app.services.queue_service import queue_service
from app.services.cloud_llm_service import cloud_llm_service
import logging
import asyncio
import json
from datetime import datetime
from typing import Optional, Union

logger = logging.getLogger(__name__)

router = APIRouter(tags=["chat"])


async def queued_chat_stream(
    message_in: ChatMessageIn,
    file: Optional[Union[UploadFile, str]],
    conversation_id: Optional[int],
    user_id: int,
    db: Session,
    voice_enabled: bool = False,
    voice_id: Optional[str] = None,
    force_canvas_tool: bool = False,
):
    """
    Wrapper that manages queue for chat requests.
    Acquires semaphore before processing, with cloud fallback on timeout.
    """
    queue_stats = queue_service.get_stats()

    # Emit queue status if overloaded
    if queue_stats["is_overloaded"]:
        position = queue_stats["queue_length"] + 1
        yield f"data: {json.dumps({'queue_status': {'position': position, 'message': f'Đang xếp hàng... Vị trí: {position}'}}, separators=(',', ':'))}\n\n"

    # Try to acquire semaphore
    try:
        acquired = await asyncio.wait_for(
            queue_service._semaphore.acquire(), timeout=queue_service.queue_timeout
        )
    except asyncio.TimeoutError:
        # Timeout - cloud fallback not implemented for full chat yet
        yield f"data: {json.dumps({'error': 'Server đang bận, vui lòng thử lại sau.'}, separators=(',', ':'))}\n\n"
        yield f"data: [DONE]\n\n"
        return

    try:
        # Clear queue status
        yield f"data: {json.dumps({'queue_status': {'position': 0, 'message': 'Đang xử lý...'}}, separators=(',', ':'))}\n\n"

        # Call the actual chat service - now returns async generator directly
        stream = await ChatService.chat_with_rag(
            message=message_in,
            file=file,
            conversation_id=conversation_id,
            user_id=user_id,
            db=db,
            voice_enabled=voice_enabled,
            voice_id=voice_id,
            force_canvas_tool=force_canvas_tool,
        )

        # Stream the response directly - no double-wrapping
        try:
            async for chunk in stream:
                yield chunk
        except Exception as e:
            logger.error(f"Error in chat stream: {e}", exc_info=True)
            yield f"data: {json.dumps({'error': f'Server Error: {str(e)}'}, separators=(',', ':'))}\n\n"

    finally:
        queue_service._semaphore.release()
        logger.debug("Released queue semaphore")


@router.post("/send", response_class=StreamingResponse)
async def chat(
    message: str = Body(..., embed=True),
    file: Optional[Union[UploadFile, str]] = Body(None, embed=True),
    conversation_id: Optional[int] = None,
    voice_enabled: bool = Body(False),  # Accept from JSON Body
    voice_id: Optional[str] = Body(None),
    force_canvas_tool: bool = Body(False),  # Force LLM to use canvas tool
    # Also accept from Query for backward compatibility/flexibility
    q_voice_enabled: bool = Query(False, alias="voice_enabled"),
    q_voice_id: Optional[str] = Query(None, alias="voice_id"),
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Endpoint chính cho chat với RAG và file processing"""

    # Merge parameters (Body takes precedence or OR logic)
    final_voice_enabled = voice_enabled or q_voice_enabled
    final_voice_id = voice_id or q_voice_id

    logger.info(
        f"Chat request: voice_enabled={final_voice_enabled} (Body={voice_enabled}, Query={q_voice_enabled}), force_canvas={force_canvas_tool}"
    )

    # Wrap message in ChatMessageIn for service compatibility
    # Ensure to pass the final voice flags
    message_in = ChatMessageIn(
        message=message, voice_enabled=final_voice_enabled, voice_id=final_voice_id
    )

    # Use queued stream wrapper for concurrency control
    return StreamingResponse(
        queued_chat_stream(
            message_in=message_in,
            file=file,
            conversation_id=conversation_id,
            user_id=user_id,
            db=db,
            voice_enabled=final_voice_enabled,
            voice_id=final_voice_id,
            force_canvas_tool=force_canvas_tool,
        ),
        media_type="text/event-stream",
    )


@router.post("/tool_result", response_class=StreamingResponse)
async def tool_result(
    tool_name: str = Body(..., embed=True),
    result: str = Body(..., embed=True),
    tool_call_id: Optional[str] = Body(None, embed=True),
    conversation_id: int = Body(..., embed=True),
    voice_enabled: bool = Body(False),
    voice_id: Optional[str] = Body(None),
    user_id: int = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Endpoint to receive results from client-side tool execution.
    Resumes the chat stream with the provided result.
    """
    logger.info(
        f"Received tool result for {tool_name} in conversation {conversation_id}"
    )

    # Wrap in queued stream
    return StreamingResponse(
        queued_tool_result_stream(
            tool_name=tool_name,
            result=result,
            tool_call_id=tool_call_id,
            conversation_id=conversation_id,
            user_id=user_id,
            db=db,
            voice_enabled=voice_enabled,
            voice_id=voice_id,
        ),
        media_type="text/event-stream",
    )


async def queued_tool_result_stream(
    tool_name: str,
    result: str,
    tool_call_id: Optional[str],
    conversation_id: int,
    user_id: int,
    db: Session,
    voice_enabled: bool = False,
    voice_id: Optional[str] = None,
):
    """Queue wrapper for tool result processing"""
    try:
        acquired = await asyncio.wait_for(
            queue_service._semaphore.acquire(), timeout=queue_service.queue_timeout
        )
    except asyncio.TimeoutError:
        yield f"data: {json.dumps({'error': 'Server đang bận, vui lòng thử lại sau.'}, separators=(',', ':'))}\n\n"
        yield f"data: [DONE]\n\n"
        return

    try:
        # Call the chat service - now returns async generator directly
        stream = await ChatService.handle_client_tool_result(
            user_id=user_id,
            conversation_id=conversation_id,
            tool_name=tool_name,
            result=result,
            tool_call_id=tool_call_id,
            db=db,
            voice_enabled=voice_enabled,
            voice_id=voice_id,
        )

        # Stream the response directly - no double-wrapping
        async for chunk in stream:
            yield chunk

    finally:
        queue_service._semaphore.release()


@router.get("/queue-stats")
async def get_queue_stats(user_id: int = Depends(get_current_user)):
    """Get current queue statistics"""
    return queue_service.get_stats()
