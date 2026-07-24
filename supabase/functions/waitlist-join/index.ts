/**
 * Edge Function: waitlist-join
 *
 * Public, unauthenticated early-access signup for the inrange.life landing
 * page. Same architecture as ncii-intake: the edge adds the per-IP rate limit
 * an RPC can't (PostgREST never sees the client IP), hashes the IP (never
 * stored raw), then calls join_waitlist() as service-role. join_waitlist() is
 * never granted to anon (migration 0054), so this path is the only way in.
 *
 * verify_jwt=false: visitors have no token. Secrets: SUPABASE_URL,
 * SUPABASE_SERVICE_ROLE_KEY (auto).
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, apikey, authorization",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for") ?? "";
  const first = xff.split(",")[0]?.trim();
  return first || req.headers.get("x-real-ip") || "";
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json({ ok: false, error: "service_unavailable" }, 503);
    const supabase = createClient(supabaseUrl, serviceKey);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ ok: false, error: "invalid_body" }, 400);
    }

    const email = String(body.email ?? "").trim();
    const source = body.source == null ? null : String(body.source).slice(0, 40);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 320) {
      return json({ ok: false, error: "invalid_email" }, 400);
    }

    const ip = clientIp(req);
    if (ip) {
      const ipHash = await sha256Hex(ip);
      const { error: rateErr } = await supabase.rpc("check_waitlist_ip_rate", { p_ip_hash: ipHash });
      if (rateErr) {
        const tooMany = String(rateErr.code) === "53400" ||
          /too many/i.test(String(rateErr.message ?? ""));
        return json(
          { ok: false, error: tooMany ? "rate_limited" : "operation_failed" },
          tooMany ? 429 : 500,
        );
      }
    }

    const { error: rpcErr } = await supabase.rpc("join_waitlist", {
      p_email: email,
      p_source: source,
    });
    if (rpcErr) {
      return json({ ok: false, error: "operation_failed" }, 400);
    }

    // "You're #N in line" for the success state. Total list size only — it
    // reveals nothing about any individual address (the insert is idempotent
    // and unreadable to anon either way).
    const { count } = await supabase
      .from("waitlist")
      .select("*", { count: "exact", head: true });

    return json({ ok: true, position: count ?? null });
  } catch (e) {
    console.error("waitlist-join", e);
    return json({ ok: false, error: "operation_failed" }, 500);
  }
});
