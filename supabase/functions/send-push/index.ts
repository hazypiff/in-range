/**
 * Edge Function: send-push
 *
 * Drains public.notification_outbox and delivers via Firebase Cloud Messaging
 * HTTP v1 (legacy server-key API was shut down by Google in 2024).
 *
 * Secrets (set via `supabase secrets set`):
 *   FCM_PROJECT_ID           — Firebase project id (required for HTTP v1)
 *   FCM_SERVICE_ACCOUNT_JSON — full service account JSON (required for HTTP v1)
 *   FCM_SERVER_KEY           — legacy; kept only for dry-run detection fallback
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
    throw new Error(`oauth_${tokenRes.status}: ${await tokenRes.text()}`);
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
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
    const saJsonRaw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";
    const legacyKey = Deno.env.get("FCM_SERVER_KEY") ?? "";

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
      } catch {
        return json(
          { ok: false, error: "FCM_SERVICE_ACCOUNT_JSON is not valid JSON" },
          500,
        );
      }
    }

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

      // Mint one access token for the whole batch (valid 1h; we use it seconds).
      let accessToken: string;
      try {
        accessToken = await mintAccessToken(sa!);
      } catch (e) {
        allOk = false;
        lastErr = `oauth_mint: ${String(e)}`;
        await supabase
          .from("notification_outbox")
          .update({
            status: "failed",
            last_error: lastErr,
            attempts: row.attempts + 1,
          })
          .eq("id", row.id);
        results.push({ id: row.id, status: "failed", error: lastErr });
        continue;
      }

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
