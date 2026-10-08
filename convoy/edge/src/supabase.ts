import type { Env } from "./env";
import { HttpError } from "./http";

/**
 * Minimal PostgREST client. Calls made "as the user" forward their JWT so
 * Row Level Security and the RPC rules apply exactly as they do in the app;
 * the service role is used only for tables clients may never write
 * (entitlements, affiliate clicks and conversions).
 */
export class Supabase {
  constructor(private env: Env) {}

  private headers(token?: string): HeadersInit {
    const key = token ? this.env.SUPABASE_ANON_KEY : this.env.SUPABASE_SERVICE_ROLE_KEY;
    return {
      apikey: key,
      authorization: `Bearer ${token ?? this.env.SUPABASE_SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    };
  }

  async rpc<T>(fn: string, args: Record<string, unknown>, token?: string): Promise<T> {
    const res = await fetch(`${this.env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: this.headers(token),
      body: JSON.stringify(args),
    });
    return this.parse<T>(res);
  }

  async select<T>(table: string, query: string, token?: string): Promise<T[]> {
    const res = await fetch(`${this.env.SUPABASE_URL}/rest/v1/${table}?${query}`, { headers: this.headers(token) });
    return this.parse<T[]>(res);
  }

  /** Service-role upsert. */
  async upsert(table: string, rows: Record<string, unknown> | Record<string, unknown>[], onConflict?: string) {
    const url = `${this.env.SUPABASE_URL}/rest/v1/${table}${onConflict ? `?on_conflict=${onConflict}` : ""}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { ...this.headers(), prefer: "resolution=merge-duplicates,return=representation" },
      body: JSON.stringify(rows),
    });
    return this.parse<Record<string, unknown>[]>(res);
  }

  private async parse<T>(res: Response): Promise<T> {
    const text = await res.text();
    const body = text ? JSON.parse(text) : null;
    if (!res.ok) {
      // Surface the stable error codes raised by the SQL (vehicle_cap_reached …).
      const message = (body && (body.message as string)) || `supabase_${res.status}`;
      throw new HttpError(res.status >= 500 ? 502 : 400, message);
    }
    return body as T;
  }
}
