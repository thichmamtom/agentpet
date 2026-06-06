import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { verifySession, SESSION_COOKIE } from "../../lib/auth";
import { getDB, ensureSchema } from "../../lib/db";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};

// Like counts for every pet that has any (slug -> count), plus the slugs the
// current user has liked. The nav/cards fetch this once to render real numbers.
export const GET: APIRoute = async ({ cookies }) => {
  const db = getDB();
  const likes: Record<string, number> = {};
  let mine: string[] = [];

  if (db) {
    await ensureSchema(db);
    const counts: any = await db.prepare("SELECT slug, COUNT(*) AS c FROM pet_likes GROUP BY slug").all();
    for (const r of counts?.results ?? []) likes[r.slug] = r.c;

    const token = cookies.get(SESSION_COOKIE)?.value || "";
    const user = token ? await verifySession(token, v("SESSION_SECRET")) : null;
    if (user) {
      const m: any = await db.prepare("SELECT slug FROM pet_likes WHERE user_id=?").bind(user.id).all();
      mine = (m?.results ?? []).map((r: any) => r.slug);
    }
  }

  return new Response(JSON.stringify({ likes, mine }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
