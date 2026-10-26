"""
init_db.py
Creates smartbus.db (SQLite) using schema.sql for the
SmartBus Guardian mini project.

Run this once from the Flask backend project root:
    python init_db.py
"""

import sqlite3
import os

DB_NAME = "smartbus.db"
SCHEMA_FILE = "schema.sql"


def init_db():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    db_path = os.path.join(base_dir, DB_NAME)
    schema_path = os.path.join(base_dir, SCHEMA_FILE)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    with open(schema_path, "r") as f:
        cursor.executescript(f.read())

    conn.commit()

    # Verify tables were created
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall() if not row[0].startswith("sqlite_")]

    conn.close()

    print(f"Database created at: {db_path}")
    print(f"Tables created ({len(tables)}):")
    for t in tables:
        print(f"  - {t}")


if __name__ == "__main__":
    init_db()