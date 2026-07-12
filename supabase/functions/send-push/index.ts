/**
 * Edge Function: send-push
 *
 * Drains public.notification_outbox and delivers via Firebase Cloud Messaging
 * HTTP v1 (legacy server-key API was shut down by Google in 2024).
 *
 * Secrets (set via `supabase secrets set`):
 *   FCM_PROJECT_ID           — Firebase project id (required for HTTP v1)
 *   FCM_SERVICE_ACCOUNT_JSON — full service account JSON (required for HTTP v1)
 *   SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase
 *   SUPABASE_URL             — auto-injected
 *
 * Invoke:
 *   - Cron: every 1 min
 *   - Database webhook on notification_outbox INSERT
 *   - Manual: POST /functions/v1/send-push  { "limit": 50 }
 *
 * When FCM_PROJECT_ID or FCM_SERVICE_ACCOUNT_JSON is missing/mock, marks rows as
 * skipped with last_error=dry_run.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireServiceRole } from "../_shared/service_auth.ts";




function publicError(e: unknown): string {
  console.error(e);
  return "operation_failed";
}

function newRunKey(source: string): string {
  return `${source}:${Date.now()}:${crypto.randomUUID()}`;
}

async function logRun(
  supabase: ReturnType<typeof createClient>,
  source: string,
  metadata: Record<string, unknown>,
) {
  try {
    const { data, error } = await supabase.rpc("log_ai_run", {
      p_run_key: newRunKey(source),
      p_source: source,
      p_actor_type: "edge_function",
      p_actor_id: source,
      p_code_version: Deno.env.get("FUNCTION_VERSION") ?? null,
      p_input_schema_version: "notification_outbox.v1",
      p_output_schema_version: "push_delivery.v1",
      p_status: "started",
      p_metadata: metadata,
    });
    if (error) console.error("log_ai_run", error);
    return data as string | null;
  } catch (e) {
    console.error("log_ai_run", e);
    return null;
  }
}

async function logEvent(
  supabase: ReturnType<typeof createClient>,
  runId: string | null,
  params: Record<string, unknown>,
) {
  if (!runId) return;
  try {
    const { error } = await supabase.rpc("log_ai_event", {
      p_run_id: runId,
      ...params,
    });
    if (error) console.error("log_ai_event", error);
  } catch (e) {
    console.error("log_ai_event", e);
  }
}

async function completeRun(
  supabase: ReturnType<typeof createClient>,
  runId: string | null,
  status: string,
  metadata: Record<string, unknown>,
  errorPublic: string | null = null,
) {
  if (!runId) return;
  try {
    const { error } = await supabase.rpc("complete_ai_run", {
      p_run_id: runId,
      p_status: status,
      p_error_public: errorPublic,
      p_metadata_patch: metadata,
    });
    if (error) console.error("complete_ai_run", error);
  } catch (e) {
    console.error("complete_ai_run", e);
  }
}




interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

// JWT for Google OAuth2 service-account auth (RFC 7519).
// Minimal implementation — no external deps.
async function mintAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };
  const enc = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const unsigned = `${enc(header)}.${enc(payload)}`;

  const pem = sa.private_key.replace(/\\n/g, "\n");
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const b64 = pem
    .split(pemHeader)[1]
    .split(pemFooter)[0]
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  const jwt = `${unsigned}.${sigB64}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!tokenRes.ok) {
    await tokenRes.body?.cancel();
    throw new Error(`oauth_${tokenRes.status}`);
  }
  const tokenJson = (await tokenRes.json()) as { access_token: string };
  return tokenJson.access_token;
}

interface OutboxRow {
  id: number;
  user_id: string;
  kind: string;
  title: string;
  body: string;
  payload: Record<string, unknown>;
  attempts: number;
}

Deno.serve(async (req) => {
  let supabase: ReturnType<typeof createClient> | null = null;
  let runId: string | null = null;
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authError = requireServiceRole(req, serviceKey);
    if (authError) return authError;
    const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
    const saJsonRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";

    const dryRun =
      !projectId ||
      !saJsonRaw ||
      saJsonRaw === "mock" ||
      saJsonRaw === "YOUR_SERVICE_ACCOUNT_JSON" ||
      saJsonRaw.startsWith("REPLACE");

    let sa: ServiceAccount | null = null;
    if (!dryRun) {
      try {
        sa = JSON.parse(saJsonRaw) as ServiceAccount;
        if (!sa.client_email || !sa.private_key) throw new Error("missing_fields");
      } catch {
        return json({ ok: false, error: "invalid_fcm_credentials" }, 500);
      }
    }

    supabase = createClient(supabaseUrl, serviceKey!);

    let limit = 50;
    if (req.method === "POST") {
      try {
        const body = await req.json();
        if (body?.limit) {
          limit = Math.max(1, Math.min(200, Number(body.limit) || 50));
        }
      } catch {
        /* empty body ok */
      }
    }
    runId = await logRun(supabase, "send-push", {
      dry_run: dryRun,
      limit,
      fcm_configured: !dryRun,
    });

    const { data: rows, error } = await supabase.rpc(
      "claim_notification_batch",
      { p_limit: limit },
    );

    if (error) {
      const err = publicError(error);
      await completeRun(supabase, runId, "failed", { phase: "load_outbox" }, err);
      return json({ ok: false, error: err }, 500);
    }

    const results: Array<Record<string, unknown>> = [];
    let failed = 0;
    let retried = 0;
    let skipped = 0;
    let sent = 0;
    const claimedRows = (rows ?? []) as unknown as OutboxRow[];

    // Google access tokens are valid for an hour; one batch needs only one.
    let accessToken: string | null = null;
    let oauthError: string | null = null;
    if (!dryRun && claimedRows.length > 0) {
      try {
        accessToken = await mintAccessToken(sa!);
      } catch (e) {
        oauthError = `oauth_mint: ${publicError(e)}`;
      }
    }

    for (const row of claimedRows) {
      const { data: recipient } = await supabase
        .from("profiles")
        .select("is_active,is_paused,account_deleted_at")
        .eq("id", row.user_id)
        .maybeSingle();
      if (
        !recipient || recipient.is_active !== true || recipient.is_paused === true ||
        recipient.account_deleted_at != null
      ) {
        await supabase.from("notification_outbox").update({
          status: "skipped",
          last_error: "recipient_unavailable",
          processing_at: null,
          sent_at: new Date().toISOString(),
        }).eq("id", row.id).eq("status", "processing");
        results.push({ id: row.id, status: "skipped", reason: "recipient_unavailable" });
        skipped++;
        continue;
      }

      // If the notification was triggered by another user (match, message),
      // skip delivery when the pair is blocked. Encounter jobs use other_user_id.
      const payload = row.payload as Record<string, unknown> | null;
      const actorId = payload?.sender_id ?? payload?.other_user_id;
      if (typeof actorId === "string") {
        const { data: blockedCheck } = await supabase
          .rpc("is_blocked_pair", { a: actorId, b: row.user_id });
        if (blockedCheck === true) {
          await supabase
            .from("notification_outbox")
            .update({
              status: "skipped",
              last_error: "blocked_pair",
              processing_at: null,
              sent_at: new Date().toISOString(),
            })
            .eq("id", row.id)
            .eq("status", "processing");
          results.push({ id: row.id, status: "skipped", reason: "blocked" });
          skipped++;
          await logEvent(supabase, runId, {
            p_event_type: "push_delivery",
            p_subject_table: "notification_outbox",
            p_subject_id: String(row.id),
            p_user_id: row.user_id,
            p_decision: "skipped_blocked",
            p_status: "skipped",
            p_metadata: { kind: row.kind },
          });
          continue;
        }
      }

      const { data: tokens } = await supabase
        .from("device_push_tokens")
        .select("token,platform")
        .eq("user_id", row.user_id);

      if (!tokens || tokens.length === 0) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "skipped",
            last_error: "no_device_token",
            processing_at: null,
            sent_at: new Date().toISOString(),
          })
          .eq("id", row.id)
          .eq("status", "processing");
        results.push({ id: row.id, status: "skipped", reason: "no_token" });
        skipped++;
        await logEvent(supabase, runId, {
          p_event_type: "push_delivery",
          p_subject_table: "notification_outbox",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: "skipped_no_token",
          p_status: "skipped",
          p_metadata: { kind: row.kind },
        });
        continue;
      }

      if (dryRun) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "skipped",
            last_error: "dry_run_no_fcm_key",
            processing_at: null,
            sent_at: new Date().toISOString(),
          })
          .eq("id", row.id)
          .eq("status", "processing");
        results.push({
          id: row.id,
          status: "dry_run",
          tokens: tokens.length,
        });
        skipped++;
        await logEvent(supabase, runId, {
          p_event_type: "push_delivery",
          p_subject_table: "notification_outbox",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: "dry_run",
          p_status: "skipped",
          p_metadata: { kind: row.kind, token_count: tokens.length },
        });
        continue;
      }

      if (!accessToken) {
        const lastErr = oauthError ?? "oauth_unavailable";
        const retrying = row.attempts < 5;
        await supabase
          .from("notification_outbox")
          .update({
            status: retrying ? "pending" : "failed",
            last_error: lastErr,
            processing_at: null,
          })
          .eq("id", row.id)
          .eq("status", "processing");
        results.push({
          id: row.id,
          status: retrying ? "retrying" : "failed",
          error: lastErr,
        });
        if (retrying) retried++;
        else failed++;
        await logEvent(supabase, runId, {
          p_event_type: "push_delivery",
          p_subject_table: "notification_outbox",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: "oauth_failed",
          p_status: "failed",
          p_error_public: lastErr,
          p_metadata: { kind: row.kind, token_count: tokens.length },
        });
        continue;
      }

      let allOk = true;
      let lastErr: string | null = null;

      const v1Url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

      for (const t of tokens) {
        try {
          const res = await fetch(v1Url, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: t.token,
                android: { priority: "high" },
                apns: { payload: { aps: { sound: "default" } } },
                notification: {
                  title: row.title,
                  body: row.body,
                },
                data: {
                  kind: row.kind,
                  ...flattenPayload(row.payload),
                },
              },
            }),
          });
          if (!res.ok) {
            allOk = false;
            lastErr = `fcm_${res.status}`;
            await res.body?.cancel();
          }
        } catch (e) {
          allOk = false;
          lastErr = publicError(e);
        }
      }

      await supabase
        .from("notification_outbox")
        .update({
          status: allOk ? "sent" : row.attempts < 5 ? "pending" : "failed",
          last_error: lastErr,
          processing_at: null,
          sent_at: allOk ? new Date().toISOString() : null,
        })
        .eq("id", row.id)
        .eq("status", "processing");

      results.push({
        id: row.id,
        status: allOk ? "sent" : row.attempts < 5 ? "retrying" : "failed",
        error: lastErr,
      });
      if (allOk) {
        sent++;
      } else if (row.attempts < 5) {
        retried++;
      } else {
        failed++;
      }
      await logEvent(supabase, runId, {
        p_event_type: "push_delivery",
        p_subject_table: "notification_outbox",
        p_subject_id: String(row.id),
        p_user_id: row.user_id,
        p_decision: allOk ? "sent" : "failed",
        p_status: allOk ? "succeeded" : "failed",
        p_error_public: lastErr,
        p_metadata: { kind: row.kind, token_count: tokens.length, dry_run: false },
      });
    }

    await completeRun(supabase, runId, failed + retried > 0 ? "partial" : "succeeded", {
      processed: results.length,
      sent,
      skipped,
      retried,
      failed,
      dry_run: dryRun,
    });

    return json({
      ok: true,
      dry_run: dryRun,
      processed: results.length,
      results,
    });
  } catch (e) {
    const err = publicError(e);
    if (supabase) await completeRun(supabase, runId, "failed", {}, err);
    return json({ ok: false, error: err }, 500);
  }
});

function flattenPayload(
  payload: Record<string, unknown> | null,
): Record<string, string> {
  const out: Record<string, string> = {};
  if (!payload) return out;
  for (const [k, v] of Object.entries(payload)) {
    out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
