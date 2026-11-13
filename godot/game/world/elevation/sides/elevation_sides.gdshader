shader_type canvas_item;

// Cliffs with side walls (docs/godot/ELEVATION.md "Side walls", sides/elevation_sides.gd): one mesh
// holds a level's walls and their edges in painter's order, so each piece picks its look here.
// The edges are drawn, not painted strips: the grounds' own sheets in world space (as the ground
// draws them, so they join it without a seam), a shade, a jagged outline and a shadow, as in the
// owner's reference (2026-10-13: "simpler borders").
// Vertex colour r = the kind of piece: 0 … 0.2 wall (front … side), 0.3 corner stone, 0.5 foot
// (0.54 where that edge's lower ground is water: the water lapping up the wall),
// 0.6 / 0.7 the lower / the top's ground filling a corner, 1 top edge; a = the height in levels ((level + 4) / 32, elevation_light.gdshaderinc).
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
//   only the shadow. A foot in water draws the water itself up the wall's base (`has_water`: the
//   water surface's own maths and parameters, Elevation hands them on), as a deep-water bank's
//   foot (docs/godot/specs/water.md §11).

#include "res://game/world/elevation/elevation_light.gdshaderinc"
#include "res://game/world/water_surface.gdshaderinc"

uniform sampler2D wall_texture : source_color, repeat_enable, filter_linear;
uniform vec2 wall_size = vec2(536.0, 256.0);
// Wall variation (docs/godot/ELEVATION.md "Wall variation", scripts/art/build-wall-variants.py):
// the style's variants, `variant_count` courses a period wide that all start and end alike, stacked;
// 0 without them (the wall art repeats). Each course of a wall shows them shifted by its own amount,
// a variant picked per period of it.
uniform sampler2D variant_texture : source_color, repeat_enable, filter_linear;
uniform float variant_count = 0.0;
// 1: each course shifted by its own amount (a style whose courses meet in a crevice); 0: a seamless
// style (the earth walls), whose variants share their top and bottom rows: its courses stay aligned.
uniform float course_shift = 1.0;
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
// Ledge strips (elevation.gd FRINGE_GROUNDS): the top's lip strip and the lower ground's foot strip,
// periodic along the edge, 2 px a world unit, their edge line on row `lip_edge_row` / `foot_edge_row`.
// The top's own ground covers only `grass_reach_in` over the top: past it only a strip's art draws,
// fading out `strip_fade` short of the piece's ends (`lip_reach_in` over the top, `lip_reach_out`
// past the edge, `foot_reach_up` up the wall: elevation_sides.gd EDGE_IN, EDGE_OUT, FOOT_UP).
uniform sampler2D lip_strip : source_color, repeat_enable, filter_linear;
uniform vec2 lip_strip_size = vec2(564.0, 160.0);
uniform float has_lip_strip = 0.0;
uniform sampler2D foot_strip : source_color, repeat_enable, filter_linear;
uniform vec2 foot_strip_size = vec2(457.0, 128.0);
uniform float has_foot_strip = 0.0;
uniform float lip_edge_row = 96.0;
uniform float foot_edge_row = 80.0;
uniform float grass_reach_in = 12.0;
uniform float lip_reach_in = 36.0;
uniform float lip_reach_out = 24.0;
uniform float foot_reach_up = 30.0;
uniform float strip_fade = 6.0;
// A lip strip's part over the top melts into the top's ground over this many world units.
uniform float strip_top_fade = 20.0;
// Fixed ledges (the owner, 2026-11-06: "instead of random ledges ... a fixed ledge with some variation
// like the walls but occupying all the edge, not random spots, in the top and bottom"): every top edge
// shows the top's lip strip and every foot the lower ground's foot strip along its whole length (plain
// clumps where the ground has none). Their variation, as the walls' variants: every `ledge_period`
// units along the edge the strip is read from a place of its own (`ledge_period_of`), the change
// ragged plant by plant (`ragged`, in chunks about `ragged_width` units wide) over `lip_blend` of a
// period, so no stretch repeats the one beside it. (The ledge variety before them, 2026-11-05, picked
// a kind of lip and foot per stretch: shaggy tufts, rim stones, bare soil, tall grass, fallen stones;
// replaced by them, removed 2026-11-07.)
uniform float ledge_period = 150.0;
uniform float lip_blend = 0.3;
uniform float ragged_width = 9.0;
// The shadow laid over a foot strip (the owner: "painting the shadow over the ledge with opacity"):
// `foot_shadow_over` of the foot's shadow strength, as strong as the shadow over the ground beside it
// and fading out `foot_shadow_up` units up the wall, so the strip sinks into the shadowed ground.
uniform float foot_shadow_over = 0.75;
uniform float foot_shadow_up = 26.0;
// The fixed lip goes round every edge of a top (the owner: "why the top lid stops at the sides and
// back?"): past a side edge it reaches `lip_side_out` of `lip_reach_out`, past a back edge (no wall to
// hang over) `lip_back_out` of it.
uniform float lip_side_out = 0.45;
uniform float lip_back_out = 0.15;
// A plant strip's painted background (elevation.gd FRINGE_KEYS; alpha 0: not keyed), see-through
// within `key_near` … `key_far` of it (0 … 1 RGB distance): a foot's everywhere, a lip's over the top.
uniform vec4 lip_key : source_color = vec4(0.0);
uniform vec4 foot_key : source_color = vec4(0.0);
uniform float key_near = 0.05;
uniform float key_far = 0.12;
// A foot in water without the water's parameters (no water surface): a band of foam.
uniform vec4 foam_colour : source_color = vec4(0.88, 0.96, 1.0, 0.8);
// A foot in water with them (1): the water laps `water_line_rise` units up the wall's base,
// wobbling `water_line_sway` units either way, the rock `wet_height` units above it darkened by
// `wet_shade`, and foam laps there `water_line_foam_strength` strong, as at a bank's foot. The
// water is open water at the wall, the surface's own again by the foot's far end, `foot_rows`
// past the foot line (Elevation sets it: elevation_sides.gd FOOT_OUT).
uniform float has_water = 0.0;
// 0: the wall stands on no ground (it hangs into a sky floor, elevation.gd SKY_GROUND): no foot is
// drawn, neither its art nor its shadow.
uniform float has_foot = 1.0;
uniform float foot_rows = 20.0;
uniform float water_line_rise = 2.8;
uniform float water_line_sway = 2.4;
uniform float wet_height = 2.5;
uniform float wet_shade = 0.3;
uniform float water_line_foam_strength = 0.6;
// A deep-water bank's face (specs/water.md §11): the foam's reach is measured in it.
const float BANK_FACE = 24.0;

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

// The wall's rock at `uv` (px along the border, px down the courses). With variants, each course
// (128 px, crevice to crevice: the shift and the picks never meet on a stone) is shifted by its own
// amount and shows a variant picked per period, by the course, so neither the periods along a wall
// nor the courses down it repeat (each chain's u starts its own whole number of periods in:
// elevation_sides.gd START_PERIODS). Only the course and the period may pick: the vertex data vary
// down a wall (data.a is the height of each point), and the hash scatters on any difference.
vec3 wall_rock(vec2 uv) {
	if (variant_count < 0.5) {
		return texture(wall_texture, uv / wall_size).rgb;
	}
	float course = floor(uv.y / 128.0);
	float seed = course * 12.9898;
	float u = uv.x + floor(hash(seed + 0.31) * wall_size.x) * course_shift;
	float period = floor(u / wall_size.x);
	float pick = min(floor(hash(period * 0.6180339 + seed + 0.5) * variant_count), variant_count - 1.0);
	vec2 at = vec2(u - period * wall_size.x, pick * 128.0 + uv.y - course * 128.0);
	return texture(variant_texture, at / vec2(wall_size.x, 128.0 * variant_count)).rgb;
}

// Grass clumps along an edge: two sizes of bumps over each other, so they never repeat evenly.
float clumps(float u, float width) {
	return max(bumps(u, width, 0.0), 0.8 * bumps(u + width * 0.43, width * 0.63, 17.0));
}

// Two pieces of art (straight alpha) blended, `t` of the second: by their premultiplied colours, so
// one's colour where it is see-through does not tint the other.
vec4 blend_art(vec4 a, vec4 b, float t) {
	float alpha = mix(a.a, b.a, t);
	vec3 colour = mix(a.rgb * a.a, b.rgb * b.a, t);
	return vec4(alpha > 0.0 ? colour / alpha : vec3(0.0), alpha);
}

// A fixed ledge's period at `u` (`ledge_period`): (where in the strip it reads from, 0 … 1 of the
// strip's width; the next period's; how far it has blended into the next one).
vec3 ledge_period_of(float u, float seed) {
	float x = u / ledge_period;
	float i = floor(x);
	return vec3(hash(i * 0.917 + seed), hash((i + 1.0) * 0.917 + seed), smoothstep(1.0 - lip_blend, 1.0, fract(x)));
}

// A ledge strip's art at (u, d) (world units along, past its edge line), see-through off the strip.
vec4 strip_art(sampler2D strip, vec2 size, float edge_row, float u, float d) {
	float v = (edge_row + d * 2.0) / size.y;
	vec4 art = texture(strip, vec2(u * 2.0 / size.x, clamp(v, 0.001, 0.999)));
	art.a *= step(0.0, v) * step(v, 1.0);
	return art;
}

// Smooth value noise along a line (0 … 1).
float line_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i * 1.913 + 7.0), hash((i + 1.0) * 1.913 + 7.0), f * f * (3.0 - 2.0 * f));
}

// A kind's blend `t` (0 … 1) made ragged along `u` (`ragged_width`), slanting with `d` so a patch
// does not end on a straight line down the wall.
float ragged(float t, float u, float d) {
	float threshold = 0.1 + 0.8 * line_noise(u / ragged_width + d / 14.0);
	return smoothstep(threshold - 0.06, threshold + 0.06, t);
}

// How much of a strip pixel is its painted background `key` (0 … 1; 0 without a key).
float keyed(vec3 colour, vec4 key) {
	return key.a * (1.0 - smoothstep(key_near, key_far, distance(colour, key.rgb)));
}

// `top` over `under` (straight alpha).
vec4 over(vec4 top, vec4 under) {
	float alpha = top.a + under.a * (1.0 - top.a);
	vec3 colour = top.rgb * top.a + under.rgb * under.a * (1.0 - top.a);
	return vec4(alpha > 0.0 ? colour / alpha : vec3(0.0), alpha);
}

// The top's grass (`top`, its ground's colour there) over its edge up to `tip` (world units past the
// edge), darkening towards the edge, a dark outline along the tip (a back edge's dark green).
vec4 grass_lip(vec3 top, float tip, float d, float back, float light, float aa) {
	vec3 grass = top * light;
	grass *= 1.0 - band_shade * smoothstep(-band_width, 0.0, d);
	// What hangs past the edge is a clump seen from the front: in its own shade towards its tip.
	grass *= 1.0 - 0.28 * smoothstep(0.0, max(tip, 1.0), d) * step(0.0, d);
	float inside = (1.0 - smoothstep(tip - aa, tip + aa, d)) * step(-grass_reach_in, d);
	float edge = smoothstep(tip - outline_width - aa, tip - outline_width + aa, d);
	vec3 line = mix(outline_colour.rgb, back_outline_colour.rgb * light, back);
	return vec4(mix(grass, line, edge), inside);
}

// The lip at (u, d): plain clumps (`strip_kind` 0) or the top's lip strip over shorter ones (1).
// `side` 1 on a side edge (a shorter overhang), `back` 1 on a back edge.
vec4 lip_of(vec3 top, float strip_kind, float u, float d, float side, float back, float light, float aa) {
	float scale = mix(mix(1.0, 0.6, side), 1.0, back);
	float base = mix(overhang_front, overhang_side, side);
	if (strip_kind < 0.5) {
		return grass_lip(top, base + clump_height * scale * clumps(u, clump_width), d, back, light, aa);
	}
	vec4 strip = strip_art(lip_strip, lip_strip_size, lip_edge_row, u, d);
	strip.a *= 1.0 - keyed(strip.rgb, lip_key) * (1.0 - smoothstep(-2.0, 2.0, d));
	strip.rgb *= light;
	// Past the edge the strip hangs over the wall: a side's narrow strip takes `lip_side_out` of it,
	// a back edge (no wall) only `lip_back_out`, so its soil does not lie on the ground as a dark slab.
	float reach_out = lip_reach_out * mix(mix(1.0, lip_side_out, side), lip_back_out, back);
	strip.a *= smoothstep(-lip_reach_in, -lip_reach_in + strip_top_fade, d) * (1.0 - smoothstep(reach_out - strip_fade, reach_out, d));
	return over(strip, grass_lip(top, base * 0.6, d, back, light, aa));
}

// The foot at (u, d) (d negative up the wall): plain clumps (`strip_kind` 0) or the lower ground's foot
// strip over them (1). Its art only (the shadow is laid under it by the caller). `ground` the lower
// ground's colour there.
vec4 foot_of(float strip_kind, float u, float d, vec3 ground, float light, float aa) {
	float reach = foot_clumps * clumps(u + 13.7, clump_width * 0.8);
	float above_tips = 1.0 - smoothstep(-reach - aa, -reach + aa, d);
	float line = smoothstep(-reach - foot_outline - aa, -reach - foot_outline + aa, d) * above_tips;
	float blade = (1.0 - above_tips) * (1.0 - step(0.0, d));
	vec4 art = vec4(mix(ground, foot_line_colour.rgb, line), max(line, blade));
	if (strip_kind > 0.5) {
		vec4 strip = strip_art(foot_strip, foot_strip_size, foot_edge_row, u, d);
		strip.a *= 1.0 - keyed(strip.rgb, foot_key);
		strip.rgb *= light;
		strip.a *= smoothstep(-foot_reach_up, -foot_reach_up + strip_fade, d);
		return over(strip, art);
	}
	return art;
}

// A wall's foot in water (`has_water`), layered bottom to top: the rock just above the waterline
// wet, the water up the wall's base to a wobbling waterline (the surface's own maths, the hole's
// light as the Shade gives it: open water at the wall, the water around by the foot's far end),
// the wall's shadow on the water from the waterline out, and foam lapping in patches at the
// waterline, as at a deep-water bank's foot. `d` = world units past the foot (negative up the
// wall; past it, rows: `foot_rows` of them to the foot's far end), `shadow` its strength, `show`
// 0 on a back edge (no wall there: only the shadow).
vec4 foot_in_water(vec2 px, float along, float d, float shadow, float show, float light, float t) {
	float waterline = (-water_line_rise - water_line_sway * water_line_wobble(along)) * show;
	float deep;
	vec4 surface = water_surface_shaped(px, t, 1.0, (1.0 - smoothstep(0.0, foot_rows, d)) * show, deep);
	vec3 water = mix(water_ground_at(px, deep), surface.rgb, surface.a) * light;
	// Over the rock below the waterline and out to the foot's far end, where it is the water around.
	float cover = smoothstep(waterline - 0.6, waterline + 0.6, d) * (1.0 - smoothstep(foot_rows - 1.0, foot_rows, d)) * show;
	float wet = wet_shade * (1.0 - smoothstep(0.0, wet_height, waterline - d)) * (1.0 - step(0.0, d)) * show;
	float shade = shadow * (1.0 - smoothstep(0.0, foot_shadow_width, d - waterline)) * smoothstep(waterline - 0.6, waterline + 0.6, d);
	float foam = water_line_foam_strength * water_line_foam(along, 1.0 + (d - waterline) / BANK_FACE, t) * show;
	vec4 layered = vec4(0.0, 0.0, 0.0, wet);
	layered = vec4(water * cover, cover) + layered * (1.0 - cover);
	layered = vec4(0.0, 0.0, 0.0, shade) + layered * (1.0 - shade);
	layered = vec4(WATER_FOAM * light * foam, foam) + layered * (1.0 - foam);
	return vec4(layered.a > 0.0 ? layered.rgb / layered.a : vec3(0.0), layered.a);
}

void fragment() {
	float kind = data.r;
	float light_of_level = level_light(decode_level(data.a));
	if (kind < 0.25) {
		vec3 rock = wall_rock(UV);
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
	} else if (kind < 0.55 && has_foot < 0.5) {
		discard;
	} else if (kind > 0.52 && kind < 0.55 && has_water > 0.5) {
		COLOR = foot_in_water(world, UV.x, UV.y, data.g, 1.0 - data.b, light_of_level, TIME);
	} else if (kind < 0.55) {
		float d = UV.y;
		float aa = max(fwidth(d), 0.01);
		// The lower ground's clumps up the wall's base (−reach … 0), a dark line over their tips, under
		// its foot strip where it has one (`foot_of`).
		// As dark as the ground beside them, which the hill's shadow darkens (more facing the lower right).
		vec3 grass = texture(low_ground, world / ground_period).rgb * light_of_level * (0.85 - 0.9 * data.g);
		vec4 art;
		bool strip_foot = has_foot_strip > 0.5;
		if (strip_foot) {
			// The lower ground's foot strip all along, read from its own place every `ledge_period`.
			vec3 p = ledge_period_of(UV.x, 5.3);
			float w = foot_strip_size.x * 0.5;
			art = blend_art(foot_of(1.0, UV.x + p.x * w, d, grass, light_of_level, aa),
					foot_of(1.0, UV.x + p.y * w, d, grass, light_of_level, aa), ragged(p.z, UV.x, d));
		} else {
			art = foot_of(0.0, UV.x, d, grass, light_of_level, aa);
		}
		// A side wall's dry foot comes in two pieces (elevation_sides.gd KIND_FOOT_ART, KIND_FOOT_SHADOW):
		// the art (in world units, past the foot line too) and the shadow ring (no art: its rows are
		// stretched over the shadow's length). A ramp's foot (KIND_FOOT) draws both.
		bool art_only = kind < 0.47;
		bool shadow_only = kind >= 0.47 && kind < 0.49;
		art.a *= (1.0 - data.b) * (shadow_only ? 0.0 : 1.0);
		if (strip_foot && !shadow_only) {
			// The shadow laid over the strip: as strong as over the ground at the foot line, fading out up
			// the wall (past the foot line the ring's shadow lies under the strip's art).
			float up = 1.0 - smoothstep(0.0, foot_shadow_up, -d);
			float out_there = 1.0 - smoothstep(0.0, foot_shadow_width, d);
			art.rgb *= 1.0 - data.g * foot_shadow_over * (d < 0.0 ? up : out_there);
		}
		if (kind > 0.52) {
			// Without the water's parameters, foam: a band up the wall's base and onto the water,
			// lapping (presentation time).
			float lap = 1.2 + 1.2 * sin(UV.x * 0.13 + TIME * 1.6) + 0.6 * sin(UV.x * 0.37 - TIME * 2.3);
			float band = smoothstep(-lap - 1.5 - aa, -lap - 1.5 + aa, d) * (1.0 - smoothstep(1.5 - aa, 1.5 + aa, d));
			art = vec4(foam_colour.rgb * light_of_level, band * foam_colour.a * (1.0 - data.b));
		}
		float shadow = data.g * (1.0 - smoothstep(0.0, foot_shadow_width, d)) * step(0.0, d) * (art_only ? 0.0 : 1.0);
		float out_alpha = art.a + shadow * (1.0 - art.a);
		vec3 out_rgb = out_alpha > 0.0 ? art.rgb * art.a / out_alpha : vec3(0.0);
		COLOR = vec4(out_rgb, out_alpha);
	} else if (kind < 0.65) {
		COLOR = vec4(texture(low_ground, world / ground_period).rgb * light_of_level, 1.0);
	} else if (kind < 0.8) {
		COLOR = vec4(level_lit(texture(top_ground, world / ground_period).rgb, light_of_level), 1.0);
	} else {
		float d = UV.y;
		float aa = max(fwidth(d), 0.01);
		// The lip (`lip_of`): the top's lip strip all round where its ground has one, else plain clumps; a
		// back edge's clumps lie on the ground behind, as big as a front's (no wall to hang over).
		// (lifted as the top's own ground is, elevation_top_light.gdshader: the lip multiplies it by
		// the light again)
		vec3 top = level_lit(texture(top_ground, world / ground_period).rgb, light_of_level) / max(light_of_level, 0.001);
		vec4 lip;
		if (has_lip_strip > 0.5) {
			// The top's lip strip all round its edge, read from its own place every `ledge_period`.
			vec3 p = ledge_period_of(UV.x, 1.7);
			float w = lip_strip_size.x * 0.5;
			lip = blend_art(lip_of(top, 1.0, UV.x + p.x * w, d, data.g, data.b, light_of_level, aa),
					lip_of(top, 1.0, UV.x + p.y * w, d, data.g, data.b, light_of_level, aa), ragged(p.z, UV.x, d));
		} else {
			lip = lip_of(top, 0.0, UV.x, d, data.g, data.b, light_of_level, aa);
		}
		COLOR = lip;
	}
}
