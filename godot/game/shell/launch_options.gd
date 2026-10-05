extends RefCounted
class_name LaunchOptions
## Launch options of a test run: the web page's query (`?map=level-1&spawn=1130,1300`) or the
## desktop user arguments after `--` (`-- --map=level-1 --spawn=1130,1300`). main.gd reads the
## values (`Main.launch_option`); the title screen only asks whether any of them is present,
## because a test launch skips the title (docs/godot/specs/shell.md section 1).
##
## Owner: shell.

## Options that start the game at once, skipping the title screen. `skip-title` takes no value.
const SKIP_TITLE_OPTIONS: PackedStringArray = ["map", "spawn", "weapon", "skip-title"]


## True when this launch carries any SKIP_TITLE_OPTIONS (web query or desktop user args).
static func should_skip_title() -> bool:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		return should_skip_title_query(search as String if search is String else "")
	return should_skip_title_args(OS.get_cmdline_user_args())


## Desktop form: `--map=<id>`, `--spawn=<x>,<y>`, `--weapon=<id>` or `--skip-title` among `args`.
static func should_skip_title_args(args: PackedStringArray) -> bool:
	for option: String in SKIP_TITLE_OPTIONS:
		if has_arg_option(args, option):
			return true
	return false


## Web form: any SKIP_TITLE_OPTIONS key in a `?a=b&c` query string (with or without the "?").
static func should_skip_title_query(query: String) -> bool:
	var keys := query_keys(query)
	for option: String in SKIP_TITLE_OPTIONS:
		if keys.has(option):
			return true
	return false


## True when `args` holds `--<option>` or `--<option>=<value>`.
static func has_arg_option(args: PackedStringArray, option: String) -> bool:
	var flag := "--" + option
	for arg: String in args:
		if arg == flag or arg.begins_with(flag + "="):
			return true
	return false


## The decoded keys of a query string, in order.
static func query_keys(query: String) -> PackedStringArray:
	var keys := PackedStringArray()
	var trimmed := query.strip_edges().trim_prefix("?")
	if trimmed.is_empty():
		return keys
	for part: String in trimmed.split("&", false):
		keys.append(part.split("=", true, 1)[0].uri_decode())
	return keys
