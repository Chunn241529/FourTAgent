import sqlite3
import os
import re

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


def migrate():
    db_path = get_db_path()
    
    if not os.path.exists(db_path):
        print(f"Database not found at {db_path}")
        return

    print(f"Migrating database at {db_path}...")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
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