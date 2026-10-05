shader_type canvas_item;

// A ground "swatch" tile (docs/godot/TERRAIN_LAB.md): one tile per ground, drawn from the
// ground's seamless sheet in world space. Same picture as Phaser's sheet-wrap frames
// (cell x mod 19, y mod 19), but the painter picks one tile instead of the right frame.

uniform sampler2D ground_texture : source_color, repeat_enable, filter_linear_mipmap;
// World units covered by one repeat of the sheet (19 cells x 64 units).
uniform float ground_period = 1216.0;

varying vec2 world_position;
varying vec4 tint;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	tint = COLOR;
}

void fragment() {
	COLOR = texture(ground_texture, world_position / ground_period) * tint;
}
