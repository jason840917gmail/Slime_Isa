// The player's Visual material: the Gulp form skins plus the hit flash (abilities spec 11.3,
// owner decision 2026-10-05: a shader skin instead of redrawn sheets).
// Phaser re-textured its old side-view sheet with painted skins (slime-form-heavy / -sticky); the
// three-quarter top-down sheet has no such sheets, so this paints the form over the slime's own
// frames: only the green body (by hue and saturation) changes, keeping the outline, the eyes, the
// highlights and the shading (the pattern is lit by the frame's own brightness). The pattern is
// laid out in the sprite's local pixels, so it sticks to the body from frame to frame.
//   skin 0: none; 1: Heavy (grey cobbles); 2: Sticky (cream silk strands); 3: Frog (tree-frog
//   green with darker spots and a pale belly, the Frog badge's colours).
// Swimming (the Frog form in deep water) hides the art under a waterline: `waterline` cell pixels
// above the frame's baseline stay above water, with a thin foam line; the player lowers the art by
// as much, so the waterline sits on its feet (game/player/gulp/player_swimming.gd).
// The hit flash keeps hit_flash.gdshader's parameters (HitFlash finds this material by its
// `hit_flash` meta), so a flash works over a skin. Like hit_flash.gdshader it hides the slime
// behind higher ground, as a silhouette (elevation_occlusion.gdshaderinc).
// Owner: abilities.
shader_type canvas_item;

#include "res://game/world/elevation/elevation_occlusion.gdshaderinc"

uniform vec4 flash_color : source_color = vec4(1.0, 0.435, 0.533, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform int skin = 0;
// Cobble size in texture pixels (the slime is 186 px wide in its frames: about 5 stones across).
uniform float stone_size = 34.0;
// Strand spacing in texture pixels.
uniform float strand_size = 16.0;
// Frog spot spacing in texture pixels.
uniform float spot_size = 30.0;
// Swimming: how much of the art stays above water, in cell pixels above the baseline (0: no water).
uniform float waterline = 0.0;
// The slime sheets' cells and the baseline the slime stands on (docs/assets/slime-sheet-guide.md).
const float CELL_PX = 256.0;
const float BASELINE_PX = 251.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
	elevation_world = elevation_world_position(VERTEX, MODEL_MATRIX);
}

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.3))) * 9134.17);
}

// Grey cobbles: Voronoi stones with dark joints, each stone its own tone, lit from the top left.
vec3 rock(vec2 p) {
	vec2 g = p / stone_size;
	vec2 cell = floor(g);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 best_cell = cell;
	vec2 best_offset = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 point = c + 0.15 + 0.7 * hash2(c);
			vec2 offset = g - point;
			float d = length(offset);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				best_cell = c;
				best_offset = offset;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float tone = 0.48 + 0.2 * hash1(best_cell);
	vec3 stone = vec3(tone * 0.97, tone, tone * 1.04);
	// Rounded stones: lighter toward the top left of each one, darker toward the joints.
	float dome = clamp(1.0 - f1 * 1.6, 0.0, 1.0);
	stone *= 0.78 + 0.32 * dome + 0.18 * clamp(-(best_offset.x + best_offset.y), -1.0, 1.0);
	float joint = smoothstep(0.02, 0.09, f2 - f1);
	return mix(vec3(0.16, 0.17, 0.19), stone, joint);
}

// Cream silk: two crossing families of wavy strands over a warm base, like a wrapped web.
vec3 silk(vec2 p) {
	vec2 q = p / strand_size;
	float wave_a = sin(q.y * 0.9 + sin(q.x * 0.35) * 1.7);
	float wave_b = sin(q.x * 0.8 - sin(q.y * 0.4) * 1.5);
	float strand_a = pow(abs(sin((q.x + q.y * 0.55 + wave_a * 0.6) * 1.57)), 9.0);
	float strand_b = pow(abs(sin((q.y - q.x * 0.5 + wave_b * 0.6) * 1.57)), 11.0);
	float strands = clamp(strand_a + strand_b * 0.8, 0.0, 1.0);
	vec3 base = vec3(0.86, 0.81, 0.69);
	return mix(base * 0.88, vec3(1.0, 0.98, 0.93), strands);
}

// Frog: a vivid tree-frog green with darker rounded spots and a pale creamy belly toward the bottom
// of the frame (sprite-local y grows downward; the slime stands near +123).
vec3 frog(vec2 p) {
	vec2 g = p / spot_size;
	vec2 cell = floor(g);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 point = c + 0.2 + 0.6 * hash2(c);
			float radius = 0.16 + 0.14 * hash1(c);
			nearest = min(nearest, length(g - point) / radius);
		}
	}
	float spot = 1.0 - smoothstep(0.8, 1.05, nearest);
	vec3 green = mix(vec3(0.47, 0.74, 0.20), vec3(0.17, 0.39, 0.13), spot);
	float belly = smoothstep(45.0, 108.0, p.y) * (1.0 - 0.6 * smoothstep(0.0, 1.0, abs(p.x) / 95.0));
	return mix(green, vec3(0.90, 0.88, 0.58), belly * 0.75 * (1.0 - 0.8 * spot));
}

void fragment() {
	// The art's own colour decides what is body; COLOR already holds texture x modulate (Godot 4).
	vec4 raw = texture(TEXTURE, UV);
	vec4 tex = COLOR;
	vec3 c = tex.rgb;
	if (skin > 0) {
		vec3 hsv = rgb2hsv(raw.rgb);
		// The slime's body is yellow-green (hue about 0.2-0.3) and saturated; the eyes, the
		// highlights and the dark outline are not.
		float hue_match = 1.0 - smoothstep(0.07, 0.13, abs(hsv.x - 0.24));
		float body = hue_match * smoothstep(0.25, 0.42, hsv.y) * smoothstep(0.12, 0.25, hsv.z);
		float lum = dot(raw.rgb, vec3(0.299, 0.587, 0.114));
		vec3 pattern = skin == 1 ? rock(local_pos) : (skin == 2 ? silk(local_pos) : frog(local_pos));
		float light = skin == 1 ? 0.35 + 1.15 * lum : (skin == 2 ? 0.55 + 0.75 * lum : 0.45 + 0.95 * lum);
		c = mix(c, pattern * light, body);
	}
	c = mix(c, flash_color.rgb, flash_amount);
	float alpha = tex.a;
	if (waterline > 0.0) {
		float cell_y = mod(UV.y * float(textureSize(TEXTURE, 0).y), CELL_PX);
		float cut = BASELINE_PX - waterline;
		float under = smoothstep(cut - 1.5, cut + 1.5, cell_y);
		float foam = (1.0 - smoothstep(0.0, 4.0, abs(cell_y - (cut - 2.0)))) * (1.0 - under);
		c = mix(c, vec3(0.86, 0.97, 1.0), foam * 0.6);
		alpha *= 1.0 - under;
	}
	COLOR = elevation_occlude(vec4(c, alpha));
}
