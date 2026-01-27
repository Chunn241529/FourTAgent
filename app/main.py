from fastapi import FastAPI, Request, Depends, HTTPException
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from app.db import Base, engine
from app.models import *  # Import tất cả model để đăng ký với Base
from app.routers.task import router as task_router
from app.routers.auth import router as auth_router
from app.routers.chat import router as chat_router
from app.routers.conversations import router as conversations_router
from app.routers.messages import router as messages_router
from app.routers.rag import router as rag_router
from app.routers.feedback import router as feedback_router
from app.routers.tts import router as tts_router
from app.routers.voice import router as voice_router
from app.routers.generate import router as generate_router
from app.utils import verify_jwt
import uvicorn
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
import logging
import os
import subprocess
import signal
import atexit

import time
from logging.handlers import RotatingFileHandler

# Tạo thư mục logs và storage
os.makedirs("logs", exist_ok=True)
os.makedirs("storage", exist_ok=True)

# === LOGGING CONFIGURATION ===
# Get root logger
root_logger = logging.getLogger()
root_logger.setLevel(logging.DEBUG)  # Root phải accept tất cả

# File Handler (logs/server.log) - ghi TẤT CẢ log
file_handler = RotatingFileHandler(
    "logs/server.log", maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
)
file_handler.setFormatter(
    logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
)
file_handler.setLevel(logging.DEBUG)
root_logger.addHandler(file_handler)

# Console Handler - chỉ hiện INFO trở lên
console_handler = logging.StreamHandler()
console_handler.setFormatter(
    logging.Formatter("%(asctime)s - %(levelname)s: %(message)s")
)
console_handler.setLevel(logging.INFO)
root_logger.addHandler(console_handler)

# Tắt bớt log ồn ào từ các thư viện bên thứ 3 (cả file và console)
for noisy_logger in [
    "uvicorn.access",
    "httpcore",
    "watchfiles.main",
    "httpx",
    "multipart",
    "passlib",
    "faiss",
    "rquest",
    "cookie_store",
    "primp",
]:
    logging.getLogger(noisy_logger).setLevel(logging.WARNING)

# Logger riêng cho ứng dụng
logger = logging.getLogger("fourt_ai")

# Tạo tất cả bảng trong database
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Lumina AI",
    version="1.0.0",
    description="Lumina AI - Your Personal Task and Chat Assistant",
    openapi_tags=[
        {"name": "auth", "description": "Authentication and User Management"},
        {"name": "task", "description": "Task Management"},
        {"name": "chat", "description": "Chat with AI"},
        {"name": "conversations", "description": "Conversation History Management"},
        {"name": "messages", "description": "Message Handling"},
        {"name": "rag", "description": "Retrieval-Augmented Generation"},
        {"name": "feedback", "description": "User Feedback for AI Responses"},
        {"name": "tts", "description": "Text-to-Speech Service"},
    ],
)

# Cấu hình Jinja2Templates
templates = Jinja2Templates(directory="ui/web/pages")

# Phục vụ file tĩnh (script.js, style.css)
app.mount("/static", StaticFiles(directory="ui/web/static"), name="static")
app.mount("/storage", StaticFiles(directory="storage"), name="storage")

# Thêm middleware CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://api.fourt.io.vn",  # Cloudflare Tunnel
        "https://fourt.io.vn",
        "http://localhost:8080",  # Flutter web dev server
        "http://127.0.0.1:8080",
        "http://localhost:3000",
        "http://0.0.0.0:8080",
        "*",  # Allow all for development
    ],
    allow_credentials=True,
    allow_methods=["*"],  # Allow all methods
    allow_headers=["*"],  # Allow all headers
    expose_headers=[
        "Access-Control-Allow-Origin",
        "Access-Control-Allow-Methods",
        "Access-Control-Allow-Headers",
    ],
)


# Enable GZip compression
app.add_middleware(GZipMiddleware, minimum_size=1000)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()

    # Log request start
    # logger.debug(f"START REQ: {request.method} {request.url.path}")

    try:
        response = await call_next(request)
        process_time = (time.time() - start_time) * 1000
        formatted_process_time = "{0:.2f}".format(process_time)

        logger.info(
            f"{request.method} {request.url.path} "
            f"- {response.status_code} - {formatted_process_time}ms"
        )
        return response
    except Exception as e:
        process_time = (time.time() - start_time) * 1000
        logger.error(
            f"ERROR {request.method} {request.url.path} "
            f"- {str(e)} - {process_time:.2f}ms",
            exc_info=True,
        )
        raise e


# Route để render login.html tại '/'
@app.get("/", response_class=HTMLResponse)
async def get_login(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})


@app.get("/register", response_class=HTMLResponse)
async def get_register(request: Request):
    return templates.TemplateResponse("register.html", {"request": request})


@app.get("/forgetpw", response_class=HTMLResponse)
async def get_forgetpw(request: Request):
    return templates.TemplateResponse("forget-password.html", {"request": request})


@app.get("/reset-password", response_class=HTMLResponse)
async def get_reset_password(request: Request):
    return templates.TemplateResponse("reset-password.html", {"request": request})


app.include_router(auth_router)
app.include_router(task_router)
app.include_router(chat_router)
app.include_router(conversations_router)
app.include_router(messages_router)
app.include_router(rag_router)
app.include_router(feedback_router)
app.include_router(tts_router)
app.include_router(voice_router)
app.include_router(generate_router)


def main():
    try:
        uvicorn.run(app, host="0.0.0.0", port=8000)
    except Exception as e:
        logger.error(f"Server error: {e}")


# Startup event
@app.on_event("startup")
async def startup_event():
    """Run tasks on server startup"""
    from app.services.chat_service import ChatService
    import asyncio

    logger.info("Triggering background tasks...")
    # Run filler warmup in background
    asyncio.create_task(ChatService.warmup_fillers())


if __name__ == "__main__":
    try:
        uvicorn.run(
            "app.main:app",
            host="0.0.0.0",
            port=8000,
            reload=False,
            reload_dirs=["app"],  # Only watch app folder, not logs
        )
    except Exception as e:
        logger.error(f"Server crashed: {e}")
