// A cliff of any size from a kit painting (game/world/cliffs/cliff_builder.gd): each cell of the
// cliff shows the kit cell col_map[x], row_map[y]; where two neighbouring cells do not follow each
// other in the painting, the picture crossfades over BLEND of a cell on each side of the line.
shader_type canvas_item;

uniform sampler2D kit : filter_linear, repeat_disable;
uniform vec2 kit_cells = vec2(18.0);
uniform vec2 size = vec2(18.0);
uniform float cell = 64.0;
uniform int col_map[64];
uniform int row_map[64];
uniform sampler2D behind_map : filter_nearest;
uniform bool behind_only = false;
uniform float behind_frac = 0.5;

const float BLEND = 0.2;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

vec4 at(float kx, float ky) {
	return texture(kit, vec2(kx, ky) / kit_cells);
}

// The picture at kit row position ky (in kit cells), blended across the column lines.
vec4 across(int cx, float fx, float ky) {
	vec4 c = at(float(col_map[cx]) + fx, ky);
	if (fx < BLEND && cx > 0) {
		vec4 other = at(float(col_map[cx - 1]) + 1.0 + fx, ky);
		c = mix(c, other, 0.5 - 0.5 * fx / BLEND);
	} else if (fx > 1.0 - BLEND && cx < int(size.x) - 1) {
		vec4 other = at(float(col_map[cx + 1]) - 1.0 + fx, ky);
		c = mix(c, other, 0.5 * (fx - (1.0 - BLEND)) / BLEND);
	}
	return c;
}

void fragment() {
	vec2 p = local_px / cell;
	int cx = clamp(int(floor(p.x)), 0, int(size.x) - 1);
	int cy = clamp(int(floor(p.y)), 0, int(size.y) - 1);
	float fx = p.x - float(cx);
	float fy = p.y - float(cy);
	if (behind_only && (texelFetch(behind_map, ivec2(cx, cy), 0).r < 0.5 || fy >= behind_frac)) {
		// The behind overlay: only the north band of the top's north-side cells.
		discard;
	}
	vec4 c = across(cx, fx, float(row_map[cy]) + fy);
	if (fy < BLEND && cy > 0) {
		vec4 other = across(cx, fx, float(row_map[cy - 1]) + 1.0 + fy);
		c = mix(c, other, 0.5 - 0.5 * fy / BLEND);
	} else if (fy > 1.0 - BLEND && cy < int(size.y) - 1) {
		vec4 other = across(cx, fx, float(row_map[cy + 1]) - 1.0 + fy);
		c = mix(c, other, 0.5 * (fy - (1.0 - BLEND)) / BLEND);
	}
	COLOR = c;
}
