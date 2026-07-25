/**
 * Edge Function: proximity-wake
 *
 * Drains public.proximity_wake_requests and sends APNs silent pushes to
 * likely co-located devices so they run a BLE burst (Tier 4 of
 * docs/SUBTLE_TRACKING_ARCHITECTURE.md). Co-location is inferred from
 * recent sightings and public.venue_anchors (coarse geohash + hashed
 * BSSID) — never from continuous raw GPS. Pushes carry no user data,
 * only a wake nonce. Fail-closed: any doubt means skipped, not sent.
 *
 * Secrets (set via `supabase secrets set`):
 *   APNS_KEY_ID       — 10-char key id of the APNs Auth Key
 *   APNS_TEAM_ID      — 10-char Apple Developer team id
 *   APNS_AUTH_KEY_P8  — full .p8 private key PEM (ES256)
 *   APNS_BUNDLE_ID    — app bundle id, used as apns-topic
 *   APNS_USE_SANDBOX  — optional; "true" targets api.sandbox.push.apple.com
 *   SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase
 *   SUPABASE_URL            — auto-injected
 *
 * Invoke:
 *   - Cron: every 5 min
 *   - Manual: POST /functions/v1/proximity-wake  { "limit": 50 }
 *
 * When any APNS_* secret is missing/mock, rows are marked as skipped
 * with last_error=dry_run and nothing is sent.
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
      p_input_schema_version: "proximity_wake_requests.v1",
      p_output_schema_version: "apns_wake_delivery.v1",
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




// How fresh a venue anchor or sighting must be to count as co-location.
const COLOCATION_WINDOW_MIN = 30;
// Minimum minutes between wake pushes to the same user.
const RATE_LIMIT_MIN = 15;
// Max peers woken per request — bounds fan-out on a hot venue.
const MAX_PEERS = 10;

// APNs provider token (RFC 7519, ES256 over the .p8 Auth Key).
// Minimal implementation — no external deps.
async function mintApnsJwt(
  keyId: string,
  teamId: string,
  p8: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", typ: "JWT", kid: keyId };
  const payload = { iss: teamId, iat: now };
  const enc = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const unsigned = `${enc(header)}.${enc(payload)}`;

  const pem = p8.replace(/\\n/g, "\n");
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
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  // WebCrypto ECDSA returns raw r||s (IEEE P1363), which is exactly what
  // a JWS ES256 signature needs — no DER transcoding.
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  return `${unsigned}.${sigB64}`;
}

interface WakeRow {
  id: number;
  user_id: string;
  peer_hint: Record<string, unknown>;
  attempts: number;
  recipient_user_id?: string | null;
}

function minutesAgo(min: number): string {
  return new Date(Date.now() - min * 60_000).toISOString();
}

// Users whose recent anchors or BLE sightings overlap the requester's hint.
async function findLikelyPeers(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  hint: { geohash: string | null; hashedBssid: string | null },
): Promise<string[]> {
  const peers = new Set<string>();
  const anchorCutoff = minutesAgo(COLOCATION_WINDOW_MIN);

  // Venue anchors: same hashed BSSID is a strong venue match, same coarse
  // geohash is a weak one. Both are privacy-preserving by construction.
  if (hint.hashedBssid) {
    const { data } = await supabase
      .from("venue_anchors")
      .select("user_id")
      .eq("hashed_bssid", hint.hashedBssid)
      .neq("user_id", userId)
      .gte("updated_at", anchorCutoff)
      .limit(MAX_PEERS);
    for (const r of data ?? []) peers.add(r.user_id as string);
  }
  if (hint.geohash && peers.size < MAX_PEERS) {
    const { data } = await supabase
      .from("venue_anchors")
      .select("user_id")
      .eq("geohash", hint.geohash)
      .neq("user_id", userId)
      .gte("updated_at", anchorCutoff)
      .limit(MAX_PEERS);
    for (const r of data ?? []) peers.add(r.user_id as string);
  }

  // Recent sightings, either direction: the requester observed a peer's
  // token, or a peer observed one of the requester's live tokens.
  const sightingCutoff = minutesAgo(COLOCATION_WINDOW_MIN);
  const { data: seenByMe } = await supabase
    .from("sightings")
    .select("observed_token")
    .eq("observer_user_id", userId)
    .gte("observed_at", sightingCutoff)
    .limit(50);
  const seenTokens = [...new Set((seenByMe ?? []).map((r) => r.observed_token as string))];
  if (seenTokens.length > 0) {
    const { data: claims } = await supabase
      .from("token_claims")
      .select("user_id")
      .in("token", seenTokens)
      .neq("user_id", userId)
      .limit(MAX_PEERS);
    for (const r of claims ?? []) peers.add(r.user_id as string);
  }

  if (peers.size < MAX_PEERS) {
    const { data: myClaims } = await supabase
      .from("token_claims")
      .select("token")
      .eq("user_id", userId)
      .gte("valid_until", sightingCutoff)
      .limit(50);
    const myTokens = [...new Set((myClaims ?? []).map((r) => r.token as string))];
    if (myTokens.length > 0) {
      const { data: seenMe } = await supabase
        .from("sightings")
        .select("observer_user_id")
        .in("observed_token", myTokens)
        .neq("observer_user_id", userId)
        .gte("observed_at", sightingCutoff)
        .limit(MAX_PEERS);
      for (const r of seenMe ?? []) peers.add(r.observer_user_id as string);
    }
  }

  peers.delete(userId);
  return [...peers].slice(0, MAX_PEERS);
}

async function recentlyWoken(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  // Rate limit rows are recorded with recipient_user_id = the woken peer, so
  // this check actually covers the peer side of the wake (the requester side
  // is covered by the row's own user_id).
  const { data } = await supabase
    .from("proximity_wake_requests")
    .select("id")
    .or(`user_id.eq.${userId},recipient_user_id.eq.${userId}`)
    .eq("status", "sent")
    .gte("sent_at", minutesAgo(RATE_LIMIT_MIN))
    .limit(1);
  return (data ?? []).length > 0;
}

Deno.serve(async (req) => {
  let supabase: ReturnType<typeof createClient> | null = null;
  let runId: string | null = null;
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authError = requireServiceRole(req, serviceKey);
    if (authError) return authError;

    const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
    const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
    const p8 = Deno.env.get("APNS_AUTH_KEY_P8") ?? "";
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";
    const apnsHost = Deno.env.get("APNS_USE_SANDBOX") === "true"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";

    const dryRun =
      !keyId ||
      !teamId ||
      !p8 ||
      !bundleId ||
      p8 === "mock" ||
      p8.startsWith("REPLACE");

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
    runId = await logRun(supabase, "proximity-wake", {
      dry_run: dryRun,
      limit,
      apns_configured: !dryRun,
    });

    const { data: rows, error } = await supabase.rpc(
      "claim_proximity_wake_batch",
      { p_limit: limit },
    );

    if (error) {
      const err = publicError(error);
      await completeRun(supabase, runId, "failed", { phase: "load_requests" }, err);
      return json({ ok: false, error: err }, 500);
    }

    const results: Array<Record<string, unknown>> = [];
    let failed = 0;
    let retried = 0;
    let skipped = 0;
    let sent = 0;
    const claimedRows = (rows ?? []) as unknown as WakeRow[];

    // APNs provider tokens are valid for an hour; one batch needs only one.
    let apnsJwt: string | null = null;
    let jwtError: string | null = null;
    if (!dryRun && claimedRows.length > 0) {
      try {
        apnsJwt = await mintApnsJwt(keyId, teamId, p8);
      } catch (e) {
        jwtError = `apns_jwt: ${publicError(e)}`;
      }
    }

    // Finalizes a claimed row. Claimed rows stay 'pending' (the status CHECK
    // is the four-state spec), so the update is guarded on that to stay
    // idempotent against a double-run after the stale-processing window.
    const finalize = async (
      row: WakeRow,
      update: Record<string, unknown>,
    ) => {
      await supabase!
        .from("proximity_wake_requests")
        .update({ processing_at: null, ...update })
        .eq("id", row.id)
        .eq("status", "pending");
    };

    for (const row of claimedRows) {
      const hintRaw = row.peer_hint as Record<string, unknown> | null;
      const hint = {
        geohash: typeof hintRaw?.geohash === "string" ? hintRaw.geohash : null,
        hashedBssid: typeof hintRaw?.hashed_bssid === "string"
          ? hintRaw.hashed_bssid
          : null,
      };

      if (!hint.geohash && !hint.hashedBssid) {
        await finalize(row, { status: "skipped", last_error: "empty_peer_hint" });
        results.push({ id: row.id, status: "skipped", reason: "empty_peer_hint" });
        skipped++;
        continue;
      }

      if (await recentlyWoken(supabase, row.user_id)) {
        await finalize(row, { status: "skipped", last_error: "rate_limited" });
        results.push({ id: row.id, status: "skipped", reason: "rate_limited" });
        skipped++;
        continue;
      }

      const peers = await findLikelyPeers(supabase, row.user_id, hint);
      if (peers.length === 0) {
        await finalize(row, { status: "skipped", last_error: "no_colocated_peer" });
        results.push({ id: row.id, status: "skipped", reason: "no_colocated_peer" });
        skipped++;
        await logEvent(supabase, runId, {
          p_event_type: "proximity_wake",
          p_subject_table: "proximity_wake_requests",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: "no_colocated_peer",
          p_status: "skipped",
          p_metadata: { has_geohash: !!hint.geohash, has_bssid: !!hint.hashedBssid },
        });
        continue;
      }

      if (dryRun) {
        await finalize(row, { status: "skipped", last_error: "dry_run" });
        results.push({ id: row.id, status: "dry_run", peers: peers.length });
        skipped++;
        await logEvent(supabase, runId, {
          p_event_type: "proximity_wake",
          p_subject_table: "proximity_wake_requests",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: "dry_run",
          p_status: "skipped",
          p_metadata: { peer_count: peers.length },
        });
        continue;
      }

      if (!apnsJwt) {
        const lastErr = jwtError ?? "apns_jwt_unavailable";
        const retrying = row.attempts < 5;
        await finalize(row, {
          status: retrying ? "pending" : "failed",
          last_error: lastErr,
        });
        results.push({ id: row.id, status: retrying ? "retrying" : "failed", error: lastErr });
        if (retrying) retried++;
        else failed++;
        continue;
      }

      // Wake the requester plus each likely co-located peer. The row's
      // rate limit covers the requester; peers get their own check so one
      // hot venue cannot push the same phone every batch.
      const recipients = [row.user_id];
      for (const peerId of peers) {
        if (!(await recentlyWoken(supabase, peerId))) recipients.push(peerId);
      }

      const { data: tokens } = await supabase
        .from("device_push_tokens")
        .select("token,user_id")
        .in("user_id", recipients)
        .eq("platform", "ios")
        .eq("provider", "apns");

      if (!tokens || tokens.length === 0) {
        await finalize(row, { status: "skipped", last_error: "no_device_token" });
        results.push({ id: row.id, status: "skipped", reason: "no_token" });
        skipped++;
        continue;
      }

      let sentCount = 0;
      let lastErr: string | null = null;
      const sentTo: string[] = [];

      for (const t of tokens) {
        try {
          const res = await fetch(`${apnsHost}/3/device/${t.token}`, {
            method: "POST",
            headers: {
              authorization: `bearer ${apnsJwt}`,
              "apns-topic": bundleId,
              "apns-push-type": "background",
              "apns-priority": "5",
              "apns-expiration": `${Math.floor(Date.now() / 1000) + 3600}`,
              "Content-Type": "application/json",
            },
            // Silent push: wake hint + nonce only, no user data.
            body: JSON.stringify({
              aps: { "content-available": 1 },
              wake: crypto.randomUUID(),
            }),
          });
          if (res.ok) {
            sentCount++;
            sentTo.push(t.user_id);
          } else {
            lastErr = `apns_${res.status}`;
            await res.body?.cancel();
          }
        } catch (e) {
          lastErr = publicError(e);
        }
      }

      // Record a sent row for each successfully woken peer so the per-peer
      // rate limit works. The requester's own row is finalized below.
      const sentAt = new Date().toISOString();
      for (const peerId of sentTo) {
        if (peerId === row.user_id) continue;
        await supabase
          .from("proximity_wake_requests")
          .insert({
            user_id: row.user_id,
            recipient_user_id: peerId,
            peer_hint: row.peer_hint,
            status: "sent",
            sent_at: sentAt,
          });
      }

      const allOk = sentCount > 0 && !lastErr;
      const retrying = row.attempts < 5;
      await finalize(row, {
        status: allOk ? "sent" : retrying ? "pending" : "failed",
        last_error: lastErr,
        sent_at: allOk ? sentAt : null,
      });

      results.push({
        id: row.id,
        status: allOk ? "sent" : retrying ? "retrying" : "failed",
        peers: peers.length,
        tokens: tokens.length,
        sent_to: sentTo.length,
        error: lastErr,
      });
      if (allOk) sent++;
      else if (retrying) retried++;
      else failed++;
      await logEvent(supabase, runId, {
        p_event_type: "proximity_wake",
        p_subject_table: "proximity_wake_requests",
        p_subject_id: String(row.id),
        p_user_id: row.user_id,
        p_decision: allOk ? "sent" : "failed",
        p_status: allOk ? "succeeded" : "failed",
        p_error_public: lastErr,
        p_metadata: {
          peer_count: peers.length,
          token_count: tokens.length,
          sent_to: sentTo.length,
        },
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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
