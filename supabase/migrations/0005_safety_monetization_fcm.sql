-- =============================================================================
-- Migration 0005: Safety, monetization, FCM tokens, profile extensions
-- =============================================================================
-- Covers outline sections 11–13, 12:
--   blocks, reports, subscriptions, boosts, ad_impressions, push tokens,
--   account pause/delete fields, photo verification queue, incognito.
-- Safe on a fresh project after 0001–0004.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. Profile extensions (privacy + monetization flags)
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_incognito BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_subscriber BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS subscription_tier TEXT DEFAULT 'free'
    CHECK (subscription_tier IN ('free', 'plus', 'gold')),
  ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS neighborhood TEXT,
  ADD COLUMN IF NOT EXISTS location_history_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS show_ads BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS email_hint TEXT,
  ADD COLUMN IF NOT EXISTS phone_hint TEXT;

COMMENT ON COLUMN public.profiles.is_paused IS
  'Account pause: hidden from discovery; data retained.';
COMMENT ON COLUMN public.profiles.is_incognito IS
  'Subscriber feature: not shown in Locals unless mutual encounter.';
COMMENT ON COLUMN public.profiles.deleted_at IS
  'Soft delete timestamp; hard purge via cleanup job.';

-- ----------------------------------------------------------------------------
-- 2. Photo verification queue (AI stub + manual review)
-- ----------------------------------------------------------------------------
CREATE TYPE public.photo_verification_state AS ENUM (
  'pending_upload',
  'ai_review',
  'ai_passed',
  'ai_failed',
  'manual_review',
  'approved',
  'rejected'
);

CREATE TABLE IF NOT EXISTS public.photo_verifications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_path      TEXT NOT NULL,              -- storage path in profile_photos
  slot_index      SMALLINT NOT NULL CHECK (slot_index BETWEEN 0 AND 5),
  state           public.photo_verification_state NOT NULL DEFAULT 'pending_upload',
  ai_score        NUMERIC(5,4),              -- stub: 0–1 face/liveness score
  ai_notes        TEXT,
  reviewer_id     UUID,                      -- manual moderator (auth.users or staff)
  review_notes    TEXT,
  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_photo_verifications_user
  ON public.photo_verifications (user_id, state);

CREATE INDEX IF NOT EXISTS idx_photo_verifications_queue
  ON public.photo_verifications (state, submitted_at)
  WHERE state IN ('ai_review', 'manual_review');

CREATE TRIGGER photo_verifications_updated_at
  BEFORE UPDATE ON public.photo_verifications
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.photo_verifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own photo verifications"
  ON public.photo_verifications FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users insert own photo verifications"
  ON public.photo_verifications FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Updates only via SECURITY DEFINER RPCs / service_role
CREATE POLICY "Service role manages photo verifications"
  ON public.photo_verifications FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 3. Blocks
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blocks (
  id            BIGSERIAL PRIMARY KEY,
  blocker_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (blocker_id <> blocked_id),
  UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON public.blocks (blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON public.blocks (blocked_id);

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own blocks"
  ON public.blocks FOR ALL
  TO authenticated
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 4. Reports
-- ----------------------------------------------------------------------------
CREATE TYPE public.report_reason AS ENUM (
  'spam',
  'harassment',
  'inappropriate_photos',
  'fake_profile',
  'underage',
  'other'
);

CREATE TYPE public.report_status AS ENUM (
  'open',
  'reviewing',
  'actioned',
  'dismissed'
);

CREATE TABLE IF NOT EXISTS public.reports (
  id            BIGSERIAL PRIMARY KEY,
  reporter_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason        public.report_reason NOT NULL,
  details       TEXT CHECK (char_length(details) <= 2000),
  match_id      BIGINT REFERENCES public.matches(id) ON DELETE SET NULL,
  status        public.report_status NOT NULL DEFAULT 'open',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at   TIMESTAMPTZ,
  CHECK (reporter_id <> reported_id)
);

CREATE INDEX IF NOT EXISTS idx_reports_open
  ON public.reports (status, created_at)
  WHERE status IN ('open', 'reviewing');

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own reports"
  ON public.reports FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "Users read own reports"
  ON public.reports FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

CREATE POLICY "Service role manages reports"
  ON public.reports FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 5. Subscriptions (IAP receipts bind later; structure ready)
-- ----------------------------------------------------------------------------
CREATE TYPE public.subscription_status AS ENUM (
  'active',
  'trialing',
  'canceled',
  'expired',
  'grace_period'
);

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tier              TEXT NOT NULL DEFAULT 'plus'
    CHECK (tier IN ('plus', 'gold')),
  status            public.subscription_status NOT NULL DEFAULT 'active',
  provider          TEXT NOT NULL DEFAULT 'placeholder'
    CHECK (provider IN ('placeholder', 'apple', 'google', 'stripe')),
  product_id        TEXT,                       -- e.g. inrange.plus.monthly
  original_tx_id    TEXT,                       -- store transaction id
  starts_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMPTZ,
  canceled_at       TIMESTAMPTZ,
  raw_receipt       JSONB,                      -- store payload (server-only)
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_active
  ON public.subscriptions (user_id, status);

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own subscriptions"
  ON public.subscriptions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Service role manages subscriptions"
  ON public.subscriptions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 6. Boosts (pay to be seen more)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.boosts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id    TEXT,                           -- e.g. inrange.boost.30m
  provider      TEXT NOT NULL DEFAULT 'placeholder',
  starts_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at       TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_boosts_active
  ON public.boosts (user_id, ends_at);

ALTER TABLE public.boosts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own boosts"
  ON public.boosts FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Service role manages boosts"
  ON public.boosts FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 7. Ad impressions (free tier; analytics)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ad_impressions (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  placement     TEXT NOT NULL DEFAULT 'home_banner',
  ad_unit_id    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ad_impressions_user_time
  ON public.ad_impressions (user_id, created_at DESC);

ALTER TABLE public.ad_impressions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own ad impressions"
  ON public.ad_impressions FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 8. Device push tokens (FCM / APNs)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.device_push_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token         TEXT NOT NULL,
  platform      TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  app_version   TEXT,
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user
  ON public.device_push_tokens (user_id);

ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own push tokens"
  ON public.device_push_tokens FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 9. Notification outbox (Edge Function / webhook drains this)
-- ----------------------------------------------------------------------------
CREATE TYPE public.notification_kind AS ENUM (
  'new_encounter',
  'new_match',
  'new_message',
  'expiring_encounter',
  'photo_verified',
  'photo_rejected'
);

CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind          public.notification_kind NOT NULL,
  title         TEXT NOT NULL,
  body          TEXT NOT NULL,
  payload       JSONB NOT NULL DEFAULT '{}'::jsonb,
  status        TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'failed', 'skipped')),
  attempts      INT NOT NULL DEFAULT 0,
  last_error    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
  ON public.notification_outbox (status, created_at)
  WHERE status = 'pending';

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

-- Clients never read outbox; service_role + edge only
CREATE POLICY "Service role manages notification outbox"
  ON public.notification_outbox FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- 10. Helpers: is_blocked either direction
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_blocked_pair(a UUID, b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocks
    WHERE (blocker_id = a AND blocked_id = b)
       OR (blocker_id = b AND blocked_id = a)
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_pair TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 11. Helper: active boost?
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_active_boost(p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.boosts
    WHERE user_id = p_user AND ends_at > NOW()
  );
$$;

GRANT EXECUTE ON FUNCTION public.has_active_boost TO authenticated;

-- ----------------------------------------------------------------------------
-- 12. Helper: is subscriber (tier features)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_subscriber(p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT is_subscriber FROM public.profiles WHERE id = p_user),
    FALSE
  ) OR EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.user_id = p_user
      AND s.status IN ('active', 'trialing', 'grace_period')
      AND (s.expires_at IS NULL OR s.expires_at > NOW())
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_subscriber TO authenticated;

COMMENT ON TABLE public.blocks IS 'User-initiated blocks; mutual exclusion from feeds/chat.';
COMMENT ON TABLE public.reports IS 'Safety reports for moderation queue.';
COMMENT ON TABLE public.subscriptions IS 'IAP/subscription state; pricing TBD — structure ready.';
COMMENT ON TABLE public.boosts IS 'Time-boxed visibility boosts.';
COMMENT ON TABLE public.device_push_tokens IS 'FCM/APNs device tokens for push.';
COMMENT ON TABLE public.notification_outbox IS 'Push jobs drained by send-push Edge Function.';
COMMENT ON TABLE public.photo_verifications IS 'Mandatory photo verification state machine (AI stub + manual).';
