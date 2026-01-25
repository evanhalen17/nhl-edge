import os
from datetime import date, datetime, timedelta, timezone
from typing import cast

from dotenv import load_dotenv
from supabase import create_client

from run_jobs import (
    sb_exec,
    fetch_schedule,
    upsert_games_and_results,
    upsert_game_results_from_gamecenter,
    upsert_player_stats_from_boxscore,
    ensure_model_version,
    generate_poc_projections,
    upsert_team_directory,
)

load_dotenv(dotenv_path=".env")

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")


def _parse_date(s: str) -> date:
    return date.fromisoformat(s)


def backfill(start_date: date, end_date: date, include_projections: bool, model_version: str):
    sb = create_client(cast(str, SUPABASE_URL), cast(str, SUPABASE_SERVICE_ROLE_KEY))

    run = sb_exec(sb.table("ingestion_runs").insert({"job_name": "historical_backfill"}), "ingestion_runs")
    run_id = run.data[0]["run_id"] if run.data else None

    try:
        # Refresh team directory once for consistency (best-effort)
        try:
            upsert_team_directory(sb)
        except Exception as e:
            print(f"[teams] directory refresh failed (continuing): {e}")

        all_game_ids: list[int] = []

        d = start_date
        while d <= end_date:
            sched = fetch_schedule(d)
            upsert_games_and_results(sb, sched)

            g_rows = sb.table("games").select("game_id").eq("game_date", d.isoformat()).execute()
            print(f"[games] {d.isoformat()} -> {len(g_rows.data or [])} games in DB")

            for r in (g_rows.data or []):
                gid = r["game_id"]
                try:
                    upsert_game_results_from_gamecenter(sb, gid)
                    upsert_player_stats_from_boxscore(sb, gid)
                except Exception as e:
                    print(f"[backfill] failed for game_id={gid}: {e}")

            all_game_ids.extend([r["game_id"] for r in (g_rows.data or [])])
            d += timedelta(days=1)

        if include_projections and all_game_ids:
            ensure_model_version(sb, model_version)
            generate_poc_projections(sb, sorted(set(all_game_ids)), model_version=model_version)

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


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Historical backfill for NHL Edge data.")
    parser.add_argument("--start", required=True, help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end", required=True, help="End date (YYYY-MM-DD)")
    parser.add_argument("--include-projections", action="store_true", help="Also generate projections")
    parser.add_argument("--model-version", default="0.1.0", help="Model version for projections")
    args = parser.parse_args()

    start_date = _parse_date(args.start)
    end_date = _parse_date(args.end)
    if end_date < start_date:
        raise ValueError("end date must be >= start date")

    backfill(start_date, end_date, include_projections=args.include_projections, model_version=args.model_version)


if __name__ == "__main__":
    main()
