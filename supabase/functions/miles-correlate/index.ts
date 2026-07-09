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




Deno.serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

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
          return json({ ok: false, error: publicError(pingErr) }, 400);
        }
      }
    }

    const { data, error } = await supabase.rpc("batch_correlate_recent_pings", {
      p_lookback_minutes: lookback,
    });

    if (error) {
      return json({ ok: false, error: publicError(error) }, 500);
    }

    return json({
      ok: true,
      processed_users: data,
      lookback_minutes: lookback,
      at: new Date().toISOString(),
    });
  } catch (e) {
    return json({ ok: false, error: publicError(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
