// Solid-colour hit flash (Phaser setTintFill). Combat spec 11.
// flash_amount 0 = normal sprite; 1 = every opaque pixel becomes flash_color (alpha kept).
// Applied as a per-instance ShaderMaterial by res://game/feel/hit_flash.gd; leaves modulate /
// self_modulate free (authored tint stays in self_modulate, which is already in COLOR).
// Owner: combat builder.
shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 0.435, 0.533, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(tex.rgb, flash_color.rgb, flash_amount), tex.a);
}
