/** Authorizes cron/webhook-only Edge Functions before any privileged work. */
export function requireServiceRole(
  req: Request,
  serviceRoleKey: string | undefined,
): Response | null {
  if (req.method !== "POST") {
    return jsonError("method_not_allowed", 405, { Allow: "POST" });
  }

  if (!serviceRoleKey) {
    console.error("SUPABASE_SERVICE_ROLE_KEY is not configured");
    return jsonError("service_unavailable", 503);
  }

  const authorization = req.headers.get("authorization") ?? "";
  if (authorization !== `Bearer ${serviceRoleKey}`) {
    return jsonError("unauthorized", 401);
  }

  return null;
}

function jsonError(
  error: string,
  status: number,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify({ ok: false, error }), {
    status,
    headers: { "Content-Type": "application/json", ...extraHeaders },
  });
}
