import base64
import io
import logging
from app.services.file_service import FileService

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_dummy_pdf():
    from reportlab.pdfgen import canvas

    buffer = io.BytesIO()
    c = canvas.Canvas(buffer)
    c.drawString(100, 750, "Hello World")
    c.save()
    return buffer.getvalue()


def test_pdf_upload():
    print("--- Creating dummy PDF ---")
    pdf_bytes = create_dummy_pdf()
    print(f"Original PDF size: {len(pdf_bytes)} bytes")

    # Encode to base64
    b64_data = base64.b64encode(pdf_bytes).decode("utf-8")
    # Add prefix similar to Flutter client
    # Note: Flutter client sends 'data:application/pdf;base64,...'
    # Only if it detects extension. Default fallback is application/octet-stream

    file_string_pdf = f"data:application/pdf;base64,{b64_data}"
    file_string_generic = f"data:application/octet-stream;base64,{b64_data}"

    print("\n--- Testing 'application/pdf' prefix ---")
    try:
        decoded_bytes = FileService.get_file_bytes(file_string_pdf)
        print(f"Decoded bytes length: {len(decoded_bytes)}")

        if len(decoded_bytes) == len(pdf_bytes):
            print("SUCCESS: Decoded size matches original")
        else:
            print(
                f"FAILURE: Size mismatch! Expected {len(pdf_bytes)}, got {len(decoded_bytes)}"
            )

        # Try extraction
        text = FileService._extract_pdf_text(decoded_bytes)
        if "Hello World" in text:
            print("SUCCESS: PDF text extracted correctly")
        else:
            print(f"FAILURE: PDF text extraction failed. Result: '{text}'")

    except Exception as e:
        print(f"EXCEPTION: {e}")

    print("\n--- Testing 'application/octet-stream' prefix ---")
    try:
        decoded_bytes = FileService.get_file_bytes(file_string_generic)
        print(f"Decoded bytes length: {len(decoded_bytes)}")

        if len(decoded_bytes) == len(pdf_bytes):
            print("SUCCESS: Decoded size matches original")
        else:
            print(
                f"FAILURE: Size mismatch! Expected {len(pdf_bytes)}, got {len(decoded_bytes)}"
            )

        text = FileService._extract_pdf_text(decoded_bytes)
        if "Hello World" in text:
            print("SUCCESS: PDF text extracted correctly")
        else:
            print(f"FAILURE: PDF text extraction failed. Result: '{text}'")

    except Exception as e:
        print(f"EXCEPTION: {e}")


if __name__ == "__main__":
    try:
        import reportlab

        test_pdf_upload()
    except ImportError:
        print("reportlab not installed, creating simple fake PDF header")
        # Minimal valid PDF header/trailer structure usually needed for PyPDF2
        # But PyPDF2 is strict. Let's just test bytes preservation if reportlab missing.
        fake_pdf = b"%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\n2 0 obj\n<<\n/Type /Pages\n/Kids [3 0 R]\n/Count 1\n>>\nendobj\n3 0 obj\n<<\n/Type /Page\n/Parent 2 0 R\n/Resources <<\n/Font <<\n/F1 4 0 R\n>>\n>>\n/MediaBox [0 0 612 792]\n/Contents 5 0 R\n>>\nendobj\n4 0 obj\n<<\n/Type /Font\n/Subtype /Type1\n/BaseFont /Helvetica\n>>\nendobj\n5 0 obj\n<<\n/Length 44\n>>\nstream\nBT\n/F1 24 Tf\n100 100 Td\n(Hello World) Tj\nET\nendstream\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000236 00000 n \n0000000306 00000 n \ntrailer\n<<\n/Size 6\n/Root 1 0 R\n>>\nstartxref\n400\n%%EOF"

        b64_data = base64.b64encode(fake_pdf).decode("utf-8")
        file_string = f"data:application/pdf;base64,{b64_data}"

        decoded = FileService.get_file_bytes(file_string)
        print(f"Decoded size: {len(decoded)}. Original: {len(fake_pdf)}")
        if decoded == fake_pdf:
            print("SUCCESS: Bytes match")
        else:
            print("FAILURE: Bytes mismatch")

        text = FileService._extract_pdf_text(decoded)
        print(f"Extraction result: {text}")
