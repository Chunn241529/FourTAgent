import sqlite3
import os

DB_PATH = "server.db"


def verify():
    if not os.path.exists(DB_PATH):
        print(f"Database not found at {DB_PATH}")
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("PRAGMA table_info(users)")
        columns = [info[1] for info in cursor.fetchall()]

        if "avatar" in columns:
            print("VERIFICATION SUCCESS: 'avatar' column exists in 'users' table.")
        else:
            print("VERIFICATION FAILED: 'avatar' column MISSING in 'users' table.")

    except Exception as e:
        print(f"Verification failed: {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    verify()
