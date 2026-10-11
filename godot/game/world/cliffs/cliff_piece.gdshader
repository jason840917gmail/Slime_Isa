// The behind overlay of a cliff piece (game/world/cliffs/cliff_piece.gd): the painting, kept only on
// the north band (behind_frac of a cell) of the top's north-side cells (behind_map, one texel a cell).
shader_type canvas_item;

uniform sampler2D behind_map : filter_nearest;
uniform vec2 cells = vec2(1.0);
uniform float behind_frac = 0.5;

void fragment() {
	vec2 p = UV * cells;
	vec2 f = fract(p);
	if (texelFetch(behind_map, ivec2(floor(p)), 0).r < 0.5 || f.y >= behind_frac) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
