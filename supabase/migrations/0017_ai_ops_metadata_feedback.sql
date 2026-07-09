CREATE TABLE IF NOT EXISTS public.ai_runs (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_key               TEXT NOT NULL UNIQUE,
  source                TEXT NOT NULL CHECK (char_length(source) BETWEEN 1 AND 80),
  actor_type            TEXT NOT NULL DEFAULT 'edge_function'
    CHECK (actor_type IN ('edge_function', 'agent', 'cron', 'model', 'system', 'human_operator')),
  actor_id              TEXT CHECK (actor_id IS NULL OR char_length(actor_id) <= 160),
  model_name            TEXT CHECK (model_name IS NULL OR char_length(model_name) <= 160),
  model_version         TEXT CHECK (model_version IS NULL OR char_length(model_version) <= 160),
  decision_config_version TEXT CHECK (decision_config_version IS NULL OR char_length(decision_config_version) <= 160),
  code_version          TEXT CHECK (code_version IS NULL OR char_length(code_version) <= 160),
  input_schema_version  TEXT CHECK (input_schema_version IS NULL OR char_length(input_schema_version) <= 80),
  output_schema_version TEXT CHECK (output_schema_version IS NULL OR char_length(output_schema_version) <= 80),
  status                TEXT NOT NULL DEFAULT 'started'
    CHECK (status IN ('started', 'succeeded', 'failed', 'partial', 'cancelled')),
  metadata              JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_public          TEXT CHECK (error_public IS NULL OR char_length(error_public) <= 200),
  started_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE INDEX IF NOT EXISTS idx_ai_runs_source_time
  ON public.ai_runs (source, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_runs_status_time
  ON public.ai_runs (status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.ai_events (
  id              BIGSERIAL PRIMARY KEY,
  run_id          UUID REFERENCES public.ai_runs(id) ON DELETE SET NULL,
  event_type      TEXT NOT NULL CHECK (char_length(event_type) BETWEEN 1 AND 100),
  subject_table   TEXT CHECK (subject_table IS NULL OR char_length(subject_table) <= 80),
  subject_id      TEXT CHECK (subject_id IS NULL OR char_length(subject_id) <= 160),
  user_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  decision        TEXT CHECK (decision IS NULL OR char_length(decision) <= 120),
  confidence      NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  risk_score      NUMERIC(5,4) CHECK (risk_score IS NULL OR (risk_score >= 0 AND risk_score <= 1)),
  status          TEXT NOT NULL DEFAULT 'observed'
    CHECK (status IN ('observed', 'succeeded', 'failed', 'skipped', 'requires_review')),
  input_refs      JSONB NOT NULL DEFAULT '{}'::jsonb,
  output          JSONB NOT NULL DEFAULT '{}'::jsonb,
  public_summary  TEXT CHECK (public_summary IS NULL OR char_length(public_summary) <= 500),
  error_public    TEXT CHECK (error_public IS NULL OR char_length(error_public) <= 200),
  metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_events_run
  ON public.ai_events (run_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_events_user_time
  ON public.ai_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_events_subject
  ON public.ai_events (subject_table, subject_id);

CREATE INDEX IF NOT EXISTS idx_ai_events_type_time
  ON public.ai_events (event_type, created_at DESC);

CREATE TABLE IF NOT EXISTS public.ai_feedback (
  id              BIGSERIAL PRIMARY KEY,
  event_id        BIGINT REFERENCES public.ai_events(id) ON DELETE SET NULL,
  run_id          UUID REFERENCES public.ai_runs(id) ON DELETE SET NULL,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  feedback_type   TEXT NOT NULL DEFAULT 'quality'
    CHECK (feedback_type IN ('thumbs_up', 'thumbs_down', 'correction', 'appeal', 'bug', 'safety', 'quality', 'other')),
  rating          SMALLINT CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
  label           TEXT CHECK (label IS NULL OR char_length(label) <= 80),
  notes           TEXT CHECK (notes IS NULL OR char_length(notes) <= 2000),
  metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
  status          TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ai_feedback_event
  ON public.ai_feedback (event_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_feedback_user
  ON public.ai_feedback (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_feedback_status
  ON public.ai_feedback (status, created_at DESC);

ALTER TABLE public.ai_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role manages ai runs"
  ON public.ai_runs FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Service role manages ai events"
  ON public.ai_events FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Service role manages ai feedback"
  ON public.ai_feedback FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Users insert own ai feedback"
  ON public.ai_feedback FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users read own ai feedback"
  ON public.ai_feedback FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.log_ai_run(
  p_run_key TEXT,
  p_source TEXT,
  p_actor_type TEXT DEFAULT 'edge_function',
  p_actor_id TEXT DEFAULT NULL,
  p_model_name TEXT DEFAULT NULL,
  p_model_version TEXT DEFAULT NULL,
  p_decision_config_version TEXT DEFAULT NULL,
  p_code_version TEXT DEFAULT NULL,
  p_input_schema_version TEXT DEFAULT NULL,
  p_output_schema_version TEXT DEFAULT NULL,
  p_status TEXT DEFAULT 'started',
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_error_public TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_run_key IS NULL OR trim(p_run_key) = '' THEN
    RAISE EXCEPTION 'run_key required';
  END IF;
  IF p_source IS NULL OR trim(p_source) = '' THEN
    RAISE EXCEPTION 'source required';
  END IF;

  INSERT INTO public.ai_runs (
    run_key, source, actor_type, actor_id, model_name, model_version,
    decision_config_version, code_version, input_schema_version, output_schema_version,
    status, metadata, error_public
  )
  VALUES (
    p_run_key,
    trim(p_source),
    COALESCE(NULLIF(trim(p_actor_type), ''), 'edge_function'),
    NULLIF(trim(p_actor_id), ''),
    NULLIF(trim(p_model_name), ''),
    NULLIF(trim(p_model_version), ''),
    NULLIF(trim(p_decision_config_version), ''),
    NULLIF(trim(p_code_version), ''),
    NULLIF(trim(p_input_schema_version), ''),
    NULLIF(trim(p_output_schema_version), ''),
    COALESCE(NULLIF(trim(p_status), ''), 'started'),
    COALESCE(p_metadata, '{}'::jsonb),
    NULLIF(trim(p_error_public), '')
  )
  ON CONFLICT (run_key) DO UPDATE
    SET status = EXCLUDED.status,
        metadata = public.ai_runs.metadata || EXCLUDED.metadata,
        error_public = COALESCE(EXCLUDED.error_public, public.ai_runs.error_public)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_ai_run(
  p_run_id UUID,
  p_status TEXT,
  p_error_public TEXT DEFAULT NULL,
  p_metadata_patch JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.ai_runs
  SET status = COALESCE(NULLIF(trim(p_status), ''), status),
      error_public = COALESCE(NULLIF(trim(p_error_public), ''), error_public),
      metadata = metadata || COALESCE(p_metadata_patch, '{}'::jsonb),
      finished_at = NOW()
  WHERE id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI run not found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_ai_event(
  p_run_id UUID DEFAULT NULL,
  p_event_type TEXT DEFAULT 'event',
  p_subject_table TEXT DEFAULT NULL,
  p_subject_id TEXT DEFAULT NULL,
  p_user_id UUID DEFAULT NULL,
  p_decision TEXT DEFAULT NULL,
  p_confidence NUMERIC DEFAULT NULL,
  p_risk_score NUMERIC DEFAULT NULL,
  p_status TEXT DEFAULT 'observed',
  p_input_refs JSONB DEFAULT '{}'::jsonb,
  p_output JSONB DEFAULT '{}'::jsonb,
  p_public_summary TEXT DEFAULT NULL,
  p_error_public TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  IF p_event_type IS NULL OR trim(p_event_type) = '' THEN
    RAISE EXCEPTION 'event_type required';
  END IF;

  INSERT INTO public.ai_events (
    run_id, event_type, subject_table, subject_id, user_id, decision,
    confidence, risk_score, status, input_refs, output, public_summary,
    error_public, metadata
  )
  VALUES (
    p_run_id,
    trim(p_event_type),
    NULLIF(trim(p_subject_table), ''),
    NULLIF(trim(p_subject_id), ''),
    p_user_id,
    NULLIF(trim(p_decision), ''),
    p_confidence,
    p_risk_score,
    COALESCE(NULLIF(trim(p_status), ''), 'observed'),
    COALESCE(p_input_refs, '{}'::jsonb),
    COALESCE(p_output, '{}'::jsonb),
    NULLIF(trim(p_public_summary), ''),
    NULLIF(trim(p_error_public), ''),
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_ai_feedback(
  p_event_id BIGINT DEFAULT NULL,
  p_feedback_type TEXT DEFAULT 'quality',
  p_rating SMALLINT DEFAULT NULL,
  p_label TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event_user UUID;
  v_event_run UUID;
  v_id BIGINT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_event_id IS NOT NULL THEN
    SELECT user_id, run_id INTO v_event_user, v_event_run
    FROM public.ai_events
    WHERE id = p_event_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'AI event not found';
    END IF;

    IF v_event_user IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'Not authorized for this AI event'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO public.ai_feedback (
    event_id, run_id, user_id, feedback_type, rating, label, notes, metadata
  )
  VALUES (
    p_event_id,
    v_event_run,
    v_uid,
    COALESCE(NULLIF(trim(p_feedback_type), ''), 'quality'),
    p_rating,
    NULLIF(trim(p_label), ''),
    NULLIF(trim(p_notes), ''),
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.log_ai_run(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_ai_run(UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.log_ai_event(UUID, TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, JSONB, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_ai_feedback(BIGINT, TEXT, SMALLINT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.log_ai_run(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_ai_run(UUID, TEXT, TEXT, JSONB)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.log_ai_event(UUID, TEXT, TEXT, TEXT, UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, JSONB, TEXT, TEXT, JSONB)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_ai_feedback(BIGINT, TEXT, SMALLINT, TEXT, TEXT, JSONB)
  TO authenticated;
