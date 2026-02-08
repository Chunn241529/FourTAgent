import sqlite3
import os

DB_PATH = "server.db"
# Try commonly used paths if not found in root
if not os.path.exists(DB_PATH):
    paths = ["app/server.db", "mobile_app/server.db", "data/server.db"]
    for p in paths:
        if os.path.exists(p):
            DB_PATH = p
            break

print(f"Checking database at {DB_PATH}")

if os.path.exists(DB_PATH):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check columns
    try:
        cursor.execute("PRAGMA table_info(chat_messages)")
        columns = [info[1] for info in cursor.fetchall()]
        print(f"Existing columns: {columns}")

        if "generated_images" not in columns:
            print("Adding generated_images column...")
            cursor.execute("ALTER TABLE chat_messages ADD COLUMN generated_images JSON")
        else:
            print("generated_images column exists.")

        if "thinking" not in columns:
            print("Adding thinking column...")
            cursor.execute("ALTER TABLE chat_messages ADD COLUMN thinking TEXT")
        else:
            print("thinking column exists.")

        if "deep_search_updates" not in columns:
            print("Adding deep_search_updates column...")
            cursor.execute(
                "ALTER TABLE chat_messages ADD COLUMN deep_search_updates JSON"
            )
        else:
            print("deep_search_updates column exists.")

        # Check for Canvas table
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='canvas'"
        )
        if not cursor.fetchone():
            print("Creating canvas table...")
            cursor.execute(
                """
                CREATE TABLE canvas (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    title VARCHAR,
                    content VARCHAR,
                    type VARCHAR DEFAULT 'markdown',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            """
            )
        else:
            print("Canvas table exists.")

        conn.commit()
    except Exception as e:
        print(f"Error during migration: {e}")
    finally:
        conn.close()
    print("Migration check complete.")
else:
    print("Database file not found!")
