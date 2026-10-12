// The shadows raised ground casts (docs/godot/ELEVATION.md), shared by the shaders that draw what
// they fall on: the ground near every drop (elevation_cast_shadow.gdshader) and a ramp's slope
// (elevation_ramp.gdshader, which covers that ground). The light comes from the upper left, high:
// shadows fall to the right and a little down, as long as `shadow_units` per level of height. A
// pixel looks back towards the light along three rays through the depth map (elevation_occlusion.gd,
// in the space of the Elevation node) for ground high enough to shade it.

uniform sampler2D elevation_depth : filter_nearest, repeat_disable;
// The depth map's rect in the ground layer's space: origin xy, size zw.
uniform vec4 depth_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float shadow_units = 20.0;
uniform float strength = 0.36;
// Where shadows fall (screen, unit length).
uniform vec2 fall = vec2(0.94, 0.34);

const int SAMPLES = 12;
const float STEP = 6.0;

// Height (levels) of what is drawn at `p`: walls count as their top, structures (stairs) and a
// ramp's slope and skirt (b = 0.875, elevation_ramp.gd: its bottom level + 8 · g) as their own
// height, so the shadow beside a ramp is as long as the slope is high there.
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
	if (texel.b > 0.8125 && texel.b < 0.9375) {
		return top + texel.g * 8.0;
	}
	return texel.b < 0.75 ? top - (texel.g * 512.0 - 128.0) / 64.0 : top;
}

// How much the ground along `dir` (towards the light) shades `at` (of height `level`), 0..1.
float shade_along(vec2 at, float level, vec2 dir) {
	float shade = 0.0;
	for (int i = 1; i <= SAMPLES; i++) {
		float s = float(i) * STEP;
		float reach = (height_at(at - dir * s) - level) * shadow_units;
		shade = max(shade, smoothstep(s - 4.0, s + 6.0, reach));
	}
	return shade;
}

// The cast shadow at `at` on ground of height `level`, 0..1: three rays spread around the light's
// direction soften its sides.
float cast_shade(vec2 at, float level) {
	vec2 side = vec2(-fall.y, fall.x) * 0.28;
	return (shade_along(at, level, normalize(fall + side)) + shade_along(at, level, fall) + shade_along(at, level, normalize(fall - side))) / 3.0;
}
