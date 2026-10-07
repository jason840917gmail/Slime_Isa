shader_type canvas_item;
render_mode blend_add;

// The light caught by the top rims of raised ground (docs/godot/ELEVATION.md): Elevation draws a
// thin strip along every rim without a wall, its vertex colour fading from a warm light at the edge
// to nothing; added to what is below.

void fragment() {
	COLOR = vec4(COLOR.rgb * COLOR.a, 1.0);
}
