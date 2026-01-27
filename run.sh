#!/bin/bash

# Kiểm tra xem môi trường ảo đã được kích hoạt hay chưa
if [ -n "$VIRTUAL_ENV" ]; then
    echo "Môi trường ảo đã được kích hoạt: $VIRTUAL_ENV"
else
    # Tìm môi trường ảo trong thư mục hiện tại (venv hoặc .venv)
    if [ -d "venv" ]; then
        source venv/bin/activate
        echo "Đã kích hoạt môi trường ảo: venv"
    elif [ -d ".venv" ]; then
        source .venv/bin/activate
        echo "Đã kích hoạt môi trường ảo: .venv"
    else
        echo "Lỗi: Không tìm thấy môi trường ảo (venv hoặc .venv) trong thư mục hiện tại."
        exit 1
    fi
fi

# Kiểm tra xem uvicorn đã được cài đặt chưa
if ! command -v uvicorn >/dev/null 2>&1; then
    echo "Lỗi: uvicorn không được cài đặt trong môi trường ảo. Hãy cài đặt bằng 'pip install uvicorn'."
    exit 1
fi

# Dọn dẹp cache Python (__pycache__ và file .pyc)
cleanup_cache() {
    echo "Đang dọn dẹp cache Python..."
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
    find . -type f -name "*.pyc" -delete 2>/dev/null
    echo "Đã xóa cache Python thành công."
    echo "Đã xóa cache Python thành công."
}

# Hàm chạy tunnel
run_tunnel() {
    if pgrep -f "cloudflared tunnel run fourt-api" > /dev/null; then
        echo "✅ Tunnel Cloudflare đang chạy."
    else
        echo "🚀 Đang khởi động Cloudflare Tunnel..."
        nohup cloudflared tunnel run fourt-api > logs/tunnel.log 2>&1 &
        TUNNEL_PID=$!
        # Chờ xíu để nó start
        sleep 2
        echo "✅ Tunnel đã khởi động (PID: $TUNNEL_PID). Log: logs/tunnel.log"
    fi
}

stop_tunnel() {
    if [ -n "$TUNNEL_PID" ]; then
        echo "Đang dừng Tunnel (PID: $TUNNEL_PID)..."
        kill $TUNNEL_PID 2>/dev/null
    fi
    # Kill all leftovers just in case
    pkill -f "cloudflared tunnel run fourt-api" 2>/dev/null
}

# Hàm chạy server
run_server() {
    # Kiểm tra sự tồn tại của file app/main.py
    if [ -f "run_server.py" ] || [ -f "app/main.py" ]; then
        echo ""
        echo "=========================================="
        echo "  🚀 Đang chạy FastAPI Server..."
        echo "=========================================="
        echo "  Phím tắt:"
        echo "    R - Restart server"
        echo "    Q - Quit (thoát)"
        echo "=========================================="
        echo ""
        python3 -m app.main &
        SERVER_PID=$!
        return 0
    else
        echo "Lỗi: Không tìm thấy file app/main.py trong thư mục hiện tại."
        return 1
    fi
}

# Hàm dừng server
stop_server() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo ""
        echo "Đang dừng server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
        echo "Server đã dừng."
    fi
}

# Trap để cleanup khi script bị kill
# Trap để cleanup khi script bị kill
trap 'stop_server; stop_tunnel; exit 0' SIGINT SIGTERM

# Dọn dẹp cache lần đầu
cleanup_cache

# Chạy tunnel
run_tunnel

# Chạy server lần đầu
if ! run_server; then
    exit 1
fi

# Vòng lặp chính để lắng nghe phím tắt
echo ""
echo "Nhấn R để restart, Q để quit..."
while true; do
    # Đọc một ký tự từ input
    read -rsn1 key
    
    case "$key" in
        r|R)
            echo ""
            echo "🔄 Đang restart server..."
            stop_server
            cleanup_cache
            run_server
            echo ""
            echo "Nhấn R để restart, Q để quit..."
            ;;
        q|Q)
            echo ""
            echo "👋 Đang thoát..."
            echo "👋 Đang thoát..."
            stop_server
            stop_tunnel
            echo "Goodbye!"
            exit 0
            ;;
        *)
            # Kiểm tra xem server còn chạy không
            if ! kill -0 $SERVER_PID 2>/dev/null; then
                echo ""
                echo "⚠️  Server đã dừng bất ngờ. Nhấn R để restart hoặc Q để quit."
            fi
            ;;
    esac
done
