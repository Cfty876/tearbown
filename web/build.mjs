import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
const output = resolve(root, "dist");
const engine = resolve(root, "game-build");
const allow = /^(?:index(?:\.audio(?:\.position)?\.worklet)?\.(?:html|js|wasm|pck|png)|index\.side\.wasm|voxcore\.wasm)$/;
const files = (await readdir(engine)).filter(name => allow.test(name));
for (const required of ["index.html", "index.js", "index.pck", "index.wasm", "index.side.wasm", "voxcore.wasm"]) {
  if (!files.includes(required) || !(await stat(resolve(engine, required))).size) {
    throw new Error("Сначала выгрузи Godot Web. Отсутствует " + required);
  }
}

function publicUrl(name, scheme) {
  const value = process.env[name]?.trim();
  if (!value) return "";
  const url = new URL(value);
  const local = process.env.BREAKPOINT_LOCAL === "1" && (
    (scheme === "wss:" && ["localhost", "127.0.0.1"].includes(url.hostname) && url.protocol === "ws:") ||
    (scheme === "https:" && ["localhost", "127.0.0.1"].includes(url.hostname) && url.protocol === "http:")
  );
  if ((!local && url.protocol !== scheme) || url.username || url.password || url.hash) {
    throw new Error("Некорректный адрес в " + name);
  }
  return url.href;
}

const manifestFile = resolve(root, "desktop-release.json");
const manifest = await readFile(manifestFile, "utf8")
  .then(content => JSON.parse(content))
  .catch(error => { if (error.code === "ENOENT") return null; throw error; });
const config = {
  relay: publicUrl("BREAKPOINT_RELAY_URL", "wss:")
    || (process.env.BREAKPOINT_USE_VERCEL_ROOMS === "1" && process.env.VERCEL_URL
      ? "wss://" + process.env.VERCEL_URL + "/api/rooms" : ""),
  windows: manifest?.platforms.windows?.url || publicUrl("BREAKPOINT_WINDOWS_URL", "https:"),
  macos: manifest?.platforms.macos?.url || publicUrl("BREAKPOINT_MACOS_URL", "https:"),
  macosNotarized: manifest?.platforms.macos?.notarized === true,
  version: manifest?.version || "",
};
await rm(output, { recursive: true, force: true });
await mkdir(resolve(output, "play"), { recursive: true });
await mkdir(resolve(output, "media"));
await cp(resolve(root, "landing"), output, { recursive: true });
for (const file of files) await cp(resolve(engine, file), resolve(output, "play", file));
for (const file of ["menu_courtyard.png", "map_district.jpg", "map_school.jpg", "map_pocket.jpg"]) {
  await cp(resolve(root, "media", file), resolve(output, "media", file));
}
await writeFile(resolve(output, "release-config.js"), "globalThis.BreakpointConfig = " + JSON.stringify(config) + ";\n");
if (manifest) await cp(manifestFile, resolve(output, "desktop-release.json"));
console.log("BREAKPOINT website built. Browser rooms:", config.relay ? "configured" : "disabled");
