import asyncio
import os

import httpx
from dotenv import load_dotenv

load_dotenv()

JOLPICA_BASE_URL = os.getenv("JOLPICA_BASE_URL", "https://api.jolpi.ca/ergast/f1")

# Jolpica is volunteer-run; be polite. Retry on rate-limit / transient errors.
MAX_RETRIES = 4
MAX_BACKOFF = 4  # cap individual backoff waits at 4s (snappier failure)
TIMEOUT_SECONDS = 15.0

# Identify our app politely to the volunteer-run API.
HEADERS = {
    "User-Agent": "pitstop-f1/0.1 (personal learning project)",
    "Accept": "application/json",
}


class UpstreamUnavailable(Exception):
    """Raised when the F1 data source (Jolpica) can't be reached."""
    pass


async def _get_json(url: str) -> dict:
    """
    GET a Jolpica URL and return parsed JSON.

    Resilience features:
      - Retries with exponential backoff on 429 (rate limit) and 5xx errors.
      - Falls back from https:// to http:// if the secure attempt keeps failing
        (mirrors what mature Jolpica clients do during origin outages).
      - Raises UpstreamUnavailable (not a bare RuntimeError) so endpoints can
        translate it into a clean 503 instead of a 500.
    """
    # Build the list of URLs to try: the original first, then an http:// twin.
    candidates = [url]
    if url.startswith("https://"):
        candidates.append("http://" + url[len("https://"):])

    last_error: Exception | None = None

    async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS, headers=HEADERS) as client:
        for candidate in candidates:
            for attempt in range(MAX_RETRIES):
                try:
                    response = await client.get(candidate)

                    # Rate limited -> wait and retry
                    if response.status_code == 429:
                        await asyncio.sleep(min(2 ** attempt, MAX_BACKOFF))
                        continue

                    # Server-side / origin-down (incl. Cloudflare 5xx like 521,
                    # 522, 523) -> wait and retry
                    if response.status_code >= 500:
                        last_error = httpx.HTTPStatusError(
                            f"{response.status_code} from upstream",
                            request=response.request,
                            response=response,
                        )
                        await asyncio.sleep(min(2 ** attempt, MAX_BACKOFF))
                        continue

                    response.raise_for_status()
                    return response.json()

                except (httpx.RequestError, httpx.HTTPStatusError) as exc:
                    last_error = exc
                    await asyncio.sleep(min(2 ** attempt, MAX_BACKOFF))
            # exhausted retries for this candidate -> try next (http fallback)

    raise UpstreamUnavailable(
        f"Could not reach the F1 data source after retries: {last_error}"
    )


async def fetch_driver_standings(season: str) -> list[dict]:
    """
    Fetch driver standings for a season from Jolpica.
    Returns a list of normalized dicts (one per driver).
    """
    url = f"{JOLPICA_BASE_URL}/{season}/driverStandings.json"
    data = await _get_json(url)

    standings_lists = (
        data.get("MRData", {})
        .get("StandingsTable", {})
        .get("StandingsLists", [])
    )
    if not standings_lists:
        return []

    rows = standings_lists[0].get("DriverStandings", [])
    result: list[dict] = []

    for row in rows:
        driver = row.get("Driver", {})
        constructors = row.get("Constructors", [])
        constructor = constructors[0] if constructors else {}

        result.append(
            {
                "position": _to_int(row.get("position")),
                "points": _to_float(row.get("points")),
                "wins": _to_int(row.get("wins")),
                "driver_ref": driver.get("driverId"),
                "code": driver.get("code"),
                "given_name": driver.get("givenName"),
                "family_name": driver.get("familyName"),
                "nationality": driver.get("nationality"),
                "dob": driver.get("dateOfBirth"),
                "constructor_ref": constructor.get("constructorId"),
                "constructor_name": constructor.get("name"),
            }
        )

    return result


async def fetch_constructor_standings(season: str) -> list[dict]:
    """
    Fetch constructor standings for a season from Jolpica.
    Returns a list of normalized dicts (one per constructor).
    """
    url = f"{JOLPICA_BASE_URL}/{season}/constructorStandings.json"
    data = await _get_json(url)

    standings_lists = (
        data.get("MRData", {})
        .get("StandingsTable", {})
        .get("StandingsLists", [])
    )
    if not standings_lists:
        return []

    rows = standings_lists[0].get("ConstructorStandings", [])
    result: list[dict] = []

    for row in rows:
        constructor = row.get("Constructor", {})
        result.append(
            {
                "position": _to_int(row.get("position")),
                "points": _to_float(row.get("points")),
                "wins": _to_int(row.get("wins")),
                "constructor_ref": constructor.get("constructorId"),
                "name": constructor.get("name"),
                "nationality": constructor.get("nationality"),
            }
        )

    return result


def _to_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _to_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


async def fetch_races(season: str) -> list[dict]:
    """
    Fetch the race schedule for a season from Jolpica.
    Returns a list of normalized race dicts.
    """
    url = f"{JOLPICA_BASE_URL}/{season}/races.json"
    data = await _get_json(url)

    races = (
        data.get("MRData", {})
        .get("RaceTable", {})
        .get("Races", [])
    )

    result: list[dict] = []
    for race in races:
        circuit = race.get("Circuit", {})
        location = circuit.get("Location", {})
        result.append(
            {
                "round": _to_int(race.get("round")),
                "race_name": race.get("raceName"),
                "circuit_name": circuit.get("circuitName"),
                "country": location.get("country"),
                "locality": location.get("locality"),
                "date": race.get("date"),
                "time": race.get("time"),
            }
        )
    return result


async def _get_total(url: str) -> int:
    """
    Return MRData.total for a filtered query (e.g. wins, poles).
    Uses limit=1 so we transfer almost nothing but still read the count.
    """
    sep = "&" if "?" in url else "?"
    data = await _get_json(f"{url}{sep}limit=1")
    try:
        return int(data.get("MRData", {}).get("total", 0))
    except (TypeError, ValueError):
        return 0


async def fetch_driver_career(driver_ref: str) -> dict | None:
    """
    Aggregate a driver's career stats from several Jolpica queries:
    info, races, wins, podiums, poles, total points, and points-per-season.
    Returns a dict, or None if the driver isn't found.
    """
    base = f"{JOLPICA_BASE_URL}/drivers/{driver_ref}"

    # --- driver info ---
    info_data = await _get_json(f"{base}.json")
    drivers = (
        info_data.get("MRData", {})
        .get("DriverTable", {})
        .get("Drivers", [])
    )
    if not drivers:
        return None
    d = drivers[0]

    # --- counts (cheap: read MRData.total) ---
    races = await _get_total(f"{base}/results.json")
    wins = await _get_total(f"{base}/results/1.json")
    poles = await _get_total(f"{base}/qualifying/1.json")
    p1 = await _get_total(f"{base}/results/1.json")
    p2 = await _get_total(f"{base}/results/2.json")
    p3 = await _get_total(f"{base}/results/3.json")
    podiums = p1 + p2 + p3

    # --- points per season + total points ---
    # Jolpica requires a season_year for driver standings, so we can't
    # fetch a whole career in one call. Instead: get the driver's list of
    # seasons, then fetch each season's standings and sum the points.
    points_per_season: list[dict] = []
    total_points = 0.0
    try:
        seasons_data = await _get_json(f"{base}/seasons/?format=json&limit=100")
        seasons = (
            seasons_data.get("MRData", {})
            .get("SeasonTable", {})
            .get("Seasons", [])
        )

        for s in seasons:
            year = s.get("season")
            if not year:
                continue

            season_url = (
                f"{JOLPICA_BASE_URL}/{year}/drivers/{driver_ref}"
                f"/driverStandings/?format=json"
            )
            try:
                sd = await _get_json(season_url)
                slists = (
                    sd.get("MRData", {})
                    .get("StandingsTable", {})
                    .get("StandingsLists", [])
                )
                if not slists:
                    continue
                ds = slists[0].get("DriverStandings", [])
                if not ds:
                    continue
                pts = _to_float(ds[0].get("points")) or 0.0
                total_points += pts
                points_per_season.append({"season": year, "points": pts})
            except Exception:
                # skip a season that fails, keep the rest
                continue
    except Exception:
        # If even the seasons list fails, still return the other stats.
        pass

    win_rate = round((wins / races) * 100, 1) if races else 0.0
    podium_rate = round((podiums / races) * 100, 1) if races else 0.0

    return {
        "driver_ref": driver_ref,
        "code": d.get("code"),
        "given_name": d.get("givenName"),
        "family_name": d.get("familyName"),
        "nationality": d.get("nationality"),
        "dob": d.get("dateOfBirth"),
        "races": races,
        "wins": wins,
        "podiums": podiums,
        "poles": poles,
        "total_points": total_points,
        "win_rate": win_rate,
        "podium_rate": podium_rate,
        "points_per_season": points_per_season,
    }


async def _fetch_position_finishers(season: str, position: int) -> dict[int, dict]:
    """
    Fetch every round's finisher at a given position for a season.
    Returns {round_number: {driver/constructor fields}}.
    Uses /{season}/results/{position}.json which returns one result per round.
    """
    url = f"{JOLPICA_BASE_URL}/{season}/results/{position}.json?limit=100"
    data = await _get_json(url)

    races = (
        data.get("MRData", {})
        .get("RaceTable", {})
        .get("Races", [])
    )

    by_round: dict[int, dict] = {}
    for race in races:
        rnd = _to_int(race.get("round"))
        results = race.get("Results", [])
        if rnd is None or not results:
            continue
        r = results[0]
        driver = r.get("Driver", {})
        constructors = r.get("Constructor", {})
        by_round[rnd] = {
            "driver_ref": driver.get("driverId"),
            "driver_code": driver.get("code"),
            "given_name": driver.get("givenName"),
            "family_name": driver.get("familyName"),
            "constructor_ref": constructors.get("constructorId"),
            "constructor_name": constructors.get("name"),
        }
    return by_round


async def fetch_race_podiums(season: str) -> list[dict]:
    """
    Fetch the full podium (P1, P2, P3) for every race in a season.
    Returns a list of dicts, one per race, each with first/second/third.
    """
    p1 = await _fetch_position_finishers(season, 1)
    p2 = await _fetch_position_finishers(season, 2)
    p3 = await _fetch_position_finishers(season, 3)

    # also grab race names/rounds from the schedule for labels
    schedule_url = f"{JOLPICA_BASE_URL}/{season}/races.json?limit=100"
    schedule_data = await _get_json(schedule_url)
    sched_races = (
        schedule_data.get("MRData", {})
        .get("RaceTable", {})
        .get("Races", [])
    )

    result: list[dict] = []
    for race in sched_races:
        rnd = _to_int(race.get("round"))
        if rnd is None:
            continue
        result.append(
            {
                "round": rnd,
                "race_name": race.get("raceName"),
                "first": p1.get(rnd),
                "second": p2.get(rnd),
                "third": p3.get(rnd),
            }
        )
    return result