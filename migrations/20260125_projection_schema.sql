-- Projection schema enhancements: constraints, provenance, ratings, and market linkage.
-- NOTE: This file is for review/migration planning only.

-- 1) Provenance table to trace projection runs.
CREATE TABLE IF NOT EXISTS public.projection_runs (
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version text NOT NULL,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  git_sha text,
  inputs_hash text,
  notes text,
  status text NOT NULL DEFAULT 'success',
  CONSTRAINT projection_runs_model_version_fkey
    FOREIGN KEY (model_version) REFERENCES public.model_versions(model_version)
);

-- 2) Add projection_run_id to projection tables for lineage.
ALTER TABLE public.game_projections
  ADD COLUMN IF NOT EXISTS projection_run_id uuid;
ALTER TABLE public.player_projections
  ADD COLUMN IF NOT EXISTS projection_run_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'game_projections_run_id_fkey'
  ) THEN
    ALTER TABLE public.game_projections
      ADD CONSTRAINT game_projections_run_id_fkey
      FOREIGN KEY (projection_run_id) REFERENCES public.projection_runs(run_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'player_projections_run_id_fkey'
  ) THEN
    ALTER TABLE public.player_projections
      ADD CONSTRAINT player_projections_run_id_fkey
      FOREIGN KEY (projection_run_id) REFERENCES public.projection_runs(run_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_game_projections_run_id
  ON public.game_projections (projection_run_id);
CREATE INDEX IF NOT EXISTS idx_player_projections_run_id
  ON public.player_projections (projection_run_id);

-- 3) Optional distribution metadata for game-level scoring model.
ALTER TABLE public.game_projections
  ADD COLUMN IF NOT EXISTS goals_dist text;
ALTER TABLE public.game_projections
  ADD COLUMN IF NOT EXISTS goals_params jsonb;

-- 4) Market lines (raw sportsbook data) and consensus snapshots.
CREATE TABLE IF NOT EXISTS public.market_lines (
  market_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_id bigint NOT NULL,
  market text NOT NULL,
  side text NOT NULL,
  line_value numeric,
  odds_american integer,
  book text,
  as_of timestamp with time zone NOT NULL DEFAULT now(),
  is_consensus boolean NOT NULL DEFAULT false,
  team_id integer,
  player_id integer,
  prop text,
  CONSTRAINT market_lines_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(game_id),
  CONSTRAINT market_lines_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(team_id),
  CONSTRAINT market_lines_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(player_id)
);

CREATE TABLE IF NOT EXISTS public.market_consensus (
  consensus_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_id bigint NOT NULL,
  market text NOT NULL,
  side text NOT NULL,
  line_value numeric,
  odds_american integer,
  as_of timestamp with time zone NOT NULL DEFAULT now(),
  team_id integer,
  player_id integer,
  prop text,
  source text,
  CONSTRAINT market_consensus_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(game_id),
  CONSTRAINT market_consensus_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(team_id),
  CONSTRAINT market_consensus_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(player_id)
);

-- Normalized line key for market tables (avoids 6.5 vs 6.50 drift).
ALTER TABLE public.market_lines
  ADD COLUMN IF NOT EXISTS line_value_key integer;
ALTER TABLE public.market_consensus
  ADD COLUMN IF NOT EXISTS line_value_key integer;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_lines_line_value_key_chk'
  ) THEN
    ALTER TABLE public.market_lines
      ADD CONSTRAINT market_lines_line_value_key_chk
      CHECK (
        line_value_key IS NULL
        OR line_value_key = ROUND(line_value * 10)::integer
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_consensus_line_value_key_chk'
  ) THEN
    ALTER TABLE public.market_consensus
      ADD CONSTRAINT market_consensus_line_value_key_chk
      CHECK (
        line_value_key IS NULL
        OR line_value_key = ROUND(line_value * 10)::integer
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_market_lines_game_id
  ON public.market_lines (game_id);
CREATE INDEX IF NOT EXISTS idx_market_lines_as_of
  ON public.market_lines (as_of);
CREATE INDEX IF NOT EXISTS idx_market_lines_team_id
  ON public.market_lines (team_id);
CREATE INDEX IF NOT EXISTS idx_market_lines_player_id
  ON public.market_lines (player_id);

CREATE INDEX IF NOT EXISTS idx_market_consensus_game_id
  ON public.market_consensus (game_id);
CREATE INDEX IF NOT EXISTS idx_market_consensus_as_of
  ON public.market_consensus (as_of);
CREATE INDEX IF NOT EXISTS idx_market_consensus_team_id
  ON public.market_consensus (team_id);
CREATE INDEX IF NOT EXISTS idx_market_consensus_player_id
  ON public.market_consensus (player_id);

-- Market/side constraints for market tables.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_lines_market_chk'
  ) THEN
    ALTER TABLE public.market_lines
      ADD CONSTRAINT market_lines_market_chk
      CHECK (market IN ('moneyline', 'spread', 'total', 'team_total', 'player_prop'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_lines_side_chk'
  ) THEN
    ALTER TABLE public.market_lines
      ADD CONSTRAINT market_lines_side_chk
      CHECK (
        (market = 'moneyline' AND side IN ('home', 'away')) OR
        (market = 'spread' AND side IN ('home', 'away')) OR
        (market = 'total' AND side IN ('over', 'under')) OR
        (market = 'team_total' AND side IN ('over', 'under')) OR
        (market = 'player_prop' AND side IN ('over', 'under'))
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_lines_team_req_chk'
  ) THEN
    ALTER TABLE public.market_lines
      ADD CONSTRAINT market_lines_team_req_chk
      CHECK (market != 'team_total' OR team_id IS NOT NULL);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_lines_player_req_chk'
  ) THEN
    ALTER TABLE public.market_lines
      ADD CONSTRAINT market_lines_player_req_chk
      CHECK (market != 'player_prop' OR player_id IS NOT NULL);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_consensus_market_chk'
  ) THEN
    ALTER TABLE public.market_consensus
      ADD CONSTRAINT market_consensus_market_chk
      CHECK (market IN ('moneyline', 'spread', 'total', 'team_total', 'player_prop'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_consensus_side_chk'
  ) THEN
    ALTER TABLE public.market_consensus
      ADD CONSTRAINT market_consensus_side_chk
      CHECK (
        (market = 'moneyline' AND side IN ('home', 'away')) OR
        (market = 'spread' AND side IN ('home', 'away')) OR
        (market = 'total' AND side IN ('over', 'under')) OR
        (market = 'team_total' AND side IN ('over', 'under')) OR
        (market = 'player_prop' AND side IN ('over', 'under'))
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_consensus_team_req_chk'
  ) THEN
    ALTER TABLE public.market_consensus
      ADD CONSTRAINT market_consensus_team_req_chk
      CHECK (market != 'team_total' OR team_id IS NOT NULL);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_consensus_player_req_chk'
  ) THEN
    ALTER TABLE public.market_consensus
      ADD CONSTRAINT market_consensus_player_req_chk
      CHECK (market != 'player_prop' OR player_id IS NOT NULL);
  END IF;
END $$;

-- 5) Model-vs-market evaluations (probability for a given market line).
CREATE TABLE IF NOT EXISTS public.model_market_eval (
  eval_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  model_version text NOT NULL,
  projection_run_id uuid,
  market_line_id bigint,
  consensus_id bigint,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  prob_model numeric NOT NULL,
  fair_odds_american integer,
  edge numeric,
  notes text,
  CONSTRAINT model_market_eval_model_version_fkey
    FOREIGN KEY (model_version) REFERENCES public.model_versions(model_version),
  CONSTRAINT model_market_eval_run_id_fkey
    FOREIGN KEY (projection_run_id) REFERENCES public.projection_runs(run_id),
  CONSTRAINT model_market_eval_market_line_fkey
    FOREIGN KEY (market_line_id) REFERENCES public.market_lines(market_line_id),
  CONSTRAINT model_market_eval_consensus_fkey
    FOREIGN KEY (consensus_id) REFERENCES public.market_consensus(consensus_id),
  CONSTRAINT model_market_eval_line_or_consensus_chk
    CHECK ((market_line_id IS NOT NULL) <> (consensus_id IS NOT NULL)),
  CONSTRAINT model_market_eval_prob_chk
    CHECK (prob_model >= 0 AND prob_model <= 1)
);

CREATE INDEX IF NOT EXISTS idx_model_market_eval_market_line
  ON public.model_market_eval (market_line_id);
CREATE INDEX IF NOT EXISTS idx_model_market_eval_consensus
  ON public.model_market_eval (consensus_id);
CREATE INDEX IF NOT EXISTS idx_model_market_eval_run_id
  ON public.model_market_eval (projection_run_id);

-- 6) Probability/value constraints on core projections.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'game_projections_home_win_prob_chk'
  ) THEN
    ALTER TABLE public.game_projections
      ADD CONSTRAINT game_projections_home_win_prob_chk
      CHECK (home_win_prob >= 0 AND home_win_prob <= 1);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'game_projections_away_win_prob_chk'
  ) THEN
    ALTER TABLE public.game_projections
      ADD CONSTRAINT game_projections_away_win_prob_chk
      CHECK (away_win_prob >= 0 AND away_win_prob <= 1);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'player_projections_nonneg_chk'
  ) THEN
    ALTER TABLE public.player_projections
      ADD CONSTRAINT player_projections_nonneg_chk
      CHECK (
        (toi_seconds_mean IS NULL OR toi_seconds_mean >= 0) AND
        (shots_mean IS NULL OR shots_mean >= 0) AND
        (goals_mean IS NULL OR goals_mean >= 0) AND
        (assists_mean IS NULL OR assists_mean >= 0) AND
        (points_mean IS NULL OR points_mean >= 0) AND
        (saves_mean IS NULL OR saves_mean >= 0) AND
        (goals_against_mean IS NULL OR goals_against_mean >= 0)
      );
  END IF;
END $$;

-- 7) Ratings tables to support consistent inputs.
CREATE TABLE IF NOT EXISTS public.team_ratings (
  team_id integer NOT NULL,
  model_version text NOT NULL,
  as_of_date date NOT NULL,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  attack_rating numeric,
  defense_rating numeric,
  pp_attack_rating numeric,
  pk_defense_rating numeric,
  pace_rating numeric,
  home_ice_rating numeric,
  inputs_hash text,
  notes text,
  CONSTRAINT team_ratings_pkey PRIMARY KEY (team_id, model_version, as_of_date),
  CONSTRAINT team_ratings_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(team_id),
  CONSTRAINT team_ratings_model_version_fkey FOREIGN KEY (model_version) REFERENCES public.model_versions(model_version)
);

CREATE TABLE IF NOT EXISTS public.player_ratings (
  player_id integer NOT NULL,
  team_id integer,
  model_version text NOT NULL,
  as_of_date date NOT NULL,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  position text,
  is_goalie boolean NOT NULL DEFAULT false,
  toi_rate numeric,
  shots_rate numeric,
  shooting_pct numeric,
  goals_rate numeric,
  assists_rate numeric,
  points_rate numeric,
  pp_share numeric,
  goalie_save_pct numeric,
  goalie_ga_rate numeric,
  inputs_hash text,
  notes text,
  CONSTRAINT player_ratings_pkey PRIMARY KEY (player_id, model_version, as_of_date),
  CONSTRAINT player_ratings_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(player_id),
  CONSTRAINT player_ratings_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(team_id),
  CONSTRAINT player_ratings_model_version_fkey FOREIGN KEY (model_version) REFERENCES public.model_versions(model_version)
);

-- 8) Indexes for common joins.
CREATE INDEX IF NOT EXISTS idx_game_results_game_id
  ON public.game_results (game_id);
CREATE INDEX IF NOT EXISTS idx_player_game_stats_player_id
  ON public.player_game_stats (player_id);
CREATE INDEX IF NOT EXISTS idx_player_game_stats_team_id
  ON public.player_game_stats (team_id);
CREATE INDEX IF NOT EXISTS idx_game_projections_game_id
  ON public.game_projections (game_id);
CREATE INDEX IF NOT EXISTS idx_player_projections_player_id
  ON public.player_projections (player_id);
CREATE INDEX IF NOT EXISTS idx_player_projections_team_id
  ON public.player_projections (team_id);

-- 9) RLS for client reads (authenticated only). Writes remain blocked unless explicitly allowed.
ALTER TABLE public.projection_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_projections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_projections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_consensus ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_market_eval ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_ratings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'projection_runs' AND policyname = 'select_authenticated_projection_runs'
  ) THEN
    CREATE POLICY select_authenticated_projection_runs
      ON public.projection_runs
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'game_projections' AND policyname = 'select_authenticated_game_projections'
  ) THEN
    CREATE POLICY select_authenticated_game_projections
      ON public.game_projections
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'player_projections' AND policyname = 'select_authenticated_player_projections'
  ) THEN
    CREATE POLICY select_authenticated_player_projections
      ON public.player_projections
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'market_lines' AND policyname = 'select_authenticated_market_lines'
  ) THEN
    CREATE POLICY select_authenticated_market_lines
      ON public.market_lines
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'market_consensus' AND policyname = 'select_authenticated_market_consensus'
  ) THEN
    CREATE POLICY select_authenticated_market_consensus
      ON public.market_consensus
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'model_market_eval' AND policyname = 'select_authenticated_model_market_eval'
  ) THEN
    CREATE POLICY select_authenticated_model_market_eval
      ON public.model_market_eval
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'team_ratings' AND policyname = 'select_authenticated_team_ratings'
  ) THEN
    CREATE POLICY select_authenticated_team_ratings
      ON public.team_ratings
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'player_ratings' AND policyname = 'select_authenticated_player_ratings'
  ) THEN
    CREATE POLICY select_authenticated_player_ratings
      ON public.player_ratings
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;
