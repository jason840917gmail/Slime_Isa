// Light by height (game/world/ground_shade.gd): multiplies the ground by `low_tint` where it is
// not raised and by `top_tint` on the raised tops. `height_map` has one texel per cell (1 =
// raised) and is sampled with linear filtering; the light turns inside a top's border cells, so it
// never spills onto the low ground. The tints stay warm: the art style has no cold shadows (docs/assets/visual-style-guide.md).
shader_type canvas_item;
render_mode blend_mul;

uniform sampler2D height_map : filter_linear;
uniform vec2 grid_size = vec2(1.0);
uniform float tile_size = 64.0;
uniform vec3 low_tint : source_color = vec3(0.80, 0.77, 0.72);
uniform vec3 top_tint : source_color = vec3(1.0, 1.0, 1.0);

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float high = texture(height_map, local_px / tile_size / grid_size).r;
	COLOR = vec4(mix(low_tint, top_tint, smoothstep(0.5, 0.95, high)), 1.0);
}
