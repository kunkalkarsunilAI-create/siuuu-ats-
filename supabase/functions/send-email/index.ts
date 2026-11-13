// Meridian ATS: send an email through Resend on behalf of a signed-in team member.
// Secrets: RESEND_API_KEY (required), RESEND_FROM (optional, e.g. "Meridian ATS <ats@yourdomain.com>").
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const EMAIL_RE = /^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/;
const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function claims(token: string): Record<string, unknown> {
  try {
    const p = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(p + "=".repeat((4 - (p.length % 4)) % 4)));
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return json(401, { error: "Not signed in" });

  // Check the caller is a recruiter or admin. PostgREST validates the token (Clerk or Supabase).
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data: role, error: roleErr } = await sb.rpc("my_role");
  if (roleErr) return json(401, { error: "Session not accepted" });
  if (role !== "admin" && role !== "recruiter") return json(403, { error: "Only recruiters and admins can send email" });

  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return json(503, { error: "Email isn't set up yet: add the RESEND_API_KEY secret in Supabase." });

  let body: { to?: string; subject?: string; text?: string; senderName?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid request" });
  }
  const to = String(body.to ?? "").trim();
  const subject = String(body.subject ?? "").trim().slice(0, 200);
  const text = String(body.text ?? "").slice(0, 20000);
  if (!EMAIL_RE.test(to)) return json(400, { error: "Invalid recipient address" });
  if (!subject || !text.trim()) return json(400, { error: "Subject and message are required" });

  const senderEmail = String(claims(token).email ?? "");
  const from = Deno.env.get("RESEND_FROM") || "Meridian ATS <onboarding@resend.dev>";
  const html = `<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.55;color:#1b1d1f">${esc(text).replace(/\n/g, "<br>")}</div>`;

  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      text,
      html,
      ...(EMAIL_RE.test(senderEmail) ? { reply_to: senderEmail } : {}),
    }),
  });
  const out = await r.json().catch(() => ({}));
  if (!r.ok) return json(502, { error: (out as { message?: string }).message || `Resend error ${r.status}` });
  return json(200, { id: (out as { id?: string }).id });
});
