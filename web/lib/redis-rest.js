export class RedisRest {
  constructor(url, token) {
    this.url = url;
    this.token = token;
  }

  async command(name, ...args) {
    const response = await fetch(this.url, {
      method: "POST",
      headers: { Authorization: "Bearer " + this.token, "Content-Type": "application/json" },
      body: JSON.stringify([name, ...args]),
      signal: AbortSignal.timeout(2500),
    });
    const data = await response.json();
    if (data.error) throw new Error(data.error);
    if (!response.ok) throw new Error("Redis HTTP " + response.status);
    return data.result;
  }

  get(key) { return this.command("GET", key); }
  ping() { return this.command("PING"); }
  eval(...args) { return this.command("EVAL", ...args); }
  evalsha(...args) { return this.command("EVALSHA", ...args); }
  xrange(...args) { return this.command("XRANGE", ...args); }
  publish(...args) { return this.command("PUBLISH", ...args); }
}

export function redisConnectionUrl(env = process.env) {
  const direct = env.BREAKPOINT_REDIS_URL || env.REDIS_URL || env.KV_URL;
  if (direct) return direct;
  const rest = env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN;
  if (!rest || !token) return undefined;
  const endpoint = new URL(rest);
  if (endpoint.protocol !== "https:" || !endpoint.hostname.endsWith(".upstash.io")) return undefined;
  const tcp = new URL("rediss://" + endpoint.hostname + ":6379");
  tcp.username = "default";
  tcp.password = token;
  return tcp.href;
}

export function upstashCommands(redisUrl, env = process.env) {
  const explicitUrl = env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL;
  const explicitToken = env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN;
  if (explicitUrl && explicitToken) return new RedisRest(explicitUrl, explicitToken);
  if (!redisUrl) return undefined;
  const endpoint = new URL(redisUrl);
  if (endpoint.protocol !== "rediss:" || !endpoint.hostname.endsWith(".upstash.io") || !endpoint.password) {
    return undefined;
  }
  return new RedisRest("https://" + endpoint.hostname, decodeURIComponent(endpoint.password));
}
