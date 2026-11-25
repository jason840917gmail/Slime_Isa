#!/usr/bin/env bash
# Films one of the Orb-Weaver Matron's ram-fight films (godot/tools/film_matron.gd, in world.matron-lab)
# and lays it out (mechanism-film-sheet.py), one film at a time: it waits on the throw films' lock
# folder, since two game windows rendering at once stall each other.
#   scripts/godot/film-matron.sh <name> --film=<film> [film options...] [sheet options...]
# Films: round1, dive, ram-catch, ring, round3, look. With --tool=film_crown the same films in the
# rebuilt Weaver Hollow's Crown (godot/tools/film_crown.gd, world.weaver-hollow-c2-crown: the lab's
# arena carried into the room), into output/dungeon-rework/hollow/crown-films/<name>/ (round1,
# ram-catch and round3 say PASS or FAIL).
# Writes output/boss-rework/matron-films/<name>/ (frames, film.json, godot.log, strip.png, film.gif,
# film-slow.gif). Sheet options (--crop= --step= --cols= --scale= --from= --to= --title=) go to the
# sheet tool, everything else to the film (its camera zoom is --zoom=<z>). $GODOT overrides the Godot
# console exe.
set -u
cd "$(dirname "$0")/../.." || exit 1
here="$(pwd -W 2>/dev/null || pwd)"
godot="${GODOT:-C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"; shift
lock="$here/output/throw-feel/.film-lock"
tool="film_matron"
film=(); sheet=()
for arg in "$@"; do
	case "$arg" in
		--tool=*) tool="${arg#--tool=}" ;;
		--crop=*|--step=*|--cols=*|--scale=*|--from=*|--to=*|--title=*) sheet+=("$arg") ;;
		*) film+=("$arg") ;;
	esac
done
if [ "$tool" = "film_crown" ]; then films="$here/output/dungeon-rework/hollow/crown-films"; else films="$here/output/boss-rework/matron-films"; fi
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
grep -E "film_matron|film_crown|SCRIPT ERROR|Parse Error|ERROR|^ +at: .*\.gd" "$out/godot.log" | grep -v "leaked" | cut -c1-300 | head -40
rmdir "$lock" 2>/dev/null
trap - EXIT
[ -f "$out/film.json" ] || { echo "film-matron: no film.json (the film failed)"; exit 1; }
python "$here/scripts/godot/mechanism-film-sheet.py" "$out" ${sheet[@]+"${sheet[@]}"}
