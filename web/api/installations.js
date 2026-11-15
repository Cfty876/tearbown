import Redis from "ioredis";
import { redisConnectionUrl, upstashCommands } from "../lib/redis-rest.js";
import { installationHandler } from "../lib/installations.js";

const url = redisConnectionUrl();
const db = upstashCommands(url) || (url ? new Redis(url, {
  lazyConnect: true, connectTimeout: 4000, commandTimeout: 4000, maxRetriesPerRequest: 1,
}) : undefined);
export default installationHandler(db, process.env.BREAKPOINT_INSTALLATIONS_ADMIN, process.env.VERCEL_ENV || "development");
