// The world map sketch tool: serves the editor and saves the map into docs/story/.
//   pnpm story:map            → http://127.0.0.1:3210
// Saving writes docs/story/world-map.json (the drawing), docs/story/world-map.png (the picture)
// and rewrites the block between the world-map markers in docs/story/03-world.md.
import { createServer } from "node:http";
import { readFile, writeFile, rename } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../../..");
const STORY = join(ROOT, "docs/story");
const MAP_JSON = join(STORY, "world-map.json");
const MAP_PNG = join(STORY, "world-map.png");
const WORLD_DOC = join(STORY, "03-world.md");
const START = "<!-- world-map:start -->";
const END = "<!-- world-map:end -->";
const PORT = Number(process.env.PORT || process.argv.find(a => a.startsWith("--port="))?.slice(7) || 3210);

// Writes through a temp file so a crash never leaves half a map behind.
async function writeAtomic(path, data) {
	await writeFile(path + ".tmp", data);
	await rename(path + ".tmp", path);
}

// One grid row per line keeps the JSON readable and its git diffs small.
function formatMap(map) {
	const grids = ["terrain", "elevation", "regionCells"];
	const head = Object.fromEntries(Object.entries(map).filter(([k]) => !grids.includes(k)));
	let text = JSON.stringify(head, null, "\t").replace(/\n}$/, "");
	for (const g of grids) text += `,\n\t"${g}": [\n` + (map[g] || []).map(r => `\t\t${JSON.stringify(r)}`).join(",\n") + "\n\t]";
	return text + "\n}\n";
}

async function readBody(req) {
	const chunks = [];
	for await (const c of req) chunks.push(c);
	return Buffer.concat(chunks).toString("utf8");
}

function send(res, status, body, type = "application/json") {
	res.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store" });
	res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

const server = createServer(async (req, res) => {
	try {
		const url = new URL(req.url, "http://localhost");
		if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
			return send(res, 200, await readFile(join(HERE, "index.html")), "text/html; charset=utf-8");
		}
		if (req.method === "GET" && url.pathname === "/api/map") {
			try { return send(res, 200, await readFile(MAP_JSON, "utf8")); }
			catch { return send(res, 404, { error: "no map yet" }); }
		}
		if (req.method === "POST" && url.pathname === "/api/save") {
			const { map, png, section } = JSON.parse(await readBody(req));
			if (map?.format !== "slime-isa-world-map") return send(res, 400, { error: "not a world map" });
			const wrote = ["world-map.json"];
			await writeAtomic(MAP_JSON, formatMap(map));
			if (typeof png === "string" && png.startsWith("data:image/png;base64,")) {
				await writeAtomic(MAP_PNG, Buffer.from(png.slice(22), "base64"));
				wrote.push("world-map.png");
			}
			let docUpdated = false;
			if (typeof section === "string") {
				const doc = await readFile(WORLD_DOC, "utf8");
				const a = doc.indexOf(START), b = doc.indexOf(END);
				if (a >= 0 && b > a) {
					const eol = doc.includes("\r\n") ? "\r\n" : "\n";
					const next = doc.slice(0, a + START.length) + eol + section.trim().replace(/\n/g, eol) + eol + doc.slice(b);
					if (next !== doc) { await writeAtomic(WORLD_DOC, next); wrote.push("03-world.md"); }
					docUpdated = true;
				}
			}
			console.log(`saved ${wrote.join(", ")}`);
			return send(res, 200, { ok: true, wrote, docUpdated });
		}
		send(res, 404, { error: "not found" });
	} catch (err) {
		console.error(err);
		send(res, 500, { error: String(err.message || err) });
	}
});

server.listen(PORT, "127.0.0.1", () => {
	console.log(`World map sketch: http://127.0.0.1:${PORT}`);
	console.log(`Saves to ${MAP_JSON}, world-map.png and the map block in 03-world.md`);
});
