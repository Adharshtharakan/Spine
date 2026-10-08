/** HMAC-SHA256 helpers for signed click links and partner postbacks. */

const enc = new TextEncoder();

async function key(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

function b64url(bytes: ArrayBuffer): string {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sign(secret: string, message: string): Promise<string> {
  return b64url(await crypto.subtle.sign("HMAC", await key(secret), enc.encode(message)));
}

export async function verify(secret: string, message: string, signature: string): Promise<boolean> {
  const expected = await sign(secret, message);
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}
