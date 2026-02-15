import sqlite3
import os

DB_PATH = "server.db"


def migrate():
    if not os.path.exists(DB_PATH):
        print(f"Database {DB_PATH} not found.")
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # Check if column exists
        cursor.execute("PRAGMA table_info(users)")
        columns = [info[1] for info in cursor.fetchall()]

        if "phone_number" not in columns:
            print("Adding phone_number column to users table...")
            cursor.execute("ALTER TABLE users ADD COLUMN phone_number TEXT")
            conn.commit()
            print("Migration successful: phone_number added.")
        else:
            print("Column phone_number already exists.")

    except Exception as e:
        print(f"Migration failed: {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    migrate()
