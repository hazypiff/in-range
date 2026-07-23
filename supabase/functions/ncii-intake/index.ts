/**
 * Edge Function: ncii-intake
 *
 * Public, unauthenticated front door for NCII / TAKE IT DOWN reports. It exists
 * to add the one control an RPC cannot: a per-IP rate limit (PostgREST can't see
 * the client IP). The IP is hashed here and never stored raw. After the per-IP
 * check it calls submit_ncii_report() as service-role, which applies the
 * per-email and global backstops. submit_ncii_report() is revoked from anon
 * (migration 0050), so this rate-limited path is the only way in.
 *
 * verify_jwt=false: anonymous reporters have no token. Secrets: SUPABASE_URL,
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

    const email = String(body.p_reporter_email ?? "").trim();
    const description = String(body.p_description ?? "").trim();
    if (!email.includes("@")) return json({ ok: false, error: "invalid_email" }, 400);
    if (description.length < 10) return json({ ok: false, error: "description_too_short" }, 400);

    // Per-IP hourly limit. An empty/unknown IP falls through to the email +
    // global backstops rather than blocking a legitimate reporter.
    const ip = clientIp(req);
    if (ip) {
      const ipHash = await sha256Hex(ip);
      const { error: rateErr } = await supabase.rpc("check_ncii_ip_rate", { p_ip_hash: ipHash });
      if (rateErr) {
        // 53400 = our RAISE; surface as 429 so the form shows a clear message.
        const tooMany = String(rateErr.code) === "53400" ||
          /too many/i.test(String(rateErr.message ?? ""));
        return json(
          { ok: false, error: tooMany ? "rate_limited" : "operation_failed" },
          tooMany ? 429 : 500,
        );
      }
    }

    const { error: rpcErr } = await supabase.rpc("submit_ncii_report", {
      p_reporter_email: email,
      p_description: description,
      p_reporter_name: (body.p_reporter_name as string | null) ?? null,
      p_target_hint: (body.p_target_hint as string | null) ?? null,
      p_is_authorized: Boolean(body.p_is_authorized),
    });
    if (rpcErr) {
      const tooMany = String(rpcErr.code) === "53400" ||
        /too many|saturated/i.test(String(rpcErr.message ?? ""));
      // Do not leak internal SQL detail to an anonymous caller.
      return json(
        { ok: false, error: tooMany ? "rate_limited" : "operation_failed" },
        tooMany ? 429 : 400,
      );
    }

    return json({ ok: true });
  } catch (e) {
    console.error("ncii-intake", e);
    return json({ ok: false, error: "operation_failed" }, 500);
  }
});
