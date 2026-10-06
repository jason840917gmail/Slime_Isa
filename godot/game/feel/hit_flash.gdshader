// Solid-colour hit flash (Phaser setTintFill). Combat spec 11.
// flash_amount 0 = normal sprite; 1 = every opaque pixel becomes flash_color (alpha kept).
// Applied as a per-instance ShaderMaterial by res://game/feel/hit_flash.gd; leaves modulate /
// self_modulate free (authored tint stays in self_modulate, which is already in COLOR).
// It also hides the body behind higher ground (elevation_occlusion.gdshaderinc; inert in worlds
// without elevation).
// Owner: combat builder.
shader_type canvas_item;

#include "res://game/world/elevation/elevation_occlusion.gdshaderinc"

uniform vec4 flash_color : source_color = vec4(1.0, 0.435, 0.533, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	elevation_world = elevation_world_position(VERTEX, MODEL_MATRIX);
}

void fragment() {
	// COLOR already holds the texture times the modulate (Godot 4); multiplying by the texture
	// again squared every colour (sprites drew darker and more saturated than their art).
	vec4 tex = COLOR;
	COLOR = elevation_occlude(vec4(mix(tex.rgb, flash_color.rgb, flash_amount), tex.a));
}
