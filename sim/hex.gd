class_name Hex
extends RefCounted
## 六边形网格工具（axial 坐标 q,r；尖顶朝向）。
##
## 大陆地图用六边形而不是方格，是因为**每个格子有恰好 6 个邻居，且到所有邻居的距离相等**。
## 方格网格的对角邻居是"作弊"的（距离 √2），会让"往哪边迁徙更近"变成一个假问题。

const DIRS: Array = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbors(h: Vector2i) -> Array:
	var out: Array = []
	for d in DIRS:
		out.append(h + d)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


## 半径 R 内的全部 hex（正六边形大陆，共 3R²+3R+1 格）。
static func within(radius: int) -> Array:
	var out: Array = []
	for q in range(-radius, radius + 1):
		var lo := maxi(-radius, -q - radius)
		var hi := mini(radius, -q + radius)
		for r in range(lo, hi + 1):
			out.append(Vector2i(q, r))
	return out


## axial → 像素（尖顶六边形）。
static func to_pixel(h: Vector2i, size: float) -> Vector2:
	var x := size * (sqrt(3.0) * float(h.x) + sqrt(3.0) * 0.5 * float(h.y))
	var y := size * (1.5 * float(h.y))
	return Vector2(x, y)


## 像素 → 最近的 axial（用于鼠标点选）。
static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var r := (2.0 / 3.0 * p.y) / size
	return _round_axial(q, r)


static func _round_axial(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(float(q) - qf)
	var dr := absf(float(r) - rf)
	var ds := absf(float(s) - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


## 六个角点（尖顶：一个角朝上）。
static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * float(i) - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * size)
	return pts


static func hex_key(h: Vector2i) -> String:
	return "%d,%d" % [h.x, h.y]


static func parse_key(k: String) -> Vector2i:
	var parts := k.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
