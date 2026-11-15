import Redis from "ioredis";
import { createRooms } from "../lib/rooms.js";
import { redisConnectionUrl, upstashCommands } from "../lib/redis-rest.js";

const url = redisConnectionUrl();
const redis = url ? new Redis(url, {
  lazyConnect: true, connectTimeout: 5000, commandTimeout: 5000, maxRetriesPerRequest: 1,
  retryStrategy: attempt => Math.min(attempt * 150, 2000),
}) : undefined;

export default createRooms({ redis, commands: upstashCommands(url),
  namespace: "breakpoint:rooms:" + (process.env.VERCEL_ENV || "development") + ":v1",
  onError: error => console.error("[breakpoint rooms]", error.name,
    error.message.startsWith("Redis ") ? error.message : ""),
}).server;
