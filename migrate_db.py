import sqlite3
import os

DB_PATH = "server.db"


def migrate():
    if not os.path.exists(DB_PATH):
        print(f"Database not found at {DB_PATH}")
        return

    print(f"Migrating database at {DB_PATH}...")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        # Check if avatar column exists in users table
        cursor.execute("PRAGMA table_info(users)")
        columns = [info[1] for info in cursor.fetchall()]

        if "avatar" not in columns:
            print("Adding 'avatar' column to 'users' table...")
            cursor.execute("ALTER TABLE users ADD COLUMN avatar TEXT")
            conn.commit()
            print("Migration successful: 'avatar' column added.")
        else:
            print("'avatar' column already exists.")

        if "full_name" not in columns:
            print("Adding 'full_name' column to 'users' table...")
            cursor.execute("ALTER TABLE users ADD COLUMN full_name TEXT")
            conn.commit()
            print("Migration successful: 'full_name' column added.")
        else:
            print("'full_name' column already exists.")

    except Exception as e:
        print(f"Migration failed: {e}")
        conn.rollback()
    finally:
        conn.close()


if __name__ == "__main__":
    migrate()
