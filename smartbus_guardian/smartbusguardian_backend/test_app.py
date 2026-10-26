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
        self.temporary_directory.cleanup()

    def create_user(self):
        response = self.client.post(
            "/api/register",
            json={
                "full_name": "Test Passenger",
                "email": "passenger@example.test",
                "phone_number": "5551234567",
                "password": "test123",
            },
        )
        self.assertEqual(response.status_code, 201)
        return response.json["user_id"]

    def create_journey(self, user_id):
        response = self.client.post(
            "/api/journey/start",
            json={
                "user_id": user_id,
                "source_location": "Bus Stop A",
                "destination_location": "Bus Stop B",
                "dest_latitude": 9.7,
                "dest_longitude": 76.6,
            },
        )
        self.assertEqual(response.status_code, 201)
        return response.json["journey_id"]

    def test_register_and_login_use_schema_user_id(self):
        registration = self.client.post(
            "/api/register",
            json={
                "full_name": "Test Passenger",
                "email": "passenger@example.test",
                "phone_number": "5551234567",
                "password_hash": "test123",
            },
        )

        self.assertEqual(registration.status_code, 201)
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
                "identifier": "passenger@example.test",
                "password_hash": "test123",
            },
        )

        self.assertEqual(login.status_code, 200)
        self.assertEqual(login.json["user"]["id"], user_id)
        self.assertEqual(login.json["user"]["user_id"], user_id)

    def test_login_rejects_invalid_password(self):
        self.client.post(
            "/api/register",
            json={
                "full_name": "Test Passenger",
                "email": "passenger@example.test",
                "phone_number": "5551234567",
                "password_hash": "test123",
            },
        )

        login = self.client.post(
            "/api/login",
            json={
                "identifier": "passenger@example.test",
                "password_hash": "wrong123",
            },
        )

        self.assertEqual(login.status_code, 401)
        self.assertFalse(login.json["success"])

    def test_journey_completion_writes_history_without_duplicates(self):
        user_id = self.create_user()
        journey_id = self.create_journey(user_id)

        for _ in range(2):
            completion = self.client.post(
                f"/api/journey/{journey_id}/finish",
                json={
                    "user_id": user_id,
                    "distance_travelled": 3.4,
                    "status": "COMPLETED",
                },
            )
            self.assertEqual(completion.status_code, 200)

        history = self.client.get(f"/api/journey/history/{user_id}")
        self.assertEqual(history.status_code, 200)
        self.assertEqual(len(history.json["journeys"]), 1)
        self.assertEqual(history.json["journeys"][0]["journey_status"], "COMPLETED")

    def test_saved_destinations_are_user_scoped_and_deletable(self):
        user_id = self.create_user()
        saved = self.client.post(
            "/api/saved-destinations",
            json={
                "user_id": user_id,
                "destination_name": "Home",
                "latitude": 9.7,
                "longitude": 76.6,
            },
        )
        self.assertEqual(saved.status_code, 201)

        listed = self.client.get(f"/api/saved-destinations/{user_id}")
        self.assertEqual(len(listed.json["destinations"]), 1)
        destination_id = saved.json["destination_id"]
        deleted = self.client.delete(
            f"/api/saved-destinations/{destination_id}"
        )
        self.assertEqual(deleted.status_code, 200)
        self.assertEqual(
            self.client.get(f"/api/saved-destinations/{user_id}").json[
                "destinations"
            ],
            [],
        )

    def test_alert_and_missed_stop_records_use_schema_relationships(self):
        user_id = self.create_user()
        journey_id = self.create_journey(user_id)
        alert = self.client.post(
            "/api/alerts",
            json={
                "journey_id": journey_id,
                "alert_type": "VOICE",
                "distance_remaining": 80,
            },
        )
        missed = self.client.post(
            "/api/missed-stop",
            json={
                "journey_id": journey_id,
                "missed_latitude": 9.71,
                "missed_longitude": 76.61,
                "nearest_return_stop": "Bus Stop C",
            },
        )
        self.assertEqual(alert.status_code, 201)
        self.assertEqual(missed.status_code, 201)

        completion = self.client.post(
            f"/api/journey/{journey_id}/finish",
            json={
                "user_id": user_id,
                "distance_travelled": 3.4,
                "status": "MISSED",
            },
        )
        history = self.client.get(f"/api/journey/history/{user_id}")
        self.assertEqual(completion.status_code, 200)
        self.assertEqual(history.json["journeys"][0]["missed_stop_count"], 1)

    def test_profile_and_password_updates_persist(self):
        user_id = self.create_user()
        profile = self.client.post(
            f"/api/profile/{user_id}",
            json={
                "full_name": "Updated Passenger",
                "email": "updated@example.test",
                "phone_number": "5557654321",
            },
        )
        password = self.client.post(
            f"/api/profile/{user_id}/password",
            json={
                "current_password": "test123",
                "new_password": "next123",
            },
        )
        login = self.client.post(
            "/api/login",
            json={
                "identifier": "updated@example.test",
                "password": "next123",
            },
        )
        self.assertEqual(profile.status_code, 200)
        self.assertEqual(password.status_code, 200)
        self.assertEqual(login.status_code, 200)

    def test_emergency_contact_and_sos_persistence(self):
        user_id = self.create_user()
        journey_id = self.create_journey(user_id)
        contact = self.client.post(
            "/api/contacts",
            json={
                "user_id": user_id,
                "contact_name": "Trusted Contact",
                "contact_phone": "5559990000",
                "relationship": "Friend",
            },
        )
        self.assertEqual(contact.status_code, 201)
        self.assertEqual(
            len(self.client.get(f"/api/contacts/{user_id}").json["contacts"]),
            1,
        )
        self.assertEqual(
            self.client.post(
                "/api/sos",
                json={
                    "user_id": user_id,
                    "journey_id": journey_id,
                    "latitude": 9.7,
                    "longitude": 76.6,
                },
            ).status_code,
            201,
        )
        self.assertEqual(
            len(self.client.get(f"/api/sos/{user_id}").json["alerts"]),
            1,
        )

    def test_sos_without_a_journey_does_not_create_a_placeholder_record(self):
        user_id = self.create_user()

        response = self.client.post(
            "/api/sos",
            json={
                "user_id": user_id,
                "latitude": 9.7,
                "longitude": 76.6,
            },
        )

        self.assertEqual(response.status_code, 409)
        with sqlite3.connect(self.database_path) as connection:
            journey_count = connection.execute(
                "SELECT COUNT(*) FROM tbl_journey WHERE user_id = ?",
                (user_id,),
            ).fetchone()[0]
            self.assertEqual(journey_count, 0)

        missing_user = self.client.post(
            "/api/sos",
            json={"latitude": 9.7, "longitude": 76.6},
        )
        self.assertEqual(missing_user.status_code, 400)


if __name__ == "__main__":
    unittest.main()
