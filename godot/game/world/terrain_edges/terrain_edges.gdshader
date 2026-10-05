shader_type canvas_item;

// Edge overlay for hand-made terrain transitions (docs/godot/TERRAIN_LAB.md).
// The overlay is a dual grid: each tile sits on a corner shared by four ground cells and
// joins the upper ground (e.g. snow) to the lower one (e.g. sand). The tiles are art: alpha
// is where the upper ground covers, colour is the painted rim, and `rim_weight` (same
// atlas layout) says where that painted rim shows. Both grounds are drawn from their own
// sheets in world space, exactly like the ground layer (ground_world.gdshader), so the
// overlay meets the plain cells around it without a seam. It is opaque: where the tile
// rounds a corner away it shows the lower ground over the upper cell.

// The upper and lower grounds' seamless sheets (19 x 19 cells of 128 px).
uniform sampler2D upper_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D lower_texture : source_color, repeat_enable, filter_linear_mipmap;
// Rim weights, laid out exactly like the edge tile atlas (1 = painted rim, 0 = ground).
uniform sampler2D rim_weight : filter_linear;
// World units covered by one repeat of the sheets (19 cells x 64 units).
uniform float ground_period = 1216.0;

varying vec2 world_position;
// Vertex colour and modulate (fragment COLOR already includes the texture, so keep this apart).
varying vec4 tint;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	tint = COLOR;
}

void fragment() {
	vec4 tile = texture(TEXTURE, UV);
	float rim = texture(rim_weight, UV).r;
	vec2 uv = world_position / ground_period;
	vec3 upper = mix(texture(upper_texture, uv).rgb, tile.rgb, rim);
	vec3 lower = texture(lower_texture, uv).rgb;
	COLOR = vec4(mix(lower, upper, tile.a), 1.0) * tint;
}
