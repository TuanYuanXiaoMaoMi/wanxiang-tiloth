class_name WorldGen
extends RefCounted
## 肉鸽大陆生成器：**每一局从种子重新生成整片六边形大陆。**
##
## 两个设计约束：
##
## 1. **承载力必须落在已验证的区间内。**
##    生成器不是自由发挥，它是**在 docs/11 标定好的数值区间里抽签** ——
##    否则「第 24 分钟被迫迁徙」在大陆随机重开之后就废了。
##      承载力(人) = food_r·food_K/4 + prey_r·prey_K/8
##
## 2. **地形是六边形网格，不是一个 k-近邻图。**
##    每个格子恰好 6 个邻居、且到所有邻居距离相等，所以「往哪边迁徙更近」是真问题。
##    （方格网格的对角邻居距离是 √2，那个问题是假的。）
##    邻接边一律 1 天路程，因此旅途天数 = 六边形距离。

const BIOME_PATH := "res://data/biomes.json"

static var _biomes: Dictionary = {}
static var _region_names: Array = []
static var _prefixes: Array = []
static var _suffixes: Array = []
static var _factions: Array = []
static var _loaded := false
static var _error := ""

const NODE_K_FOOD := [1800.0, 4000.0]     ## 食物存量 K：决定衰退曲线有多可读
const NODE_K_PREY := [300.0, 1200.0]
const HEX_SIZE := 100.0                   ## 六边形外接圆半径（像素，用于布局与视图）
const RIM_REMOVE_CHANCE := 0.30           ## 挖掉边缘格的比例 → 不规则海岸线
const REGION_COUNT := 6
const OWNED_NODE_CHANCE := 0.16


static func ensure_loaded(path: String = BIOME_PATH) -> bool:
	if _loaded:
		return true
	if _error != "":
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_error = "无法打开生态数据：%s" % path
		push_error("WorldGen: " + _error)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_error = "生态数据解析失败"
		push_error("WorldGen: " + _error)
		return false
	var root: Dictionary = parsed
	_biomes = root.get("biomes", {})
	_region_names = root.get("region_names", [])
	_prefixes = root.get("node_prefixes", [])
	_suffixes = root.get("node_suffixes", [])
	_factions = root.get("factions", [])
	_loaded = true
	return true


static func error() -> String:
	return _error


static func biome(bid: String) -> Dictionary:
	return _biomes.get(bid, {})


static func biome_ids() -> Array:
	return _biomes.keys()


# --------------------------------------------------------------------------
# 主入口
# --------------------------------------------------------------------------

## 生成一整片六边形大陆。返回结构可直接喂给 RegionDB.load_world()。
static func generate(world_seed: int, radius: int = 4) -> Dictionary:
	if not ensure_loaded():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var ids := _biomes.keys()
	if ids.is_empty():
		return {}

	# 1) 六边形大陆：**横向的椭圆**，而不是正六边形。
	#    正六边形大陆的宽高比约 1.15，在宽屏面板里会被高度卡住缩放、左右留一大片空白。
	#    改成椭圆（宽:高 ≈ 1.7）之后，同样一块面板能多出三成的格子尺寸。
	var ax := float(radius) * 2.10      # 横向半轴
	var ay := float(radius) * 1.20      # 纵向半轴
	var inside := {}
	for h in Hex.within(radius + 1):
		var p := Hex.to_pixel(h, 1.0)
		if (p.x / ax) * (p.x / ax) + (p.y / ay) * (p.y / ay) <= 1.0:
			inside[h] = true
	# **只挖边缘格**。早期版本把随机挖洞应用到了所有格子，结果内陆被打出一堆空洞，
	# 既难看又可能把某块陆地隔断。
	var land: Array = []
	for h in inside:
		var is_rim := false
		for nb in Hex.neighbors(h):
			if not inside.has(nb):
				is_rim = true
				break
		if is_rim and rng.randf() < RIM_REMOVE_CHANCE:
			continue
		land.append(h)
	if land.is_empty():
		land = Hex.within(radius)

	# 2) 六个区域按角度扇区划分（扇区大小天然不均，反而更像真实地理）
	var region_ids: Array = []
	var regions: Dictionary = {}
	for i in REGION_COUNT:
		var rid := "r%d" % i
		var theme: String = ids[rng.randi_range(0, ids.size() - 1)]
		var rname: String = _region_names[i] if i < _region_names.size() else "无名之地%d" % i
		regions[rid] = {"name": rname, "theme": theme, "nodes": {}}
		region_ids.append(rid)

	# 3) 每个格子一个节点
	var positions: Dictionary = {}
	var centers: Dictionary = {}
	for rid in region_ids:
		centers[rid] = Vector2.ZERO
	var hex_of: Dictionary = {}
	var count_of: Dictionary = {}
	for h in land:
		var sector := _sector_of(h)
		var rid: String = region_ids[sector]
		var theme: String = regions[rid]["theme"]
		var bid: String = theme if rng.randf() < 0.7 else ids[rng.randi_range(0, ids.size() - 1)]
		var nid := "h_%d_%d" % [h.x, h.y]
		var d := _make_node(nid, bid, rng, h.x * 31 + h.y)
		d["hex"] = [h.x, h.y]
		regions[rid]["nodes"][nid] = d
		var pos := Hex.to_pixel(h, HEX_SIZE)
		positions[nid] = pos
		hex_of[nid] = h
		centers[rid] = (centers[rid] as Vector2) + pos
		count_of[rid] = int(count_of.get(rid, 0)) + 1
	for rid in region_ids:
		var n: int = maxi(int(count_of.get(rid, 0)), 1)
		centers[rid] = (centers[rid] as Vector2) / float(n)

	# 4) 邻接：六边形天然相邻，一律 1 天路程
	for nid in hex_of:
		var nd: Dictionary = _node_of(regions, nid)
		var adj := {}
		for nb in Hex.neighbors(hex_of[nid]):
			var nid2 := "h_%d_%d" % [nb.x, nb.y]
			if positions.has(nid2):
				adj[nid2] = 1
		nd["adjacent"] = adj

	# 5) 势力占据
	for nid in hex_of:
		if rng.randf() < OWNED_NODE_CHANCE:
			_node_of(regions, nid)["owner"] = _factions[rng.randi_range(0, _factions.size() - 1)]

	# 6) 选址：必须宽裕（否则「先繁荣再撞墙」会变成一开局就撞墙），且至少两个邻居
	var start := ""
	var best := -1e9
	for nid in hex_of:
		var d: Dictionary = _node_of(regions, nid)
		var cap := capacity_of(d)
		if cap < 15.5 or cap > 22.0:
			continue
		if (d["adjacent"] as Dictionary).size() < 2:
			continue
		var dist_center := float(Hex.distance(hex_of[nid], Vector2i.ZERO))
		var score := -absf(cap - 17.5) - dist_center * 0.35 + rng.randf_range(0.0, 0.6)
		if score > best:
			best = score
			start = nid
	if start == "":
		for nid in hex_of:
			if (_node_of(regions, nid)["adjacent"] as Dictionary).size() >= 1:
				start = nid
				break
	if start == "" and not hex_of.is_empty():
		start = hex_of.keys()[0]

	return {
		"seed": world_seed,
		"radius": radius,
		"hex_size": HEX_SIZE,
		"regions": regions,
		"positions": positions,
		"hex_of": hex_of,
		"region_centers": centers,
		"start_node": start,
		"node_count": hex_of.size(),
	}


static func _sector_of(h: Vector2i) -> int:
	var p := Hex.to_pixel(h, 1.0)
	var ang := atan2(p.y, p.x) + PI
	return int(floor(ang / (TAU / float(REGION_COUNT)))) % REGION_COUNT


static func capacity_of(d: Dictionary) -> float:
	return float(d.get("food_r", 0.0)) * float(d.get("food_K", 0.0)) / 4.0 \
		+ float(d.get("prey_r", 0.0)) * float(d.get("prey_K", 0.0)) / 8.0


static func _node_of(regions: Dictionary, nid: String) -> Dictionary:
	for rid in regions:
		var nodes: Dictionary = regions[rid]["nodes"]
		if nodes.has(nid):
			return nodes[nid]
	return {}


# --------------------------------------------------------------------------
# 节点生成
# --------------------------------------------------------------------------

static func _make_node(nid: String, biome_id: String, rng: RandomNumberGenerator, salt: int) -> Dictionary:
	var b: Dictionary = _biomes.get(biome_id, {})
	var cap_range: Array = b.get("capacity", [10, 16])
	var capacity := rng.randf_range(float(cap_range[0]), float(cap_range[1]))
	var share_range: Array = b.get("prey_share", [0.25, 0.45])
	var prey_share := rng.randf_range(float(share_range[0]), float(share_range[1]))

	# 承载力拆分：prey_share 指「承载力里有多少来自猎物」
	var prey_contrib := capacity * prey_share
	var food_msy := capacity - prey_contrib
	var prey_msy := prey_contrib * 2.0

	# 「大 K + 小 r」：K 取区间内的值，r 由 MSY 反推
	var food_K := rng.randf_range(NODE_K_FOOD[0], NODE_K_FOOD[1])
	var food_r := 4.0 * food_msy / food_K
	var prey_K := rng.randf_range(NODE_K_PREY[0], NODE_K_PREY[1])
	var prey_r := 8.0 * prey_contrib / prey_K

	var res: Dictionary = b.get("resources", {})
	var magic_range: Array = b.get("magic", [0.3, 0.5])
	var danger_range: Array = b.get("danger", [1, 3])
	var pool: Array = b.get("blood_pool", [])

	return {
		"name": _node_name(rng, salt),
		"biome": biome_id,
		"food_stock": round(food_K * rng.randf_range(0.55, 0.85)),
		"food_K": round(food_K), "food_r": food_r,
		"prey_stock": round(prey_K * rng.randf_range(0.45, 0.75)),
		"prey_K": round(prey_K), "prey_r": prey_r,
		"wood": _roll(res, "wood", rng),
		"stone": _roll(res, "stone", rng),
		"crystal": _roll(res, "crystal", rng),
		"herb": _roll(res, "herb", rng),
		"magic_density": rng.randf_range(float(magic_range[0]), float(magic_range[1])),
		"danger": rng.randi_range(int(danger_range[0]), int(danger_range[1])),
		"disaster_bias": b.get("disaster_bias", {}),
		"blood_pool": pool.duplicate(),
		"adjacent": {},
		"owner": null,
	}


static func _roll(res: Dictionary, key: String, rng: RandomNumberGenerator) -> float:
	if not res.has(key):
		return 0.0
	var r: Array = res[key]
	return round(rng.randf_range(float(r[0]), float(r[1])))


static func _node_name(rng: RandomNumberGenerator, salt: int) -> String:
	var p: String = _prefixes[absi(salt + rng.randi_range(0, 99)) % _prefixes.size()]
	var s: String = _suffixes[rng.randi_range(0, _suffixes.size() - 1)]
	return p + s
