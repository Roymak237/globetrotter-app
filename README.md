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
| GET | `/api/auth/me` | JWT | Read the current public profile |
| POST | `/api/auth/refresh` | JWT | Issue a replacement JWT for the current session |
| PATCH | `/api/auth/profile` | JWT | Update profile details and preferences |
| PATCH | `/api/auth/username` | JWT | Change username and preserve trip/share ownership |
| PATCH | `/api/auth/password` | JWT | Change password and rotate sessions |
| POST | `/api/auth/sessions/revoke` | JWT | Sign out all other sessions |
| DELETE | `/api/auth/account` | JWT | Delete account and cascade owned data |
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

```powershell
# 1. Install dependencies
Set-Location frontend
flutter pub get

# 2. Run the app
flutter run
```

> **Note for Android Emulator:** The Flutter app runs on an emulator. Update `lib/utils/constants.dart` with the correct `backendBaseUrl` if needed. The default uses `http://10.0.2.2:5000` for Android emulator access to host localhost.

### Map configuration

The map surfaces use OpenStreetMap via `flutter_map` and `latlong2`. No API key is required for the default OpenStreetMap tile layer.

**Tile providers**

- Default: OpenStreetMap (`https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png`)
- Windows fallback: Leaflet inside Edge WebView2 through `webview_windows`

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

## Deployment — Docker + Nginx + DuckDNS

### Prerequisites
- A VPS (e.g., Contabo) with Ubuntu 22.04+
- Domain or DuckDNS subdomain (e.g., `globetrotter.duckdns.org`)
- Docker and Docker Compose installed on the VPS

### Quick Start

```bash
# 1. Clone the project
git clone YOUR_REPO_URL globetrotter
cd globetrotter

# 2. Copy environment file and edit it
cp .env.example .env
nano .env   # Fill in your DuckDNS token and email

# 3. Set up SSL certificate (first time only)
chmod +x setup_ssl.sh
./setup_ssl.sh

# 4. Build and start the stack
docker-compose up -d --build

# 5. Check status
docker-compose ps
docker-compose logs -f backend
```

### What Gets Deployed

| Service   | Port | Description                    |
|-----------|------|--------------------------------|
| backend   | 5000 | Flask REST API (internal only) |
| nginx     | 80/443 | Reverse proxy + SSL termination |

### DuckDNS Setup

1. Sign up at [https://www.duckdns.org](https://www.duckdns.org)
2. Create a domain (e.g., `globetrotter`)
3. Get your API token from the DuckDNS dashboard
4. Add to `.env`:
   ```
   DUCKDNS_TOKEN=your_token_here
   DUCKDNS_DOMAIN=globetrotter
   SSL_EMAIL=your_email@example.com
   ```
5. The `setup_ssl.sh` script obtains a free Let's Encrypt SSL certificate
6. Certbot auto-renewal is handled by a cron job (add to crontab):
   ```bash
   crontab -e
   # Add this line:
   0 3 * * * certbot renew --quiet && docker restart globetrotter_nginx
   ```

### Updating the Deployment

```bash
# Pull latest code
git pull

# Rebuild and restart
docker-compose up -d --build
```

### Production Environment Variables

| Variable     | Required | Description                              |
|--------------|----------|------------------------------------------|
| `SECRET_KEY` | Yes      | Long random JWT signing key              |
| `FLASK_DEBUG`| No       | Set to `0` in production                 |
| `PORT`       | No       | Default `5000`                           |

> **Important:** Always override `SECRET_KEY` in production:
> ```bash
> python -c "import secrets; print(secrets.token_hex(32))"
> ```

### Flutter Frontend (Production Build)

```bash
cd frontend
flutter build windows
# The built app is at build/windows/x64/runner/Release/
```

Update `lib/utils/constants.dart` to point to your DuckDNS domain:
```dart
static const String backendBaseUrl = "https://globetrotter.duckdns.org";
```

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
