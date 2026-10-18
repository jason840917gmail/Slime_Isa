shader_type canvas_item;
render_mode unshaded;
uniform vec2 outline[64];
uniform int point_count = 0;
uniform vec4 wall_frames[16];
uniform int frame_count = 0;
uniform vec4 darkness : source_color = vec4(0.025, 0.032, 0.048, 1.0);
void fragment() {
	bool inside = false;
	int previous = point_count - 1;
	for (int i = 0; i < 64; i++) {
		if (i >= point_count) { break; }
		vec2 a = outline[i];
		vec2 b = outline[previous];
		if ((a.y > UV.y) != (b.y > UV.y)) {
			float crossing = (b.x - a.x) * (UV.y - a.y) / (b.y - a.y) + a.x;
			if (UV.x < crossing) { inside = !inside; }
		}
		previous = i;
	}
	for (int i = 0; i < 16; i++) {
		if (i >= frame_count) { break; }
		vec4 box = wall_frames[i];
		if (UV.x >= box.x && UV.y >= box.y && UV.x <= box.z && UV.y <= box.w) { inside = true; }
	}
	COLOR = inside ? vec4(0.0) : darkness;
}
