/**
 * Edge Function: photo-review
 *
 * Processes photo_verifications in `ai_review` state.
 * STUB: no real AI model — validates file type, then either:
 *   - STUB_AUTO_APPROVE=true  → full approve (localhost lab only)
 *   - else                    → advance to manual_review for human mods
 *
 * Real AI: replace `stubAiScore()` with Vision API / face-match provider.
 *
 * Secrets:
 *   STUB_AUTO_APPROVE=true|false  (default false; ignored outside localhost)
 *   PHOTO_AI_API_KEY              (optional, unused in stub)
 *   SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL
 *
 * Invoke: cron every 2 min, or POST { "verification_id": "..." }
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
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const authError = requireServiceRole(req, serviceKey);
    if (authError) return authError;
    const host = new URL(supabaseUrl).hostname;
    const isLocal = host === "127.0.0.1" || host === "localhost";
    const autoApprove = isLocal &&
      (Deno.env.get("STUB_AUTO_APPROVE") ?? "false").toLowerCase() === "true";

    supabase = createClient(supabaseUrl, serviceKey!);
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
        .eq("state", "ai_review")
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
      // This is format validation only, not identity, face, or liveness AI.
      const { data: photo, error: downloadError } = await supabase.storage
        .from("profile_photos")
        .download(row.photo_path as string);
      const header = downloadError || !photo
        ? new Uint8Array()
        : new Uint8Array(await photo.slice(0, 16).arrayBuffer());
      const { score, passed, notes } = stubAiScore(
        row.photo_path as string,
        header,
      );

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

function stubAiScore(path: string, header: Uint8Array): {
  score: number;
  passed: boolean;
  notes: string;
} {
  const lower = (path ?? "").toLowerCase();
  const extensionMatches = /\.(jpe?g|png|webp|heic)$/.test(lower);
  const jpeg = header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff;
  const png = header[0] === 0x89 && header[1] === 0x50 &&
    header[2] === 0x4e && header[3] === 0x47;
  const webp = header[0] === 0x52 && header[1] === 0x49 &&
    header[2] === 0x46 && header[3] === 0x46 && header[8] === 0x57 &&
    header[9] === 0x45 && header[10] === 0x42 && header[11] === 0x50;
  const heif = header[4] === 0x66 && header[5] === 0x74 &&
    header[6] === 0x79 && header[7] === 0x70;
  const looksImage = extensionMatches && (jpeg || png || webp || heif);
  const score = looksImage ? 0.8 : 0.1;
  const passed = score >= 0.75;
  return {
    score: Number(score.toFixed(4)),
    passed,
    notes: passed
      ? "format validation passed; manual identity/liveness review required"
      : "file could not be validated as a supported image",
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
