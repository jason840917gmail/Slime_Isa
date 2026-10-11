// A cliff of any shape (game/world/cliffs/cliff_shape.gd): each cell shows the kit cell stored in
// cell_map (r, g = kit cell, b = kit index; a = 0: nothing), and where two neighbouring cells do not follow each
// other in the painting the picture crossfades over BLEND of a cell on each side of the line.
shader_type canvas_item;

uniform sampler2D kit0 : filter_linear, repeat_disable;
uniform sampler2D kit1 : filter_linear, repeat_disable;
uniform sampler2D kit2 : filter_linear, repeat_disable;
uniform sampler2D kit3 : filter_linear, repeat_disable;
uniform sampler2D cell_map : filter_nearest;
uniform vec2 kit_cells[4];
uniform vec2 size = vec2(1.0);
uniform float cell = 64.0;
uniform vec2 origin = vec2(0.0);
uniform sampler2D behind_map : filter_nearest;
uniform bool behind_only = false;
uniform float behind_frac = 0.5;

const float BLEND = 0.2;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

// The picture of grid cell c at position f inside it (f may run past 0..1 into the next cell of
// the painting); transparent where the cell shows nothing.
vec4 piece(ivec2 c, vec2 f) {
	if (c.x < 0 || c.y < 0 || c.x >= int(size.x) || c.y >= int(size.y)) {
		return vec4(0.0);
	}
	vec4 m = texelFetch(cell_map, c, 0);
	if (m.a < 0.5) {
		return vec4(0.0);
	}
	int index = int(m.b * 255.0 + 0.5);
	vec2 uv = (floor(m.rg * 255.0 + 0.5) + f) / kit_cells[index];
	if (index == 1) return texture(kit1, uv);
	if (index == 2) return texture(kit2, uv);
	if (index == 3) return texture(kit3, uv);
	return texture(kit0, uv);
}

vec4 across(ivec2 c, vec2 f) {
	vec4 col = piece(c, f);
	if (f.x < BLEND) {
		col = mix(col, piece(c + ivec2(-1, 0), f + vec2(1.0, 0.0)), 0.5 - 0.5 * f.x / BLEND);
	} else if (f.x > 1.0 - BLEND) {
		col = mix(col, piece(c + ivec2(1, 0), f - vec2(1.0, 0.0)), 0.5 * (f.x - (1.0 - BLEND)) / BLEND);
	}
	return col;
}

void fragment() {
	vec2 p = local_px / cell;
	vec2 base = floor(p);
	ivec2 c = ivec2(base) - ivec2(origin);
	vec2 f = p - base;
	if (behind_only) {
		// The behind overlay: only the north band of a top's north-side cells.
		bool inside = c.x >= 0 && c.y >= 0 && c.x < int(size.x) && c.y < int(size.y);
		if (!inside || texelFetch(behind_map, c, 0).r < 0.5 || f.y >= behind_frac) {
			discard;
		}
	}
	vec4 col = across(c, f);
	if (f.y < BLEND) {
		col = mix(col, across(c + ivec2(0, -1), f + vec2(0.0, 1.0)), 0.5 - 0.5 * f.y / BLEND);
	} else if (f.y > 1.0 - BLEND) {
		col = mix(col, across(c + ivec2(0, 1), f - vec2(0.0, 1.0)), 0.5 * (f.y - (1.0 - BLEND)) / BLEND);
	}
	COLOR = col;
}
