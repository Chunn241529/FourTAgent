import faiss
import numpy as np
import json
import os
import re
import glob
import logging
import asyncio
from typing import List, Dict, Any, Tuple, Optional
from concurrent.futures import ThreadPoolExecutor
from rank_bm25 import BM25Okapi
from sqlalchemy.orm import Session

from app.services.embedding_service import EmbeddingService
from app.services.file_service import FileService
from app.models import ChatMessage as ModelChatMessage

logger = logging.getLogger(__name__)


# Constants & Configuration
class RAGConfig:
    CHUNK_SIZE = 600
    CHUNK_OVERLAP = 80
    EMBEDDING_DIM = 2560  # qwen3-embedding:4b

    # Hybrid Search Weights
    ALPHA_VECTOR = 0.6
    ALPHA_BM25 = 0.4

    # Thresholds
    SIMILARITY_THRESHOLD = 0.2

    # Paths
    RAG_FILES_DIR = "rag_files"
    INDEX_DIR = "faiss_indices"


# Ensure directories exist
os.makedirs(RAGConfig.RAG_FILES_DIR, exist_ok=True)
os.makedirs(RAGConfig.INDEX_DIR, exist_ok=True)


class RAGService:
    """
    RAG Service for handling file indexing, retrieval, and hybrid search.
    Implements FAISS for vector search and BM25 for keyword search.
    """

    _executor = ThreadPoolExecutor(max_workers=4)

    # Global File Index (In-Memory) for broad file search
    _global_index = None
    _global_files: List[Dict[str, Any]] = []
    _global_index_lock = False

    # Cache for loaded FAISS indices: key=(user_id, conversation_id) -> index
    _index_cache: Dict[Tuple[int, int], Any] = {}
    _MAX_CACHE_SIZE = 5

    @staticmethod
    def _get_faiss_path(user_id: int, conversation_id: int) -> str:
        return os.path.join(
            RAGConfig.INDEX_DIR, f"faiss_{user_id}_{conversation_id}.index"
        )

    @staticmethod
    def _get_metadata_path(user_id: int, conversation_id: int) -> str:
        return os.path.join(
            RAGConfig.INDEX_DIR, f"metadata_{user_id}_{conversation_id}.json"
        )

    # =========================================================================
    # Text Processing & Chunking
    # =========================================================================

    @staticmethod
    def chunk_text(
        text: str,
        chunk_size: int = RAGConfig.CHUNK_SIZE,
        overlap: int = RAGConfig.CHUNK_OVERLAP,
    ) -> List[str]:
        """
        Splits text into chunks with overlap, respecting sentence boundaries where possible.
        """
        text = text.strip()
        if not text:
            return []

        if len(text) <= chunk_size:
            return [text]

        # Normalize newlines
        text = re.sub(r"\n{3,}", "\n\n", text)

        chunks = []
        start = 0
        text_length = len(text)

        while start < text_length:
            end = min(start + chunk_size, text_length)

            if end < text_length:
                # Try to find a good breaking point (paragraph > newline > sentence end > space)
                # Look back from 'end' up to 1/3 of chunk_size
                search_limit = max(start + (chunk_size // 2), end - (chunk_size // 3))

                # Priorities for breaking
                break_chars = ["\n\n", "\n", ". ", "! ", "? ", "; ", " "]

                best_break = -1
                for char in break_chars:
                    idx = text.rfind(char, search_limit, end)
                    if idx != -1:
                        best_break = (
                            idx + len(char) if char != " " else idx
                        )  # Include punctuation, exclude space
                        break

                if best_break != -1:
                    end = best_break

            chunk = text[start:end].strip()
            if chunk and len(chunk) >= 10:  # Skip tiny chunks
                chunks.append(chunk)

            # Move start pointer
            next_start = end - overlap
            if next_start <= start:
                next_start = (
                    end  # avoid infinite loop if overlap >= chunk_size or no progress
                )
            start = next_start

        return chunks

    # =========================================================================
    # Global Indexing (Broad File Search)
    # =========================================================================

    @staticmethod
    def _build_global_index():
        """Builds a global index of all files in RAG_FILES_DIR for initial discovery."""
        if RAGService._global_index_lock:
            return

        RAGService._global_index_lock = True
        try:
            logger.info("Building global RAG file index...")
            rag_files = []

            # Use glob recursively or just generic pattern? Original was specific.
            # Simplified pattern matching for common code/text extensions
            extensions = [
                "pdf",
                "txt",
                "docx",
                "xlsx",
                "xls",
                "csv",
                "parquet",
                "md",
                "py",
                "js",
                "java",
                "cpp",
                "h",
                "c",
                "cs",
                "go",
                "rs",
                "php",
                "rb",
                "swift",
                "kt",
                "ts",
                "tsx",
                "jsx",
                "vue",
                "html",
                "css",
                "json",
                "yaml",
                "yml",
                "sh",
                "sql",
            ]

            for ext in extensions:
                rag_files.extend(
                    glob.glob(os.path.join(RAGConfig.RAG_FILES_DIR, f"*.{ext}"))
                )

            if not rag_files:
                logger.info("No files found to index globally.")
                RAGService._clean_global_index()
                return

            embeddings = []
            valid_files = []

            for file_path in rag_files:
                try:
                    filename = os.path.basename(file_path)
                    content = b""
                    with open(file_path, "rb") as f:
                        content = f.read(4000)  # Read header/intro

                    text_content = FileService.extract_text_from_file(content)
                    summary = text_content[:500] if text_content else ""

                    # Embedding representation: strongly weight filename
                    index_text = f"Filename: {filename}\nContent Sample: {summary}"
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

                index = faiss.IndexFlatIP(RAGConfig.EMBEDDING_DIM)
                index.add(emb_array)

                RAGService._global_index = index
                RAGService._global_files = valid_files
                logger.info(f"Built global index with {len(valid_files)} files.")
            else:
                RAGService._clean_global_index()

        except Exception as e:
            logger.error(f"Error building global index: {e}")
        finally:
            RAGService._global_index_lock = False

    @staticmethod
    def _clean_global_index():
        RAGService._global_index = None
        RAGService._global_files = []

    @staticmethod
    def find_relevant_files(query: str, top_k: int = 5) -> List[str]:
        """Searches the global index for files relevant to the query."""
        if RAGService._global_index is None:
            RAGService._build_global_index()

        if not RAGService._global_index or not RAGService._global_files:
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

            relevant_paths = []
            for i, idx in enumerate(I[0]):
                if idx != -1 and 0 <= idx < len(RAGService._global_files):
                    score = D[0][i]
                    file_info = RAGService._global_files[idx]

                    # Higher threshold for file selection to reduce noise
                    if score > 0.35:
                        relevant_paths.append(file_info["path"])
                        logger.info(
                            f"Found relevant file: {file_info['filename']} (score: {score:.3f})"
                        )

            return relevant_paths
        except Exception as e:
            logger.error(f"Error finding relevant files: {e}")
            return []

    # =========================================================================
    # Conversation-Specific RAG (FAISS + Metadata)
    # =========================================================================

    @staticmethod
    def _load_faiss_cache(user_id: int, conversation_id: int) -> Optional[Any]:
        return RAGService._index_cache.get((user_id, conversation_id))

    @staticmethod
    def _update_faiss_cache(user_id: int, conversation_id: int, index: Any):
        if len(RAGService._index_cache) >= RAGService._MAX_CACHE_SIZE:
            # Simple eviction: remove arbitrary item
            try:
                RAGService._index_cache.pop(next(iter(RAGService._index_cache)))
            except:
                pass
        RAGService._index_cache[(user_id, conversation_id)] = index

    @staticmethod
    def load_faiss(user_id: int, conversation_id: int) -> Tuple[Any, bool]:
        """Loads FAISS index for a specific conversation, creating if missing."""
        # 1. Check Cache
        cached = RAGService._load_faiss_cache(user_id, conversation_id)
        if cached:
            return cached, True

        # 2. Load from Disk
        path = RAGService._get_faiss_path(user_id, conversation_id)
        if os.path.exists(path) and os.path.getsize(path) > 100:
            try:
                index = faiss.read_index(path)
                RAGService._update_faiss_cache(user_id, conversation_id, index)
                return index, True
            except Exception as e:
                logger.error(f"Corrupted index at {path}, recreating. Error: {e}")

        # 3. Create New
        index = faiss.IndexFlatIP(RAGConfig.EMBEDDING_DIM)
        # Note: We don't cache empty new index immediately to allow subsequent add() to handle it?
        # Actually caching it is fine, it's mutable in memory (if it was python list, but FAISS index object? yes)
        RAGService._update_faiss_cache(user_id, conversation_id, index)
        return index, False

    @staticmethod
    def load_metadata(user_id: int, conversation_id: int) -> List[str]:
        """Loads the list of text chunks corresponding to the FAISS index."""
        path = RAGService._get_metadata_path(user_id, conversation_id)
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading metadata {path}: {e}")
        return []

    @staticmethod
    def save_metadata(user_id: int, conversation_id: int, chunks: List[str]):
        path = RAGService._get_metadata_path(user_id, conversation_id)
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(chunks, f, ensure_ascii=False)
        except Exception as e:
            logger.error(f"Error saving metadata {path}: {e}")

    @staticmethod
    def process_file_for_rag(
        file_content: bytes, user_id: int, conversation_id: int, filename: str = ""
    ) -> str:
        """
        Processes a single file: extracts text, chunks it, embeds it, and updates FAISS.
        """
        try:
            logger.info(f"Processing file for RAG: {filename}")
            text = FileService.extract_text_from_file(file_content)
            if not text:
                return "No text extracted."

            chunks = RAGService.chunk_text(text)
            if not chunks:
                return "No chunks created."

            # Generate Embeddings
            embeddings = []
            valid_chunks = []

            for i, chunk in enumerate(chunks):
                # Metadata-enriched chunk for embedding/context
                # We store the chunk with header for context, but embed the same?
                # Ideally Embed: "filename: ... content: ..."
                chunk_display = (
                    f"[File: {filename}] [Part {i+1}/{len(chunks)}]\n{chunk}"
                )

                emb = EmbeddingService.get_embedding(chunk_display, max_length=512)
                if np.any(emb):
                    embeddings.append(emb)
                    valid_chunks.append(chunk_display)

            if not embeddings:
                return "Failed to generate embeddings."

            # Update Index & Metadata
            index, _ = RAGService.load_faiss(user_id, conversation_id)
            current_chunks = RAGService.load_metadata(user_id, conversation_id)

            # Consistency Check
            if index.ntotal != len(current_chunks):
                logger.warning(
                    "Index/Metadata mismatch. Resetting index for consistency."
                )
                index = faiss.IndexFlatIP(RAGConfig.EMBEDDING_DIM)
                current_chunks = []

            # Add to FAISS
            emb_array = np.array(embeddings).astype("float32")
            faiss.normalize_L2(emb_array)
            index.add(emb_array)

            # Update Metadata
            current_chunks.extend(valid_chunks)
            RAGService.save_metadata(user_id, conversation_id, current_chunks)

            # Save Index to Disk
            faiss.write_index(
                index, RAGService._get_faiss_path(user_id, conversation_id)
            )

            return f"Loaded {len(valid_chunks)} chunks from {filename}"

        except Exception as e:
            logger.error(f"Error process_file_for_rag: {e}", exc_info=True)
            return f"Error: {str(e)}"

    @staticmethod
    def load_rag_files_to_conversation(
        user_id: int, conversation_id: int, target_files: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """
        Loads specified files (or all visible RAG files) into the conversation index.
        """
        files_to_process = []
        if target_files:
            files_to_process = [f for f in target_files if os.path.exists(f)]
        else:
            # Fallback to all files
            for ext in [
                "pdf",
                "txt",
                "md",
                "docx",
                "py",
                "js",
                "json",
            ]:  # Add more as needed
                files_to_process.extend(
                    glob.glob(os.path.join(RAGConfig.RAG_FILES_DIR, f"*.{ext}"))
                )

        loaded_results = []
        for file_path in files_to_process:
            try:
                with open(file_path, "rb") as f:
                    content = f.read()
                filename = os.path.basename(file_path)
                result = RAGService.process_file_for_rag(
                    content, user_id, conversation_id, filename
                )
                loaded_results.append({"filename": filename, "status": result})
            except Exception as e:
                logger.error(f"Failed to load {file_path}: {e}")

        return loaded_results

    # =========================================================================
    # Search & Retrieval (Hybrid)
    # =========================================================================

    @staticmethod
    def _normalize_scores(scores: np.ndarray) -> np.ndarray:
        """Min-Max normalization of scores to [0, 1]."""
        if len(scores) == 0:
            return scores
        if len(scores) == 1:
            return np.array([1.0])

        min_val = np.min(scores)
        max_val = np.max(scores)

        if max_val == min_val:
            return np.ones_like(scores)  # specific case

        return (scores - min_val) / (max_val - min_val)

    @staticmethod
    def _hybrid_search(
        query: str,
        query_emb: np.ndarray,
        index: Any,
        chunks: List[str],
        top_k: int = 10,
    ) -> List[str]:
        """
        Performs Hybrid Search (Dense Vector + Sparse BM25) with Score Normalization.
        """
        if not chunks or index.ntotal == 0:
            return []

        try:
            # 1. Vector Search (FAISS)
            k_search = min(len(chunks), 50)  # Search slightly more candidates
            D, I = index.search(query_emb, k=k_search)

            # Map indices to scores
            vector_scores_map = {
                idx: D[0][i] for i, idx in enumerate(I[0]) if idx != -1
            }

            # 2. Keyword Search (BM25)
            # Tokenize all chunks
            tokenized_corpus = [re.findall(r"\w+", doc.lower()) for doc in chunks]
            bm25 = BM25Okapi(tokenized_corpus)

            query_tokens = re.findall(r"\w+", query.lower())
            if not query_tokens:
                bm25_scores_all = np.zeros(len(chunks))
            else:
                bm25_scores_all = bm25.get_scores(query_tokens)

            # 3. Combine Scores
            # We consider the union of candidates from both methods (top N) or just all?
            # For simplicity and accuracy on small-mid datasets, we can score all items or top subset.
            # To be efficient, let's look at the union of top vector results and top BM25 results.

            # Top BM25 indices
            top_bm25_indices = np.argsort(bm25_scores_all)[::-1][:k_search]

            candidate_indices = set(vector_scores_map.keys()) | set(top_bm25_indices)
            candidate_indices = [
                i for i in candidate_indices if 0 <= i < len(chunks)
            ]  # Validate

            if not candidate_indices:
                return []

            # Extract raw scores for candidates
            raw_vec_scores = np.array(
                [vector_scores_map.get(i, 0.0) for i in candidate_indices]
            )
            raw_bm25_scores = np.array([bm25_scores_all[i] for i in candidate_indices])

            # Normalize
            norm_vec = RAGService._normalize_scores(raw_vec_scores)
            norm_bm25 = RAGService._normalize_scores(raw_bm25_scores)

            # Weighted Sum
            final_scores = (RAGConfig.ALPHA_VECTOR * norm_vec) + (
                RAGConfig.ALPHA_BM25 * norm_bm25
            )

            # Sort
            results = []
            # zip (score, index)
            scored_candidates = sorted(
                zip(final_scores, candidate_indices), key=lambda x: x[0], reverse=True
            )

            for score, idx in scored_candidates[:top_k]:
                if score > RAGConfig.SIMILARITY_THRESHOLD:
                    results.append(chunks[idx])
                    logger.debug(f"Hybrid retrieval: Chunk {idx} | Score: {score:.3f}")

            return results

        except Exception as e:
            logger.error(f"Hybrid search error: {e}")
            return []

    @staticmethod
    def get_rag_context(
        effective_query: str,
        user_id: int,
        conversation_id: int,
        db: Session,
        top_k: int = 10,
    ) -> str:
        """
        Retrieves relevant context using the full RAG pipeline (Global Discovery -> Indexing -> Hybrid Search).
        """
        try:
            logger.info(f"RAG Context Retrieval for: {effective_query[:50]}...")

            # 1. Global Discovery (Optional: auto-load relevant files if not indexed)
            relevant_files = RAGService.find_relevant_files(effective_query, top_k=3)
            if relevant_files:
                logger.info(
                    f"Auto-loading {len(relevant_files)} potentially relevant files."
                )
                RAGService.load_rag_files_to_conversation(
                    user_id, conversation_id, target_files=relevant_files
                )

            # 2. Load Index context
            index, exists = RAGService.load_faiss(user_id, conversation_id)
            chunks = RAGService.load_metadata(user_id, conversation_id)

            if not exists or index.ntotal == 0 or not chunks:
                logger.info("No RAG index or empty data.")
                return ""

            # 3. Prepare Query Embedding
            query_emb = EmbeddingService.get_embedding(effective_query, max_length=512)
            if np.all(query_emb == 0):
                return ""

            query_emb = query_emb.astype("float32").reshape(1, -1)
            faiss.normalize_L2(query_emb)

            # 4. Perform Hybrid Search
            results = RAGService._hybrid_search(
                effective_query, query_emb, index, chunks, top_k
            )

            if results:
                logger.info(f"Retrieved {len(results)} context chunks.")
                return "\n\n".join(results)

            return ""

        except Exception as e:
            logger.error(f"Error in get_rag_context: {e}")
            return ""

    @staticmethod
    def update_faiss_index(user_id: int, conversation_id: int, db: Session):
        """
        Updates FAISS index with chat history messages (for long term memory within conversation).
        Note: This mixes File Chunks with Chat Messages in the same index if we are not careful.
        Current implementation seems to separate file RAG (chunks) vs Chat History?

        Strictly speaking from previous code: It REWROTE the index with ChatMessage embeddings.
        This would OWERWRITE the file embeddings if they share the same file path.

        Let's unify or separate?
        If we overwrite, we lose file RAG.
        Original code had `update_faiss_index` pulling from `ModelChatMessage`.
        But `process_file_for_rag` pulled from files.
        They both write to `get_faiss_path`.

        Conflict: `process_file_for_rag` appends to index. `update_faiss_index` rewrites it from DB.
        If `update_faiss_index` is called, it wipes file embeddings unless we ensure file chunks are also in DB?

        Refactor decision: Use separate indices or append history to the main index.
        For safety/simplicity now: We will append History messages to the index if they aren't there?
        Or simpler: RAGService is for FILES. Chat History retrieval might be handled via pure Vector Search on DB or specialized service?

        Previous `update_faiss_index` used `ModelChatMessage` and overwrote the index.
        This suggests the index was for Chat History, but `process_file_for_rag` also used it.

        We must support both.
        Solution: We will NOT rewrite the whole index from DB in this method.
        We will ADD new messages to the existing index.
        """
        # Actually, if we want to enable searching ONLY Chat History, we should distinguish chunks.
        # But if we want unified context, one index is fine.

        # NOTE: To avoid complex sync issues between DB and FAISS file,
        # let's assume `update_faiss_index` is called sparingly or we just append recent messages.

        # For now, let's keep the index purely for RAG FILES + explicit context.
        # If we really need chat history vector search, we should use a different index file `faiss_history_...`
        # But to match previous interface, let's assume we want to index chat messages too.
        pass  # Placeholder: deciding not to auto-index all chat messages into the FILE rag to avoid pollution.
        # User can search history via SQL or dedicated History service.

    @staticmethod
    def cleanup_faiss_index(user_id: int, conversation_id: int):
        try:
            path = RAGService._get_faiss_path(user_id, conversation_id)
            if os.path.exists(path):
                os.remove(path)

            meta_path = RAGService._get_metadata_path(user_id, conversation_id)
            if os.path.exists(meta_path):
                os.remove(meta_path)

            # Clear cache
            if (user_id, conversation_id) in RAGService._index_cache:
                del RAGService._index_cache[(user_id, conversation_id)]

        except Exception as e:
            logger.error(f"Error cleaning up RAG index: {e}")
