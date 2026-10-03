class_name RegionDB
extends RefCounted
## 区域节点定义库。数据来自 res://data/regions.json。
##
##   RegionDB.ensure_loaded()
##   var r := RegionDB.make(&"gt_ashwater")     # 得到一个全新的 Region 实例
##   RegionDB.node_ids()                        # 全部节点 id
##   RegionDB.region_of_node(&"gt_ashwater")    # -> &"green_throat"

const DEFAULT_PATH := "res://data/regions.json"

static var _loaded: bool = false
static var _load_error: String = ""
static var _regions: Dictionary = {}        # StringName -> {name, nodes:{...}}
static var _node_index: Dictionary = {}     # StringName -> {region, data}
static var _seasonal_gather: Array = [1.0, 1.15, 1.3, 0.35]
static var _seasonal_growth: Array = [1.0, 1.2, 0.8, 0.1]
static var _positions: Dictionary = {}       # StringName -> Vector2（仅生成的大陆有）
static var _region_centers: Dictionary = {}
static var _generated: bool = false
static var _start_node: StringName = &""
static var _hex_of: Dictionary = {}          # StringName -> Vector2i（六边形坐标）
static var _hex_size: float = 100.0
static var _world_seed: int = 0 


## 载入一张生成出来的大陆（肉鸽模式）。会覆盖静态 JSON 的内容。
static func load_world(world: Dictionary) -> bool:
	if world.is_empty() or not world.has("regions"):
		return false
	_load_error = ""
	_regions.clear()
	_node_index.clear()
	_positions.clear()
	_region_centers.clear()
	for rid in world["regions"]:
		var rkey := StringName(rid)
		var r: Dictionary = world["regions"][rid]
		_regions[rkey] = {"name": r.get("name", String(rid)), "nodes": r.get("nodes", {})}
		for nid in (r.get("nodes", {}) as Dictionary):
			_node_index[StringName(nid)] = {"region": rkey, "data": r["nodes"][nid]}
	for nid in world.get("positions", {}):
		_positions[StringName(nid)] = world["positions"][nid]
	for rid in world.get("region_centers", {}):
		_region_centers[StringName(rid)] = world["region_centers"][rid]
	_hex_of.clear()
	for nid in world.get("hex_of", {}):
		_hex_of[StringName(nid)] = world["hex_of"][nid]
	_hex_size = float(world.get("hex_size", 100.0))
	_world_seed = int(world.get("seed", 0))
	_start_node = StringName(world.get("start_node", ""))
	_generated = true
	_loaded = true
	return true


static func hex_of(node_id: StringName) -> Vector2i:
	return _hex_of.get(node_id, Vector2i.ZERO)


static func hex_size() -> float:
	return _hex_size


static func world_seed() -> int:
	return _world_seed


## 从某点出发、恰好隔了 n 天路程的所有节点（BFS，用于地图上高亮可达范围）。
static func reachable_within(from_id: StringName, max_days: int) -> Dictionary:
	var out: Dictionary = {}
	var seen := {from_id: 0}
	var frontier: Array = [from_id]
	while not frontier.is_empty():
		var next: Array = []
		for cur in frontier:
			var cost: int = int(seen[cur])
			for nb in neighbors(cur):
				var nc := cost + int(neighbors(cur)[nb])
				if nc <= max_days and (not seen.has(nb) or int(seen[nb]) > nc):
					seen[nb] = nc
					out[nb] = nc
					next.append(nb)
		frontier = next
	return out


static func is_generated() -> bool:
	return _generated


static func start_node() -> StringName:
	return _start_node


static func node_position(node_id: StringName) -> Vector2:
	return _positions.get(node_id, Vector2.ZERO)


static func region_center(region_id: StringName) -> Vector2:
	return _region_centers.get(region_id, Vector2.ZERO)


static func ensure_loaded(path: String = DEFAULT_PATH) -> bool:
	if _loaded:
		return true
	if _load_error != "":
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_load_error = "无法打开区域数据：%s" % path
		push_error("RegionDB: " + _load_error)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "区域数据 JSON 解析失败：%s" % path
		push_error("RegionDB: " + _load_error)
		return false

	var root: Dictionary = parsed
	var sg: Array = root.get("seasonal_gather", [])
	var sgr: Array = root.get("seasonal_growth", [])
	if sg.size() == 4:
		_seasonal_gather = sg
	if sgr.size() == 4:
		_seasonal_growth = sgr

	var raw: Dictionary = root.get("regions", {})
	for rid in raw:
		var rkey := StringName(rid)
		var rdata: Dictionary = raw[rid]
		_regions[rkey] = rdata
		var nodes: Dictionary = rdata.get("nodes", {})
		for nid in nodes:
			_node_index[StringName(nid)] = {"region": rkey, "data": nodes[nid]}

	_loaded = true
	return true


static func load_error() -> String:
	return _load_error


static func region_ids() -> Array:
	return _regions.keys()


static func node_ids() -> Array:
	return _node_index.keys()


static func region_name(region_id: StringName) -> String:
	var r: Dictionary = _regions.get(region_id, {})
	return String(r.get("name", String(region_id)))


static func region_of_node(node_id: StringName) -> StringName:
	var e: Dictionary = _node_index.get(node_id, {})
	return e.get("region", &"")


static func node_data(node_id: StringName) -> Dictionary:
	var e: Dictionary = _node_index.get(node_id, {})
	return e.get("data", {})


static func has_node(node_id: StringName) -> bool:
	return _node_index.has(node_id)


static func nodes_in_region(region_id: StringName) -> Array:
	var r: Dictionary = _regions.get(region_id, {})
	var out: Array = []
	for nid in r.get("nodes", {}):
		out.append(StringName(nid))
	return out


static func node_display_name(node_id: StringName) -> String:
	var d := node_data(node_id)
	return String(d.get("name", String(node_id)))


## 造一个全新的 Region 实例（每次调用都是独立状态）。
static func make(node_id: StringName) -> Region:
	ensure_loaded()
	if not _node_index.has(node_id):
		push_error("RegionDB: 未知节点 %s" % node_id)
		return null
	var r := Region.from_dict(node_data(node_id), node_id)
	r.region_id = region_of_node(node_id)
	r.set_seasonal_tables(_seasonal_gather, _seasonal_growth)
	return r


## 从当前节点出发，沿邻接边可直接抵达的节点（含旅途天数）。
static func neighbors(node_id: StringName) -> Dictionary:
	var d := node_data(node_id)
	var out: Dictionary = {}
	for k in d.get("adjacent", {}):
		out[StringName(k)] = int(d["adjacent"][k])
	return out


## 最短路径的节点序列（不含起点，含终点）。用 BFS，边权为 1 格 = 1 回合。
static func path_to(from_id: StringName, to_id: StringName) -> Array:
	if from_id == to_id or not has_node(from_id) or not has_node(to_id):
		return []
	var prev := {from_id: &""}
	var frontier: Array = [from_id]
	while not frontier.is_empty():
		var next: Array = []
		for cur in frontier:
			for nb in neighbors(cur):
				if prev.has(nb):
					continue
				prev[nb] = cur
				if nb == to_id:
					var path: Array = [nb]
					var walk: StringName = cur
					while walk != from_id and walk != &"":
						path.push_front(walk)
						walk = prev.get(walk, &"")
					return path
				next.append(nb)
		frontier = next
	return []


## 广度优先求两点间最短旅途天数（-1 表示不可达）。
static func travel_days(from_id: StringName, to_id: StringName) -> int:
	if from_id == to_id:
		return 0
	var seen := {from_id: true}
	var frontier: Array = [[from_id, 0]]
	while not frontier.is_empty():
		var next: Array = []
		for item in frontier:
			var cur: StringName = item[0]
			var cost: int = item[1]
			for nb in neighbors(cur):
				if nb == to_id:
					return cost + int(neighbors(cur)[nb])
				if not seen.has(nb):
					seen[nb] = true
					next.append([nb, cost + int(neighbors(cur)[nb])])
		frontier = next
	return -1
