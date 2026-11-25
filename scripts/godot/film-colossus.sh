#!/usr/bin/env bash
# Films one of the Crystal Colossus's plate-fight films (godot/tools/film_colossus.gd, in
# world.colossus-lab) and lays it out (mechanism-film-sheet.py), one film at a time: it waits on the
# throw films' lock folder, since two game windows rendering at once stall each other.
#   scripts/godot/film-colossus.sh <name> --film=<film> [film options...] [sheet options...]
# Films: look, poses, walks, glow, burst, clang, pass, dip, bare, wall, core. With
# --tool=film_colossus_arena the same films in the rebuilt Crystal Mine's arena (godot/tools/
# film_colossus_arena.gd, world.crystal-mine-m15-colossus-arena: the lab's world carried into the room),
# into output/dungeon-rework/mine/arena-films/<name>/ (burst, clang, wall and core say PASS or FAIL).
# Writes output/boss-rework/colossus-films/<name>/ (frames, film.json, godot.log, strip.png, film.gif,
# film-slow.gif). Sheet options (--crop= --step= --cols= --scale= --from= --to= --title=) go to the
# sheet tool, everything else to the film (its camera zoom is --zoom=<z>). $GODOT overrides the Godot
# console exe.
set -u
cd "$(dirname "$0")/../.." || exit 1
here="$(pwd -W 2>/dev/null || pwd)"
godot="${GODOT:-C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"; shift
lock="$here/output/throw-feel/.film-lock"
film=(); sheet=()
tool="film_colossus"
for arg in "$@"; do
	case "$arg" in
		--crop=*|--step=*|--cols=*|--scale=*|--from=*|--to=*|--title=*) sheet+=("$arg") ;;
		--tool=*) tool="${arg#--tool=}" ;;
		*) film+=("$arg") ;;
	esac
done
if [ "$tool" = "film_colossus_arena" ]; then films="$here/output/dungeon-rework/mine/arena-films"; else films="$here/output/boss-rework/colossus-films"; fi
out="$films/$name"
mkdir -p "$here/output/throw-feel" "$films"
until mkdir "$lock" 2>/dev/null; do
	# A lock older than 8 minutes is a film that died: take it over.
	if [ -n "$(find "$lock" -maxdepth 0 -mmin +8 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null; continue; fi
	sleep 4
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
rm -rf "$out"; mkdir -p "$out"
"$godot" --path "$here/godot" --fixed-fps 60 -s "res://tools/$tool.gd" -- --out="$out" ${film[@]+"${film[@]}"} > "$out/godot.log" 2>&1
grep -E "film_colossus|SCRIPT ERROR|Parse Error|ERROR|^ +at: .*\.gd" "$out/godot.log" | grep -v "leaked" | cut -c1-300 | head -40
rmdir "$lock" 2>/dev/null
trap - EXIT
[ -f "$out/film.json" ] || { echo "film-colossus: no film.json (the film failed)"; exit 1; }
python "$here/scripts/godot/mechanism-film-sheet.py" "$out" ${sheet[@]+"${sheet[@]}"}
