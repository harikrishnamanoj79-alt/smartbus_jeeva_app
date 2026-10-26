# SmartBus Guardian 🚌🛡️

A comprehensive passenger safety and journey tracking application built with **Flutter** (Frontend) and **Flask/SQLite** (Backend). 

Designed to keep public transit users safe, SmartBus Guardian provides intelligent **Sleep Protection**, **Live Location Tracking**, and an integrated **Emergency SOS system**.

---

## 🌟 Key Features

* 📍 **Live Journey Tracking**: Real-time GPS routing and map integration using `flutter_map` and OpenStreetMap. Monitor your trip progress with distance and ETA estimations.
* 😴 **Sleep Protection & Destination Alerts**: Never miss your stop! The app uses GPS to trigger wake-up alarms (Text-to-Speech announcements, strong vibrations, and full-screen notifications) as you approach your destination.
* 🚨 **Emergency SOS System**: In case of danger, trigger an SOS to immediately:
  * Send automated SMS alerts with your live location to your trusted emergency contacts (powered by Twilio).
  * Activate a loud device siren and haptic feedback to deter threats.
* 🔄 **Offline-First Resilience**: Core functionalities like local authentication, saved destinations, and journey history are cached on the device using `SharedPreferences`, automatically syncing with the Flask backend when the network is restored.
* 🔙 **Missed Stop Detection**: Alerts the user with guidance if they've accidentally traveled past their intended destination.

---

## 🛠️ Tech Stack

### Frontend (Mobile App)
* **Framework**: [Flutter](https://flutter.dev/) (Dart)
* **Maps & Location**: `flutter_map`, `geolocator`, `latlong2`
* **Alerts & Device Hardware**: `flutter_local_notifications`, `flutter_tts`, `vibration`
* **Local Storage**: `shared_preferences`

### Backend (API Server)
* **Framework**: [Flask](https://flask.palletsprojects.com/) (Python)
* **Database**: SQLite
* **External Services**: Twilio API (for robust Emergency SMS dispatch)

---

## 🚀 Getting Started

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (^3.12.0)
* Python 3.9+
* (Optional) A [Twilio](https://www.twilio.com/) account for backend SMS dispatch.

### 1. Backend Setup (Flask)
Navigate to the backend directory and start the server:

```bash
cd smartbusguardian_backend
# Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# (Optional) Set Twilio Environment Variables for SOS SMS
export TWILIO_ACCOUNT_SID="your_sid"
export TWILIO_AUTH_TOKEN="your_token"
export TWILIO_FROM_NUMBER="your_twilio_number"

# Run the server
python app.py
```
*The server will start on `http://0.0.0.0:5000/`.*

### 2. Frontend Setup (Flutter)
Open a new terminal at the root of the Flutter project.

```bash
# Get Flutter dependencies
flutter pub get

# Connect a physical device or emulator, then run
flutter run
```

> **Note on Local Network**: If running on a physical Android device, ensure the `_deviceBaseUrl` in `lib/services/api_service.dart` is updated to your computer's local network IP address (e.g., `http://192.168.x.x:5000`) so the app can communicate with the local Flask server.

---

## 📂 Project Structure

```text
SmartBus Guardian/
├── android/ & ios/             # Native mobile configurations
├── lib/
│   ├── main.dart               # App entry point & Theme setup
│   ├── models/                 # Data models (JourneyRecord, SosRecord, etc.)
│   ├── screens/                # UI Views (Map, Home, SOS, Login, etc.)
│   └── services/               # Core Logic (ApiService, JourneyService, EmergencyService, AlertService)
└── smartbusguardian_backend/   # Python Flask API
    ├── app.py                  # API Endpoints (Auth, Journey, Contacts, SOS)
    ├── smartbus.db             # SQLite Database
    └── test_app.py             # Backend test suite
```

---

## 🔒 Privacy & Permissions
SmartBus Guardian requires the following permissions to function correctly:
* **Location (Foreground & Background)**: To track journeys and trigger destination alerts even when the phone is locked.
* **Notifications**: To display full-screen wake-up alarms.
* **SMS / Phone**: To dispatch native fallback SOS messages and dial emergency numbers directly.

---

## 📝 License
This project is not currently published. Code is provided "as is" for educational and developmental purposes.
