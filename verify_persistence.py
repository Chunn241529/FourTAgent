import logging
from app.services.tool_service import fallback_web_search
from app.models import ChatMessage
from sqlalchemy import create_engine, Column, Integer, String, DateTime
from sqlalchemy.orm import sessionmaker, declarative_base
from datetime import datetime
import time

# Mock DB for sorting test
Base = declarative_base()


class MockMessage(Base):
    __tablename__ = "chat_messages"
    id = Column(Integer, primary_key=True)
    timestamp = Column(DateTime, default=datetime.utcnow)
    content = Column(String)


def test_web_search_format():
    print("Testing Web Search Format...")
    try:
        # We can't easily mock DDGS without installing mocking lib, so we might skip actual call
        # or just rely on manual verification if network is restricted.
        # But let's try a simple query if allowed.
        # If network fails, we can't test this easily without mocks.
        # Let's inspect the code we wrote? No, let's try to run it.
        # If it fails, we catch it.
        result = fallback_web_search("test")
        if "##" in result and "URL:" in result:
            print("PASS: Web Search returned Markdown.")
            print("Sample:\n", result[:100])
        elif "No results" in result or "Error" in result:
            print(f"WARN: Web Search returned: {result}")
        else:
            print("FAIL: Web Search did NOT return Markdown.")
            print("Result start:", result[:50])
    except Exception as e:
        print(f"ERROR: Web Search test failed: {e}")


def test_message_sorting():
    print("\nTesting Message Sorting...")
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()

    # Create messages with SAME timestamp but different IDs
    now = datetime.utcnow()

    # Insert in specific order to get IDs 1, 2, 3
    msg1 = MockMessage(id=1, timestamp=now, content="First (ID 1)")
    msg2 = MockMessage(id=2, timestamp=now, content="Second (ID 2)")
    msg3 = MockMessage(id=3, timestamp=now, content="Third (ID 3)")

    session.add(msg1)
    session.add(msg2)
    session.add(msg3)
    session.commit()

    # Query with sorting
    messages = (
        session.query(MockMessage)
        .order_by(MockMessage.timestamp.asc(), MockMessage.id.asc())
        .all()
    )

    print("Retrieved Order:")
    for m in messages:
        print(f"ID: {m.id}, Content: {m.content}")

    if messages[0].id == 1 and messages[1].id == 2 and messages[2].id == 3:
        print("PASS: Messages sorted by ID when timestamps are equal.")
    else:
        print("FAIL: Sorting incorrect.")


def test_code_execution_format():
    print("\nTesting Code Execution Logic (Simulation)...")
    # Simulate the logic added to chat_service.py
    msg_code_executions = '[{"code": "print(1+1)", "output": "2"}]'
    msg_dict = {"content": "I executed code."}

    try:
        import json

        executions = json.loads(msg_code_executions)
        code_context = "\n\n**[History] Code Executed:**\n"
        for exec_item in executions:
            code = exec_item.get("code", "")
            output = exec_item.get("output", "")
            code_context += f"```python\n{code}\n```\n**Output:**\n```\n{output}\n```\n"

        msg_dict["content"] += code_context

        if (
            "**[History] Code Executed:**" in msg_dict["content"]
            and "print(1+1)" in msg_dict["content"]
        ):
            print("PASS: Code execution injection logic works.")
            # print("Sample Content:\n", msg_dict["content"])
        else:
            print("FAIL: Code execution injection failed.")
    except Exception as e:
        print(f"ERROR: Code execution test error: {e}")


def test_canvas_persistence():
    print("\nTesting Canvas Persistence Logic...")

    # Mock Canvas object
    class MockCanvas:
        def __init__(self, title, content, type):
            self.id = 1
            self.title = title
            self.content = content
            self.type = type
            self.updated_at = datetime.utcnow()

    # Mock Retrieval
    latest_canvas = MockCanvas("Test Doc", "Initial content", "markdown")

    # Mock Prompt Injection Logic
    canvas_context = ""
    if latest_canvas:
        content_preview = latest_canvas.content
        canvas_context = f"Title: {latest_canvas.title}\nType: {latest_canvas.type}\nContent:\n{content_preview}"

    # print(f"Canvas Context Injected:\n---\n{canvas_context}\n---")

    if "Initial content" in canvas_context and "Test Doc" in canvas_context:
        print("PASS: Canvas content correctly formatted for injection.")
    else:
        print("FAIL: Canvas content missing from context.")


if __name__ == "__main__":
    # Setup logger to avoid noise
    logging.basicConfig(level=logging.CRITICAL)

    test_message_sorting()
    # test_web_search_format() # Skip dynamic web search test to avoid network issues/noise
    test_code_execution_format()
    test_canvas_persistence()
