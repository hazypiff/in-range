/**
 * Edge Function: photo-review
 *
 * Processes photo_verifications in `ai_review` state.
 * STUB: no real AI model — scores random/heuristic, then either:
 *   - STUB_AUTO_APPROVE=true  → full approve (dev/lab)
 *   - else                    → advance to manual_review for human mods
 *
 * Real AI: replace `stubAiScore()` with Vision API / face-match provider.
 *
 * Secrets:
 *   STUB_AUTO_APPROVE=true|false  (default true in non-prod)
 *   PHOTO_AI_API_KEY              (optional, unused in stub)
 *   SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL
 *
 * Invoke: cron every 2 min, or POST { "verification_id": "..." }
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

async function logRun(supabase: ReturnType<typeof createClient>, runKey: string, metadata: Record<string, unknown>) {
  try {
    const { data, error } = await supabase.rpc("log_ai_run", {
      p_run_key: runKey,
      p_source: "photo-review",
      p_actor_type: "edge_function",
      p_actor_id: "photo-review",
      p_model_name: "stub-photo-review",
      p_model_version: "heuristic-v1",
      p_decision_config_version: "photo-review-v1",
      p_code_version: Deno.env.get("FUNCTION_VERSION") ?? null,
      p_input_schema_version: "photo_verifications.v1",
      p_output_schema_version: "photo_review.v1",
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
    const autoApprove =
      (Deno.env.get("STUB_AUTO_APPROVE") ?? "true").toLowerCase() === "true";

    supabase = createClient(supabaseUrl, serviceKey);
    const runKey = newRunKey("photo-review");

    let onlyId: string | null = null;
    if (req.method === "POST") {
      try {
        const body = await req.json();
        onlyId = body?.verification_id ?? null;
      } catch {
        /* */
      }
    }
    runId = await logRun(supabase, runKey, {
      auto_approve: autoApprove,
      targeted: Boolean(onlyId),
    });

    let query = supabase
      .from("photo_verifications")
      .select("id,user_id,photo_path,state")
      .eq("state", "ai_review")
      .order("submitted_at", { ascending: true })
      .limit(20);

    if (onlyId) {
      query = supabase
        .from("photo_verifications")
        .select("id,user_id,photo_path,state")
        .eq("id", onlyId)
        .limit(1);
    }

    const { data: rows, error } = await query;
    if (error) {
      const err = publicError(error);
      await completeRun(supabase, runId, "failed", { phase: "load_queue" }, err);
      return json({ ok: false, error: err }, 500);
    }

    const results: Array<Record<string, unknown>> = [];
    let failures = 0;

    for (const row of rows ?? []) {
      // Stub AI: pass if path looks like an image; score 0.85–0.99
      const { score, passed, notes } = stubAiScore(row.photo_path as string);

      const { error: aiErr } = await supabase.rpc("complete_ai_photo_review", {
        p_verification_id: row.id,
        p_score: score,
        p_passed: passed,
        p_notes: notes,
      });

      if (aiErr) {
        failures++;
        const err = publicError(aiErr);
        results.push({ id: row.id, error: err });
        await logEvent(supabase, runId, {
          p_event_type: "photo_review",
          p_subject_table: "photo_verifications",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: passed ? "passed" : "failed",
          p_confidence: score,
          p_status: "failed",
          p_output: { passed },
          p_error_public: err,
          p_metadata: { auto_approve: autoApprove, stub: true },
        });
        continue;
      }

      if (autoApprove && passed) {
        const { error: decErr } = await supabase.rpc(
          "stub_auto_approve_photo",
          { p_verification_id: row.id },
        );
        results.push({
          id: row.id,
          score,
          passed,
          auto_approved: !decErr,
          error: decErr ? publicError(decErr) : undefined,
        });
        if (decErr) failures++;
        await logEvent(supabase, runId, {
          p_event_type: "photo_review",
          p_subject_table: "photo_verifications",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: decErr ? "auto_approve_failed" : "auto_approved",
          p_confidence: score,
          p_status: decErr ? "failed" : "succeeded",
          p_output: { passed, auto_approved: !decErr },
          p_error_public: decErr ? publicError(decErr) : null,
          p_metadata: { auto_approve: true, stub: true },
        });
      } else {
        results.push({
          id: row.id,
          score,
          passed,
          auto_approved: false,
          next: passed ? "manual_review" : "ai_failed",
        });
        await logEvent(supabase, runId, {
          p_event_type: "photo_review",
          p_subject_table: "photo_verifications",
          p_subject_id: String(row.id),
          p_user_id: row.user_id,
          p_decision: passed ? "manual_review" : "ai_failed",
          p_confidence: score,
          p_status: passed ? "requires_review" : "succeeded",
          p_output: { passed, auto_approved: false },
          p_metadata: { auto_approve: autoApprove, stub: true },
        });
      }
    }

    await completeRun(
      supabase,
      runId,
      failures > 0 ? "partial" : "succeeded",
      { processed: results.length, failures },
    );

    return json({
      ok: true,
      auto_approve: autoApprove,
      processed: results.length,
      results,
    });
  } catch (e) {
    const err = publicError(e);
    if (supabase) await completeRun(supabase, runId, "failed", {}, err);
    return json({ ok: false, error: err }, 500);
  }
});

function stubAiScore(path: string): {
  score: number;
  passed: boolean;
  notes: string;
} {
  const lower = (path ?? "").toLowerCase();
  const looksImage = /\.(jpe?g|png|webp|heic)$/.test(lower) || lower.length > 0;
  // Deterministic-ish score from path length
  const score = looksImage
    ? Math.min(0.99, 0.82 + (path.length % 17) / 100)
    : 0.2;
  const passed = score >= 0.75;
  return {
    score: Number(score.toFixed(4)),
    passed,
    notes: passed
      ? "stub AI: face/liveness heuristic pass"
      : "stub AI: failed basic path/image heuristic",
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
