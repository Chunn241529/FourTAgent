import base64
import json
import os
import logging
import asyncio
from datetime import datetime
from typing import List, Dict, Any, Optional, Union

from fastapi import HTTPException, UploadFile

# from fastapi.responses import StreamingResponse # Unused import in original? No, it was imported. Keeping it.
from fastapi.responses import StreamingResponse
import aiohttp
import ollama

from sqlalchemy.orm import Session
from app.db import SessionLocal
from app.models import (
    ChatMessage as ModelChatMessage,
    Conversation as ModelConversation,
    User,
)
from app.schemas import ChatMessageIn
from app.services.embedding_service import EmbeddingService
from app.services.file_service import FileService
from app.services.rag_service import RAGService
from app.services.preference_service import PreferenceService
from app.services.voice_agent_service import voice_agent
from app.services.tool_service import ToolService

# Import new modules
from app.services.chat import utils, voice, models, prompts, memory

logger = logging.getLogger(__name__)
tool_service = ToolService()


class ChatService:
    # Facade for Chat Service Logic

    @staticmethod
    def get_client():
        return utils.get_client()

    @staticmethod
    def _get_random_filler() -> str:
        return voice.get_random_filler()

    @staticmethod
    async def warmup_fillers():
        await voice.warmup_fillers()

    @staticmethod
    async def cleanup_vram(model_name: str):
        await utils.cleanup_vram(model_name)

    @staticmethod
    def generate_title_suggestion(
        context: str, model_name: str = "Lumina-small"
    ) -> Optional[str]:
        return utils.generate_title_suggestion(context, model_name)

    @staticmethod
    async def chat_with_rag(
        message: ChatMessageIn,
        file: Optional[Union[UploadFile, str]],
        conversation_id: Optional[int],
        user_id: int,
        db: Session,
        voice_enabled: bool = False,
        voice_id: Optional[str] = None,
        force_canvas_tool: bool = False,
    ):
        """Xử lý chat chính với RAG integration - với debug chi tiết"""

        # Lấy thông tin user và xưng hô
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        # Xử lý conversation (Create/Get conversation FIRST)
        conversation, is_new_conversation = memory.get_or_create_conversation(
            db, user_id, conversation_id
        )
        logger.info(
            f"Using conversation {conversation.id}, is_new: {is_new_conversation}"
        )

        # Check for Deep Search slash command ONLY
        is_deep_search = message.message.strip().startswith("/deepsearch")

        if is_deep_search:
            from app.services.deep_search_service import DeepSearchService

            topic = message.message.strip().replace("/deepsearch", "", 1).strip()

            if not topic:
                # Return an async generator for consistency
                async def _empty_topic_error():
                    yield f"data: {json.dumps({'message': {'content': 'Vui lòng nhập chủ đề cần nghiên cứu'}}, separators=(',', ':'))}\n\n"

                return _empty_topic_error()

            deep_search_service = DeepSearchService()
            # Return raw generator, caller will wrap in StreamingResponse
            return deep_search_service.execute_deep_search(
                topic, user_id, conversation.id, db
            )

        gender = user.gender
        xung_ho = "anh" if gender == "male" else "chị" if gender == "female" else "bạn"
        current_time = datetime.now().strftime("%Y-%m-%d %I:%M %p %z")

        # Detect canvas mode from message content (frontend appends " dùng canvas")
        # canvas_keywords = ["dùng canvas", "sử dụng canvas", "tạo canvas"]
        # message_lower = message.message.lower()
        # if any(kw in message_lower for kw in canvas_keywords):
        #    force_canvas_tool = True
        #    logger.info("Canvas mode detected from message content")

        # Xử lý file và context
        file_context = FileService.process_file_for_chat(file, user_id, conversation.id)
        effective_query = prompts.build_effective_query(
            message.message, file, file_context
        )

        logger.info(f"Effective query: {effective_query[:200]}...")

        # Chọn model dựa trên input evaluation
        model_name, tools, level_think = models.select_model(
            effective_query, file, conversation.id, db
        )
        logger.info(f"Selected model: {model_name}, level_think: {level_think}")
        logger.info(
            f"Tools passed to model: {[t['function']['name'] for t in tools] if tools else 'None'}"
        )

        # System prompt
        system_prompt = prompts.build_system_prompt(
            xung_ho, current_time, voice_enabled, tools
        )

        if force_canvas_tool:
            system_prompt += "\n\n**[CANVAS MODE ACTIVE]** BẠN PHẢI sử dụng tool `create_canvas` hoặc `update_canvas` ngay lập tức để trả lời. Toàn bộ nội dung trả lời (văn bản, code, báo cáo) PHẢI nằm trong canvas. Không viết nội dung chính vào khung chat, chỉ đưa ra một câu thông báo ngắn như 'Lumin đã tạo/cập nhật canvas cho bạn!'."

        # Get RAG context (Non-blocking)
        loop = asyncio.get_running_loop()
        rag_context = ""
        preference_examples = ""

        # Skip RAG and preferences for Voice Agent to reduce latency
        if not voice_enabled:
            rag_context = await loop.run_in_executor(
                None,
                lambda: RAGService.get_rag_context(
                    effective_query, user_id, conversation.id, db
                ),
            )

            preference_examples = await loop.run_in_executor(
                None,
                lambda: PreferenceService.get_similar_preferences(
                    effective_query, user_id
                ),
            )
            if preference_examples:
                logger.info(f"Found preference examples for context injection")

        logger.info(
            f"RAG context retrieved: {len(rag_context) if rag_context else 0} characters"
        )

        # Tạo full prompt với RAG context
        full_prompt = prompts.build_full_prompt(rag_context, effective_query, file)

        logger.info(f"Full prompt length: {len(full_prompt)} characters")

        # Save user message IMMEDIATELY to DB (before streaming)
        # This ensures next request can see this message in history
        query_emb = await loop.run_in_executor(
            None, lambda: EmbeddingService.get_embedding(effective_query)
        )
        user_msg = ModelChatMessage(
            user_id=user_id,
            conversation_id=conversation.id,
            content=effective_query,
            role="user",
            embedding=json.dumps(query_emb.tolist()),
        )
        db.add(user_msg)
        db.commit()
        logger.info("User message saved to DB immediately")

        # Trigger title generation in background if it's a new conversation or has no title
        # We do this AFTER verifying user and creating conversation AND saving user message
        if is_new_conversation or not conversation.title:
            logger.info(
                f"Triggering background title generation for conversation {conversation.id}"
            )
            # Pass the user query directly to avoid DB lookup latency in BG task if possible,
            # but utils.generate_title_suggestion might want more context.
            # Let's pass conversation_id and let it refetch to be safe/consistent.
            asyncio.create_task(
                ChatService._generate_title_bg(conversation.id, user_id)
            )

        # Generate stream response
        # Inject preference examples into system prompt if available
        enhanced_system_prompt = system_prompt
        if preference_examples:
            enhanced_system_prompt += f"""
            **Ví dụ câu trả lời tốt (người dùng đã thích):**
            {preference_examples}
            """

        return await ChatService._generate_stream_response(
            system_prompt=enhanced_system_prompt,
            full_prompt=full_prompt,
            model_name=model_name,
            tools=tools,
            file=file,
            user_id=user_id,
            conversation_id=conversation.id,
            effective_query=effective_query,
            level_think=level_think,
            db=db,
            voice_enabled=voice_enabled,
            voice_id=voice_id,
        )

    @staticmethod
    async def _generate_title_bg(conversation_id: int, user_id: int):
        """Background task to generate conversation title"""
        try:
            # Wait a bit for the assistant to start responding/generating context
            # This allows capturing the AI's response in the context too if we wait long enough,
            # but usually the user prompt is enough for a title.
            # Let's wait 2 seconds to not block anything and ensure DB consistency.
            await asyncio.sleep(2)

            # Create a new session for this background task
            db_bg = SessionLocal()
            try:
                # Get the conversation
                conversation = (
                    db_bg.query(ModelConversation)
                    .filter(ModelConversation.id == conversation_id)
                    .first()
                )
                if not conversation:
                    return

                # Check again if title exists (race condition check)
                if conversation.title:
                    return

                # Get recent messages (first few are enough)
                messages = (
                    db_bg.query(ModelChatMessage)
                    .filter(ModelChatMessage.conversation_id == conversation_id)
                    .order_by(ModelChatMessage.timestamp.asc())
                    .limit(3)
                    .all()
                )

                if not messages:
                    return

                # Build context string
                context = ""
                for msg in messages:
                    role_str = "User" if msg.role == "user" else "Assistant"
                    context += f"{role_str}: {msg.content}\n"

                # Generate title using utility
                # Use a small/fast model for this
                model_name = "Lumina-small"  # Hardcode or config
                title = await asyncio.to_thread(
                    utils.generate_title_suggestion, context, model_name
                )

                if title:
                    conversation.title = title
                    db_bg.commit()
                    logger.info(
                        f"Generated title for conversation {conversation_id}: {title}"
                    )
                else:
                    logger.warning(
                        f"Failed to generate title for conversation {conversation_id}"
                    )

            finally:
                db_bg.close()

        except Exception as e:
            logger.error(f"Background title generation failed: {e}")

    @staticmethod
    async def _generate_stream_response(
        system_prompt: str,
        full_prompt: str,
        model_name: str,
        tools: list,
        file,
        user_id: int,
        conversation_id: int,
        effective_query: str,
        level_think: Union[str, bool],
        db: Session,
        voice_enabled: bool = False,
        voice_id: Optional[str] = None,
    ):
        """Generate streaming response với level_think (Async)"""
        # Override model for voice mode - use faster model
        if voice_enabled:
            model_name = (
                "Lumina-small:latest"  # Faster model for voice, no reasoning needed
            )
            level_think = False
            logger.info(f"Voice mode: overriding model to {model_name}")

        async def generate_stream():
            logger.info(f"Stream generation started for conversation {conversation_id}")
            yield f"data: {json.dumps({'conversation_id': conversation_id}, separators=(',', ':'))}\n\n"

            loop = asyncio.get_running_loop()

            # --- PARALLEL TASK 1: Hierarchical Memory Retrieval ---
            memory_future = loop.run_in_executor(
                None,
                lambda: memory.get_hierarchical_memory(
                    db, conversation_id, current_query=full_prompt, user_id=user_id
                ),
            )

            # --- PARALLEL TASK 2: Voice Filler Generation (if enabled) ---
            filler_audio = None
            filler_text = None
            if voice_enabled:
                filler_text = voice.get_random_filler()
                cache_key = (filler_text, voice_id)
                filler_audio = voice._filler_cache.get(cache_key)

                if not filler_audio:
                    # If not cached, try to generate asynchronously (wrapped in thread)
                    # to avoid blocking the main thread significantly if TTS is slow
                    async def _generate_filler_async():
                        try:
                            from app.services.tts_service import tts_service

                            # Run TTS in executor to avoid blocking event loop
                            audio = await loop.run_in_executor(
                                None,
                                lambda: tts_service.synthesize(
                                    filler_text, voice_id=voice_id
                                ),
                            )
                            return audio
                        except Exception as e:
                            logger.warning(f"Failed to generate filler TTS: {e}")
                            return None

                    pass

            # handle filler emission logic immediately if cached, otherwise parallelize
            if voice_enabled:
                if not filler_audio:
                    # Generate if missing
                    try:
                        from app.services.tts_service import tts_service

                        # Async generation
                        filler_audio = await loop.run_in_executor(
                            None,
                            lambda: tts_service.synthesize(
                                filler_text, voice_id=voice_id
                            ),
                        )
                        if filler_audio:
                            voice._filler_cache[(filler_text, voice_id)] = filler_audio
                    except Exception as e:
                        logger.warning(f"TTS filler gen failed: {e}")

                # Emit filler immediately if we have it
                if filler_audio:
                    try:
                        filler_b64 = base64.b64encode(filler_audio).decode("utf-8")
                        yield f"data: {json.dumps({'voice_audio': {'text': filler_text, 'audio': filler_b64, 'is_filler': True}}, separators=(',', ':'))}\n\n"
                        logger.info(f"Voice filler emitted: {filler_text}")
                    except Exception as e:
                        logger.error(f"Error emitting filler: {e}")

            # Now we wait for memory
            summary = ""
            semantic_messages = []
            working_memory = []

            try:
                # Await the memory task we started earlier
                summary, semantic_messages, working_memory = await memory_future
                logger.info("Hierarchical memory retrieved successfully")
            except Exception as e:
                logger.error(f"Error retrieving hierarchical memory: {e}")

            full_response = []

            # Update system prompt with conversation summary AND semantic memory
            enhanced_system_prompt = system_prompt

            # Add Summary
            if summary:
                enhanced_system_prompt += f"\n\n**Conversation Summary**:\n{summary}"

            # Add Semantic Memory as Context (Reference Only)
            if semantic_messages:
                enhanced_system_prompt += "\n\n**Relevant Past Context (Use ONLY if relevant to current query)**:\n"
                for msg in semantic_messages:
                    enhanced_system_prompt += f"- [{msg.role}]: {msg.content}\n"
                logger.info(
                    f"Added {len(semantic_messages)} semantic messages to system prompt"
                )

            # Build messages
            messages: List[Dict[str, Any]] = [
                {"role": "system", "content": enhanced_system_prompt}
            ]

            # Add Working Memory (Flow)
            for msg in working_memory:
                msg_dict = {"role": msg.role, "content": msg.content}

                # INJECT GENERATED IMAGES FROM HISTORY
                if msg.generated_images:
                    try:
                        gen_imgs = json.loads(msg.generated_images)
                        if gen_imgs and isinstance(gen_imgs, list):
                            # Ensure limit to avoid context overflow (max 1 recent image set?)
                            # For now, append all. Ollama handles base64 in "images" list.
                            msg_dict["images"] = gen_imgs
                            logger.info(
                                f"Injected {len(gen_imgs)} generated images into message history for Vision Model"
                            )
                    except Exception as e:
                        logger.warning(f"Failed to inject generated images: {e}")

                if msg.role == "assistant" and msg.tool_calls:
                    try:
                        msg_dict["tool_calls"] = (
                            json.loads(msg.tool_calls)
                            if isinstance(msg.tool_calls, str)
                            else msg.tool_calls
                        )
                    except:
                        pass
                elif msg.role == "tool":
                    msg_dict["tool_call_id"] = msg.tool_call_id
                    msg_dict["name"] = msg.tool_name

                messages.append(msg_dict)

            logger.info(f"Using {len(working_memory)} messages from working memory")

            # Add current user message
            messages.append({"role": "user", "content": full_prompt})

            if file and FileService.is_image_file(file):
                file_bytes = FileService.get_file_bytes(file)
                images = [base64.b64encode(file_bytes).decode("utf-8")]
                messages[-1]["images"] = images

            save_db = None
            try:
                # Reuse client
                client = utils.get_client()

                options = {
                    "temperature": 0.2,
                }

                max_iterations = 10
                current_iteration = 0
                has_tool_calls = False

                # Track executed search queries to prevent repetition
                executed_search_queries = set()
                last_saved_assistant_msg_id = None

                while current_iteration < max_iterations:
                    current_iteration += 1
                    current_message: Dict[str, Any] = {
                        "role": "assistant",
                        "content": "",
                        "thinking": "",
                    }
                    tool_calls: List[Dict[str, Any]] = []
                    accumulated_tool_calls: Dict[int, Dict[str, Any]] = (
                        {}
                    )  # Keyed by index
                    generated_images_list: List[str] = []
                    code_executions_list: List[Dict] = []
                    deep_search_updates_list: List[str] = []

                    # Async chat call
                    stream = await client.chat(
                        model=model_name,
                        messages=messages,
                        tools=tools,
                        stream=True,
                        options=options,
                        think=level_think,
                    )

                    logger.info(
                        f"Ollama chat stream started using model {model_name}. Tools count: {len(tools) if tools else 0}"
                    )

                    iteration_has_tool_calls = False

                    # Async iteration over stream
                    async for chunk in stream:
                        # logger.debug(f"DEBUG CHUNK: {chunk}")
                        if "message" in chunk:
                            msg_chunk = chunk["message"]
                            if "tool_calls" in msg_chunk and msg_chunk["tool_calls"]:
                                logger.debug(
                                    f"Tool call detected: {msg_chunk['tool_calls']}"
                                )
                                iteration_has_tool_calls = True
                                has_tool_calls = True

                                serialized_tool_calls = [
                                    {
                                        "function": {
                                            "name": tc["function"]["name"],
                                            "arguments": tc["function"]["arguments"],
                                        }
                                    }
                                    for tc in msg_chunk["tool_calls"]
                                ]
                                yield f"data: {json.dumps({'tool_calls': serialized_tool_calls}, separators=(',', ':'))}\n\n"

                                for i, tc in enumerate(msg_chunk["tool_calls"]):
                                    # Ollama often sends full objects, but let's handle potential streaming
                                    # Try to use 'index' if available, otherwise use loop index
                                    idx = tc.get("index", i)

                                    if idx not in accumulated_tool_calls:
                                        accumulated_tool_calls[idx] = tc
                                    else:
                                        # Merge arguments if they are being streamed
                                        if (
                                            "function" in tc
                                            and "arguments" in tc["function"]
                                        ):
                                            existing_args = accumulated_tool_calls[idx][
                                                "function"
                                            ]["arguments"]
                                            new_args = tc["function"]["arguments"]
                                            accumulated_tool_calls[idx]["function"][
                                                "arguments"
                                            ] = (existing_args + new_args)

                            if "content" in msg_chunk and msg_chunk["content"]:
                                delta = msg_chunk["content"]
                                current_message["content"] += delta
                                full_response.append(delta)

                            # Handle thinking/reasoning content
                            # Check in message chunk
                            if (
                                "reasoning_content" in msg_chunk
                                and msg_chunk["reasoning_content"]
                            ):
                                delta = msg_chunk["reasoning_content"]
                                current_message["thinking"] += delta
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                            elif "think" in msg_chunk and msg_chunk["think"]:
                                delta = msg_chunk["think"]
                                current_message["thinking"] += delta
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                            elif "reasoning" in msg_chunk and msg_chunk["reasoning"]:
                                delta = msg_chunk["reasoning"]
                                current_message["thinking"] += delta
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                            elif "thought" in msg_chunk and msg_chunk["thought"]:
                                delta = msg_chunk["thought"]
                                current_message["thinking"] += delta
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"

                        # Check top-level chunk for thinking fields (some models might put it here)
                        if "reasoning_content" in chunk and chunk["reasoning_content"]:
                            delta = chunk["reasoning_content"]
                            current_message["thinking"] += delta
                            yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                        elif "think" in chunk and chunk["think"]:
                            delta = chunk["think"]
                            current_message["thinking"] += delta
                            yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"

                        # Always stream the raw chunk if it's not a tool call
                        if not iteration_has_tool_calls:
                            # Convert ChatResponse to dict if needed
                            chunk_data = (
                                chunk.model_dump()
                                if hasattr(chunk, "model_dump")
                                else chunk
                            )
                            yield f"data: {json.dumps(chunk_data, separators=(',', ':'))}\n\n"

                    # Convert accumulated dictionary back to list for processing
                    if accumulated_tool_calls:
                        tool_calls = list(accumulated_tool_calls.values())

                    if tool_calls:
                        # Convert ToolCall objects to dicts for JSON serialization
                        serializable_tool_calls = []
                        for tc in tool_calls:
                            if hasattr(tc, "model_dump"):
                                serializable_tool_calls.append(tc.model_dump())
                            elif hasattr(tc, "__dict__"):
                                serializable_tool_calls.append(dict(tc))
                            else:
                                serializable_tool_calls.append(tc)
                        current_message["tool_calls"] = serializable_tool_calls

                    messages.append(current_message)
                    # Save intermediate assistant message step to DB
                    if last_saved_assistant_msg_id:
                        saved_msg = await loop.run_in_executor(
                            None,
                            lambda: memory.update_merged_message(
                                db,
                                last_saved_assistant_msg_id,
                                current_message,
                                thinking=current_message.get("thinking"),
                            ),
                        )
                    else:
                        saved_msg = await loop.run_in_executor(
                            None,
                            lambda: memory.save_message_to_db(
                                db,
                                user_id,
                                conversation_id,
                                current_message,
                                thinking=current_message.get("thinking"),
                            ),
                        )
                        if saved_msg:
                            last_saved_assistant_msg_id = saved_msg.id

                    if tool_calls:
                        # 1. Prepare tasks and emit "Started" events
                        tasks = []
                        skipped_duplicate_count = 0
                        tool_call_to_task_mapping = (
                            []
                        )  # Track which tool_calls have tasks

                        for tool_call in tool_calls:
                            function_name = tool_call["function"]["name"]
                            args_str = tool_call["function"]["arguments"]
                            should_skip = False

                            # Show status message BEFORE execution
                            if function_name == "web_search":
                                try:
                                    if isinstance(args_str, str):
                                        args = json.loads(args_str)
                                    else:
                                        args = args_str

                                    query = args.get("query", "")

                                    # Normalize query for deduplication
                                    normalized_query = query.lower().strip()

                                    # Check if this query was already executed
                                    if normalized_query in executed_search_queries:
                                        logger.warning(
                                            f"Duplicate search query detected: '{query}'. Warning model."
                                        )
                                        # Add a tool message to inform model about the duplicate
                                        messages.append(
                                            {
                                                "role": "tool",
                                                "content": f"Query '{query}' đã được tìm kiếm trước đó. Hãy thử từ khóa KHÁC hoặc sử dụng thông tin đã có.",
                                                "tool_name": function_name,
                                            }
                                        )
                                        skipped_duplicate_count += 1
                                        should_skip = True
                                    else:
                                        # Track this query
                                        executed_search_queries.add(normalized_query)

                                        # Emit search_started event
                                        # Ensure tool_call is serializable
                                        tool_call_dict = tool_call
                                        if hasattr(tool_call, "model_dump"):
                                            tool_call_dict = tool_call.model_dump()
                                        elif hasattr(tool_call, "dict"):
                                            tool_call_dict = tool_call.dict()
                                        elif not isinstance(tool_call, dict):
                                            try:
                                                tool_call_dict = dict(tool_call)
                                            except:
                                                pass

                                        yield f"data: {json.dumps({'tool_calls': [tool_call_dict]}, separators=(',', ':'))}\n\n"
                                except Exception as e:
                                    logger.debug(
                                        f"Could not parse web_search args: {e}"
                                    )

                            elif function_name == "deep_search":
                                try:
                                    if isinstance(args_str, str):
                                        args = json.loads(args_str)
                                    else:
                                        args = args_str

                                    topic = args.get("topic", "")
                                    status_msg = (
                                        f"🔬 Đang thực hiện nghiên cứu sâu: {topic}..."
                                    )

                                    yield f"data: {json.dumps({'deep_search_started': {'topic': topic, 'message': status_msg}}, separators=(',', ':'))}\n\n"

                                    # SPECIAL HANDLING: Inject DeepSearch stream directly
                                    # DeepSearch already does everything (research + synthesis)
                                    # So we don't need LLM to process the result
                                    from app.services.deep_search_service import (
                                        DeepSearchService,
                                    )

                                    deep_search_service = DeepSearchService()

                                    # Yield all SSE events from DeepSearch generator (now async)
                                    async for (
                                        sse_chunk
                                    ) in deep_search_service.execute_deep_search(
                                        topic, user_id, conversation_id, db
                                    ):
                                        # Extract data for persistence if available
                                        if isinstance(
                                            sse_chunk, str
                                        ) and sse_chunk.startswith("data: "):
                                            try:
                                                data_json = json.loads(sse_chunk[6:])
                                                if "deep_search_update" in data_json:
                                                    deep_search_updates_list.append(
                                                        sse_chunk
                                                    )
                                            except:
                                                pass
                                        yield sse_chunk

                                    # After Deep Search completes, update the Assistant message in DB with logs
                                    if deep_search_updates_list and saved_msg:
                                        await loop.run_in_executor(
                                            None,
                                            lambda: memory.update_message_deep_search_logs(
                                                db,
                                                saved_msg.id,
                                                deep_search_updates_list,
                                            ),
                                        )

                                    # DeepSearch already saves to DB, so we're done
                                    # Exit the tool loop and main loop
                                    return

                                except Exception as e:
                                    logger.error(f"Deep search error: {e}")
                                    yield f"data: {json.dumps({'error': f'Deep Search failed: {str(e)}'}, separators=(',', ':'))}\n\n"
                                    # Fall through to normal processing or return [DONE]
                                should_skip = True  # deep_search is handled separately

                            elif function_name.startswith("client_"):
                                # Handle client-run tools by yielding and breaking
                                # The client will execute and then re-call the API with the result
                                try:
                                    if isinstance(args_str, str):
                                        args = json.loads(args_str)
                                    else:
                                        args = args_str

                                    # Emit client_tool_call event
                                    yield f"data: {json.dumps({'client_tool_call': {'name': function_name, 'args': args, 'tool_call_id': tool_call.get('id')}}, separators=(',', ':'))}\n\n"

                                    # We MUST stop the stream here because we need the client's input to continue
                                    # The client is responsible for resuming the conversation.
                                    return
                                except Exception as e:
                                    logger.error(f"Error preparing client tool: {e}")
                                    # Fall through if error

                            # Create task for parallel execution (only for non-skipped, non-deep_search tools)
                            if not should_skip and function_name != "deep_search":
                                # Emit start event for image generation to show UI loading state
                                if function_name == "generate_image":
                                    yield f"data: {json.dumps({'image_generation_started': True}, separators=(',', ':'))}\n\n"

                                    # --- SEED REUSE LOGIC ---
                                    # Check if this is an "edit" request and inject seed
                                    try:
                                        img_args = (
                                            json.loads(args_str)
                                            if isinstance(args_str, str)
                                            else args_str
                                        )
                                        if isinstance(img_args, dict):
                                            current_query_lower = (
                                                effective_query.lower()
                                            )
                                            edit_keywords = [
                                                "change",
                                                "edit",
                                                "modify",
                                                "update",
                                                "replace",
                                                "thêm",
                                                "sửa",
                                                "đổi",
                                                "chỉnh",
                                                "bỏ",
                                                "xoá",
                                                "fix",
                                                "biến",
                                            ]
                                            is_edit = any(
                                                k in current_query_lower
                                                for k in edit_keywords
                                            )

                                            if is_edit:
                                                last_seed = None
                                                # Scan history for previous generate_image seed
                                                # Look in messages list which contains history
                                                for msg in reversed(messages):
                                                    if (
                                                        msg.get("role") == "tool"
                                                        or msg.get("role") == "function"
                                                    ):
                                                        t_name = msg.get(
                                                            "tool_name"
                                                        ) or msg.get("name")
                                                        if t_name == "generate_image":
                                                            try:
                                                                content_json = (
                                                                    json.loads(
                                                                        msg.get(
                                                                            "content",
                                                                            "{}",
                                                                        )
                                                                    )
                                                                )
                                                                if (
                                                                    "seed"
                                                                    in content_json
                                                                ):
                                                                    last_seed = (
                                                                        content_json[
                                                                            "seed"
                                                                        ]
                                                                    )
                                                                    break
                                                            except:
                                                                pass

                                                if last_seed is not None:
                                                    img_args["seed"] = last_seed
                                                    logger.info(
                                                        f"♻️ Injected seed {last_seed} for image edit request"
                                                    )
                                                    # Update args_str with new seed
                                                    args_str = json.dumps(img_args)
                                    except Exception as e:
                                        logger.warning(
                                            f"Error in seed injection logic: {e}"
                                        )

                                tasks.append(
                                    tool_service.execute_tool_async(
                                        function_name,
                                        args_str,
                                        context={"user_id": user_id},
                                    )
                                )
                                tool_call_to_task_mapping.append(tool_call)

                        # If all tool calls were duplicates, break to prevent infinite loop
                        if (
                            skipped_duplicate_count > 0
                            and skipped_duplicate_count == len(tool_calls)
                        ):
                            logger.warning(
                                "All tool calls were duplicates. Breaking to prevent loop."
                            )
                            break

                        # If no tasks to execute, continue to next iteration
                        if not tasks:
                            continue

                        # 2. Execute all tasks in parallel
                        # Limit concurrency to 3 if there are many tasks (as per user request)
                        execution_results = await asyncio.gather(*tasks)

                        # 3. Process results
                        for i, execution_result in enumerate(execution_results):
                            function_name = execution_result["tool_name"]
                            tool_call = tool_call_to_task_mapping[i]
                            args_str = tool_call["function"]["arguments"]
                            result = execution_result["result"]
                            error = execution_result["error"]

                            # For generate_image: filter result for LLM (hide paths/technical details)
                            tool_content = (
                                str(result)[:8000] if not error else f"Error: {error}"
                            )

                            # Handle Canvas updates - notify frontend immediately
                            if (
                                function_name in ["create_canvas", "update_canvas"]
                                and not error
                            ):
                                try:
                                    res_json = (
                                        json.loads(result)
                                        if isinstance(result, str)
                                        else result
                                    )
                                    if res_json.get("success") and res_json.get(
                                        "canvas"
                                    ):
                                        yield f"data: {json.dumps({'canvas_update': res_json['canvas']}, ensure_ascii=False)}\n\n"
                                except Exception as e:
                                    logger.error(f"Error yielding canvas update: {e}")

                            # Handle execute_python - stream result to frontend
                            if function_name == "execute_python":
                                try:
                                    # result is already a dict from CodeInterpreterService
                                    res_json = result
                                    if isinstance(res_json, str):
                                        try:
                                            res_json = json.loads(res_json)
                                        except:
                                            res_json = {
                                                "output": res_json,
                                                "success": True,
                                            }

                                    # Prepare event data
                                    # args_str might be JSON string
                                    try:
                                        # args_str might be JSON string or already a dict
                                        if isinstance(args_str, dict):
                                            code_input = args_str.get("code", "")
                                        else:
                                            try:
                                                code_input = json.loads(args_str).get(
                                                    "code", ""
                                                )
                                            except:
                                                code_input = (
                                                    "Code not available (parse error)"
                                                )
                                    except:
                                        code_input = "Code not available"

                                    event_data = {
                                        "code_execution_result": {
                                            "code": code_input,
                                            "output": res_json.get("output", ""),
                                            "error": res_json.get("error", ""),
                                            "tool_call_id": tool_call.get("id"),
                                            "success": res_json.get("success", False),
                                        }
                                    }
                                    yield f"data: {json.dumps(event_data, ensure_ascii=False)}\n\n"

                                    # Add to list for persistence
                                    code_executions_list.append(
                                        event_data["code_execution_result"]
                                    )

                                except Exception as e:
                                    logger.error(
                                        f"Error yielding code execution result: {e}"
                                    )

                            if function_name == "generate_image" and not error:
                                try:
                                    result_data = (
                                        json.loads(result)
                                        if isinstance(result, str)
                                        else result
                                    )
                                    if result_data.get("success"):
                                        # Only send user-friendly message to LLM
                                        tool_content = json.dumps(
                                            {
                                                "success": True,
                                                "message": result_data.get(
                                                    "message", "Đã tạo xong ảnh!"
                                                ),
                                                "seed": result_data.get("seed"),
                                                "prompt": result_data.get(
                                                    "generated_prompt"
                                                ),
                                            },
                                            ensure_ascii=False,
                                        )
                                except:
                                    pass

                            tool_msg = {
                                "role": "tool",
                                "content": tool_content,
                                "tool_name": function_name,
                                "tool_call_id": tool_call.get("id"),
                            }

                            if not error:
                                # Handle search specific logic (sending status)
                                if function_name == "web_search":
                                    try:
                                        # Parse args for query
                                        if isinstance(args_str, str):
                                            args = json.loads(args_str)
                                        else:
                                            args = args_str

                                        result_data = (
                                            json.loads(result)
                                            if isinstance(result, str)
                                            else result
                                        )
                                        result_count = (
                                            len(result_data.get("results", []))
                                            if isinstance(result_data, dict)
                                            else 0
                                        )

                                        # Clean query: remove newlines and truncate
                                        query = args.get("query", "")
                                        query = (
                                            query.replace("\n", " ")
                                            .replace("\r", " ")
                                            .strip()
                                        )
                                        if len(query) > 100:
                                            query = query[:100] + "..."

                                        # Use separators to ensure compact JSON
                                        yield f"data: {json.dumps({'search_complete': {'query': query, 'count': result_count}}, separators=(',', ':'))}\n\n"
                                    except Exception as e:
                                        logger.debug(
                                            f"Could not parse search results for count: {e}"
                                        )

                                elif function_name == "search_music":
                                    # Add logging for search_music
                                    try:
                                        result_data = (
                                            json.loads(result)
                                            if isinstance(result, str)
                                            else result
                                        )
                                        results = result_data.get("results", [])
                                        count = len(results)
                                        logger.debug(
                                            f"Music search found {count} results"
                                        )

                                        # Emit thinking update
                                        yield f"data: {json.dumps({'thinking': f'Found {count} songs...'}, separators=(',', ':'))}\n\n"

                                        # AUTO-PLAY Logic: Pick first result and play immediately
                                        if count > 0:
                                            first_song = results[0]
                                            song_url = first_song.get("url")
                                            song_title = first_song.get("title")

                                            logger.debug(
                                                f"Auto-playing first result: {song_title}"
                                            )
                                            yield f"data: {json.dumps({'thinking': f'Auto-playing: {song_title}...'}, separators=(',', ':'))}\n\n"

                                            # Call play_music directly
                                            from app.services.music_service import (
                                                music_service,
                                            )

                                            play_result_json = music_service.play_music(
                                                song_url
                                            )
                                            play_result = json.loads(play_result_json)

                                            if (
                                                "action" in play_result
                                                and play_result["action"]
                                                == "play_music"
                                            ):
                                                logger.info(
                                                    f"[MUSIC] Auto-emitting music_play for: {play_result.get('title')}"
                                                )
                                                yield f"data: {json.dumps({'music_play': play_result}, separators=(',', ':'))}\n\n"
                                            else:
                                                logger.error(
                                                    f"[MUSIC] Auto-play failed: {play_result}"
                                                )

                                    except Exception as e:
                                        logger.debug(
                                            f"Error processing search_music result: {e}"
                                        )

                                # Handle play_music - emit music_play event for Flutter to play
                                elif function_name == "play_music":
                                    try:
                                        logger.info(
                                            f"[MUSIC] play_music result: {result[:200] if result else 'None'}"
                                        )
                                        result_data = (
                                            json.loads(result)
                                            if isinstance(result, str)
                                            else result
                                        )
                                        if (
                                            "action" in result_data
                                            and result_data["action"] == "play_music"
                                        ):
                                            logger.info(
                                                f"[MUSIC] Emitting music_play event for: {result_data.get('title', 'Unknown')}"
                                            )
                                            yield f"data: {json.dumps({'music_play': result_data}, separators=(',', ':'))}\n\n"
                                    except Exception as e:
                                        logger.error(
                                            f"Could not parse play_music result: {e}"
                                        )

                                elif function_name == "add_to_queue":
                                    try:
                                        result_data = (
                                            json.loads(result)
                                            if isinstance(result, str)
                                            else result
                                        )
                                        if (
                                            "action" in result_data
                                            and result_data["action"] == "add_to_queue"
                                        ):
                                            yield f"data: {json.dumps({'music_queue_add': result_data}, separators=(',', ':'))}\n\n"
                                    except Exception as e:
                                        logger.error(
                                            f"Error emitting music_queue_add: {e}"
                                        )

                                elif function_name in [
                                    "stop_music",
                                    "pause_music",
                                    "resume_music",
                                    "next_music",
                                    "previous_music",
                                ]:
                                    try:
                                        result_data = (
                                            json.loads(result)
                                            if isinstance(result, str)
                                            else result
                                        )
                                        if "action" in result_data:
                                            # Emit generic music_control event
                                            yield f"data: {json.dumps({'music_control': result_data}, separators=(',', ':'))}\n\n"
                                    except Exception as e:
                                        logger.error(
                                            f"Error emitting music_control for {function_name}: {e}"
                                        )

                                elif function_name in [
                                    "read_file",
                                    "create_file",
                                    "search_file",
                                ]:
                                    try:
                                        if isinstance(args_str, str):
                                            args = json.loads(args_str)
                                        else:
                                            args = args_str

                                        # Determine target (path or query)
                                        path = args.get("path")
                                        query = args.get("query")
                                        target = path if path else query

                                        if target:
                                            # Format: ACTION:Target
                                            # Must match Flutter's expected format (READ:path, CREATE:path, SEARCH_FILE:query)
                                            action = ""
                                            if function_name == "read_file":
                                                action = "READ"
                                            elif function_name == "create_file":
                                                action = "CREATE"
                                            elif function_name == "search_file":
                                                action = "SEARCH_FILE"

                                            completion_tag = f"{action}:{target}"

                                            yield f"data: {json.dumps({'file_tool_complete': {'tag': completion_tag}}, separators=(',', ':'))}\n\n"
                                    except Exception as e:
                                        logger.error(
                                            f"Error emitting file tool complete event: {e}"
                                        )

                                # Handle generate_image - emit image_generated event for Flutter
                                elif function_name == "generate_image":
                                    try:
                                        result_data = (
                                            json.loads(result)
                                            if isinstance(result, str)
                                            else result
                                        )

                                        # Emit event for both success and failure so UI can handle it
                                        logger.info(
                                            f"[IMAGE] Emitting image_generated event (Success: {result_data.get('success')})"
                                        )
                                        yield f"data: {json.dumps({'image_generated': result_data}, separators=(',', ':'))}\n\n"

                                        if result_data.get("success"):
                                            if result_data.get("image_base64"):
                                                generated_images_list.append(
                                                    result_data["image_base64"]
                                                )
                                        else:
                                            logger.error(
                                                f"[IMAGE] Generation failed: {result_data.get('error')}"
                                            )
                                    except Exception as e:
                                        logger.error(
                                            f"Error emitting image_generated event: {e}"
                                        )

                            messages.append(tool_msg)
                            # Save tool result to DB
                            await loop.run_in_executor(
                                None,
                                lambda: memory.save_message_to_db(
                                    db, user_id, conversation_id, tool_msg
                                ),
                            )

                        # After tool execution loop (inside if tool_calls block)
                        # If images were generated, update the assistant message
                        if generated_images_list and saved_msg:
                            await loop.run_in_executor(
                                None,
                                lambda: memory.update_message_generated_images(
                                    db, saved_msg.id, generated_images_list
                                ),
                            )

                        # Save code executions if any
                        if code_executions_list and saved_msg:
                            await loop.run_in_executor(
                                None,
                                lambda: memory.update_message_code_executions(
                                    db, saved_msg.id, code_executions_list
                                ),
                            )

                        continue
                    else:
                        break

            except Exception as e:
                logger.error(f"Lỗi trong streaming: {e}")
                yield f"data: {json.dumps({'error': str(e)}, separators=(',', ':'))}\n\n"
            finally:
                # Save final text if any was missed (unlikely but safe)
                final_content = "".join(full_response)

                # Perform RAG indexing for the conversation
                try:
                    RAGService.update_faiss_index(user_id, conversation_id, db)
                except Exception as e:
                    logger.warning(
                        f"Failed to update FAISS index at end of stream: {e}"
                    )

                # Get the last assistant message ID to send to client
                last_ass_msg = (
                    db.query(ModelChatMessage)
                    .filter(
                        ModelChatMessage.conversation_id == conversation_id,
                        ModelChatMessage.role == "assistant",
                    )
                    .order_by(ModelChatMessage.id.desc())
                    .first()
                )

                if last_ass_msg:
                    yield f"data: {json.dumps({'message_saved': {'id': last_ass_msg.id}}, separators=(',', ':'))}\n\n"

                # Stream voice audio if enabled (after text is complete)
                if voice_enabled and final_content and final_content.strip():
                    try:
                        logger.info("[VoiceAgent] Starting audio streaming...")
                        async for audio_event in voice_agent.stream_audio_chunks(
                            final_content, voice_id or "Đoan"
                        ):
                            yield f"data: {json.dumps({'voice_audio': audio_event}, separators=(',', ':'))}\n\n"
                        logger.info("[VoiceAgent] Audio streaming complete")
                    except Exception as e:
                        logger.error(f"[VoiceAgent] Audio streaming error: {e}")

                yield "data: [DONE]\n\n"

                # Cleanup VRAM after stream completes
                await utils.cleanup_vram(model_name)

        # Return the generator directly for the caller to wrap
        # This avoids double-wrapping in StreamingResponse which causes buffering
        return generate_stream()

    @staticmethod
    async def handle_client_tool_result(
        user_id: int,
        conversation_id: int,
        tool_name: str,
        result: str,
        tool_call_id: Optional[str],
        db: Session,
        voice_enabled: bool = False,
        voice_id: Optional[str] = None,
    ):
        """
        Special handler for continuing a stream after a client-side tool execution.
        """
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        # 1. Save tool result to DB
        tool_msg = {
            "role": "tool",
            "content": result,
            "tool_name": tool_name,
            "tool_call_id": tool_call_id,
        }
        memory.save_message_to_db(db, user_id, conversation_id, tool_msg)

        # 2. Re-setup context
        last_user_msg = (
            db.query(ModelChatMessage)
            .filter(
                ModelChatMessage.conversation_id == conversation_id,
                ModelChatMessage.role == "user",
            )
            .order_by(ModelChatMessage.id.desc())
            .first()
        )
        effective_query = (
            last_user_msg.content if last_user_msg else "Continuing tool processing"
        )
        gender = user.gender
        xung_ho = "anh" if gender == "male" else "chị" if gender == "female" else "bạn"
        current_time = datetime.now().strftime("%Y-%m-%d %I:%M %p %z")

        model_name, tools, level_think = models.select_model(
            effective_query, None, conversation_id, db
        )
        system_prompt = prompts.build_system_prompt(
            xung_ho, current_time, False, voice_enabled
        )

        # 3. Resume streaming
        return await ChatService._generate_stream_response(
            system_prompt=system_prompt,
            full_prompt=effective_query,
            model_name=model_name,
            tools=tools,
            file=None,
            user_id=user_id,
            conversation_id=conversation_id,
            effective_query=effective_query,
            level_think=level_think,
            db=db,
            voice_enabled=voice_enabled,
            voice_id=voice_id,
        )
