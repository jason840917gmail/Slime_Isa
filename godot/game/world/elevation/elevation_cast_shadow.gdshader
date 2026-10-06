shader_type canvas_item;
render_mode blend_mul;

// The shadows raised ground casts on lower ground (docs/godot/ELEVATION.md). The light comes from
// the upper left, high: shadows fall to the right and a little down, as long as SHADOW_UNITS per
// level of height, so a level-3 hill casts three times the shadow of a level-1 one. North and
// west of a hill there is none; along a south wall's foot a thin contact band; inside a hole the
// rim casts onto the floor along its west side. Elevation draws this over the ground near every
// drop (vertex colour a = the ground's level) before the walls; each pixel looks back towards the
// light through the depth map (elevation_occlusion.gd, ground-layer space) for ground high enough
// to shade it. Soft at its far end and sides.

uniform sampler2D elevation_depth : filter_nearest, repeat_disable;
// The depth map's rect in the ground layer's space: origin xy, size zw.
uniform vec4 depth_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float shadow_units = 20.0;
uniform float strength = 0.36;
// Where shadows fall (screen, unit length).
uniform vec2 fall = vec2(0.94, 0.34);

const int SAMPLES = 12;
const float STEP = 6.0;

varying vec2 local;
varying float level;

void vertex() {
	local = VERTEX;
	level = COLOR.a * 8.0 - 4.0;
}

// Height (levels) of what is drawn at `p`: walls count as their top, structures (stairs) as their
// own height.
float height_at(vec2 p) {
	vec2 uv = (p - depth_rect.xy) / depth_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec4 texel = texture(elevation_depth, uv);
	if (texel.b < 0.25) {
		return 0.0;
	}
	float top = floor(texel.r * 8.0 - 4.0 + 0.5);
	return texel.b < 0.75 ? top - (texel.g * 512.0 - 128.0) / 64.0 : top;
}

// How much the ground along `dir` (towards the light) shades this pixel, 0..1.
float shade_along(vec2 dir) {
	float shade = 0.0;
	for (int i = 1; i <= SAMPLES; i++) {
		float s = float(i) * STEP;
		float reach = (height_at(local - dir * s) - level) * shadow_units;
		shade = max(shade, smoothstep(s - 4.0, s + 6.0, reach));
	}
	return shade;
}

void fragment() {
	// Three rays spread around the light's direction soften the shadow's sides.
	vec2 side = vec2(-fall.y, fall.x) * 0.28;
	float shade = (shade_along(normalize(fall + side)) + shade_along(fall) + shade_along(normalize(fall - side))) / 3.0;
	COLOR = vec4(vec3(1.0 - strength * shade), 1.0);
}
