import { handleAffiliates } from "./affiliates";
import { handleBilling } from "./billing";
import { handleDiscovery } from "./discovery";
import type { Env } from "./env";
import { corsHeaders, errorResponse, json } from "./http";
import { handleTiles } from "./tiles";

/**
 * Convoy edge: one Cloudflare Worker, no idle servers.
 *
 *   /style.json, /tiles/…, /fonts/…, /sprites/…   self-hosted PMTiles basemap
 *   /discovery/…                                   public trip discovery
 *   /affiliates/…                                  B2B bookings along the route
 *   /billing/…                                     subscription verification
 */
export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
    try {
      const url = new URL(req.url);
      if (url.pathname === "/health") return json({ ok: true });

      for (const handler of [handleTiles, handleDiscovery, handleAffiliates]) {
        const res = await handler(req, env, ctx);
        if (res) return res;
      }
      const billing = await handleBilling(req, env);
      if (billing) return billing;

      return json({ error: "not_found" }, { status: 404 });
    } catch (err) {
      return errorResponse(err);
    }
  },
} satisfies ExportedHandler<Env>;
