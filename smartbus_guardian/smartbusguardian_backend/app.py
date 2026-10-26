"""
SmartBus Guardian Flask Backend

Flutter → Flask → SQLite
"""

from flask import Flask, request, jsonify, g
import sqlite3
import os
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)

@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
    return response


@app.route("/<path:path>", methods=["OPTIONS"])
def handle_preflight(path):
    return "", 204


DB_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "smartbus.db"
)


# ============================================================
# HOME
# ============================================================

@app.route("/")
def home():
    return jsonify({
        "message": "SmartBus Guardian Backend is running!"
    })


# ============================================================
# DATABASE
# ============================================================

def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON;")

    return g.db


@app.teardown_appcontext
def close_db(exception=None):
    db = g.pop("db", None)

    if db is not None:
        db.close()


# ============================================================
# REGISTER
# ============================================================

@app.route("/api/register", methods=["POST"])
def register_user():

    data = request.get_json(silent=True)

    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    full_name = data.get("full_name", "")
    email = data.get("email", "")
    phone_number = data.get("phone_number", "")
    password = data.get("password", data.get("password_hash", ""))

    if not all(isinstance(value, str) for value in
               (full_name, email, phone_number, password)):
        return jsonify({"error": "All registration fields must be text"}), 400

    full_name = full_name.strip()
    email = email.strip().lower()
    phone_number = phone_number.strip()
    password = password.strip()

    if not full_name:
        return jsonify({
            "error": "Full name is required"
        }), 400

    if not email:
        return jsonify({
            "error": "Email is required"
        }), 400

    if not phone_number:
        return jsonify({
            "error": "Phone number is required"
        }), 400

    if not password:
        return jsonify({
            "error": "Password is required"
        }), 400
    if len(password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400

    db = get_db()

    try:

        cur = db.execute(
            """
            INSERT INTO tbl_users
            (
                full_name,
                email,
                phone_number,
                password_hash
            )
            VALUES (?, ?, ?, ?)
            """,
            (
                full_name,
                email,
                phone_number,
                generate_password_hash(password)
            )
        )

        db.commit()

        return jsonify({
            "success": True,
            "user_id": cur.lastrowid,
            "message": "User registered successfully"
        }), 201

    except sqlite3.IntegrityError as e:

        return jsonify({
            "success": False,
            "error": str(e)
        }), 400


# ============================================================
# LOGIN
# ============================================================

@app.route("/api/login", methods=["POST"])
def login_user():

    data = request.get_json(silent=True)

    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    identifier = data.get("identifier", "")
    password = data.get("password", data.get("password_hash", ""))
    if not isinstance(identifier, str) or not isinstance(password, str):
        return jsonify({"error": "Email/phone and password must be text"}), 400
    identifier = identifier.strip()
    password = password.strip()

    if not identifier:
        return jsonify({
            "error": "Email or phone number is required"
        }), 400

    if not password:
        return jsonify({
            "error": "Password is required"
        }), 400

    db = get_db()

    row = db.execute(
        """
        SELECT
            user_id,
            full_name,
            email,
            phone_number,
            password_hash
        FROM tbl_users
        WHERE email = ? OR phone_number = ?
        """,
        (
            identifier.lower(),
            identifier
        )
    ).fetchone()

    if row:
        stored_password = row["password_hash"]
        try:
            password_matches = check_password_hash(stored_password, password)
        except (ValueError, TypeError):
            password_matches = False

        if not password_matches and stored_password == password:
            password_matches = True
            db.execute(
                "UPDATE tbl_users SET password_hash = ? WHERE user_id = ?",
                (generate_password_hash(password), row["user_id"]),
            )
            db.commit()

    else:
        password_matches = False

    if row and password_matches:

        return jsonify({
            "success": True,
            "message": "Login successful",
            "user": {
                "id": row["user_id"],
                "user_id": row["user_id"],
                "full_name": row["full_name"],
                "email": row["email"],
                "phone_number": row["phone_number"]
            }
        }), 200

    return jsonify({
        "success": False,
        "error": "Invalid email/phone number or password"
    }), 401


@app.route("/api/profile/<int:user_id>", methods=["POST"])
def update_profile(user_id):
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    full_name = data.get("full_name")
    email = data.get("email")
    phone_number = data.get("phone_number")
    if not all(
        isinstance(value, str) and value.strip()
        for value in (full_name, email, phone_number)
    ):
        return jsonify({"error": "Name, email, and phone number are required"}), 400

    try:
        cursor = get_db().execute(
            """
            UPDATE tbl_users
            SET full_name = ?, email = ?, phone_number = ?
            WHERE user_id = ?
            """,
            (full_name.strip(), email.strip().lower(), phone_number.strip(), user_id),
        )
        get_db().commit()
    except sqlite3.IntegrityError as error:
        return jsonify({"error": str(error)}), 400
    if cursor.rowcount == 0:
        return jsonify({"error": "User not found"}), 404
    return jsonify({"success": True}), 200


@app.route("/api/profile/<int:user_id>/password", methods=["POST"])
def update_password(user_id):
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    current_password = data.get("current_password")
    new_password = data.get("new_password")
    if not isinstance(current_password, str) or not isinstance(new_password, str):
        return jsonify({"error": "Current and new passwords are required"}), 400
    if len(new_password.strip()) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400

    db = get_db()
    user = db.execute(
        "SELECT password_hash FROM tbl_users WHERE user_id = ?",
        (user_id,),
    ).fetchone()
    if user is None:
        return jsonify({"error": "User not found"}), 404
    stored_password = user["password_hash"]
    try:
        password_matches = check_password_hash(
            stored_password,
            current_password.strip(),
        )
    except (ValueError, TypeError):
        password_matches = False
    if not password_matches and stored_password == current_password.strip():
        password_matches = True
    if not password_matches:
        return jsonify({"error": "Current password does not match"}), 400

    db.execute(
        "UPDATE tbl_users SET password_hash = ? WHERE user_id = ?",
        (generate_password_hash(new_password.strip()), user_id),
    )
    db.commit()
    return jsonify({"success": True}), 200


# ============================================================
# START JOURNEY
# ============================================================

@app.route("/api/journey/start", methods=["POST"])
def start_journey():

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    required_text = ("source_location", "destination_location")
    if any(not isinstance(data.get(key), str) or not data[key].strip()
           for key in required_text):
        return jsonify({"error": "Source and destination are required"}), 400

    try:
        user_id = int(data["user_id"])
        latitude = float(data["dest_latitude"])
        longitude = float(data["dest_longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "A user and valid destination coordinates are required"}), 400
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "Destination coordinates are out of range"}), 400

    db = get_db()

    try:
        cur = db.execute(
            """
        INSERT INTO tbl_journey
        (
            user_id,
            source_location,
            destination_location,
            dest_latitude,
            dest_longitude,
            sleep_mode_enabled,
            start_time
        )
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        """,
            (
                user_id,
                data["source_location"].strip(),
                data["destination_location"].strip(),
                latitude,
                longitude,
                int(bool(data.get("sleep_mode_enabled", 0))),
            ),
        )
    except sqlite3.IntegrityError as error:
        return jsonify({"error": str(error)}), 400

    db.commit()

    return jsonify({
        "success": True,
        "journey_id": cur.lastrowid
    }), 201


@app.route("/api/journey/<int:journey_id>/finish", methods=["POST"])
def finish_journey(journey_id):
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    try:
        user_id = int(data["user_id"])
        distance = float(data["distance_travelled"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "user_id and distance_travelled are required"}), 400
    status = data.get("status", "COMPLETED")
    if status not in ("COMPLETED", "MISSED"):
        return jsonify({"error": "Journey status must be COMPLETED or MISSED"}), 400
    if distance < 0:
        return jsonify({"error": "distance_travelled cannot be negative"}), 400

    db = get_db()
    journey = db.execute(
        """
        SELECT start_time FROM tbl_journey
        WHERE journey_id = ? AND user_id = ?
        """,
        (journey_id, user_id),
    ).fetchone()
    if journey is None:
        return jsonify({"error": "Journey not found"}), 404

    end_time = db.execute("SELECT CURRENT_TIMESTAMP").fetchone()[0]
    duration_minutes = 0
    try:
        from datetime import datetime
        started = datetime.fromisoformat(journey["start_time"])
        ended = datetime.fromisoformat(end_time)
        duration_minutes = max(0, int((ended - started).total_seconds() // 60))
    except (TypeError, ValueError):
        duration_minutes = 0

    db.execute(
        """
        UPDATE tbl_journey
        SET journey_status = ?, end_time = ?
        WHERE journey_id = ? AND user_id = ?
        """,
        (status, end_time, journey_id, user_id),
    )
    missed_count = db.execute(
        "SELECT COUNT(*) FROM tbl_missed_stop WHERE journey_id = ?",
        (journey_id,),
    ).fetchone()[0]
    existing_history = db.execute(
        "SELECT history_id FROM tbl_journey_history WHERE journey_id = ?",
        (journey_id,),
    ).fetchone()
    values = (distance, f"{duration_minutes} minutes", missed_count)
    if existing_history:
        db.execute(
            """
            UPDATE tbl_journey_history
            SET distance_travelled = ?, travel_duration = ?, missed_stop_count = ?
            WHERE history_id = ?
            """,
            (*values, existing_history["history_id"]),
        )
    else:
        db.execute(
            """
            INSERT INTO tbl_journey_history
            (user_id, journey_id, distance_travelled, travel_duration, missed_stop_count)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, journey_id, *values),
        )
    db.commit()
    return jsonify({"success": True, "journey_id": journey_id}), 200


@app.route("/api/journey/history/<int:user_id>", methods=["GET"])
def get_journey_history(user_id):
    rows = get_db().execute(
        """
        SELECT h.history_id, h.journey_id, h.distance_travelled,
               h.travel_duration, h.missed_stop_count, j.user_id,
               j.source_location, j.destination_location, j.dest_latitude,
               j.dest_longitude, j.sleep_mode_enabled, j.start_time,
               j.end_time, j.journey_status
        FROM tbl_journey_history h
        JOIN tbl_journey j ON j.journey_id = h.journey_id
        WHERE h.user_id = ?
        ORDER BY j.start_time DESC
        """,
        (user_id,),
    ).fetchall()
    return jsonify({
        "success": True,
        "journeys": [dict(row) for row in rows],
    }), 200


@app.route(
    "/api/journey/history/<int:user_id>/<int:journey_id>",
    methods=["DELETE"],
)
def delete_journey_history(user_id, journey_id):
    cursor = get_db().execute(
        """
        DELETE FROM tbl_journey_history
        WHERE user_id = ? AND journey_id = ?
        """,
        (user_id, journey_id),
    )
    get_db().commit()
    if cursor.rowcount == 0:
        return jsonify({"error": "Journey history record not found"}), 404
    return jsonify({"success": True}), 200


@app.route("/api/journey/history/<int:user_id>", methods=["DELETE"])
def clear_journey_history(user_id):
    get_db().execute(
        "DELETE FROM tbl_journey_history WHERE user_id = ?",
        (user_id,),
    )
    get_db().commit()
    return jsonify({"success": True}), 200


@app.route("/api/missed-stop", methods=["POST"])
def record_missed_stop():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    try:
        journey_id = int(data["journey_id"])
        latitude = float(data["missed_latitude"])
        longitude = float(data["missed_longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "Journey and valid missed-stop coordinates are required"}), 400
    return_stop = data.get("nearest_return_stop")
    if not isinstance(return_stop, str) or not return_stop.strip():
        return jsonify({"error": "nearest_return_stop is required"}), 400
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "Missed-stop coordinates are out of range"}), 400

    db = get_db()
    try:
        cur = db.execute(
            """
            INSERT INTO tbl_missed_stop
            (journey_id, missed_latitude, missed_longitude, nearest_return_stop, alternate_route)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                journey_id,
                latitude,
                longitude,
                return_stop.strip(),
                str(data.get("alternate_route") or "").strip() or None,
            ),
        )
        db.commit()
    except sqlite3.IntegrityError as error:
        return jsonify({"error": str(error)}), 400
    return jsonify({"success": True, "missed_id": cur.lastrowid}), 201


@app.route("/api/alerts", methods=["POST"])
def record_alert():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    try:
        journey_id = int(data["journey_id"])
        distance = float(data["distance_remaining"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "Journey and distance_remaining are required"}), 400
    alert_type = data.get("alert_type")
    if alert_type not in ("VOICE", "VIBRATION", "ALARM", "SCREEN"):
        return jsonify({"error": "Unsupported alert_type"}), 400
    if distance < 0:
        return jsonify({"error": "distance_remaining cannot be negative"}), 400
    try:
        cursor = get_db().execute(
            """
            INSERT INTO tbl_alerts (journey_id, alert_type, distance_remaining)
            VALUES (?, ?, ?)
            """,
            (journey_id, alert_type, distance),
        )
        get_db().commit()
    except sqlite3.IntegrityError as error:
        return jsonify({"error": str(error)}), 400
    return jsonify({"success": True, "alert_id": cursor.lastrowid}), 201


@app.route("/api/saved-destinations/<int:user_id>", methods=["GET"])
def get_saved_destinations(user_id):
    rows = get_db().execute(
        """
        SELECT destination_id, user_id, destination_name, latitude, longitude
        FROM tbl_saved_destinations
        WHERE user_id = ?
        ORDER BY destination_name COLLATE NOCASE
        """,
        (user_id,),
    ).fetchall()
    return jsonify({"success": True, "destinations": [dict(row) for row in rows]}), 200


@app.route("/api/saved-destinations", methods=["POST"])
def add_saved_destination():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    name = data.get("destination_name")
    try:
        user_id = int(data["user_id"])
        latitude = float(data["latitude"])
        longitude = float(data["longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "User and valid destination coordinates are required"}), 400
    if not isinstance(name, str) or not name.strip():
        return jsonify({"error": "destination_name is required"}), 400
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "Destination coordinates are out of range"}), 400
    try:
        cursor = get_db().execute(
            """
            INSERT INTO tbl_saved_destinations
            (user_id, destination_name, latitude, longitude)
            VALUES (?, ?, ?, ?)
            """,
            (user_id, name.strip(), latitude, longitude),
        )
        get_db().commit()
    except sqlite3.IntegrityError as error:
        return jsonify({"error": str(error)}), 400
    return jsonify({"success": True, "destination_id": cursor.lastrowid}), 201


@app.route("/api/saved-destinations/<int:destination_id>", methods=["DELETE"])
def delete_saved_destination(destination_id):
    cursor = get_db().execute(
        "DELETE FROM tbl_saved_destinations WHERE destination_id = ?",
        (destination_id,),
    )
    get_db().commit()
    if cursor.rowcount == 0:
        return jsonify({"error": "Saved destination not found"}), 404
    return jsonify({"success": True}), 200


# ============================================================
# EMERGENCY CONTACTS
# ============================================================

@app.route("/api/contacts/<int:user_id>", methods=["GET"])
def get_emergency_contacts(user_id):
    db = get_db()
    rows = db.execute(
        """
        SELECT contact_id, user_id, contact_name, contact_phone, relationship
        FROM tbl_emergency_contact
        WHERE user_id = ?
        ORDER BY contact_id DESC
        """,
        (user_id,)
    ).fetchall()

    contacts = [
        {
            "contact_id": row["contact_id"],
            "user_id": row["user_id"],
            "contact_name": row["contact_name"],
            "contact_phone": row["contact_phone"],
            "relationship": row["relationship"] or ""
        }
        for row in rows
    ]

    return jsonify({"success": True, "contacts": contacts}), 200


@app.route("/api/contacts", methods=["POST"])
def add_emergency_contact():
    data = request.get_json()
    if not data:
        return jsonify({"error": "No data received"}), 400

    user_id = data.get("user_id")
    contact_name = data.get("contact_name", "").strip()
    contact_phone = data.get("contact_phone", "").strip()
    relationship = data.get("relationship", "Emergency Contact").strip()

    if not user_id or not contact_name or not contact_phone:
        return jsonify({"error": "user_id, contact_name, and contact_phone are required"}), 400

    if is_emergency_helpline_number(contact_phone):
        return jsonify({
            "success": False,
            "error": "Emergency helpline numbers cannot be saved as trusted contacts"
        }), 400

    db = get_db()
    cur = db.execute(
        """
        INSERT INTO tbl_emergency_contact
        (user_id, contact_name, contact_phone, relationship)
        VALUES (?, ?, ?, ?)
        """,
        (user_id, contact_name, contact_phone, relationship)
    )
    db.commit()

    return jsonify({
        "success": True,
        "contact_id": cur.lastrowid,
        "message": "Emergency contact added successfully"
    }), 201


@app.route("/api/contacts/<int:contact_id>", methods=["DELETE"])
def delete_emergency_contact(contact_id):
    db = get_db()
    db.execute("DELETE FROM tbl_emergency_contact WHERE contact_id = ?", (contact_id,))
    db.commit()
    return jsonify({"success": True, "message": "Emergency contact deleted"}), 200


def is_emergency_helpline_number(phone_number):
    digits = "".join(ch for ch in str(phone_number) if ch.isdigit())
    helpline_numbers = {"112", "100", "1091", "108", "911", "999", "000"}
    if digits in helpline_numbers:
        return True
    if digits.startswith("91") and digits[2:] in helpline_numbers:
        return True
    if digits.startswith("0091") and digits[4:] in helpline_numbers:
        return True
    return False


@app.route("/api/sms/send", methods=["POST"])
def send_sms_message():
    data = request.get_json(silent=True) or {}
    phones = data.get("phones") or data.get("phone_numbers") or []
    message = str(data.get("message", "") or "").strip()

    if not phones or not message:
        return jsonify({
            "success": False,
            "fallback": "device",
            "error": "phones and message are required"
        }), 400

    normalized_numbers = []
    for raw_phone in phones:
        clean_phone = "".join(ch for ch in str(raw_phone) if ch.isdigit() or ch == "+")
        if clean_phone and not is_emergency_helpline_number(clean_phone):
            normalized_numbers.append(clean_phone)

    if not normalized_numbers:
        return jsonify({
            "success": False,
            "fallback": "none",
            "error": "no eligible trusted contact numbers were provided; emergency helplines are excluded"
        }), 400

    account_sid = os.getenv("TWILIO_ACCOUNT_SID")
    auth_token = os.getenv("TWILIO_AUTH_TOKEN")
    from_number = os.getenv("TWILIO_FROM_NUMBER")

    if not (account_sid and auth_token and from_number):
        return jsonify({
            "success": False,
            "fallback": "device",
            "backend": "not_configured",
            "message": "Backend SMS gateway is not configured. Device SMS fallback will be used."
        }), 200

    try:
        from twilio.rest import Client

        client = Client(account_sid, auth_token)
        for phone_number in normalized_numbers:
            client.messages.create(
                body=message,
                from_=from_number,
                to=phone_number,
            )

        return jsonify({
            "success": True,
            "fallback": "none",
            "backend": "twilio",
            "sent_to": len(normalized_numbers),
            "message": "Emergency SMS sent successfully via backend"
        }), 200
    except Exception as exc:
        return jsonify({
            "success": False,
            "fallback": "device",
            "backend": "twilio",
            "error": str(exc)
        }), 502


# ============================================================
# SOS
# ============================================================

@app.route("/api/sos", methods=["POST"])
def raise_sos():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    try:
        user_id = int(data["user_id"])
        latitude = float(data["latitude"])
        longitude = float(data["longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "User and valid GPS coordinates are required"}), 400
    if user_id <= 0 or not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "User or GPS coordinates are out of range"}), 400

    db = get_db()
    raw_journey_id = data.get("journey_id")
    if raw_journey_id is None:
        journey = db.execute(
            """
            SELECT journey_id FROM tbl_journey
            WHERE user_id = ? AND journey_status = 'ONGOING'
            ORDER BY journey_id DESC LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if journey is None:
            return jsonify({
                "error": "SOS logging requires an active journey"
            }), 409
        journey_id = journey["journey_id"]
    else:
        try:
            journey_id = int(raw_journey_id)
        except (TypeError, ValueError):
            return jsonify({"error": "A valid journey_id is required"}), 400
        journey = db.execute(
            "SELECT journey_id FROM tbl_journey WHERE journey_id = ? AND user_id = ?",
            (journey_id, user_id),
        ).fetchone()
        if journey is None:
            return jsonify({"error": "Journey not found for this user"}), 404

    cur = db.execute(
        """
        INSERT INTO tbl_sos_alert
        (
            user_id,
            journey_id,
            latitude,
            longitude,
            status
        )
        VALUES (?, ?, ?, ?, 'SENT')
        """,
        (
            user_id,
            journey_id,
            latitude,
            longitude,
        ),
    )

    db.commit()

    return jsonify({
        "success": True,
        "sos_id": cur.lastrowid,
        "journey_id": journey_id,
        "status": "SENT",
        "message": "Emergency SOS broadcasted successfully"
    }), 201


@app.route("/api/sos/<int:user_id>", methods=["GET"])
def get_sos_history(user_id):
    db = get_db()
    rows = db.execute(
        """
        SELECT sos_id, user_id, journey_id, latitude, longitude, sent_at, status
        FROM tbl_sos_alert
        WHERE user_id = ?
        ORDER BY sent_at DESC
        """,
        (user_id,)
    ).fetchall()

    alerts = [
        {
            "sos_id": row["sos_id"],
            "user_id": row["user_id"],
            "journey_id": row["journey_id"],
            "latitude": row["latitude"],
            "longitude": row["longitude"],
            "sent_at": row["sent_at"],
            "status": row["status"]
        }
        for row in rows
    ]

    return jsonify({"success": True, "alerts": alerts}), 200


# ============================================================
# RUN SERVER
# ============================================================

if __name__ == "__main__":
    app.run(
        debug=True,
        host="0.0.0.0",
        port=5000
    )