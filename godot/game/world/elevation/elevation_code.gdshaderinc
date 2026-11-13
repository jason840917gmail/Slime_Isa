// How a level and a depth travel in vertex colours and in the depth map's texels
// (game/world/elevation/level_code.gd writes them: change the numbers in both).
#ifndef ELEVATION_CODE_INCLUDED
#define ELEVATION_CODE_INCLUDED

// A level (or a height in levels): (level + 4) / 32.
float decode_level(float channel) {
	return channel * 32.0 - 4.0;
}

// A depth below a wall's top edge or past a rim's edge (world units): (dy + 128) / 1536.
float decode_dy(float channel) {
	return channel * 1536.0 - 128.0;
}

#endif
