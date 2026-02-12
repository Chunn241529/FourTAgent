import faiss
import numpy as np
import json
import os
import re
import glob
from typing import List, Dict, Any, Tuple, Optional
import logging
from concurrent.futures import ThreadPoolExecutor
from rank_bm25 import BM25Okapi
from sqlalchemy.orm import Session

from app.services.embedding_service import EmbeddingService
from app.services.file_service import FileService
from app.models import ChatMessage as ModelChatMessage

logger = logging.getLogger(__name__)
executor = ThreadPoolExecutor(max_workers=4)

RAG_FILES_DIR = "rag_files"
os.makedirs(RAG_FILES_DIR, exist_ok=True)


class RAGService:
    rag_files_dir = RAG_FILES_DIR

    # Global File Index (In-Memory)
    _global_index = None
    _global_files: List[Dict[str, Any]] = []
    _global_index_lock = False

    @staticmethod
    def _build_global_index():
        """Build global index of all available RAG files for quick retrieval"""
        if RAGService._global_index_lock:
            return

        RAGService._global_index_lock = True
        try:
            logger.info("Building global RAG file index...")
            rag_files = []

            # Supported patterns (same as before)
            supported_patterns = [
                os.path.join(RAG_FILES_DIR, "*.pdf"),
                os.path.join(RAG_FILES_DIR, "*.txt"),
                os.path.join(RAG_FILES_DIR, "*.docx"),
                os.path.join(RAG_FILES_DIR, "*.xlsx"),
                os.path.join(RAG_FILES_DIR, "*.xls"),
                os.path.join(RAG_FILES_DIR, "*.csv"),
                os.path.join(RAG_FILES_DIR, "*.parquet"),
                os.path.join(RAG_FILES_DIR, "*.md"),
                os.path.join(RAG_FILES_DIR, "*.py"),
                os.path.join(RAG_FILES_DIR, "*.js"),
                os.path.join(RAG_FILES_DIR, "*.java"),
                os.path.join(RAG_FILES_DIR, "*.cpp"),
                os.path.join(RAG_FILES_DIR, "*.h"),
                os.path.join(RAG_FILES_DIR, "*.c"),
                os.path.join(RAG_FILES_DIR, "*.cs"),
                os.path.join(RAG_FILES_DIR, "*.go"),
                os.path.join(RAG_FILES_DIR, "*.rs"),
                os.path.join(RAG_FILES_DIR, "*.php"),
                os.path.join(RAG_FILES_DIR, "*.rb"),
                os.path.join(RAG_FILES_DIR, "*.swift"),
                os.path.join(RAG_FILES_DIR, "*.kt"),
                os.path.join(RAG_FILES_DIR, "*.ts"),
                os.path.join(RAG_FILES_DIR, "*.tsx"),
                os.path.join(RAG_FILES_DIR, "*.jsx"),
                os.path.join(RAG_FILES_DIR, "*.vue"),
                os.path.join(RAG_FILES_DIR, "*.html"),
                os.path.join(RAG_FILES_DIR, "*.css"),
                os.path.join(RAG_FILES_DIR, "*.json"),
                os.path.join(RAG_FILES_DIR, "*.yaml"),
                os.path.join(RAG_FILES_DIR, "*.yml"),
                os.path.join(RAG_FILES_DIR, "*.sh"),
                os.path.join(RAG_FILES_DIR, "*.sql"),
            ]

            for pattern in supported_patterns:
                rag_files.extend(glob.glob(pattern))

            if not rag_files:
                logger.info("No files found to index.")
                RAGService._global_files = []
                RAGService._global_index = None
                return

            embeddings = []
            valid_files = []

            for file_path in rag_files:
                try:
                    filename = os.path.basename(file_path)

                    # Read first 1000 chars for summary
                    summary = ""
                    with open(file_path, "rb") as f:
                        # Try to read a bit to get context
                        content = f.read(2048)

                    text_content = FileService.extract_text_from_file(content)
                    if text_content:
                        summary = text_content[:500]

                    # Create embedding for "Filename: ... Content: ..."
                    # Weight filename heavily
                    index_text = f"Filename: {filename}\nContent: {summary}"
                    emb = EmbeddingService.get_embedding(index_text, max_length=512)

                    if np.any(emb):
                        embeddings.append(emb)
                        valid_files.append(
                            {
                                "filename": filename,
                                "path": file_path,
                                "summary": summary,
                            }
                        )
                except Exception as e:
                    logger.warning(f"Failed to index file {file_path}: {e}")

            if embeddings:
                emb_array = np.array(embeddings).astype("float32")
                faiss.normalize_L2(emb_array)

                index = faiss.IndexFlatIP(EmbeddingService.DIM)
                index.add(emb_array)

                RAGService._global_index = index
                RAGService._global_files = valid_files
                logger.info(f"Built global index with {len(valid_files)} files.")
            else:
                RAGService._global_index = None
                RAGService._global_files = []

        except Exception as e:
            logger.error(f"Error building global index: {e}")
        finally:
            RAGService._global_index_lock = False

    @staticmethod
    def find_relevant_files(query: str, top_k: int = 5) -> List[str]:
        """Find relevant files from global index based on query"""
        # Ensure index exists
        if RAGService._global_index is None:
            RAGService._build_global_index()

        if RAGService._global_index is None or not RAGService._global_files:
            return []

        try:
            query_emb = EmbeddingService.get_embedding(query, max_length=512)
            if np.all(query_emb == 0):
                return []

            query_emb = query_emb.astype("float32").reshape(1, -1)
            faiss.normalize_L2(query_emb)

            D, I = RAGService._global_index.search(
                query_emb, k=min(top_k, len(RAGService._global_files))
            )

            relevant_files = []
            scores = D[0]
            indices = I[0]

            for i, idx in enumerate(indices):
                if idx != -1 and 0 <= idx < len(RAGService._global_files):
                    score = scores[i]
                    file_info = RAGService._global_files[idx]
                    logger.info(
                        f"Checking file: {file_info['filename']} (score: {score:.3f})"
                    )
                    if (
                        score > 0.40
                    ):  # Threshold for file relevance - Increased from 0.15
                        relevant_files.append(file_info["path"])
                        logger.info(
                            f"Found relevant file: {file_info['filename']} (score: {score:.3f})"
                        )

            return relevant_files

        except Exception as e:
            logger.error(f"Error searching relevant files: {e}")
            return []

    @staticmethod
    def chunk_text(text: str, chunk_size: int = 600, overlap: int = 80) -> List[str]:
        """Chunk text thành các đoạn nhỏ với overlap - improved version"""
        if len(text) <= chunk_size:
            return [text]

        text = re.sub(r"\n+", "\n", text.strip())
        if not text:
            return []

        chunks = []
        start = 0
        text_length = len(text)

        while start < text_length:
            end = min(start + chunk_size, text_length)

            if end < text_length:
                # Tìm điểm cắt tốt hơn
                break_points = [
                    text.rfind("\n\n", start, end),
                    text.rfind("\n", start, end),
                    text.rfind(". ", start, end),
                    text.rfind("! ", start, end),
                    text.rfind("? ", start, end),
                ]

                best_break = -1
                for bp in break_points:
                    if bp != -1 and bp > start + (chunk_size // 3):
                        best_break = bp
                        break

                if best_break != -1:
                    end = best_break + 1

            chunk = text[start:end].strip()
            if chunk and len(chunk) >= 25:
                chunks.append(chunk)

            next_start = end - overlap
            if next_start <= start:
                next_start = end
            start = next_start

        logger.info(f"Created {len(chunks)} chunks from text")
        return chunks

    @staticmethod
    def process_file_for_rag(
        file_content: bytes, user_id: int, conversation_id: int, filename: str = ""
    ) -> str:
        """Xử lý file để tạo RAG context - với debug chi tiết"""
        try:
            logger.info(f"Starting to process file for RAG: {filename}")

            file_text = FileService.extract_text_from_file(file_content)
            if not file_text or not file_text.strip():
                logger.warning(f"No text extracted from file {filename}")
                return ""

            logger.info(f"Extracted {len(file_text)} characters from {filename}")

            # Chunk text
            chunks = RAGService.chunk_text(file_text, chunk_size=600, overlap=80)
            if not chunks:
                logger.warning(f"No chunks created from file {filename}")
                return ""

            logger.info(f"Created {len(chunks)} chunks from {filename}")

            # Load FAISS index
            index, exists = RAGService.load_faiss(user_id, conversation_id)

            embeddings = []
            valid_chunks = []

            # Tạo embeddings cho từng chunk
            for i, chunk in enumerate(chunks):
                if len(chunk.strip()) < 25:
                    continue

                chunk_with_info = (
                    f"[File: {filename}] [Chunk {i+1}/{len(chunks)}] {chunk}"
                )
                emb = EmbeddingService.get_embedding(chunk_with_info, max_length=512)

                if np.any(emb) and not np.all(emb == 0):
                    embeddings.append(emb)
                    valid_chunks.append(chunk_with_info)
                    logger.debug(f"Created embedding for chunk {i+1}")
                else:
                    logger.warning(f"Failed to create embedding for chunk {i+1}")

            logger.info(
                f"Created {len(embeddings)} valid embeddings from {len(chunks)} chunks"
            )

            if embeddings:
                emb_array = np.array(embeddings).astype("float32")
                faiss.normalize_L2(emb_array)

                # Kiểm tra index trước khi thêm
                # Load current metadata
                current_chunks = RAGService.load_metadata(user_id, conversation_id)
                initial_count = index.ntotal

                # Check consistency
                if len(current_chunks) != initial_count:
                    logger.warning(
                        f"Index/Metadata mismatch: {initial_count} vectors but {len(current_chunks)} chunks. Resetting."
                    )
                    index = faiss.IndexFlatIP(EmbeddingService.DIM)
                    current_chunks = []
                    initial_count = 0

                index.add(emb_array)
                new_count = index.ntotal

                # Append new chunks
                current_chunks.extend(valid_chunks)
                RAGService.save_metadata(user_id, conversation_id, current_chunks)

                logger.info(
                    f"Added {new_count - initial_count} vectors to FAISS index. Total: {new_count}"
                )

                # Lưu index
                faiss_path = RAGService.get_faiss_path(user_id, conversation_id)
                faiss.write_index(index, faiss_path)

                result_context = f"[File: {filename}] [Loaded: {len(valid_chunks)} chunks, {sum(len(chunk) for chunk in valid_chunks)} characters]"
                logger.info(f"Successfully processed file {filename}: {result_context}")
                return result_context
            else:
                logger.warning(f"No valid embeddings created from file {filename}")
                return ""

        except Exception as e:
            logger.error(
                f"Error processing file {filename} for RAG: {e}", exc_info=True
            )
            return ""

    @staticmethod
    def _ensure_rag_loaded(user_id: int, conversation_id: int) -> bool:
        """Đảm bảo RAG files được load - trả về True nếu đã load hoặc load thành công"""
        try:
            index_path = RAGService.get_faiss_path(user_id, conversation_id)

            # Kiểm tra xem đã có index chưa
            if os.path.exists(index_path) and os.path.getsize(index_path) > 100:
                index, exists = RAGService.load_faiss(user_id, conversation_id)
                if exists and index.ntotal > 0:
                    logger.info(f"RAG already loaded with {index.ntotal} vectors")
                    return True

            # Nếu chưa, load RAG files
            logger.info(
                f"Loading RAG files for user {user_id}, conversation {conversation_id}"
            )
            loaded_files = RAGService.load_rag_files_to_conversation(
                user_id, conversation_id
            )

            if loaded_files:
                logger.info(f"Successfully loaded {len(loaded_files)} RAG files")
                return True
            else:
                logger.warning("No RAG files were loaded")
                return False

        except Exception as e:
            logger.error(f"Error ensuring RAG loaded: {e}")
            return False

    @staticmethod
    def load_rag_files_to_conversation(
        user_id: int, conversation_id: int, target_files: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """
        Load RAG files vào conversation.
        Nếu target_files is None, load tất cả (behavior cũ - deprecated logic but kept for fallback).
        Nếu target_files list provided, chỉ load những file đó.
        """
        rag_files = []

        if target_files is not None:
            # Validate existing files
            rag_files = [f for f in target_files if os.path.exists(f)]
        else:
            # Fallback: Load all supported patterns
            supported_patterns = [
                os.path.join(RAG_FILES_DIR, "*.pdf"),
                os.path.join(RAG_FILES_DIR, "*.txt"),
                os.path.join(RAG_FILES_DIR, "*.docx"),
                os.path.join(RAG_FILES_DIR, "*.xlsx"),
                os.path.join(RAG_FILES_DIR, "*.xls"),
                os.path.join(RAG_FILES_DIR, "*.csv"),
                os.path.join(RAG_FILES_DIR, "*.parquet"),
                os.path.join(RAG_FILES_DIR, "*.md"),
                os.path.join(RAG_FILES_DIR, "*.py"),
                os.path.join(RAG_FILES_DIR, "*.js"),
                os.path.join(RAG_FILES_DIR, "*.java"),
                os.path.join(RAG_FILES_DIR, "*.cpp"),
                os.path.join(RAG_FILES_DIR, "*.h"),
                os.path.join(RAG_FILES_DIR, "*.c"),
                os.path.join(RAG_FILES_DIR, "*.cs"),
                os.path.join(RAG_FILES_DIR, "*.go"),
                os.path.join(RAG_FILES_DIR, "*.rs"),
                os.path.join(RAG_FILES_DIR, "*.php"),
                os.path.join(RAG_FILES_DIR, "*.rb"),
                os.path.join(RAG_FILES_DIR, "*.swift"),
                os.path.join(RAG_FILES_DIR, "*.kt"),
                os.path.join(RAG_FILES_DIR, "*.ts"),
                os.path.join(RAG_FILES_DIR, "*.tsx"),
                os.path.join(RAG_FILES_DIR, "*.jsx"),
                os.path.join(RAG_FILES_DIR, "*.vue"),
                os.path.join(RAG_FILES_DIR, "*.html"),
                os.path.join(RAG_FILES_DIR, "*.css"),
                os.path.join(RAG_FILES_DIR, "*.json"),
                os.path.join(RAG_FILES_DIR, "*.yaml"),
                os.path.join(RAG_FILES_DIR, "*.yml"),
                os.path.join(RAG_FILES_DIR, "*.sh"),
                os.path.join(RAG_FILES_DIR, "*.sql"),
            ]

            for pattern in supported_patterns:
                rag_files.extend(glob.glob(pattern))

        if not rag_files:
            # logger.info(f"No RAG files found in {RAG_FILES_DIR}")
            return []

        logger.info(
            f"Found {len(rag_files)} RAG files to load: {[os.path.basename(f) for f in rag_files]}"
        )

        loaded_files = []

        for file_path in rag_files:
            try:
                with open(file_path, "rb") as f:
                    file_content = f.read()

                filename = os.path.basename(file_path)
                logger.info(f"Processing RAG file: {filename}")

                rag_context = RAGService.process_file_for_rag(
                    file_content, user_id, conversation_id, filename
                )

                if rag_context:
                    loaded_files.append(
                        {
                            "filename": filename,
                            "path": file_path,
                            "chunks_loaded": rag_context,
                        }
                    )
                    logger.info(f"Successfully loaded RAG file: {filename}")
                else:
                    logger.warning(f"Failed to load RAG file: {filename}")

            except Exception as e:
                logger.error(f"Error loading RAG file {file_path}: {e}")

        logger.info(
            f"Loaded {len(loaded_files)} RAG files for user {user_id}, conversation {conversation_id}"
        )
        return loaded_files

    @staticmethod
    def get_faiss_path(user_id: int, conversation_id: int) -> str:
        """Tạo đường dẫn cho FAISS index"""
        index_dir = "faiss_indices"
        os.makedirs(index_dir, exist_ok=True)
        return os.path.join(index_dir, f"faiss_{user_id}_{conversation_id}.index")

    @staticmethod
    def get_metadata_path(user_id: int, conversation_id: int) -> str:
        """Tạo đường dẫn cho Metadata JSON (lưu text content)"""
        index_dir = "faiss_indices"
        os.makedirs(index_dir, exist_ok=True)
        return os.path.join(index_dir, f"metadata_{user_id}_{conversation_id}.json")

    @staticmethod
    def load_metadata(user_id: int, conversation_id: int) -> List[str]:
        """Load text chunks mapping"""
        path = RAGService.get_metadata_path(user_id, conversation_id)
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading metadata {path}: {e}")
        return []

    @staticmethod
    def save_metadata(user_id: int, conversation_id: int, chunks: List[str]):
        """Save text chunks mapping"""
        path = RAGService.get_metadata_path(user_id, conversation_id)
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(chunks, f, ensure_ascii=False)
        except Exception as e:
            logger.error(f"Error saving metadata {path}: {e}")

    # Simple in-memory cache for FAISS indices: key=(user_id, conversation_id), value=index
    _index_cache = {}
    _MAX_CACHE_SIZE = 5

    @staticmethod
    def _get_from_cache(user_id: int, conversation_id: int) -> Optional[Any]:
        return RAGService._index_cache.get((user_id, conversation_id))

    @staticmethod
    def _add_to_cache(user_id: int, conversation_id: int, index: Any):
        if len(RAGService._index_cache) >= RAGService._MAX_CACHE_SIZE:
            # Very simple eviction: pop random item. For better logical LRU, requires more complex structure.
            # Given small size, popping first key is fine.
            try:
                key = next(iter(RAGService._index_cache))
                RAGService._index_cache.pop(key)
            except:
                pass
        RAGService._index_cache[(user_id, conversation_id)] = index

    @staticmethod
    def load_faiss(user_id: int, conversation_id: int) -> Tuple[Any, bool]:
        """Tải hoặc tạo mới FAISS index (có caching)"""
        # Check cache first
        cached_index = RAGService._get_from_cache(user_id, conversation_id)
        if cached_index:
            return cached_index, True

        path = RAGService.get_faiss_path(user_id, conversation_id)

        if os.path.exists(path) and os.path.getsize(path) > 100:
            try:
                index = faiss.read_index(path)
                logger.info(
                    f"Loaded FAISS index with {index.ntotal} vectors from {path}"
                )
                RAGService._add_to_cache(user_id, conversation_id, index)
                return index, True
            except Exception as e:
                logger.error(f"Error loading FAISS index {path}: {e}")
                try:
                    os.remove(path)
                    logger.info(f"Removed corrupted FAISS index: {path}")
                except:
                    pass

        logger.info(
            f"Creating new FAISS index for user {user_id}, conversation {conversation_id}"
        )
        index = faiss.IndexFlatIP(EmbeddingService.DIM)
        # Don't cache empty new index until it has data? Or cache it. Cache it is fine.
        RAGService._add_to_cache(user_id, conversation_id, index)
        return index, False

    @staticmethod
    def get_rag_context(
        effective_query: str,
        user_id: int,
        conversation_id: int,
        db: Session,
        top_k: int = 10,
    ) -> str:
        """Lấy RAG context từ FAISS index và history - với debug chi tiết"""
        try:
            logger.info(f"Getting RAG context for query: {effective_query[:100]}...")

            # Load FAISS index directly
            index, exists = RAGService.load_faiss(user_id, conversation_id)

            # IDENTIFY RELEVANT FILES
            relevant_files = RAGService.find_relevant_files(effective_query, top_k=5)

            if relevant_files:
                logger.info(f"Found {len(relevant_files)} relevant files for query")

                # Check which files are NOT yet loaded in the current metadata
                # Note: This is a bit coarse. Metadata stores chunks, not filenames directly in a clean way in current implementation.
                # But we can reconstruct it or simply try to load them.
                # Better approach: load_rag_files_to_conversation handles logic of "adding" to index.

                # For now, we just call load for these files.
                # Ideally we should check if they are already in index to avoid duplicate work,
                # but process_file_for_rag creates embeddings every time currently.
                # Optimization: We should have a way to know what's loaded.

                # Let's load the relevant files.
                # Note: This might re-index files if they are already there.
                # Ideally we should modify load_metadata to return list of loaded filenames to skip.

                RAGService.load_rag_files_to_conversation(
                    user_id, conversation_id, target_files=relevant_files
                )

                # Reload index after potential updates
                index, exists = RAGService.load_faiss(user_id, conversation_id)
            else:
                logger.info(
                    "No particular relevant files found from global index for this query."
                )

            if not exists or index.ntotal == 0:
                # If still empty (no relevant files found or first run), maybe fallback to nothing or check?
                # If no relevant files, we shouldn't return anything unless there's previous history.
                logger.warning(
                    "FAISS index is empty and no relevant files found to load."
                )
                return ""

            # Load metadata
            chunks = RAGService.load_metadata(user_id, conversation_id)
            if not chunks or len(chunks) != index.ntotal:
                logger.warning(
                    f"Metadata mismatch or empty. Index: {index.ntotal}, Chunks: {len(chunks)}"
                )
                return ""

            query_emb = EmbeddingService.get_embedding(effective_query, max_length=512)
            if np.all(query_emb == 0):
                logger.warning("Failed to generate query embedding")
                return ""

            logger.info(f"FAISS index has {index.ntotal} vectors")

            # Search in FAISS
            query_emb = query_emb.astype("float32").reshape(1, -1)
            faiss.normalize_L2(query_emb)

            search_k = min(top_k, index.ntotal)
            D, I = index.search(query_emb, k=search_k)

            scores = D[0]
            indices = I[0]

            context_results = []
            logger.info(f"Search results: {len(indices)} items")

            for i, idx in enumerate(indices):
                if idx == -1:
                    continue

                score = scores[i]
                if score < 0.2:  # Threshold
                    continue

                if 0 <= idx < len(chunks):
                    chunk_text = chunks[idx]
                    context_results.append(chunk_text)
                    logger.debug(f"Retrieved chunk {idx} with score {score:.3f}")

            if context_results:
                final_context = "\n\n".join(context_results)
                logger.info(
                    f"Retrieved {len(context_results)} relevant chunks from RAG"
                )
                return final_context
            else:
                logger.warning(
                    "No relevant context found in RAG search (scores too low)"
                )
                return ""

        except Exception as e:
            logger.error(f"Error in get_rag_context: {e}")
            return ""

    @staticmethod
    def _hybrid_search(
        query: str,
        query_emb: np.ndarray,
        index: Any,
        history: List[ModelChatMessage],
        top_k: int = 10,
    ) -> str:
        """Thực hiện hybrid search với FAISS và BM25"""
        if not history or index.ntotal == 0:
            return ""

        try:
            index_contents = [h.content for h in history]

            # BM25 search
            tokenized_contents = [
                re.findall(r"\w+", content.lower()) for content in index_contents
            ]
            if not any(tokenized_contents):
                return ""

            bm25 = BM25Okapi(tokenized_contents)
            query_tokens = re.findall(r"\w+", query.lower())

            if not query_tokens:
                bm25_scores = np.zeros(len(history))
            else:
                bm25_scores = bm25.get_scores(query_tokens)

            # FAISS search
            search_k = min(20, index.ntotal)
            if index.ntotal > 0:
                D, I_faiss = index.search(query_emb, k=search_k)
                faiss_scores = D[0]
                faiss_indices = I_faiss[0]
            else:
                faiss_scores = np.array([])
                faiss_indices = np.array([])

            # Kết hợp scores
            hybrid_scores = {}
            for i, idx in enumerate(faiss_indices):
                if idx < len(bm25_scores):
                    faiss_score = (faiss_scores[i] + 1) / 2
                    bm25_score = min(bm25_scores[idx] / 5, 1.0)
                    hybrid_score = 0.6 * faiss_score + 0.4 * bm25_score
                    hybrid_scores[idx] = hybrid_score

            # Nếu không có kết quả từ FAISS, sử dụng BM25
            if not hybrid_scores and len(bm25_scores) > 0:
                for idx, bm25_score in enumerate(bm25_scores):
                    if bm25_score > 0:
                        hybrid_scores[idx] = bm25_score / 5

            # Chọn top k results
            reranked_indices = sorted(
                hybrid_scores, key=hybrid_scores.get, reverse=True
            )[:top_k]

            context_messages = []
            for idx in reranked_indices:
                if idx < len(history):
                    msg = history[idx]
                    sim_score = hybrid_scores[idx]
                    if sim_score > 0.15:  # Threshold vừa phải
                        context_messages.append(msg.content)
                        logger.debug(f"Retrieved context with score {sim_score:.3f}")

            if context_messages:
                # Sử dụng separator rõ ràng
                return "|||".join(context_messages)
            else:
                return ""

        except Exception as e:
            logger.error(f"Error in hybrid search: {e}")
            return ""

    @staticmethod
    def update_faiss_index(user_id: int, conversation_id: int, db: Session):
        """Cập nhật FAISS index với tất cả messages"""
        try:
            index = faiss.IndexFlatIP(EmbeddingService.DIM)
            all_msgs = (
                db.query(ModelChatMessage)
                .filter(ModelChatMessage.conversation_id == conversation_id)
                .all()
            )

            valid_embs = []
            for m in all_msgs:
                if m.embedding:
                    try:
                        emb = json.loads(m.embedding)
                        if isinstance(emb, list) and len(emb) == EmbeddingService.DIM:
                            valid_embs.append(emb)
                    except:
                        continue

            if valid_embs:
                emb_array = np.array(valid_embs).astype("float32")
                faiss.normalize_L2(emb_array)
                index.add(emb_array)

            faiss.write_index(
                index, RAGService.get_faiss_path(user_id, conversation_id)
            )
            logger.info(f"Updated FAISS index with {len(valid_embs)} vectors")

        except Exception as e:
            logger.error(f"Lỗi khi cập nhật FAISS index: {e}")

    @staticmethod
    def cleanup_faiss_index(user_id: int, conversation_id: int):
        """Xóa FAISS index của một conversation"""
        try:
            path = RAGService.get_faiss_path(user_id, conversation_id)
            if os.path.exists(path):
                os.remove(path)
                logger.info(f"Deleted FAISS index: {path}")
        except Exception as e:
            logger.error(f"Error deleting FAISS index {path}: {e}")

    @staticmethod
    def cleanup_all_user_faiss(user_id: int) -> int:
        """Xóa tất cả FAISS indices của user"""
        count = 0
        try:
            index_dir = "faiss_indices"
            if not os.path.exists(index_dir):
                return 0

            pattern = f"faiss_{user_id}_*.index"
            for f in glob.glob(os.path.join(index_dir, pattern)):
                try:
                    os.remove(f)
                    count += 1
                    logger.info(f"Deleted FAISS index: {f}")
                except Exception as e:
                    logger.error(f"Error deleting FAISS index {f}: {e}")
            return count
        except Exception as e:
            logger.error(f"Error cleaning up user FAISS indices: {e}")
            return 0
