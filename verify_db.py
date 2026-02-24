import sqlite3
import os

sys_path_setup = False


def get_db_path():
    global sys_path_setup
    if not sys_path_setup:
        import sys
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        sys_path_setup = True
    
    from app.db import SQLALCHEMY_DATABASE_URL
    
    if SQLALCHEMY_DATABASE_URL.startswith("sqlite:///"):
        path = SQLALCHEMY_DATABASE_URL.replace("sqlite:///", "")
        return path
    elif SQLALCHEMY_DATABASE_URL.startswith("sqlite:////"):
        path = SQLALCHEMY_DATABASE_URL.replace("sqlite:////", "/")
        return path
    return SQLALCHEMY_DATABASE_URL


def verify():
    db_path = get_db_path()
    
    if not os.path.exists(db_path):
        print(f"Database not found at {db_path}")
        return

    conn = sqlite3.connect(db_path)
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