import { handleAffiliates } from "./affiliates";
import { handleBilling } from "./billing";
import { handleDiscovery } from "./discovery";
import { handleInvite } from "./invite";
import { handleNotify } from "./notify";
import { handlePlaces } from "./places";
import { handleRouting } from "./routing";
import type { Env } from "./env";
import { corsHeaders, errorResponse, json } from "./http";
import { handleTiles } from "./tiles";
import { handleTolls } from "./tolls";
import { handleWeather } from "./weather";

/**
 * Convoy edge: one Cloudflare Worker, no idle servers.
 *
 *   /style.json, /tiles/…, /fonts/…, /sprites/…   self-hosted PMTiles basemap
 *   /discovery/…                                   public trip discovery
 *   /affiliates/…                                  B2B bookings along the route
 *   /route                                         road geometry for prediction
 *   /billing/…                                     subscription verification
 *   /places/search, /places/reverse                place search for stops
 *   /weather                                       forecast at each stop's ETA
 *   /tolls                                         toll plazas on the route
 *   /notify, /sos/sms                              push to the party, SOS texts
 *   /j/<code>, /.well-known/…                      invite links and app links
 */
export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
    try {
      const url = new URL(req.url);
      if (url.pathname === "/health") return json({ ok: true });

      for (const handler of [handleTiles, handleDiscovery, handleAffiliates, handleRouting, handlePlaces, handleWeather, handleTolls]) {
        const res = await handler(req, env, ctx);
        if (res) return res;
      }
      for (const handler of [handleBilling, handleNotify, handleInvite]) {
        const res = await handler(req, env);
        if (res) return res;
      }

      return json({ error: "not_found" }, { status: 404 });
    } catch (err) {
      return errorResponse(err);
    }
  },
} satisfies ExportedHandler<Env>;
