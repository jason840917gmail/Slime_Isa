#!/usr/bin/env bash
# Films one of the dungeon mechanisms' films (godot/tools/film_mechanisms.gd: the knock target, the
# ram with its bricked arch, the runaway cart with its rail gate, in world.mechanism-lab) and lays
# it out (mechanism-film-sheet.py), one film at a time: it waits on the throw films' lock folder,
# since two game windows rendering at once stall each other.
#   scripts/godot/film-mechanisms.sh <name> --film=<film> [film options...] [sheet options...]
# Films: ram-arch, ram-enemies, ram-slime, ram-south, ram-west, target-refuse, target-arrow,
# target-blast, target-roll, arch-refuse, gate-refuse, cart-gate, cart-enemy, cart-return, cart-hook,
# look.
# Writes output/mechanisms/<name>/ (frames, film.json, godot.log, strip.png, film.gif, film-slow.gif).
# Sheet options (--crop= --step= --cols= --scale= --from= --to= --title=) go to the sheet tool,
# everything else to the film (its camera zoom is --zoom=<z>). $GODOT overrides the Godot console exe.
set -u
cd "$(dirname "$0")/../.." || exit 1
here="$(pwd -W 2>/dev/null || pwd)"
godot="${GODOT:-C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"; shift
out="$here/output/mechanisms/$name"
lock="$here/output/throw-feel/.film-lock"
film=(); sheet=()
for arg in "$@"; do
	case "$arg" in
		--crop=*|--step=*|--cols=*|--scale=*|--from=*|--to=*|--title=*) sheet+=("$arg") ;;
		*) film+=("$arg") ;;
	esac
done
mkdir -p "$here/output/throw-feel" "$here/output/mechanisms"
until mkdir "$lock" 2>/dev/null; do
	# A lock older than 8 minutes is a film that died: take it over.
	if [ -n "$(find "$lock" -maxdepth 0 -mmin +8 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null; continue; fi
	sleep 4
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
rm -rf "$out"; mkdir -p "$out"
"$godot" --path "$here/godot" --fixed-fps 60 -s res://tools/film_mechanisms.gd -- --out="$out" ${film[@]+"${film[@]}"} > "$out/godot.log" 2>&1
grep -E "film_mechanisms|SCRIPT ERROR|Parse Error|ERROR|^ +at: .*\.gd" "$out/godot.log" | grep -v "leaked" | cut -c1-300 | head -40
rmdir "$lock" 2>/dev/null
trap - EXIT
[ -f "$out/film.json" ] || { echo "film-mechanisms: no film.json (the film failed)"; exit 1; }
python "$here/scripts/godot/mechanism-film-sheet.py" "$out" ${sheet[@]+"${sheet[@]}"}
