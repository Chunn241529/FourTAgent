import base64
from fastapi import HTTPException, UploadFile
from fastapi.responses import StreamingResponse
import ollama

# NOTE: We don't use ollama's web_search/web_fetch anymore
# ToolService provides custom implementations
from app.services.tool_service import ToolService
import json
import os
from datetime import datetime
from typing import List, Dict, Any, Optional, Union
import logging
import asyncio
from sqlalchemy.orm import Session
from concurrent.futures import ThreadPoolExecutor
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

logger = logging.getLogger(__name__)
tool_service = ToolService()


SEARCH_TRIGGERS = [
    "tìm kiếm",
    "tra cứu",
    "search",
    "google",
    "tin tức",
    "thời tiết",
    "sự kiện",
    "lịch thi đấu",
    "review",
    "so sánh giá",
]

DEEP_SEARCH_TRIGGERS = [
    "tìm hiểu",
    "nghiên cứu",
    "research",
    "deep search",
    "tìm hiểu sâu",
]


class ChatService:

    @staticmethod
    async def chat_with_rag(
        message: ChatMessageIn,
        file: Optional[Union[UploadFile, str]],
        conversation_id: Optional[int],
        user_id: int,
        db: Session,
    ):
        """Xử lý chat chính với RAG integration - với debug chi tiết"""

        # Lấy thông tin user và xưng hô
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        # Xử lý conversation (Create/Get conversation FIRST)
        conversation, is_new_conversation = ChatService._get_or_create_conversation(
            db, user_id, conversation_id
        )
        logger.info(
            f"Using conversation {conversation.id}, is_new: {is_new_conversation}"
        )

        # Check for Deep Search command or triggers
        is_deep_search = message.message.strip().startswith("/deepsearch") or any(
            trigger in message.message.lower() for trigger in DEEP_SEARCH_TRIGGERS
        )

        if is_deep_search:
            from app.services.deep_search_service import DeepSearchService

            topic = message.message.strip().replace("/deepsearch", "", 1).strip()

            # If triggered by keyword but no topic (e.g. "nghiên cứu giúp tôi"), use the whole message
            if not topic or topic == message.message.strip():
                topic = message.message.strip()

            if not topic:
                return StreamingResponse(
                    iter(
                        [
                            f"data: {json.dumps({'message': {'content': 'Vui lòng nhập chủ đề cần nghiên cứu'}}, separators=(',', ':'))}\n\n"
                        ]
                    ),
                    media_type="text/event-stream",
                )

            deep_search_service = DeepSearchService()
            return StreamingResponse(
                deep_search_service.execute_deep_search(
                    topic, user_id, conversation.id, db
                ),
                media_type="text/event-stream",
            )

        gender = user.gender
        xung_ho = "anh" if gender == "male" else "chị" if gender == "female" else "bạn"
        current_time = datetime.now().strftime("%Y-%m-%d %I:%M %p %z")

        # Check search triggers
        force_search = any(
            trigger in message.message.lower() for trigger in SEARCH_TRIGGERS
        )
        if force_search:
            logger.info("Search trigger detected, forcing web search")

        # System prompt
        system_prompt = ChatService._build_system_prompt(
            xung_ho, current_time, force_search
        )

        # Xử lý file và context
        file_context = FileService.process_file_for_chat(file, user_id, conversation.id)
        effective_query = ChatService._build_effective_query(
            message.message, file, file_context
        )

        logger.info(f"Effective query: {effective_query[:200]}...")

        # Chọn model dựa trên input evaluation
        model_name, tools, level_think = ChatService._select_model(
            effective_query, file, conversation.id, db
        )
        logger.info(f"Selected model: {model_name}, level_think: {level_think}")

        # Get RAG context (Non-blocking)
        loop = asyncio.get_running_loop()
        rag_context = await loop.run_in_executor(
            None,
            lambda: RAGService.get_rag_context(
                effective_query, user_id, conversation.id, db
            ),
        )

        preference_examples = await loop.run_in_executor(
            None,
            lambda: PreferenceService.get_similar_preferences(effective_query, user_id),
        )
        if preference_examples:
            logger.info(f"Found preference examples for context injection")

        logger.info(
            f"RAG context retrieved: {len(rag_context) if rag_context else 0} characters"
        )

        # Tạo full prompt với RAG context
        full_prompt = ChatService._build_full_prompt(rag_context, effective_query, file)

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
        )

    @staticmethod
    def _build_system_prompt(
        xung_ho: str,
        current_time: str,
        force_search: bool = False,
    ) -> str:
        """Xây dựng system prompt với hướng dẫn sử dụng RAG"""
        prompt = f"""
        Bạn là Nhi - một AI nói chuyện tự nhiên như con người, rất thông minh, trẻ con, dí dỏm và thân thiện.
        Bạn tự xưng Nhi và người dùng là {xung_ho}. Ví dụ: "Nhi rất vui được giúp {xung_ho}!"  
        
        Thời gian hiện tại: {current_time}
        """

        if force_search:
            prompt += """
            
            QUAN TRỌNG: Người dùng đang yêu cầu tìm kiếm thông tin cụ thể hoặc cập nhật.
            BẠN BẮT BUỘC PHẢI SỬ DỤNG CÔNG CỤ `web_search` để tìm thông tin chính xác và mới nhất trước khi trả lời.
            
            **KHI GỌI TOOL `web_search`**:
            - Nếu cần tìm nhiều thông tin khác nhau, hãy gọi `web_search` NHIỀU LẦN (ví dụ: search A, nhận kết quả, rồi search B).
            - Luôn dùng TIẾNG ANH với KEYWORDS NGẮN GỌN (ví dụ: "Vietnam flood 2025", "Python install Ubuntu")
            - KHÔNG dùng câu hỏi dài.
            
            KHÔNG được bịa đặt thông tin. Nếu không tìm thấy, hãy nói rõ.
            TRẢ LỜI NGẮN GỌN, ĐI THẲNG VÀO VẤN ĐỀ. KHÔNG DÀI DÒNG.
            """
        else:
            # Even when not forced, add general guideline
            prompt += """
            
            **KHI CẦN TÌM KIẾM THÔNG TIN** (dùng tool `web_search`):
            - Có thể gọi `web_search` NHIỀU LẦN để thu thập đủ thông tin.
            - Luôn dùng TIẾNG ANH với KEYWORDS NGẮN GỌN.
            - TRẢ LỜI ĐÚNG TRỌNG TÂM CÂU HỎI. KHÔNG LAN MAN.
            """

        return prompt

    @staticmethod
    def _get_or_create_conversation(
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
            conversation = ModelConversation(
                user_id=user_id, created_at=datetime.utcnow()
            )
            db.add(conversation)
            db.flush()
            return conversation, True

    @staticmethod
    def _build_effective_query(user_message: str, file, file_context: str) -> str:
        """Xây dựng effective query từ message và file context"""
        if not file:
            return user_message

        is_image = FileService.is_image_file(file)
        if is_image:
            return user_message
        else:
            effective_query = f"{user_message}"
            if file_context:
                effective_query += f"\n\nFile content reference: {file_context}"
            if hasattr(file, "filename") and file.filename:
                effective_query += f"\n(File: {file.filename})"
            return effective_query

    @staticmethod
    def _select_model(
        effective_query: str, file, conversation_id: int = None, db: Session = None
    ) -> tuple:
        """Chọn model phù hợp dựa trên input evaluation"""
        if file and FileService.is_image_file(file):
            return "qwen3-vl:235b-cloud", None, False

        # Evaluate using keywords instead of LLM
        input_lower = effective_query.lower()

        # Logic keywords (math, coding, technical)
        logic_keywords = [
            "code",
            "python",
            "java",
            "c++",
            "javascript",
            "sql",
            "lập trình",
            "thuật toán",
            "bug",
            "error",
            "fix",
            "debug",
            "toán",
            "tính toán",
            "công thức",
            "phương trình",
            "logic",
            "function",
            "class",
            "api",
        ]
        needs_logic = any(k in input_lower for k in logic_keywords)

        # Sticky Logic: If current query doesn't trigger logic, check previous message
        if not needs_logic and conversation_id and db:
            try:
                # Get the last user message
                last_user_msg = (
                    db.query(ModelChatMessage)
                    .filter(
                        ModelChatMessage.conversation_id == conversation_id,
                        ModelChatMessage.role == "user",
                    )
                    .order_by(ModelChatMessage.timestamp.desc())
                    .first()
                )

                if last_user_msg:
                    last_content_lower = last_user_msg.content.lower()
                    if any(k in last_content_lower for k in logic_keywords):
                        logger.info(
                            "Sticky Logic triggered: Previous message required logic, maintaining 4T-Logic context."
                        )
                        needs_logic = True
            except Exception as e:
                logger.warning(f"Error checking sticky logic: {e}")

        # Reasoning keywords (analysis, comparison, explanation)
        reasoning_keywords = [
            "tại sao",
            "vì sao",
            "như thế nào",
            "giải thích",
            "phân tích",
            "so sánh",
            "đánh giá",
            "ý nghĩa",
            "nguyên nhân",
            "hệ quả",
            "suy luận",
            "quan điểm",
            "nhận xét",
            "ưu điểm",
            "nhược điểm",
            "khác nhau",
            "giống nhau",
        ]
        needs_reasoning = any(k in input_lower for k in reasoning_keywords)

        # Determine think level based on keywords and length
        level_think = "low"
        if needs_reasoning or needs_logic:
            if (
                len(effective_query) > 200
                or "chi tiết" in input_lower
                or "sâu" in input_lower
            ):
                level_think = "high"
            else:
                level_think = "medium"

        tools = tool_service.get_tools()

        if needs_logic:
            return "4T-Reasoning", tools, "high"
        elif needs_reasoning:
            return "4T-Reasoning", tools, level_think
        else:
            return "4T-New", tools, False

    @staticmethod
    def _get_hierarchical_memory(
        db: Session, conversation_id: int, current_query: str, user_id: int
    ) -> tuple:
        """
        Get hierarchical memory: summary + semantic + working memory.
        Returns: (summary: str, messages: List[Dict])
        """
        import numpy as np
        import json
        import faiss
        from app.services.rag_service import RAGService
        from app.services.embedding_service import EmbeddingService

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

        # 2. Working memory (last 3 messages for conversation flow)
        working_memory = (
            db.query(ModelChatMessage)
            .filter(ModelChatMessage.conversation_id == conversation_id)
            .order_by(ModelChatMessage.timestamp.desc())
            .limit(5)
            .all()
        )
        working_memory = list(reversed(working_memory))  # Chronological order
        working_ids = [msg.id for msg in working_memory]

        # 3. Semantic memory (top 5 relevant, excluding working memory)
        semantic_messages = []
        try:
            # Generate query embedding
            query_emb = EmbeddingService.get_embedding(current_query)

            # Get all messages except working memory
            all_messages = (
                db.query(ModelChatMessage)
                .filter(
                    ModelChatMessage.conversation_id == conversation_id,
                    ~ModelChatMessage.id.in_(working_ids) if working_ids else True,
                )
                .all()
            )

            if all_messages and len(all_messages) > 0:
                # Score by cosine similarity
                scored_messages = []
                for msg in all_messages:
                    if msg.embedding:
                        try:
                            msg_emb = np.array(json.loads(msg.embedding))
                            # Normalize
                            query_norm = query_emb / (np.linalg.norm(query_emb) + 1e-8)
                            msg_norm = msg_emb / (np.linalg.norm(msg_emb) + 1e-8)
                            similarity = np.dot(query_norm, msg_norm)
                            scored_messages.append((similarity, msg))
                        except:
                            continue

                # Sort and take top 5 with threshold
                scored_messages.sort(reverse=True, key=lambda x: x[0])

                # Filter by threshold (0.5 for stricter relevance)
                threshold = 0.5
                relevant_messages = [
                    (score, msg) for score, msg in scored_messages if score >= threshold
                ]

                semantic_messages = [msg for _, msg in relevant_messages[:5]]

                logger.info(
                    f"Semantic memory: {len(semantic_messages)} relevant messages (threshold={threshold}, top score={scored_messages[0][0] if scored_messages else 0:.2f})"
                )
        except Exception as e:
            logger.warning(f"Error getting semantic memory: {e}")

        # 4. Return components separately
        logger.info(
            f"Hierarchical memory: summary={bool(summary)}, semantic={len(semantic_messages)}, working={len(working_memory)}"
        )

        return summary, semantic_messages, working_memory

    @staticmethod
    def _get_conversation_history(
        db: Session, conversation_id: int, limit: int = 20
    ) -> List[Dict[str, str]]:
        """
        DEPRECATED: Use _get_hierarchical_memory instead.
        Kept for backward compatibility.
        """
        messages = (
            db.query(ModelChatMessage)
            .filter(ModelChatMessage.conversation_id == conversation_id)
            .order_by(ModelChatMessage.timestamp.asc())
            .limit(limit)
            .all()
        )

        return [{"role": msg.role, "content": msg.content} for msg in messages]

    @staticmethod
    def _build_full_prompt(rag_context: str, effective_query: str, file) -> str:
        """Xây dựng full prompt cho model - cải thiện để sử dụng RAG context"""
        if FileService.is_image_file(file):
            return effective_query

        if rag_context and rag_context.strip():
            # Tách các context chunks và format lại
            context_chunks = rag_context.split("|||")
            formatted_context = "\n\n".join(
                [f"Context {i+1}:\n{chunk}" for i, chunk in enumerate(context_chunks)]
            )

            prompt = f"""Hãy sử dụng thông tin từ các thông tin dưới đây để trả lời câu hỏi. Nếu thông tin không đủ, hãy sử dụng kiến thức của bạn.

            {formatted_context}

            Câu hỏi: {effective_query}

            Hãy trả lời dựa trên thông tin được cung cấp và luôn trả lời bằng tiếng Việt tự nhiên:"""
        else:
            prompt = effective_query

        return prompt

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
    ):
        """Generate streaming response với level_think (Async)"""

        async def generate_stream():
            yield f"data: {json.dumps({'conversation_id': conversation_id}, separators=(',', ':'))}\n\n"
            full_response = []

            # Get hierarchical memory (summary + semantic + working)
            # Use run_in_executor for embedding generation inside this method
            loop = asyncio.get_running_loop()
            summary, semantic_messages, working_memory = await loop.run_in_executor(
                None,
                lambda: ChatService._get_hierarchical_memory(
                    db, conversation_id, current_query=full_prompt, user_id=user_id
                ),
            )

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
                messages.append({"role": msg.role, "content": msg.content})

            logger.info(f"Using {len(working_memory)} messages from working memory")

            # Add current user message
            messages.append({"role": "user", "content": full_prompt})

            if file and FileService.is_image_file(file):
                file_bytes = FileService.get_file_bytes(file)
                images = [base64.b64encode(file_bytes).decode("utf-8")]
                messages[-1]["images"] = images

            save_db = None
            try:
                api_key = os.getenv("OLLAMA_API_KEY")
                if not api_key:
                    raise ValueError("OLLAMA_API_KEY env var not set")
                os.environ["OLLAMA_API_KEY"] = api_key

                # Use AsyncClient
                client = ollama.AsyncClient()

                options = {
                    "temperature": 0.6,
                    "repeat_penalty": 1.2,
                }

                max_iterations = 5
                current_iteration = 0
                has_tool_calls = False

                while current_iteration < max_iterations:
                    current_iteration += 1
                    current_message: Dict[str, Any] = {
                        "role": "assistant",
                        "content": "",
                    }
                    tool_calls: List[Dict[str, Any]] = []

                    # Async chat call
                    stream = await client.chat(
                        model=model_name,
                        messages=messages,
                        tools=tools,
                        stream=True,
                        options=options,
                        think=level_think,
                    )

                    iteration_has_tool_calls = False

                    # Async iteration over stream
                    async for chunk in stream:
                        if "message" in chunk:
                            msg_chunk = chunk["message"]
                            if "tool_calls" in msg_chunk and msg_chunk["tool_calls"]:
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

                                for tc in msg_chunk["tool_calls"]:
                                    if "function" in tc:
                                        tool_calls.append(tc)

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
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                            elif "think" in msg_chunk and msg_chunk["think"]:
                                delta = msg_chunk["think"]
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                            elif "reasoning" in msg_chunk and msg_chunk["reasoning"]:
                                delta = msg_chunk["reasoning"]
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                            elif "thought" in msg_chunk and msg_chunk["thought"]:
                                delta = msg_chunk["thought"]
                                yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"

                        # Check top-level chunk for thinking fields (some models might put it here)
                        if "reasoning_content" in chunk and chunk["reasoning_content"]:
                            delta = chunk["reasoning_content"]
                            yield f"data: {json.dumps({'thinking': delta}, separators=(',', ':'))}\n\n"
                        elif "think" in chunk and chunk["think"]:
                            delta = chunk["think"]
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

                    messages.append(current_message)

                    if tool_calls:
                        for tool_call in tool_calls:
                            function_name = tool_call["function"]["name"]
                            args_str = tool_call["function"]["arguments"]

                            # Show status message BEFORE execution
                            if function_name == "web_search":
                                try:
                                    if isinstance(args_str, str):
                                        args = json.loads(args_str)
                                    else:
                                        args = args_str

                                    query = args.get("query", "")
                                    # Emit search_started event
                                    yield f"data: {json.dumps({'tool_calls': [tool_call]}, separators=(',', ':'))}\n\n"
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
                                except Exception as e:
                                    logger.debug(
                                        f"Could not parse deep_search args: {e}"
                                    )

                            # Execute tool via service (ASYNC)
                            execution_result = await tool_service.execute_tool_async(
                                function_name, args_str
                            )

                            if execution_result["error"]:
                                tool_msg = {
                                    "role": "tool",
                                    "content": f"Error: {execution_result['error']}",
                                    "tool_name": function_name,
                                }
                            else:
                                result = execution_result["result"]

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

                                tool_msg = {
                                    "role": "tool",
                                    "content": str(result)[:8000],
                                    "tool_name": function_name,
                                }

                            messages.append(tool_msg)

                        continue
                    else:
                        break

            except Exception as e:
                logger.error(f"Lỗi trong streaming: {e}")
                yield f"data: {json.dumps({'error': str(e)}, separators=(',', ':'))}\n\n"
            finally:
                # Save assistant message BEFORE sending [DONE]
                final_content = "".join(full_response)
                logger.info(f"[DEBUG] full_response length: {len(final_content)}")

                if final_content and final_content.strip():
                    try:
                        logger.info("[DEBUG] Attempting to save assistant message...")
                        # Create new DB session for save
                        save_db = SessionLocal()
                        try:
                            ass_emb = EmbeddingService.get_embedding(final_content)
                            ass_msg = ModelChatMessage(
                                user_id=user_id,
                                conversation_id=conversation_id,
                                content=final_content,
                                role="assistant",
                                embedding=json.dumps(ass_emb.tolist()),
                            )
                            save_db.add(ass_msg)
                            save_db.commit()  # Commit to save

                            # Update FAISS index
                            RAGService.update_faiss_index(
                                user_id,
                                conversation_id,
                                save_db,
                            )

                            logger.info(
                                f"[DEBUG] Assistant message saved to DB with id={ass_msg.id}"
                            )

                            # Send message_id to client for feedback feature BEFORE [DONE]
                            msg_saved_data = json.dumps(
                                {"message_saved": {"id": ass_msg.id}},
                                separators=(",", ":"),
                            )
                            logger.info(f"[DEBUG] Yielding: {msg_saved_data}")
                            yield f"data: {msg_saved_data}\n\n"
                        finally:
                            save_db.close()
                    except Exception as e:
                        logger.error(f"[DEBUG] Error saving assistant message: {e}")
                        import traceback

                        traceback.print_exc()
                else:
                    logger.warning(
                        f"[DEBUG] Empty response (len={len(final_content)}), skipping save"
                    )

                # Send [DONE] LAST
                logger.info("[DEBUG] Sending [DONE]")
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate_stream(), media_type="text/event-stream")
