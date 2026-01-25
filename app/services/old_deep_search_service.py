import json
import logging
import ollama
import numpy as np
import faiss
import re
import gc
from datetime import datetime
from typing import List, Dict, Any, Generator
from rank_bm25 import BM25Okapi
from app.services.tool_service import ToolService
from app.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)


class DeepSearchService:
    def __init__(self):
        self.tool_service = ToolService()
        self.model_name = "Lumina:latest"  # Default fast model
        self.reasoning_model = "Lumina:latest"  # Smart model for planning/synthesis

    def execute_deep_search(
        self, topic: str, user_id: int, conversation_id: int, db: Any
    ) -> Generator[str, None, None]:
        """
        Executes the Deep Search flow using Broad Search -> RAG Rerank -> Plan -> Execute.
        """
        from app.models import (
            ChatMessage as ModelChatMessage,
            Conversation as ModelConversation,
        )
        from app.services.rag_service import RAGService
        from app.services.conversation_summary_service import ConversationSummaryService
        from app.services.chat_service import ChatService

        # yield f"data: {json.dumps({'deep_search_update': {'status': 'started', 'message': f'Starting Deep Search for: {topic}'}}, separators=(',', ':'))}\n\n"

        # 1. Get History Context
        summary, _, working_memory = ChatService._get_hierarchical_memory(
            db, conversation_id, current_query=topic, user_id=user_id
        )

        history_context = ""
        if summary:
            history_context += f"Conversation Summary:\n{summary}\n\n"
        if working_memory:
            history_context += "Recent Messages:\n"
            for msg in working_memory:
                history_context += f"- {msg.role}: {msg.content}\n"

        # 2. Generate Broad Queries
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': 'Generating search strategy...'}}, separators=(',', ':'))}\n\n"
        queries = self._generate_multi_queries(topic, history_context)

        # 3. Execute Broad Search
        yield f"data: {json.dumps({'deep_search_update': {'status': 'searching', 'message': f'Researching...'}}, separators=(',', ':'))}\n\n"

        all_results = []
        for i, query in enumerate(queries):
            # Log internally but don't spam UI
            logger.info(f"Searching ({i+1}/{len(queries)}): {query}")
            results = self._web_search_results(query)
            all_results.extend(results)

        # 4. RAG Reranking
        yield f"data: {json.dumps({'deep_search_update': {'status': 'reflecting', 'message': 'Analyzing and verifying specific details...'}}, separators=(',', ':'))}\n\n"
        top_results = self._rerank_results(topic, all_results, top_k=6)

        # Memory cleanup after search/rerank
        del all_results
        gc.collect()

        # 5. Plan Report
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': 'Creating research plan...'}}, separators=(',', ':'))}\n\n"
        combined_context = "\n\n".join(top_results)
        report_plan = self._generate_report_plan(topic, combined_context)

        # Stream the plan as a dedicated event (for PlanIndicator widget)
        yield f"data: {json.dumps({'plan': report_plan}, separators=(',', ':'))}\n\n"

        # Memory cleanup after plan generation
        gc.collect()

        # 6. Final Synthesis - yields SSE strings directly like chat_service
        yield f"data: {json.dumps({'deep_search_update': {'status': 'synthesizing', 'message': 'Synthesizing answer...'}}, separators=(',', ':'))}\n\n"

        final_report = ""
        for sse_chunk in self._final_synthesis(topic, report_plan, combined_context):
            yield sse_chunk
            # Accumulate content for DB save
            try:
                # Parse the SSE chunk to extract content
                if sse_chunk.startswith("data: "):
                    chunk_json = json.loads(sse_chunk[6:].strip())
                    if "message" in chunk_json and "content" in chunk_json["message"]:
                        content_delta = chunk_json["message"].get("content", "")
                        if content_delta:
                            final_report += content_delta
            except:
                pass

        # Memory cleanup after synthesis
        del combined_context, top_results
        gc.collect()

        # End of message stream
        yield f"data: {json.dumps({'done': True}, separators=(',', ':'))}\n\n"

        # --- SAVE HISTORY ---
        try:
            # Save User Message (Topic)
            query_emb = EmbeddingService.get_embedding(topic)
            user_msg = ModelChatMessage(
                user_id=user_id,
                conversation_id=conversation_id,
                content=topic,
                role="user",
                embedding=json.dumps(query_emb.tolist()),
            )
            db.add(user_msg)

            # Save Assistant Message (Report)
            ass_emb = EmbeddingService.get_embedding(final_report)
            ass_msg = ModelChatMessage(
                user_id=user_id,
                conversation_id=conversation_id,
                content=final_report,
                role="assistant",
                embedding=json.dumps(ass_emb.tolist()),
            )
            db.add(ass_msg)
            db.commit()  # Commit to get IDs

            # Update FAISS
            RAGService.update_faiss_index(user_id, conversation_id, db)

            # Update Summary
            if ConversationSummaryService.should_update_summary(conversation_id, db):
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

        yield f"data: {json.dumps({'done': True})}\n\n"

    def _generate_multi_queries(self, topic: str, history_context: str) -> List[str]:
        system_prompt = "You are a search expert. Generate 4 distinct search queries (English or Vietnamese based on topic) to research the topic comprehensively."
        prompt = f"""
        Topic: {topic}
        Context:
        {history_context}

        Generate 4 search queries.
        
        **LANGUAGE RULE**:
        - Use **ENGLISH** for Technical topics (Coding, Science, Global Tech), International News, or General Knowledge.
        - Use **VIETNAMESE** for Vietnam-specific topics (Local News, Laws, Culture, Locations).
        - If uncertain, mix both.
        
        Structure:
        1. Basic concept/definition (Concise)
        2. Key features/components (Comprehensive)
        3. Advanced/Technical details (Specific)
        4. Current trends/comparisons (Up-to-date)

        Ensure queries are concise (Keywords preferred).
        Return ONLY the list of 4 queries, one per line. No numbering.
        """
        response = ollama.chat(
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

    def _generate_report_plan(self, topic: str, context: str) -> str:
        system_prompt = (
            "You are a helpful assistant. Create a momentary plan to answer the user."
        )
        prompt = f"""
        Topic: {topic}
        Context (Abstract):
        {context[:5000]}...
        
        Briefly outline how you will answer this request based on the context.
        Keep it simple and direct. No complex markdown checklists.
        """
        response = ollama.chat(
            model=self.model_name,  # Use FAST model (Lumina:latest) instead of Reasoning
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            options={"temperature": 0.3},
        )
        return response["message"]["content"]

    def _web_search_results(self, query: str) -> List[str]:
        """
        Returns raw list of result strings.
        """
        try:
            import ddgs

            # Optimization: Trust the generator to provide good queries.
            # Skip the redundant LLM call to "optimize" the query again.
            # This reduces latency and keeps the "Fast Model" usage to a minimum.
            english_query = query

            # Simple fallback: if query somehow has Vietnamese (unlikely if generator works), leave it.
            # DDGS handles language reasonably well, but we prefer English for technical topics.

            snippets = []
            with ddgs.DDGS() as ddg_client:
                results = ddg_client.text(
                    english_query, max_results=5
                )  # 5 results per query
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
        """
        Reranks results using Hybrid Search (FAISS + BM25).
        """
        if not results:
            return []

        try:
            # 1. Prepare Data
            unique_results = list(set(results))  # Deduplicate
            if not unique_results:
                return []

            # 2. BM25 Scores
            tokenized_corpus = [
                re.findall(r"\w+", doc.lower()) for doc in unique_results
            ]
            bm25 = BM25Okapi(tokenized_corpus)
            query_tokens = re.findall(r"\w+", topic.lower())
            bm25_scores = bm25.get_scores(query_tokens)

            # 3. FAISS Scores
            embeddings = EmbeddingService.get_embeddings_batch(unique_results)
            valid_embs = [e for e in embeddings if np.any(e)]

            if not valid_embs:
                return unique_results[:top_k]  # Fallback

            emb_array = np.array(valid_embs).astype("float32")
            faiss.normalize_L2(emb_array)

            index = faiss.IndexFlatIP(EmbeddingService.DIM)
            index.add(emb_array)

            query_emb = EmbeddingService.get_embedding(topic)
            query_emb = query_emb.astype("float32").reshape(1, -1)
            faiss.normalize_L2(query_emb)

            # Fix: Ensure k does not exceed availability in index
            search_k = min(len(unique_results), index.ntotal)
            D, I = index.search(query_emb, k=search_k)
            faiss_scores_map = {idx: score for score, idx in zip(D[0], I[0])}

            # 4. Hybrid Score
            hybrid_scores = []
            for i in range(len(unique_results)):
                # Normalize BM25 (simple min-max or just scaling)
                # BM25 scores can be large, so we scale them down roughly
                bm25_score = bm25_scores[i]
                faiss_score = faiss_scores_map.get(i, 0)

                # Simple normalization for BM25 to 0-1 range roughly
                # Assuming max bm25 score is around 20-30 usually
                norm_bm25 = min(bm25_score / 20.0, 1.0)

                # Weighted sum: 0.6 Vector + 0.4 Keyword
                final_score = 0.6 * faiss_score + 0.4 * norm_bm25
                hybrid_scores.append((final_score, unique_results[i]))

            # 5. Sort and Select
            hybrid_scores.sort(key=lambda x: x[0], reverse=True)
            return [item[1] for item in hybrid_scores[:top_k]]

        except Exception as e:
            logger.error(f"Rerank error: {e}")
            return results[:top_k]  # Fallback

    def _final_synthesis(
        self, topic: str, plan: str, context: str
    ) -> Generator[Dict[str, str], None, None]:
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
        - The Plan is for your internal guidance, but you can follow its flow.
        - Answer the user's request naturally and comprehensively.
        - Use Markdown for formatting (headers, lists, code blocks).
        - Ensure smooth transitions between sections.

        Research Context:
        {context[:15000]}
        """
        stream = ollama.chat(
            model=self.reasoning_model,  # Use reasoning model for final synthesis
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            stream=True,
        )

        for chunk in stream:
            # Convert ChatResponse to dict if needed (same as chat_service)
            chunk_data = chunk.model_dump() if hasattr(chunk, "model_dump") else chunk
            msg = chunk_data.get("message", {})

            # Handle thinking/reasoning content (same extraction as chat_service lines 669-691)
            if "reasoning_content" in msg and msg["reasoning_content"]:
                yield f"data: {json.dumps({'thinking': msg['reasoning_content']}, separators=(',', ':'))}\n\n"
            elif "think" in msg and msg["think"]:
                yield f"data: {json.dumps({'thinking': msg['think']}, separators=(',', ':'))}\n\n"
            elif "reasoning" in msg and msg["reasoning"]:
                yield f"data: {json.dumps({'thinking': msg['reasoning']}, separators=(',', ':'))}\n\n"
            elif "thought" in msg and msg["thought"]:
                yield f"data: {json.dumps({'thinking': msg['thought']}, separators=(',', ':'))}\n\n"

            # Check top-level chunk for thinking (some models)
            if "reasoning_content" in chunk_data and chunk_data["reasoning_content"]:
                yield f"data: {json.dumps({'thinking': chunk_data['reasoning_content']}, separators=(',', ':'))}\n\n"
            elif "think" in chunk_data and chunk_data["think"]:
                yield f"data: {json.dumps({'thinking': chunk_data['think']}, separators=(',', ':'))}\n\n"

            # Stream the raw chunk (same as chat_service line 701)
            yield f"data: {json.dumps(chunk_data, separators=(',', ':'))}\n\n"
