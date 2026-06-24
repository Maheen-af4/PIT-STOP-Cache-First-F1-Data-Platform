from __future__ import annotations

from sqlalchemy import (
    ForeignKey,
    Integer,
    JSON,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Season(Base):
    """One row per F1 season/year that we've fetched and cached."""
    __tablename__ = "seasons"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    year: Mapped[str] = mapped_column(String(4), nullable=False, unique=True)

    # back-references
    driver_standings: Mapped[list["DriverStanding"]] = relationship(
        "DriverStanding", back_populates="season_rel", cascade="all, delete-orphan"
    )
    constructor_standings: Mapped[list["ConstructorStanding"]] = relationship(
        "ConstructorStanding", back_populates="season_rel", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Season year={self.year!r}>"


class Driver(Base):
    __tablename__ = "drivers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    driver_ref: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    code: Mapped[str | None] = mapped_column(String(5), nullable=True)
    given_name: Mapped[str] = mapped_column(String(100), nullable=False)
    family_name: Mapped[str] = mapped_column(String(100), nullable=False)
    nationality: Mapped[str | None] = mapped_column(String(100), nullable=True)
    dob: Mapped[str | None] = mapped_column(String(20), nullable=True)

    standings: Mapped[list["DriverStanding"]] = relationship(
        "DriverStanding", back_populates="driver_rel"
    )

    def __repr__(self) -> str:
        return f"<Driver ref={self.driver_ref!r} {self.given_name} {self.family_name}>"


class Constructor(Base):
    __tablename__ = "constructors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    constructor_ref: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    nationality: Mapped[str | None] = mapped_column(String(100), nullable=True)

    standings: Mapped[list["ConstructorStanding"]] = relationship(
        "ConstructorStanding", back_populates="constructor_rel"
    )

    def __repr__(self) -> str:
        return f"<Constructor ref={self.constructor_ref!r} name={self.name!r}>"


class DriverStanding(Base):
    __tablename__ = "driver_standings"
    __table_args__ = (
        UniqueConstraint("season", "driver_id", name="uq_driver_standing_season"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    season: Mapped[str] = mapped_column(
        String(4), ForeignKey("seasons.year", ondelete="CASCADE"), nullable=False
    )
    driver_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("drivers.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int | None] = mapped_column(Integer, nullable=True)
    points: Mapped[float | None] = mapped_column(nullable=True)
    wins: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # relationships
    season_rel: Mapped["Season"] = relationship(
        "Season", back_populates="driver_standings"
    )
    driver_rel: Mapped["Driver"] = relationship(
        "Driver", back_populates="standings"
    )

    def __repr__(self) -> str:
        return f"<DriverStanding season={self.season!r} pos={self.position} pts={self.points}>"


class ConstructorStanding(Base):
    __tablename__ = "constructor_standings"
    __table_args__ = (
        UniqueConstraint("season", "constructor_id", name="uq_constructor_standing_season"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    season: Mapped[str] = mapped_column(
        String(4), ForeignKey("seasons.year", ondelete="CASCADE"), nullable=False
    )
    constructor_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("constructors.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int | None] = mapped_column(Integer, nullable=True)
    points: Mapped[float | None] = mapped_column(nullable=True)
    wins: Mapped[int | None] = mapped_column(Integer, nullable=True)

    season_rel: Mapped["Season"] = relationship(
        "Season", back_populates="constructor_standings"
    )
    constructor_rel: Mapped["Constructor"] = relationship(
        "Constructor", back_populates="standings"
    )

    def __repr__(self) -> str:
        return f"<ConstructorStanding season={self.season!r} pos={self.position} pts={self.points}>"


class Race(Base):
    __tablename__ = "races"
    __table_args__ = (
        UniqueConstraint("season", "round", name="uq_race_season_round"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    season: Mapped[str] = mapped_column(
        String(4), ForeignKey("seasons.year", ondelete="CASCADE"), nullable=False
    )
    round: Mapped[int] = mapped_column(Integer, nullable=False)
    race_name: Mapped[str] = mapped_column(String(200), nullable=False)
    circuit_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    country: Mapped[str | None] = mapped_column(String(100), nullable=True)
    locality: Mapped[str | None] = mapped_column(String(100), nullable=True)
    date: Mapped[str | None] = mapped_column(String(20), nullable=True)
    time: Mapped[str | None] = mapped_column(String(20), nullable=True)

    def __repr__(self) -> str:
        return f"<Race season={self.season!r} round={self.round} {self.race_name!r}>"


class DriverCareer(Base):
    __tablename__ = "driver_careers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    driver_ref: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    code: Mapped[str | None] = mapped_column(String(5), nullable=True)
    given_name: Mapped[str] = mapped_column(String(100), nullable=False)
    family_name: Mapped[str] = mapped_column(String(100), nullable=False)
    nationality: Mapped[str | None] = mapped_column(String(100), nullable=True)
    dob: Mapped[str | None] = mapped_column(String(20), nullable=True)
    races: Mapped[int | None] = mapped_column(Integer, nullable=True)
    wins: Mapped[int | None] = mapped_column(Integer, nullable=True)
    podiums: Mapped[int | None] = mapped_column(Integer, nullable=True)
    poles: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_points: Mapped[float | None] = mapped_column(nullable=True)
    win_rate: Mapped[float | None] = mapped_column(nullable=True)
    podium_rate: Mapped[float | None] = mapped_column(nullable=True)
    # points-per-season list stored as JSON
    points_per_season: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    def __repr__(self) -> str:
        return f"<DriverCareer ref={self.driver_ref!r} races={self.races} wins={self.wins}>"


class RaceWinner(Base):
    __tablename__ = "race_winners"
    __table_args__ = (
        UniqueConstraint("season", "round", name="uq_race_winner_season_round"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    season: Mapped[str] = mapped_column(
        String(4), ForeignKey("seasons.year", ondelete="CASCADE"), nullable=False
    )
    round: Mapped[int] = mapped_column(Integer, nullable=False)
    race_name: Mapped[str | None] = mapped_column(String(200), nullable=True)

    # P1
    first_driver: Mapped[str | None] = mapped_column(String(150), nullable=True)
    first_driver_ref: Mapped[str | None] = mapped_column(String(100), nullable=True)
    first_team: Mapped[str | None] = mapped_column(String(200), nullable=True)
    # P2
    second_driver: Mapped[str | None] = mapped_column(String(150), nullable=True)
    second_driver_ref: Mapped[str | None] = mapped_column(String(100), nullable=True)
    second_team: Mapped[str | None] = mapped_column(String(200), nullable=True)
    # P3
    third_driver: Mapped[str | None] = mapped_column(String(150), nullable=True)
    third_driver_ref: Mapped[str | None] = mapped_column(String(100), nullable=True)
    third_team: Mapped[str | None] = mapped_column(String(200), nullable=True)

    def __repr__(self) -> str:
        return f"<RaceWinner season={self.season!r} round={self.round} winner={self.first_driver!r}>"


class YearList(Base):
    """The full list of selectable F1 seasons (1950..present).

    This is distinct from `seasons`, which only holds years that have
    actually been fetched/cached. `year_list` powers the year dropdown so
    users can pick a year that hasn't been fetched yet.
    """
    __tablename__ = "year_list"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    year: Mapped[str] = mapped_column(String(4), nullable=False, unique=True)

    def __repr__(self) -> str:
        return f"<YearList year={self.year!r}>"