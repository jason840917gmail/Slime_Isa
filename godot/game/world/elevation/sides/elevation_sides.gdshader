shader_type canvas_item;

// Cliffs with side walls (docs/godot/ELEVATION.md "Side walls", sides/elevation_sides.gd): one mesh
// holds a level's walls and their edges in painter's order, so each piece picks its look here.
// The edges are drawn, not painted strips: the grounds' own sheets in world space (as the ground
// draws them, so they join it without a seam), a shade, a jagged outline and a shadow, as in the
// owner's reference (2026-10-13: "simpler borders").
// Vertex colour r = the kind of piece: 0 … 0.2 wall (front … side), 0.3 corner stone, 0.5 foot
// (0.54 standing in water: foam),
// 0.6 / 0.7 the lower / the top's ground filling a corner, 1 top edge; a = the height in levels ((level + 4) / 8, elevation_light.gdshaderinc).
// - Wall: UV = (px along the border, px down the fibre + the course of its level); g = the face's
//   light, b = px down the fibre / 512 (the top edge's shadow on the wall). r / 0.2 = how much it is
//   a side's: the style's side strip art (`side_texture`, one course tall) blends in by it.
// - Corner stone: UV = (u in the corner sheet, 0 … 1 down its course); g, b as a wall's.
// - Top edge: UV = (world units along the border, world units past the edge: negative over the top,
//   positive over the wall); g = 1 on a side or back edge (a shorter overhang), 0 on a front; b = 1
//   on a back edge, which has no wall: its clumps lie on the ground behind and their outline is a
//   dark green, not the walls' brown.
// - Foot: UV = (world units along the foot, world units past it: negative up the wall, positive
//   over the lower ground); g = the strength of the shadow on the ground; b = 1 on a back edge:
//   only the shadow.

#include "res://game/world/elevation/elevation_light.gdshaderinc"

uniform sampler2D wall_texture : source_color, repeat_enable, filter_linear;
uniform vec2 wall_size = vec2(536.0, 256.0);
// A side wall's own art: a row of short rounded stones, one course tall, as wide as the wall's art
// (0 without one: the wall's art is used).
uniform sampler2D side_texture : source_color, repeat_enable, filter_linear;
uniform vec2 side_size = vec2(536.0, 128.0);
uniform float has_side = 0.0;
// The corner stones, side by side (sides/elevation_sides.gd CORNER_STONES); 0 without them.
uniform sampler2D corner_texture : source_color, filter_linear;
uniform float has_corners = 0.0;
// The top's ground and the lower ground: their sheets, sheet-wrapped in world space.
uniform sampler2D top_ground : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D low_ground : source_color, repeat_enable, filter_linear_mipmap;
uniform float ground_period = 1216.0;
uniform vec2 ground_origin = vec2(0.0);
// The top edge's shadow on its wall: strength and how far down the fibre (px of art).
uniform float top_shadow = 0.4;
uniform float top_shadow_px = 22.0;
// Top edge: the top darkening towards the edge (world units, strength), the grass hanging over the
// wall (world units: a front's, a side's, and how much its clumps add), the clumps' width, and the
// outline along them (a back edge's in `back_outline_colour`).
uniform float band_width = 12.0;
uniform float band_shade = 0.22;
uniform float overhang_front = 2.5;
uniform float overhang_side = 1.5;
uniform float clump_height = 4.5;
uniform float clump_width = 7.0;
uniform float outline_width = 3.0;
uniform vec4 outline_colour : source_color = vec4(0.16, 0.1, 0.05, 1.0);
uniform vec4 back_outline_colour : source_color = vec4(0.22, 0.3, 0.06, 1.0);
// Foot: the outline over the lower ground's clumps up the wall, their height, the shadow over the
// ground.
uniform float foot_outline = 2.2;
uniform vec4 foot_line_colour : source_color = vec4(0.16, 0.1, 0.05, 1.0);
uniform float foot_clumps = 4.0;
uniform float foot_shadow_width = 18.0;
// 1 when the lower ground is water: the foot is a band of foam lapping at the wall instead.
uniform float low_is_water = 0.0;
uniform vec4 foam_colour : source_color = vec4(0.88, 0.96, 1.0, 0.8);

varying vec2 world;
varying vec4 data;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	data = COLOR;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// Round bumps along an edge, `width` wide, each of its own height (0 … 1).
float bumps(float u, float width, float seed) {
	float i = floor(u / width);
	float x = fract(u / width) * 2.0 - 1.0;
	return sqrt(max(0.0, 1.0 - x * x)) * (0.4 + 0.6 * hash(i + seed));
}

// Grass clumps along an edge: two sizes of bumps over each other, so they never repeat evenly.
float clumps(float u, float width) {
	return max(bumps(u, width, 0.0), 0.8 * bumps(u + width * 0.43, width * 0.63, 17.0));
}

void fragment() {
	float kind = data.r;
	float light_of_level = level_light(decode_level(data.a));
	if (kind < 0.25) {
		vec3 rock = texture(wall_texture, UV / wall_size).rgb;
		float side = clamp(kind / 0.2, 0.0, 1.0) * has_side;
		if (side > 0.0) {
			rock = mix(rock, texture(side_texture, UV / side_size).rgb, side);
		}
		float depth = data.b * 512.0;
		float light = data.g * light_of_level;
		light *= 1.0 - top_shadow * (1.0 - smoothstep(0.0, top_shadow_px, depth));
		COLOR = vec4(rock * light, 1.0);
	} else if (kind < 0.4) {
		vec4 stone = texture(corner_texture, vec2(UV.x, clamp(UV.y, 0.002, 0.998)));
		float depth = data.b * 512.0;
		float light = data.g * light_of_level;
		light *= 1.0 - top_shadow * (1.0 - smoothstep(0.0, top_shadow_px, depth));
		COLOR = vec4(stone.rgb * light, stone.a * has_corners);
	} else if (kind < 0.55) {
		float d = UV.y;
		float aa = max(fwidth(d), 0.01);
		// The lower ground's clumps up the wall's base (−reach … 0), a dark line over their tips.
		float reach = foot_clumps * clumps(UV.x + 13.7, clump_width * 0.8) * (1.0 - data.b);
		// As dark as the ground beside them, which the hill's shadow darkens (more facing the lower right).
		vec3 grass = texture(low_ground, world / ground_period).rgb * light_of_level * (0.85 - 0.9 * data.g);
		float above_tips = 1.0 - smoothstep(-reach - aa, -reach + aa, d);
		float line = smoothstep(-reach - foot_outline - aa, -reach - foot_outline + aa, d) * above_tips;
		float blade = (1.0 - above_tips) * (1.0 - step(0.0, d));
		vec4 art = vec4(mix(grass, foot_line_colour.rgb, line), max(line, blade) * (1.0 - data.b));
		if (low_is_water > 0.5 || kind > 0.52) {
			// Foam: a band up the wall's base and onto the water, lapping (presentation time).
			float lap = 1.2 + 1.2 * sin(UV.x * 0.13 + TIME * 1.6) + 0.6 * sin(UV.x * 0.37 - TIME * 2.3);
			float band = smoothstep(-lap - 1.5 - aa, -lap - 1.5 + aa, d) * (1.0 - smoothstep(1.5 - aa, 1.5 + aa, d));
			art = vec4(foam_colour.rgb * light_of_level, band * foam_colour.a * (1.0 - data.b));
		}
		float shadow = data.g * (1.0 - smoothstep(0.0, foot_shadow_width, d)) * step(0.0, d);
		float out_alpha = art.a + shadow * (1.0 - art.a);
		vec3 out_rgb = out_alpha > 0.0 ? art.rgb * art.a / out_alpha : vec3(0.0);
		COLOR = vec4(out_rgb, out_alpha);
	} else if (kind < 0.65) {
		COLOR = vec4(texture(low_ground, world / ground_period).rgb * light_of_level, 1.0);
	} else if (kind < 0.8) {
		COLOR = vec4(texture(top_ground, world / ground_period).rgb * light_of_level, 1.0);
	} else {
		float d = UV.y;
		float aa = max(fwidth(d), 0.01);
		// A back edge's clumps lie on the ground behind, as big as a front's.
		float tip = mix(overhang_front, overhang_side, data.g) + clump_height * mix(mix(1.0, 0.6, data.g), 1.0, data.b) * clumps(UV.x, clump_width);
		vec3 grass = texture(top_ground, world / ground_period).rgb * light_of_level;
		grass *= 1.0 - band_shade * smoothstep(-band_width, 0.0, d);
		float inside = 1.0 - smoothstep(tip - aa, tip + aa, d);
		float edge = smoothstep(tip - outline_width - aa, tip - outline_width + aa, d);
		vec3 line = mix(outline_colour.rgb, back_outline_colour.rgb * light_of_level, data.b);
		COLOR = vec4(mix(grass, line, edge), inside);
	}
}
