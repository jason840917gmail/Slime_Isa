#!/usr/bin/env bash
# Films one of the enemy films (godot/tools/film_enemy_ways.gd: the Dung Roller's stolen ball, the
# walk home) and lays it out (throw-film-sheet.py), one film at a time: it waits on the throw
# films' lock folder, since two game windows rendering at once stall each other.
#   scripts/godot/film-enemy-ways.sh <name> --film=<film> [film options...] [sheet options...]
# Writes output/enemy-ways/<name>/ (frames, film.json, godot.log, strip.png, throw.gif).
# Sheet options (--crop= --step= --cols= --zoom= --from= --to= --title=) go to the sheet tool,
# everything else to the film (its own zoom is --cam=<z>). $GODOT overrides the Godot console exe.
# --tool=<name> films with another tool in godot/tools/ (film_worm_bulwark: the Worm Bulwark).
set -u
cd "$(dirname "$0")/../.." || exit 1
here="$(pwd -W 2>/dev/null || pwd)"
godot="${GODOT:-C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"; shift
out="$here/output/enemy-ways/$name"
lock="$here/output/throw-feel/.film-lock"
film=(); sheet=(); tool=film_enemy_ways
for arg in "$@"; do
	case "$arg" in
		--crop=*|--step=*|--cols=*|--zoom=*|--from=*|--to=*|--title=*) sheet+=("$arg") ;;
		--cam=*) film+=("--zoom=${arg#--cam=}") ;;
		--tool=*) tool="${arg#--tool=}" ;;
		*) film+=("$arg") ;;
	esac
done
mkdir -p "$here/output/throw-feel" "$here/output/enemy-ways"
until mkdir "$lock" 2>/dev/null; do
	# A lock older than 6 minutes is a film that died: take it over.
	if [ -n "$(find "$lock" -maxdepth 0 -mmin +6 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null; continue; fi
	sleep 4
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
rm -rf "$out"; mkdir -p "$out"
"$godot" --path "$here/godot" --fixed-fps 60 -s "res://tools/$tool.gd" -- --out="$out" ${film[@]+"${film[@]}"} > "$out/godot.log" 2>&1
grep -E "film_enemy_ways|$tool|SCRIPT ERROR|Parse Error|ERROR|^ +at: .*.gd" "$out/godot.log" | grep -v "leaked" | cut -c1-300 | head -40
rmdir "$lock" 2>/dev/null
trap - EXIT
[ -f "$out/film.json" ] || { echo "film-enemy-ways: no film.json (the film failed)"; exit 1; }
python "$here/scripts/godot/throw-film-sheet.py" "$out" ${sheet[@]+"${sheet[@]}"}
