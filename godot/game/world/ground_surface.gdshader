// The ground at 128 px per cell (game/world/ground_surface.gd): each pixel finds its cell in
// `cell_map` (one texel per cell: the slot of the cell's sharp sheet, 255 = none) and draws that
// sheet in world space, wrapping every `texture_period` units as the 64 px tiles do (sheet-wrap).
shader_type canvas_item;

uniform sampler2D cell_map : filter_nearest;
uniform float tile_size = 64.0;
uniform float texture_period = 1216.0;
uniform sampler2D sheet0 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet3 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet4 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet5 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet6 : filter_linear_mipmap, repeat_enable;
uniform sampler2D sheet7 : filter_linear_mipmap, repeat_enable;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	ivec2 cell = ivec2(floor(local_px / tile_size));
	int slot = int(round(texelFetch(cell_map, cell, 0).r * 255.0));
	vec2 uv = local_px / texture_period;
	vec4 colour = vec4(0.0);
	if (slot == 0) colour = vec4(texture(sheet0, uv).rgb, 1.0);
	else if (slot == 1) colour = vec4(texture(sheet1, uv).rgb, 1.0);
	else if (slot == 2) colour = vec4(texture(sheet2, uv).rgb, 1.0);
	else if (slot == 3) colour = vec4(texture(sheet3, uv).rgb, 1.0);
	else if (slot == 4) colour = vec4(texture(sheet4, uv).rgb, 1.0);
	else if (slot == 5) colour = vec4(texture(sheet5, uv).rgb, 1.0);
	else if (slot == 6) colour = vec4(texture(sheet6, uv).rgb, 1.0);
	else if (slot == 7) colour = vec4(texture(sheet7, uv).rgb, 1.0);
	COLOR = colour;
}
