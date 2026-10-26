import sqlite3
import tempfile
import unittest
from pathlib import Path

import app as backend


class BackendApiTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database_path = Path(self.temporary_directory.name) / "test.db"
        with sqlite3.connect(self.database_path) as connection:
            schema_path = Path(__file__).with_name("schema.sql")
            connection.executescript(schema_path.read_text(encoding="utf-8"))

        self.original_database_path = backend.DB_PATH
        backend.DB_PATH = str(self.database_path)
        self.client = backend.app.test_client()

    def tearDown(self):
        backend.DB_PATH = self.original_database_path
        with backend.app.app_context():
            backend.close_db()
        try:
            self.temporary_directory.cleanup()
        except (PermissionError, OSError):
            pass

    def create_user(self, email="passenger@example.test", phone="9876543210"):
        response = self.client.post(
            "/api/register",
            json={
                "full_name": "Test Passenger",
                "email": email,
                "phone_number": phone,
                "password": "test123",
            },
        )
        self.assertEqual(response.status_code, 201)
        return response.json["user_id"], response.json["access_token"]

    def create_journey(self, token):
        response = self.client.post(
            "/api/journey/start",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "source_location": "Bus Stop A",
                "destination_location": "Bus Stop B",
                "dest_latitude": 9.7,
                "dest_longitude": 76.6,
            },
        )
        self.assertEqual(response.status_code, 201)
        return response.json["journey_id"]

    def test_register_and_login_return_jwt_token(self):
        registration = self.client.post(
            "/api/register",
            json={
                "full_name": "Test Passenger",
                "email": "reg@example.test",
                "phone_number": "9112345678",
                "password_hash": "test123",
            },
        )
        self.assertEqual(registration.status_code, 201)
        self.assertIn("access_token", registration.json)
        user_id = registration.json["user_id"]

        with sqlite3.connect(self.database_path) as connection:
            stored_password = connection.execute(
                "SELECT password_hash FROM tbl_users WHERE user_id = ?",
                (user_id,),
            ).fetchone()[0]
        self.assertNotEqual(stored_password, "test123")

        login = self.client.post(
            "/api/login",
            json={
                "identifier": "reg@example.test",
                "password_hash": "test123",
            },
        )
        self.assertEqual(login.status_code, 200)
        self.assertIn("access_token", login.json)
        self.assertEqual(login.json["user"]["id"], user_id)

    def test_login_rejects_invalid_password(self):
        self.client.post(
            "/api/register",
            json={
                "full_name": "Test Passenger",
                "email": "auth@example.test",
                "phone_number": "9811122233",
                "password_hash": "test123",
            },
        )
        login = self.client.post(
            "/api/login",
            json={
                "identifier": "auth@example.test",
                "password_hash": "wrong123",
            },
        )
        self.assertEqual(login.status_code, 401)
        self.assertFalse(login.json["success"])

    def test_journey_completion_writes_history(self):
        user_id, token = self.create_user("journey@example.test", "9812345678")
        journey_id = self.create_journey(token)

        finish = self.client.post(
            f"/api/journey/{journey_id}/finish",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "distance_travelled": 12.5,
                "status": "COMPLETED",
            },
        )
        self.assertEqual(finish.status_code, 200)

        history = self.client.get(
            f"/api/journey/history/{user_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(history.status_code, 200)
        self.assertEqual(len(history.json["journeys"]), 1)
        record = history.json["journeys"][0]
        self.assertEqual(record["journey_id"], journey_id)
        self.assertEqual(record["distance_travelled"], 12.5)
        self.assertIn("duration_seconds", record)

    def test_saved_destinations_ownership_and_scoping(self):
        user1_id, token1 = self.create_user("user1@example.test", "9000000001")
        user2_id, token2 = self.create_user("user2@example.test", "9000000002")

        # User 1 adds destination
        add_res = self.client.post(
            "/api/saved-destinations",
            headers={"Authorization": f"Bearer {token1}"},
            json={
                "destination_name": "Central Station",
                "latitude": 9.9312,
                "longitude": 76.2673,
            },
        )
        self.assertEqual(add_res.status_code, 201)
        dest_id = add_res.json["destination_id"]

        # User 2 cannot see User 1's destination
        u2_list = self.client.get(
            f"/api/saved-destinations/{user2_id}",
            headers={"Authorization": f"Bearer {token2}"},
        )
        self.assertEqual(len(u2_list.json["destinations"]), 0)

        # User 2 cannot delete User 1's destination
        del_attempt = self.client.delete(
            f"/api/saved-destinations/{dest_id}",
            headers={"Authorization": f"Bearer {token2}"},
        )
        self.assertEqual(del_attempt.status_code, 404)

        # User 1 can delete their destination
        del_success = self.client.delete(
            f"/api/saved-destinations/{dest_id}",
            headers={"Authorization": f"Bearer {token1}"},
        )
        self.assertEqual(del_success.status_code, 200)

    def test_emergency_contact_ownership_and_validation(self):
        user1_id, token1 = self.create_user("contact1@example.test", "9111111111")
        user2_id, token2 = self.create_user("contact2@example.test", "9222222222")

        # Adding helpline should be rejected
        helpline_res = self.client.post(
            "/api/contacts",
            headers={"Authorization": f"Bearer {token1}"},
            json={
                "contact_name": "Police",
                "contact_phone": "100",
            },
        )
        self.assertEqual(helpline_res.status_code, 400)

        # Valid trusted contact
        valid_res = self.client.post(
            "/api/contacts",
            headers={"Authorization": f"Bearer {token1}"},
            json={
                "contact_name": "Family",
                "contact_phone": "9876543210",
                "relationship": "Parent",
            },
        )
        self.assertEqual(valid_res.status_code, 201)
        contact_id = valid_res.json["contact_id"]

        # User 2 cannot delete User 1's contact
        u2_del = self.client.delete(
            f"/api/contacts/{contact_id}",
            headers={"Authorization": f"Bearer {token2}"},
        )
        self.assertEqual(u2_del.status_code, 404)

        # User 1 deletes their contact
        u1_del = self.client.delete(
            f"/api/contacts/{contact_id}",
            headers={"Authorization": f"Bearer {token1}"},
        )
        self.assertEqual(u1_del.status_code, 200)

    def test_sos_logging_without_active_journey_succeeds(self):
        user_id, token = self.create_user("sos@example.test", "9333333333")

        # SOS raised without journey
        sos_res = self.client.post(
            "/api/sos",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": 9.9312,
                "longitude": 76.2673,
            },
        )
        self.assertEqual(sos_res.status_code, 201)
        sos_id = sos_res.json["sos_id"]
        self.assertIsNone(sos_res.json["journey_id"])
        self.assertEqual(sos_res.json["status"], "SENT")

        # Status update
        update_res = self.client.put(
            f"/api/sos/{sos_id}/status",
            headers={"Authorization": f"Bearer {token}"},
            json={"status": "DELIVERED"},
        )
        self.assertEqual(update_res.status_code, 200)
        self.assertEqual(update_res.json["status"], "DELIVERED")

    def test_sms_relay_requires_auth_and_saved_contacts(self):
        # Unauthenticated request rejected
        unauth_res = self.client.post(
            "/api/sms/send",
            json={"message": "Help me!"},
        )
        self.assertEqual(unauth_res.status_code, 401)

        user_id, token = self.create_user("smsuser@example.test", "9444444444")

        # User with no contacts configured
        no_contacts_res = self.client.post(
            "/api/sms/send",
            headers={"Authorization": f"Bearer {token}"},
            json={"message": "Emergency alert!"},
        )
        self.assertEqual(no_contacts_res.status_code, 400)

        # Add trusted contact
        self.client.post(
            "/api/contacts",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "contact_name": "Friend",
                "contact_phone": "9998887776",
            },
        )

        # Gateway not configured fallback
        send_res = self.client.post(
            "/api/sms/send",
            headers={"Authorization": f"Bearer {token}"},
            json={"message": "Emergency alert!"},
        )
        # Should return 200 with fallback: device when Twilio env vars are not set
        self.assertEqual(send_res.status_code, 200)
        self.assertFalse(send_res.json["success"])
        self.assertEqual(send_res.json["fallback"], "device")

    def test_alert_and_missed_stop_journey_scoping(self):
        user1_id, token1 = self.create_user("journey1@example.test", "9555555551")
        user2_id, token2 = self.create_user("journey2@example.test", "9555555552")
        journey_id = self.create_journey(token1)

        # User 2 cannot post missed stop on User 1's journey
        cross_missed = self.client.post(
            "/api/missed-stop",
            headers={"Authorization": f"Bearer {token2}"},
            json={
                "journey_id": journey_id,
                "missed_latitude": 9.71,
                "missed_longitude": 76.61,
                "nearest_return_stop": "Bus Stop C",
            },
        )
        self.assertEqual(cross_missed.status_code, 404)

        # User 1 can post missed stop
        valid_missed = self.client.post(
            "/api/missed-stop",
            headers={"Authorization": f"Bearer {token1}"},
            json={
                "journey_id": journey_id,
                "missed_latitude": 9.71,
                "missed_longitude": 76.61,
                "nearest_return_stop": "Bus Stop C",
            },
        )
        self.assertEqual(valid_missed.status_code, 201)


if __name__ == "__main__":
    unittest.main()
