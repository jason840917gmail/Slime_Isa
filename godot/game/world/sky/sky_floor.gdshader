// The sky floor's look (sky_floor.gd, docs/godot/SKY_FLOOR.md), in three kinds of draw (`sky_mode`):
// - 1, the backdrop: the elevation's own mesh of the holes' floors, drawn in its Shade (under every
//   wall, rim and top), kept to the floors in the sky floor's `area` at `sky_level` or lower: up to
//   four picture layers that tile, far to near, each moved with the camera by its scroll factor and
//   drifting on its own, and over them the cloud bank out over the sky from the islands' silhouettes;
// - 0, the lip: each of the elevation's wall meshes drawn again over itself. On its walls and corner
//   stones: the bank up the bottom `bank_cover` of its height (its vertex colour's a: the height in
//   levels, elevation_sides.gd), thinning out up a side wall's strip (seen from the side, its bottom
//   is its lower end), and the sky itself where a wall piece hangs out over the open sky (a side
//   wall's slanted start). On its feet (not drawn in the sky): the sky past the foot line, as the
//   backdrop draws it, so the wall's wobbling foot meets the sky without a gap;
// - 2, without an elevation drawing to sit in: both from the field alone, cut round its silhouettes.
shader_type canvas_item;
render_mode unshaded;

// The field (sky_floor.gd `_build_field`), one texel per `field_texel` world units from
// `field_origin`: R the distance up a side wall's strip from its foot (as G; 1 off a strip), G the
// distance out from
// the islands' silhouettes, negative up a wall from its foot (`field_range` units each way, 0.5 at
// the silhouette's edge), B on a sky cell its level ((level + 8) / 16; 0 elsewhere), A the distance
// to the nearest top (`to_land_range`).
uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 field_origin;
uniform vec2 field_size = vec2(1.0);
uniform float field_texel = 16.0;
uniform float field_range = 256.0;
uniform float to_land_range = 64.0;
// The world point at the middle of the screen.
uniform vec2 camera;
// 0: the lip on a wall mesh; 1: the backdrop (sky and bank, under the walls); 2: both from the field
// alone, cut round the islands' silhouettes (no elevation drawing to sit in).
uniform int sky_mode = 2;
// The sky floor's area (global x, y, width, height): only its cells are sky.
uniform vec4 area = vec4(0.0);

// The elevation's depth map (elevation_occlusion.gd, elevation_occlusion.gdshaderinc): what the
// elevation draws at each point, its level and how far below its wall's top edge: under a wall the
// backdrop shows rock by it, and the lip never covers a top and draws the sky where a wall piece
// hangs out over the open sky. `depth_rect` origin xy, size zw (zw 0: none).
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec4 depth_rect = vec4(0.0);

uniform sampler2D layer1 : filter_linear, repeat_enable;
uniform sampler2D layer2 : filter_linear, repeat_enable;
uniform sampler2D layer3 : filter_linear, repeat_enable;
uniform sampler2D layer4 : filter_linear, repeat_enable;
// Per layer: xy its drift (units a second), z its scroll factor, w 1 when it has a picture.
uniform vec4 layer_motion[4];
// The world units one copy of its picture covers.
uniform vec2 layer_span[4];
uniform vec4 layer_tint[4];
// A colour mixed over it, alpha how much.
uniform vec4 layer_haze[4];
uniform float layer_opacity[4];
// Under every layer (shows where the first layer is see-through or off).
uniform vec3 base_colour = vec3(0.42, 0.62, 0.72);

uniform sampler2D bank : filter_linear, repeat_enable;
uniform bool bank_on = false;
uniform vec2 bank_span = vec2(512.0);
uniform vec2 bank_drift;
uniform vec4 bank_tint = vec4(1.0);
uniform vec4 bank_shade = vec4(0.62, 0.6, 0.78, 0.3);
// The bank picture's luminance: its mean and spread, which the puffs push the edges by.
uniform vec2 bank_lum = vec2(0.8, 0.08);
uniform float bank_cover = 20.0;
uniform float bank_reach = 40.0;
uniform float bank_soft = 8.0;
uniform float bank_puff = 16.0;
uniform float rim_soft = 4.0;

// The backdrop: the Shade's floors at this level or lower are sky (their level in the vertex colour's
// r, (level + 4) / 8, elevation.gd `_level_channel`): a floor triangle the elevation cuts into an
// island's own cell at a 45° corner is sky too.
uniform float sky_level = -2.0;
// The rock a crack in a wall's meshes shows.
const vec3 CRACK = vec3(0.2, 0.17, 0.14);
// How far up a wall from its foot (world units, by the depth map) the backdrop shows that rock, and
// how far below the point the map must still hold a wall. By its foot the backdrop stays sky and bank:
// a wall's drawn foot wobbles a few units round the depth map's straight one, and the map, read
// smoothly, passes through a wall's values along a foot that lands on another island's back rim; with
// no foot piece over them (a wall in the sky has none) the rock showed there as dark slivers along
// the foot line.
const float CRACK_FOOT = 8.0;
// How far past a wall's foot line (world units) the lip lays the sky: over the foot's wobble.
const float FOOT_FILL = 8.0;
// The depth map's word that a point is a top counts within this far of a top by the field (world
// units). Read smoothly, the map also passes through a top's values between a wall's foot and the thin
// core it lays past a back rim (a wall whose foot lands on another island's back edge): a line along
// that foot that is no top.
const float TOP_NEAR = 12.0;

varying vec2 world;
// The backdrop: a floor triangle's level (vertex colour r). The lip: the wall's height there in
// levels (vertex colour a). Both (level + 4) / 8 (elevation.gd `_level_channel`).
varying float tri_level;
varying float wall_height;
// The lip: the kind of wall piece (vertex colour r, elevation_sides.gdshader): 0 … 0.2 a wall (front …
// side), 0.3 a corner stone, 0.46 … 0.54 a foot (not drawn where a wall hangs into the sky,
// elevation.gd SKY_GROUND: the lip fills what it leaves past the foot line). The corner fills (0.6,
// 0.7) and the top edge (1) take no lip, nor does a back edge's foot (b 1: it lies on the top's ground
// at a cut corner, under no wall).
varying float piece;
varying float piece_b;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	tri_level = COLOR.r * 8.0 - 4.0;
	wall_height = COLOR.a * 8.0 - 4.0;
	piece = COLOR.r;
	piece_b = COLOR.b;
}

vec4 layer_colour(sampler2D picture, int i, vec2 at, float t) {
	vec4 motion = layer_motion[i];
	vec2 p = at - camera * (1.0 - motion.z) - motion.xy * t;
	vec4 c = texture(picture, p / layer_span[i]);
	c.rgb *= layer_tint[i].rgb;
	c.rgb = mix(c.rgb, layer_haze[i].rgb, layer_haze[i].a);
	c.a *= layer_opacity[i] * layer_tint[i].a * motion.w;
	return c;
}

// The bank's cover and colour at `at`: `up` how far up a wall from its foot (0 off a wall), `away` how
// far out over the sky from the islands' silhouettes (0 on a wall). The backdrop and the lip work it
// out alike, so the lip's bank over the backdrop's matches it wherever the lip ends.
vec4 bank_at(vec2 at, float up, float away, float fade) {
	vec4 b = texture(bank, (at - bank_drift * TIME) / bank_span);
	float lum = dot(b.rgb, vec3(0.299, 0.587, 0.114));
	float puff = clamp((lum - bank_lum.x) / max(bank_lum.y * 2.0, 0.001), -1.0, 1.0) * bank_puff;
	// up a wall: `bank_cover` from its foot; out over the sky: thinning past `bank_reach`
	float inner = 1.0 - smoothstep(bank_cover - bank_soft, bank_cover + bank_soft, up - puff);
	float outer = 1.0 - smoothstep(bank_reach - bank_soft, bank_reach + bank_soft, away - puff);
	vec3 rgb = b.rgb * bank_tint.rgb;
	float near = 1.0 - smoothstep(0.0, max(bank_reach, 1.0), away);
	rgb = mix(rgb, rgb * bank_shade.rgb, bank_shade.a * near);
	return vec4(rgb, inner * outer * fade * b.a * bank_tint.a);
}

// What the elevation draws at `at` (its depth map) above a sky floor of `cell_level`: -1 a top (or
// the core past a back rim), 0 the sky floor, else a south wall, as 64 + how far up it from its foot
// (above 0). The map is 8-bit: dy comes back in 2-unit steps, flat ground (0) as about -1.5, so within
// 3 units it is flat. Read smoothly, so a 45° wall's edge is a line, not the map's 2-unit steps.
float wall_below(vec2 at, float cell_level) {
	vec2 uv = (at - depth_rect.xy) / depth_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec4 d = texture(depth_map, uv);
	float terrain = smoothstep(0.2, 0.3, d.b);
	float ramp = 1.0 - smoothstep(0.03, 0.07, abs(d.b - 0.875));
	float level = (d.r * 8.0 - 4.0) * terrain;
	float dy = (d.g * 512.0 - 128.0) * terrain * (1.0 - ramp);
	if (level < cell_level + 0.5 || dy < -3.5) {
		// the floor, or the thin core the map lays past a back rim (elevation_rims.gd `add_cores`),
		// which the elevation draws as the floor
		return 0.0;
	}
	if (dy < 4.0) {
		return -1.0;
	}
	// up from the foot: the wall's height (64 a level) less how far below its top edge
	return 64.0 + (level - cell_level) * 64.0 - dy;
}

bool in_area(vec2 at) {
	return at.x >= area.x && at.y >= area.y && at.x <= area.x + area.z && at.y <= area.y + area.w;
}

vec3 sky_at(vec2 at) {
	vec3 sky = base_colour;
	vec4 c = layer_colour(layer1, 0, at, TIME);
	sky = mix(sky, c.rgb, c.a);
	c = layer_colour(layer2, 1, at, TIME);
	sky = mix(sky, c.rgb, c.a);
	c = layer_colour(layer3, 2, at, TIME);
	sky = mix(sky, c.rgb, c.a);
	c = layer_colour(layer4, 3, at, TIME);
	return mix(sky, c.rgb, c.a);
}

void fragment() {
	// the backdrop and the lip run on the elevation's meshes of the whole world: off the area (and,
	// the backdrop, above the sky's level) they stop before reading the field
	if (sky_mode != 2 && (!in_area(world) || (sky_mode == 1 && tri_level > sky_level + 0.5))) {
		discard;
	}
	vec2 ft = (world - field_origin) / field_texel;
	ivec2 ti = ivec2(floor(ft));
	bool in_field = ti.x >= 0 && ti.y >= 0 && ti.x < int(field_size.x) && ti.y < int(field_size.y);
	vec4 cell = in_field ? texelFetch(field, ti, 0) : vec4(1.0, 1.0, 0.0, 1.0);
	vec4 f = texture(field, ft / field_size);
	// out over the sky from the silhouettes (negative inside them), and up a side wall's strip
	float dist = (f.g * 2.0 - 1.0) * field_range;
	float strip = (f.r * 2.0 - 1.0) * field_range;
	vec4 bank_c = vec4(0.0);

	if (sky_mode == 1) {
		// the backdrop: the floors at the sky's level; the bank out from the silhouettes (the walls and
		// tops drawn over it end it as they are drawn)
		if (bank_on) {
			bank_c = bank_at(world, 0.0, max(dist, 0.0), 1.0);
		}
		vec3 floor_rgb = mix(sky_at(world), bank_c.rgb, bank_c.a);
		// under a wall the elevation draws (CRACK_FOOT up from its foot): rock, so a hairline crack
		// between its meshes (a side strip and a front face) shows rock, not the bright sky
		if (depth_rect.z > 0.0) {
			float level = floor(tri_level + 0.5);
			if (max(wall_below(world + vec2(2.0, 0.0), level), wall_below(world - vec2(2.0, 0.0), level)) > 64.0 + CRACK_FOOT
					&& wall_below(world + vec2(0.0, CRACK_FOOT), level) > 0.0) {
				floor_rgb = CRACK;
			}
		}
		COLOR = vec4(floor_rgb, 1.0);
	} else if (sky_mode == 0) {
		// the lip, on a wall piece drawn into the sky (its foot at the sky floor's level)
		bool foot = piece > 0.45 && piece < 0.57;
		if (piece > 0.57 || (foot && piece_b > 0.5) || cell.b < 0.002) {
			discard;
		}
		float cell_level = floor(cell.b * 16.0 - 8.0 + 0.5);
		float here = depth_rect.z > 0.0 ? wall_below(world, cell_level) : 0.0;
		if (here < -0.5 && f.a * to_land_range >= TOP_NEAR) {
			here = 0.0;
		}
		if (foot) {
			// a foot piece: the elevation draws no foot in the sky, and its floor ends on the depth
			// map's straight foot line while the wall's own foot wobbles round it (UV.y: units past the
			// wobbling foot line), so between the two neither draws. The sky goes there as the backdrop
			// draws it, in a band FOOT_FILL wide along the wall's foot; not over a top or up another wall.
			float past = smoothstep(-0.5, 0.5, UV.y) * (1.0 - smoothstep(FOOT_FILL - 2.0, FOOT_FILL, UV.y));
			float floor_here = (here > -0.5 && here < 64.0 + CRACK_FOOT) ? 1.0 : 0.0;
			float foot_a = past * floor_here;
			if (foot_a <= 0.002) {
				discard;
			}
			vec4 foot_bank = bank_on ? bank_at(world, 0.0, max(dist, 0.0), 1.0) : vec4(0.0);
			COLOR = vec4(mix(sky_at(world), foot_bank.rgb, foot_bank.a), foot_a);
		} else {
			if (here < -0.5 || dist < -0.9 * field_range) {
				// a top the elevation draws, by its depth map or by the field (the grass a cut corner's patch
				// lays over the floor's triangles), where a wall reaches over it
				discard;
			}
			// how much the point is open sky (by the depth map, the field, and off a side wall's strip, read
			// smoothly so the lip has no edge on a texel's line): there a wall piece hanging out over it (the
			// slanted start of a side wall at a back corner) shows the sky as the backdrop draws it;
			// elsewhere the bank goes up the wall from its foot
			float off_strip = smoothstep(0.55, 0.95, f.r);
			float open_w = (here == 0.0 ? 1.0 : 0.0) * smoothstep(0.0, 4.0, dist) * off_strip;
			// up the wall from its foot. A side wall's strip is the wall seen from the side: its height runs
			// across it, so by that alone the bank would line its outer edge from the top's back corner down
			// (the owner, 2026-11-11: "clouds start from the top edge on lateral walls"). Its bottom is its
			// lower end: the bank comes round the front corner and thins out up the strip as the wall turns
			// into a side's (piece 0 … 0.2), none on the strip itself.
			float side = piece < 0.25 ? clamp(piece / 0.2, 0.0, 1.0) : 0.0;
			float up = max((wall_height - cell_level) * 64.0, 0.0) + side * (bank_cover + bank_soft + bank_puff);
			vec4 wall_bank = bank_on ? bank_at(world, up, max(dist, 0.0), 1.0) : vec4(0.0);
			vec3 open_rgb = vec3(0.0);
			if (open_w > 0.0) {
				vec4 open_bank = bank_on ? bank_at(world, 0.0, max(dist, 0.0), 1.0) : vec4(0.0);
				open_rgb = mix(sky_at(world), open_bank.rgb, open_bank.a);
			}
			float a = open_w + (1.0 - open_w) * wall_bank.a;
			if (a <= 0.002) {
				discard;
			}
			COLOR = vec4((open_rgb * open_w + wall_bank.rgb * wall_bank.a * (1.0 - open_w)) / a, a);
		}
	} else {
		// no elevation drawing: the sky cut round the field's silhouettes, and the bank
		if (cell.b < 0.002) {
			discard;
		}
		float rim = smoothstep(0.0, max(rim_soft, 0.001), f.a * to_land_range);
		float a_open = smoothstep(-1.0, 1.0, dist) * rim;
		if (bank_on) {
			float inside = cell.r < 0.5 ? strip : dist;
			bank_c = bank_at(world, max(-inside, 0.0), max(dist, 0.0), rim);
		}
		float a = a_open * (1.0 - bank_c.a) + bank_c.a;
		if (a <= 0.002) {
			discard;
		}
		COLOR = vec4((sky_at(world) * a_open * (1.0 - bank_c.a) + bank_c.rgb * bank_c.a) / a, a);
	}
}
