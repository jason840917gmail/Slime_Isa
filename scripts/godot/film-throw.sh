#!/usr/bin/env bash
# Films one Gulp throw (godot/tools/film_throw.gd) and lays it out (throw-film-sheet.py), one film
# at a time: two game windows rendering at once stall each other, so every caller waits its turn
# on a lock folder.
#   scripts/godot/film-throw.sh <name> [--title="..."] [film_throw.gd options...]
# Writes output/throw-feel/<name>/ (frames, film.json, strip.png, throw.gif, throw-slow.gif).
# Sheet options (--crop= --step= --cols= --zoom= --from= --to= --title=) go to the sheet tool,
# everything else to the film. $GODOT overrides the Godot 4.7.2 console executable.
set -u
cd "$(dirname "$0")/../.." || exit 1
here="$(pwd -W 2>/dev/null || pwd)"
godot="${GODOT:-C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"; shift
out="$here/output/throw-feel/$name"
lock="$here/output/throw-feel/.film-lock"
film=(); sheet=()
for arg in "$@"; do
	case "$arg" in
		--crop=*|--step=*|--cols=*|--zoom=*|--from=*|--to=*|--title=*) sheet+=("$arg") ;;
		*) film+=("$arg") ;;
	esac
done
mkdir -p "$here/output/throw-feel"
waited=0
until mkdir "$lock" 2>/dev/null; do
	# A lock older than 6 minutes is a film that died: take it over.
	if [ -n "$(find "$lock" -maxdepth 0 -mmin +6 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null; continue; fi
	sleep 4; waited=$((waited + 4))
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
rm -rf "$out"; mkdir -p "$out"
"$godot" --path "$here/godot" --fixed-fps 60 -s res://tools/film_throw.gd -- --out="$out" ${film[@]+"${film[@]}"} > "$out/godot.log" 2>&1
grep -E "film_throw|SCRIPT ERROR|Parse Error|^ +at: .*\.gd" "$out/godot.log" | cut -c1-300 | head -40
rmdir "$lock" 2>/dev/null
trap - EXIT
[ -f "$out/film.json" ] || { echo "film-throw: no film.json (the film failed)"; exit 1; }
python "$here/scripts/godot/throw-film-sheet.py" "$out" ${sheet[@]+"${sheet[@]}"}
