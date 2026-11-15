import Redis from "ioredis";
import { createRooms } from "../lib/rooms.js";

const url = process.env.BREAKPOINT_REDIS_URL || process.env.REDIS_URL || process.env.KV_URL;
const redis = url ? new Redis(url, {
  lazyConnect: true, connectTimeout: 5000, maxRetriesPerRequest: 1,
  retryStrategy: attempt => Math.min(attempt * 150, 2000),
}) : undefined;

export default createRooms({ redis,
  namespace: "breakpoint:rooms:" + (process.env.VERCEL_ENV || "development") + ":v1",
}).server;
