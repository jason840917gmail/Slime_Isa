shader_type canvas_item;

// The cliffs' dressing (sides/ledge_dressing.gd, docs/godot/ELEVATION.md "Ledge dressing"): pieces
// of the dressing atlas (scripts/art/build-cliff-dressing.py) at the walls' feet.
// UV = px in the atlas; colour r = the light, a = the level channel (holes darken it).

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear;

varying vec4 data;

void vertex() {
	data = COLOR;
}

void fragment() {
	vec4 art = texture(atlas, UV / vec2(textureSize(atlas, 0)));
	float light = data.r * level_light(decode_level(data.a));
	COLOR = vec4(art.rgb * light, art.a);
}
