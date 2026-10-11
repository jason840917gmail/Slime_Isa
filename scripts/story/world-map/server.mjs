// The world map sketch tool: serves the editor and saves the world layout.
//   pnpm story:map            → http://127.0.0.1:3210
// Saving writes godot/game/data/world-map.json (the layout the game, the Godot world atlas and the
// region builder read), docs/story/world-map.png (the picture) and rewrites the block between the
// world-map markers in docs/story/03-world.md.
// --map=<file> --png=<file> --doc=<file> point those three somewhere else (a copy, to try the tool
// without touching the real files); --port=<n> or PORT picks the port.
// A save is accepted only from the tool's own page, and only over the version of the file the page
// loaded (a file it never loaded, or one that changed since, is replaced only when the page insists).
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { readFile, writeFile, rename } from "node:fs/promises";
import { dirname, join, relative, resolve, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../../..");
const arg = name => process.argv.find(a => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const MAP_JSON = resolve(arg("map") || join(ROOT, "godot/game/data/world-map.json"));
const MAP_PNG = resolve(arg("png") || join(ROOT, "docs/story/world-map.png"));
const WORLD_DOC = resolve(arg("doc") || join(ROOT, "docs/story/03-world.md"));
const START = "<!-- world-map:start -->";
const END = "<!-- world-map:end -->";
const PORT = Number(process.env.PORT || arg("port") || 3210);

// Writes through a temp file so a crash never leaves half a map behind.
async function writeAtomic(path, data) {
	await writeFile(path + ".tmp", data);
	await rename(path + ".tmp", path);
}

// One grid row per line keeps the JSON readable and its git diffs small. world_map_data.gd
// (to_text) writes the same layout.
function formatMap(map) {
	const grids = ["terrain", "elevation", "regionCells"];
	const head = Object.fromEntries(Object.entries(map).filter(([k]) => !grids.includes(k)));
	let text = JSON.stringify(head, null, "\t").replace(/\n}$/, "");
	for (const g of grids) text += `,\n\t"${g}": [\n` + (map[g] || []).map(r => `\t\t${JSON.stringify(r)}`).join(",\n") + "\n\t]";
	return text + "\n}\n";
}

// The file's version: the page sends back the one it loaded, so a save cannot silently overwrite
// what the Godot world atlas or region builder wrote in the meantime (or a file the page never read).
function versionOf(text) { return createHash("sha1").update(text).digest("hex").slice(0, 16); }

// Saves come only from this server's own page: a JSON request (another site's page cannot send one
// without a CORS preflight, which this server never answers) whose Origin, or else Referer, when the
// browser sends one, is this server.
const ORIGINS = new Set([`http://127.0.0.1:${PORT}`, `http://localhost:${PORT}`]);
function fromOwnPage(req) {
	const type = String(req.headers["content-type"] || "").split(";")[0].trim().toLowerCase();
	if (type !== "application/json") return false;
	if (req.headers.origin) return ORIGINS.has(req.headers.origin);
	if (req.headers.referer) {
		try { return ORIGINS.has(new URL(req.headers.referer).origin); } catch { return false; }
	}
	return true;
}

// A path as the page shows it: from the repo root when it is inside it.
function shown(path) {
	const rel = relative(ROOT, path);
	return rel && !rel.startsWith("..") && !isAbsolute(rel) ? rel.replace(/\\/g, "/") : path;
}

async function readBody(req) {
	const chunks = [];
	for await (const c of req) chunks.push(c);
	return Buffer.concat(chunks).toString("utf8");
}

function send(res, status, body, type = "application/json", headers = {}) {
	res.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store", ...headers });
	res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

const server = createServer(async (req, res) => {
	try {
		const url = new URL(req.url, "http://localhost");
		if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
			return send(res, 200, await readFile(join(HERE, "index.html")), "text/html; charset=utf-8");
		}
		if (req.method === "GET" && url.pathname === "/api/map") {
			// the path is URI-encoded: a header holds only Latin-1
			const where = { "X-Map-Path": encodeURIComponent(shown(MAP_JSON)) };
			let text;
			try { text = await readFile(MAP_JSON, "utf8"); }
			catch (err) {
				if (err.code === "ENOENT") return send(res, 404, { error: "no map on disk yet" }, "application/json", where);
				return send(res, 500, { error: `cannot read it (${err.message})` }, "application/json", where);
			}
			return send(res, 200, text, "application/json", { "X-Map-Version": versionOf(text), ...where });
		}
		if (req.method === "POST" && url.pathname === "/api/save") {
			if (!fromOwnPage(req)) return send(res, 403, { error: "saves are accepted only from this server's own page (a JSON request)" });
			let body;
			try { body = JSON.parse(await readBody(req)); } catch { return send(res, 400, { error: "the request is not JSON" }); }
			const { map, png, section, version, force } = body ?? {};
			if (map?.format !== "slime-isa-world-map") return send(res, 400, { error: "not a world map" });
			let current = null;
			try {
				current = await readFile(MAP_JSON, "utf8");
			} catch (error) {
				// only a missing file is "no file yet"; one that cannot be read must not be written over
				if (error?.code !== "ENOENT") return send(res, 500, { error: `${shown(MAP_JSON)} cannot be read (${error?.code ?? error}): not saved.` });
			}
			// a page that never loaded the file sends no version: it must not replace the file unasked
			if (current !== null && !force && !version) {
				return send(res, 409, { error: `${shown(MAP_JSON)} is on disk, but this drawing did not start from it (the page could not load it, or the drawing began before the file existed).` });
			}
			if (current !== null && !force && versionOf(current) !== version) {
				return send(res, 409, { error: `${shown(MAP_JSON)} changed on disk since this page loaded it (the Godot world atlas or region builder may have written it).` });
			}
			const text = formatMap(map);
			const wrote = [shown(MAP_JSON)];
			await writeAtomic(MAP_JSON, text);
			if (typeof png === "string" && png.startsWith("data:image/png;base64,")) {
				await writeAtomic(MAP_PNG, Buffer.from(png.slice(22), "base64"));
				wrote.push(shown(MAP_PNG));
			}
			let docUpdated = false;
			if (typeof section === "string") {
				const doc = await readFile(WORLD_DOC, "utf8");
				const a = doc.indexOf(START), b = doc.indexOf(END);
				if (a >= 0 && b > a) {
					const eol = doc.includes("\r\n") ? "\r\n" : "\n";
					const next = doc.slice(0, a + START.length) + eol + section.trim().replace(/\n/g, eol) + eol + doc.slice(b);
					if (next !== doc) { await writeAtomic(WORLD_DOC, next); wrote.push(shown(WORLD_DOC)); }
					docUpdated = true;
				}
			}
			console.log(`saved ${wrote.join(", ")}`);
			return send(res, 200, { ok: true, wrote, docUpdated, version: versionOf(text) });
		}
		send(res, 404, { error: "not found" });
	} catch (err) {
		console.error(err);
		send(res, 500, { error: String(err.message || err) });
	}
});

server.listen(PORT, "127.0.0.1", () => {
	console.log(`World map sketch: http://127.0.0.1:${PORT}`);
	console.log(`Saves to ${MAP_JSON}, ${MAP_PNG} and the map block in ${WORLD_DOC}`);
});
