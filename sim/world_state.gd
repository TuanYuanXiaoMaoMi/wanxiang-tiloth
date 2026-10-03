class_name WorldState
extends RefCounted
## M1 垂直切片的完整可玩循环：**一个部落 + 它脚下的区域节点 + 食物仓 + 饱食度 + 日历。**
##
## 这个类的作用是把三个系统接起来，让「资源枯竭」真的能杀死人、真的能逼出迁徙：
##   Region  （土地：可再生资源会枯竭，且枯竭是永久的）
##   Tribe   （人：繁衍、近交、世代更替）
##   WorldState（日历、食物仓、饱食、饥饿致死、迁徙）
##
## 时间尺度（文档 06.1）：1 游戏日 = 2 秒现实时间（1x 档）。

## 日历（与文档 06.1 一致）：1 季 = 30 日，1 年 = 4 季 = **120 日**。
## 这同时给了「1 游戏年 = 4 现实分钟 @1x」的换算（120 日 × 2 秒 = 240 秒）。
## 注意：早期版本这里写成 365，与季节系统（30 日/季）自相矛盾 —— 一年会跑 12 个季节。
const DAYS_PER_YEAR := 120
const DAYS_PER_SEASON := 30
const SEASONS_PER_YEAR := 4
const FOOD_PER_PERSON_DAY := 1.0     ## 含幼崽
const GRANARY_CAP_PER_PERSON := 60.0
const SATIETY_RECOVER_PER_DAY := 0.6
const SATIETY_CRISIS := 40.0         ## 低于此值开始出现饥饿减员
const SATIETY_FULL_WORK := 70.0      ## 饱食度低于此值就开始削弱劳动产出
const SATIETY_MIN_WORK := 0.4        ## 饿到极点也还能挤出四成产出
const STARVE_DEBT_PER_DAY := 0.25    ## satiety 归零时每天累积多少「死亡债」
const REAL_SECONDS_PER_DAY_1X := 2.0

# --- 回合制 ---
## 一回合 = 一季 = 30 天。**回合制不是把模拟粒度变粗，而是在日结算外面套一层决策边界** ——
## 所以 docs/11 标定的「第 24 分钟被迫迁徙」直接平移成「第 24 回合」，数值零返工。
const DAYS_PER_TURN := 30
## 在途每人每日的采集产出。比扎营时低得多：没有工作点、没有猎场、还要搬运家当。
const TRANSIT_FORAGE_RATE := 0.55

# --- 非食物资源的每人每日采集速率 ---
const EXTRACT_WOOD := 2.0
const EXTRACT_STONE := 1.5
const EXTRACT_CRYSTAL := 0.6
const EXTRACT_HERB := 1.0

# --- 信仰与士气 ---
const FAITH_MAX := 100.0
const FAITH_PER_DAY := 0.45
const MORALE_RECOVER_PER_DAY := 0.35

# --- 三种配对 ---
const REST_CONCEPTION_CHANCE := 0.16      ## 休息所里每日受孕概率（自然约 0.05）
const FORCE_PAIR_CHANCE := 0.90           ## 法术强制结合
const FORCE_PAIR_FAITH := 35.0            ## 消耗信仰
const FORCE_PAIR_MORALE_COST := 14.0      ## 士气代价：族人看着呢


var tribe: Tribe = null
var region: Region = null
var day: int = 0
var food_store: float = 0.0
var satiety: float = 100.0
var hunt_ratio: float = 0.0          ## 0..1，投入狩猎的成年劳动力比例
var policy: int = Tribe.Policy.AVOID_INBREEDING
var gene_flow_per_year: float = 0.0
var camp_capacity: int = 24
var extinct: bool = false

var site_map: SiteMap = null
var assignments: Dictionary = {}     # beast_id -> site_id（-1 = 未指派）
var auto_assign: bool = true         ## 自动派工；玩家手动指派后该人不再被自动改动
## 狩猎倾向：1.0 = 严格按可持续产量分配；>1 = 超额打猎（猎物会崩，见 docs/11.3）
var hunt_bias: float = 1.0
# --------------------------------------------------------------------------
# 知识树
# --------------------------------------------------------------------------
var known: Dictionary = {}          ## 已发现（触发条件满足）
var adopted: Dictionary = {}        ## 已采纳（生效）
var stats: Dictionary = {}          ## 触发条件用的计数器
var new_discoveries: Array = []     ## 本回合新发现的，供界面提示
var last_gathered: float = 0.0
var last_hunted: float = 0.0
var faith: float = 30.0              ## 祖灵的信仰值：法术与仪式的货币
var morale: float = 80.0             ## 士气：法术强制配对的代价记在这里
var forced_pairs: int = 0

var turn: int = 0
# --- 在途状态：迁徙途中不能采集工作点、不能配对，但每一格只花一回合 ---
var in_transit: bool = false
var transit_target: StringName = &""
var transit_route: Array = []          ## 途经节点（不含起点，含终点）
var transit_turns_left: int = 0
var turn_log: Array = []

var migrations: int = 0
var visited: Array = []
var log: Array = []
var history: Array = []
var record_history: bool = true

var _starve_debt: float = 0.0
var _last_year_ticked: int = 0

# 压力时间线：首次触发的日号（-1 = 未发生）
var first_food_low: int = -1
var first_degraded: int = -1
var first_store_empty: int = -1
var first_satiety_low: int = -1
var first_death: int = -1


# --------------------------------------------------------------------------
# 建立世界
# --------------------------------------------------------------------------

## use_family = true 时用「一家人出走」的方式奠基（见 docs/10 的实测修正）。
func setup(node_id: StringName, founder_count: int = 12, use_family: bool = true,
		cap: int = 24, couples: int = 2) -> bool:
	if not BloodlineDB.ensure_loaded() or not RegionDB.ensure_loaded():
		return false
	region = RegionDB.make(node_id)
	if region == null:
		return false

	tribe = Tribe.new()
	camp_capacity = cap
	var pool := region.blood_pool
	if use_family:
		tribe.found_family(founder_count, pool, region.magic_density, cap, couples)
	else:
		tribe.found(founder_count, pool, region.magic_density, cap)

	site_map = SiteMap.generate(node_id, region, Genome.rng)
	assignments.clear()
	auto_assign = true
	faith = 30.0
	known = {}
	adopted = {}
	stats = {}
	new_discoveries = []
	for id in Knowledge.ALL_IDS:
		if Knowledge.cost_of(id) <= 0.0 and String(Knowledge.trigger_of(id).get("kind", "")) == "start":
			known[id] = true
			adopted[id] = true
	_sync_knowledge_to_tribe()
	morale = 80.0
	forced_pairs = 0
	auto_assign_all()
	_sync_sites()
	day = 0
	food_store = granary_cap() * 0.75
	satiety = 100.0
	extinct = false
	migrations = 0
	visited = [node_id]
	log.clear()
	history.clear()
	_starve_debt = 0.0
	_last_year_ticked = 0
	first_food_low = -1
	first_degraded = -1
	first_store_empty = -1
	first_satiety_low = -1
	first_death = -1
	_say("部落在%s（%s）扎营，共 %d 人。" % [
		region.name, RegionDB.region_name(region.region_id), tribe.population()])
	_snapshot()
	return true


func granary_cap() -> float:
	return maxf(GRANARY_CAP_PER_PERSON * float(tribe.population()) * k_mult("granary_mult"), 60.0)


func year() -> int:
	return day / DAYS_PER_YEAR


func adults() -> int:
	var n := 0
	for id in tribe.beasts:
		if tribe.beasts[id].age >= Tribe.MATURITY_AGE:
			n += 1
	return n


func population() -> int:
	return tribe.population()


## 该节点在不破坏存量的前提下能长期养活多少人。
func capacity() -> float:
	return region.carrying_capacity_adults()


## 可持续性判据：需求量 vs 土地的最大可持续产量。
## > 1 表示正在吃老本，迟早要迁徙。
func pressure_ratio() -> float:
	return float(population()) * FOOD_PER_PERSON_DAY / maxf(capacity(), 0.01)


## 全族平均近交系数。**必须显示在界面上**：
## 玩家不能在毫不知情的情况下滑向近交崩溃，也不能在 F 一直是 0 的时候
## 误以为「这个系统跟我无关」。
func mean_inbreeding() -> float:
	if tribe == null or tribe.beasts.is_empty():
		return 0.0
	var total := 0.0
	for id in tribe.beasts:
		total += tribe.beasts[id].genome.inbreeding
	return total / float(tribe.beasts.size())


## 部落里还有多少对「互无血缘」的可繁殖组合。
## 这个数字归零的那一刻，近交压力才真正开始。
func unrelated_pair_count() -> int:
	var ids: Array = tribe.beasts.keys()
	var n := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if tribe.pedigree.kinship(ids[i], ids[j]) <= 0.0:
				n += 1
	return n


## 实际可投入生产的劳动力（工时当量）。
##
## **关键：这不是「有几个成年人」，而是每个人劳动能力的总和。**
## 早期版本只让成年人干活，结果一次年龄结构波动就让全族瞬间失去产出、集体饿死，
## 而土地上的食物还剩七成。现实中的采集社会里，小孩采浆果、老人做手工，
## 只要还能动就在干活——而一个瞎了的壮年劳力，反而不如一个健康的老人。
## 详见 Beast.labor_capacity()。
## 饥饿会削弱劳动产出。吃饱的人干满勤，饿到极点也还能挤出四成力气。
## 这让饥荒是一个**渐进的下滑**，而不是一脚踩空直接归零。
func labor_efficiency() -> float:
	var by_food := clampf(satiety / SATIETY_FULL_WORK, SATIETY_MIN_WORK, 1.0)
	# 士气低落时出工不出力。这让「法术强制配对」的代价落在粮食曲线上，
	# 而不是只躺在某个没人看的数字里。
	var by_morale := clampf(0.6 + 0.4 * (morale / 100.0), 0.6, 1.0)
	return by_food * by_morale


func workers() -> float:
	var total := 0.0
	for id in tribe.beasts:
		total += tribe.beasts[id].labor_capacity()
	return total


## 需求驱动的劳动分配。**这是整个经济模型的关键。**
##
## 早期版本让部落把全部劳动力都派出去采集，结果 8 个人能采 10.2/天，
## 而土地的可持续产量只有 8/天 —— 部落从第一天起就在吃老本，第 296 天灭族。
## 但真实的人不会去采集自己吃不完的东西。劳动应当按**需求**投入：
##   需求 = 当日口粮 + 补仓缺口（按 180 天补满，最多追加 50%）
## 只有当「需求超过土地的最大可持续产量」时，部落才会真的把存量吃下去。
## 这正是设计要的压力：**你被自己的繁荣推着走，而不是被自己的愚蠢推着走。**
func allocate_labor(daily_need: float, labor: float) -> Array:
	# 粮仓目标 90%：冬季采集只有 ×0.45，物理上就采不够，必须靠秋天囤的粮过冬。
	# 目标设低了，部落会年年冬天亏空、逐年下沉 —— 那不是被土地逼走，是被自己的粮仓策略饿死。
	var store_target := granary_cap() * 0.9
	var deficit := maxf(0.0, store_target - food_store)
	var want := daily_need + minf(deficit / 240.0, daily_need * 0.25)
	if want <= 0.0 or labor <= 0.0:
		return [0.0, 0.0]

	var h := clampf(hunt_ratio, 0.0, 1.0)
	var gather_rate := Region.GATHER_RATE * region.gather_mult()
	var need_gather := (want * (1.0 - h)) / maxf(gather_rate, 0.01)
	var need_hunt := (want * h) / Region.HUNT_RATE
	var total_needed := need_gather + need_hunt
	if total_needed <= 0.0:
		return [0.0, 0.0]
	# 只派出「够用」的人；人力不足时才按比例缩水。
	# 早期版本这里写成了 `labor × 比例`：算出需要 6.8 个采集工，却把全部 9.76 个劳动力都派了出去，
	# 实际产出 14.6/天 而不是 12/天 —— 土地被超额采空，部落从第一天起就在毁掉自己的营地。
	var ratio := minf(1.0, labor / total_needed)
	return [need_gather * ratio, need_hunt * ratio]


func tick_day() -> Dictionary:
	if extinct:
		return {}
	day += 1

	var daily_need := 0.0
	for id in tribe.beasts:
		daily_need += FOOD_PER_PERSON_DAY * Persona.food_mult(tribe.beasts[id]) * k_mult("food_mult")
	var labor_eff := labor_efficiency()
	var r: Dictionary
	var gatherers := 0.0
	var hunters := 0.0
	if in_transit:
		# 在途：没有工作点，只能边走边采；也**不动脚下这片土地的存量**（我们已经离开了）
		var forage := workers() * labor_eff * k_value("transit_forage", TRANSIT_FORAGE_RATE)
		r = region.step_day(0.0, 0.0)
		r["total_food"] = forage
		r["gathered"] = forage
		r["hunted"] = 0.0
	else:
		_sync_sites()
		if auto_assign:
			auto_assign_all()
			_sync_sites()
		var alloc := _production_from_sites(labor_eff)
		gatherers = alloc["gatherers"]
		hunters = alloc["hunters"]
		last_gathered += float(gatherers)
		last_hunted += float(hunters)
		r = region.step_day(gatherers, hunters)
		_extract_nonfood(labor_eff)
	var produced: float = r["total_food"]

	# 食物结算：先吃当天产出，不够再吃仓
	var available := produced + food_store
	var shortfall := maxf(0.0, daily_need - available)
	var consumed := daily_need - shortfall
	food_store = clampf(available - consumed, 0.0, granary_cap())

	# 饱食度
	if shortfall > 0.0:
		var ratio := shortfall / maxf(daily_need, 1.0)
		satiety = maxf(0.0, satiety - ratio * 18.0)
		if first_satiety_low < 0 and satiety < SATIETY_CRISIS:
			first_satiety_low = day
	else:
		satiety = minf(100.0, satiety + SATIETY_RECOVER_PER_DAY)

	# 饥饿减员：先饿死最弱的（老人、幼崽），最后才是壮年
	var deaths := 0
	if satiety < SATIETY_CRISIS:
		_starve_debt += (1.0 - satiety / SATIETY_CRISIS) * STARVE_DEBT_PER_DAY \
			* k_mult("starve_debt_mult")
		while _starve_debt >= 1.0:
			_starve_debt -= 1.0
			if tribe.kill_weakest(1) > 0:
				deaths += 1
				if first_death < 0:
					first_death = day
			else:
				break
		if tribe.extinct:
			extinct = true
			_say("部落于第 %d 天灭绝。" % day)

	# 三种配对：休息所走这里，法术走 force_pair()，自然配对由 Tribe.step() 按年处理
	if not in_transit:
		_try_rest_pairing()
	_tick_faith_and_morale()

	# 压力时间线打点
	if first_food_low < 0 and float(r["food_ratio"]) < Region.FOOD_LOW_RATIO:
		first_food_low = day
		_say("【警告】%s 的食物存量跌破两成，采集效率减半。" % region.name)
	if first_degraded < 0 and bool(r["degraded"]):
		first_degraded = day
		_say("【不可逆】%s 的生态彻底退化，土地承载力永久下降三成。" % region.name)
	if first_store_empty < 0 and food_store <= 0.01 and produced < daily_need:
		first_store_empty = day
		_say("【警告】粮仓见底，今天开始挨饿。")

	for e in r["events"]:
		if String(e.get("type", "")) == "prey_migration":
			_say("【事件】猎物种群崩溃，兽群迁徙，狩猎产出大幅下降，持续 60 天。")

	# 世代推进：每 365 天走一次 Tribe
	if day - _last_year_ticked >= DAYS_PER_YEAR:
		_last_year_ticked = day
		tribe.step(policy, gene_flow_per_year)
		if tribe.extinct and not extinct:
			extinct = true
			_say("部落于第 %d 天灭绝（人口不足或无可繁殖配对）。" % day)

	_sync_sites()      # 收尾再同步一次：本 tick 里死掉的人要立刻从工作点名单里消失
	_snapshot()
	return {
		"day": day, "need": daily_need, "produced": produced,
		"store": food_store, "satiety": satiety, "deaths": deaths,
		"food_ratio": r["food_ratio"], "prey_ratio": r["prey_ratio"],
		"population": population(), "pressure": pressure_ratio(),
		"gatherers": gatherers, "hunters": hunters,
	}


# --------------------------------------------------------------------------
# 工作点与指派
# --------------------------------------------------------------------------

## 把 assignments 同步到各工作点的 workers 列表，并清掉已死/超额的指派。
func _sync_sites() -> void:
	if site_map == null:
		return
	for s in site_map.sites:
		(s["workers"] as Array).clear()
	var drop: Array = []
	for id in assignments:
		if not tribe.beasts.has(id):
			drop.append(id)
			continue
		var s := site_map.site(int(assignments[id]))
		if s.is_empty() or (s["workers"] as Array).size() >= int(s["slots"]):
			drop.append(id)
			continue
		(s["workers"] as Array).append(id)
	for id in drop:
		assignments.erase(id)
	for id in tribe.beasts:
		var b: Beast = tribe.beasts[id]
		b.site_id = int(assignments.get(id, -1))
		b.activity = Beast.Activity.WORKING if b.site_id >= 0 else Beast.Activity.IDLE


## 取某个工作点当前实际在场的人（过滤掉已经死掉但名单还没更新的）。
func site_workers(site_id: int) -> Array:
	var s := site_map.site(site_id)
	var out: Array = []
	for id in (s.get("workers", []) as Array):
		if tribe.beasts.has(id):
			out.append(id)
	return out


func occupied_slots(site_id: int) -> int:
	var n := 0
	for id in assignments:
		if int(assignments[id]) == site_id:
			n += 1
	return n


## 手动把某人指派到某地。返回是否成功（名额满了会失败）。
func assign(beast_id: int, site_id: int) -> bool:
	if site_map == null or not tribe.beasts.has(beast_id):
		return false
	var s := site_map.site(site_id)
	if s.is_empty():
		return false
	if int(assignments.get(beast_id, -1)) != site_id \
			and occupied_slots(site_id) >= int(s["slots"]):
		return false
	assignments[beast_id] = site_id
	_sync_sites()
	return true


func unassign(beast_id: int) -> void:
	assignments.erase(beast_id)
	_sync_sites()


## 一次性把一批人派到某类工作点（UI 的「全员去采集」用）。
func assign_kind(kind: int, ids: Array) -> int:
	var ok := 0
	var pool: Array = site_map.sites_of_kind(kind)
	for id in ids:
		for s in pool:
			if assign(id, int(s["id"])):
				ok += 1
				break
	return ok


## 把还没派出去的人填进某一类工作点，直到预计产出满足 want。
## **每个名额都挑最合适的人**（能力 × 距离偏好 × 工作偏好）——
## 自动派工如果无视爱好，就会把人派到他不喜欢的工作上白吃惩罚。
## 被派出去的人会从 ids 里移除，供下一类工作点继续挑。
func _fill_kind(kind: int, ids: Array, used: Dictionary,
		want: float, labor_eff: float) -> void:
	if want <= 0.0:
		return
	var rate: float = Region.HUNT_RATE if kind == SiteMap.Kind.HUNT else Region.GATHER_RATE
	var pool: Array = site_map.sites_of_kind(kind)
	pool.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	var projected := 0.0
	for s in pool:
		var sid := int(s["id"])
		var dist := float(s["dist"])
		var rate_mult := site_map.rate_multiplier(s)
		for _slot in int(s["slots"]):
			if ids.is_empty() or projected >= want:
				return
			var best_i := -1
			var best_score := -1.0
			for i in ids.size():
				var b: Beast = tribe.beasts[ids[i]]
				var sc := b.labor_capacity() * Persona.distance_mult(b, dist) \
					* Persona.site_pref_mult(b, kind)
				if sc > best_score:
					best_score = sc
					best_i = i
			if best_i < 0:
				return
			var who: int = ids[best_i]
			ids.remove_at(best_i)
			assignments[who] = sid
			projected += rate * rate_mult * labor_eff * best_score
			used[sid] = int(used.get(sid, 0)) + 1


## 自动派工：**需求驱动**。只派出够用的人，剩下的去采非食物资源。
## 这不是"部落很蠢地把所有人撒出去" —— 真实的人不会采集自己吃不完的东西。
func auto_assign_all() -> void:
	if site_map == null:
		return
	assignments.clear()
	var labor_eff := labor_efficiency()
	var want := float(population()) * FOOD_PER_PERSON_DAY
	var deficit := maxf(0.0, granary_cap() * 0.9 - food_store)
	want += minf(deficit / 240.0, want * 0.25)
	if want <= 0.0:
		return

	# 劳动能力强的先派出去
	var ranked: Array = []
	for id in tribe.beasts:
		ranked.append([tribe.beasts[id].labor_capacity(), id])
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var ids: Array = []
	for r in ranked:
		ids.append(r[1])

	var used := {}

	# 1) 食物点：**必须先按 hunt_ratio 拆分需求**，再各自由近到远填。
	#    早期版本把采集点和猎场混在一起按距离填 —— 因为打猎的单位产出是采集的两倍，
	#    结果"最近的那个点是猎场"就等于全族去打猎，猎物种群直接崩到 7%。
	#    hunt_ratio 是战略旋钮，自动派工不能绕过它。
	# 按**两个来源各自的可持续产量**分配力气，而不是写死百分比。
	# 写死 15% 狩猎在猎物占比高的节点上等于把 85% 的力气全压在采集上，必然超采。
	var cap_g := region.food_msy()
	var cap_h := region.prey_msy() * 0.5      # 与 carrying_capacity_adults() 同一口径
	var cap_total := maxf(cap_g + cap_h, 0.01)
	var share_h := clampf((cap_h / cap_total) * hunt_bias, 0.0, 0.92)
	_fill_kind(SiteMap.Kind.GATHER, ids, used, want * (1.0 - share_h), labor_eff)
	_fill_kind(SiteMap.Kind.HUNT, ids, used, want * share_h, labor_eff)

	# 2) 余下的人去采木/石/魔晶/药草
	var others: Array = []
	for s in site_map.sites:
		var k := int(s["kind"])
		if k == SiteMap.Kind.WOOD or k == SiteMap.Kind.STONE \
				or k == SiteMap.Kind.CRYSTAL or k == SiteMap.Kind.HERB:
			others.append(int(s["id"]))
	if others.is_empty():
		return
	var oi := 0
	var guard := 0
	while not ids.is_empty() and guard < 400:
		guard += 1
		var sid2: int = others[oi % others.size()]
		oi += 1
		if int(used.get(sid2, 0)) < int(site_map.site(sid2)["slots"]):
			var who: int = ids.pop_front()
			assignments[who] = sid2
			used[sid2] = int(used.get(sid2, 0)) + 1


## 汇总各工作点的有效劳动当量。
##
## **逐个个体结算**，而不是"人数 × 统一速率"——只有这样，性情（勤勉/怠惰）、
## 爱好（对口/不对口）、距离偏好（恋家/远行癖）、以及个体会的伤病残疾
## 才会真的体现在产出上。之前用人数结算时，这些都只是列表里的装饰。
func _production_from_sites(labor_eff: float) -> Dictionary:
	var g := 0.0
	var h := 0.0
	for s in site_map.sites:
		var ws: Array = s["workers"]
		if ws.is_empty():
			continue
		var kind := int(s["kind"])
		var base := site_map.rate_multiplier(s) * labor_eff * _coop_bonus(ws)
		for id in ws:
			if not tribe.beasts.has(id):
				continue
			var b: Beast = tribe.beasts[id]
			var per := base * b.labor_capacity() \
				* Persona.distance_mult(b, float(s["dist"])) \
				* Persona.site_pref_mult(b, kind)
			if kind == SiteMap.Kind.GATHER:
				g += per * k_mult("gather_mult")
			elif kind == SiteMap.Kind.HUNT:
				h += per * k_mult("hunt_mult")
	return {"gatherers": g, "hunters": h}


## 同一工作点上的人合不合得来。关系好一起干活更快，关系差互相拖后腿。
## 一个人的时候没有协作加成。
func _coop_bonus(ids: Array) -> float:
	if ids.size() < 2:
		return 1.0
	var total := 0.0
	var n := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			total += tribe.relation(ids[i], ids[j])
			n += 1
	if n == 0:
		return 1.0
	return 1.0 + clampf((total / float(n)) / 100.0 * 0.14, -0.14, 0.14)


## 木/石/魔晶/药草是**不可再生**的，采一点少一点。
func _extract_nonfood(labor_eff: float) -> void:
	for s in site_map.sites:
		var ws: Array = s["workers"]
		if ws.is_empty():
			continue
		var e := 0.0
		for id in ws:
			if tribe.beasts.has(id):
				e += tribe.beasts[id].labor_capacity() * Persona.distance_mult(
					tribe.beasts[id], float(s["dist"]))
		e *= site_map.rate_multiplier(s) * labor_eff * _coop_bonus(ws)
		match int(s["kind"]):
			SiteMap.Kind.WOOD: region.extract(&"wood", e * EXTRACT_WOOD)
			SiteMap.Kind.STONE: region.extract(&"stone", e * EXTRACT_STONE)
			SiteMap.Kind.CRYSTAL: region.extract(&"crystal", e * EXTRACT_CRYSTAL)
			SiteMap.Kind.HERB: region.extract(&"herb", e * EXTRACT_HERB)


# --------------------------------------------------------------------------
# 三种配对
# --------------------------------------------------------------------------

## ① 休息所配对：把一雄一雌安排到休息所，每日掷一次高概率受孕。
func _try_rest_pairing() -> void:
	if site_map == null:
		return
	for s in site_map.sites_of_kind(SiteMap.Kind.REST):
		var males: Array = []
		var females: Array = []
		for id in (s["workers"] as Array):
			if tribe.beasts[id].is_male():
				males.append(id)
			else:
				females.append(id)
		# 先撮合最合得来的一对：关系会自己选出人，而不是随机配对
		var pairs: Array = []
		for f in females:
			for m in males:
				pairs.append([tribe.relation(f, m), f, m])
		pairs.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		for p in pairs:
			if tribe.conceive(p[1], p[2], REST_CONCEPTION_CHANCE):
				tribe.add_affinity(p[1], p[2], 5.0)
				tribe.note(tribe.beasts[p[1]], "在休息所里怀上了%s的孩子。" % tribe.beasts[p[2]].display_name())
				_say("休息所里，%s 怀上了（和%s）。" % [
					tribe.beasts[p[1]].display_name(), tribe.beasts[p[2]].display_name()])
				return


## ② 法术强制配对：消耗信仰，**并且有士气代价**。
## 刻意不做成免费按钮 —— 免费的强制只会让玩家把它当最优解，
## 那这个机制就从"一个沉重的选择"退化成"一个更快的生育键"。
func force_pair(a: int, b: int) -> Dictionary:
	if not tribe.beasts.has(a) or not tribe.beasts.has(b):
		return {"ok": false, "reason": "对象不存在"}
	var ba: Beast = tribe.beasts[a]
	var bb: Beast = tribe.beasts[b]
	if ba.is_male() == bb.is_male():
		return {"ok": false, "reason": "需要一雄一雌"}
	if faith < FORCE_PAIR_FAITH:
		return {"ok": false, "reason": "信仰不足（需要 %d，现有 %d）" % [
			int(FORCE_PAIR_FAITH), int(faith)]}
	var male: int = a if ba.is_male() else b
	var female: int = b if ba.is_male() else a
	faith -= FORCE_PAIR_FAITH
	morale = maxf(0.0, morale - FORCE_PAIR_MORALE_COST * (0.3 if k_flag("force_pair_mercy") else 1.0))
	forced_pairs += 1
	ba.forced_pair_with = b
	bb.forced_pair_with = a
	var ok := tribe.conceive(female, male, FORCE_PAIR_CHANCE)
	# **代价落在两个人身上**：他们互相恨上了，各自的心情也塌了。
	# 这比一个抽象的"士气 −14"有说服力得多 —— 玩家能在人物档案里看到这笔账。
	tribe.add_affinity(male, female, -42.0)
	ba.mood = maxf(0.0, ba.mood - 26.0)
	bb.mood = maxf(0.0, bb.mood - 26.0)
	tribe.note(ba, "祖灵把我和%s按在了一起。我不会忘记这件事。" % bb.display_name())
	tribe.note(bb, "祖灵把我和%s按在了一起。我不会忘记这件事。" % ba.display_name())
	_say("【法术】祖灵把两人强行结合。族人低着头，没人说话。%s" % (
		"她怀上了。" if ok else "什么也没发生。"))
	return {"ok": true, "conceived": ok}


## ③ 自然配对：不归这里管 —— 由 Tribe.step() 的自主择偶按年处理。
func _tick_faith_and_morale() -> void:
	faith = minf(FAITH_MAX, faith + FAITH_PER_DAY * k_mult("faith_rate"))
	morale = minf(100.0, morale + MORALE_RECOVER_PER_DAY)


func _snapshot() -> void:
	if not record_history:
		return
	history.append({		"day": day,
		"population": population(),
		"food_store": food_store,
		"satiety": satiety,
		"food_ratio": region.food_ratio(),
		"prey_ratio": region.prey_ratio(),
		"food_K": region.food_K,
		"degraded": region.degraded,
		"pressure": pressure_ratio(),
		"year": year(),
	})


func _say(msg: String) -> void:
	log.append({"day": day, "msg": msg})
	if log.size() > 400:
		log.pop_front()


# --------------------------------------------------------------------------
# 回合制
# --------------------------------------------------------------------------

func days_per_turn() -> int:
	return DAYS_PER_TURN


func season_name() -> String:
	return region.season_name() if region != null else ""


## 拔营启程。邻格 = 1 回合，远处的格子 = 途经格数那么多回合。
## 途中处于「在途」状态：不能派工、不能配对、采集减半，但每一回合仍然要吃饭。
func start_migration(target: StringName) -> Dictionary:
	if extinct:
		return {"ok": false, "reason": "部落已经没了"}
	if in_transit:
		return {"ok": false, "reason": "已经在路上（还剩 %d 回合）" % transit_turns_left}
	if target == region.id:
		return {"ok": false, "reason": "部落已经在这里了"}
	var path := RegionDB.path_to(region.id, target)
	if path.is_empty():
		return {"ok": false, "reason": "没有可行的路线"}
	in_transit = true
	transit_target = target
	transit_route = path
	transit_turns_left = path.size()
	_say("拔营启程，前往%s。路程 %d 回合，途中无法正常生产。" % [
		RegionDB.node_display_name(target), transit_turns_left])
	for id in tribe.beasts:
		tribe.note(tribe.beasts[id], "拔营启程，前往%s。" % RegionDB.node_display_name(target))
	return {"ok": true, "turns": transit_turns_left, "route": path.duplicate()}


func transit_route_names() -> String:
	var parts: Array = []
	for nid in transit_route:
		parts.append(RegionDB.node_display_name(nid))
	return " → ".join(parts)


## 结束一个回合：推进 30 天，然后处理在途推进/抵达。
func end_turn() -> Dictionary:
	if extinct:
		return {"ok": false, "reason": "部落已经没了"}
	last_gathered = 0.0
	last_hunted = 0.0
	var events_before := log.size()
	for _i in DAYS_PER_TURN:
		if extinct:
			break
		tick_day()
	turn += 1
	tribe.current_turn = turn
	_tick_stats(last_gathered, last_hunted)
	_refresh_personas()
	if in_transit:
		transit_turns_left -= 1
		if transit_turns_left <= 0:
			_arrive()
	_sync_knowledge_to_tribe()
	_check_discoveries()
	var summary := {
		"ok": true, "turn": turn, "day": day, "season": season_name(),
		"population": population(), "food_store": food_store, "satiety": satiety,
		"pressure": pressure_ratio(), "in_transit": in_transit,
		"transit_turns_left": transit_turns_left,
		"events": log.slice(events_before) if log.size() > events_before else [],
		"extinct": extinct,
	}
	turn_log.append(summary)
	return summary


## 每回合刷新一次：关系网、心情、当前想法。
## 放在回合边界而不是每次 tick，是因为这些都是"这一季过得怎么样"的粒度。
func _refresh_personas() -> void:
	tribe.update_relations()
	var transit := in_transit
	for id in tribe.beasts:
		var b: Beast = tribe.beasts[id]
		# 心情向基准回归，再叠加这一回合的处境
		b.mood += (70.0 - b.mood) * 0.10
		var kind := -1
		if b.site_id >= 0:
			var s := site_map.site(b.site_id)
			if not s.is_empty():
				kind = int(s["kind"])
				b.mood += 2.5 if Persona.likes_kind(b, kind) else -1.2
		if transit:
			b.mood -= 3.0
		if satiety < 50.0:
			b.mood -= 4.0
		b.mood = clampf(b.mood, 0.0, 100.0)

		var ctx := {
			"satiety": satiety, "in_transit": transit, "site_kind": kind,
			"partner_name": tribe.partner_name(b),
		}
		b.thought = Persona.think(b, ctx)


# --------------------------------------------------------------------------
# 继嗣制度
# --------------------------------------------------------------------------

## 社会阶段由人口推导，不另设一套进度条 —— 少一个要维护的状态。
## 已采纳知识里某个乘数项的总倍率。
func k_mult(key: String) -> float:
	var m := 1.0
	for id in adopted:
		var e: Dictionary = Knowledge.effects_of(id)
		if e.has(key):
			m *= float(e[key])
	return m


## 已采纳知识里某个开关项。
func k_flag(key: String) -> bool:
	for id in adopted:
		if Knowledge.effects_of(id).has(key):
			return true
	return false


func k_value(key: String, default_value: float) -> float:
	for id in adopted:
		var e: Dictionary = Knowledge.effects_of(id)
		if e.has(key):
			return float(e[key])
	return default_value


## 把知识的效果同步到 Tribe 的开关上。Tribe 不认识 Knowledge，只认这几个数。
func _sync_knowledge_to_tribe() -> void:
	tribe.kin_avoid = k_value("kin_avoid", 1.0)
	tribe.defect_resist = k_mult("defect_resist")
	tribe.planned_pairing = k_flag("planned_pairing")
	tribe.clan_exogamy = k_flag("clan_exogamy")
	gene_flow_per_year = maxf(gene_flow_per_year, k_value("gene_flow", 0.0))


## 这个制度现在能不能选（由知识解锁，而不是人口阶段）。
func descent_unlocked(mode: int) -> bool:
	for id in adopted:
		if Knowledge.unlocks_descent(id) == mode:
			return true
	return false


func unlocked_descent_modes() -> Array:
	var out: Array = []
	for m in Descent.ALL_MODES:
		if descent_unlocked(m):
			out.append(m)
	return out


## 每回合检查有没有新知识被发现。**发现不等于采纳。**
func _check_discoveries() -> void:
	new_discoveries.clear()
	for id in Knowledge.find_discoverables(stats, known):
		known[id] = true
		new_discoveries.append(id)
		_say("【新知】%s —— %s" % [Knowledge.node_name(id), Knowledge.node_desc(id)])


func can_adopt(id: StringName) -> bool:
	if adopted.has(id) or not known.has(id):
		return false
	return faith >= Knowledge.cost_of(id)


func adopt_blocked_reason(id: StringName) -> String:
	if adopted.has(id):
		return "已经采纳了。"
	if not known.has(id):
		return "还没发现。"
	for r in Knowledge.requires_of(id):
		if not adopted.has(r):
			return "需要先采纳「%s」。" % Knowledge.node_name(r)
	var cost := Knowledge.cost_of(id)
	if faith < cost:
		return "信仰不够（需要 %.0f，现有 %.0f）。" % [cost, faith]
	return ""


## 采纳一项知识。
func adopt(id: StringName) -> bool:
	var reason := adopt_blocked_reason(id)
	if reason != "":
		_say("【知识】学不了「%s」：%s" % [Knowledge.node_name(id), reason])
		return false
	faith -= Knowledge.cost_of(id)
	adopted[id] = true
	var dm := Knowledge.unlocks_descent(id)
	_sync_knowledge_to_tribe()
	for bid in tribe.beasts:
		var b: Beast = tribe.beasts[bid]
		tribe.note(b, "部落学会了「%s」。" % Knowledge.node_name(id))
	_say("【知识】部落采纳了「%s」%s" % [Knowledge.node_name(id),
		"，从此可以改行「%s」。" % Descent.mode_name(dm) if dm >= 0 else "。"])
	return true


## 每回合刷新计数器。触发器全靠这些数。
func _tick_stats(gathered: float, hunted: float) -> void:
	stats["gathered"] = float(stats.get("gathered", 0.0)) + gathered
	stats["hunted"] = float(stats.get("hunted", 0.0)) + hunted
	stats["deaths"] = tribe.stat_deaths
	stats["births"] = tribe.stat_births
	stats["defect_births"] = tribe.stat_defect_births
	stats["inbreed_births"] = tribe.stat_inbreed_births
	stats["chimera_births"] = tribe.stat_chimera_births
	stats["max_pop"] = maxf(float(stats.get("max_pop", 0.0)), float(tribe.beasts.size()))
	stats["migrations"] = float(migrations)
	stats["faith_peak"] = maxf(float(stats.get("faith_peak", 0.0)), faith)
	stats["forced_pairs"] = float(forced_pairs)
	# 单个男人留下的活后代数 —— 父系氏族就是这么被"发现"的
	var best_m := 0
	var best_f := 0
	for id in tribe.beasts:
		var b: Beast = tribe.beasts[id]
		if not b.is_male():
			continue
		var n := 0
		for oid in tribe.beasts:
			var o: Beast = tribe.beasts[oid]
			if o.father == id:
				n += 1
		best_m = maxi(best_m, n)
	stats["dominant_male"] = float(best_m)
	# 同一个狩猎点上同时有几个自己人
	var crew := 0
	for site in site_map.sites:
		if int(site["kind"]) == SiteMap.Kind.HUNT:
			crew = maxi(crew, (site["workers"] as Array).size())
	stats["hunt_crew_max"] = float(maxi(int(stats.get("hunt_crew_max", 0)), crew))


func social_stage() -> int:
	return Descent.stage_for_population(tribe.beasts.size())


func stage_name() -> String:
	return Descent.stage_name(social_stage())


func descent_name() -> String:
	return Descent.mode_name(tribe.descent_mode)


func unlocked_modes() -> Array:
	return Descent.unlocked_modes(tribe.beasts.size())


func can_reform_to(mode: int) -> bool:
	if mode == tribe.descent_mode:
		return false
	if not descent_unlocked(mode):
		return false
	return faith >= Descent.reform_cost(tribe.descent_mode, mode)


func reform_blocked_reason(mode: int) -> String:
	if mode == tribe.descent_mode:
		return "这已经是现行的制度。"
	if not descent_unlocked(mode):
		return "还没有这项知识 —— 得先在「知识」里发现并采纳对应的制度。"
	var cost := Descent.reform_cost(tribe.descent_mode, mode)
	if faith < cost:
		return "信仰不够（需要 %.0f，现有 %.0f）。" % [cost, faith]
	return ""


## 改制。**代价不只是信仰** —— 守旧的人把改制当成对祖灵的冒犯。
## 这是这个系统真正的分量所在：制度是可以变的，但变的时候要有人不高兴。
func reform_descent(mode: int) -> bool:
	if not can_reform_to(mode):
		_say("【改制】改不了：%s" % reform_blocked_reason(mode))
		return false
	var old_name := descent_name()
	var old_mode := tribe.descent_mode
	var cost := Descent.reform_cost(tribe.descent_mode, mode)
	faith -= cost
	var magnitude: float = 1.0 + 0.5 * float(absi(Descent.stage_of_mode(mode)
		- Descent.stage_of_mode(tribe.descent_mode)))
	for id in tribe.beasts:
		var b: Beast = tribe.beasts[id]
		b.mood = clampf(b.mood + Descent.reform_mood_delta(b.traits, magnitude), 0.0, 100.0)
		tribe.note(b, "部落改制：%s → %s。" % [old_name, Descent.mode_name(mode)])
	# 名后挂父母名的制度里，记下来的是「碎息女」这样的临时标记。
	# 一旦改成有姓的制度，这种标记会被原样继承下去，变成一个叫「碎息女」的氏族。
	# 所以改制时**重新登记一次**：把性别后缀去掉，还原成家族名。
	if Descent.is_suffix_style(old_mode) and not Descent.is_suffix_style(mode):
		for id in tribe.beasts:
			var b: Beast = tribe.beasts[id]
			var sn := b.surname
			if sn.ends_with("子") or sn.ends_with("女"):
				b.surname = sn.substr(0, sn.length() - 1)
	tribe.descent_mode = mode
	_say("【改制】部落由「%s」改为「%s」，耗去信仰 %.0f。从此以后出生的孩子按新规矩取名。此前出生的人保留原名。"
		% [old_name, Descent.mode_name(mode), cost])
	return true


func _arrive() -> void:
	var target := transit_target
	var old_name := region.name
	region = RegionDB.make(target)
	site_map = SiteMap.generate(target, region, Genome.rng)
	assignments.clear()
	auto_assign = true
	auto_assign_all()
	_sync_sites()
	in_transit = false
	transit_target = &""
	transit_route.clear()
	transit_turns_left = 0
	migrations += 1
	visited.append(target)
	_say("部落抵达%s（%s）。上一个是%s，那些窝棚就留在那儿烂掉了。" % [
		region.name, RegionDB.region_name(region.region_id), old_name])
	for id in tribe.beasts:
		tribe.note(tribe.beasts[id], "抵达%s。上一个营地是%s。" % [region.name, old_name])
	_snapshot()


# --------------------------------------------------------------------------
# 迁徙（即时版，保留给旧工具与测试）
# --------------------------------------------------------------------------

func can_migrate_to(node_id: StringName) -> bool:
	return RegionDB.has_node(node_id) and node_id != region.id


## 迁徙：消耗旅途口粮，抵达新节点，建筑归零（M1 不建模建筑，只记日志）。
func migrate_to(node_id: StringName) -> Dictionary:
	if not can_migrate_to(node_id):
		return {"ok": false, "reason": "目标不可达"}
	var travel := RegionDB.travel_days(region.id, node_id)
	if travel < 0:
		return {"ok": false, "reason": "没有可行的路线"}

	var need := float(population()) * FOOD_PER_PERSON_DAY * float(travel)
	var available := food_store
	var shortfall := maxf(0.0, need - available)
	food_store = maxf(0.0, available - need)
	if shortfall > 0.0:
		var ratio := shortfall / maxf(need, 1.0)
		satiety = maxf(0.0, satiety - ratio * 40.0)

	var old_name := region.name
	region = RegionDB.make(node_id)
	site_map = SiteMap.generate(node_id, region, Genome.rng)
	assignments.clear()
	auto_assign = true
	auto_assign_all()
	_sync_sites()
	day += travel
	migrations += 1
	for v in visited:
		if v == node_id:
			return {"ok": true, "travel": travel, "revisit": true}
	visited.append(node_id)
	_say("部落离开%s，跋涉 %d 天抵达%s（%s）。留下的营地会慢慢烂掉。" % [
		old_name, travel, region.name, RegionDB.region_name(region.region_id)])
	_snapshot()
	return {"ok": true, "travel": travel, "shortfall": shortfall}


# --------------------------------------------------------------------------
# 现实时间换算（用于校验节奏）
# --------------------------------------------------------------------------

func real_minutes_at(speed: float = 1.0) -> float:
	return float(day) * REAL_SECONDS_PER_DAY_1X / maxf(speed, 0.01) / 60.0


static func day_to_real_minutes(d: int, speed: float = 1.0) -> float:
	return float(d) * REAL_SECONDS_PER_DAY_1X / maxf(speed, 0.01) / 60.0


# --------------------------------------------------------------------------
# 诊断 / 存档
# --------------------------------------------------------------------------

func metrics() -> Dictionary:
	return {
		"day": day, "year": year(), "population": population(), "adults": adults(),
		"workers": workers(),
		"food_store": food_store, "granary_cap": granary_cap(), "satiety": satiety,
		"food_ratio": region.food_ratio(), "prey_ratio": region.prey_ratio(),
		"food_K": region.food_K, "degraded": region.degraded,
		"capacity": capacity(), "pressure": pressure_ratio(),
		"turn": turn, "season": season_name(), "in_transit": in_transit,
		"transit_turns_left": transit_turns_left, "transit_target": String(transit_target),
		"hunt_ratio": hunt_ratio, "hunt_bias": hunt_bias,
		"migrations": migrations, "extinct": extinct,
		"faith": faith, "morale": morale, "forced_pairs": forced_pairs,
		"assigned": assignments.size(),
		"first_food_low": first_food_low, "first_degraded": first_degraded,
		"first_store_empty": first_store_empty, "first_satiety_low": first_satiety_low,
		"first_death": first_death,
	}


func snapshot() -> String:
	var m := metrics()
	return "第%4d天(第%d年) 人=%2d 仓=%4.0f/%4.0f 饱食=%3.0f 食物=%.0f%% 猎物=%.0f%% 压力=%.2f%s" % [
		m["day"], m["year"], m["population"], m["food_store"], m["granary_cap"],
		m["satiety"], m["food_ratio"] * 100.0, m["prey_ratio"] * 100.0,
		m["pressure"], "  [已退化]" if m["degraded"] else ""]


## 全量存档。**这是唯一一处必须逐个字段点名的地方** ——
## 漏一个字段不会报错，只会让读档后的世界悄悄偏离。
## 所以有一条"轨迹测试"守着：存档后跑 N 回合 vs 读档后再跑 N 回合，
## 两边必须逐字段完全相同。
func to_dict() -> Dictionary:
	var store: Array = []
	for h in history:
		store.append(h.duplicate(true))
	return {
		# --- 世界 ---
		"day": day, "turn": turn,
		"food_store": food_store, "satiety": satiety, "starve_debt": _starve_debt,
		"hunt_ratio": hunt_ratio, "hunt_bias": hunt_bias, "policy": policy,
		"gene_flow_per_year": gene_flow_per_year, "camp_capacity": camp_capacity,
		"extinct": extinct, "migrations": migrations,
		"visited": visited.duplicate(), "log": log.duplicate(),
		"history": store, "record_history": record_history,
		"last_year_ticked": _last_year_ticked,
		"node_id": String(region.id), "region_id": String(region.region_id),
		"region_state": region.to_save(),
		"site_map": site_map.to_save(),
		"assignments": assignments.duplicate(), "auto_assign": auto_assign,
		# --- 信仰与士气 ---
		"faith": faith, "morale": morale, "forced_pairs": forced_pairs,
		# --- 知识树 ---
		"known": known.keys(), "adopted": adopted.keys(),
		"stats": stats.duplicate(),
		# --- 在途 ---
		"in_transit": in_transit, "transit_target": String(transit_target),
		"transit_route": transit_route.duplicate(), "transit_turns_left": transit_turns_left,
		"turn_log": turn_log.duplicate(true),
		# --- 里程碑 ---
		"timeline": {
			"food_low": first_food_low, "degraded": first_degraded,
			"store_empty": first_store_empty, "satiety_low": first_satiety_low,
			"death": first_death,
		},
		# --- 部落 ---
		"tribe": tribe.to_save(),
		# --- 随机数状态 ---
		# **不存这个，读档后的世界一定会和历史分岔。**
		"rng": {"seed": Genome.rng.seed, "state": Genome.rng.state},
	}


## 读档。返回是否成功。
func load_from_dict(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	# 随机数先复位：任何后续的随机调用都要接得上
	var rng_d: Dictionary = d.get("rng", {})
	if not rng_d.is_empty():
		Genome.rng.seed = int(rng_d.get("seed", 0))
		Genome.rng.state = int(rng_d.get("state", 0))

	var node_id := StringName(d.get("node_id", ""))
	region = RegionDB.make(node_id) if RegionDB.has_node(node_id) else null
	if region == null:
		return false
	region.load_save(d.get("region_state", {}))

	site_map = SiteMap.new()
	var sm: Dictionary = d.get("site_map", {})
	if sm.is_empty():
		site_map = SiteMap.generate(node_id, region, Genome.rng)
	else:
		site_map.load_save(sm)

	tribe = Tribe.new()
	tribe.load_save(d.get("tribe", {}))

	day = int(d.get("day", 0))
	turn = int(d.get("turn", 0))
	food_store = float(d.get("food_store", 0.0))
	satiety = float(d.get("satiety", 100.0))
	_starve_debt = float(d.get("starve_debt", 0.0))
	hunt_ratio = float(d.get("hunt_ratio", 0.0))
	hunt_bias = float(d.get("hunt_bias", 1.0))
	policy = int(d.get("policy", Tribe.Policy.AVOID_INBREEDING))
	gene_flow_per_year = float(d.get("gene_flow_per_year", 0.0))
	camp_capacity = int(d.get("camp_capacity", 24))
	extinct = bool(d.get("extinct", false))
	migrations = int(d.get("migrations", 0))
	visited.clear()
	for v in d.get("visited", []):
		visited.append(StringName(v))
	log.clear()
	for e in d.get("log", []):
		log.append(e)
	history.clear()
	for h in d.get("history", []):
		history.append(h)
	record_history = bool(d.get("record_history", true))
	_last_year_ticked = int(d.get("last_year_ticked", 0))

	assignments.clear()
	for k in d.get("assignments", {}):
		assignments[int(k)] = int(d["assignments"][k])
	auto_assign = bool(d.get("auto_assign", true))

	faith = float(d.get("faith", 30.0))
	morale = float(d.get("morale", 80.0))
	forced_pairs = int(d.get("forced_pairs", 0))

	known.clear()
	for k in d.get("known", []):
		known[StringName(k)] = true
	adopted.clear()
	for k in d.get("adopted", []):
		adopted[StringName(k)] = true
	stats = (d.get("stats", {}) as Dictionary).duplicate()
	new_discoveries.clear()

	in_transit = bool(d.get("in_transit", false))
	transit_target = StringName(d.get("transit_target", ""))
	transit_route.clear()
	for r in d.get("transit_route", []):
		transit_route.append(StringName(r))
	transit_turns_left = int(d.get("transit_turns_left", 0))
	turn_log.clear()
	for e in d.get("turn_log", []):
		turn_log.append(e)

	var tl: Dictionary = d.get("timeline", {})
	first_food_low = int(tl.get("food_low", -1))
	first_degraded = int(tl.get("degraded", -1))
	first_store_empty = int(tl.get("store_empty", -1))
	first_satiety_low = int(tl.get("satiety_low", -1))
	first_death = int(tl.get("death", -1))

	_sync_knowledge_to_tribe()
	_sync_sites()
	return true


## 写盘。用 store_var 而不是 JSON —— 它会原样处理 Vector2 与 StringName，
## 不必为每种类型手写编解码（那是存档最容易出错的地方）。
func save_to_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败：%s" % path)
		return false
	f.store_var(to_dict(), false)
	f.close()
	return true


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = f.get_var(false)
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	return load_from_dict(d)
