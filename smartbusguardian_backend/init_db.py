"""
init_db.py
Creates and migrates smartbus.db (SQLite) using schema.sql for the
SmartBus Guardian project.

Run this from the Flask backend directory:
    python init_db.py
"""

import sqlite3
import os
import shutil
import time

DB_NAME = "smartbus.db"
SCHEMA_FILE = "schema.sql"


def init_db():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    db_path = os.path.join(base_dir, DB_NAME)
    schema_path = os.path.join(base_dir, SCHEMA_FILE)

    # Backup existing database before running migrations
    if os.path.exists(db_path) and os.path.getsize(db_path) > 0:
        backup_path = f"{db_path}.backup_{int(time.time())}"
        try:
            shutil.copy2(db_path, backup_path)
            print(f"[Backup] Existing database safely backed up to: {backup_path}")
        except Exception as e:
            print(f"[Backup Warning] Could not create backup before migration: {e}")

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
        print("[Migration] Migrating tbl_sos_alert: making journey_id nullable...")
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

    # 3. Migrate unique constraints for existing databases via unique indexes
    try:
        cursor.execute("""
            SELECT user_id, contact_phone, COUNT(*) as cnt
            FROM tbl_emergency_contact
            GROUP BY user_id, contact_phone
            HAVING cnt > 1;
        """)
        dupe_contacts = cursor.fetchall()
        if dupe_contacts:
            print(f"[Migration] Found {len(dupe_contacts)} duplicate contact group(s). Retaining oldest rows:")
            for row in dupe_contacts:
                print(f"  - User {row[0]}: phone {row[1]} ({row[2]} copies)")
            cursor.execute("""
                DELETE FROM tbl_emergency_contact
                WHERE contact_id NOT IN (
                    SELECT MIN(contact_id) FROM tbl_emergency_contact GROUP BY user_id, contact_phone
                );
            """)
        cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_user_contact_phone ON tbl_emergency_contact(user_id, contact_phone);")
    except sqlite3.OperationalError:
        pass

    try:
        cursor.execute("""
            SELECT user_id, destination_name, COUNT(*) as cnt
            FROM tbl_saved_destinations
            GROUP BY user_id, destination_name
            HAVING cnt > 1;
        """)
        dupe_destinations = cursor.fetchall()
        if dupe_destinations:
            print(f"[Migration] Found {len(dupe_destinations)} duplicate destination group(s). Retaining oldest rows:")
            for row in dupe_destinations:
                print(f"  - User {row[0]}: destination '{row[1]}' ({row[2]} copies)")
            cursor.execute("""
                DELETE FROM tbl_saved_destinations
                WHERE destination_id NOT IN (
                    SELECT MIN(destination_id) FROM tbl_saved_destinations GROUP BY user_id, destination_name
                );
            """)
        cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_user_destination ON tbl_saved_destinations(user_id, destination_name);")
    except sqlite3.OperationalError:
        pass

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
