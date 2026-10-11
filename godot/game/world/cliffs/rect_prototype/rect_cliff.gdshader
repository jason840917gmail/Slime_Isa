// Independent rectangular art proof. Preserve corners, turf lip and foot;
// extend grass and rock independently. No crossfade across silhouette seams.
shader_type canvas_item;
uniform vec2 output_size = vec2(768.0, 384.0);
uniform float top_depth = 256.0;

float remap(float v, float a, float b, float c, float d) {
	return mix(c, d, clamp((v - a) / max(b - a, 0.001), 0.0, 1.0));
}

// An odd number of reflected runs keeps both end connections intact.
// Long grass tops keep tuft scale instead of pulling it into long streaks.
float grass_y(float y) {
	float length = max(top_depth - 32.0, 1.0);
	float runs = max(1.0, floor(length / 184.0 / 2.0) * 2.0 + 1.0);
	float t = (y - 32.0) / length * runs;
	float reflected = 1.0 - abs(mod(t, 2.0) - 1.0);
	return mix(192.0, 560.0, reflected);
}

void fragment() {
	vec2 p = UV * output_size;
	float x;
	if (p.x < 80.0) x = 54.0 + p.x * 2.0;
	else if (p.x > output_size.x - 80.0) x = 1482.0 - (output_size.x - p.x) * 2.0;
	else x = remap(p.x, 80.0, output_size.x - 80.0, 214.0, 1322.0);
	float y;
	if (p.y < 32.0) y = 128.0 + p.y * 2.0;
	else if (p.y < top_depth) y = grass_y(p.y);
	else if (p.y < top_depth + 24.0) y = 560.0 + (p.y - top_depth) * 2.0;
	else if (p.y > output_size.y - 32.0) y = 896.0 - (output_size.y - p.y) * 2.0;
	else y = remap(p.y, top_depth + 24.0, output_size.y - 32.0, 608.0, 832.0);
	COLOR = texture(TEXTURE, vec2(x / 1536.0, y / 1024.0));
}
