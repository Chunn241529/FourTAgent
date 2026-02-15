import logging
import json
from sqlalchemy.orm import Session
from app.services.tool_service import ToolService
from app.services.file_service import FileService
from app.models import ChatMessage as ModelChatMessage

logger = logging.getLogger(__name__)
tool_service = ToolService()


def select_model(
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
        return "Lumina", tools, False
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
                logger.warning(f"Error checking recent images for vision switch: {e}")

        return "Lumina", tools, False


def should_use_rag(query: str) -> bool:
    """Determine if RAG should be used based on query content"""
    query_lower = query.lower()

    # 1. Skip if Image Generation (handled by tool)
    image_keywords = [
        "vẽ",
        "tạo ảnh",
        "generate image",
        "draw",
        "sketch",
        "paint",
        "picture",
        "photo",
    ]
    if (
        any(k in query_lower for k in image_keywords) and len(query.split()) < 20
    ):  # Short image prompts
        return False

    # 2. Skip if Greeting/Chitchat (approximate)
    chitchat = [
        "hi",
        "hello",
        "chào",
        "xin chào",
        "bạn ơi",
        "alo",
        "thời tiết",
        "mấy giờ",
        "cảm ơn",
        "thank",
    ]
    if any(query_lower.startswith(k) for k in chitchat) and len(query.split()) < 5:
        return False

    # 3. Enable for Informational/Search keywords
    rag_keywords = [
        "là gì",
        "như thế nào",
        "how to",
        "giải thích",
        "explain",
        "tài liệu",
        "document",
        "hồ sơ",
        "quy trình",
        "policy",
        "tìm",
        "search",
        "thông tin",
        "chi tiết",
        "phân tích",
        "code",
        "lỗi",
        "error",
        "bug",
        "fix",
        "sửa",
        "tại sao",
        "why",
        "nằm ở đâu",
        "location",
        "cấu trúc",
        "project",
        "dự án",
    ]
    if any(k in query_lower for k in rag_keywords):
        return True

    # 4. Default: Enable if query is long enough (likely seeking info)
    if len(query.split()) > 5:
        return True

    return False
