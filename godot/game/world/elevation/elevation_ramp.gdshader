shader_type canvas_item;

// A ramp's slope (docs/godot/ELEVATION.md "Ramps", elevation_ramp.gd): its ground's sheet in world
// space, as the ground draws it (the 128 px sheet where there is one, sheet-wrap), so the slope is
// one with the ground around it and the levels seem to meet (the illusion of A Link to the Past).
// Drawn over the wall it runs beside, it leaves of that wall only what stands above the slope. It
// takes the shadows higher ground casts on it (elevation_cast_shadow.gdshaderinc) at its own
// height, as the ground it covers took them at its level. Vertex colour g = the slope's height in
// levels ((L + 4) / 8): in a hole it darkens as the ground there does (elevation_light.gdshaderinc);
// a = its opacity (its edge along a face, a rimmed ramp's landing at its sides and an open end's cap
// fade out); r = how much of the cast shadows it takes (an open end's cap none near the end,
// elevation_ramp.gd `shadow_take`; 1 elsewhere).

#include "res://game/world/elevation/elevation_light.gdshaderinc"
#include "res://game/world/elevation/elevation_cast_shadow.gdshaderinc"

uniform sampler2D ground_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform float ground_period = 1216.0;
uniform vec2 ground_origin = vec2(0.0);
// 0 without a depth map (the shadows are left out).
uniform float shadows = 1.0;

varying vec2 world;
varying vec2 local;
varying float height;
varying float opacity;
varying float take;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	local = VERTEX;
	height = decode_level(COLOR.g);
	opacity = COLOR.a;
	take = COLOR.r;
}

void fragment() {
	float shade = shadows > 0.5 ? take * cast_shade(local, height) : 0.0;
	vec3 ground = texture(ground_texture, world / ground_period).rgb * level_light(height);
	COLOR = vec4(ground * (1.0 - strength * shade), smoothstep(0.0, 1.0, opacity));
}
