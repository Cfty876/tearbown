import { createServer } from "node:http";
import { open } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { Readable } from "node:stream";
import { makeRoomHandler, memoryStore } from "./api/room.js";

const publicDir = fileURLToPath(new URL("./public", import.meta.url));
const api = makeRoomHandler({ command: memoryStore(), local: true });
const isolation = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
};
const types = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".svg": "image/svg+xml",
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://" + req.headers.host);
    if (url.pathname === "/api/room") {
      const request = new Request(url, {
        method: req.method, headers: req.headers,
        ...(req.method === "POST" ? { body: Readable.toWeb(req), duplex: "half" } : {}),
      });
      const response = await api(request);
      res.writeHead(response.status, { ...isolation, ...Object.fromEntries(response.headers) });
      res.end(Buffer.from(await response.arrayBuffer()));
      return;
    }
    const pathname = decodeURIComponent(url.pathname);
    const file = resolve(publicDir, "." + (pathname === "/" ? "/index.html" : pathname));
    if (!file.startsWith(publicDir + sep)) {
      res.writeHead(403).end();
      return;
    }
    const handle = await open(file);
    const info = await handle.stat();
    if (!info.isFile()) {
      await handle.close();
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, {
      ...isolation,
      "Content-Type": types[extname(file)] ?? "application/octet-stream",
      "Content-Length": info.size,
    });
    if (req.method === "HEAD") { await handle.close(); res.end(); return; }
    handle.createReadStream().pipe(res);
  } catch {
    if (!res.headersSent) res.writeHead(404, isolation);
    res.end("Файл недоступен. Проверь сборку public/index.html.");
  }
});
server.listen(Number(process.env.PORT ?? 8080), "127.0.0.1", () =>
  console.log("Voxel Teardown Web at http://127.0.0.1:" + server.address().port));
