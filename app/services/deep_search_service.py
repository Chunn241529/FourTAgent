import json
import logging
import ollama
import numpy as np
import faiss
import re
import gc
import asyncio
import os
from datetime import datetime
from typing import List, Dict, Any, AsyncGenerator
from rank_bm25 import BM25Okapi
from app.services.tool_service import ToolService
from app.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)


class DeepSearchService:
    def __init__(self):
        self.tool_service = ToolService()
        self.model_name = "Lumina-small"  # Correction: Default fast model
        self.reasoning_model = (
            "Lumina:latest"  # Correction: Smart model for planning/synthesis
        )

    async def execute_deep_search(
        self,
        topic: str,
        user_id: int,
        conversation_id: int,
        db: Any,
        is_autonomous: bool = False,
    ) -> AsyncGenerator[str, None]:
        """
        Executes the Deep Search flow using Broad Search -> RAG Rerank -> Plan -> Execute. (Async)
        Args:
            topic: The search topic
            user_id: User ID
            conversation_id: Conversation ID
            db: Database session
            is_autonomous: If True, indicates this was triggered by an LLM tool call, so we skip saving the User message (Topic) again.
        """
        from app.models import (
            ChatMessage as ModelChatMessage,
            Conversation as ModelConversation,
        )
        from app.services.rag_service import RAGService
        from app.services.conversation_summary_service import ConversationSummaryService
        from app.services.chat_service import ChatService
        from app.services.chat import memory

        client = ollama.AsyncClient()

        # 1. Get History Context
        # data access should be in executor if blocking
        loop = asyncio.get_running_loop()
        summary, semantic_messages, working_memory = await loop.run_in_executor(
            None,
            lambda: memory.get_hierarchical_memory(
                db, conversation_id, current_query=topic, user_id=user_id
            ),
        )

        history_context = ""
        if summary:
            history_context += f"Conversation Summary:\n{summary}\n\n"

        # Add Semantic Memory to context
        if semantic_messages:
            history_context += "Relevant Past Details:\n"
            for msg in semantic_messages:
                history_context += f"- {msg.role}: {msg.content}\n"
            history_context += "\n"

        if working_memory:
            history_context += "Recent Messages:\n"
            for msg in working_memory:
                history_context += f"- {msg.role}: {msg.content}\n"

        # Track artifacts for saving history
        collected_plan = ""
        collected_thinking = ""
        collected_updates = []

        # 2. Generate Broad Queries
        update_msg = "Generating search strategy..."
        collected_updates.append(update_msg)
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': update_msg}}, separators=(',', ':'))}\n\n"
        queries = await self._generate_multi_queries(topic, history_context, client)

        # Emit generated queries
        yield f"data: {json.dumps({'deep_search_data': {'step': 'planning', 'type': 'queries', 'data': queries}}, separators=(',', ':'))}\n\n"

        # 3. Execute Broad Search
        update_msg = "Researching..."
        collected_updates.append(update_msg)
        yield f"data: {json.dumps({'deep_search_update': {'status': 'searching', 'message': update_msg}}, separators=(',', ':'))}\n\n"

        all_results = []
        for i, query in enumerate(queries):
            logger.info(f"Searching ({i+1}/{len(queries)}): {query}")

            # Emit search start
            yield f"data: {json.dumps({'search_started': {'query': query}}, separators=(',', ':'))}\n\n"

            # Offload blocking DDGS search to thread
            results = await loop.run_in_executor(None, self._web_search_results, query)
            all_results.extend(results)

            # Emit search complete
            yield f"data: {json.dumps({'search_complete': {'query': query, 'result_count': len(results)}}, separators=(',', ':'))}\n\n"
            await asyncio.sleep(0.1)  # Brief pause for UI update

        # Emit all search results (titles/urls)
        search_data = []
        for r in all_results:
            # Extract title/url from snippet string if possible, or just send raw snippets?
            # _web_search_results returns strings: "Title: ...\nURL: ...\nContent: ..."
            # Let's try to parse it for cleaner UI
            lines = r.split("\n")
            title = next(
                (l.split("Title: ")[1] for l in lines if l.startswith("Title: ")),
                "Unknown",
            )
            url = next(
                (l.split("URL: ")[1] for l in lines if l.startswith("URL: ")), "#"
            )
            search_data.append({"title": title, "url": url})

        yield f"data: {json.dumps({'deep_search_data': {'step': 'searching', 'type': 'results', 'data': search_data}}, separators=(',', ':'))}\n\n"

        # 4. RAG Reranking
        update_msg = "Analyzing and verifying specific details..."
        collected_updates.append(update_msg)
        yield f"data: {json.dumps({'deep_search_update': {'status': 'reflecting', 'message': update_msg}}, separators=(',', ':'))}\n\n"
        # Offload FAISS/BM25 rerank to thread
        top_results = await loop.run_in_executor(
            None, lambda: self._rerank_results(topic, all_results, top_k=6)
        )

        # Emit relevant sources
        relevant_data = []
        for r in top_results:
            lines = r.split("\n")
            title = next(
                (l.split("Title: ")[1] for l in lines if l.startswith("Title: ")),
                "Unknown",
            )
            url = next(
                (l.split("URL: ")[1] for l in lines if l.startswith("URL: ")), "#"
            )
            relevant_data.append({"title": title, "url": url})

        yield f"data: {json.dumps({'deep_search_data': {'step': 'reflecting', 'type': 'sources', 'data': relevant_data}}, separators=(',', ':'))}\n\n"

        del all_results
        gc.collect()

        # 5. Plan Report
        update_msg = "Creating research plan..."
        collected_updates.append(update_msg)
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': update_msg}}, separators=(',', ':'))}\n\n"
        combined_context = "\n\n".join(top_results)
        report_plan = await self._generate_report_plan(topic, combined_context, client)
        collected_plan = report_plan

        yield f"data: {json.dumps({'plan': report_plan}, separators=(',', ':'))}\n\n"
        # Also emit as data for the step
        yield f"data: {json.dumps({'deep_search_data': {'step': 'planning_create', 'type': 'plan', 'data': report_plan}}, separators=(',', ':'))}\n\n"

        gc.collect()

        # 6. Final Synthesis
        update_msg = "Synthesizing answer..."
        collected_updates.append(update_msg)
        yield f"data: {json.dumps({'deep_search_update': {'status': 'synthesizing', 'message': update_msg}}, separators=(',', ':'))}\n\n"

        final_report = ""
        async for sse_chunk in self._final_synthesis(
            topic, report_plan, combined_context, client
        ):
            yield sse_chunk
            try:
                if sse_chunk.startswith("data: "):
                    chunk_json = json.loads(sse_chunk[6:].strip())

                    # Collect thinking
                    if "thinking" in chunk_json:
                        collected_thinking += chunk_json["thinking"]

                    if "message" in chunk_json and "content" in chunk_json["message"]:
                        content_delta = chunk_json["message"].get("content", "")
                        if content_delta:
                            final_report += content_delta
            except:
                pass

        del combined_context, top_results
        gc.collect()

        # End of message stream
        yield f"data: {json.dumps({'done': True}, separators=(',', ':'))}\n\n"

        # --- SAVE HISTORY ---
        def save_history():
            try:
                # Save User Message (Topic) - ONLY if not autonomous (Slash Command)
                # If autonomous, the user message already exists and triggered the tool
                user_msg = None
                if not is_autonomous:
                    query_emb = EmbeddingService.get_embedding(topic)
                    user_msg = ModelChatMessage(
                        user_id=user_id,
                        conversation_id=conversation_id,
                        content=topic,
                        role="user",
                        embedding=json.dumps(query_emb.tolist()),
                    )
                    db.add(user_msg)

                # Save Tool Message (Plan & Sources) for context
                # This ensures the LLM knows WHERE the info came from in future turns
                sources_text = "\n".join(
                    [f"- [{d['title']}]({d['url']})" for d in relevant_data]
                )
                tool_content = f"**Research Plan:**\n{collected_plan}\n\n**Verified Sources:**\n{sources_text}"

                tool_msg = ModelChatMessage(
                    user_id=user_id,
                    conversation_id=conversation_id,
                    content=tool_content,
                    role="tool",
                    tool_name="deep_search",
                    tool_call_id="call_"
                    + datetime.now().strftime("%Y%m%d%H%M%S"),  # Dummy ID
                    embedding=None,  # Context message, embedding optional/skipped for now
                )
                db.add(tool_msg)

                # Save Assistant Message (Report)
                ass_emb = EmbeddingService.get_embedding(final_report)

                # Check for existing deep search updates to assume start index
                # Ideally, if we have thinking, we should check when deep search started?
                # For now, let's just save the raw data.

                ass_msg = ModelChatMessage(
                    user_id=user_id,
                    conversation_id=conversation_id,
                    content=final_report,
                    role="assistant",
                    embedding=json.dumps(ass_emb.tolist()),
                    thinking=collected_thinking if collected_thinking else None,
                    deep_search_updates=(
                        json.dumps(collected_updates) if collected_updates else None
                    ),
                    # We can store plan in 'deep_search_updates' or maybe specific field if we migrate DB
                    # But ChatMessage doesn't have 'plan' field yet in `app/models.py`?
                    # Let's check `app/models.py`. It does NOT have 'plan'.
                    # So we should append plan to thinking or content?
                    # Or serialize it into deep_search_updates?
                    # Re-checking model: It supports `deep_search_updates`.
                    # Let's stash the plan as a special entry in updates or just pre-pend to content?
                    # Better: The frontend expects 'plan' field in Message model, but backend ModelChatMessage might not have it.
                    # Wait, looking at `app/models.py` in previous turn:
                    # `deep_search_updates = Column(JSON, nullable=True)`
                    # `thinking = Column(String, nullable=True)`
                    # It DOES NOT have `plan`.
                    # We should probably add `plan` column OR store it in `deep_search_updates` as a special object?
                    # But `deep_search_updates` is usually List[String].
                    # Let's just append plan to the beginning of thinking with a marker? OR rely on frontend to parse it?
                    # Actually, let's just add it to `thinking` with a marker if we can't change schema.
                    # OR, we format `thinking` nicely: "PLAN:\n...\n\nTHINKING:\n..."
                )

                # Adding plan to thinking for now since schema mod is risky in hotfix
                if collected_plan:
                    if ass_msg.thinking:
                        ass_msg.thinking = (
                            f"PLAN:\n{collected_plan}\n\n{ass_msg.thinking}"
                        )
                    else:
                        ass_msg.thinking = f"PLAN:\n{collected_plan}"

                db.add(ass_msg)
                db.commit()

                RAGService.update_faiss_index(user_id, conversation_id, db)

                if ConversationSummaryService.should_update_summary(
                    conversation_id, db
                ):
                    new_summary = ConversationSummaryService.update_summary_incremental(
                        conversation_id, [user_msg, ass_msg], db
                    )
                    conv = db.query(ModelConversation).get(conversation_id)
                    conv.summary = new_summary
                    db.commit()

                logger.info("Deep Search history saved successfully")
            except Exception as e:
                logger.error(f"Error saving Deep Search history: {e}")
                db.rollback()

        await loop.run_in_executor(None, save_history)
        yield f"data: {json.dumps({'done': True})}\n\n"

    async def _generate_multi_queries(
        self, topic: str, history_context: str, client: ollama.AsyncClient
    ) -> List[str]:
        system_prompt = "Bạn là Chuyên gia Nghiên cứu (Senior Research Analyst). Nhiệm vụ là phân tích yêu cầu và tạo 4 truy vấn tìm kiếm tối ưu, khai thác sâu chủ đề."
        prompt = f"""
        Topic: {topic}
        Context:
        {history_context}

        Tạo 4 truy vấn tìm kiếm (Search Queries) để nghiên cứu toàn diện chủ đề này.
        
        **QUY TẮC NGÔN NGỮ (QUAN TRỌNG)**:
        - Kỹ thuật, Lập trình, Khoa học, Quốc tế -> Dùng **TIẾNG ANH**.
        - Tin tức VN, Pháp luật, Địa danh, Văn hóa VN -> Dùng **TIẾNG VIỆT**.
        - Nếu chủ đề rộng -> Kết hợp 2 Tiếng Anh, 2 Tiếng Việt.
        
        **CẤU TRÚC PHÂN TÍCH**:
        1. Query 1: Khái niệm cốt lõi / Definitional (Tìm hiểu bản chất)
        2. Query 2: Chi tiết kỹ thuật / Technical Specs (Đi sâu vào thành phần)
        3. Query 3: So sánh & Đánh giá / Comparative (So với đối thủ/giải pháp khác)
        4. Query 4: Ứng dụng & Thực tiễn / Use-cases (Ví dụ thực tế/Tutorial)
        
        Yêu cầu:
        - Truy vấn ngắn gọn, chứa từ khóa trọng tâm (Keywords).
        - KHÔNG đánh số thứ tự đầu dòng.
        - Trả về đúng 4 dòng.
        """
        response = await client.chat(
            model=self.model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            options={"temperature": 0.3},
        )
        content = response["message"]["content"]
        queries = [
            line.strip("- *1234.") for line in content.split("\n") if line.strip()
        ]
        return queries[:4]

    async def _generate_report_plan(
        self, topic: str, context: str, client: ollama.AsyncClient
    ) -> str:
        system_prompt = "Bạn là Trợ lý Tổng hợp Thông tin Chiến lược. Nhiệm vụ là lập dàn ý chi tiết để trả lời người dùng dựa trên dữ liệu đã thu thập."
        prompt = f"""
        Topic: {topic}
        
        Research Context (Dữ liệu đã tìm được):
        {context[:8000]}...
        
        Hãy lập dàn ý (Plan) để viết câu trả lời cuối cùng.
        Dàn ý cần logic, chặt chẽ, đi thẳng vào vấn đề người dùng hỏi.
        
        Cấu trúc gợi ý:
        1. **Tóm tắt/Câu trả lời trực tiếp**: Trả lời ngay câu hỏi của user.
        2. **Phân tích chi tiết**: Các điểm chính rút ra từ Research Context.
        3. **Số liệu/Dẫn chứng**: Nếu có trong context.
        4. **Kết luận/Lời khuyên hành động**.

        Yêu cầu:
        - Viết bằng Tiếng Việt.
        - Dùng gạch đầu dòng (-). KHÔNG dùng checkbox.
        - Ngắn gọn, rõ ràng.
        """
        response = await client.chat(
            model=self.model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            options={"temperature": 0.3},
        )
        return response["message"]["content"]

    def _web_search_results(self, query: str) -> List[str]:
        try:
            from ddgs import DDGS

            snippets = []
            with DDGS() as ddg_client:
                results = ddg_client.text(query, max_results=5)
                for item in results:
                    snippets.append(
                        f"Title: {item.get('title')}\nURL: {item.get('href')}\nContent: {item.get('body')}"
                    )
            return snippets
        except Exception as e:
            logger.error(f"Search error: {e}")
            return []

    def _rerank_results(
        self, topic: str, results: List[str], top_k: int = 10
    ) -> List[str]:
        if not results:
            return []
        try:
            unique_results = list(set(results))
            if not unique_results:
                return []

            tokenized_corpus = [
                re.findall(r"\w+", doc.lower()) for doc in unique_results
            ]
            bm25 = BM25Okapi(tokenized_corpus)
            query_tokens = re.findall(r"\w+", topic.lower())
            bm25_scores = bm25.get_scores(query_tokens)

            embeddings = EmbeddingService.get_embeddings_batch(unique_results)
            valid_embs = [e for e in embeddings if np.any(e)]
            if not valid_embs:
                return unique_results[:top_k]

            emb_array = np.array(valid_embs).astype("float32")
            faiss.normalize_L2(emb_array)
            index = faiss.IndexFlatIP(EmbeddingService.DIM)
            index.add(emb_array)

            query_emb = EmbeddingService.get_embedding(topic)
            query_emb = query_emb.astype("float32").reshape(1, -1)
            faiss.normalize_L2(query_emb)

            search_k = min(len(unique_results), index.ntotal)
            D, I = index.search(query_emb, k=search_k)
            faiss_scores_map = {idx: score for score, idx in zip(D[0], I[0])}

            hybrid_scores = []
            for i in range(len(unique_results)):
                bm25_score = bm25_scores[i]
                faiss_score = faiss_scores_map.get(i, 0)
                norm_bm25 = min(bm25_score / 20.0, 1.0)
                final_score = 0.6 * faiss_score + 0.4 * norm_bm25
                hybrid_scores.append((final_score, unique_results[i]))

            hybrid_scores.sort(key=lambda x: x[0], reverse=True)
            return [item[1] for item in hybrid_scores[:top_k]]
        except Exception as e:
            logger.error(f"Rerank error: {e}")
            return results[:top_k]

    async def _final_synthesis(
        self, topic: str, plan: str, context: str, client: ollama.AsyncClient
    ) -> AsyncGenerator[str, None]:
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        system_prompt = f"""Bạn là Nhi - một AI thông minh, thân thiện và bao quát.
        KHÔNG ĐƯỢC tự giới thiệu lại ("Chào bạn, mình là Nhi..."). Hãy bắt đầu phần tổng hợp ngay.
        Dùng tiếng Việt.
        Thời gian: {current_time}"""
        prompt = f"""
        Topic: {topic}
        
        PLAN:
        {plan}
        
        INSTRUCTIONS:
        Using the Research Context below, write the final detailed response.
        - Answer the user's request naturally and comprehensively.
        - Use Markdown for formatting (headers, lists, code blocks).
        - Ensure smooth transitions between sections.

        Research Context:
        {context[:15000]}
        """
        stream = await client.chat(
            model=self.reasoning_model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            stream=True,
        )

        async for chunk in stream:
            chunk_data = chunk.model_dump() if hasattr(chunk, "model_dump") else chunk
            msg = chunk_data.get("message", {})

            if "reasoning_content" in msg and msg["reasoning_content"]:
                yield f"data: {json.dumps({'thinking': msg['reasoning_content']}, separators=(',', ':'))}\n\n"
            elif "think" in msg and msg["think"]:
                yield f"data: {json.dumps({'thinking': msg['think']}, separators=(',', ':'))}\n\n"

            yield f"data: {json.dumps(chunk_data, separators=(',', ':'))}\n\n"
