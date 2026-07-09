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




Deno.serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const autoApprove =
      (Deno.env.get("STUB_AUTO_APPROVE") ?? "true").toLowerCase() === "true";

    const supabase = createClient(supabaseUrl, serviceKey);

    let onlyId: string | null = null;
    if (req.method === "POST") {
      try {
        const body = await req.json();
        onlyId = body?.verification_id ?? null;
      } catch {
        /* */
      }
    }

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
    if (error) return json({ ok: false, error: publicError(error) }, 500);

    const results: Array<Record<string, unknown>> = [];

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
        results.push({ id: row.id, error: publicError(aiErr) });
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
      } else {
        results.push({
          id: row.id,
          score,
          passed,
          auto_approved: false,
          next: passed ? "manual_review" : "ai_failed",
        });
      }
    }

    return json({
      ok: true,
      auto_approve: autoApprove,
      processed: results.length,
      results,
    });
  } catch (e) {
    return json({ ok: false, error: publicError(e) }, 500);
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
