import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db import SessionLocal
from app.models import Conversation


def force_update():
    db = SessionLocal()
    try:
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
    finally:
        db.close()


if __name__ == "__main__":
    force_update()
