"""
SmartBus Guardian Flask Backend

Flutter → Flask → SQLite
Secured with JWT authentication, user scoping, rate limiting, and robust input validation.
"""

from flask import Flask, request, jsonify, g
import sqlite3
import os
import time
import datetime
from werkzeug.security import check_password_hash, generate_password_hash
from flask_jwt_extended import (
    JWTManager,
    create_access_token,
    jwt_required,
    get_jwt_identity,
)

import secrets
import threading

app = Flask(__name__)

# JWT Configuration
def get_jwt_secret():
    """
    Returns JWT secret from environment or generates a secure random
    secret persisted in .jwt_secret with atomic creation and restricted permissions.
    """
    env_secret = os.environ.get("JWT_SECRET_KEY")
    if env_secret and env_secret.strip():
        return env_secret.strip()

    secret_file = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        ".jwt_secret"
    )
    if os.path.exists(secret_file):
        try:
            with open(secret_file, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    return content
        except OSError:
            pass

    new_secret = secrets.token_hex(32)
    try:
        flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
        mode = 0o600
        try:
            fd = os.open(secret_file, flags, mode)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(new_secret)
            return new_secret
        except FileExistsError:
            with open(secret_file, "r", encoding="utf-8") as f:
                return f.read().strip() or new_secret
    except OSError:
        pass
    return new_secret

app.config["JWT_SECRET_KEY"] = get_jwt_secret()
app.config["JWT_ACCESS_TOKEN_EXPIRES"] = datetime.timedelta(days=30)
jwt = JWTManager(app)


@jwt.unauthorized_loader
def unauthorized_callback(callback):
    return jsonify({"error": "Missing or unauthorized authorization token"}), 401


@jwt.invalid_token_loader
def invalid_token_callback(callback):
    return jsonify({"error": "Invalid authorization token"}), 401


@jwt.expired_token_loader
def expired_token_callback(jwt_header, jwt_payload):
    return jsonify({"error": "Authorization token has expired"}), 401


# Configure reverse proxy support securely via ProxyFix if enabled
BEHIND_PROXY = os.environ.get("BEHIND_PROXY", "").strip().lower() in ("1", "true", "yes")
NUM_PROXIES = int(os.environ.get("NUM_PROXIES", "1")) if BEHIND_PROXY else 0

if BEHIND_PROXY and NUM_PROXIES > 0:
    from werkzeug.middleware.proxy_fix import ProxyFix
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=NUM_PROXIES, x_proto=NUM_PROXIES, x_host=NUM_PROXIES)

# Thread-safe in-memory sliding-window rate limit trackers
_RATE_LIMIT_LOCK = threading.Lock()
_LAST_PRUNE_TIME = time.time()
LOGIN_ATTEMPTS = {}  # key -> list of timestamp floats
SMS_ATTEMPTS = {}    # user_id -> list of timestamp floats

HELPLINE_NUMBERS = {"112", "100", "108", "1091", "911", "999", "000"}
DEFAULT_COUNTRY_CODE = os.environ.get("DEFAULT_COUNTRY_CODE", "+91")


def get_client_ip():
    """
    Extracts the client IP address.
    When BEHIND_PROXY is enabled, Werkzeug's ProxyFix securely resolves request.remote_addr.
    Otherwise, request.remote_addr is used directly, preventing clients from bypassing
    rate limiting via forged X-Forwarded-For headers.
    """
    return request.remote_addr or "client"


def is_rate_limited(tracker_dict, key, max_attempts=5, window_seconds=300):
    """
    Checks if a key has exceeded max attempts within the given window without recording an attempt.
    """
    global _LAST_PRUNE_TIME
    now = time.time()

    with _RATE_LIMIT_LOCK:
        if now - _LAST_PRUNE_TIME > 60:
            _LAST_PRUNE_TIME = now
            for tracker in (LOGIN_ATTEMPTS, SMS_ATTEMPTS):
                expired_keys = []
                for k, timestamps in tracker.items():
                    valid = [t for t in timestamps if now - t < 3600]
                    if not valid:
                        expired_keys.append(k)
                    else:
                        tracker[k] = valid
                for k in expired_keys:
                    tracker.pop(k, None)

        attempts = tracker_dict.get(key, [])
        valid_attempts = [t for t in attempts if now - t < window_seconds]
        tracker_dict[key] = valid_attempts
        return len(valid_attempts) >= max_attempts


def record_rate_limit_attempt(tracker_dict, key):
    """
    Records an event timestamp (e.g. on failed authentication).
    """
    with _RATE_LIMIT_LOCK:
        attempts = tracker_dict.get(key, [])
        attempts.append(time.time())
        tracker_dict[key] = attempts


def clear_rate_limit(tracker_dict, key):
    """
    Resets the rate limit tracking for a key upon successful action.
    """
    with _RATE_LIMIT_LOCK:
        tracker_dict.pop(key, None)


def check_rate_limit(tracker_dict, key, max_attempts=5, window_seconds=300):
    """
    Convenience method that checks and records an attempt (used for SMS sending).
    """
    if is_rate_limited(tracker_dict, key, max_attempts=max_attempts, window_seconds=window_seconds):
        return False
    record_rate_limit_attempt(tracker_dict, key)
    return True


def normalize_phone_number(raw_phone, default_country_code=DEFAULT_COUNTRY_CODE):
    """
    Normalizes a phone number into an E.164-compatible string.
    Preserves existing international prefixes.
    """
    if not isinstance(raw_phone, str):
        return None
    raw = raw_phone.strip()
    if not raw:
        return None
    digits = "".join(ch for ch in raw if ch.isdigit())
    if not digits:
        return None
    if raw.startswith("+"):
        return f"+{digits}"
    if raw.startswith("00"):
        return f"+{digits[2:]}"
    # Strip leading trunk '0' for 11-digit numbers (common in India: e.g. 09876543210 -> 9876543210)
    if len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if len(digits) == 10 and default_country_code:
        prefix = default_country_code if default_country_code.startswith("+") else f"+{default_country_code}"
        return f"{prefix}{digits}"
    return f"+{digits}" if len(digits) > 10 else digits


def is_emergency_helpline_number(phone_str):
    """
    Checks if a phone number matches standard national emergency numbers,
    avoiding accidental matches with regular 10-digit mobile numbers.
    """
    if not isinstance(phone_str, str):
        return False
    digits = "".join(ch for ch in phone_str if ch.isdigit())
    if not digits:
        return False
    if digits in HELPLINE_NUMBERS:
        return True
    if digits.startswith("91") and len(digits) > 2 and digits[2:] in HELPLINE_NUMBERS:
        return True
    if digits.startswith("0091") and len(digits) > 4 and digits[4:] in HELPLINE_NUMBERS:
        return True
    return False


@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = (
        "Content-Type, Authorization"
    )
    response.headers["Access-Control-Allow-Methods"] = (
        "GET, POST, PUT, DELETE, OPTIONS"
    )
    return response


@app.route("/<path:path>", methods=["OPTIONS"])
def handle_preflight(path):
    return "", 204


DB_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "smartbus.db"
)


# ============================================================
# HOME / HEALTH CHECK
# ============================================================

@app.route("/")
def home():
    return jsonify({
        "status": "online",
        "service": "SmartBus Guardian Backend",
        "version": "2.0.0"
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
    password = data.get("password") or data.get("password_hash", "")

    if not all(isinstance(value, str) for value in (full_name, email, phone_number, password)):
        return jsonify({"error": "All registration fields must be text"}), 400

    full_name = full_name.strip()
    email = email.strip().lower()
    phone_number = phone_number.strip()

    if not full_name:
        return jsonify({"error": "Full name is required"}), 400
    if not email or "@" not in email:
        return jsonify({"error": "A valid email address is required"}), 400
    if not phone_number:
        return jsonify({"error": "Phone number is required"}), 400
    if len(password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400

    normalized_phone = normalize_phone_number(phone_number)
    if not normalized_phone:
        return jsonify({"error": "Invalid phone number format"}), 400

    db = get_db()
    try:
        cur = db.execute(
            """
            INSERT INTO tbl_users (full_name, email, phone_number, password_hash)
            VALUES (?, ?, ?, ?)
            """,
            (full_name, email, normalized_phone, generate_password_hash(password)),
        )
        db.commit()
        user_id = cur.lastrowid
        access_token = create_access_token(identity=str(user_id))

        return jsonify({
            "success": True,
            "user_id": user_id,
            "access_token": access_token,
            "message": "User registered successfully",
            "user": {
                "id": user_id,
                "user_id": user_id,
                "full_name": full_name,
                "email": email,
                "phone_number": normalized_phone,
            }
        }), 201

    except sqlite3.IntegrityError:
        return jsonify({
            "success": False,
            "error": "An account with this email or phone number already exists"
        }), 400


# ============================================================
# LOGIN
# ============================================================

@app.route("/api/login", methods=["POST"])
def login_user():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    identifier = data.get("identifier") or data.get("email") or ""
    password = data.get("password") or data.get("password_hash") or ""

    if not isinstance(identifier, str) or not isinstance(password, str):
        return jsonify({"error": "Email/phone and password must be text"}), 400

    identifier = identifier.strip()

    if not identifier:
        return jsonify({"error": "Email or phone number is required"}), 400
    if not password:
        return jsonify({"error": "Password is required"}), 400

    client_ip = get_client_ip()
    rate_key = f"{client_ip}:{identifier.lower()}"
    if is_rate_limited(LOGIN_ATTEMPTS, rate_key, max_attempts=5, window_seconds=300):
        return jsonify({
            "success": False,
            "error": "Too many failed login attempts. Please wait 5 minutes before trying again."
        }), 429

    db = get_db()
    row = db.execute(
        """
        SELECT user_id, full_name, email, phone_number, password_hash
        FROM tbl_users
        WHERE email = ? OR phone_number = ?
        """,
        (identifier.lower(), identifier),
    ).fetchone()

    password_matches = False
    if row:
        stored_hash = row["password_hash"]
        try:
            password_matches = check_password_hash(stored_hash, password)
        except (ValueError, TypeError):
            password_matches = False

    if row and password_matches:
        clear_rate_limit(LOGIN_ATTEMPTS, rate_key)
        user_id = row["user_id"]
        access_token = create_access_token(identity=str(user_id))

        return jsonify({
            "success": True,
            "message": "Login successful",
            "access_token": access_token,
            "user": {
                "id": user_id,
                "user_id": user_id,
                "full_name": row["full_name"],
                "email": row["email"],
                "phone_number": row["phone_number"],
            }
        }), 200

    # Only record attempt on authentication failure!
    record_rate_limit_attempt(LOGIN_ATTEMPTS, rate_key)
    return jsonify({
        "success": False,
        "error": "Invalid email/phone number or password"
    }), 401


# ============================================================
# USER PROFILE & PASSWORD
# ============================================================

@app.route("/api/profile/<int:user_id>", methods=["POST"])
@jwt_required()
def update_profile(user_id):
    current_user_id = int(get_jwt_identity())
    if user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    full_name = data.get("full_name")
    email = data.get("email")
    phone_number = data.get("phone_number")
    if not all(isinstance(v, str) and v.strip() for v in (full_name, email, phone_number)):
        return jsonify({"error": "Name, email, and phone number are required"}), 400

    norm_phone = normalize_phone_number(phone_number)
    if not norm_phone:
        return jsonify({"error": "Invalid phone number"}), 400

    try:
        cursor = get_db().execute(
            """
            UPDATE tbl_users
            SET full_name = ?, email = ?, phone_number = ?
            WHERE user_id = ?
            """,
            (full_name.strip(), email.strip().lower(), norm_phone, current_user_id),
        )
        get_db().commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "Email or phone number is already taken"}), 400

    if cursor.rowcount == 0:
        return jsonify({"error": "User not found"}), 404
    return jsonify({"success": True}), 200


@app.route("/api/profile/<int:user_id>/password", methods=["POST"])
@jwt_required()
def update_password(user_id):
    current_user_id = int(get_jwt_identity())
    if user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    current_password = data.get("current_password")
    new_password = data.get("new_password")
    if not isinstance(current_password, str) or not isinstance(new_password, str):
        return jsonify({"error": "Current and new passwords are required"}), 400
    if len(new_password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400

    db = get_db()
    user = db.execute(
        "SELECT password_hash FROM tbl_users WHERE user_id = ?",
        (current_user_id,),
    ).fetchone()
    if user is None:
        return jsonify({"error": "User not found"}), 404

    stored_hash = user["password_hash"]
    try:
        password_matches = check_password_hash(stored_hash, current_password)
    except (ValueError, TypeError):
        password_matches = False

    if not password_matches:
        return jsonify({"error": "Current password does not match"}), 400

    db.execute(
        "UPDATE tbl_users SET password_hash = ? WHERE user_id = ?",
        (generate_password_hash(new_password), current_user_id),
    )
    db.commit()
    return jsonify({"success": True}), 200


# ============================================================
# JOURNEY
# ============================================================

@app.route("/api/journey/start", methods=["POST"])
@jwt_required()
def start_journey():
    current_user_id = int(get_jwt_identity())

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    required_text = ("source_location", "destination_location")
    if any(not isinstance(data.get(k), str) or not data[k].strip() for k in required_text):
        return jsonify({"error": "Source and destination are required"}), 400

    try:
        latitude = float(data["dest_latitude"])
        longitude = float(data["dest_longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "Valid destination coordinates are required"}), 400

    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "Destination coordinates are out of range"}), 400

    db = get_db()
    user_check = db.execute("SELECT user_id FROM tbl_users WHERE user_id = ?", (current_user_id,)).fetchone()
    if user_check is None:
        return jsonify({"error": "User not found"}), 404

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
            current_user_id,
            data["source_location"].strip(),
            data["destination_location"].strip(),
            latitude,
            longitude,
            int(bool(data.get("sleep_mode_enabled", 0))),
        ),
    )
    db.commit()

    return jsonify({
        "success": True,
        "journey_id": cur.lastrowid
    }), 201


@app.route("/api/journey/<int:journey_id>/finish", methods=["POST"])
@jwt_required()
def finish_journey(journey_id):
    current_user_id = int(get_jwt_identity())

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    try:
        distance = float(data["distance_travelled"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "distance_travelled is required"}), 400

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
        (journey_id, current_user_id),
    ).fetchone()
    if journey is None:
        return jsonify({"error": "Journey not found or not owned by user"}), 404

    end_time = db.execute("SELECT CURRENT_TIMESTAMP").fetchone()[0]
    duration_minutes = 0
    duration_seconds = 0
    try:
        started = datetime.datetime.fromisoformat(journey["start_time"])
        ended = datetime.datetime.fromisoformat(end_time)
        duration_seconds = max(0, int((ended - started).total_seconds()))
        duration_minutes = duration_seconds // 60
    except (TypeError, ValueError):
        pass

    db.execute(
        """
        UPDATE tbl_journey
        SET journey_status = ?, end_time = ?
        WHERE journey_id = ? AND user_id = ?
        """,
        (status, end_time, journey_id, current_user_id),
    )
    missed_count = db.execute(
        "SELECT COUNT(*) FROM tbl_missed_stop WHERE journey_id = ?",
        (journey_id,),
    ).fetchone()[0]

    existing_history = db.execute(
        "SELECT history_id FROM tbl_journey_history WHERE journey_id = ?",
        (journey_id,),
    ).fetchone()

    values = (distance, f"{duration_minutes} minutes", duration_seconds, missed_count)
    if existing_history:
        db.execute(
            """
            UPDATE tbl_journey_history
            SET distance_travelled = ?, travel_duration = ?, duration_seconds = ?, missed_stop_count = ?
            WHERE history_id = ?
            """,
            (*values, existing_history["history_id"]),
        )
    else:
        db.execute(
            """
            INSERT INTO tbl_journey_history
            (user_id, journey_id, distance_travelled, travel_duration, duration_seconds, missed_stop_count)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (current_user_id, journey_id, *values),
        )
    db.commit()
    return jsonify({"success": True, "journey_id": journey_id}), 200


@app.route("/api/journey/history", methods=["GET"])
@app.route("/api/journey/history/<int:user_id>", methods=["GET"])
@jwt_required()
def get_journey_history(user_id=None):
    current_user_id = int(get_jwt_identity())
    if user_id is not None and user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    rows = get_db().execute(
        """
        SELECT h.history_id, h.journey_id, h.distance_travelled,
               h.travel_duration, h.duration_seconds, h.missed_stop_count, j.user_id,
               j.source_location, j.destination_location, j.dest_latitude,
               j.dest_longitude, j.sleep_mode_enabled, j.start_time,
               j.end_time, j.journey_status
        FROM tbl_journey_history h
        JOIN tbl_journey j ON j.journey_id = h.journey_id
        WHERE h.user_id = ?
        ORDER BY j.start_time DESC
        """,
        (current_user_id,),
    ).fetchall()
    return jsonify({
        "success": True,
        "journeys": [dict(row) for row in rows],
    }), 200


@app.route(
    "/api/journey/history/<int:user_id>/<int:journey_id>",
    methods=["DELETE"],
)
@jwt_required()
def delete_journey_history(user_id, journey_id):
    current_user_id = int(get_jwt_identity())
    if user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    cursor = get_db().execute(
        """
        DELETE FROM tbl_journey_history
        WHERE user_id = ? AND journey_id = ?
        """,
        (current_user_id, journey_id),
    )
    get_db().commit()
    if cursor.rowcount == 0:
        return jsonify({"error": "Journey history record not found"}), 404
    return jsonify({"success": True}), 200


@app.route("/api/journey/history/<int:user_id>", methods=["DELETE"])
@jwt_required()
def clear_journey_history(user_id):
    current_user_id = int(get_jwt_identity())
    if user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    get_db().execute(
        "DELETE FROM tbl_journey_history WHERE user_id = ?",
        (current_user_id,),
    )
    get_db().commit()
    return jsonify({"success": True}), 200


# ============================================================
# MISSED STOP & ALERTS
# ============================================================

@app.route("/api/missed-stop", methods=["POST"])
@jwt_required()
def record_missed_stop():
    current_user_id = int(get_jwt_identity())

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
    journey = db.execute(
        "SELECT user_id FROM tbl_journey WHERE journey_id = ? AND user_id = ?",
        (journey_id, current_user_id)
    ).fetchone()
    if journey is None:
        return jsonify({"error": "Journey not found or not owned by caller"}), 404

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
    return jsonify({"success": True, "missed_id": cur.lastrowid}), 201


@app.route("/api/alerts", methods=["POST"])
@jwt_required()
def record_alert():
    current_user_id = int(get_jwt_identity())

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

    db = get_db()
    journey = db.execute(
        "SELECT user_id FROM tbl_journey WHERE journey_id = ? AND user_id = ?",
        (journey_id, current_user_id)
    ).fetchone()
    if journey is None:
        return jsonify({"error": "Journey not found or not owned by caller"}), 404

    cursor = db.execute(
        """
        INSERT INTO tbl_alerts (journey_id, alert_type, distance_remaining)
        VALUES (?, ?, ?)
        """,
        (journey_id, alert_type, distance),
    )
    db.commit()
    return jsonify({"success": True, "alert_id": cursor.lastrowid}), 201


# ============================================================
# SAVED DESTINATIONS
# ============================================================

@app.route("/api/saved-destinations", methods=["GET"])
@app.route("/api/saved-destinations/<int:user_id>", methods=["GET"])
@jwt_required()
def get_saved_destinations(user_id=None):
    current_user_id = int(get_jwt_identity())
    if user_id is not None and user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    rows = get_db().execute(
        """
        SELECT destination_id, user_id, destination_name, latitude, longitude
        FROM tbl_saved_destinations
        WHERE user_id = ?
        ORDER BY destination_name COLLATE NOCASE
        """,
        (current_user_id,),
    ).fetchall()
    return jsonify({"success": True, "destinations": [dict(row) for row in rows]}), 200


@app.route("/api/saved-destinations", methods=["POST"])
@jwt_required()
def add_saved_destination():
    current_user_id = int(get_jwt_identity())

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    name = data.get("destination_name")
    try:
        latitude = float(data["latitude"])
        longitude = float(data["longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "Valid destination coordinates are required"}), 400

    if not isinstance(name, str) or not name.strip():
        return jsonify({"error": "destination_name is required"}), 400
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "Destination coordinates are out of range"}), 400

    name = name.strip()
    try:
        cursor = get_db().execute(
            """
            INSERT INTO tbl_saved_destinations
            (user_id, destination_name, latitude, longitude)
            VALUES (?, ?, ?, ?)
            """,
            (current_user_id, name, latitude, longitude),
        )
        get_db().commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "A destination with this name already exists"}), 400

    return jsonify({"success": True, "destination_id": cursor.lastrowid}), 201


@app.route("/api/saved-destinations/<int:destination_id>", methods=["DELETE"])
@jwt_required()
def delete_saved_destination(destination_id):
    current_user_id = int(get_jwt_identity())

    cursor = get_db().execute(
        "DELETE FROM tbl_saved_destinations WHERE destination_id = ? AND user_id = ?",
        (destination_id, current_user_id),
    )
    get_db().commit()
    if cursor.rowcount == 0:
        return jsonify({"error": "Saved destination not found or not owned by caller"}), 404
    return jsonify({"success": True}), 200


@app.route("/api/saved-destinations/<int:destination_id>", methods=["PUT"])
@jwt_required()
def update_saved_destination(destination_id):
    current_user_id = int(get_jwt_identity())

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400
    try:
        name = str(data.get("destination_name", "")).strip()
        latitude = float(data["latitude"])
        longitude = float(data["longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "destination_name and valid coordinates are required"}), 400

    if not name:
        return jsonify({"error": "destination_name cannot be empty"}), 400

    db = get_db()
    existing = db.execute(
        "SELECT user_id FROM tbl_saved_destinations WHERE destination_id = ?",
        (destination_id,)
    ).fetchone()
    if existing is None or existing["user_id"] != current_user_id:
        return jsonify({"error": "Destination not found or not owned by caller"}), 404

    try:
        db.execute(
            "UPDATE tbl_saved_destinations SET destination_name = ?, latitude = ?, longitude = ? WHERE destination_id = ?",
            (name, latitude, longitude, destination_id)
        )
        db.commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "Another destination with this name already exists"}), 400

    return jsonify({"success": True, "destination_id": destination_id}), 200


# ============================================================
# EMERGENCY CONTACTS
# ============================================================

@app.route("/api/contacts", methods=["GET"])
@app.route("/api/contacts/<int:user_id>", methods=["GET"])
@jwt_required()
def get_emergency_contacts(user_id=None):
    current_user_id = int(get_jwt_identity())
    if user_id is not None and user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    rows = get_db().execute(
        """
        SELECT contact_id, user_id, contact_name, contact_phone, relationship
        FROM tbl_emergency_contact
        WHERE user_id = ?
        ORDER BY contact_id DESC
        """,
        (current_user_id,)
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
@jwt_required()
def add_emergency_contact():
    current_user_id = int(get_jwt_identity())

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    contact_name = data.get("contact_name")
    contact_phone = data.get("contact_phone")
    relationship = data.get("relationship", "Emergency Contact")

    if not isinstance(contact_name, str) or not isinstance(contact_phone, str):
        return jsonify({"error": "contact_name and contact_phone must be text"}), 400

    contact_name = contact_name.strip()
    contact_phone = contact_phone.strip()
    relationship = str(relationship).strip() if relationship else "Emergency Contact"

    if not contact_name or not contact_phone:
        return jsonify({"error": "contact_name and contact_phone are required"}), 400

    normalized_phone = normalize_phone_number(contact_phone)
    if not normalized_phone:
        return jsonify({"error": "Invalid phone number format"}), 400

    if is_emergency_helpline_number(normalized_phone):
        return jsonify({
            "success": False,
            "error": "Emergency helpline numbers cannot be saved as personal trusted contacts"
        }), 400

    db = get_db()
    # Limit contacts to maximum 10
    count = db.execute(
        "SELECT COUNT(*) FROM tbl_emergency_contact WHERE user_id = ?",
        (current_user_id,)
    ).fetchone()[0]
    if count >= 10:
        return jsonify({"error": "Maximum of 10 emergency contacts allowed"}), 400

    try:
        cur = db.execute(
            """
            INSERT INTO tbl_emergency_contact
            (user_id, contact_name, contact_phone, relationship)
            VALUES (?, ?, ?, ?)
            """,
            (current_user_id, contact_name, normalized_phone, relationship)
        )
        db.commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "A contact with this phone number already exists"}), 400

    return jsonify({
        "success": True,
        "contact_id": cur.lastrowid,
        "contact": {
            "contact_id": cur.lastrowid,
            "user_id": current_user_id,
            "contact_name": contact_name,
            "contact_phone": normalized_phone,
            "relationship": relationship
        },
        "message": "Emergency contact added successfully"
    }), 201


@app.route("/api/contacts/<int:contact_id>", methods=["DELETE"])
@jwt_required()
def delete_emergency_contact(contact_id):
    current_user_id = int(get_jwt_identity())

    db = get_db()
    cur = db.execute(
        "DELETE FROM tbl_emergency_contact WHERE contact_id = ? AND user_id = ?",
        (contact_id, current_user_id)
    )
    db.commit()
    if cur.rowcount == 0:
        return jsonify({"error": "Emergency contact not found or not owned by caller"}), 404
    return jsonify({"success": True}), 200


# ============================================================
# SMS SERVICE (SECURED TWILIO RELAY)
# ============================================================

@app.route("/api/sms/send", methods=["POST"])
@jwt_required()
def send_sms_message():
    current_user_id = int(get_jwt_identity())

    # Rate limiting: maximum 5 SMS broadcasts per 60 seconds per user
    if not check_rate_limit(SMS_ATTEMPTS, current_user_id, max_attempts=5, window_seconds=60):
        return jsonify({
            "success": False,
            "fallback": "device",
            "error": "SMS rate limit exceeded. Please wait a moment before sending more emergency alerts."
        }), 429

    data = request.get_json(silent=True) or {}
    message = str(data.get("message", "") or "").strip()

    if not message:
        return jsonify({
            "success": False,
            "fallback": "device",
            "error": "Emergency message content is required"
        }), 400

    # Look up emergency contacts ONLY from DB for this authenticated user
    db = get_db()
    contact_rows = db.execute(
        "SELECT contact_phone, contact_name FROM tbl_emergency_contact WHERE user_id = ?",
        (current_user_id,)
    ).fetchall()

    if not contact_rows:
        return jsonify({
            "success": False,
            "fallback": "device",
            "error": "No emergency contacts configured for your account. Please add contacts first."
        }), 400

    eligible_numbers = []
    for row in contact_rows:
        norm = normalize_phone_number(row["contact_phone"])
        if norm and not is_emergency_helpline_number(norm):
            eligible_numbers.append(norm)

    if not eligible_numbers:
        return jsonify({
            "success": False,
            "fallback": "none",
            "error": "No eligible personal trusted contacts available (helplines excluded)"
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
    except Exception as exc:
        app.logger.error("Failed to initialize Twilio client: %s", exc)
        return jsonify({
            "success": False,
            "fallback": "device",
            "backend": "twilio",
            "sent_to": 0,
            "sent_numbers": [],
            "failed_numbers": eligible_numbers,
            "error": "Failed to initialize SMS gateway. Device SMS fallback should be used."
        }), 502

    sent_numbers = []
    failed_numbers = []

    for phone_number in eligible_numbers:
        try:
            client.messages.create(
                body=message,
                from_=from_number,
                to=phone_number,
            )
            sent_numbers.append(phone_number)
        except Exception as exc:
            app.logger.warning("Twilio SMS transmission failed for %s: %s", phone_number, exc)
            failed_numbers.append(phone_number)

    if failed_numbers and not sent_numbers:
        return jsonify({
            "success": False,
            "fallback": "device",
            "backend": "twilio",
            "sent_to": 0,
            "sent_numbers": [],
            "failed_numbers": failed_numbers,
            "error": "Failed to deliver SMS to any contact via gateway. Device SMS fallback should be used."
        }), 502
    elif failed_numbers and sent_numbers:
        return jsonify({
            "success": True,
            "partial": True,
            "fallback": "device_for_failed",
            "backend": "twilio",
            "sent_to": len(sent_numbers),
            "sent_numbers": sent_numbers,
            "failed_numbers": failed_numbers,
            "message": f"SMS sent to {len(sent_numbers)} contact(s), but failed for {len(failed_numbers)} contact(s)."
        }), 200
    else:
        return jsonify({
            "success": True,
            "partial": False,
            "fallback": "none",
            "backend": "twilio",
            "sent_to": len(sent_numbers),
            "sent_numbers": sent_numbers,
            "failed_numbers": [],
            "message": f"Emergency SMS sent successfully via backend to {len(sent_numbers)} contact(s)"
        }), 200


# ============================================================
# SOS
# ============================================================

@app.route("/api/sos", methods=["POST"])
@jwt_required()
def raise_sos():
    current_user_id = int(get_jwt_identity())

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "A JSON object is required"}), 400

    try:
        latitude = float(data["latitude"])
        longitude = float(data["longitude"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "Valid GPS coordinates (latitude, longitude) are required"}), 400

    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return jsonify({"error": "GPS coordinates are out of range"}), 400

    db = get_db()
    raw_journey_id = data.get("journey_id")
    journey_id = None
    if raw_journey_id is not None:
        try:
            candidate_id = int(raw_journey_id)
            journey = db.execute(
                "SELECT journey_id FROM tbl_journey WHERE journey_id = ? AND user_id = ?",
                (candidate_id, current_user_id),
            ).fetchone()
            if journey is not None:
                journey_id = candidate_id
        except (TypeError, ValueError):
            pass

    if journey_id is None:
        ongoing = db.execute(
            """
            SELECT journey_id FROM tbl_journey
            WHERE user_id = ? AND journey_status = 'ONGOING'
            ORDER BY journey_id DESC LIMIT 1
            """,
            (current_user_id,),
        ).fetchone()
        if ongoing is not None:
            journey_id = ongoing["journey_id"]

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
            current_user_id,
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


@app.route("/api/sos/<int:sos_id>/status", methods=["PUT"])
@jwt_required()
def update_sos_status(sos_id):
    current_user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    status = data.get("status")
    if status not in ("SENT", "DELIVERED", "FAILED"):
        return jsonify({"error": "Status must be SENT, DELIVERED, or FAILED"}), 400

    db = get_db()
    cur = db.execute(
        "UPDATE tbl_sos_alert SET status = ? WHERE sos_id = ? AND user_id = ?",
        (status, sos_id, current_user_id)
    )
    db.commit()
    if cur.rowcount == 0:
        return jsonify({"error": "SOS alert not found or not owned by caller"}), 404

    return jsonify({"success": True, "sos_id": sos_id, "status": status}), 200


@app.route("/api/sos", methods=["GET"])
@app.route("/api/sos/<int:user_id>", methods=["GET"])
@jwt_required()
def get_sos_history(user_id=None):
    current_user_id = int(get_jwt_identity())
    if user_id is not None and user_id != current_user_id:
        return jsonify({"error": "Unauthorized"}), 403

    db = get_db()
    rows = db.execute(
        """
        SELECT sos_id, user_id, journey_id, latitude, longitude, sent_at, status
        FROM tbl_sos_alert
        WHERE user_id = ?
        ORDER BY sent_at DESC
        """,
        (current_user_id,)
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
    is_debug = os.environ.get("FLASK_DEBUG", "0") == "1"
    port = int(os.environ.get("PORT", 5000))
    host = os.environ.get("HOST", "127.0.0.1" if is_debug else "0.0.0.0")

    if is_debug:
        print(f"Starting development server on {host}:{port} (debug=True)")
        app.run(debug=True, host=host, port=port)
    else:
        print(f"Starting production server (waitress) on {host}:{port} (debug=False)")
        from waitress import serve
        serve(app, host=host, port=port)
