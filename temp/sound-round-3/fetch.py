"""Download Magnific creations listed in ids.txt (name id1 id2 ...) using a saved creations_get dump."""
import re, sys, urllib.request, pathlib
dump = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
urls = {}
for block in dump.split("  - identifier: ")[1:]:
    ident = block.split("\n", 1)[0].strip()
    m = re.search(r'\n    url: "([^"]+)"', block)
    status = re.search(r'\n    status: (\w+)', block)
    if m: urls[ident] = (m.group(1), status.group(1) if status else "?")
for line in pathlib.Path("ids.txt").read_text().splitlines():
    if not line.strip(): continue
    name, *ids = line.split()
    for n, ident in enumerate(ids, 1):
        out = pathlib.Path("raw") / f"{name}-{n}.mp3"
        if out.exists(): continue
        if ident not in urls: print("no url", name, ident); continue
        url, status = urls[ident]
        if status != "completed": print("not done", name, ident, status); continue
        out.write_bytes(urllib.request.urlopen(url, timeout=60).read())
        print("got", out)
