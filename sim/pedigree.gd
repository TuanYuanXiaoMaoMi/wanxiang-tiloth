class_name Pedigree
extends RefCounted
## 谱系与亲缘系数（Wright's coefficient of kinship φ）。
##
## 这是文档 07 里标注为「最需要尽早替换」的那一处近似实现的正解。
## 使用标准递推：
##   φ(a,a) = 0.5 * (1 + F_a)
##   φ(a,b) = 0.5 * (φ(父_a, b) + φ(母_a, b))     （a 取更年轻的一方）
##   F_c    = φ(父_c, 母_c)
## 递推带记忆化，因此不会指数爆炸。
##
## 已知正确值（tools/run_tests.gd 会验证）：
##   父女 = 0.25   全同胞 = 0.25   半同胞 = 0.125   表亲 = 0.0625   无血缘 = 0

## 超过这个世代深度就按无血缘处理（谱系截断）。
## 这是性能与精度的取舍：截断会**低估**长期封闭种群的 F。
## 默认 40 足够覆盖本作 8–12 代的世代跨度。
var max_depth: int = 40

var _fathers: Dictionary = {}     # int -> int (-1 = 奠基者)
var _mothers: Dictionary = {}     # int -> int
var _f_values: Dictionary = {}    # int -> float  个体自身的近交系数 F
var _cache: Dictionary = {}       # "min|max" -> float
var _calls: int = 0


## 序列化父系表与各自的近交系数。
## `_cache` 不存 —— 它是纯缓存，读档后重算即可（而且存了反而可能读到脏值）。
func to_save() -> Dictionary:
	return {
		"fathers": _fathers.duplicate(),
		"mothers": _mothers.duplicate(),
		"f_values": _f_values.duplicate(),
		"max_depth": max_depth,
	}


func load_save(d: Dictionary) -> void:
	_fathers = (d.get("fathers", {}) as Dictionary).duplicate()
	_mothers = (d.get("mothers", {}) as Dictionary).duplicate()
	_f_values = (d.get("f_values", {}) as Dictionary).duplicate()
	max_depth = int(d.get("max_depth", 40))
	_cache.clear()
	_calls = 0


func add(id: int, father: int, mother: int, f_value: float) -> void:
	_fathers[id] = father
	_mothers[id] = mother
	_f_values[id] = f_value


func inbreeding_of(id: int) -> float:
	return float(_f_values.get(id, 0.0))


func father_of(id: int) -> int:
	return int(_fathers.get(id, -1))


func mother_of(id: int) -> int:
	return int(_mothers.get(id, -1))


func size() -> int:
	return _fathers.size()


func call_count() -> int:
	return _calls


func clear_cache() -> void:
	_cache.clear()
	_calls = 0


## 亲缘系数 φ(a,b)。用于计算子代近交系数与配对评分。
func kinship(a: int, b: int) -> float:
	if a < 0 or b < 0:
		return 0.0
	_calls += 1
	return _kinship(a, b, 0)


func _kinship(a: int, b: int, depth: int) -> float:
	if a < 0 or b < 0:
		return 0.0
	if depth > max_depth:
		return 0.0
	if a == b:
		return 0.5 * (1.0 + float(_f_values.get(a, 0.0)))

	# 让 a 始终是更年轻的一方（id 递增 = 出生更晚），保证递推朝向祖先收敛
	if a < b:
		var t := a
		a = b
		b = t

	var key := "%d|%d" % [b, a]
	if _cache.has(key):
		return _cache[key]

	var fa := father_of(a)
	var ma := mother_of(a)
	var v := 0.0
	if fa < 0 and ma < 0:
		v = 0.0            # a 是奠基者，与任何非自身个体无血缘
	else:
		v = 0.5 * (_kinship(fa, b, depth + 1) + _kinship(ma, b, depth + 1))

	_cache[key] = v
	return v


## 子代近交系数 F_child = φ(父, 母)。
func offspring_inbreeding(father: int, mother: int) -> float:
	if father < 0 or mother < 0:
		return 0.0
	return clampf(kinship(father, mother), 0.0, 1.0)


func stats() -> Dictionary:
	var f_values: Array = _f_values.values()
	var total := 0.0
	for v in f_values:
		total += float(v)
	return {
		"individuals": _f_values.size(),
		"cache_entries": _cache.size(),
		"mean_inbreeding": (total / float(f_values.size())) if f_values.size() > 0 else 0.0,
	}
