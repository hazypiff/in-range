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




/**
 * Drains public.storage_deletion_queue.
 *
 * Postgres cannot delete storage objects — Supabase blocks DELETE on
 * storage.objects ("Direct deletion from storage tables is not allowed. Use
 * the Storage API instead."). So scrub_account_pii() enqueues the objects of a
 * deleted account and this worker removes them through the Storage API.
 * Until it runs, photos of deleted accounts are still in the buckets, so this
 * is the step that actually completes an erasure request.
 *
 * Rows are retained with deleted_at stamped, as the audit trail that the
 * erasure happened. Failures record last_error and stay pending for retry.
 */
const STORAGE_DRAIN_BATCH = 200;

async function drainStorageDeletionQueue(
  supabase: ReturnType<typeof createClient>,
): Promise<{ deleted: number; failed: number; pending: number }> {
  const { data: rows, error } = await supabase
    .from("storage_deletion_queue")
    .select("id, bucket_id, object_name")
    .is("deleted_at", null)
    .order("requested_at", { ascending: true })
    .limit(STORAGE_DRAIN_BATCH);

  if (error) {
    console.error("storage_deletion_queue select", error);
    return { deleted: 0, failed: 0, pending: -1 };
  }
  if (!rows || rows.length === 0) return { deleted: 0, failed: 0, pending: 0 };

  // One remove() call per bucket rather than per object.
  const byBucket = new Map<string, { id: number; name: string }[]>();
  for (const r of rows as { id: number; bucket_id: string; object_name: string }[]) {
    const list = byBucket.get(r.bucket_id) ?? [];
    list.push({ id: r.id, name: r.object_name });
    byBucket.set(r.bucket_id, list);
  }

  let deleted = 0;
  let failed = 0;

  for (const [bucket, items] of byBucket) {
    const { error: rmError } = await supabase.storage
      .from(bucket)
      .remove(items.map((i) => i.name));

    if (rmError) {
      console.error(`storage remove failed for ${bucket}`, rmError);
      failed += items.length;
      await supabase
        .from("storage_deletion_queue")
        .update({ last_error: String(rmError.message ?? rmError).slice(0, 500) })
        .in("id", items.map((i) => i.id));
      continue;
    }

    // remove() is idempotent: an object already gone is not an error, which is
    // what we want — the queue must be able to converge after a partial run.
    const { error: markError } = await supabase
      .from("storage_deletion_queue")
      .update({ deleted_at: new Date().toISOString(), last_error: null })
      .in("id", items.map((i) => i.id));

    if (markError) {
      // Objects are gone but the stamp failed; the retry is harmless.
      console.error("storage_deletion_queue mark", markError);
      failed += items.length;
      continue;
    }
    deleted += items.length;
  }

  const { count } = await supabase
    .from("storage_deletion_queue")
    .select("id", { count: "exact", head: true })
    .is("deleted_at", null);

  return { deleted, failed, pending: count ?? 0 };
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

    // Complete pending erasure requests: run_maintenance() enqueued the
    // storage objects, only the Storage API can actually remove them.
    const storage = await drainStorageDeletionQueue(supabase);

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
      p_output: {
        maintenance: data,
        pending_notifications: count ?? 0,
        storage_deletions: storage,
      },
    });
    await completeRun(supabase, runId, "succeeded", {
      pending_notifications: count ?? 0,
      storage_deletions: storage,
    });

    return new Response(
      JSON.stringify({
        ok: true,
        maintenance: data,
        pending_notifications: count ?? 0,
        storage_deletions: storage,
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
