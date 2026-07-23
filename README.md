# GlobeTrotter

GlobeTrotter is a Phase 1 monolithic travel planning app. The backend is a
single Flask REST API in `backend/` and the frontend is a Flutter client in
`frontend/`.

## Phase 1: Monolith

This phase intentionally keeps all backend responsibilities in one Flask
application:

- Authentication and JWT creation
- Destination catalogue search
- Preference-based recommendations
- Itinerary creation and listing
- JSON-file database persistence for local development

The limitation of this centralized architecture is that every feature shares the
same deployment unit, runtime, data access layer, and scaling boundary. That is
simple for a first working system, but later phases can split these concerns into
services when independent scaling, ownership, failure isolation, and deployment
speed become more important.

## Project Structure

```text
.
|-- backend/
|   |-- __init__.py
|   `-- app.py
|-- data/
|   |-- destinations.json
|   |-- itineraries.json
|   `-- users.json
|-- frontend/
|   `-- lib/main.dart
|-- tests/
|   `-- test_api.py
|-- requirements.txt
`-- README.md
```

## REST API

| Method | Endpoint | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | No | API health check |
| POST | `/register` | No | Register a user |
| POST | `/login` | No | Login and receive a JWT |
| GET | `/destinations` | No | Search destinations |
| GET | `/recommendations` | Yes | Get personalized recommendations |
| POST | `/itineraries` | Yes | Create an itinerary |
| GET | `/itineraries` | Yes | List a user's itineraries |

Protected routes expect:

```text
Authorization: Bearer <token>
```

## Run Locally

### Backend

```bash
pip install -r requirements.txt
python backend/app.py
```

The API runs at `http://localhost:5000`.

The backend stores data in JSON files under `data/`:

- `data/destinations.json` keeps the seed destination catalogue.
- `data/users.json` is created automatically for registered users.
- `data/itineraries.json` is created automatically for saved trips.

### Flutter Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

The frontend uses `http://localhost:5000` by default. To point it somewhere
else:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000
```

For Android emulator runs, use `http://10.0.2.2:5000`.

## Example API Calls

```bash
curl http://localhost:5000/health

curl -X POST http://localhost:5000/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"s3cr3t","preferences":["beach","food"]}'

curl -X POST http://localhost:5000/login \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"s3cr3t"}'

curl "http://localhost:5000/destinations?tag=beach&max_cost=100"
```

## Run Tests

```bash
python -m unittest discover -s tests
cd frontend
flutter test
```

## Configuration

| Environment Variable | Default | Description |
| --- | --- | --- |
| `SECRET_KEY` | `globetrotter-secret-change-in-prod` | JWT signing key |
| `FLASK_DEBUG` | `0` | Enables Flask debug when set to `1` |
| `PORT` | `5000` | Backend port |
| `CORS_ORIGIN` | `*` | Allowed browser origin for development |
