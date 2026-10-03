class_name BloodlineDB
extends RefCounted
## 血脉 / 类群 / 嵌合 / 区域 的静态定义库。
## 数据全部来自 res://data/genetics.json —— sim 层不硬编码任何血脉数值。
##
## 用法：
##   BloodlineDB.ensure_loaded()
##   BloodlineDB.clade_of(&"fel_cat")            -> &"shadow"
##   BloodlineDB.chimera_for(&"fel_cat", &"acc_hawk")  -> {"id": "chimera_sky_hunter", ...}

const DEFAULT_PATH := "res://data/genetics.json"

static var _loaded: bool = false
static var _load_error: String = ""

static var _clades: Dictionary = {}            # StringName -> Dictionary
static var _bloodlines: Dictionary = {}        # StringName -> Dictionary
static var _clade_of: Dictionary = {}          # StringName -> StringName
static var _clade_members: Dictionary = {}     # StringName -> Array[StringName]
static var _chimera_by_pair: Dictionary = {}   # "cladeA|cladeB" -> Dictionary
static var _chimera_by_id: Dictionary = {}     # StringName -> Dictionary
static var _bloodline_ids: Array = []          # Array[StringName]
static var _clade_ids: Array = []              # Array[StringName]
static var _regions: Dictionary = {}           # StringName -> Dictionary

static var _main_coeff: float = 0.30
static var _sub_coeff: float = 0.12
static var _base_attribute: float = 10.0


static func ensure_loaded(path: String = DEFAULT_PATH) -> bool:
	if _loaded:
		return true
	if _load_error != "":
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_load_error = "无法打开数据文件：%s" % path
		push_error("BloodlineDB: " + _load_error)
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "JSON 解析失败：%s" % path
		push_error("BloodlineDB: " + _load_error)
		return false
	var root: Dictionary = parsed

	_main_coeff = float(root.get("main_coeff", 0.30))
	_sub_coeff = float(root.get("sub_coeff", 0.12))
	_base_attribute = float(root.get("base_attribute", 10))

	# --- 类群 ---
	var raw_clades: Dictionary = root.get("clades", {})
	for cid in raw_clades:
		var key := StringName(cid)
		var c: Dictionary = raw_clades[cid]
		_clades[key] = c
		_clade_ids.append(key)
		var members: Array = []
		for b in c.get("bloodlines", []):
			members.append(StringName(b))
		_clade_members[key] = members

	# --- 血脉 ---
	var raw_bl: Dictionary = root.get("bloodlines", {})
	for bid in raw_bl:
		var key := StringName(bid)
		var b: Dictionary = raw_bl[bid]
		var clade := StringName(b.get("clade", ""))
		if not _clades.has(clade):
			push_error("BloodlineDB: 血脉 %s 引用了不存在的类群 %s" % [bid, clade])
			continue
		_bloodlines[key] = b
		_clade_of[key] = clade
		_bloodline_ids.append(key)

	# --- 嵌合 ---
	for raw in root.get("chimeras", []):
		var ch: Dictionary = raw
		var pair: Array = ch.get("clades", [])
		if pair.size() != 2:
			push_error("BloodlineDB: 嵌合 %s 的 clades 字段必须恰好两项" % ch.get("id", "?"))
			continue
		var ca := StringName(pair[0])
		var cb := StringName(pair[1])
		if not _clades.has(ca) or not _clades.has(cb) or ca == cb:
			push_error("BloodlineDB: 嵌合 %s 的类群对不合法" % ch.get("id", "?"))
			continue
		var id := StringName(ch.get("id", ""))
		_chimera_by_id[id] = ch
		_chimera_by_pair[pair_key(ca, cb)] = ch

	# --- 区域 ---
	var raw_regions: Dictionary = root.get("regions", {})
	for rid in raw_regions:
		_regions[StringName(rid)] = raw_regions[rid]

	_loaded = true
	return true


static func load_error() -> String:
	return _load_error


## 排序后的类群对 key，保证 (a,b) 与 (b,a) 命中同一条目。
static func pair_key(a: StringName, b: StringName) -> String:
	var x := String(a)
	var y := String(b)
	if x > y:
		var t := x
		x = y
		y = t
	return x + "|" + y


static func clade_of(bloodline: StringName) -> StringName:
	return _clade_of.get(bloodline, &"")


static func clade_name(clade: StringName) -> String:
	var c: Dictionary = _clades.get(clade, {})
	return String(c.get("name", String(clade)))


static func bloodline_name(bloodline: StringName) -> String:
	var b: Dictionary = _bloodlines.get(bloodline, {})
	return String(b.get("name", String(bloodline)))


static func bloodline(bloodline: StringName) -> Dictionary:
	return _bloodlines.get(bloodline, {})


static func clade_ids() -> Array:
	return _clade_ids.duplicate()


static func bloodline_ids() -> Array:
	return _bloodline_ids.duplicate()


static func chimera_by_id(id: StringName) -> Dictionary:
	return _chimera_by_id.get(id, {})


static func chimera_name(id: StringName) -> String:
	var c: Dictionary = _chimera_by_id.get(id, {})
	return String(c.get("name", String(id)))


## 两条血脉是否构成嵌合（不同类群且该对已定义）。血浓门槛由 Genome 负责判定。
static func chimera_for(a: StringName, b: StringName) -> Dictionary:
	var ca := clade_of(a)
	var cb := clade_of(b)
	if ca == &"" or cb == &"" or ca == cb:
		return {}
	return _chimera_by_pair.get(pair_key(ca, cb), {})


static func chimera_count() -> int:
	return _chimera_by_id.size()


static func region(region_id: StringName) -> Dictionary:
	return _regions.get(region_id, {})


static func region_pool(region_id: StringName) -> Array:
	var r: Dictionary = _regions.get(region_id, {})
	var out: Array = []
	for b in r.get("pool", []):
		out.append(StringName(b))
	return out


static func region_magic(region_id: StringName) -> float:
	var r: Dictionary = _regions.get(region_id, {})
	return float(r.get("magic_density", 0.35))


static func main_coeff() -> float:
	return _main_coeff


static func sub_coeff() -> float:
	return _sub_coeff


static func base_attribute() -> float:
	return _base_attribute
