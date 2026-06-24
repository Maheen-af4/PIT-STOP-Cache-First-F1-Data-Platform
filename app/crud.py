from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Season,
    Driver,
    Constructor,
    DriverStanding,
    ConstructorStanding,
    Race,
    DriverCareer,
    RaceWinner,
    YearList,
)


# ---------- READ (cache lookups) ----------

async def get_driver_standings_from_db(db: AsyncSession, season: str) -> list[dict]:
    """Return cached driver standings for a season, or [] if none stored."""
    stmt = (
        select(DriverStanding, Driver)
        .join(Driver, DriverStanding.driver_id == Driver.id)
        .where(DriverStanding.season == season)
        .order_by(DriverStanding.position)
    )
    rows = (await db.execute(stmt)).all()

    result = []
    for standing, driver in rows:
        result.append(
            {
                "position": standing.position,
                "points": standing.points,
                "wins": standing.wins,
                "driver_ref": driver.driver_ref,
                "code": driver.code,
                "given_name": driver.given_name,
                "family_name": driver.family_name,
                "nationality": driver.nationality,
                "dob": driver.dob,
            }
        )
    return result


async def get_constructor_standings_from_db(db: AsyncSession, season: str) -> list[dict]:
    """Return cached constructor standings for a season, or [] if none stored."""
    stmt = (
        select(ConstructorStanding, Constructor)
        .join(Constructor, ConstructorStanding.constructor_id == Constructor.id)
        .where(ConstructorStanding.season == season)
        .order_by(ConstructorStanding.position)
    )
    rows = (await db.execute(stmt)).all()

    result = []
    for standing, constructor in rows:
        result.append(
            {
                "position": standing.position,
                "points": standing.points,
                "wins": standing.wins,
                "constructor_ref": constructor.constructor_ref,
                "name": constructor.name,
                "nationality": constructor.nationality,
            }
        )
    return result


# ---------- WRITE (persist fetched data) ----------

async def _get_or_create_season(db: AsyncSession, year: str) -> Season:
    existing = (
        await db.execute(select(Season).where(Season.year == year))
    ).scalar_one_or_none()
    if existing:
        return existing
    season = Season(year=year)
    db.add(season)
    await db.flush()
    return season


async def _get_or_create_driver(db: AsyncSession, data: dict) -> Driver:
    existing = (
        await db.execute(
            select(Driver).where(Driver.driver_ref == data["driver_ref"])
        )
    ).scalar_one_or_none()
    if existing:
        return existing
    driver = Driver(
        driver_ref=data["driver_ref"],
        code=data.get("code"),
        given_name=data.get("given_name") or "",
        family_name=data.get("family_name") or "",
        nationality=data.get("nationality"),
        dob=data.get("dob"),
    )
    db.add(driver)
    await db.flush()
    return driver


async def _get_or_create_constructor(db: AsyncSession, ref: str, name: str, nationality) -> Constructor:
    existing = (
        await db.execute(
            select(Constructor).where(Constructor.constructor_ref == ref)
        )
    ).scalar_one_or_none()
    if existing:
        return existing
    constructor = Constructor(
        constructor_ref=ref,
        name=name or "",
        nationality=nationality,
    )
    db.add(constructor)
    await db.flush()
    return constructor


async def save_driver_standings(db: AsyncSession, season: str, rows: list[dict]) -> None:
    """Persist driver standings for a season (idempotent on season+driver)."""
    await _get_or_create_season(db, season)

    for row in rows:
        if not row.get("driver_ref"):
            continue
        driver = await _get_or_create_driver(db, row)

        # skip if this standing already exists (unique on season+driver)
        existing = (
            await db.execute(
                select(DriverStanding).where(
                    DriverStanding.season == season,
                    DriverStanding.driver_id == driver.id,
                )
            )
        ).scalar_one_or_none()
        if existing:
            continue

        db.add(
            DriverStanding(
                season=season,
                driver_id=driver.id,
                position=row.get("position"),
                points=row.get("points"),
                wins=row.get("wins"),
            )
        )

    await db.commit()


async def save_constructor_standings(db: AsyncSession, season: str, rows: list[dict]) -> None:
    """Persist constructor standings for a season (idempotent on season+constructor)."""
    await _get_or_create_season(db, season)

    for row in rows:
        if not row.get("constructor_ref"):
            continue
        constructor = await _get_or_create_constructor(
            db, row["constructor_ref"], row.get("name"), row.get("nationality")
        )

        existing = (
            await db.execute(
                select(ConstructorStanding).where(
                    ConstructorStanding.season == season,
                    ConstructorStanding.constructor_id == constructor.id,
                )
            )
        ).scalar_one_or_none()
        if existing:
            continue

        db.add(
            ConstructorStanding(
                season=season,
                constructor_id=constructor.id,
                position=row.get("position"),
                points=row.get("points"),
                wins=row.get("wins"),
            )
        )

    await db.commit()


async def get_races_from_db(db: AsyncSession, season: str) -> list[dict]:
    """Return cached race schedule for a season, or [] if none stored."""
    stmt = (
        select(Race)
        .where(Race.season == season)
        .order_by(Race.round)
    )
    races = (await db.execute(stmt)).scalars().all()

    return [
        {
            "round": race.round,
            "race_name": race.race_name,
            "circuit_name": race.circuit_name,
            "country": race.country,
            "locality": race.locality,
            "date": race.date,
            "time": race.time,
        }
        for race in races
    ]


async def save_races(db: AsyncSession, season: str, rows: list[dict]) -> None:
    """Persist race schedule for a season (idempotent on season+round)."""
    await _get_or_create_season(db, season)

    for row in rows:
        if row.get("round") is None:
            continue

        existing = (
            await db.execute(
                select(Race).where(
                    Race.season == season,
                    Race.round == row["round"],
                )
            )
        ).scalar_one_or_none()
        if existing:
            continue

        db.add(
            Race(
                season=season,
                round=row["round"],
                race_name=row.get("race_name") or "",
                circuit_name=row.get("circuit_name"),
                country=row.get("country"),
                locality=row.get("locality"),
                date=row.get("date"),
                time=row.get("time"),
            )
        )

    await db.commit()


async def get_driver_career_from_db(db: AsyncSession, driver_ref: str) -> dict | None:
    """Return cached career stats for a driver, or None if not stored."""
    existing = (
        await db.execute(
            select(DriverCareer).where(DriverCareer.driver_ref == driver_ref)
        )
    ).scalar_one_or_none()
    if not existing:
        return None

    return {
        "driver_ref": existing.driver_ref,
        "code": existing.code,
        "given_name": existing.given_name,
        "family_name": existing.family_name,
        "nationality": existing.nationality,
        "dob": existing.dob,
        "races": existing.races,
        "wins": existing.wins,
        "podiums": existing.podiums,
        "poles": existing.poles,
        "total_points": existing.total_points,
        "win_rate": existing.win_rate,
        "podium_rate": existing.podium_rate,
        "points_per_season": existing.points_per_season,
    }


async def save_driver_career(db: AsyncSession, data: dict) -> None:
    """Persist a driver's career stats (idempotent on driver_ref)."""
    existing = (
        await db.execute(
            select(DriverCareer).where(
                DriverCareer.driver_ref == data["driver_ref"]
            )
        )
    ).scalar_one_or_none()
    if existing:
        return

    db.add(
        DriverCareer(
            driver_ref=data["driver_ref"],
            code=data.get("code"),
            given_name=data.get("given_name") or "",
            family_name=data.get("family_name") or "",
            nationality=data.get("nationality"),
            dob=data.get("dob"),
            races=data.get("races"),
            wins=data.get("wins"),
            podiums=data.get("podiums"),
            poles=data.get("poles"),
            total_points=data.get("total_points"),
            win_rate=data.get("win_rate"),
            podium_rate=data.get("podium_rate"),
            points_per_season=data.get("points_per_season"),
        )
    )
    await db.commit()


async def search_drivers(db: AsyncSession, query: str, limit: int = 20) -> list[dict]:
    """
    Search cached drivers by name (case-insensitive, partial match on
    given name, family name, or full name). Returns a list of matches.
    """
    q = f"%{query.lower()}%"
    stmt = (
        select(Driver)
        .where(
            func.lower(Driver.given_name).like(q)
            | func.lower(Driver.family_name).like(q)
            | func.lower(
                Driver.given_name + " " + Driver.family_name
            ).like(q)
        )
        .order_by(Driver.family_name)
        .limit(limit)
    )
    drivers = (await db.execute(stmt)).scalars().all()

    return [
        {
            "driver_ref": d.driver_ref,
            "code": d.code,
            "given_name": d.given_name,
            "family_name": d.family_name,
            "nationality": d.nationality,
        }
        for d in drivers
    ]


async def list_drivers(db: AsyncSession, limit: int = 50) -> list[dict]:
    """Return all cached drivers (used when the search box is empty)."""
    stmt = select(Driver).order_by(Driver.family_name).limit(limit)
    drivers = (await db.execute(stmt)).scalars().all()
    return [
        {
            "driver_ref": d.driver_ref,
            "code": d.code,
            "given_name": d.given_name,
            "family_name": d.family_name,
            "nationality": d.nationality,
        }
        for d in drivers
    ]


async def list_seasons(db: AsyncSession) -> list[str]:
    """Return all cached season years, newest first."""
    stmt = select(Season.year).order_by(Season.year.desc())
    years = (await db.execute(stmt)).scalars().all()
    return list(years)


def _full_name(d: dict | None) -> str | None:
    if not d:
        return None
    given = d.get("given_name") or ""
    family = d.get("family_name") or ""
    name = f"{given} {family}".strip()
    return name or None


async def get_race_winners_from_db(db: AsyncSession, season: str) -> list[dict]:
    """Return cached race podiums for a season, or [] if none stored."""
    stmt = (
        select(RaceWinner)
        .where(RaceWinner.season == season)
        .order_by(RaceWinner.round)
    )
    rows = (await db.execute(stmt)).scalars().all()

    return [
        {
            "round": rw.round,
            "race_name": rw.race_name,
            "podium": {
                "first": {"driver": rw.first_driver, "driver_ref": rw.first_driver_ref, "team": rw.first_team},
                "second": {"driver": rw.second_driver, "driver_ref": rw.second_driver_ref, "team": rw.second_team},
                "third": {"driver": rw.third_driver, "driver_ref": rw.third_driver_ref, "team": rw.third_team},
            },
        }
        for rw in rows
    ]


async def save_race_winners(db: AsyncSession, season: str, rows: list[dict]) -> None:
    """Persist race podiums for a season (idempotent on season+round)."""
    await _get_or_create_season(db, season)

    for row in rows:
        rnd = row.get("round")
        if rnd is None:
            continue

        existing = (
            await db.execute(
                select(RaceWinner).where(
                    RaceWinner.season == season,
                    RaceWinner.round == rnd,
                )
            )
        ).scalar_one_or_none()
        if existing:
            continue

        first = row.get("first")
        second = row.get("second")
        third = row.get("third")

        db.add(
            RaceWinner(
                season=season,
                round=rnd,
                race_name=row.get("race_name"),
                first_driver=_full_name(first),
                first_driver_ref=(first or {}).get("driver_ref"),
                first_team=(first or {}).get("constructor_name"),
                second_driver=_full_name(second),
                second_driver_ref=(second or {}).get("driver_ref"),
                second_team=(second or {}).get("constructor_name"),
                third_driver=_full_name(third),
                third_driver_ref=(third or {}).get("driver_ref"),
                third_team=(third or {}).get("constructor_name"),
            )
        )

    await db.commit()


async def ensure_year_list(db: AsyncSession, start: int = 1950, end: int | None = None) -> None:
    """
    Populate year_list with every season from `start` to `end` (current year
    if not given), but only insert years that aren't already there.
    F1's first World Championship season was 1950.
    """
    from datetime import datetime

    if end is None:
        end = datetime.now().year

    existing = set(
        (await db.execute(select(YearList.year))).scalars().all()
    )

    added = False
    for y in range(start, end + 1):
        ys = str(y)
        if ys not in existing:
            db.add(YearList(year=ys))
            added = True

    if added:
        await db.commit()


async def get_year_list(db: AsyncSession) -> list[dict]:
    """
    Return every selectable year (newest first), each flagged with whether
    it's already cached (present in the `seasons` table).
    """
    all_years = (
        await db.execute(select(YearList.year).order_by(YearList.year.desc()))
    ).scalars().all()

    cached_years = set(
        (await db.execute(select(Season.year))).scalars().all()
    )

    return [
        {"year": y, "cached": (y in cached_years)}
        for y in all_years
    ]