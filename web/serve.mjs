import { createServer } from "node:http";
import { open } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const dist = fileURLToPath(new URL("./dist", import.meta.url));
const types = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".jpg": "image/jpeg",
};

const server = createServer(async (req, res) => {
  if (!["GET", "HEAD"].includes(req.method)) return res.writeHead(405).end();
  try {
    const url = new URL(req.url, "http://localhost");
    const pathname = decodeURIComponent(url.pathname);
    const file = resolve(dist, "." + pathname + (pathname.endsWith("/") ? "index.html" : ""));
    if (!file.startsWith(dist + sep)) return res.writeHead(404).end();
    const handle = await open(file);
    const info = await handle.stat();
    if (!info.isFile()) {
      await handle.close();
      return res.writeHead(404).end();
    }
    res.writeHead(200, {
      "Content-Type": types[extname(file)] ?? "application/octet-stream",
      "Content-Length": info.size,
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    });
    if (req.method === "HEAD") { await handle.close(); res.end(); return; }
    handle.createReadStream().pipe(res);
  } catch {
    if (!res.headersSent) res.writeHead(404);
    res.end();
  }
});
server.listen(Number(process.env.PORT ?? 8080), "127.0.0.1", () =>
  console.log("BREAKPOINT http://127.0.0.1:" + server.address().port));
