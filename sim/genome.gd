class_name Genome
extends RefCounted
## 万形种的血脉基因组：血浓、区间、嵌合、遗传、突变。
##
## 本类**不依赖任何 Node**，可在 headless 下运行；也不依赖 Pedigree——
## 亲缘系数由调用方（Tribe）算好后作为参数传入，保证遗传规则可单独测试。
##
## 全部随机数走 static RNG，因此固定种子即可完全复现一局模拟。

# --- 阈值（文档 02.3 / 02.4）---
const TITER_EXPRESSED := 60      # 显征
const TITER_LATENT := 35         # 潜征 / 嵌合门槛
const TITER_HIDDEN := 15         # 隐没下限（1..14 为暗池）
const CHIMERA_MAX_DIFF := 15     # 嵌合允许的最大血浓差
const DILUTE_THRESHOLD := 40     # 触发混血稀释的「强血脉」门槛
const DILUTE_PENALTY := 3
const MAX_BLOODLINES := 6
const PURIFY_BONUS := 6          # 纯化加固
const ATAVISM_CHANCE := 0.15     # 暗池返祖概率

# --- 突变概率（文档 02.5）---
const MUT_NEW_BASE := 0.02
const MUT_NEW_PER_MAGIC := 0.08
const MUT_TIDE_MULT := 3.0
const MUT_SURGE_CHANCE := 0.03
const MUT_DEGRADE_CHANCE := 0.02
const MUT_ABERRANT_SHARE := 0.30

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 血浓区间编码，供 UI 与统计使用。
enum Band { NONE = 0, DARK = 1, HIDDEN = 2, LATENT = 3, EXPRESSED = 4 }

var titers: Dictionary = {}          # StringName -> int (1..100)
var inbreeding: float = 0.0          # 个体自身 F 系数
var defects: Array = []              # Array[StringName]
var beast_id: int = -1


static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s


static func from_titers(d: Dictionary) -> Genome:
	var g := Genome.new()
	for k in d:
		g.titers[StringName(k)] = clampi(int(d[k]), 0, 100)
	return g


func clone() -> Genome:
	var g := Genome.new()
	g.titers = titers.duplicate()
	g.inbreeding = inbreeding
	g.defects = defects.duplicate()
	g.beast_id = beast_id
	return g


# --------------------------------------------------------------------------
# 查询
# --------------------------------------------------------------------------

func band(bloodline: StringName) -> int:
	var t := int(titers.get(bloodline, 0))
	if t <= 0:
		return Band.NONE
	if t < TITER_HIDDEN:
		return Band.DARK
	if t < TITER_LATENT:
		return Band.HIDDEN
	if t < TITER_EXPRESSED:
		return Band.LATENT
	return Band.EXPRESSED


func expressed() -> Array:
	var out: Array = []
	for k in titers:
		if int(titers[k]) >= TITER_EXPRESSED:
			out.append(k)
	return out


func top_titer() -> int:
	var best := 0
	for k in titers:
		best = maxi(best, int(titers[k]))
	return best


func top_bloodline() -> StringName:
	var best_id: StringName = &""
	var best := -1
	for k in titers:
		var t := int(titers[k])
		if t > best:
			best = t
			best_id = k
	return best_id


## 按血浓降序排列的血脉 id。
func sorted_bloodlines() -> Array:
	var keys: Array = titers.keys()
	keys.sort_custom(func(x, y): return int(titers[x]) > int(titers[y]))
	return keys


## 达到指定血浓的血脉（默认按血浓降序）。
func strong_bloodlines(threshold: int = DILUTE_THRESHOLD) -> Array:
	var out: Array = []
	for k in sorted_bloodlines():
		if int(titers[k]) >= threshold:
			out.append(k)
	return out


func total_titer() -> int:
	var total := 0
	for k in titers:
		total += int(titers[k])
	return total


## 血脉稀薄：没有任何一条达到潜征门槛。
func is_dilute() -> bool:
	for k in titers:
		if int(titers[k]) >= TITER_LATENT:
			return false
	return true


## 实际触发的嵌合 id 列表（文档 02.4 的三条件）。
func chimeras() -> Array:
	var out: Array = []
	var keys: Array = titers.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var k1: StringName = keys[i]
			var k2: StringName = keys[j]
			var t1 := int(titers[k1])
			var t2 := int(titers[k2])
			if t1 < TITER_LATENT or t2 < TITER_LATENT:
				continue
			if absi(t1 - t2) > CHIMERA_MAX_DIFF:
				continue
			var ch := BloodlineDB.chimera_for(k1, k2)
			if not ch.is_empty():
				out.append(StringName(ch["id"]))
	return out


## 六维属性（基准 + 主属性系数 + 副属性系数）。
func attribute(attr: StringName) -> float:
	var total := BloodlineDB.base_attribute()
	for k in titers:
		var b := BloodlineDB.bloodline(k)
		if b.is_empty():
			continue
		var t := float(titers[k])
		if StringName(b.get("main", "")) == attr:
			total += t * BloodlineDB.main_coeff()
		if StringName(b.get("sub", "")) == attr:
			total += t * BloodlineDB.sub_coeff()
	return total


func attributes() -> Dictionary:
	var out := {}
	for a in ["body", "agility", "perception", "craft", "vitality", "spirit"]:
		out[StringName(a)] = attribute(StringName(a))
	return out


## 部落血脉多样性指数（辛普森）：1 − Σ(t_i/Σt)²
func diversity_contribution() -> Dictionary:
	var total := float(total_titer())
	var partial := 0.0
	for k in titers:
		var p := float(titers[k]) / maxf(total, 1.0)
		partial += p * p
	return {"total": total, "simpson": 1.0 - partial}


# --------------------------------------------------------------------------
# 遗传
# --------------------------------------------------------------------------

## 单条血脉的继承（文档 02.5）。kin 只影响日志，不参与血浓计算。
static func _inherit_one(ta: int, tb: int, magic: float) -> int:
	var lo := mini(ta, tb)
	var hi := maxi(ta, tb)

	# 返祖：父母任一方把这条血脉压在暗池区间
	if lo >= 1 and hi <= TITER_HIDDEN and rng.randf() < ATAVISM_CHANCE:
		return rng.randi_range(25, 45)

	var t := float(ta + tb) * 0.5
	if lo >= TITER_EXPRESSED:
		t += float(PURIFY_BONUS)                  # 纯化加固
	t += rng.randfn(0.0, 3.0 + 5.0 * magic)       # 随机扰动，σ 随魔力浓度上升
	return clampi(roundi(t), 0, 100)


## 混血稀释：父母各有一条 ≥40 的不同类群血脉 → 各自 −3（文档 02.5）。
static func _apply_dilution(child: Genome, a: Genome, b: Genome) -> void:
	var sa := a.strong_bloodlines(DILUTE_THRESHOLD)
	var sb := b.strong_bloodlines(DILUTE_THRESHOLD)
	if sa.is_empty() or sb.is_empty():
		return
	if BloodlineDB.clade_of(sa[0]) == BloodlineDB.clade_of(sb[0]):
		return
	for k in sa + sb:
		if child.titers.has(k):
			child.titers[k] = maxi(1, int(child.titers[k]) - DILUTE_PENALTY)


static func _random_key(d: Dictionary) -> StringName:
	var keys: Array = d.keys()
	return keys[rng.randi_range(0, keys.size() - 1)]


static func _apply_mutation(child: Genome, magic: float, pool: Array, magic_tide: bool = false) -> void:
	# 新增血脉
	var p_new := MUT_NEW_BASE + MUT_NEW_PER_MAGIC * magic
	if magic_tide:
		p_new *= MUT_TIDE_MULT
	if rng.randf() < p_new and not pool.is_empty():
		var n := 2 if rng.randf() < 0.25 else 1
		for _i in n:
			var bl: StringName = pool[rng.randi_range(0, pool.size() - 1)]
			child.titers[bl] = rng.randi_range(8, 25)

	if child.titers.is_empty():
		return

	# 血浓跃升
	if rng.randf() < MUT_SURGE_CHANCE:
		var k := _random_key(child.titers)
		child.titers[k] = mini(100, int(child.titers[k]) + rng.randi_range(15, 30))

	# 退化 / 异血
	if rng.randf() < MUT_DEGRADE_CHANCE:
		if rng.randf() < MUT_ABERRANT_SHARE:
			child.defects.append(&"aberrant")
		else:
			var k2 := _random_key(child.titers)
			child.titers[k2] = maxi(1, int(child.titers[k2]) - rng.randi_range(10, 25))


static func _trim_to_limit(child: Genome) -> void:
	if child.titers.size() <= MAX_BLOODLINES:
		return
	var ordered := child.sorted_bloodlines()
	for i in range(MAX_BLOODLINES, ordered.size()):
		child.titers.erase(ordered[i])


## 核心遗传函数。kin 由 Pedigree 算好（子代 F = φ(父,母)）。
static func breed(a: Genome, b: Genome, kin: float, magic: float,
		pool: Array, magic_tide: bool = false) -> Genome:
	BloodlineDB.ensure_loaded()
	var child := Genome.new()

	var keys := {}
	for k in a.titers:
		keys[k] = true
	for k in b.titers:
		keys[k] = true

	for k in keys:
		var ta := int(a.titers.get(k, 0))
		var tb := int(b.titers.get(k, 0))
		var t := _inherit_one(ta, tb, magic)
		if t > 0:
			child.titers[k] = t

	_apply_dilution(child, a, b)
	_apply_mutation(child, magic, pool, magic_tide)
	_trim_to_limit(child)

	child.inbreeding = clampf(kin, 0.0, 1.0)
	return child


## 子代血浓的确定性期望（不含噪声与突变），供谱系规划器与 AI 使用。
static func expected_titers(a: Genome, b: Genome) -> Dictionary:
	var out := {}
	var keys := {}
	for k in a.titers:
		keys[k] = true
	for k in b.titers:
		keys[k] = true
	for k in keys:
		var ta := int(a.titers.get(k, 0))
		var tb := int(b.titers.get(k, 0))
		var t := float(ta + tb) * 0.5
		if mini(ta, tb) >= TITER_EXPRESSED:
			t += float(PURIFY_BONUS)
		out[k] = t
	return out


## 对「期望血浓」做嵌合的软评分 0..1。完全满足条件得 1.0。
## slack 越大越宽容，代表玩家愿意赌一把的余量。
static func chimera_score(t_expected: Dictionary, slack: float = 6.0) -> float:
	var best := 0.0
	var keys: Array = t_expected.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var k1: StringName = keys[i]
			var k2: StringName = keys[j]
			if BloodlineDB.chimera_for(k1, k2).is_empty():
				continue
			var e1 := float(t_expected[k1])
			var e2 := float(t_expected[k2])
			var lo := float(TITER_LATENT) - slack
			var m1 := clampf((e1 - lo) / slack, 0.0, 1.0)
			var m2 := clampf((e2 - lo) / slack, 0.0, 1.0)
			var md := clampf(1.0 - absf(e1 - e2) / (float(CHIMERA_MAX_DIFF) + slack), 0.0, 1.0)
			best = maxf(best, m1 * m2 * md)
	return best


# --------------------------------------------------------------------------
# 存档
# --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var t := {}
	for k in titers:
		t[String(k)] = int(titers[k])
	var d: Array = []
	for x in defects:
		d.append(String(x))
	return {
		"titers": t,
		"inbreeding": inbreeding,
		"defects": d,
		"beast_id": beast_id,
	}


static func from_dict(d: Dictionary) -> Genome:
	var g := Genome.new()
	var t: Dictionary = d.get("titers", {})
	for k in t:
		g.titers[StringName(k)] = int(t[k])
	g.inbreeding = float(d.get("inbreeding", 0.0))
	for x in d.get("defects", []):
		g.defects.append(StringName(x))
	g.beast_id = int(d.get("beast_id", -1))
	return g


func describe() -> String:
	var parts: Array = []
	for k in sorted_bloodlines():
		parts.append("%s%d" % [BloodlineDB.bloodline_name(k), int(titers[k])])
	return "%s  [F=%.3f]%s" % [
		" / ".join(parts),
		inbreeding,
		("  嵌合:" + ", ".join(chimeras().map(func(c): return BloodlineDB.chimera_name(c)))) if not chimeras().is_empty() else "",
	]
