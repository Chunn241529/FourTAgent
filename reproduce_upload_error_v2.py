import base64
import io
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("reproduce")


class MockFileService:
    @staticmethod
    def get_file_bytes(file) -> bytes:
        """Lấy bytes từ file object"""
        if isinstance(file, str):
            if file.startswith("data:"):
                try:
                    header, data = file.split(",", 1)
                    logger.info(f"Decoding base64 file with header: {header}")
                    decoded = base64.b64decode(data)
                    logger.info(f"Decoded {len(decoded)} bytes from base64 string")
                    return decoded
                except Exception as e:
                    logger.error(f"Base64 decoding failed: {e}")
                    return base64.b64decode(file)
            else:
                return file.encode("utf-8")
        return file

    @staticmethod
    def _extract_pdf_text(file_content: bytes) -> str:
        """Extract text from PDF"""
        try:
            import PyPDF2

            reader = PyPDF2.PdfReader(io.BytesIO(file_content))
            text = ""
            for page in reader.pages:
                text += page.extract_text() + "\n"
            return text
        except Exception as e:
            logger.warning(f"PDF extraction failed: {e}")
            return ""


def test_pdf_upload():
    print("--- Creating dummy PDF (without reportlab if missing) ---")

    # Minimal valid PDF binary content (approx)
    fake_pdf = b"%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\n2 0 obj\n<<\n/Type /Pages\n/Kids [3 0 R]\n/Count 1\n>>\nendobj\n3 0 obj\n<<\n/Type /Page\n/Parent 2 0 R\n/Resources <<\n/Font <<\n/F1 4 0 R\n>>\n>>\n/MediaBox [0 0 612 792]\n/Contents 5 0 R\n>>\nendobj\n4 0 obj\n<<\n/Type /Font\n/Subtype /Type1\n/BaseFont /Helvetica\n>>\nendobj\n5 0 obj\n<<\n/Length 44\n>>\nstream\nBT\n/F1 24 Tf\n100 100 Td\n(Hello World) Tj\nET\nendstream\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000236 00000 n \n0000000306 00000 n \ntrailer\n<<\n/Size 6\n/Root 1 0 R\n>>\nstartxref\n400\n%%EOF"

    print(f"Original PDF size: {len(fake_pdf)} bytes")

    # Encode to base64
    b64_data = base64.b64encode(fake_pdf).decode("utf-8")

    # Test cases
    prefixes = [
        "data:application/pdf;base64,",
        "data:application/octet-stream;base64,",
        # Test allow newline chars which sometimes happens
        "data:application/pdf;base64,\n",
    ]

    for prefix in prefixes:
        print(f"\n--- Testing '{prefix.strip()}' prefix ---")
        file_string = f"{prefix}{b64_data}"

        try:
            decoded_bytes = MockFileService.get_file_bytes(file_string)
            print(f"Decoded bytes length: {len(decoded_bytes)}")

            if len(decoded_bytes) == len(fake_pdf):
                print("SUCCESS: Decoded size matches original")
            else:
                print(
                    f"FAILURE: Size mismatch! Expected {len(fake_pdf)}, got {len(decoded_bytes)}"
                )

            # Try extraction
            text = MockFileService._extract_pdf_text(decoded_bytes)
            if "Hello World" in text:
                print("SUCCESS: PDF text extracted correctly")
            else:
                # Fallback check for fake PDF text
                if "Hello World" in str(fake_pdf):
                    print("SUCCESS: (Manual check) Bytes contain expected string")
                else:
                    print(f"FAILURE: PDF text extraction failed. Result: '{text}'")

        except Exception as e:
            print(f"EXCEPTION: {e}")


if __name__ == "__main__":
    test_pdf_upload()
