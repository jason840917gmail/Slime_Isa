shader_type canvas_item;

// One ground's hand-made edge tiles (docs/godot/TERRAIN_LAB.md), drawn by TerrainEdges on a dual
// grid over the ground layer. The tile is art: alpha is where this ground covers, colour its
// painted rim, and `rim_weight` (same atlas layout) where that rim shows. Everywhere else the
// ground's own sheet is drawn at the texel the ground layer shows there (sheet-wrap: the pixel's
// position mod 1216), so an edge tile meets the plain cells around it without a seam. Uncovered
// pixels are transparent: the ground below shows (drawn by the layer under this one).

// This ground's sheet, as the ground layer uses it (19 x 19 cells of 64 px).
uniform sampler2D ground_texture : source_color, repeat_enable, filter_linear;
// Rim weights, laid out exactly like the edge tile atlas (1 = painted rim, 0 = ground).
uniform sampler2D rim_weight : filter_linear;
// World units covered by one repeat of the sheet (19 cells x 64 units).
uniform float ground_period = 1216.0;
// The ground layer's global position: the sheet is anchored to its cell (0, 0).
uniform vec2 ground_origin = vec2(0.0);

varying vec2 layer_px;
// Vertex colour and modulate (fragment COLOR already includes the texture, so keep this apart).
varying vec4 tint;

void vertex() {
	// TileMapLayer draws in quadrants with their own origins: go through world space.
	layer_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
	tint = COLOR;
}

void fragment() {
	vec4 tile = texture(TEXTURE, UV);
	float rim = texture(rim_weight, UV).r;
	vec3 ground = texture(ground_texture, layer_px / ground_period).rgb;
	COLOR = vec4(mix(ground, tile.rgb, rim), tile.a) * tint;
}
