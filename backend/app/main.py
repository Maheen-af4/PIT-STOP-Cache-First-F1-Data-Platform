from fastapi import FastAPI, Depends, BackgroundTasks, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import init_db, get_db, AsyncSessionLocal
from app import crud
from app.fetcher import (
    fetch_driver_standings,
    fetch_constructor_standings,
    fetch_races,
    fetch_driver_career,
    fetch_race_podiums,
    UpstreamUnavailable,
)

app = FastAPI(title="PIT STOP — F1 Cache API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    await init_db()
    # Make sure the full year list (1950..present) exists for the dropdown.
    async with AsyncSessionLocal() as db:
        await crud.ensure_year_list(db)


@app.get("/health")
async def health():
    return {"status": "ok"}


# ---------- background write helpers ----------
# These open their OWN session, because the request's session is closed
# once the response has been sent.

async def _bg_save_driver_standings(season: str, rows: list[dict]):
    async with AsyncSessionLocal() as db:
        await crud.save_driver_standings(db, season, rows)


async def _bg_save_constructor_standings(season: str, rows: list[dict]):
    async with AsyncSessionLocal() as db:
        await crud.save_constructor_standings(db, season, rows)


async def _bg_save_races(season: str, rows: list[dict]):
    async with AsyncSessionLocal() as db:
        await crud.save_races(db, season, rows)


async def _bg_save_driver_career(data: dict):
    async with AsyncSessionLocal() as db:
        await crud.save_driver_career(db, data)


async def _bg_save_race_winners(season: str, rows: list[dict]):
    async with AsyncSessionLocal() as db:
        await crud.save_race_winners(db, season, rows)


# ---------- cache-first endpoints ----------

@app.get("/standings/drivers/{season}")
async def driver_standings(
    season: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    cached = await crud.get_driver_standings_from_db(db, season)
    if cached:
        return {"season": season, "source": "cache", "standings": cached}

    try:
        fetched = await fetch_driver_standings(season)
    except UpstreamUnavailable:
        raise HTTPException(
            status_code=503,
            detail="F1 data source is temporarily unavailable. Please try again shortly.",
        )

    if fetched:
        background_tasks.add_task(_bg_save_driver_standings, season, fetched)

    return {"season": season, "source": "api", "standings": fetched}


@app.get("/standings/constructors/{season}")
async def constructor_standings(
    season: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    cached = await crud.get_constructor_standings_from_db(db, season)
    if cached:
        return {"season": season, "source": "cache", "standings": cached}

    try:
        fetched = await fetch_constructor_standings(season)
    except UpstreamUnavailable:
        raise HTTPException(
            status_code=503,
            detail="F1 data source is temporarily unavailable. Please try again shortly.",
        )

    if fetched:
        background_tasks.add_task(_bg_save_constructor_standings, season, fetched)

    return {"season": season, "source": "api", "standings": fetched}


@app.get("/races/{season}")
async def races(
    season: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    cached = await crud.get_races_from_db(db, season)
    if cached:
        return {"season": season, "source": "cache", "races": cached}

    try:
        fetched = await fetch_races(season)
    except UpstreamUnavailable:
        raise HTTPException(
            status_code=503,
            detail="F1 data source is temporarily unavailable. Please try again shortly.",
        )

    if fetched:
        background_tasks.add_task(_bg_save_races, season, fetched)

    return {"season": season, "source": "api", "races": fetched}


@app.get("/drivers/{driver_ref}/career")
async def driver_career(
    driver_ref: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    cached = await crud.get_driver_career_from_db(db, driver_ref)
    if cached:
        return {"driver_ref": driver_ref, "source": "cache", "career": cached}

    try:
        fetched = await fetch_driver_career(driver_ref)
    except UpstreamUnavailable:
        raise HTTPException(
            status_code=503,
            detail="F1 data source is temporarily unavailable. Please try again shortly.",
        )

    if fetched:
        background_tasks.add_task(_bg_save_driver_career, fetched)

    return {"driver_ref": driver_ref, "source": "api", "career": fetched}


@app.get("/search/drivers")
async def search_drivers(
    q: str = "",
    db: AsyncSession = Depends(get_db),
):
    query = q.strip()
    if not query:
        results = await crud.list_drivers(db)
    else:
        results = await crud.search_drivers(db, query)
    return {"query": query, "count": len(results), "drivers": results}


@app.get("/seasons")
async def seasons(db: AsyncSession = Depends(get_db)):
    years = await crud.list_seasons(db)
    return {"count": len(years), "seasons": years}


@app.get("/races/{season}/winners")
async def race_winners(
    season: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    cached = await crud.get_race_winners_from_db(db, season)
    if cached:
        return {"season": season, "source": "cache", "winners": cached}

    try:
        fetched = await fetch_race_podiums(season)
    except UpstreamUnavailable:
        raise HTTPException(
            status_code=503,
            detail="F1 data source is temporarily unavailable. Please try again shortly.",
        )

    if fetched:
        background_tasks.add_task(_bg_save_race_winners, season, fetched)

    return {"season": season, "source": "api", "winners": fetched}


@app.get("/years")
async def years(db: AsyncSession = Depends(get_db)):
    """
    Full list of selectable F1 seasons (1950..present), each flagged with
    whether it's already cached. Powers the year dropdown.
    """
    data = await crud.get_year_list(db)
    return {"count": len(data), "years": data}