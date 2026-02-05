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
from app.services.voice_agent_service import voice_agent

logger = logging.getLogger(__name__)
tool_service = ToolService()


# Triggers removed for autonomous LLM


class ChatService:
    # Reuse Ollama Client
    _client = None

    # Cache for voice fillers: {(text, voice_id): audio_bytes}
    _filler_cache = {}

    # Track last used filler index to avoid repetition
    _last_filler_index = -1

    # List of filler phrases to rotate
    FILLER_PHRASES = [
        "Ok, được rồi, đợi em chút nhé",
        "Được rồi, đợi em chút nhé",
        "Đợi em một chút nhé",
    ]

    @classmethod
    def get_client(cls):
        """Get or create singleton AsyncClient"""
        if cls._client is None:
            # Check API Key
            api_key = os.getenv("OLLAMA_API_KEY")
            if not api_key:
                # Minimal fallback or let it fail later
                logger.warning("OLLAMA_API_KEY not set in env, connection might fail.")
            else:
                os.environ["OLLAMA_API_KEY"] = api_key

            cls._client = ollama.AsyncClient()
        return cls._client

    @classmethod
    def _get_random_filler(cls) -> str:
        """Get a random filler that's different from the last one used"""
        import random

        if len(cls.FILLER_PHRASES) <= 1:
            return cls.FILLER_PHRASES[0] if cls.FILLER_PHRASES else ""

        # Get available indices (excluding the last used one)
        available_indices = [
            i for i in range(len(cls.FILLER_PHRASES)) if i != cls._last_filler_index
        ]

        # Pick a random index from available ones
        new_index = random.choice(available_indices)
        cls._last_filler_index = new_index

        return cls.FILLER_PHRASES[new_index]

    @classmethod
    async def warmup_fillers(cls):
        """Pre-generate fillers for all voices to avoid latency"""
        from app.services.tts_service import tts_service

        logger.info("Starting filler warmup...")

        try:
            voices = tts_service.list_voices()

            # Loop through all available voices
            for voice in voices:
                voice_id = voice["id"]

                # Loop through all filler phrases
                for filler_text in cls.FILLER_PHRASES:
                    cache_key = (filler_text, voice_id)

                    # Check if already cached
                    if cache_key not in cls._filler_cache:
                        try:
                            # logger.info(f"Warming up filler '{filler_text}' for voice: {voice_id}")
                            audio = tts_service.synthesize(
                                filler_text, voice_id=voice_id
                            )
                            if audio:
                                cls._filler_cache[cache_key] = audio
                        except Exception as e:
                            logger.warning(f"Failed to warmup voice {voice_id}: {e}")

            logger.info(
                f"Filler warmup complete. Cached {len(cls._filler_cache)} items."
            )

        except Exception as e:
            logger.error(f"Warmup process failed: {e}")

    @staticmethod
    async def chat_with_rag(
        message: ChatMessageIn,
        file: Optional[Union[UploadFile, str]],
        conversation_id: Optional[int],
        user_id: int,
        db: Session,
        voice_enabled: bool = False,
        voice_id: Optional[str] = None,
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

        # System prompt
        system_prompt = ChatService._build_system_prompt(
            xung_ho, current_time, voice_enabled
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
            voice_enabled=voice_enabled,
            voice_id=voice_id,
        )

    @staticmethod
    def _build_system_prompt(
        xung_ho: str,
        current_time: str,
        voice_enabled: bool = False,
    ) -> str:
        """Xây dựng system prompt với hướng dẫn sử dụng Tool Tự động"""
        prompt = f"""
        Bạn là Lumin - một AI nói chuyện tự nhiên như con người, rất thông minh, trẻ con, dí dỏm và thân thiện.
        Bạn tự xưng Lumin và người dùng là {xung_ho}. Ví dụ: "Lumin rất vui được giúp {xung_ho}!"  
        
        Thời gian hiện tại: {current_time}

        **CHÍNH SÁCH SỬ DỤNG CÔNG CỤ:**
        Bạn có các công cụ mạnh. **TỰ QUYẾT ĐỊNH** khi dùng - KHÔNG hỏi trước.
        
        **1. Web Search (`web_search`)** - TÌM KIẾM:
           **TRIGGER**: Người dùng hỏi tin tức, giá cả, review, hoặc info bạn không chắc
           **VD**: "iPhone 16 giá bao nhiêu?" → `web_search("iPhone 16 price Vietnam")`
           **ACTION**: Thấy cần info → Gọi ngay, dùng English keywords

        2. **Music Player (`search_music`, `play_music`, `get_current_playing`)**:
           - **KHI NÀO DÙNG**:
             - Khi người dùng muốn nghe nhạc (ví dụ: "Mở nhạc chill đi", "Nghe bài Lạc Trôi").
             - Khi người dùng buồn và bạn muốn tặng một bài hát.
             - Khi người dùng hỏi đang phát bài gì → dùng `get_current_playing()`.
           - **CÁCH DÙNG**:
             - Luôn gọi `search_music(query="...")` trước để tìm bài.
             - **LUÔN LUÔN** tự động chọn bài phù hợp nhất (thường là bài đầu tiên) và gọi `play_music(url="...")` NGAY LẬP TỨC.
             - **KHÔNG BAO GIỜ** đưa danh sách hỏi user chọn bài nào - hãy tự quyết định và phát luôn.

        **3. Image Generation (`generate_image`)** - TẠO ẢNH:
           **TRIGGER**: Người dùng muốn thấy/tạo/vẽ hình ảnh, hoặc mô tả visual
           **VD**: 
           - "Vẽ con mèo" → `generate_image(prompt="cute cat, digital art", size="1024x1024")`
           - "Tạo ảnh cô gái" → `generate_image(prompt="1girl, cute smile", size="768x768")`
           - "Làm hình nền" → `generate_image(prompt="beautiful landscape", size="1024x1024")`
           **PARAMS**:
           - `prompt`: Viết TIẾNG ANH, format: [Subject], [Style], [Details], [Quality]
             - Style: Photo → `photo, 35mm, f/1.8`, Art → `digital art`
             - Kết thúc: `masterpiece, best quality, ultra high res, (photorealistic:1.4), 8k uhd`
           - `size`: "512x512", "768x768" (default), "1024x1024" (tốt nhất cho chi tiết), ...
           - VD: "1girl, smile, cafe, soft light, masterpiece, best quality, ultra high res, (photorealistic:1.4), 8k uhd"

        4. **Deep Search (`deep_search`)**:
           - **KHI NÀO DÙNG**: Khi người dùng yêu cầu "nghiên cứu", "tìm hiểu sâu", hoặc hỏi một vấn đề rất phức tạp cần báo cáo chi tiết.
        
        **QUY TẮC TRẢ LỜI:**
        - Nếu bạn dùng tool, hãy dùng thông tin từ tool để trả lời thật đầy đủ và chi tiết.
        - Nếu không dùng tool, hãy trả lời bằng kiến thức của bạn.
        - Luôn giữ thái độ vui vẻ, thân thiện của Lumin.
        """

        if voice_enabled:
            prompt += """
            **CHẾ ĐỘ GIỌNG NÓI (VOICE MODE):**
            Bạn đang trả lời qua loa (Audio).
            - Trả lời ngắn gọn, súc tích hơn văn bản.
            - Không dùng Markdown (bold, italic, list).
            - Nói chuyện tự nhiên, không đọc URL dài dòng.
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
            return "qwen3-vl:8b-instruct", None, False

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
            "giải thích",
            "phân tích",
            "suy luận",
            "tạo file",
            "file",
            "hồ sơ",
            "tài liệu",
            "dataset",
            "dữ liệu",
            "nghiên cứu",
            "tìm kiếm",
        ]
        needs_reasoning = any(k in input_lower for k in reasoning_keywords)

        tools = tool_service.get_tools()

        if needs_logic:
            return "qwen3-coder", tools, False
        elif needs_reasoning:
            return "Lumina", tools, True
        else:
            # Check if there are any images in recent history (working memory) to enable Vision
            if conversation_id and db:
                try:
                    # Check last 3 messages for generated_images or potential image content
                    recent_msgs = (
                        db.query(ModelChatMessage)
                        .filter(ModelChatMessage.conversation_id == conversation_id)
                        .order_by(ModelChatMessage.timestamp.desc())
                        .limit(3)
                        .all()
                    )
                    for msg in recent_msgs:
                        # detections: 1. Application-generated images
                        has_generated = False
                        if msg.generated_images:
                            try:
                                imgs = json.loads(msg.generated_images)
                                if imgs and len(imgs) > 0:
                                    has_generated = True
                            except:
                                pass

                        # detections: 2. User uploaded images (blind check if not storing file metadata in useful way yet,
                        # but standard flow usually processes file immediately.
                        # However, if we want to "chat about previous image", we need vision model.)

                        if has_generated:
                            pass
                            # logger.info(
                            #     "Found images in recent history, switching to Vision Model (qwen3-vl:8b)"
                            # )
                            # return "qwen3-vl:8b", tools, False

                except Exception as e:
                    logger.warning(
                        f"Error checking recent images for vision switch: {e}"
                    )

            return "Lumina", tools, False

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

            Hãy trả lời dựa trên thông tin được cung cấp và luôn trả lời bằng tiếng Việt"""
        else:
            prompt = effective_query

        return prompt

    @staticmethod
    def generate_title_suggestion(
        context: str, model_name: str = "Lumina-small"
    ) -> Optional[str]:
        """Generate a title for the conversation context"""
        try:
            print(f"DEBUG: Generating title with model {model_name}")

            system_prompt = (
                "Bạn là chuyên gia tạo tiêu đề cho cuộc hội thoại. "
                "Nhiệm vụ: Tạo tiêu đề ngắn gọn (tối đa 6 từ) tóm tắt chủ đề chính. "
                "CHỈ TRẢ VỀ TIÊU ĐỀ, không giải thích, không dùng dấu ngoặc kép."
            )

            user_prompt = f"Tạo tiêu đề ngắn gọn cho cuộc trò chuyện sau:\n\n{context}"

            response = ollama.chat(
                model=model_name,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                options={"num_predict": 50, "temperature": 0.3},
                stream=False,
                think=False,
            )

            title = response["message"]["content"].strip().strip('"')
            if not title:
                return None

            return title
        except Exception as e:
            logger.error(f"Title generation failed: {e}")
            return None

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
                lambda: ChatService._get_hierarchical_memory(
                    db, conversation_id, current_query=full_prompt, user_id=user_id
                ),
            )

            # --- PARALLEL TASK 2: Voice Filler Generation (if enabled) ---
            filler_audio = None
            filler_text = None
            if voice_enabled:
                filler_text = ChatService._get_random_filler()
                cache_key = (filler_text, voice_id)
                filler_audio = ChatService._filler_cache.get(cache_key)

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

                    # Start generation task
                    # We await it later or do we want to emit it AS SOON AS POSSIBLE?
                    # Ideally we want to emit it ASAP.
                    # Let's simple await it here since it's "parallel" to memory retrieval
                    # But wait! run_in_executor starts immediately.
                    # We can await the specific filler generation here concurrently with memory.

                    # Refinement: We want to emit the filler audio ASAP to the client.
                    # So we shouldn't wait for memory to finish before emitting filler.
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
                            ChatService._filler_cache[(filler_text, voice_id)] = (
                                filler_audio
                            )
                    except Exception as e:
                        logger.warning(f"TTS filler gen failed: {e}")

                # Emit filler immediately if we have it
                if filler_audio:
                    try:
                        import base64

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
                client = ChatService.get_client()

                options = {
                    "temperature": 0.6,
                    "repeat_penalty": 1.2,
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
                    generated_images_list: List[str] = []
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

                    logger.info(f"Ollama chat stream started using model {model_name}")

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
                    # Save intermediate assistant message step to DB
                    if last_saved_assistant_msg_id:
                        saved_msg = await loop.run_in_executor(
                            None,
                            lambda: ChatService._update_merged_message(
                                db,
                                last_saved_assistant_msg_id,
                                current_message,
                                thinking=current_message.get("thinking"),
                            ),
                        )
                    else:
                        saved_msg = await loop.run_in_executor(
                            None,
                            lambda: ChatService._save_message_to_db(
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
                                    # Since Deep Search is a "tool", but special handling might mean we need to attach logs to the tool output or assistant message?
                                    # Actually deep_search is executed as a tool call. The logs should probably be associated with the tool usage or the assistant message.
                                    # Let's attach to the assistant message for now as that's where we added the column.
                                    if deep_search_updates_list and saved_msg:
                                        await loop.run_in_executor(
                                            None,
                                            lambda: ChatService._update_message_deep_search_logs(
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
                                        function_name, args_str
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
                        # Though we likely won't have > 3 tool calls in one turn usually.
                        # But slicing tasks[:3] handles "max 3 times" roughly per turn if they spammed it.
                        # Using gather calls them all.
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
                                lambda: ChatService._save_message_to_db(
                                    db, user_id, conversation_id, tool_msg
                                ),
                            )

                        # After tool execution loop (inside if tool_calls block)
                        # If images were generated, update the assistant message
                        if generated_images_list and saved_msg:
                            await loop.run_in_executor(
                                None,
                                lambda: ChatService._update_message_generated_images(
                                    db, saved_msg.id, generated_images_list
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
        ChatService._save_message_to_db(db, user_id, conversation_id, tool_msg)

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

        model_name, tools, level_think = ChatService._select_model(
            effective_query, None, conversation_id, db
        )
        system_prompt = ChatService._build_system_prompt(
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

    @staticmethod
    def _save_message_to_db(
        db: Session,
        user_id: int,
        conversation_id: int,
        msg: Dict[str, Any],
        embedding: Optional[List[float]] = None,
        generated_images: Optional[List[str]] = None,
        thinking: Optional[str] = None,
    ):
        """Helper to save a message to DB"""
        try:
            from app.services.embedding_service import EmbeddingService

            content = msg.get("content", "")
            role = msg.get("role", "assistant")
            tool_name = msg.get("tool_name") or msg.get("name")
            tool_call_id = msg.get("tool_call_id")
            tool_calls = msg.get("tool_calls")

            emb_json = None
            if embedding:
                emb_json = json.dumps(embedding)
            elif role in ["user", "assistant"] and content and len(content) > 10:
                try:
                    from app.services.embedding_service import EmbeddingService

                    emb = EmbeddingService.get_embedding(content)
                    emb_json = json.dumps(emb.tolist())
                except:
                    pass

            db_msg = ModelChatMessage(
                user_id=user_id,
                conversation_id=conversation_id,
                content=str(content),
                role=role,
                embedding=emb_json,
                tool_name=tool_name,
                tool_call_id=tool_call_id,
                tool_calls=json.dumps(tool_calls) if tool_calls else None,
                generated_images=(
                    json.dumps(generated_images) if generated_images else None
                ),
                thinking=thinking,
            )
            db.add(db_msg)
            db.commit()
            return db_msg
        except Exception as e:
            logger.error(f"Error saving message to DB: {e}")
            db.rollback()
            return None

    @staticmethod
    def _update_message_generated_images(
        db: Session, message_id: int, images: List[str]
    ):
        try:
            msg = (
                db.query(ModelChatMessage)
                .filter(ModelChatMessage.id == message_id)
                .first()
            )
            if msg:
                msg.generated_images = json.dumps(images)
                db.commit()
                logger.info(f"Updated message {message_id} with {len(images)} images")
        except Exception as e:
            logger.error(f"Error updating message images: {e}")

    @staticmethod
    def _update_message_deep_search_logs(db: Session, message_id: int, logs: List[str]):
        try:
            msg = (
                db.query(ModelChatMessage)
                .filter(ModelChatMessage.id == message_id)
                .first()
            )
            if msg:
                # Store cleaned logs or raw SSE strings?
                # Raw SSE strings are what UI expects in deepSearchUpdates list
                msg.deep_search_updates = json.dumps(logs)
                db.commit()
        except Exception as e:
            logger.error(f"Error updating deep search logs: {e}")

    @staticmethod
    def _update_merged_message(
        db: Session,
        message_id: int,
        new_msg_data: Dict[str, Any],
        thinking: Optional[str] = None,
    ) -> Optional[ModelChatMessage]:
        """
        Updates an existing assistant message by determining if we should append content
        (for multi-step tool use) or just update fields.
        """
        try:
            msg = (
                db.query(ModelChatMessage)
                .filter(ModelChatMessage.id == message_id)
                .first()
            )
            if not msg:
                return None

            # Append content if new content exists
            new_content = new_msg_data.get("content")
            if new_content:
                if msg.content:
                    msg.content += "\n" + new_content
                else:
                    msg.content = new_content

            # Append thinking if new thinking exists
            if thinking:
                if msg.thinking:
                    msg.thinking += "\n\n" + thinking
                else:
                    msg.thinking = thinking

            # Merge tool calls if new ones exist
            new_tool_calls = new_msg_data.get("tool_calls")
            if new_tool_calls:
                existing_calls = []
                if msg.tool_calls:
                    # Check type because it might be string or list/dict
                    if isinstance(msg.tool_calls, str):
                        try:
                            existing_calls = json.loads(msg.tool_calls)
                        except:
                            existing_calls = []
                    elif isinstance(msg.tool_calls, list):
                        existing_calls = msg.tool_calls

                # Append new calls
                if existing_calls is None:
                    existing_calls = []

                if isinstance(existing_calls, list):
                    # Dedup? No, usually distinct calls.
                    existing_calls.extend(new_tool_calls)
                    msg.tool_calls = json.dumps(existing_calls)  # Save as JSON string

            db.commit()
            db.refresh(msg)
            return msg
        except Exception as e:
            logger.error(f"Error merging message: {e}")
            return None
