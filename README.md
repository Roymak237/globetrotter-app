# GlobeTrotter — A Travel App for Cameroon

GlobeTrotter is a **monolithic Flask REST API** backend paired with a **Flutter** frontend. It helps people discover and plan trips around Cameroon — from Kribi's beaches and Limbe's coastline, to Foumban's culture and Waza's wildlife.

## Features

- **Search destinations** across all 10 regions of Cameroon
- **Personalised recommendations** based on user preferences
- **Create, update, and delete** travel itineraries
- **Share trip plans** with other registered users

## Project Structure

```
globetrotter-app/
├── README.md
├── backend/
│   ├── requirements.txt
│   ├── app/
│   │   ├── __init__.py         # Flask app factory + blueprint registration
│   │   ├── main.py             # App entry point
│   │   ├── models.py           # JSON file I/O helpers
│   │   ├── auth.py             # Registration, login, JWT handling
│   │   ├── destinations.py     # Destination search endpoint
│   │   ├── recommendations.py  # Personalised recommendations endpoint
│   │   ├── itineraries.py      # CRUD itineraries endpoint
│   │   └── shares.py           # Share itineraries endpoint
│   └── data/
│       ├── destinations.json   # Static Cameroon destination catalogue
│       ├── users.json          # Registered users (created at runtime)
│       ├── itineraries.json    # User itineraries (created at runtime)
│       └── shares.json         # Shared itinerary records (created at runtime)
└── frontend/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart              # Flutter entry point
        ├── app.dart               # Root widget with Providers
        ├── models/
        │   ├── destination.dart
        │   ├── itinerary.dart
        │   ├── user.dart
        │   └── share.dart
        ├── providers/
        │   └── auth_provider.dart # Auth state management
        ├── services/
        │   ├── api_service.dart   # HTTP client for destinations/recommendations
        │   └── auth_service.dart  # HTTP client for auth, itineraries, shares
        ├── screens/
        │   ├── login_screen.dart
        │   ├── register_screen.dart
        │   ├── home_screen.dart
        │   ├── destinations_screen.dart
        │   ├── recommendations_screen.dart
        │   ├── itineraries_screen.dart
        │   ├── create_itinerary_screen.dart
        │   └── itinerary_detail_screen.dart
        ├── widgets/
        │   ├── destination_card.dart
        │   ├── itinerary_card.dart
        │   └── bottom_nav.dart
        └── utils/
            ├── constants.dart
            └── theme.dart
```

## REST API Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/register` | No | Register a new user |
| POST | `/api/auth/login` | No | Authenticate and receive a JWT token |
| GET | `/api/destinations` | No | Search the destination catalogue (`?q=&tag=&region=&max_cost=`) |
| GET | `/api/destinations/<id>` | No | Get a single destination |
| GET | `/api/recommendations` | JWT | Get personalised recommendations based on preferences |
| POST | `/api/itineraries` | JWT | Create a new itinerary |
| GET | `/api/itineraries` | JWT | List all itineraries for the logged-in user |
| GET | `/api/itineraries/<id>` | JWT | Get a single itinerary |
| PUT | `/api/itineraries/<id>` | JWT | Update an itinerary |
| DELETE | `/api/itineraries/<id>` | JWT | Delete an itinerary |
| POST | `/api/itineraries/<id>/share` | JWT | Share an itinerary with another user |
| GET | `/api/itineraries/<id>/share` | JWT | List shares for an itinerary |
| DELETE | `/api/shares/<id>` | JWT | Revoke a share |

Protected routes expect the header:  
`Authorization: Bearer <your-token>`

## Example Requests

```bash
# Register
curl -X POST http://localhost:5000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "s3cr3t", "preferences": ["beach", "food"]}'

# Login
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "s3cr3t"}'

# Search destinations
curl "http://localhost:5000/api/destinations?tag=beach&region=South"

# Personalised recommendations
curl http://localhost:5000/api/recommendations \
  -H "Authorization: Bearer <token>"

# Create itinerary
curl -X POST http://localhost:5000/api/itineraries \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"title": "Beach Escape", "destinations": ["Kribi"], "start_date": "2025-07-01", "end_date": "2025-07-14"}'

# List itineraries
curl http://localhost:5000/api/itineraries \
  -H "Authorization: Bearer <token>"
```

## Running Locally

### Backend (Flask Monolith)

**Prerequisites:**
- Python 3.9+
- pip

```bash
# 1. Install dependencies
cd backend
pip install -r requirements.txt

# 2. Start the server
python app/main.py
```

The API will be available at `http://localhost:5000`.

### Frontend (Flutter)

**Prerequisites:**
- Flutter SDK 3.0+
- Dart SDK

```bash
# 1. Install dependencies
cd frontend
flutter pub get

# 2. Run the app
flutter run
```

> **Note for Android Emulator:** The Flutter app runs on an emulator. Update `lib/utils/constants.dart` with the correct `backendBaseUrl` if needed. The default uses `http://10.0.2.2:5000` for Android emulator access to host localhost.

## Configuration

| Environment Variable | Default | Description |
|----------------------|---------|-------------|
| `SECRET_KEY` | `globetrotter-secret-change-in-prod` | JWT signing key — **must be overridden in production** |
| `FLASK_DEBUG` | `0` | Set to `1` to enable Flask debug mode (development only) |
| `PORT` | `5000` | Port the app listens on |

> **Important:** Always set `SECRET_KEY` to a long, random value in production.

## Data Storage

All data is persisted in plain JSON files under `backend/data/`:

| File                    | Purpose |
|-------------------------|---------|
| `data/destinations.json`| Static catalogue of 16 Cameroonian destinations across all 10 regions |
| `data/users.json`       | Registered users (created at runtime) |
| `data/itineraries.json` | User itineraries (created at runtime) |
| `data/shares.json`      | Shared itinerary records (created at runtime) |

## Architecture Notes

- **Phase 1 Monolith:** The backend is a single Flask application demonstrating a centralized REST API. It is the foundational step before refactoring into microservices and deploying to the cloud with Docker/Kubernetes.
- **JSON storage** keeps the project simple and portable for learning purposes.
- **JWT-based authentication** with Werkzeug password hashing.

## Destination Regions Covered

1. Adamawa
2. Centre
3. East
4. Far North
5. Littoral
6. North
7. Northwest
8. South
9. Southwest
10. West
