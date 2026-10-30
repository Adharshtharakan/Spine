import type { Env } from "./env";
import { json } from "./http";

/**
 *   GET /j/<code>                                 invite landing page
 *   GET /.well-known/assetlinks.json              Android App Links
 *   GET /.well-known/apple-app-site-association   iOS universal links
 *
 * An invite link opens the app straight onto the join screen when it is
 * installed (verified app links); otherwise this small page offers the app
 * and shows the code to type in.
 */
export async function handleInvite(req: Request, env: Env): Promise<Response | null> {
  if (req.method !== "GET") return null;
  const url = new URL(req.url);
  if (url.pathname === "/.well-known/assetlinks.json") {
    const fingerprints = (env.ANDROID_CERT_SHA256 ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    if (!env.ANDROID_PACKAGE_NAME || fingerprints.length === 0) return json([]);
    return json([
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: { namespace: "android_app", package_name: env.ANDROID_PACKAGE_NAME, sha256_cert_fingerprints: fingerprints },
      },
    ]);
  }
  if (url.pathname === "/.well-known/apple-app-site-association") {
    return json({ applinks: { details: env.APPLE_APP_ID ? [{ appIDs: [env.APPLE_APP_ID], components: [{ "/": "/j/*" }] }] : [] } });
  }
  const m = /^\/j\/([A-Za-z0-9]{6,12})$/.exec(url.pathname);
  if (!m) return null;
  return new Response(invitePage(m[1].toUpperCase(), env), {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300" },
  });
}

export function invitePage(code: string, env: Env): string {
  const store = [
    env.PLAY_STORE_URL ? `<a class="btn ghost" href="${env.PLAY_STORE_URL}">Get it on Google Play</a>` : "",
    env.APP_STORE_URL ? `<a class="btn ghost" href="${env.APP_STORE_URL}">Download on the App Store</a>` : "",
  ].join("");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Join a convoy on DriveSync</title>
<meta property="og:title" content="Join my convoy on DriveSync">
<meta property="og:description" content="Invite code ${code}. One map, one plan and one channel for every car in the group.">
<style>
:root{--bg:#f4f4f6;--card:#fff;--ink:#111114;--sub:#6c6d73;--accent:#2f6bff;--soft:#e5edff}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#17171a;--ink:#f4f4f6;--sub:#a0a1a8;--accent:#5c8dff;--soft:#1b2747}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,Roboto,sans-serif;display:grid;place-items:center;min-height:100vh;padding:16px}
.card{background:var(--card);border-radius:28px;padding:32px 24px;max-width:420px;width:100%;text-align:center}
h1{font-size:28px;margin:16px 0 8px}p{color:var(--sub);margin:0 0 24px}
.code{font-size:34px;font-weight:700;letter-spacing:6px;color:var(--accent);background:var(--soft);border-radius:20px;padding:14px;margin-bottom:24px}
.btn{display:block;padding:15px;border-radius:999px;background:var(--accent);color:#fff;text-decoration:none;font-weight:600;margin-top:10px}
.ghost{background:var(--soft);color:var(--accent)}
.logo{width:72px;height:72px;border-radius:22px;background:linear-gradient(135deg,#5b8cff,#2f6bff 45%,#1c47c9);margin:0 auto;color:#fff;font:700 40px/72px system-ui}
</style></head><body><main class="card">
<div class="logo">D</div>
<h1>Join the convoy</h1>
<p>You've been invited to a trip on DriveSync. Open the app to join, or enter this code in "Join".</p>
<div class="code">${code}</div>
<a class="btn" href="drivesync://join/${code}">Open in DriveSync</a>
${store}
</main></body></html>`;
}
