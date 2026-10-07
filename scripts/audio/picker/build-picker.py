"""Build a Sound Picker round page from its manifest (published as the Slime Isa Sound Picker artifact).

    python scripts/audio/picker/build-picker.py scripts/audio/picker/round-<n>.json <out.html>

Fills scripts/audio/picker/picker.html with the manifest's groups and cues; every take is the MP3
copy prep-takes.py wrote, embedded as a data URI. The page saves the owner's picks to the
artifact's database document `picks/<round>`; stage-round.py --picks applies them.
"""

import base64
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TEMPLATE = Path(__file__).with_name("picker.html")
AUDITION_NOTE = ("To hear the options in the game, start it with ?audition on the web (the Web (dev) export) or "
                 "-- --audition on desktop, then press F8 and F7 to switch every new sound between option sets "
                 "while you walk, swim and play. The playground has grass, forest, leaves, snow, cobble, "
                 "shallow and deep water.")


def main() -> None:
    manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    takes_dir = ROOT / manifest["takes"]
    cues = []
    for cue in manifest["cues"]:
        options = []
        for option in cue["options"]:
            takes = []
            for index in range(len(option["takes"])):
                mp3 = takes_dir / cue["id"] / f"{option['key']}-{index + 1}.mp3"
                takes.append("data:audio/mpeg;base64," + base64.b64encode(mp3.read_bytes()).decode("ascii"))
            options.append({"key": option["key"], "label": option["label"], "note": option.get("note", ""), "takes": takes})
        cues.append({"id": cue["id"], "group": cue["group"], "name": cue["name"], "where": cue["where"],
                     "rhythm": cue.get("rhythm"), "rhythmLabel": cue.get("rhythmLabel"), "loop": False,
                     "inGame": cue["inGame"], "options": options})
    page = TEMPLATE.read_text(encoding="utf-8")
    title = manifest.get("title", "Sound picker, " + manifest["round"].replace("-", " "))
    for marker, value in (("/*ROUND*/\"round-3\"", json.dumps(manifest["round"])),
                          ("/*TITLE*/\"Sound picker\"", json.dumps(title, ensure_ascii=False)),
                          ("/*INTRO*/\"\"", json.dumps(manifest.get("intro", ""), ensure_ascii=False)),
                          ("/*GROUPS*/[]", json.dumps(manifest["groups"], ensure_ascii=False)),
                          ("/*CUES*/[]", json.dumps(cues, ensure_ascii=False)),
                          ("/*AUDITION*/''", json.dumps(AUDITION_NOTE))):
        if marker not in page:
            raise SystemExit(f"template marker missing: {marker}")
        page = page.replace(marker, value)
    out = Path(sys.argv[2])
    out.write_text(page, encoding="utf-8")
    print(f"{out}: {len(cues)} cues, {out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
