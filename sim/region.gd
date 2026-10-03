class_name Region
extends RefCounted
## 一个区域节点。承载本作的核心压力源：**可再生资源会枯竭，而且枯竭是永久的。**
##
## 模型（文档 04.2）：
##   食物（可再生，会崩溃）
##     Stock ← Stock + r·Stock·(1 − Stock/K) − Harvest
##     Stock < 0.2K → 采集效率 ×0.5，并累积退化计时器
##     退化计时器满 30 天 → **K 永久 ×0.7**
##   猎物种群（独立的第二层压力，再生更慢、没有缓冲）
##     prey < 0.15·prey_K → 触发猎物迁徙，产出 ×0.3 持续 60 天
##
## 不可再生资源（木/石/魔晶/药材）只减不增，所以每个节点都有「开采寿命」。
## 建造大型设施等于把资源永久钉死在这片土地上——迁徙时建筑归零，这就是沉没成本。

# --- 每人每日基础产出（食物单位）---
const GATHER_RATE := 1.5
const HUNT_RATE := 3.0            ## 2.5× 采集。这个差距是设计上的**诱惑**

# --- 效率惩罚门槛 ---
const FOOD_LOW_RATIO := 0.2
const FOOD_LOW_PENALTY := 0.5
const PREY_LOW_RATIO := 0.15
const PREY_LOW_PENALTY := 0.3

# --- 永久退化 ---
const DEGRADE_DAYS := 30
const DEGRADE_K_FACTOR := 0.7

# --- 猎物迁徙事件 ---
const PREY_MIGRATION_DAYS := 60
const PREY_MIGRATION_FACTOR := 0.3

# --- 季节（30 天/季，春 夏 秋 冬）---
const DAYS_PER_SEASON := 30
const SEASON_DAYS := 120

var id: StringName = &""
var name: String = ""
var biome: String = ""
var region_id: StringName = &""

# 可再生存量
var food_stock: float = 0.0
var food_K: float = 0.0
var food_r: float = 0.0
var prey_stock: float = 0.0
var prey_K: float = 0.0
var prey_r: float = 0.0

# 不可再生存量
var wood: float = 0.0
var stone: float = 0.0
var crystal: float = 0.0
var herb: float = 0.0

var magic_density: float = 0.35
var danger: int = 0
var disaster_bias: Dictionary = {}
var blood_pool: Array = []
var adjacent: Dictionary = {}          # StringName -> 旅途天数
var owner: StringName = &""

# 运行时状态
var day: int = 0
var low_stock_days: int = 0
var degraded: bool = false
var prey_migration_left: int = 0
var empty_days: int = 0                # food_stock 归零的连续天数
var history: Array = []

var seasonal_gather: Array = [1.0, 1.15, 1.3, 0.35]
var seasonal_growth: Array = [1.0, 1.2, 0.8, 0.1]

var _warned_low_food := false
var _warned_low_prey := false


static func from_dict(d: Dictionary, node_id: StringName = &"") -> Region:
	var r := Region.new()
	r.id = node_id
	r.name = String(d.get("name", String(node_id)))
	r.biome = String(d.get("biome", "unknown"))
	r.food_stock = float(d.get("food_stock", 0))
	r.food_K = float(d.get("food_K", 1))
	r.food_r = float(d.get("food_r", 0.02))
	r.prey_stock = float(d.get("prey_stock", 0))
	r.prey_K = float(d.get("prey_K", 1))
	r.prey_r = float(d.get("prey_r", 0.05))
	r.wood = float(d.get("wood", 0))
	r.stone = float(d.get("stone", 0))
	r.crystal = float(d.get("crystal", 0))
	r.herb = float(d.get("herb", 0))
	r.magic_density = float(d.get("magic_density", 0.35))
	r.danger = int(d.get("danger", 0))
	r.disaster_bias = d.get("disaster_bias", {})
	for b in d.get("blood_pool", []):
		r.blood_pool.append(StringName(b))
	for k in d.get("adjacent", {}):
		r.adjacent[StringName(k)] = int(d["adjacent"][k])
	if d.get("owner", null) != null:
		r.owner = StringName(d["owner"])
	return r


func set_seasonal_tables(gather: Array, growth: Array) -> void:
	if gather.size() == 4:
		seasonal_gather = gather
	if growth.size() == 4:
		seasonal_growth = growth


func season() -> int:
	return (day / DAYS_PER_SEASON) % 4


func season_name() -> String:
	return ["春", "夏", "秋", "冬"][season()]


## 当前季节的采集倍率（世界状态用它来算「要采到目标产量需要多少工时」）。
func gather_mult() -> float:
	return seasonal_gather[season()]


func growth_mult() -> float:
	return seasonal_growth[season()]


# --------------------------------------------------------------------------
# 分析用：最大可持续产量
# --------------------------------------------------------------------------

## 逻辑斯蒂曲线的最大可持续产量 = r·K/4（在 Stock = K/2 处取得）。
func food_msy() -> float:
	return food_r * food_K * 0.25


func prey_msy() -> float:
	return prey_r * prey_K * 0.25


## 该节点在不破坏存量的前提下，最多能长期养活多少兽人（每天 1 单位/人）。
## 采集与狩猎分别有各自的 MSY，不能简单相加——两者受不同上限约束，
## 这里是「保守估计」：取采集 MSY 全用 + 狩猎 MSY 的一半（狩猎要留种群余地）。
func carrying_capacity_adults() -> float:
	return food_msy() + prey_msy() * 0.5


func food_ratio() -> float:
	return food_stock / maxf(food_K, 1.0)


func prey_ratio() -> float:
	return prey_stock / maxf(prey_K, 1.0)


## 当前是否已经进入「不迁徙就会永久损失」的阶段。
func is_at_risk() -> bool:
	return food_ratio() < FOOD_LOW_RATIO or prey_ratio() < PREY_LOW_RATIO


# --------------------------------------------------------------------------
# 日推进
# --------------------------------------------------------------------------

## gatherers / hunters：投入采集与狩猎的人数（可为小数，代表工时折算）。
## 返回本日的产出明细。
## 运行时状态的快照。定义（名称/承载力/邻接）来自世界数据，不必存；
## 但**存量与退化进度是这一局的真实历史**，必须存。
func to_save() -> Dictionary:
	return {
		"food_stock": food_stock, "prey_stock": prey_stock,
		"wood": wood, "stone": stone, "crystal": crystal, "herb": herb,
		"day": day, "low_stock_days": low_stock_days,
	}


func load_save(d: Dictionary) -> void:
	food_stock = float(d.get("food_stock", food_stock))
	prey_stock = float(d.get("prey_stock", prey_stock))
	wood = float(d.get("wood", wood))
	stone = float(d.get("stone", stone))
	crystal = float(d.get("crystal", crystal))
	herb = float(d.get("herb", herb))
	day = int(d.get("day", 0))
	low_stock_days = int(d.get("low_stock_days", 0))


func step_day(gatherers: float, hunters: float) -> Dictionary:
	# 注意：`day += 1` 刻意放在函数**末尾**。
	# 若在这里自增，同一 tick 内 WorldState.allocate_labor() 会用「第 N-1 天的季节」
	# 去算需要多少采集工，而这里却用「第 N 天的季节」结算产出 —— 在季节交界处
	# （冬 ×0.45 → 春 ×1.0）产出能翻一倍多，土地会被季节性超采掏空。
	var s := season()
	var g_mult: float = seasonal_gather[s]
	var r_mult: float = seasonal_growth[s]

	# 1) 再生（逻辑斯蒂）
	var food_growth := food_r * r_mult * food_stock * (1.0 - food_stock / maxf(food_K, 1.0))
	if food_stock > 0.0:
		food_stock += food_growth
	else:
		food_growth = 0.0

	var prey_growth := prey_r * r_mult * prey_stock * (1.0 - prey_stock / maxf(prey_K, 1.0))
	if prey_stock > 0.0:
		prey_stock += prey_growth
	else:
		prey_growth = 0.0

	# 2) 采集
	var food_eff := 1.0
	if food_ratio() < FOOD_LOW_RATIO:
		food_eff = FOOD_LOW_PENALTY
	var gathered := gatherers * GATHER_RATE * g_mult * food_eff
	gathered = minf(gathered, maxf(food_stock, 0.0))
	food_stock = maxf(food_stock - gathered, 0.0)

	# 3) 狩猎（受猎物迁徙事件压制）
	var prey_eff := 1.0
	if prey_ratio() < PREY_LOW_RATIO:
		prey_eff = PREY_LOW_PENALTY
	if prey_migration_left > 0:
		prey_eff *= PREY_MIGRATION_FACTOR
		prey_migration_left -= 1
	var hunted := hunters * HUNT_RATE * prey_eff
	hunted = minf(hunted, maxf(prey_stock, 0.0))
	prey_stock = maxf(prey_stock - hunted, 0.0)

	# 4) 生态退化：长期低存量 → K 永久下降
	var events: Array = []
	if food_ratio() < FOOD_LOW_RATIO:
		low_stock_days += 1
		if not _warned_low_food:
			_warned_low_food = true
			events.append({"type": "warn_low_food"})
	else:
		low_stock_days = maxi(0, low_stock_days - 1)
		_warned_low_food = false

	if low_stock_days >= DEGRADE_DAYS and not degraded:
		food_K *= DEGRADE_K_FACTOR
		degraded = true
		events.append({"type": "ecological_collapse", "new_K": food_K})

	# 5) 猎物迁徙事件
	if prey_ratio() < PREY_LOW_RATIO:
		if not _warned_low_prey:
			_warned_low_prey = true
			events.append({"type": "warn_low_prey"})
		if prey_migration_left <= 0:
			prey_migration_left = PREY_MIGRATION_DAYS
			events.append({"type": "prey_migration"})
	else:
		_warned_low_prey = false

	# 6) 彻底空掉
	if food_stock <= 0.01:
		empty_days += 1
	else:
		empty_days = 0

	day += 1
	return {
		"gathered": gathered,
		"hunted": hunted,
		"total_food": gathered + hunted,
		"food_growth": food_growth,
		"prey_growth": prey_growth,
		"food_stock": food_stock,
		"prey_stock": prey_stock,
		"food_ratio": food_ratio(),
		"prey_ratio": prey_ratio(),
		"low_stock_days": low_stock_days,
		"degraded": degraded,
		"prey_migration_left": prey_migration_left,
		"events": events,
	}


# --------------------------------------------------------------------------
# 不可再生资源
# --------------------------------------------------------------------------

func extract(kind: StringName, amount: float) -> float:
	var have := 0.0
	match kind:
		&"wood": have = wood
		&"stone": have = stone
		&"crystal": have = crystal
		&"herb": have = herb
	var taken := minf(amount, have)
	match kind:
		&"wood": wood -= taken
		&"stone": stone -= taken
		&"crystal": crystal -= taken
		&"herb": herb -= taken
	return taken


# --------------------------------------------------------------------------
# 诊断
# --------------------------------------------------------------------------

func metrics() -> Dictionary:
	return {
		"day": day,
		"season": season_name(),
		"food_stock": food_stock,
		"food_K": food_K,
		"food_ratio": food_ratio(),
		"prey_stock": prey_stock,
		"prey_ratio": prey_ratio(),
		"food_msy": food_msy(),
		"prey_msy": prey_msy(),
		"capacity": carrying_capacity_adults(),
		"degraded": degraded,
		"low_stock_days": low_stock_days,
		"empty_days": empty_days,
		"prey_migration_left": prey_migration_left,
	}


func snapshot() -> String:
	return "%s 第%d天(%s) 食物 %4.0f/%4.0f (%.0f%%) 猎物 %3.0f/%3.0f (%.0f%%) 承载力≈%.1f人%s%s" % [
		name, day, season_name(),
		food_stock, food_K, food_ratio() * 100.0,
		prey_stock, prey_K, prey_ratio() * 100.0,
		carrying_capacity_adults(),
		"  [已退化]" if degraded else "",
		"  [猎物迁徙中 %d 天]" % prey_migration_left if prey_migration_left > 0 else "",
	]
