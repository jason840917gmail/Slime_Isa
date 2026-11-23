"""Stage a Sound Picker round in the Godot project, or apply its final picks.

    python scripts/audio/stage-round.py scripts/audio/picker/round-<n>.json [--picks picks.json]

Reads the round manifest and the takes prep-takes.py wrote, then:
1. ships each cue's game option (`inGame`, or the owner's pick with --picks): its WAV takes become
   godot/asset/audio/sfx/library/<ship>-<n>.wav (an option with `"shipped": true` is the cue's library
   files as they are: nothing is copied and its player stays);
2. without --picks, copies every option's MP3 takes to godot/asset/audio/sfx/audition/<cue>/ and
   writes audition.json there for the in-game sound audition (game/dev/sound_audition.gd); with
   --picks the audition folder is removed;
3. writes the cue players: game/scenes/audio/footsteps.tscn (the `Footsteps/<X>` nodes) is written
   whole when the round has any; the other nodes are added to, or updated in,
   game/scenes/audio/global.tscn under Effects.
   Each player's volume brings its takes to the kind's loudness (TARGET_DB), so options compare
   evenly and steps sit under one-shots; it is held lower where the takes' peaks would go over
   full scale (PEAK_CEILING_DB, KEPT_MAX_DB).

The picks file is the picker's saved document ({"picks": {cue: option}, "dropped": {cue: {option:
[index]}}}); a cue picked "replace" or "s" (keep silent) ships nothing and loses its player.

Needs `pip install miniaudio numpy`.
"""

import argparse
import json
import re
import shutil
import zlib
from pathlib import Path

import miniaudio
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
LIBRARY = GODOT / "asset" / "audio" / "sfx" / "library"
## Shipped takes are also kept here (as `<category>-<cue>-r<round>-<n>.wav`) for `pnpm audio:bake --library`.
ORIGINALS = ROOT / "asset" / "Originals" / "audio" / "magnific"
AUDITION = GODOT / "asset" / "audio" / "sfx" / "audition"
FOOTSTEPS_SCENE = GODOT / "game" / "scenes" / "audio" / "footsteps.tscn"
GLOBAL_SCENE = GODOT / "game" / "scenes" / "audio" / "global.tscn"
SFX_PLAYER = "res://game/runtime/sfx_player.gd"
FOOTSTEPS_SCRIPT = "res://game/audio/footsteps.gd"

## Loudness each kind is played at: dBFS RMS of a take's loudest 100 ms. Steps (wading too) and
## strokes sit well under the one-shots: "make steps softer than the rest, I don't want to get
## annoyed by the steps" (owner, round 3).
TARGET_DB = {"step": -33.0, "stroke": -29.0, "blip": -30.0, "loop": -26.0, "oneshot": -17.0}
## Player settings per kind: (pitch randomness, min interval ms, max polyphony).
PLAYER = {"step": (0.06, 180.0, 2), "stroke": (0.05, 300.0, 2), "blip": (0.08, 80.0, 2), "loop": (0.0, 0.0, 1), "oneshot": (0.06, 60.0, 4)}
## Cue -> kind where the take kind is not enough.
CUE_KIND = {"player.swim-stroke": "stroke", "ui.talk-blip": "blip", "player.sleep-breath": "loop", "world.bath-soak": "loop",
            # it turns every few seconds for as long as the slime is near: as quiet as a swim stroke
            "enemy.crystal-crawler-turn": "stroke"}
## Minimum interval (ms) where the kind's does not fit: the struggle repeats while a direction is
## held, and a plate on the edge of its radius can flicker; the stairs walk's footsteps
## (elevation.stairsFootstepMs) may be set closer than walking ones.
CUE_INTERVAL = {"player.web-struggle": 700.0, "world.plate-press": 150.0, "world.plate-release": 150.0,
                "footstep.stairs": 60.0}
## Pitch randomness where the kind's does not fit: the game raises the kill's pitch a step with each
## kill of a chain (the `pitch` payload of sfx_player.gd), and a random spread would blur the steps.
## The toss ships one take and plays on every throw, so its spread is a little wider than the kind's.
## The break cues that ship one take (round 12: soft, crystal, bone) get the same wider spread, so
## repeats are not identical.
CUE_PITCH = {"player.throw-kill": 0.0, "player.throw-toss": 0.08,
             "world.break-soft": 0.08, "world.break-crystal": 0.08, "world.break-bone": 0.08,
             # Round 13: the beetle's brace ships one take and plays every few seconds.
             "enemy.dung-brace": 0.08}
## Headroom. The loudness rule (TARGET_DB) asks a positive player volume for click-like takes (a crack,
## a splat: little energy under a tall peak), which pushes their peaks over full scale; the buses
## have no limiter, so that clips at the output. Takes the tool ships are held to PEAK_CEILING_DB
## after the player's volume. Takes kept as they are (an option marked `shipped`) may go up to
## KEPT_MAX_DB, the highest volume a break cue's player had before round 12 (the owner's stone, +4.12 dB).
PEAK_CEILING_DB = -0.3
KEPT_MAX_DB = 4.1
## Cues whose global players loop.
LOOPING = {"player.sleep-breath", "world.bath-soak"}
## Global players a cue drives besides its `node` (the shell menus also close).
EXTRA_NODES = {"ui.shell-menu": ["MenuClose"]}
## Global players that existed before this round: their volume and settings stay as authored.
AUTHORED = {"Coin", "SleepBreath", "Rested", "MenuOpen", "MenuClose"}


def loudness(path: Path) -> float:
    decoded = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=44100)
    samples = np.frombuffer(decoded.samples, dtype=np.float32)
    window = 4410
    if samples.size <= window:
        return 20 * np.log10(max(float(np.sqrt(np.mean(samples ** 2))), 1e-6))
    energy = np.convolve(samples ** 2, np.ones(window) / window, mode="valid")
    return 20 * np.log10(max(float(np.sqrt(np.max(energy))), 1e-6))


def peak_db(paths: list[Path]) -> float:
    """dBFS of the loudest sample of `paths`."""
    top = 0.0
    for path in paths:
        decoded = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32, nchannels=1, sample_rate=44100)
        samples = np.frombuffer(decoded.samples, dtype=np.float32)
        top = max(top, float(np.max(np.abs(samples))) if samples.size else 0.0)
    return 20 * np.log10(max(top, 1e-6))


def kind_of(cue: dict, option: dict) -> str:
    if cue["id"] in CUE_KIND:
        return CUE_KIND[cue["id"]]
    return "step" if option.get("kind") == "step" else "oneshot"


def res(path: Path) -> str:
    return "res://" + path.relative_to(GODOT).as_posix()


def stream_type(path: str) -> str:
    return {".wav": "AudioStreamWAV", ".ogg": "AudioStreamOggVorbis", ".mp3": "AudioStreamMP3"}[Path(path).suffix.lower()]


def kept(option: dict, dropped: dict) -> list[int]:
    drop = set(dropped.get(option["key"], []))
    indices = [i for i in range(len(option["takes"])) if i not in drop]
    return indices or list(range(len(option["takes"])))


def ship(cue: dict, option: dict, takes_dir: Path, dropped: dict, round_tag: str | None = None) -> list[Path]:
    """The files the game plays for `option`. A cue with a `ship` path gets the option's prepared
    takes (as heard on the picker) as `<ship>-<n>.wav` (`<ship>.wav` for one take), replacing the ones there; a cue without one
    plays its existing files, and so does an option marked `"shipped": true` (its takes are the cue's
    library files as they are: the sound before the round, kept in the game while the round is open).
    With `round_tag` (applying picks) each shipped take is also copied to ORIGINALS."""
    indices = kept(option, dropped)
    if "ship" not in cue or option.get("shipped"):
        return [ROOT / option["takes"][i] for i in indices]
    target_dir = LIBRARY / Path(cue["ship"]).parent
    target_dir.mkdir(parents=True, exist_ok=True)
    stem = Path(cue["ship"]).name
    remove_shipped(cue)
    files = []
    for n, i in enumerate(indices, start=1):
        # One take is `<stem>.wav`, several `<stem>-<n>.wav` (as pnpm audio:bake names them).
        target = target_dir / (f"{stem}.wav" if len(indices) == 1 else f"{stem}-{n}.wav")
        shutil.copyfile(takes_dir / cue["id"] / f"{option['key']}-{i + 1}.wav", target)
        files.append(target)
        if round_tag:
            category = Path(cue["ship"]).parent.as_posix()
            shutil.copyfile(target, ORIGINALS / f"{category}-{stem}-{round_tag}-{n}.wav")
    return files


def remove_shipped(cue: dict) -> None:
    """Deletes the cue's takes from the library (`<ship>.wav|ogg`, `<ship>-<n>.wav|ogg`, with imports)."""
    if "ship" not in cue:
        return
    target_dir = LIBRARY / Path(cue["ship"]).parent
    stem = Path(cue["ship"]).name
    for old in target_dir.glob(f"{stem}*.*"):
        if re.fullmatch(rf"{re.escape(stem)}(-\d+)?\.(wav|ogg)", old.name):
            old.unlink()
            Path(str(old) + ".import").unlink(missing_ok=True)


class Scene:
    """Just enough of the .tscn text format to add resources and replace nodes."""

    def __init__(self, text: str):
        self.blocks = re.split(r"\n(?=\[)", text.strip("\n"))

    def text(self) -> str:
        return "\n".join(self.blocks) + "\n"

    def ext_id(self, path: str, kind: str) -> str:
        for block in self.blocks:
            match = re.match(rf'\[ext_resource type="[^"]+" path="{re.escape(path)}" id="([^"]+)"\]', block)
            if match:
                return match.group(1)
        new_id = f"sfx_{zlib.crc32(path.encode()):08x}"
        index = max((i for i, b in enumerate(self.blocks) if b.startswith("[ext_resource")), default=0)
        self.blocks.insert(index + 1, f'[ext_resource type="{kind}" path="{path}" id="{new_id}"]')
        return new_id

    def sub_resource(self, sub_id: str, body: str) -> None:
        self.blocks = [b for b in self.blocks if not b.startswith(f'[sub_resource type="AudioStreamRandomizer" id="{sub_id}"]')]
        index = max((i for i, b in enumerate(self.blocks) if b.startswith("[ext_resource") or b.startswith("[sub_resource")), default=0)
        self.blocks.insert(index + 1, f'[sub_resource type="AudioStreamRandomizer" id="{sub_id}"]\n{body}\n')

    def node(self, name: str, parent: str, body: str) -> None:
        header = f'[node name="{name}" type="AudioStreamPlayer" parent="{parent}"]'
        block = f"{header}\n{body}\n"
        for i, existing in enumerate(self.blocks):
            if existing.startswith(header):
                self.blocks[i] = block
                return
        index = max((i for i, b in enumerate(self.blocks) if b.startswith("[node")), default=len(self.blocks) - 1)
        self.blocks.insert(index + 1, block)

    def prune(self) -> None:
        """Drops audio resources nothing references any more (a re-staged node's old takes)."""
        while True:
            text = self.text()
            unused = []
            for i, block in enumerate(self.blocks):
                match = re.match(r'\[(ext_resource type="AudioStream\w+"|sub_resource type="AudioStreamRandomizer") [^\]]*id="([^"]+)"\]', block)
                if match and text.count(f'Resource("{match.group(2)}")') == 0:
                    unused.append(i)
            if not unused:
                return
            self.blocks = [b for i, b in enumerate(self.blocks) if i not in unused]

    def remove_node(self, name: str, parent: str) -> None:
        header = f'[node name="{name}" type="AudioStreamPlayer" parent="{parent}"]'
        self.blocks = [b for b in self.blocks if not b.startswith(header)]

    def node_body(self, name: str, parent: str) -> str | None:
        header = f'[node name="{name}" type="AudioStreamPlayer" parent="{parent}"]'
        for block in self.blocks:
            if block.startswith(header):
                return block
        return None


def player_body(scene: Scene, script_id: str, files: list[Path], kind: str, volume_db: float, loop: bool, sub_id: str, interval: float | None = None,
                pitch_randomness: float | None = None) -> str:
    paths = [res(f) for f in files]
    ids = [scene.ext_id(p, stream_type(p)) for p in paths]
    if len(ids) == 1:
        stream = f'ExtResource("{ids[0]}")'
    else:
        lines = ["playback_mode = 1", "random_pitch = 1.0", f"streams_count = {len(ids)}"]
        for n, ext in enumerate(ids):
            lines += [f'stream_{n}/stream = ExtResource("{ext}")', f"stream_{n}/weight = 1.0"]
        scene.sub_resource(sub_id, "\n".join(lines))
        stream = f'SubResource("{sub_id}")'
    pitch, kind_interval, polyphony = PLAYER[kind]
    interval = kind_interval if interval is None else interval
    pitch = pitch if pitch_randomness is None else pitch_randomness
    body = [f'script = ExtResource("{script_id}")', "process_mode = 3", f"stream = {stream}", f"volume_db = {volume_db:.2f}",
            f"max_polyphony = {polyphony}", 'bus = &"Effects"']
    if loop:
        body.append("loop = true")
    else:
        body += [f"pitch_randomness = {pitch}", f"min_interval_ms = {interval}"]
    return "\n".join(body)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest")
    parser.add_argument("--picks")
    args = parser.parse_args()
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    takes_dir = ROOT / manifest["takes"]
    picks = json.loads(Path(args.picks).read_text(encoding="utf-8")) if args.picks else None
    round_tag = "r" + manifest["round"].split("-")[-1]
    writes_footsteps = any(c["node"].startswith("Footsteps/") for c in manifest["cues"])

    footsteps = Scene(f'[gd_scene format=3]\n\n[ext_resource type="Script" path="{FOOTSTEPS_SCRIPT}" id="1"]\n'
                      f'[ext_resource type="Script" path="{SFX_PLAYER}" id="2"]\n\n[node name="Footsteps" type="Node"]\nscript = ExtResource("1")\n')
    global_scene = Scene(GLOBAL_SCENE.read_text(encoding="utf-8"))
    global_script = global_scene.ext_id(SFX_PLAYER, "Script")
    audition = {"round": manifest["round"], "cues": {}}
    if picks is None and AUDITION.exists():
        shutil.rmtree(AUDITION)

    for cue in manifest["cues"]:
        choice = cue["inGame"]
        dropped = {}
        if picks is not None:
            choice = picks.get("picks", {}).get(cue["id"], cue["inGame"])
            dropped = picks.get("dropped", {}).get(cue["id"], {})
        option = next((o for o in cue["options"] if o["key"] == choice), None)
        node_path = cue["node"]
        in_footsteps = node_path.startswith("Footsteps/")
        name = node_path.split("/")[-1]
        scene = footsteps if in_footsteps else global_scene
        parent = "." if in_footsteps else "Effects"
        names = [name] + EXTRA_NODES.get(cue["id"], [])
        if option is None or not option["takes"]:
            for each in names:
                if each not in AUTHORED:
                    scene.remove_node(each, parent)
            remove_shipped(cue)
            print(f"{cue['id']}: silent")
            continue
        kind = kind_of(cue, option)
        files = ship(cue, option, takes_dir, dropped, round_tag if picks is not None else None)
        rule = TARGET_DB[kind] - float(np.mean([loudness(f) for f in files]))
        volume = min(rule, KEPT_MAX_DB if option.get("shipped") else PEAK_CEILING_DB - peak_db(files))
        for each in names:
            if each in AUTHORED and scene.node_body(each, parent) is not None:
                continue
            # A `shipped` option's player is the one already there: its files did not change.
            if option.get("shipped") and not dropped.get(option["key"]) and scene.node_body(each, parent) is not None:
                continue
            script_id = "2" if in_footsteps else global_script
            sub_id = "Rnd_" + re.sub(r"[^A-Za-z0-9]", "_", f"{cue['id']}_{each}")
            scene.node(each, parent, player_body(scene, script_id, files, kind, volume, cue["id"] in LOOPING, sub_id, CUE_INTERVAL.get(cue["id"]),
                                                 CUE_PITCH.get(cue["id"])))
        held = "" if volume == rule else f" (the loudness rule asks {rule:+.1f} dB; held for headroom, peak {peak_db(files) + volume:+.1f} dBFS)"
        print(f"{cue['id']}: {choice} x{len(files)} at {volume:+.1f} dB{held}")
        if picks is None and sum(1 for o in cue["options"] if o["takes"]) > 1:
            entry = {"node": node_path, "inGame": cue["inGame"], "options": {}}
            for each_option in cue["options"]:
                if not each_option["takes"]:
                    continue
                folder = AUDITION / cue["id"]
                folder.mkdir(parents=True, exist_ok=True)
                paths = []
                for i in range(len(each_option["takes"])):
                    target = folder / f"{each_option['key']}-{i + 1}.mp3"
                    shutil.copyfile(takes_dir / cue["id"] / f"{each_option['key']}-{i + 1}.mp3", target)
                    paths.append(res(target))
                gain = TARGET_DB[kind_of(cue, each_option)] - float(np.mean([loudness(takes_dir / cue["id"] / f"{each_option['key']}-{i + 1}.mp3") for i in range(len(each_option["takes"]))]))
                entry["options"][each_option["key"]] = {"label": each_option["label"], "takes": paths, "volume_db": round(gain, 2)}
            audition["cues"][cue["id"]] = entry

    global_scene.prune()
    if writes_footsteps:
        FOOTSTEPS_SCENE.write_text(footsteps.text(), encoding="utf-8")
    GLOBAL_SCENE.write_text(global_scene.text(), encoding="utf-8")
    if picks is None:
        (AUDITION / "audition.json").write_text(json.dumps(audition, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    elif AUDITION.exists():
        shutil.rmtree(AUDITION)


if __name__ == "__main__":
    main()
