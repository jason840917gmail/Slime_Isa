"""Stairs mockups: flights with a top landing, railings and newel posts on all 8 sides of an
octagon hill, in the game's projection, over the game's own cliff (octagon-L<L>.png from
stairs_backdrop.gd). The design and its numbers: README.md beside this file.

Projection (Slime Isa elevation): a point at ground (x, y) and height h (world units) is drawn at
screen (x, y - h); along a view ray y + h grows towards the camera, so depth = y + h (larger is
nearer). Pictures are 2 px per world unit; one level is 64 units.

Usage: python stairs_mockup.py <work dir with octagon-L1.png, octagon-L2.png> [variants]
  Writes v3-L<levels>-w<cells>.png (and -small) to the work dir; "variants" writes the front
  variants sheet (landing railed or open, one or two cells wide) beside this file.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import sys

REPO = Path(__file__).resolve().parents[4]
GEN = REPO / "asset/Originals/elevation/generated"
ART = REPO / "godot/game/world/elevation/art"
MOCKUPS = Path(__file__).resolve().parent
HERE = Path(sys.argv[1]) if len(sys.argv) > 1 else MOCKUPS
Z = 2.0
LEVEL = 64.0
STEPS_PER_LEVEL = 3
RISE = LEVEL / STEPS_PER_LEVEL
HALF = 32.0            # half the walkable width of a flight (one cell)
LANDING = 32.0         # flat top step reaching into the higher ground
BOTTOM = 11.0          # the last step (at the lower ground) is this much deeper
RAIL = 18.0            # railing thickness (outside the walkable cell)
RAIL_UP = 24.0         # railing height above the steps' nosing line
POST = 20.0            # newel post length along the flight
POST_OUT = 6.0         # a post stands this much proud of the railing on the outside only (never into the walkway)
POST_UP = 10.0         # and this much above it
# One row of each source, crevice to crevice (y0, y1 in source px).
TREAD_SRC = ("stairs-tread-a.png", 394, 530)
BLOCK_SRC = ("stairs-riser-b.png", 322, 471)
SRC_PER_UNIT = 136 / RISE
RISER_TONE = 0.80
RAIL_TONE = 0.95
NOSING_LIGHT = 1.22
SHADE_S = 0.86
SHADE_SPREAD = 0.20
LINE = np.array([0.20, 0.13, 0.08])
LINE_ALPHA = 0.55
SHADOW_PER_LEVEL = np.array([20.0, 8.0])
SHADOW_STRENGTH = 0.38
FOOT_EDGE_ROW = 80
FOOT_LAST_ROW = 100


def rgb(path):
	return np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0


def periodic_strip(name, y0, y1, fade=64):
	a = rgb(GEN / name)[y0:y1]
	w = a.shape[1] - fade
	out = a[:, :w].copy()
	t = np.linspace(0.0, 1.0, fade)[None, :, None]
	out[:, :fade] = a[:, w:w + fade] * (1 - t) + a[:, :fade] * t
	return out


TREAD = periodic_strip(*TREAD_SRC)
BLOCK = periodic_strip(*BLOCK_SRC)
WALL_TEX = rgb(ART / "meadow-rock-wall.png")
# Copings: the cut blocks, tinted halfway to the cliff rock so the railings read as one material.
_tint = WALL_TEX.reshape(-1, 3).mean(0) / BLOCK.reshape(-1, 3).mean(0)
CAP = BLOCK * (0.5 + 0.5 * _tint)[None, None, :]
FOOT_TEX = np.asarray(Image.open(ART / "highland-foot.png").convert("RGBA")).astype(np.float32) / 255.0


def sample(tex, tx, ty, wrap_y=True):
	h, w = tex.shape[:2]
	tx = np.mod(tx, w)
	ty = np.mod(ty, h) if wrap_y else np.clip(ty, 0, h - 1.001)
	x0 = np.floor(tx).astype(int)
	y0 = np.floor(ty).astype(int)
	fx = (tx - x0)[:, None]
	fy = (ty - y0)[:, None]
	x0 %= w
	y0 = y0 % h if wrap_y else np.clip(y0, 0, h - 1)
	x1 = (x0 + 1) % w
	y1 = (y0 + 1) % h if wrap_y else np.minimum(y0 + 1, h - 1)
	return (tex[y0, x0] * (1 - fx) * (1 - fy) + tex[y0, x1] * fx * (1 - fy)
			+ tex[y1, x0] * (1 - fx) * fy + tex[y1, x1] * fx * fy)


def shade_for(normal):
	"""As elevation_wall.gdshader: tops 1.0, SW 1.0, S 0.86, SE 0.66 (faces turned away: None)."""
	if normal[2] > 0.3:
		return 1.0
	if normal[1] <= 1e-6:
		return None
	nx = normal[0] / math.sqrt(0.5)
	return SHADE_S - SHADE_SPREAD * max(-1.0, min(1.0, nx))


class Flight:
	def __init__(self, rim_mid, direction, levels, run_per_level, seed, cells=1, open_landing=False):
		self.half = HALF * cells
		self.rail_start = 0.0 if open_landing else -LANDING
		d = np.array([direction[0], direction[1]], float)
		d /= np.linalg.norm(d)
		self.d = np.array([d[0], d[1], 0.0])
		self.t = np.array([-d[1], d[0], 0.0])
		self.up = np.array([0.0, 0.0, 1.0])
		self.top = levels * LEVEL
		self.steps = levels * STEPS_PER_LEVEL
		self.run = run_per_level * levels / self.steps
		self.end = self.steps * self.run + BOTTOM
		self.base = np.array([rim_mid[0], rim_mid[1] + self.top, 0.0])
		self.rng = np.random.default_rng(seed)
		self.faces = []
		self.prisms = []  # (footprint corners (s, t), top height) for shadows
		self.feet = []
		self._build()

	def world(self, s, t, h):
		return self.base + self.d * s + self.t * t + self.up * h

	def nosing(self, s):
		"""Height of the steps' nosing line at s (the railing follows it)."""
		return float(np.clip(self.top - s * self.top / (self.steps * self.run), 0.0, self.top))

	def face(self, poly_sth, kind, normal, **extra):
		"""A planar face from its corners in (s, t, h) with its outward normal; kind picks the
		texture mapping. Faces turned away from the camera are skipped."""
		pts = [self.world(*p) for p in poly_sth]
		normal = np.array(normal, float)
		shade = shade_for(normal)
		if shade is None:
			return
		self.faces.append(dict(pts=pts, kind=kind, normal=normal, shade=shade, flight=self, **extra))

	def _build(self):
		top, run, steps, end = self.top, self.run, self.steps, self.end
		D, T, U = self.d, self.t, self.up
		# Top landing on the higher ground, then the steps.
		self.face([(-LANDING, -self.half, top), (0, -self.half, top), (0, self.half, top), (-LANDING, self.half, top)], "tread", s0=-LANDING, depth=LANDING, off=self.rng.uniform(0, 2000), normal=U)
		for k in range(steps):
			h = top - (k + 1) * RISE
			s0, s1 = k * run, (k + 1) * run if k < steps - 1 else end
			off = self.rng.uniform(0, 2000)
			self.face([(s0, -self.half, top - k * RISE), (s0, self.half, top - k * RISE), (s0, self.half, h), (s0, -self.half, h)], "riser", off=off, normal=D)
			self.face([(s0, -self.half, h), (s1, -self.half, h), (s1, self.half, h), (s0, self.half, h)], "tread", s0=s0, depth=s1 - s0, off=off, normal=U, front=s1)
			self.prisms.append(([(s0, -self.half), (s1, -self.half), (s1, self.half), (s0, self.half)], h))
		# Railings: from the landing's start to the last step's front, following the nosing line.
		for side in (-1.0, 1.0):
			inner, outer = side * self.half, side * (self.half + RAIL)
			rs = self.rail_start
			profile = [(rs, top + RAIL_UP), (0.0, top + RAIL_UP), (steps * run, RAIL_UP), (end, RAIL_UP)]
			if rs >= 0.0:
				profile = profile[1:]
			for (sa, ha), (sb, hb) in zip(profile, profile[1:]):
				self.face([(sa, inner, ha), (sb, inner, hb), (sb, outer, hb), (sa, outer, ha)], "cap", sa=sa, normal=self._up_normal(sa, ha, sb, hb))
			for t_face, sgn in ((outer, side), (inner, -side)):
				poly = [(rs, t_face, top), (0.0, t_face, top), (0.0, t_face, 0.0), (end, t_face, 0.0),
						(end, t_face, RAIL_UP), (steps * run, t_face, RAIL_UP), (0.0, t_face, top + RAIL_UP), (rs, t_face, top + RAIL_UP)]
				if rs >= 0.0:
					poly = poly[2:-1]
				self.face(poly, "block", normal=T * sgn)
				if sgn == side and (T * sgn)[1] > 1e-6:
					self.feet.append(((0.0, t_face), (end, t_face)))
			self.face([(end, inner, 0), (end, outer, 0), (end, outer, RAIL_UP), (end, inner, RAIL_UP)], "block", normal=D)
			floor_rs = top if rs < 0.0 else 0.0
			self.face([(rs, outer, floor_rs), (rs, inner, floor_rs), (rs, inner, top + RAIL_UP), (rs, outer, top + RAIL_UP)], "block", normal=-D)
			for k in range(steps + 1):
				s0 = k * run if k < steps else end - run
				s1 = min(end, s0 + run)
				self.prisms.append(([(s0, inner), (s1, inner), (s1, outer), (s0, outer)], self.nosing(s0) + RAIL_UP))
			# Newel posts at both ends.
			p_in, p_out = side * self.half, side * (self.half + RAIL + POST_OUT)
			for s0, s1, floor, height in ((rs, rs + POST, floor_rs, top + RAIL_UP + POST_UP), (end - POST, end, 0.0, RAIL_UP + POST_UP)):
				self._box(s0, s1, min(p_in, p_out), max(p_in, p_out), floor, height)
				self.prisms.append(([(s0, p_in), (s1, p_in), (s1, p_out), (s0, p_out)], height))
				if floor == 0.0 and D[1] > 1e-6:
					self.feet.append(((s1, p_in), (s1, p_out)))

	def _up_normal(self, sa, ha, sb, hb):
		slope = (hb - ha) / max(1e-6, sb - sa)
		n = self.up - self.d * slope
		return n / np.linalg.norm(n)

	def _box(self, s0, s1, t0, t1, h0, h1):
		D, T, U = self.d, self.t, self.up
		self.face([(s0, t0, h1), (s1, t0, h1), (s1, t1, h1), (s0, t1, h1)], "cap", sa=s0, normal=U)
		self.face([(s1, t0, h0), (s1, t1, h0), (s1, t1, h1), (s1, t0, h1)], "block", normal=D)
		self.face([(s0, t1, h0), (s0, t0, h0), (s0, t0, h1), (s0, t1, h1)], "block", normal=-D)
		self.face([(s0, t1, h0), (s1, t1, h0), (s1, t1, h1), (s0, t1, h1)], "block", normal=T)
		self.face([(s1, t0, h0), (s0, t0, h0), (s0, t0, h1), (s1, t0, h1)], "block", normal=-T)

	def local(self, p):
		q = p - self.base[None, :]
		return q @ self.d, q @ self.t, p[:, 2]


def screen_of(p):
	return np.array([p[0] * Z, (p[1] - p[2]) * Z])


def colour_of(face, p):
	fl = face["flight"]
	s, t, h = fl.local(p)
	kind = face["kind"]
	if kind == "tread":
		tx = t * SRC_PER_UNIT + face["off"]
		v = (s - face["s0"]) / face["depth"]
		ty = np.clip(v, 0, 0.999) * TREAD.shape[0]
		col = sample(TREAD, tx, ty, False)
		if "front" in face:
			ao = 0.78 + 0.22 * np.clip((s - face["s0"]) / (0.35 * face["depth"]), 0, 1)
			ao *= np.where(s > face["front"] - 3.0, NOSING_LIGHT, 1.0)
			col = col * ao[:, None]
		edge = np.clip((fl.half - np.abs(t)) / 9.0, 0, 1)
		col = col * (0.62 + 0.38 * edge)[:, None]
	elif kind == "riser":
		tx = t * SRC_PER_UNIT + face["off"] * 0.7
		ty = (fl.top - h) / RISE * BLOCK.shape[0]
		col = sample(BLOCK, tx, ty) * RISER_TONE
		top_of_riser = fl.top - np.floor((fl.top - h) / RISE + 1e-6) * RISE
		ao = 0.62 + 0.38 * np.clip((top_of_riser - h) / (0.4 * RISE), 0, 1)
		edge = np.clip((fl.half - np.abs(t)) / 7.0, 0, 1)
		col = col * (ao * (0.75 + 0.25 * edge))[:, None]
	elif kind == "cap":
		tx = s * SRC_PER_UNIT * 1.6 + 700
		across = (np.abs(t) - fl.half) / (RAIL + POST_OUT)
		ty = np.clip(across, 0, 0.999) * CAP.shape[0]
		col = sample(CAP, tx, ty, False) * 1.1
	else:  # block: railing and post sides in the cliff's rock, courses level with the cliff's
		along = np.where(np.abs(face["normal"] @ fl.t) > 0.5, s, t)
		tx = along * 2.0 + 300
		ty = (fl.top - h) * 2.0
		col = sample(WALL_TEX, tx, ty)
		# Contact shadow where an inner railing face meets the steps.
		above = h - np.array([fl.nosing(v) for v in s]) + RISE * 0.0
		col = col * np.where(np.abs(np.abs(t) - fl.half) < 0.5, 0.7 + 0.3 * np.clip(above / 10.0, 0, 1), 1.0)[:, None]
	return col * face["shade"]


# The octagon (screen units at its top level) from _stairs_bg.gd. A chamfered 45° rim runs through
# the middle of its single-cell steps.
TOP = [(608, 512), (992, 512), (1216, 736), (1216, 864), (992, 1088), (608, 1088), (384, 864), (384, 736)]
R2 = math.sqrt(2.0)


def sides():
	return {
		"S": ((800, 1088), (0, 1), 64.0),
		"SW": ((496, 976), (-1, 1), 64 * R2),
		"SE": ((1104, 976), (1, 1), 64 * R2),
		"E": ((1216, 800), (1, 0), 64.0),
		"W": ((384, 800), (-1, 0), 64.0),
		"N": ((800, 512), (0, -1), 96.0),
		"NE": ((1104, 624), (1, -1), 64 * R2),
		"NW": ((496, 624), (-1, -1), 64 * R2),
	}


def background_depth(shape, levels):
	"""Depth (y + h) of what the cliff render shows at every pixel, and a hill/wall mask."""
	H = levels * LEVEL
	hpx, wpx = shape
	sx = (np.arange(wpx)[None, :] + 0.5) / Z
	sy = (np.arange(hpx)[:, None] + 0.5) / Z
	sx = np.broadcast_to(sx, shape)
	sy = np.broadcast_to(sy, shape)
	depth = sy.copy()
	img = Image.new("L", (wpx, hpx), 0)
	ImageDraw.Draw(img).polygon([(x * Z, y * Z) for x, y in TOP], fill=255)
	top = np.asarray(img) > 127
	depth = np.where(top, sy + 2 * H, depth)
	solid = top.copy()
	# South wall, south-west and south-east walls hanging below their rims.
	walls = [
		((sx >= 608) & (sx <= 992), 1088.0 + 0 * sx),
		((sx >= 384) & (sx < 608), sx + 480.0),
		((sx > 992) & (sx <= 1216), -sx + 2080.0),
	]
	for band, rim in walls:
		in_wall = band & (sy >= rim) & (sy <= rim + H) & ~top
		depth = np.where(in_wall, 2 * (rim + H) - sy, depth)
		solid |= in_wall
	return depth, solid


def render(levels, only=None, cells=1):
	bg = rgb(HERE / f"octagon-L{levels}.png")
	hpx, wpx = bg.shape[:2]
	zbuf, solid = background_depth((hpx, wpx), levels)
	zbuf = zbuf - 0.75
	canvas = bg.copy()
	ids = np.full((hpx, wpx), -1, int)
	flights = [Flight(mid, d, levels, run, seed=i * 17 + levels, cells=cells)
			   for i, (name, (mid, d, run)) in enumerate(sides().items()) if only is None or name in only]
	faces = [f for fl in flights for f in fl.faces]
	# Shadows on the open ground first.
	shadow = Image.new("L", (wpx, hpx), 0)
	g = ImageDraw.Draw(shadow)
	for fl in flights:
		for corners, height in fl.prisms:
			ground = [fl.world(s, t, 0)[:2] for s, t in corners]
			shift = SHADOW_PER_LEVEL * height / LEVEL
			hull = convex_hull(np.array(ground + [q + shift for q in ground]))
			g.polygon([tuple(q * Z) for q in hull], fill=255)
	shadow = np.asarray(shadow.filter(ImageFilter.GaussianBlur(5))).astype(np.float32) / 255.0
	shadow[solid] = 0.0
	canvas *= (1.0 - SHADOW_STRENGTH * shadow)[:, :, None]
	for index, face in enumerate(faces):
		pts2 = [tuple(screen_of(p)) for p in face["pts"]]
		mask_img = Image.new("L", (wpx, hpx), 0)
		ImageDraw.Draw(mask_img).polygon(pts2, fill=255)
		ys, xs = np.nonzero(np.asarray(mask_img) > 127)
		if len(xs) == 0:
			continue
		p0, p1, p2 = face["pts"][0], face["pts"][1], face["pts"][-1]
		a, b = p1 - p0, p2 - p0
		s0 = screen_of(p0)
		sa = np.array([a[0] * Z, (a[1] - a[2]) * Z])
		sb = np.array([b[0] * Z, (b[1] - b[2]) * Z])
		m = np.array([[sa[0], sb[0]], [sa[1], sb[1]]])
		if abs(np.linalg.det(m)) < 1e-6:
			continue
		uv = np.linalg.inv(m) @ np.stack([xs + 0.5 - s0[0], ys + 0.5 - s0[1]])
		p = p0[None, :] + uv[0][:, None] * a[None, :] + uv[1][:, None] * b[None, :]
		depth = p[:, 1] + p[:, 2]
		keep = depth > zbuf[ys, xs]
		if not keep.any():
			continue
		ys, xs, p, depth = ys[keep], xs[keep], p[keep], depth[keep]
		canvas[ys, xs] = np.clip(colour_of(face, p), 0, 1)
		zbuf[ys, xs] = depth
		ids[ys, xs] = index
	# Lines where faces meet (and around the stairs).
	edge = np.zeros_like(ids, bool)
	edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
	edge[1:, :] |= ids[1:, :] != ids[:-1, :]
	edge &= (ids >= 0) | np.roll(ids >= 0, 1, 0) | np.roll(ids >= 0, 1, 1)
	edge_img = Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
	e = (np.asarray(edge_img).astype(np.float32) / 255.0) * LINE_ALPHA
	canvas = canvas * (1 - e[:, :, None]) + LINE[None, None, :] * e[:, :, None]
	for fl in flights:
		draw_feet(canvas, fl, ids, zbuf)
	return canvas


def draw_feet(canvas, fl, ids, zbuf):
	"""The ground's foot strip where the railings and posts stand on the lower ground, where that
	foot is in sight."""
	h, w = canvas.shape[:2]
	fw = FOOT_TEX.shape[1]
	for (sa, ta), (sb, tb) in fl.feet:
		a, b = fl.world(sa, ta, 0), fl.world(sb, tb, 0)
		normal = np.cross(b - a, fl.up)
		pa, pb = screen_of(a), screen_of(b)
		if abs(pb[0] - pa[0]) < 1:
			continue
		x0, x1 = sorted((int(round(pa[0])), int(round(pb[0]))))
		for x in range(max(0, x0), min(w, x1)):
			t = (x + 0.5 - pa[0]) / (pb[0] - pa[0])
			y_base = pa[1] + t * (pb[1] - pa[1])
			ground = a + (b - a) * t
			yb = int(round(y_base)) - 2
			if not (0 <= yb < h) or zbuf[yb, x] > ground[1] + ground[2] + 3.0:
				continue
			col = FOOT_TEX[:FOOT_LAST_ROW, x % fw]
			top = int(round(y_base)) - FOOT_EDGE_ROW
			ys = np.arange(top, top + FOOT_LAST_ROW)
			ok = (ys >= 0) & (ys < h)
			alpha = col[ok, 3:4]
			canvas[ys[ok], x] = canvas[ys[ok], x] * (1 - alpha) + col[ok, :3] * alpha


def convex_hull(points):
	pts = sorted(map(tuple, points))
	def cross(o, a, b):
		return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
	lower, upper = [], []
	for p in pts:
		while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
			lower.pop()
		lower.append(p)
	for p in reversed(pts):
		while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
			upper.pop()
		upper.append(p)
	return [np.array(p) for p in lower[:-1] + upper[:-1]]


def save(canvas, path, box=None, scale=1.0):
	img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8))
	if box:
		img = img.crop(box)
	if scale != 1.0:
		img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
	img.save(path)
	return img


def render_flights(levels, flights):
	"""Like render(), for a given list of flights."""
	bg = rgb(HERE / f"octagon-L{levels}.png")
	hpx, wpx = bg.shape[:2]
	zbuf, solid = background_depth((hpx, wpx), levels)
	zbuf = zbuf - 0.75
	canvas = bg.copy()
	ids = np.full((hpx, wpx), -1, int)
	faces = [f for fl in flights for f in fl.faces]
	shadow = Image.new("L", (wpx, hpx), 0)
	g = ImageDraw.Draw(shadow)
	for fl in flights:
		for corners, height in fl.prisms:
			ground = [fl.world(s_, t_, 0)[:2] for s_, t_ in corners]
			shift = SHADOW_PER_LEVEL * height / LEVEL
			hull = convex_hull(np.array(ground + [q + shift for q in ground]))
			g.polygon([tuple(q * Z) for q in hull], fill=255)
	shadow = np.asarray(shadow.filter(ImageFilter.GaussianBlur(5))).astype(np.float32) / 255.0
	shadow[solid] = 0.0
	canvas *= (1.0 - SHADOW_STRENGTH * shadow)[:, :, None]
	for index, face in enumerate(faces):
		draw_one(canvas, zbuf, ids, index, face)
	edge = np.zeros_like(ids, bool)
	edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
	edge[1:, :] |= ids[1:, :] != ids[:-1, :]
	edge &= (ids >= 0) | np.roll(ids >= 0, 1, 0) | np.roll(ids >= 0, 1, 1)
	edge_img = Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
	e = (np.asarray(edge_img).astype(np.float32) / 255.0) * LINE_ALPHA
	canvas = canvas * (1 - e[:, :, None]) + LINE[None, None, :] * e[:, :, None]
	for fl in flights:
		draw_feet(canvas, fl, ids, zbuf)
	return canvas


def draw_one(canvas, zbuf, ids, index, face):
	hpx, wpx = zbuf.shape
	pts2 = [tuple(screen_of(p)) for p in face["pts"]]
	mask_img = Image.new("L", (wpx, hpx), 0)
	ImageDraw.Draw(mask_img).polygon(pts2, fill=255)
	ys, xs = np.nonzero(np.asarray(mask_img) > 127)
	if len(xs) == 0:
		return
	p0, p1, p2 = face["pts"][0], face["pts"][1], face["pts"][-1]
	a, b = p1 - p0, p2 - p0
	s0 = screen_of(p0)
	sa = np.array([a[0] * Z, (a[1] - a[2]) * Z])
	sb = np.array([b[0] * Z, (b[1] - b[2]) * Z])
	m = np.array([[sa[0], sb[0]], [sa[1], sb[1]]])
	if abs(np.linalg.det(m)) < 1e-6:
		return
	uv = np.linalg.inv(m) @ np.stack([xs + 0.5 - s0[0], ys + 0.5 - s0[1]])
	p = p0[None, :] + uv[0][:, None] * a[None, :] + uv[1][:, None] * b[None, :]
	depth = p[:, 1] + p[:, 2]
	keep = depth > zbuf[ys, xs]
	if not keep.any():
		return
	ys, xs, p, depth = ys[keep], xs[keep], p[keep], depth[keep]
	canvas[ys, xs] = np.clip(colour_of(face, p), 0, 1)
	zbuf[ys, xs] = depth
	ids[ys, xs] = index


def variants():
	levels = 2
	mid, d, run = sides()["S"]
	out = []
	for title, cells, open_landing in (("1 cell, railed landing", 1, False), ("1 cell, open landing", 1, True),
			("2 cells, railed landing", 2, False), ("2 cells, open landing", 2, True)):
		canvas = render_flights(levels, [Flight(mid, d, levels, run, seed=5, cells=cells, open_landing=open_landing)])
		img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8)).crop((int(600 * Z), int(1000 * Z), int(1000 * Z), int(1420 * Z)))
		out.append((title, img))
	return out


if __name__ == "__main__" and sys.argv[-1] == "variants":
	from PIL import ImageFont
	font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 30)
	panels = variants()
	pad = 24
	w = sum(p.width for _, p in panels) + pad * (len(panels) + 1)
	h = max(p.height for _, p in panels) + 140
	sheet = Image.new("RGB", (w, h), (24, 28, 36))
	g = ImageDraw.Draw(sheet)
	g.text((pad, 16), "Front stairs (level 2): landing railings and width", font=font, fill=(240, 236, 220))
	x = pad
	for title, p in panels:
		g.text((x, 70), title, font=font, fill=(255, 226, 150))
		sheet.paste(p, (x, 116))
		x += p.width + pad
	sheet.save(MOCKUPS / "stairs-front-variants.png")
	print(sheet.size)
elif __name__ == "__main__":
	for levels, cells in ((1, 1), (2, 1), (2, 2)):
		canvas = render(levels, cells=cells)
		drop = levels * LEVEL
		box = (int((384 - drop - 96) * Z), int((512 - drop - 160) * Z), int((1216 + drop + 120) * Z), int((1088 + 2 * drop + 96) * Z))
		save(canvas, HERE / f"v3-L{levels}-w{cells}.png", box)
		save(canvas, HERE / f"v3-L{levels}-w{cells}-small.png", box, 0.4)
		print("v3", levels, cells, box)
