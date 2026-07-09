/**
 * Edge Function: maintenance
 *
 * Runs public.run_maintenance() then drains push outbox via internal call pattern.
 * Schedule every 15 minutes in Supabase Dashboard → Edge Functions → Cron.
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




Deno.serve(async (_req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const { data, error } = await supabase.rpc("run_maintenance");
    if (error) {
      return new Response(JSON.stringify({ ok: false, error: publicError(error) }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Best-effort outbox drain by invoking send-push logic inline would be
    // circular; recommend a second cron on send-push. We mark count of pending.
    const { count } = await supabase
      .from("notification_outbox")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending");

    return new Response(
      JSON.stringify({
        ok: true,
        maintenance: data,
        pending_notifications: count ?? 0,
        at: new Date().toISOString(),
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: publicError(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
