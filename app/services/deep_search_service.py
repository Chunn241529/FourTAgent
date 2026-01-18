import json
import logging
import ollama
import numpy as np
import faiss
import re
from datetime import datetime
from typing import List, Dict, Any, Generator
from rank_bm25 import BM25Okapi
from app.services.tool_service import ToolService
from app.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)


class DeepSearchService:
    def __init__(self):
        self.tool_service = ToolService()
        self.model_name = "4T-S"  # Or any capable model

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

        yield f"data: {json.dumps({'deep_search_update': {'status': 'started', 'message': f'Starting Deep Search for: {topic}'}})}\n\n"

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
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': 'Generating broad search queries...'}})}\n\n"
        queries = self._generate_multi_queries(topic, history_context)

        queries_str = "\n".join([f"- {q}" for q in queries])
        logger.info(f"Generated Queries:\n{queries_str}")
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': f'Generated {len(queries)} queries.'}})}\n\n"

        # 3. Execute Broad Search
        all_results = []
        for i, query in enumerate(queries):
            yield f"data: {json.dumps({'deep_search_update': {'status': 'searching', 'message': f'Searching ({i+1}/{len(queries)}): {query}'}})}\n\n"
            results = self._web_search_results(query)
            all_results.extend(results)

        yield f"data: {json.dumps({'deep_search_update': {'status': 'processing', 'message': f'Collected {len(all_results)} raw results.'}})}\n\n"

        # 4. RAG Reranking
        yield f"data: {json.dumps({'deep_search_update': {'status': 'reflecting', 'message': 'Reranking results using Hybrid Search...'}})}\n\n"
        top_results = self._rerank_results(topic, all_results)

        yield f"data: {json.dumps({'deep_search_update': {'status': 'processing', 'message': f'Selected top {len(top_results)} most relevant results.'}})}\n\n"

        # 5. Plan Report
        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': 'Creating structured report plan...'}})}\n\n"
        combined_context = "\n\n".join(top_results)
        report_plan = self._generate_report_plan(topic, combined_context)

        yield f"data: {json.dumps({'deep_search_update': {'status': 'planning', 'message': 'Report plan created.'}})}\n\n"

        # 6. Final Synthesis
        yield f"data: {json.dumps({'deep_search_update': {'status': 'synthesizing', 'message': 'Generating final report...'}})}\n\n"

        final_report = ""
        for chunk in self._final_synthesis(topic, report_plan, combined_context):
            final_report += chunk
            yield f"data: {json.dumps({'message': {'content': chunk}})}\n\n"

        # End of message stream
        yield f"data: {json.dumps({'message': {'content': ''}})}\n\n"

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
        system_prompt = "You are a search expert. Generate 4 distinct search queries in English (Basic -> Advanced) to research the topic comprehensively."
        prompt = f"""
        Topic: {topic}
        Context:
        {history_context}

        Generate 4 search queries in English:
        1. Basic concept/definition (Concise)
        2. Key features/components (Comprehensive)
        3. Advanced/Technical details (Specific)
        4. Current trends/comparisons (Up-to-date)

        Ensure queries are concise but cover the necessary depth.
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

    def _web_search_results(self, query: str) -> List[str]:
        """
        Returns raw list of result strings.
        """
        try:
            import ddgs

            # Optimize query to concise English keywords
            has_vietnamese = any(ord(c) > 127 for c in query)
            english_query = query

            if has_vietnamese:
                try:
                    # Convert Vietnamese to concise English search query
                    translate_response = ollama.chat(
                        model=self.model_name,
                        messages=[
                            {
                                "role": "user",
                                "content": f"Convert this Vietnamese query to a concise English search query. Use keywords and important phrases only. Output ONLY the English query, no explanations:\n\n{query}",
                            }
                        ],
                        options={"temperature": 0.1},
                    )
                    english_query = (
                        translate_response["message"]["content"].strip().strip('"')
                    )
                    logger.info(f"Optimized query: {query} -> {english_query}")
                except Exception as e:
                    logger.warning(f"Query optimization failed: {e}")
            else:
                # For English queries, still optimize to make them concise
                try:
                    optimize_response = ollama.chat(
                        model=self.model_name,
                        messages=[
                            {
                                "role": "user",
                                "content": f"Convert this to a concise search query. Use keywords and important phrases only. Output ONLY the optimized query, no explanations:\n\n{query}",
                            }
                        ],
                        options={"temperature": 0.1},
                    )
                    english_query = (
                        optimize_response["message"]["content"].strip().strip('"')
                    )
                    logger.info(f"Optimized query: {query} -> {english_query}")
                except Exception as e:
                    logger.warning(f"Query optimization failed: {e}")

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

            D, I = index.search(query_emb, k=len(unique_results))
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

    def _generate_report_plan(self, topic: str, context: str) -> str:
        system_prompt = "You are a strategic report planner. Create a structured implementation plan for the report."
        prompt = f"""
        Topic: {topic}
        Research Context:
        {context[:10000]}

        Create a structured plan for the final report. The plan MUST include:
        1. **Report Goal**: A brief statement of what this report aims to achieve.
        2. **Target Audience**: Who is this report for?
        3. **Key Insights to Highlight**: List 3-5 specific findings from the context that are crucial.
        4. **Structure & Content**: A detailed outline of sections and subsections.

        Format the output clearly using Markdown.
        """
        response = ollama.chat(
            model=self.model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            options={"temperature": 0.3},
        )
        return response["message"]["content"]

    def _final_synthesis(
        self, topic: str, plan: str, context: str
    ) -> Generator[str, None, None]:
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        system_prompt = f"""Bạn là Nhi - một AI nói chuyện tự nhiên như con người, rất thông minh, trẻ con, dí dỏm và thân thiện.
        Bạn tự xưng Nhi..
        Dùng tiếng Việt để trả lời.
        Thời gian hiện tại: {current_time}"""
        prompt = f"""
        Topic: {topic}
        Plan:
        {plan}
        
        Hãy tổng hợp lại thông tin từ Research Context và Plan để tạo ra một câu trả lời chi tiết.

        Research Context:
        {context[:15000]} # Larger context window
        """
        stream = ollama.chat(
            model=self.model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt},
            ],
            stream=True,
        )

        for chunk in stream:
            if "message" in chunk and "content" in chunk["message"]:
                yield chunk["message"]["content"]
