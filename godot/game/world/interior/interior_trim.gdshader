// The floor trim's colour (docs/godot/INTERIOR_WALLS.md "Floor trim"): the sheet holds every shape in
// grey (its levels stretched to 0..1, scripts/art/pack-floor-trims.py), and the trim's ramp (its
// colour's gradient map, InteriorTrimLayer.material_of) paints it, so a colour costs no sheet space.
// On a floor below level 0 it darkens as the floor does (elevation_light.gdshaderinc).
// Owner: world (interior walls).
shader_type canvas_item;

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D ramp : filter_linear, repeat_disable;
// the level of the floor the band lies on
uniform float level = 0.0;

// the modulate (the vertex colour); in fragment() COLOR is already multiplied by the grey texture
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 grey = texture(TEXTURE, UV);
	COLOR = vec4(texture(ramp, vec2(grey.r, 0.5)).rgb * level_light(level), grey.a) * tint;
}
