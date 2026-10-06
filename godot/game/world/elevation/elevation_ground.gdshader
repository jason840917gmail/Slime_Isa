shader_type canvas_item;

// A chamfered corner triangle that takes the ground across the corner (docs/godot/ELEVATION.md):
// that ground's sheet in world space, as the ground layer draws it (sheet-wrap), so it joins the
// plain cells around it without a seam.

uniform sampler2D ground_texture : source_color, repeat_enable, filter_linear;
uniform float ground_period = 1216.0;
uniform vec2 ground_origin = vec2(0.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ground_origin;
}

void fragment() {
	COLOR = vec4(texture(ground_texture, world / ground_period).rgb, 1.0);
}
