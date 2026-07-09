/**
 * Edge Function: miles-correlate
 *
 * Batch miles-based encounter correlation. Safe to run on a schedule
 * (e.g. every 5–15 minutes) as a backup to client-side record_location_ping.
 *
 * Also accepts a single-user force correlate body:
 *   POST { "user_id": "...", "lat": 34.0, "lon": -118.2, "range": "miles_10" }
 *
 * Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto)
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";




function publicError(e: unknown): string {
  // Avoid leaking stack traces / internal paths to API clients.
  console.error(e);
  if (e && typeof e === "object" && "message" in e) {
    const m = String((e as { message: unknown }).message);
    // Allow short, non-sensitive messages; reject path-like strings
    if (m.length < 120 && !m.includes("/") && m.indexOf(String.fromCharCode(92)) < 0) {
      return m;
    }
  }
  return "internal_error";
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
      p_input_schema_version: "location_pings.v1",
      p_output_schema_version: "correlation_batch.v1",
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




Deno.serve(async (req) => {
  let supabase: ReturnType<typeof createClient> | null = null;
  let runId: string | null = null;
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    supabase = createClient(supabaseUrl, serviceKey);

    let lookback = 30;
    let single: {
      user_id?: string;
      lat?: number;
      lon?: number;
      range?: string;
      neighborhood?: string;
    } | null = null;

    if (req.method === "POST") {
      try {
        const body = await req.json();
        if (body?.lookback_minutes) lookback = Number(body.lookback_minutes) || 30;
        if (body?.user_id && body?.lat != null && body?.lon != null) {
          single = body;
        }
      } catch {
        /* empty */
      }
    }
    runId = await logRun(supabase, "miles-correlate", {
      lookback_minutes: lookback,
      single_user: Boolean(single?.user_id),
    });

    if (single?.user_id) {
      // Service-role insert of a synthetic ping then batch correlate
      const range = single.range ?? "miles_10";
      const hood = single.neighborhood ?? "Nearby";

      // Use RPC batch; for single user we still run full batch (idempotent)
      const { error: insertErr } = await supabase.rpc("record_location_ping", {
        p_lat: single.lat,
        p_lon: single.lon,
        p_range: range,
        p_neighborhood: hood,
      });

      // record_location_ping needs auth.uid() — so use direct table + batch instead
      if (insertErr) {
        const { error: pingErr } = await supabase.from("location_pings").insert({
          user_id: single.user_id,
          geo: `SRID=4326;POINT(${single.lon} ${single.lat})`,
          range_type: range,
          neighborhood: hood,
        });
        if (pingErr) {
          const err = publicError(pingErr);
          await logEvent(supabase, runId, {
            p_event_type: "location_ping_insert",
            p_user_id: single.user_id,
            p_decision: "insert_failed",
            p_status: "failed",
            p_error_public: err,
            p_metadata: { range, has_neighborhood: Boolean(hood) },
          });
          await completeRun(supabase, runId, "failed", { phase: "single_ping_insert" }, err);
          return json({ ok: false, error: err }, 400);
        }
      }
    }

    const { data, error } = await supabase.rpc("batch_correlate_recent_pings", {
      p_lookback_minutes: lookback,
    });

    if (error) {
      const err = publicError(error);
      await logEvent(supabase, runId, {
        p_event_type: "miles_correlation",
        p_user_id: single?.user_id ?? null,
        p_decision: "batch_failed",
        p_status: "failed",
        p_error_public: err,
        p_metadata: { lookback_minutes: lookback },
      });
      await completeRun(supabase, runId, "failed", { phase: "batch" }, err);
      return json({ ok: false, error: err }, 500);
    }

    await logEvent(supabase, runId, {
      p_event_type: "miles_correlation",
      p_user_id: single?.user_id ?? null,
      p_decision: "batch_correlate_recent_pings",
      p_status: "succeeded",
      p_output: { processed_users: data },
      p_metadata: { lookback_minutes: lookback, single_user: Boolean(single?.user_id) },
    });
    await completeRun(supabase, runId, "succeeded", {
      processed_users: data,
      lookback_minutes: lookback,
    });

    return json({
      ok: true,
      processed_users: data,
      lookback_minutes: lookback,
      at: new Date().toISOString(),
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
