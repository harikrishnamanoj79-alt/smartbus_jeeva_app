"""
init_db.py
Creates and migrates smartbus.db (SQLite) using schema.sql for the
SmartBus Guardian project.

Run this from the Flask backend directory:
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
    conn.execute("PRAGMA foreign_keys = OFF;")
    cursor = conn.cursor()

    with open(schema_path, "r", encoding="utf-8") as f:
        cursor.executescript(f.read())

    # Migration checks for existing databases:
    # 1. Ensure duration_seconds in tbl_journey_history
    try:
        cursor.execute("ALTER TABLE tbl_journey_history ADD COLUMN duration_seconds INTEGER DEFAULT 0;")
    except sqlite3.OperationalError:
        pass  # Column already exists

    # 2. Check if tbl_sos_alert allows NULL journey_id
    cursor.execute("PRAGMA table_info(tbl_sos_alert);")
    columns = {row[1]: row[3] for row in cursor.fetchall()}  # name: notnull
    if columns.get("journey_id") == 1:
        # journey_id is NOT NULL, recreate table to allow NULL
        cursor.executescript("""
            CREATE TABLE IF NOT EXISTS tbl_sos_alert_new (
                sos_id      INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id     INTEGER NOT NULL,
                journey_id  INTEGER,
                latitude    REAL NOT NULL,
                longitude   REAL NOT NULL,
                sent_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
                status      TEXT DEFAULT 'SENT'
                    CHECK (status IN ('SENT', 'DELIVERED', 'FAILED')),
                FOREIGN KEY (user_id) REFERENCES tbl_users (user_id)
                    ON DELETE CASCADE,
                FOREIGN KEY (journey_id) REFERENCES tbl_journey (journey_id)
                    ON DELETE SET NULL
            );
            INSERT INTO tbl_sos_alert_new (sos_id, user_id, journey_id, latitude, longitude, sent_at, status)
                SELECT sos_id, user_id, journey_id, latitude, longitude, sent_at, status FROM tbl_sos_alert;
            DROP TABLE tbl_sos_alert;
            ALTER TABLE tbl_sos_alert_new RENAME TO tbl_sos_alert;
            CREATE INDEX IF NOT EXISTS idx_sos_user ON tbl_sos_alert(user_id);
        """)

    conn.commit()
    conn.execute("PRAGMA foreign_keys = ON;")

    # Verify tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall() if not row[0].startswith("sqlite_")]
    conn.close()

    print(f"Database initialized at: {db_path}")
    print(f"Tables present ({len(tables)}):")
    for t in tables:
        print(f"  - {t}")


if __name__ == "__main__":
    init_db()
