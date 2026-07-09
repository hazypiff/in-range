/**
 * Edge Function: send-push
 *
 * Drains public.notification_outbox and delivers via Firebase Cloud Messaging HTTP v1.
 *
 * Secrets (set via `supabase secrets set`):
 *   FCM_SERVER_KEY          — legacy server key OR leave empty for dry-run
 *   FCM_PROJECT_ID          — Firebase project id (for HTTP v1)
 *   FCM_SERVICE_ACCOUNT_JSON — optional full service account JSON for HTTP v1
 *   SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase
 *   SUPABASE_URL            — auto-injected
 *
 * Invoke:
 *   - Cron: every 1 min
 *   - Database webhook on notification_outbox INSERT
 *   - Manual: POST /functions/v1/send-push  { "limit": 50 }
 *
 * When FCM_SERVER_KEY is missing/mock, marks rows as skipped with last_error=dry_run.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const FCM_LEGACY_URL = "https://fcm.googleapis.com/fcm/send";

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
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const fcmKey = Deno.env.get("FCM_SERVER_KEY") ?? "";
    const dryRun =
      !fcmKey ||
      fcmKey === "mock" ||
      fcmKey === "YOUR_FCM_SERVER_KEY" ||
      fcmKey.startsWith("REPLACE");

    const supabase = createClient(supabaseUrl, serviceKey);

    let limit = 50;
    if (req.method === "POST") {
      try {
        const body = await req.json();
        if (body?.limit) limit = Math.min(200, Number(body.limit) || 50);
      } catch {
        /* empty body ok */
      }
    }

    const { data: rows, error } = await supabase
      .from("notification_outbox")
      .select("id,user_id,kind,title,body,payload,attempts")
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(limit);

    if (error) {
      return json({ ok: false, error: error.message }, 500);
    }

    const results: Array<Record<string, unknown>> = [];

    for (const row of (rows ?? []) as OutboxRow[]) {
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
            attempts: row.attempts + 1,
            sent_at: new Date().toISOString(),
          })
          .eq("id", row.id);
        results.push({ id: row.id, status: "skipped", reason: "no_token" });
        continue;
      }

      if (dryRun) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "skipped",
            last_error: "dry_run_no_fcm_key",
            attempts: row.attempts + 1,
            sent_at: new Date().toISOString(),
          })
          .eq("id", row.id);
        results.push({
          id: row.id,
          status: "dry_run",
          tokens: tokens.length,
          title: row.title,
        });
        continue;
      }

      let allOk = true;
      let lastErr: string | null = null;

      for (const t of tokens) {
        try {
          const res = await fetch(FCM_LEGACY_URL, {
            method: "POST",
            headers: {
              Authorization: `key=${fcmKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              to: t.token,
              priority: "high",
              notification: {
                title: row.title,
                body: row.body,
              },
              data: {
                kind: row.kind,
                ...flattenPayload(row.payload),
              },
            }),
          });
          if (!res.ok) {
            allOk = false;
            lastErr = `fcm_${res.status}: ${await res.text()}`;
          }
        } catch (e) {
          allOk = false;
          lastErr = String(e);
        }
      }

      await supabase
        .from("notification_outbox")
        .update({
          status: allOk ? "sent" : "failed",
          last_error: lastErr,
          attempts: row.attempts + 1,
          sent_at: new Date().toISOString(),
        })
        .eq("id", row.id);

      results.push({
        id: row.id,
        status: allOk ? "sent" : "failed",
        error: lastErr,
      });
    }

    return json({
      ok: true,
      dry_run: dryRun,
      processed: results.length,
      results,
    });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
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
