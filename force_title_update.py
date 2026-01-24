import sys
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Hardcode DB path
SQLALCHEMY_DATABASE_URL = "sqlite:///./server.db"


def force_update():
    # Import app modules locally
    sys.path.append(os.getcwd())
    try:
        from app.models import Conversation

        # Verify if model has title
        if not hasattr(Conversation, "title"):
            print("ERROR: Conversation model does NOT have 'title' attribute!")
            return

        print("Conversation model has 'title' attribute.")

        engine = create_engine(SQLALCHEMY_DATABASE_URL)
        SessionLocal = sessionmaker(bind=engine)
        db = SessionLocal()

        # Get first conversation
        conv = db.query(Conversation).first()
        if not conv:
            print("No conversations found.")
            return

        print(f"Updating Conversation ID {conv.id}...")
        conv.title = "Forced Title Update"
        db.commit()

        # Verify
        db.refresh(conv)
        print(f"Title after update: '{conv.title}'")

        if conv.title == "Forced Title Update":
            print("SUCCESS: Persistence working via script.")
        else:
            print("FAILURE: Persistence failed via script.")

    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    force_update()
