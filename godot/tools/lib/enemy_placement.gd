extends RefCounted
## Sets out the enemies of an old spawn table as placed enemies (roadmap 5.25, 2026-10-16;
## game/enemy/placed_enemy.gd): how many of each type (`apportion`), where in their area they stand
## (`spread`: an even layout over the open spots found there) and which type stands where
## (`interleave`); a legacy spawn table becomes at most TABLE_ENEMIES enemies in TABLE_CAMPS camps
## (`table_camps`). Deterministic: the same inputs give the same layout. Used by
## tools/split_region_chunks.gd (a hand-made world's spawn areas, cut into chunks) and by the
## one-off conversion of the game worlds' spawn areas and `metadata.spawns` tables.
##
## Owner: enemy builder.

## Lloyd iterations of `spread`.
const SPREAD_ROUNDS := 24
## A legacy spawn table (`metadata.spawns`, enemy spec 18: up to 16 around the player) is no camp:
## a chunk takes at most TABLE_ENEMIES of its enemies (the meadow chunks stand 3 or 4; owner's
## coordinator, 2026-10-16), in TABLE_CAMPS camps that share a rectangular wander area of
## TABLE_CAMP_SIZE world units each (`table_camps`).
const TABLE_ENEMIES := 5
const TABLE_CAMPS := 2
const TABLE_CAMP_SIZE := Vector2(288.0, 224.0)


## The types of `count` enemies from a spawn table `[{type, weight, maxAlive?}]` (an area's
## `data.enemies`, a `metadata.spawns.enemies`): seats handed out one at a time to the type with the
## highest `weight / (2 * given + 1)` (Sainte-Laguë: in proportion to the weights) among those under
## their `maxAlive` (as the old camp never had more of a type alive), ties to the earlier entry.
## Fewer than `count` when every type is full. Grouped by type, in table order.
static func apportion(table: Array, count: int) -> PackedStringArray:
	var entries: Array[Dictionary] = []
	for value: Variant in table:
		if value is Dictionary and float((value as Dictionary).get("weight", 0.0)) > 0.0 \
				and not str((value as Dictionary).get("type", "")).is_empty():
			entries.append(value)
	var given: Array[int] = []
	given.resize(entries.size())
	given.fill(0)
	for _seat in count:
		var best := -1
		var best_priority := -1.0
		for i in entries.size():
			var cap: Variant = entries[i].get("maxAlive")
			if (cap is int or cap is float) and given[i] >= int(cap):
				continue
			var priority := float(entries[i]["weight"]) / float(2 * given[i] + 1)
			if priority > best_priority:
				best = i
				best_priority = priority
		if best < 0:
			break
		given[best] += 1
	var types := PackedStringArray()
	for i in entries.size():
		for _n in given[i]:
			types.append(str(entries[i]["type"]))
	return types


## The camps a legacy spawn `table` ({enemies, maxPopulation, ...}) gives a chunk: the types of
## `min(TABLE_ENEMIES, maxPopulation)` enemies (`apportion`), mixed so each type's are spread along
## the line (`mixed`), turned by `shift` (a chunk's index, so neighbouring chunks differ), then cut
## into TABLE_CAMPS camps as even as possible, the bigger first: [types of camp 1, types of camp 2].
static func table_camps(table: Dictionary, shift: int = 0) -> Array[PackedStringArray]:
	var count := mini(TABLE_ENEMIES, int(table.get("maxPopulation", TABLE_ENEMIES)))
	var line := mixed(apportion(table.get("enemies", []), count))
	var turned := PackedStringArray()
	for i in line.size():
		turned.append(line[(i + shift) % line.size()])
	var camps: Array[PackedStringArray] = []
	var start := 0
	for k in TABLE_CAMPS:
		var size := ceili(float(turned.size() - start) / float(TABLE_CAMPS - k))
		camps.append(turned.slice(start, start + size))
		start += size
	return camps.filter(func(camp: PackedStringArray) -> bool: return not camp.is_empty())


## `types` reordered so each type's k-th of n stands at (k + 0.5) / n along the line (ties to the
## earlier entry): [brawler, brawler, swordsman, swordsman, archer] -> brawler, swordsman, archer,
## brawler, swordsman.
static func mixed(types: PackedStringArray) -> PackedStringArray:
	var totals := {}
	for type_id in types:
		totals[type_id] = int(totals.get(type_id, 0)) + 1
	var seen := {}
	var keyed: Array = []
	for i in types.size():
		var k := int(seen.get(types[i], 0))
		seen[types[i]] = k + 1
		keyed.append([(float(k) + 0.5) / float(totals[types[i]]), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var result := PackedStringArray()
	for entry: Array in keyed:
		result.append(types[int(entry[1])])
	return result


## `count` points set out evenly over `spots` (the open places of an area): k-means (Lloyd) over the
## spots, started from the spot nearest `centre` and then each time the spot farthest from those
## picked, each mean moved back onto its nearest unused spot. Fewer when there are fewer spots.
static func spread(spots: PackedVector2Array, count: int, centre: Vector2) -> PackedVector2Array:
	var picked := PackedVector2Array()
	if spots.is_empty() or count <= 0:
		return picked
	var first := 0
	for i in spots.size():
		if spots[i].distance_squared_to(centre) < spots[first].distance_squared_to(centre):
			first = i
	picked.append(spots[first])
	while picked.size() < mini(count, spots.size()):
		var far := -1
		var far_distance := -1.0
		for i in spots.size():
			var nearest := INF
			for point in picked:
				nearest = minf(nearest, spots[i].distance_squared_to(point))
			if nearest > far_distance:
				far = i
				far_distance = nearest
		picked.append(spots[far])
	for _round in SPREAD_ROUNDS:
		var sums: Array[Vector2] = []
		var counts: Array[int] = []
		for _k in picked.size():
			sums.append(Vector2.ZERO)
			counts.append(0)
		for spot in spots:
			var k := _nearest(picked, spot)
			sums[k] += spot
			counts[k] += 1
		var moved := false
		for k in picked.size():
			if counts[k] == 0:
				continue
			var mean := sums[k] / float(counts[k])
			if not mean.is_equal_approx(picked[k]):
				picked[k] = mean
				moved = true
		if not moved:
			break
	# Back onto the spots: each mean to its nearest spot not taken yet.
	var used := {}
	var placed := PackedVector2Array()
	for point in picked:
		var best := -1
		for i in spots.size():
			if used.has(i):
				continue
			if best < 0 or spots[i].distance_squared_to(point) < spots[best].distance_squared_to(point):
				best = i
		if best >= 0:
			used[best] = true
			placed.append(spots[best])
	return placed


## `types` matched to `points`: the points in order of their angle around their middle, the types
## mixed so each type's enemies are spread evenly along that order (two archers among four stand
## apart). Returns [[type, point], ...] in that order.
static func interleave(types: PackedStringArray, points: PackedVector2Array) -> Array:
	var count := mini(types.size(), points.size())
	if count == 0:
		return []
	var middle := Vector2.ZERO
	for i in count:
		middle += points[i]
	middle /= float(count)
	var order: Array = []
	for i in count:
		var offset := points[i] - middle
		order.append([offset.angle() if offset.length() > 0.5 else -PI, i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	# Each type's k-th of n enemies goes at (k + 0.5) / n along the order.
	var totals := {}
	for i in count:
		totals[types[i]] = int(totals.get(types[i], 0)) + 1
	var seen := {}
	var keyed: Array = []
	for i in count:
		var type_id := types[i]
		var k := int(seen.get(type_id, 0))
		seen[type_id] = k + 1
		keyed.append([(float(k) + 0.5) / float(totals[type_id]), i, type_id])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var result: Array = []
	for i in count:
		result.append([keyed[i][2], points[int(order[i][1])]])
	return result


static func _nearest(points: PackedVector2Array, spot: Vector2) -> int:
	var best := 0
	for k in points.size():
		if points[k].distance_squared_to(spot) < points[best].distance_squared_to(spot):
			best = k
	return best
