import os
import math
import bisect
from collections import defaultdict
from datetime import datetime, timezone, timedelta, date
from typing import cast

from supabase import create_client
from dotenv import load_dotenv

try:
    from nhlpy import NHLClient
except Exception:
    NHLClient = None

load_dotenv(dotenv_path=".env")

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

# --- Helpers ---

def sb_exec(q, label: str):
    resp = q.execute()
    err = getattr(resp, "error", None)
    if err:
        raise RuntimeError(f"[supabase error] {label}: {err}")
    if isinstance(getattr(resp, "data", None), dict) and resp.data.get("error"):
        raise RuntimeError(f"[supabase error] {label}: {resp.data.get('error')}")
    return resp


def to_date(val) -> date:
    if isinstance(val, datetime):
        return val.date()
    if isinstance(val, date):
        return val
    return datetime.fromisoformat(str(val)).date()


def american_odds_from_prob(p: float) -> int | None:
    if p is None or p <= 0.0 or p >= 1.0:
        return None
    if p >= 0.5:
        return int(round(-100 * p / (1 - p)))
    return int(round(100 * (1 - p) / p))


def poisson_pmf(k: int, lam: float) -> float:
    return math.exp(-lam) * (lam ** k) / math.factorial(k)


def poisson_win_prob(lam_home: float, lam_away: float, max_goals: int = 12) -> float:
    p = 0.0
    for hg in range(0, max_goals + 1):
        ph = poisson_pmf(hg, lam_home)
        for ag in range(0, max_goals + 1):
            if hg > ag:
                p += ph * poisson_pmf(ag, lam_away)
    return max(0.0, min(1.0, p))


def poisson_total_over_prob(lam_total: float, line: float, max_goals: int = 20) -> float:
    threshold = int(math.floor(line)) + 1
    return max(
        0.0,
        min(1.0, sum(poisson_pmf(k, lam_total) for k in range(threshold, max_goals + 1))),
    )


def poisson_spread_cover_prob(lam_home: float, lam_away: float, spread_home: float, max_goals: int = 15) -> float:
    threshold = math.floor(-spread_home) + 1
    p = 0.0
    for hg in range(0, max_goals + 1):
        ph = poisson_pmf(hg, lam_home)
        for ag in range(0, max_goals + 1):
            if (hg - ag) >= threshold:
                p += ph * poisson_pmf(ag, lam_away)
    return max(0.0, min(1.0, p))


# --- Data pulls ---

def fetch_games(sb, start_date: date, end_date: date) -> list[dict]:
    resp = sb_exec(
        sb.table("games")
        .select("game_id,game_date,home_team_id,away_team_id,status")
        .gte("game_date", start_date.isoformat())
        .lte("game_date", end_date.isoformat()),
        "fetch games",
    )
    return resp.data or []

def fetch_team_abbrevs(sb, team_ids: list[int]) -> dict[int, str]:
    if not team_ids:
        return {}
    resp = sb_exec(
        sb.table("teams")
        .select("team_id,abbrev")
        .in_("team_id", team_ids),
        "fetch teams",
    )
    return {int(r["team_id"]): r["abbrev"] for r in (resp.data or []) if r.get("abbrev")}


def fetch_game_results(sb, game_ids: list[int]) -> dict[int, dict]:
    if not game_ids:
        return {}
    resp = sb_exec(
        sb.table("game_results")
        .select("game_id,home_goals,away_goals,home_sog,away_sog,home_pp_goals,away_pp_goals,home_pp_opps,away_pp_opps")
        .in_("game_id", game_ids),
        "fetch game_results",
    )
    return {r["game_id"]: r for r in (resp.data or [])}


def fetch_player_game_stats(sb, game_ids: list[int]) -> list[dict]:
    if not game_ids:
        return []
    resp = sb_exec(
        sb.table("player_game_stats")
        .select("game_id,player_id,team_id,is_goalie,toi_seconds,goals,assists,points,shots,pp_toi_seconds,sh_toi_seconds")
        .in_("game_id", game_ids),
        "fetch player_game_stats",
    )
    return resp.data or []


def ensure_model_version(sb, model_version: str, description: str | None = None):
    existing = (
        sb.table("model_versions")
        .select("model_version")
        .eq("model_version", model_version)
        .execute()
    )
    if existing.data:
        return
    row = {
        "model_version": model_version,
        "description": description or "auto-created by model pipeline",
        "git_sha": os.environ.get("GIT_SHA"),
        "is_active": True,
    }
    sb_exec(sb.table("model_versions").insert(row), "insert model_version")


# --- Feature building ---

def build_team_game_rows(games: list[dict], results_by_game: dict[int, dict]) -> list[dict]:
    rows: list[dict] = []
    for g in games:
        gid = g["game_id"]
        res = results_by_game.get(gid)
        if not res:
            continue
        game_date = to_date(g["game_date"])
        rows.append(
            {
                "game_id": gid,
                "game_date": game_date,
                "team_id": g["home_team_id"],
                "opp_team_id": g["away_team_id"],
                "is_home": True,
                "goals_for": res.get("home_goals"),
                "goals_against": res.get("away_goals"),
                "shots_for": res.get("home_sog"),
                "shots_against": res.get("away_sog"),
                "pp_goals": res.get("home_pp_goals"),
                "pp_opps": res.get("home_pp_opps"),
            }
        )
        rows.append(
            {
                "game_id": gid,
                "game_date": game_date,
                "team_id": g["away_team_id"],
                "opp_team_id": g["home_team_id"],
                "is_home": False,
                "goals_for": res.get("away_goals"),
                "goals_against": res.get("home_goals"),
                "shots_for": res.get("away_sog"),
                "shots_against": res.get("home_sog"),
                "pp_goals": res.get("away_pp_goals"),
                "pp_opps": res.get("away_pp_opps"),
            }
        )
    return rows


def compute_team_rolling(team_rows: list[dict], window: int = 10) -> dict[tuple[int, int], dict]:
    by_team = defaultdict(list)
    for r in team_rows:
        by_team[r["team_id"]].append(r)
    for tid in by_team:
        by_team[tid].sort(key=lambda x: x["game_date"])

    features: dict[tuple[int, int], dict] = {}
    for tid, rows in by_team.items():
        history: list[dict] = []
        for r in rows:
            # Use last N games prior to this game
            recent = history[-window:]
            if recent:
                gf = sum(x["goals_for"] or 0 for x in recent) / len(recent)
                ga = sum(x["goals_against"] or 0 for x in recent) / len(recent)
                sf = sum(x["shots_for"] or 0 for x in recent) / len(recent)
                sa = sum(x["shots_against"] or 0 for x in recent) / len(recent)
                pp_goals = sum(x["pp_goals"] or 0 for x in recent)
                pp_opps = sum(x["pp_opps"] or 0 for x in recent)
                pp_pct = (pp_goals / pp_opps) if pp_opps else None
            else:
                gf = ga = sf = sa = None
                pp_pct = None
            features[(r["game_id"], tid)] = {
                "gf_avg": gf,
                "ga_avg": ga,
                "sf_avg": sf,
                "sa_avg": sa,
                "pp_pct": pp_pct,
                "is_home": r["is_home"],
                "opp_team_id": r["opp_team_id"],
            }
            history.append(r)
    return features


def compute_latest_team_features(team_rows: list[dict], window: int = 10) -> dict[int, dict]:
    by_team = defaultdict(list)
    for r in team_rows:
        by_team[r["team_id"]].append(r)
    for tid in by_team:
        by_team[tid].sort(key=lambda x: x["game_date"])

    latest: dict[int, dict] = {}
    for tid, rows in by_team.items():
        history: list[dict] = []
        for r in rows:
            recent = history[-window:]
            if recent:
                gf = sum(x["goals_for"] or 0 for x in recent) / len(recent)
                ga = sum(x["goals_against"] or 0 for x in recent) / len(recent)
                sf = sum(x["shots_for"] or 0 for x in recent) / len(recent)
                sa = sum(x["shots_against"] or 0 for x in recent) / len(recent)
                pp_goals = sum(x["pp_goals"] or 0 for x in recent)
                pp_opps = sum(x["pp_opps"] or 0 for x in recent)
                pp_pct = (pp_goals / pp_opps) if pp_opps else None
            else:
                gf = ga = sf = sa = None
                pp_pct = None
            latest[tid] = {
                "gf_avg": gf,
                "ga_avg": ga,
                "sf_avg": sf,
                "sa_avg": sa,
                "pp_pct": pp_pct,
            }
            history.append(r)
    return latest


def compute_team_features_for_games(
    team_rows: list[dict], proj_games: list[dict], window: int = 10
) -> dict[tuple[int, int], dict]:
    by_team = defaultdict(list)
    for r in team_rows:
        by_team[r["team_id"]].append(r)
    team_dates: dict[int, list[date]] = {}
    for tid in by_team:
        by_team[tid].sort(key=lambda x: x["game_date"])
        team_dates[tid] = [cast(date, r["game_date"]) for r in by_team[tid]]

    features: dict[tuple[int, int], dict] = {}

    for g in proj_games:
        gid = g["game_id"]
        gdate = to_date(g["game_date"])
        for team_id, is_home, opp_team_id in (
            (g["home_team_id"], True, g["away_team_id"]),
            (g["away_team_id"], False, g["home_team_id"]),
        ):
            rows = by_team.get(team_id) or []
            dates = team_dates.get(team_id) or []
            idx = bisect.bisect_left(dates, gdate)
            recent = rows[max(0, idx - window) : idx]
            if recent:
                gf = sum(x["goals_for"] or 0 for x in recent) / len(recent)
                ga = sum(x["goals_against"] or 0 for x in recent) / len(recent)
                sf = sum(x["shots_for"] or 0 for x in recent) / len(recent)
                sa = sum(x["shots_against"] or 0 for x in recent) / len(recent)
                pp_goals = sum(x["pp_goals"] or 0 for x in recent)
                pp_opps = sum(x["pp_opps"] or 0 for x in recent)
                pp_pct = (pp_goals / pp_opps) if pp_opps else None
            else:
                gf = ga = sf = sa = None
                pp_pct = None

            features[(gid, team_id)] = {
                "gf_avg": gf,
                "ga_avg": ga,
                "sf_avg": sf,
                "sa_avg": sa,
                "pp_pct": pp_pct,
                "is_home": is_home,
                "opp_team_id": opp_team_id,
            }
    return features


def build_player_rolling(stats_rows: list[dict], window: int = 10) -> dict[tuple[int, int], dict]:
    by_player = defaultdict(list)
    for r in stats_rows:
        if r.get("is_goalie"):
            continue
        by_player[r["player_id"]].append(r)
    for pid in by_player:
        by_player[pid].sort(key=lambda x: x["game_id"])

    features: dict[tuple[int, int], dict] = {}
    for pid, rows in by_player.items():
        history: list[dict] = []
        for r in rows:
            recent = history[-window:]
            if recent:
                shots = sum(x.get("shots") or 0 for x in recent) / len(recent)
                goals = sum(x.get("goals") or 0 for x in recent) / len(recent)
                toi = sum(x.get("toi_seconds") or 0 for x in recent) / len(recent)
                shooting_pct = (goals / shots) if shots else None
            else:
                shots = goals = toi = shooting_pct = None
            features[(r["game_id"], pid)] = {
                "shots_avg": shots,
                "goals_avg": goals,
                "toi_avg": toi,
                "shooting_pct": shooting_pct,
                "team_id": r.get("team_id"),
            }
            history.append(r)
    return features


def season_string_for_date(d: date) -> str:
    start_year = d.year if d.month >= 7 else d.year - 1
    return f"{start_year}{start_year + 1}"


def _extract_player_id(obj) -> int | None:
    if not isinstance(obj, dict):
        return None
    for key in ("id", "playerId", "player_id", "personId", "person_id"):
        if obj.get(key) is not None:
            try:
                return int(obj.get(key))
            except Exception:
                return None
    person = obj.get("person")
    if isinstance(person, dict) and person.get("id") is not None:
        try:
            return int(person.get("id"))
        except Exception:
            return None
    return None


def extract_roster_player_ids(roster) -> list[int]:
    player_ids: list[int] = []

    def add_from_list(items):
        for p in items or []:
            pid = _extract_player_id(p)
            if pid is not None:
                player_ids.append(pid)

    if isinstance(roster, dict):
        for key in ("forwards", "defensemen", "defencemen", "skaters"):
            add_from_list(roster.get(key))
        # Fallback if API returns a flat "roster" list
        add_from_list(roster.get("roster"))
    elif isinstance(roster, list):
        add_from_list(roster)

    return sorted(set(player_ids))


def fetch_team_rosters(
    team_abbrev_by_id: dict[int, str], team_seasons: set[tuple[int, str]]
) -> dict[tuple[int, str], list[int]]:
    if not team_seasons:
        return {}
    if NHLClient is None:
        raise RuntimeError(
            "nhl-api-py is not installed. Install it to fetch rosters (pip install nhl-api-py)."
        )

    client = NHLClient()
    rosters: dict[tuple[int, str], list[int]] = {}
    for team_id, season in sorted(team_seasons):
        abbr = team_abbrev_by_id.get(team_id)
        if not abbr:
            continue
        if hasattr(client.teams, "team_roster"):
            roster = client.teams.team_roster(team_abbr=abbr, season=season)
        else:
            roster = client.teams.roster(team_abbr=abbr, season=season)
        rosters[(team_id, season)] = extract_roster_player_ids(roster)
    return rosters


def build_player_features_for_games(
    stats_rows: list[dict],
    game_date_by_id: dict[int, date],
    proj_games: list[dict],
    rosters_by_team_season: dict[tuple[int, str], list[int]],
    window: int = 10,
) -> dict[tuple[int, int], dict]:
    by_player = defaultdict(list)
    for r in stats_rows:
        if r.get("is_goalie"):
            continue
        gid = r.get("game_id")
        if gid is None:
            continue
        gdate = game_date_by_id.get(int(gid))
        if not gdate:
            continue
        rr = dict(r)
        rr["game_date"] = gdate
        by_player[int(r["player_id"])].append(rr)

    player_dates: dict[int, list[date]] = {}
    for pid in by_player:
        by_player[pid].sort(key=lambda x: x["game_date"])
        player_dates[pid] = [cast(date, r["game_date"]) for r in by_player[pid]]

    features: dict[tuple[int, int], dict] = {}
    for g in proj_games:
        gid = int(g["game_id"])
        gdate = to_date(g["game_date"])
        season = season_string_for_date(gdate)
        for team_id in (int(g["home_team_id"]), int(g["away_team_id"])):
            roster_ids = rosters_by_team_season.get((team_id, season)) or []
            for pid in roster_ids:
                rows = by_player.get(pid) or []
                dates = player_dates.get(pid) or []
                idx = bisect.bisect_left(dates, gdate)
                recent = rows[max(0, idx - window) : idx]
                if recent:
                    shots = sum(x.get("shots") or 0 for x in recent) / len(recent)
                    goals = sum(x.get("goals") or 0 for x in recent) / len(recent)
                    toi = sum(x.get("toi_seconds") or 0 for x in recent) / len(recent)
                    shooting_pct = (goals / shots) if shots else None
                else:
                    shots = goals = toi = shooting_pct = None
                features[(gid, pid)] = {
                    "shots_avg": shots,
                    "goals_avg": goals,
                    "toi_avg": toi,
                    "shooting_pct": shooting_pct,
                    "team_id": team_id,
                }
    return features


# --- Modeling (baseline) ---

def compute_expected_goals(home_feats: dict, away_feats: dict, league_avg: float) -> tuple[float, float]:
    # Simple attack/defense scaling with league average.
    home_attack = home_feats.get("gf_avg") or league_avg
    home_def = home_feats.get("ga_avg") or league_avg
    away_attack = away_feats.get("gf_avg") or league_avg
    away_def = away_feats.get("ga_avg") or league_avg

    lam_home = league_avg * (home_attack / league_avg) * (away_def / league_avg)
    lam_away = league_avg * (away_attack / league_avg) * (home_def / league_avg)

    # Mild home-ice bump
    lam_home *= 1.03
    return lam_home, lam_away


def build_game_projections(
    games: list[dict], team_features: dict[tuple[int, int], dict], league_avg: float
) -> list[dict]:
    rows: list[dict] = []
    now = datetime.now(timezone.utc).isoformat()
    for g in games:
        gid = g["game_id"]
        home_id = g["home_team_id"]
        away_id = g["away_team_id"]
        hf = team_features.get((gid, home_id))
        af = team_features.get((gid, away_id))
        if not hf or not af:
            continue
        lam_home, lam_away = compute_expected_goals(hf, af, league_avg)
        total_mean = lam_home + lam_away
        home_win_prob = poisson_win_prob(lam_home, lam_away)
        away_win_prob = 1.0 - home_win_prob
        rows.append(
            {
                "game_id": gid,
                "generated_at": now,
                "home_goals_mean": lam_home,
                "away_goals_mean": lam_away,
                "total_goals_mean": total_mean,
                "home_win_prob": home_win_prob,
                "away_win_prob": away_win_prob,
                "home_ml_american": american_odds_from_prob(home_win_prob),
                "away_ml_american": american_odds_from_prob(away_win_prob),
                "goals_dist": "poisson",
                "goals_params": {"lam_home": lam_home, "lam_away": lam_away},
            }
        )
    return rows


def build_player_projections(player_features: dict) -> list[dict]:
    rows: list[dict] = []
    now = datetime.now(timezone.utc).isoformat()
    for (gid, pid), f in player_features.items():
        shots_mean = f.get("shots_avg")
        shooting_pct = f.get("shooting_pct")
        goals_mean = None
        if shots_mean is not None and shooting_pct is not None:
            goals_mean = shots_mean * shooting_pct
        rows.append(
            {
                "game_id": gid,
                "player_id": pid,
                "team_id": f.get("team_id"),
                "generated_at": now,
                "shots_mean": shots_mean,
                "goals_mean": goals_mean,
            }
        )
    return rows


def main():
    sb = create_client(cast(str, SUPABASE_URL), cast(str, SUPABASE_SERVICE_ROLE_KEY))

    # Train/infer window: last 2 seasons of games for baselines, next 3 days for projections.
    today = datetime.now(timezone.utc).date()
    hist_start = today - timedelta(days=730)
    hist_end = today - timedelta(days=1)

    hist_games = fetch_games(sb, hist_start, hist_end)
    hist_game_ids = [g["game_id"] for g in hist_games]
    hist_results = fetch_game_results(sb, hist_game_ids)

    team_rows = build_team_game_rows(hist_games, hist_results)
    if not team_rows:
        print("[model] no historical team rows available")
        return

    league_avg = sum((r.get("goals_for") or 0) for r in team_rows) / max(1, len(team_rows))

    # Projection range start: default to start of 2025-2026 season, override via PROJ_START_DATE (YYYY-MM-DD).
    proj_start_env = os.environ.get("PROJ_START_DATE")
    proj_start = date.fromisoformat(proj_start_env) if proj_start_env else date(2025, 10, 1)
    proj_end = today + timedelta(days=2)
    proj_games = fetch_games(sb, proj_start, proj_end)

    team_features = compute_team_features_for_games(team_rows, proj_games, window=10)
    game_proj_rows = build_game_projections(proj_games, team_features, league_avg)

    game_date_by_id = {int(g["game_id"]): to_date(g["game_date"]) for g in hist_games + proj_games}
    proj_team_ids = sorted({int(g["home_team_id"]) for g in proj_games} | {int(g["away_team_id"]) for g in proj_games})
    team_abbrev_by_id = fetch_team_abbrevs(sb, proj_team_ids)
    team_seasons = {
        (int(tid), season_string_for_date(to_date(g["game_date"])))
        for g in proj_games
        for tid in (g["home_team_id"], g["away_team_id"])
    }
    rosters_by_team_season = fetch_team_rosters(team_abbrev_by_id, team_seasons)

    player_stats = fetch_player_game_stats(sb, hist_game_ids)
    player_features = build_player_features_for_games(
        player_stats,
        game_date_by_id,
        proj_games,
        rosters_by_team_season,
        window=10,
    )
    player_proj_rows = build_player_projections(player_features)

    # Persist projections
    model_version = "baseline-poisson-0.1"
    ensure_model_version(sb, model_version)
    run_row = {
        "model_version": model_version,
        "git_sha": os.environ.get("GIT_SHA"),
        "inputs_hash": None,
        "notes": "baseline poisson + rolling rates",
        "status": "success",
    }
    run = sb_exec(sb.table("projection_runs").insert(run_row), "insert projection_runs")
    run_id = run.data[0]["run_id"] if run.data else None

    for r in game_proj_rows:
        r["model_version"] = model_version
        r["projection_run_id"] = run_id
    for r in player_proj_rows:
        r["model_version"] = model_version
        r["projection_run_id"] = run_id
        r.setdefault("is_goalie", False)

    if game_proj_rows:
        sb_exec(
            sb.table("game_projections").upsert(game_proj_rows, on_conflict="game_id,model_version"),
            "upsert game_projections",
        )
    if player_proj_rows:
        sb_exec(
            sb.table("player_projections").upsert(player_proj_rows, on_conflict="game_id,model_version,player_id"),
            "upsert player_projections",
        )

    print(f"[model] wrote {len(game_proj_rows)} game projections")
    print(f"[model] wrote {len(player_proj_rows)} player projections")


if __name__ == "__main__":
    main()
