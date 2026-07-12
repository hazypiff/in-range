/**
 * Edge Function: maintenance
 *
 * Runs public.run_maintenance() then drains push outbox via internal call pattern.
 * Schedule every 15 minutes in Supabase Dashboard → Edge Functions → Cron.
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

async function logRun(supabase: ReturnType<typeof createClient>, source: string) {
  try {
    const { data, error } = await supabase.rpc("log_ai_run", {
      p_run_key: newRunKey(source),
      p_source: source,
      p_actor_type: "edge_function",
      p_actor_id: source,
      p_code_version: Deno.env.get("FUNCTION_VERSION") ?? null,
      p_input_schema_version: "maintenance.v1",
      p_output_schema_version: "maintenance.v1",
      p_status: "started",
      p_metadata: {},
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
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authError = requireServiceRole(req, serviceKey);
    if (authError) return authError;
    supabase = createClient(supabaseUrl, serviceKey!);
    runId = await logRun(supabase, "maintenance");

    const { data, error } = await supabase.rpc("run_maintenance");
    if (error) {
      const err = publicError(error);
      await logEvent(supabase, runId, {
        p_event_type: "maintenance",
        p_decision: "run_maintenance_failed",
        p_status: "failed",
        p_error_public: err,
      });
      await completeRun(supabase, runId, "failed", { phase: "run_maintenance" }, err);
      return new Response(JSON.stringify({ ok: false, error: err }), {
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

    await logEvent(supabase, runId, {
      p_event_type: "maintenance",
      p_decision: "run_maintenance",
      p_status: "succeeded",
      p_output: { maintenance: data, pending_notifications: count ?? 0 },
    });
    await completeRun(supabase, runId, "succeeded", {
      pending_notifications: count ?? 0,
    });

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
    const err = publicError(e);
    if (supabase) await completeRun(supabase, runId, "failed", {}, err);
    return new Response(JSON.stringify({ ok: false, error: err }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
