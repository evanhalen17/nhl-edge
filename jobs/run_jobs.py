from dotenv import load_dotenv
load_dotenv(dotenv_path=".env")

import os
import math
from datetime import datetime, timedelta, timezone, date
import requests
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

API_WEB = "https://api-web.nhle.com/v1"
API_GAMECENTER = "https://api-web.nhle.com/v1/gamecenter"
STATS_API_TEAMS_URL = "https://statsapi.web.nhl.com/api/v1/teams"


def american_odds_from_prob(p: float) -> int | None:
    if p is None or p <= 0.0 or p >= 1.0:
        return None
    if p >= 0.5:
        return int(round(-100 * p / (1 - p)))
    return int(round(100 * (1 - p) / p))


def poisson_pmf(k: int, lam: float) -> float:
    return math.exp(-lam) * (lam ** k) / math.factorial(k)


def poisson_total_over_prob(lam_total: float, line: float, max_goals: int = 20) -> float:
    # P(total > line). For 6.5 => P(total >= 7)
    threshold = int(math.floor(line)) + 1
    return max(
        0.0,
        min(1.0, sum(poisson_pmf(k, lam_total) for k in range(threshold, max_goals + 1))),
    )


def poisson_spread_cover_prob(lam_home: float, lam_away: float, spread_home: float, max_goals: int = 15) -> float:
    """
    Computes P( (home + spread_home) > away ) under independent Poisson goals.
    - spread_home = -1.5 => home must win by 2+ (diff >= 2)
    - spread_home = +1.5 => home can lose by 1 and still cover (diff >= -1)
    """
    # home covers if (hg + spread_home) > ag  <=>  (hg - ag) > -spread_home
    threshold = math.floor(-spread_home) + 1  # smallest integer diff satisfying diff > -spread_home
    p = 0.0
    for hg in range(0, max_goals + 1):
        ph = poisson_pmf(hg, lam_home)
        for ag in range(0, max_goals + 1):
            if (hg - ag) >= threshold:
                p += ph * poisson_pmf(ag, lam_away)
    return max(0.0, min(1.0, p))


def fetch_schedule(d: date) -> dict:
    url = f"{API_WEB}/schedule/{d.isoformat()}"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def upsert_teams(sb, teams: list[dict]):
    now = datetime.now(timezone.utc).isoformat()
    rows = []
    for t in teams:
        team_id = t.get("id") or t.get("teamId") or t.get("team_id")
        abbrev = t.get("abbrev") or t.get("abbreviation") or t.get("triCode")
        name = t.get("name", {}).get("default") if isinstance(t.get("name"), dict) else t.get("name")
        city = t.get("placeName", {}).get("default") if isinstance(t.get("placeName"), dict) else (t.get("city") or "Unknown")
        if team_id is None or abbrev is None or name is None:
            continue
        rows.append(
            {
                "team_id": int(team_id),
                "abbrev": abbrev,
                "name": name,
                "city": city,
                "updated_at": now,
            }
        )
    if rows:
        sb.table("teams").upsert(rows, on_conflict="team_id").execute()


def upsert_games_and_results(sb, schedule_json: dict):
    """
    Upsert teams + games + game_results from the schedule payload ONLY.
    Uses api-web.nhle.com schedule objects, which include team name + placeName.
    Avoids any dependency on statsapi.web.nhl.com.
    """
    games = []

    def scan(obj):
        if isinstance(obj, dict):
            if "homeTeam" in obj and "awayTeam" in obj and ("id" in obj or "gameId" in obj):
                games.append(obj)
            for v in obj.values():
                scan(v)
        elif isinstance(obj, list):
            for v in obj:
                scan(v)

    scan(schedule_json)

    now_iso = datetime.now(timezone.utc).isoformat()

    # Collect teams encountered in schedule
    teams_by_id: dict[int, dict] = {}

    def extract_default(v):
        # api-web often uses {"default": "..."} (or sometimes {"default": {"...": ...}}; handle string case)
        if isinstance(v, dict):
            dv = v.get("default")
            return dv if isinstance(dv, str) else None
        return v if isinstance(v, str) else None


    def add_team(t: dict):
        if not isinstance(t, dict):
            return
        tid = t.get("id") or t.get("teamId")
        if tid is None:
            return
        tid = int(tid)

        # Abbrev fields
        abbrev = t.get("abbrev") or t.get("triCode") or t.get("abbreviation")
        if not abbrev:
            # last resort placeholder, but this should rarely happen
            abbrev = f"T{tid}"

        # api-web schedule payload commonly has:
        # - t["name"]["default"] (e.g., "Sabres")
        # - t["placeName"]["default"] (e.g., "Buffalo")
        name = extract_default(t.get("name")) or extract_default(t.get("commonName")) or t.get("teamName") or f"Team {tid}"
        city = extract_default(t.get("placeName")) or extract_default(t.get("homePlaceName")) or extract_default(t.get("locationName")) or t.get("city") or "Unknown"


        logo_url = f"https://assets.nhle.com/logos/nhl/svg/{abbrev}_light.svg"

        existing = teams_by_id.get(tid)
        if existing is None:
            teams_by_id[tid] = {
                "team_id": tid,
                "abbrev": abbrev,
                "name": name,
                "city": city,
                "logo_url": logo_url,
                "updated_at": now_iso,
            }
        else:
            # Prefer non-placeholder values if we get better ones later in scan
            if existing.get("abbrev", "").startswith("T") and not abbrev.startswith("T"):
                existing["abbrev"] = abbrev
                existing["logo_url"] = logo_url
            if existing.get("name") in (None, "", f"Team {tid}") and name not in (None, "", f"Team {tid}"):
                existing["name"] = name
            if existing.get("city") in (None, "", "Unknown") and city not in (None, "", "Unknown"):
                existing["city"] = city
            existing["updated_at"] = now_iso

    games_rows = []
    results_rows = []

    for g in games:
        game_id = g.get("id") or g.get("gameId")
        if game_id is None:
            continue

        home = g.get("homeTeam", {}) or {}
        away = g.get("awayTeam", {}) or {}

        home_id = home.get("id") or home.get("teamId")
        away_id = away.get("id") or away.get("teamId")

        start_time = g.get("startTimeUTC") or g.get("startTime")
        if start_time is None or home_id is None or away_id is None:
            continue

        # Add teams first (so FK won't fail)
        add_team(home)
        add_team(away)

        raw_state = (g.get("gameState") or g.get("gameStatus") or "scheduled").lower()
        if raw_state in ("final", "gameover", "off"):
            status = "final"
        elif raw_state in ("live", "inprogress", "critical"):
            status = "live"
        else:
            status = "scheduled"

        game_date = g.get("gameDate") or start_time.split("T")[0]

        season = 20252026
        game_type = "R"

        games_rows.append(
            {
                "game_id": int(game_id),
                "season": int(season),
                "game_type": game_type,
                "game_date": game_date,
                "start_time_utc": start_time,
                "home_team_id": int(home_id),
                "away_team_id": int(away_id),
                "status": status,
                "venue": extract_default(g.get("venue")) or g.get("venue"),
                "last_ingested_at": now_iso,
            }
        )

        hs = home.get("score")
        as_ = away.get("score")
        if hs is not None and as_ is not None:
            results_rows.append(
                {
                    "game_id": int(game_id),
                    "home_goals": int(hs),
                    "away_goals": int(as_),
                    "updated_at": now_iso,
                }
            )

    # Upsert teams first (satisfies FKs)
    if teams_by_id:
        sb.table("teams").upsert(list(teams_by_id.values()), on_conflict="team_id").execute()

    if games_rows:
        sb.table("games").upsert(games_rows, on_conflict="game_id").execute()

    if results_rows:
        sb.table("game_results").upsert(results_rows, on_conflict="game_id").execute()

def upsert_team_directory(sb):
    """
    Populate teams table from NHL Stats API team directory (stable).
    This is the ONLY place we write teams.name/city/abbrev/logo_url.
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    url = "https://statsapi.web.nhl.com/api/v1/teams"

    r = requests.get(url, timeout=30)
    r.raise_for_status()
    data = r.json()

    teams = data.get("teams", [])
    if not isinstance(teams, list) or not teams:
        raise RuntimeError(f"Unexpected teams payload from {url}: keys={list(data.keys())}")

    rows = []
    for t in teams:
        team_id = t.get("id")
        if team_id is None:
            continue

        abbrev = t.get("abbreviation") or f"T{team_id}"
        city = t.get("locationName") or "Unknown"
        name = t.get("teamName") or t.get("name") or f"Team {team_id}"

        # SVG logo (as you want). Note: iOS needs an SVG renderer.
        logo_url = f"https://assets.nhle.com/logos/nhl/svg/{abbrev}_light.svg"

        rows.append({
            "team_id": int(team_id),
            "abbrev": abbrev,
            "name": name,
            "city": city,
            "logo_url": logo_url,
            "updated_at": now_iso,
        })

    sb.table("teams").upsert(rows, on_conflict="team_id").execute()
    print(f"[teams] upserted {len(rows)} teams from statsapi directory")


def fetch_gamecenter_landing(game_id: int) -> dict:
    """
    NHL api-web gamecenter landing endpoint. Contains scoring + team stats (SOG, PIM, PP, etc.).
    """
    url = f"{API_GAMECENTER}/{int(game_id)}/landing"
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


def _safe_int(v):
    try:
        return int(v) if v is not None else None
    except Exception:
        return None


def upsert_game_results_from_gamecenter(sb, game_id: int):
    """
    Populate game_results with richer final stats.
    Updates regardless, but only for games that are final/off.
    """
    data = fetch_gamecenter_landing(game_id)

    # Status gate
    raw_state = (data.get("gameState") or data.get("gameStatus") or "").lower()
    if raw_state not in ("final", "gameover", "off"):
        return  # don't write partials to game_results

    home = data.get("homeTeam", {}) or {}
    away = data.get("awayTeam", {}) or {}

    # Goals
    home_goals = _safe_int(home.get("score"))
    away_goals = _safe_int(away.get("score"))

    # Team stats (structure varies slightly; handle a few common patterns)
    # Often present under data["summary"]["teamGameStats"] or similar.
    summary = data.get("summary", {}) or {}
    team_stats = summary.get("teamGameStats") or summary.get("teamStats") or {}

    def get_stat(side: str, key: str):
        """
        Attempts to read a stat for 'home'/'away' from multiple shapes.
        """
        # Shape A: team_stats["homeTeam"]["sog"]
        side_obj = team_stats.get(f"{side}Team") or team_stats.get(side) or {}
        if isinstance(side_obj, dict) and key in side_obj:
            return side_obj.get(key)

        # Shape B: team_stats is list of dicts
        if isinstance(team_stats, list):
            for row in team_stats:
                if not isinstance(row, dict):
                    continue
                if row.get("team") == side and key in row:
                    return row.get(key)

        return None

    # Common keys in api-web:
    # shotsOnGoal / sog, powerPlayGoals / ppGoals, powerPlayOpportunities / ppOpportunities, pim
    home_sog = get_stat("home", "shotsOnGoal") or get_stat("home", "sog")
    away_sog = get_stat("away", "shotsOnGoal") or get_stat("away", "sog")

    home_pp_goals = get_stat("home", "powerPlayGoals") or get_stat("home", "ppGoals")
    away_pp_goals = get_stat("away", "powerPlayGoals") or get_stat("away", "ppGoals")

    home_pp_opps = get_stat("home", "powerPlayOpportunities") or get_stat("home", "ppOpportunities")
    away_pp_opps = get_stat("away", "powerPlayOpportunities") or get_stat("away", "ppOpportunities")

    home_pim = get_stat("home", "pim") or get_stat("home", "penaltyMinutes")
    away_pim = get_stat("away", "pim") or get_stat("away", "penaltyMinutes")

    # Final type sometimes exists in landing payload
    final_type = data.get("finalType") or data.get("gameOutcome") or None

    now_iso = datetime.now(timezone.utc).isoformat()

    row = {
        "game_id": int(game_id),
        "home_goals": _safe_int(home_goals),
        "away_goals": _safe_int(away_goals),
        "home_sog": _safe_int(home_sog),
        "away_sog": _safe_int(away_sog),
        "home_pp_goals": _safe_int(home_pp_goals),
        "away_pp_goals": _safe_int(away_pp_goals),
        "home_pp_opps": _safe_int(home_pp_opps),
        "away_pp_opps": _safe_int(away_pp_opps),
        "home_pim": _safe_int(home_pim),
        "away_pim": _safe_int(away_pim),
        "final_type": final_type,
        "updated_at": now_iso,
    }

    sb.table("game_results").upsert(row, on_conflict="game_id").execute()


def generate_poc_projections(sb, game_ids: list[int], model_version: str = "0.1.0"):
    """
    POC baseline so you can build the UI now:
    - fixed expected goals (replace later with real model)
    - Poisson-derived spread/total probabilities
    """
    now = datetime.now(timezone.utc).isoformat()

    lam_home = 3.15
    lam_away = 2.95

    # POC: equal win prob; replace later
    home_win_prob = 0.50
    away_win_prob = 0.50

    base_rows = []
    line_rows = []

    default_spreads = [-1.5, +1.5]
    default_totals = [5.5, 6.5]

    for gid in game_ids:
        total_mean = lam_home + lam_away

        base_rows.append(
            {
                "game_id": gid,
                "model_version": model_version,
                "generated_at": now,
                "home_goals_mean": lam_home,
                "away_goals_mean": lam_away,
                "total_goals_mean": total_mean,
                "home_win_prob": home_win_prob,
                "away_win_prob": away_win_prob,
                "home_ml_american": american_odds_from_prob(home_win_prob),
                "away_ml_american": american_odds_from_prob(away_win_prob),
            }
        )

        for s in default_spreads:
            p_home = poisson_spread_cover_prob(lam_home, lam_away, spread_home=s)
            p_away = 1.0 - p_home  # POC approximation

            line_rows.append(
                {
                    "game_id": gid,
                    "model_version": model_version,
                    "generated_at": now,
                    "market": "spread",
                    "line_value": s,
                    "side": "home",
                    "prob": p_home,
                    "fair_odds_american": american_odds_from_prob(p_home),
                }
            )
            line_rows.append(
                {
                    "game_id": gid,
                    "model_version": model_version,
                    "generated_at": now,
                    "market": "spread",
                    "line_value": s,
                    "side": "away",
                    "prob": p_away,
                    "fair_odds_american": american_odds_from_prob(p_away),
                }
            )

        for t in default_totals:
            p_over = poisson_total_over_prob(total_mean, t)
            p_under = 1.0 - p_over

            line_rows.append(
                {
                    "game_id": gid,
                    "model_version": model_version,
                    "generated_at": now,
                    "market": "total",
                    "line_value": t,
                    "side": "over",
                    "prob": p_over,
                    "fair_odds_american": american_odds_from_prob(p_over),
                }
            )
            line_rows.append(
                {
                    "game_id": gid,
                    "model_version": model_version,
                    "generated_at": now,
                    "market": "total",
                    "line_value": t,
                    "side": "under",
                    "prob": p_under,
                    "fair_odds_american": american_odds_from_prob(p_under),
                }
            )

    if base_rows:
        sb.table("game_projections").upsert(base_rows, on_conflict="game_id,model_version").execute()
    if line_rows:
        sb.table("game_projection_lines").upsert(
            line_rows, on_conflict="game_id,model_version,market,line_value,side"
        ).execute()


def main():
    sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    run = sb.table("ingestion_runs").insert({"job_name": "scheduled_ingest_and_project"}).execute()
    run_id = run.data[0]["run_id"] if run.data else None

    try:
        today = datetime.now(timezone.utc).date()
        dates = [today + timedelta(days=i) for i in range(-1, 3)]  # yesterday..+2

        all_game_ids: list[int] = []

        for d in dates:
            sched = fetch_schedule(d)

            # extract teams from schedule JSON
            teams = []

            def scan(obj):
                if isinstance(obj, dict):
                    if "homeTeam" in obj and isinstance(obj["homeTeam"], dict):
                        teams.append(obj["homeTeam"])
                    if "awayTeam" in obj and isinstance(obj["awayTeam"], dict):
                        teams.append(obj["awayTeam"])
                    for v in obj.values():
                        scan(v)
                elif isinstance(obj, list):
                    for v in obj:
                        scan(v)

            scan(sched)
            upsert_teams(sb, teams)
            upsert_games_and_results(sb, sched)

            # game ids for this date from DB (more reliable than parsing)
            g_rows = sb.table("games").select("game_id").eq("game_date", d.isoformat()).execute()
            # Backfill richer results for finals (SOG/PP/PIM/etc.)
            for r in (g_rows.data or []):
                gid = r["game_id"]
                try:
                    upsert_game_results_from_gamecenter(sb, gid)
                except Exception as e:
                    # Don't fail the whole run for one bad game payload
                    print(f"[game_results] failed for game_id={gid}: {e}")

            all_game_ids.extend([r["game_id"] for r in (g_rows.data or [])])

        all_game_ids = sorted(set(all_game_ids))
        if all_game_ids:
            generate_poc_projections(sb, all_game_ids, model_version="0.1.0")

        if run_id:
            sb.table("ingestion_runs").update(
                {"status": "success", "finished_at": datetime.now(timezone.utc).isoformat()}
            ).eq("run_id", run_id).execute()

    except Exception as e:
        if run_id:
            sb.table("ingestion_runs").update(
                {
                    "status": "error",
                    "finished_at": datetime.now(timezone.utc).isoformat(),
                    "message": str(e),
                }
            ).eq("run_id", run_id).execute()
        raise


if __name__ == "__main__":
    main()
