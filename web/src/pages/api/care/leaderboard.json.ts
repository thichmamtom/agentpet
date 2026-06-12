import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;

// Public top-companions board: highest-XP pets across everyone, with the owner.
export const GET: APIRoute = async () => {
  const db = getDB();
  if (!db) {
    return new Response(JSON.stringify({ pets: [] }), { headers: { "content-type": "application/json" } });
  }
  await ensureSchema(db);

  const rows: any = await db
    .prepare(
      `SELECT c.pet_id, c.name, c.xp, c.tokens, c.meals, c.streak, c.thumb,
              u.login AS login, u.avatar AS avatar
       FROM care_pets c
       LEFT JOIN users u ON u.id = c.user_id
       WHERE c.xp > 0
       ORDER BY c.xp DESC
       LIMIT 50`
    )
    .all();

  const pets = (rows?.results ?? []).map((r: any) => ({
    name: r.name || r.pet_id,
    xp: r.xp,
    tokens: r.tokens,
    meals: r.meals,
    streak: r.streak,
    thumb: r.thumb || null,
    owner: r.login || null,
    ownerAvatar: r.avatar || null,
  }));

  return new Response(JSON.stringify({ pets }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=60" },
  });
};
