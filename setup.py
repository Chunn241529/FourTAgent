import subprocess
import sys
import os
import platform
import argparse
import re

# --- Cấu hình ---
VENV_DIR = ".venv"
PYTHON_MIN_VERSION = (3, 8)

def run_command(command, check=True, cwd=None, capture_output=False):
    """Thực thi một lệnh shell và xử lý lỗi nếu có. Hỗ trợ capture output."""
    try:
        print(f"Đang chạy lệnh: {' '.join(command)}")
        result = subprocess.run(command, check=check, shell=False, cwd=cwd or os.getcwd(), capture_output=capture_output, text=True)
        if capture_output:
            return result.stdout.strip() if result.returncode == 0 else None
        return True
    except subprocess.CalledProcessError as e:
        if capture_output:
            return None
        print(f"LỖI: Lệnh {' '.join(command)} thất bại với mã lỗi {e.returncode}")
        return False
    except FileNotFoundError:
        if capture_output:
            return None
        print(f"LỖI: Không tìm thấy lệnh '{command[0]}'. Hãy đảm bảo nó đã được cài đặt và có trong PATH.")
        return False
    return True

def get_python_executable(venv_path):
    """Lấy đường dẫn đến file thực thi python trong venv cho HĐH hiện tại."""
    if platform.system() == "Windows":
        return os.path.join(venv_path, "Scripts", "python.exe")
    else: # Linux, macOS, etc.
        return os.path.join(venv_path, "bin", "python")

def detect_cuda_version():
    """Phát hiện phiên bản CUDA từ nvidia-smi."""
    try:
        output = run_command(["nvidia-smi"], capture_output=True)
        if output:
            # Tìm phiên bản CUDA trong output, ví dụ: CUDA Version: 12.1
            match = re.search(r'CUDA Version:\s*(\d+\.\d+)', output)
            if match:
                cuda_ver = match.group(1)
                major_minor = cuda_ver.replace('.', '')  # e.g., 12.1 -> 121
                if major_minor in ['118', '121', '130']:
                    return f'cuda{major_minor}'
                elif float(cuda_ver) >= 12.1:
                    return 'cuda121'  # Mặc định cho CUDA >=12.1
                elif float(cuda_ver) >= 11.8:
                    return 'cuda118'
                else:
                    print(f"Cảnh báo: Phiên bản CUDA {cuda_ver} không được hỗ trợ trực tiếp, sử dụng CPU.")
                    return 'cpu'
        print("Không phát hiện NVIDIA GPU hoặc nvidia-smi không khả dụng, sử dụng CPU.")
        return 'cpu'
    except Exception as e:
        print(f"Lỗi khi phát hiện CUDA: {e}. Sử dụng CPU.")
        return 'cpu'

def main():
    """Hàm chính để thiết lập môi trường và cài đặt dependencies."""
    parser = argparse.ArgumentParser(
        description="Script cài đặt môi trường cho dự án.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        '--pytorch', 
        default='auto',
        choices=['auto', 'cpu', 'cuda118', 'cuda121', 'cuda130'],
        help="Chọn phiên bản PyTorch để cài đặt:\n"
             "  - auto:    Tự động tìm phiên bản tốt nhất (kiểm tra GPU và CUDA).\n"
             "  - cpu:     Chỉ cài đặt phiên bản cho CPU.\n"
             "  - cuda118: Cài đặt cho NVIDIA GPU với CUDA 11.8.\n"
             "  - cuda121: Cài đặt cho NVIDIA GPU với CUDA 12.1 (khuyên dùng cho driver mới)."
    )
    parser.add_argument(
        '--skip-requirements',
        action='store_true',
        help="Bỏ qua cài đặt requirements.txt nếu có lỗi"
    )
    args = parser.parse_args()

    # Lấy đường dẫn tuyệt đối của thư mục hiện tại
    current_dir = os.path.abspath(os.getcwd())
    venv_full_path = os.path.join(current_dir, VENV_DIR)
    
    print(f"Thiết lập môi trường tại: {current_dir}")
    print(f"Virtual environment sẽ được tạo tại: {venv_full_path}")

    # 1. Kiểm tra phiên bản Python
    if sys.version_info < PYTHON_MIN_VERSION:
        print(f"Yêu cầu Python {PYTHON_MIN_VERSION[0]}.{PYTHON_MIN_VERSION[1]} trở lên.")
        sys.exit(1)
    
    print("Bắt đầu quá trình cài đặt môi trường...")

    # 2. Tạo/Kiểm tra virtual environment
    if not os.path.exists(venv_full_path):
        print(f"Đang tạo virtual environment tại '{venv_full_path}'...")
        if not run_command([sys.executable, "-m", "venv", venv_full_path]):
            sys.exit(1)
    else:
        print(f"Virtual environment đã tồn tại tại '{venv_full_path}'")
    
    python_in_venv = get_python_executable(venv_full_path)
    
    if not os.path.exists(python_in_venv):
        print(f"LỖI: Không tìm thấy file thực thi Python tại '{python_in_venv}'.")
        sys.exit(1)

    print(f"Sử dụng Python interpreter từ: {python_in_venv}")

    # 3. Cập nhật pip
    print("\nĐang cập nhật pip...")
    if not run_command([python_in_venv, "-m", "pip", "install", "--upgrade", "pip"]):
        print("Cảnh báo: Không thể cập nhật pip, tiếp tục cài đặt...")

    # 4. Cài đặt các thư viện từ requirements.txt (nếu có)
    requirements_file = os.path.join(current_dir, "requirements.txt")
    if os.path.exists(requirements_file) and not args.skip_requirements:
        print(f"\nĐang cài đặt các thư viện từ {requirements_file}...")
        if not run_command([python_in_venv, "-m", "pip", "install", "-r", requirements_file], check=False):
            print("⚠️  Có lỗi khi cài đặt requirements.txt")
            print("Nguyên nhân có thể do xung đột phiên bản giữa các package")
            print("Thử cài đặt từng package quan trọng thủ công...")
            
            # Thử cài đặt các package cơ bản
            basic_packages = ["numpy", "pillow", "opencv-python", "requests"]
            for package in basic_packages:
                print(f"Thử cài đặt {package}...")
                run_command([python_in_venv, "-m", "pip", "install", package], check=False)
    else:
        if args.skip_requirements:
            print(f"\nBỏ qua cài đặt requirements.txt theo lựa chọn")
        else:
            print(f"\nKhông tìm thấy {requirements_file}, bỏ qua bước cài đặt requirements")

    # 5. Cài đặt PyTorch theo lựa chọn
    print(f"\nĐang cài đặt PyTorch (phiên bản đã chọn: {args.pytorch})...")
    
    base_command = [python_in_venv, "-m", "pip", "install", "torch", "torchvision", "torchaudio"]
    
    if args.pytorch == 'auto':
        detected = detect_cuda_version()
        print(f"Phát hiện hệ thống: {detected}")
        args.pytorch = detected  # Cập nhật args để sử dụng dưới
    
    if args.pytorch == 'cuda121':
        install_command = base_command + ["--index-url", "https://download.pytorch.org/whl/cu121"]
    elif args.pytorch == 'cuda118':
        install_command = base_command + ["--index-url", "https://download.pytorch.org/whl/cu118"]
    elif args.pytorch == 'cuda130':
        install_command = base_command + ["--index-url", "https://download.pytorch.org/whl/cu130"]
    elif args.pytorch == 'cpu':
        install_command = base_command + ["--index-url", "https://download.pytorch.org/whl/cpu"]
    else:  # fallback nếu auto thất bại
        install_command = base_command

    if not run_command(install_command):
        print("⚠️  Có lỗi khi cài đặt PyTorch, thử cài đặt không指定 version...")
        run_command([python_in_venv, "-m", "pip", "install", "torch", "torchvision", "torchaudio"], check=False)

    # 6. Cài đặt Playwright Chromium (cho Affiliate Scraper)
    print("\nĐang cài đặt Playwright Chromium browser...")
    if not run_command([python_in_venv, "-m", "playwright", "install", "chromium"], check=False):
        print("⚠️  Không thể cài đặt Playwright Chromium. Bạn có thể cài thủ công:")
        print(f"   {python_in_venv} -m playwright install chromium")
    
    print("\n✅ Quá trình cài đặt hoàn tất!")
    print(f"Môi trường đã được thiết lập tại: {current_dir}")
    print(f"Để kích hoạt môi trường ảo, hãy chạy lệnh sau:")
    if platform.system() == "Windows":
        print(f"   .\\{VENV_DIR}\\Scripts\\activate")
    else:
        print(f"   source {VENV_DIR}/bin/activate")
    
    print("\n📝 Lưu ý: Nếu có package bị lỗi, bạn có thể:")
    print("   1. Chạy lại với: python setup.py --skip-requirements")
    print("   2. Cài đặt thủ công các package bị thiếu")
    print("   3. Kiểm tra lại file requirements.txt")

if __name__ == "__main__":
    main()
