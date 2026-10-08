import type { Env } from "./env";
import { corsHeaders, errorResponse, json } from "./http";
import { handleTiles } from "./tiles";

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
    try {
      const url = new URL(req.url);
      if (url.pathname === "/health") return json({ ok: true });

      const tiles = await handleTiles(req, env, ctx);
      if (tiles) return tiles;

      return json({ error: "not_found" }, { status: 404 });
    } catch (err) {
      return errorResponse(err);
    }
  },
} satisfies ExportedHandler<Env>;
