# 🏁 PIT STOP — Cache-First F1 Data Platform

A full-stack Formula 1 data application: a **FastAPI + PostgreSQL** backend with a cache-first architecture, paired with a **Flutter** mobile app frontend. It serves historical and current-season F1 data — drivers, constructors, races, standings, race podiums, and full driver career stats — while minimizing load on the upstream data source.

> **Status:** Functional full-stack app — backend complete, Flutter frontend complete with all four panels.

---

## Why this project exists

F1 data is scattered across multiple APIs and sites with inconsistent formats, and hammering an external API with repeated requests risks rate limits and throttling at scale. PIT STOP solves this with a **cache-first (cache-aside) architecture**: the app reads from a local PostgreSQL store first, and only falls back to the external [Jolpica/Ergast API](https://api.jolpi.ca/ergast/f1) on a cache miss. Fetched data is normalized and stored, so repeat queries are served instantly from the local database.

---

## Architecture

```
User -> Flutter -> FastAPI -> PostgreSQL
                      |
                      +- (on cache miss) -> Jolpica API -> normalize -> store -> return
```

**Request lifecycle:**
1. **Request** — the app requests driver / race / season / career data.
2. **DB check** — FastAPI queries PostgreSQL using indexed lookups.
3. **Fallback** — on a miss, it calls Jolpica with rate-limit-aware retry/backoff, and an `https -> http` fallback for resilience.
4. **Persist & return** — the response is returned immediately, and the database write runs as a **background task** so it doesn't block the client (FastAPI `BackgroundTasks`). Subsequent requests are fast cache hits.

The `source` field in every response (`"api"` or `"cache"`) makes the caching visible: the first request for a season is fetched live, every request after is served from the database.

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (Dart) |
| Backend | FastAPI (async REST, background tasks, validation) |
| Database | PostgreSQL (normalized relational storage, indexes, constraints) |
| ORM | SQLAlchemy (async, typed models) |
| Upstream | Jolpica / Ergast API (the community successor to Ergast) |
| Images | Local asset bundle (driver headshots, team logos) with OpenF1 fallback |

---

## Features

**Home panel**
- Featured "opening titles" card (opens the F1 season launch video)
- **Next Race** card — round, name, circuit, country, date
- **Live countdown timer** (days / hours / minutes / seconds) ticking to the next upcoming race, synced to local time
- Top-5 constructor and driver standings

**Races panel**
- Year dropdown (1950–present) — selecting a year that isn't cached triggers a live fetch
- Race cards with round badges, location, date
- `COMPLETED` / `UPCOMING` status pills (auto-determined by date)
- **WATCH RACE** button -> opens a YouTube highlights search for that race (works for any race, any year)
- **DETAILS** expander -> shows the race podium (top 3 finishers) from the backend

**Standings panel**
- Year dropdown + DRIVERS / CONSTRUCTORS toggle
- Full grid with position, points, wins, nationality, and driver/team images

**Search panel**
- Live driver search
- Tap a driver -> full **career detail view**: races, wins, podiums, poles, total points, a points-per-season bar chart, and win/podium rate bars

---

## Backend data models

`seasons`, `drivers`, `constructors`, `driver_standings`, `constructor_standings`, `races`, `race_winners` (full podiums), `driver_careers` (aggregated stats), and `year_list` (full selectable year range for the dropdown). Foreign keys, unique constraints, and indexed lookups are used throughout for integrity and query performance.

---

## Project structure

```
PIT-STOP-Cache-First-F1-Data-Platform/
├── backend/        # FastAPI + SQLAlchemy + PostgreSQL
│   ├── app/
│   │   ├── main.py        # endpoints + cache-first logic
│   │   ├── models.py      # SQLAlchemy models
│   │   ├── crud.py        # DB read/write helpers
│   │   ├── fetcher.py     # Jolpica fetching with retry/backoff
│   │   └── database.py    # async engine + session
│   ├── requirements.txt
│   └── .env.example
└── frontend/       # Flutter app
    ├── lib/main.dart      # the entire app UI
    ├── assets/            # driver headshots, team logos, opening image, fonts
    └── pubspec.yaml
```

---

## Setup — Backend

**Requirements:** Python 3.11+, PostgreSQL 15+

```bash
cd backend
python -m venv venv
# Windows:
venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate

pip install -r requirements.txt
```

Create a `.env` file (copy from `.env.example`) and set your database URL:

```
DATABASE_URL=postgresql+asyncpg://postgres:YOUR_PASSWORD@localhost:5432/f1_db
JOLPICA_BASE_URL=https://api.jolpi.ca/ergast/f1
```

Create the `f1_db` database in PostgreSQL, then run:

```bash
uvicorn app.main:app --reload
```

The API runs at `http://localhost:8000`. Interactive docs are at `http://localhost:8000/docs`.

---

## Setup — Frontend (Flutter)

**Requirements:** Flutter SDK, and either Chrome (web) or an Android emulator.

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

### Running as a mobile app (emulator)

This is a **mobile app** — built with Flutter to run on an Android emulator. It was primarily tested in **Chrome during development due to local disk/RAM constraints on the development machine**, but it runs on an Android emulator with **one single change**.

In `lib/main.dart`, change the base URL constant:

```dart
// For Chrome / web:
const String kBaseUrl = 'http://localhost:8000';

// For the Android emulator (the emulator reaches the host machine via 10.0.2.2):
const String kBaseUrl = 'http://10.0.2.2:8000';
```

Then run on the emulator:

```bash
flutter run -d emulator-5554
```

That one line is the only difference — the emulator can't see `localhost` (that points at the emulated phone itself), so it uses the special host address `10.0.2.2`. The rest of the app is identical.

---

## Notes

- **Images:** Driver headshots and team logos are bundled as local assets for reliable offline display. Official F1 imagery and team marks are trademarks of their respective owners; this is a personal learning project.
- **Data source:** Jolpica is a free, community-run, unofficial API (the successor to the deprecated Ergast API). It can be intermittently rate-limited during live race sessions. The cache-first design means previously fetched data keeps working even when the upstream is unavailable.

---

## License

MIT (personal / educational project)
