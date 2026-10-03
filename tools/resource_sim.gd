extends SceneTree
## 区域资源与迁徙节奏标定。运行：
##   ./tools/godot.sh --headless --script res://tools/resource_sim.gd
##   ./tools/godot.sh --headless --script res://tools/resource_sim.gd -- --trace   （单次逐月追踪）
##
## 回答一个问题：**玩家会在第几分钟被迫决定「我得搬走了」？**
## 产出：reports/resource_report.md

const TRIALS := 16
const FOUNDERS := 12
const MAX_DAYS := 2400              ## 20 个游戏年（1 年 = 120 日）
const START_NODE := &"gt_ashwater"
const BASE_SEED := 777001
const OUT_PATH := "res://reports/resource_report.md"

## 现实时间换算（文档 06.1：1 游戏日 = 2 秒 @1x）
const SEC_PER_DAY := 2.0

var _lines: Array = []
var _trace := false


func _initialize() -> void:
	print("")
	print("=== 区域资源与迁徙节奏标定 ===")
	if not BloodlineDB.ensure_loaded() or not RegionDB.ensure_loaded():
		print("数据加载失败")
		quit(1)
		return
	_trace = OS.get_cmdline_user_args().has("--trace")

	if _trace:
		_run_trace()
		quit()
		return

	_header()
	_exp_e_capacity()
	_exp_f_pacing()
	_exp_g_founding()
	_verdict()
	_write_report()
	print("")
	print("报告已写入 %s" % OUT_PATH)
	quit()


# ==========================================================================
# 实验 E：每个节点在不破坏存量的前提下能长期养活多少人
# ==========================================================================

func _exp_e_capacity() -> void:
	print("── 实验 E：节点承载力（最大可持续产量）")
	_lines.append("## 实验 E：节点承载力\n")
	_lines.append("逻辑斯蒂最大可持续产量 = `r·K/4`（在存量 = K/2 处取得）。")
	_lines.append("`承载力` 是保守估计：采集 MSY 全用 + 狩猎 MSY 的一半（狩猎要留种群余地）。\n")
	_lines.append("| 节点 | 区域 | 食物 K | 食物 r | 采集 MSY | 猎物 K | 猎物 r | 狩猎 MSY | **承载力(人)** |")
	_lines.append("|---|---|---|---|---|---|---|---|---|")

	var rows: Array = []
	for nid in RegionDB.node_ids():
		var r := RegionDB.make(nid)
		if r == null:
			continue
		rows.append({"id": nid, "r": r})
	rows.sort_custom(func(a, b): return a["r"].carrying_capacity_adults() > b["r"].carrying_capacity_adults())

	for row in rows:
		var r: Region = row["r"]
		print("  %-18s %-8s 采集MSY %5.1f  狩猎MSY %5.1f  承载力 %5.1f 人" % [
			r.name, RegionDB.region_name(r.region_id), r.food_msy(), r.prey_msy(),
			r.carrying_capacity_adults()])
		_lines.append("| %s | %s | %.0f | %.3f | %.1f | %.0f | %.3f | %.1f | **%.1f** |" % [
			r.name, RegionDB.region_name(r.region_id), r.food_K, r.food_r, r.food_msy(),
			r.prey_K, r.prey_r, r.prey_msy(), r.carrying_capacity_adults()])
	_lines.append("")

	var start := RegionDB.make(START_NODE)
	print("  起始节点 %s 的承载力：%.1f 人；开局 8 人 → 压力 %.2f" % [
		start.name, start.carrying_capacity_adults(),
		8.0 / start.carrying_capacity_adults()])
	_lines.append("> 起始节点 **%s** 承载力 %.1f 人，开局 8 人 → 压力 %.2f。" % [
		start.name, start.carrying_capacity_adults(), 8.0 / start.carrying_capacity_adults()])
	_lines.append("")
	print("")


# ==========================================================================
# 实验 F：迁徙决策什么时候到来
# ==========================================================================

func _run_one(hunt_ratio: float, days: int, founders: int, cap: int,
		gene_flow: float = 0.0, collect_history: bool = false) -> Dictionary:
	Genome.seed_rng(BASE_SEED + int(hunt_ratio * 1000.0) + founders * 31)
	var w := WorldState.new()
	w.record_history = collect_history
	if not w.setup(START_NODE, founders, true, cap):
		return {}
	w.hunt_bias = hunt_ratio / 0.15
	w.gene_flow_per_year = gene_flow
	for _d in days:
		if w.extinct:
			break
		w.tick_day()
	return w.metrics()


func _exp_f_pacing() -> void:
	print("── 实验 F：迁徙决策什么时候到来（起始节点 %s，一家人 8 人，营地容量 24）" % START_NODE)
	_lines.append("## 实验 F：迁徙决策什么时候到来\n")
	_lines.append("起始节点 `%s`，**两对父母 + 8 名子女**共 %d 人奠基，营地容量 24，无联姻。每组 %d 次试验取中位数。\n"
		% [START_NODE, FOUNDERS, TRIALS])
	_lines.append("`劳动分配` = 投入狩猎的成年劳动力比例。时间线单位：游戏年 / 现实分钟（1x，2 秒/日）。\n")
	_lines.append("| 劳动分配 | 压力>1 首现 | 食物<20% | 永久退化 | 粮仓见底 | 首次饿死 | 人口(第6年) | 人口(第12年) | 终局食物% | 灭绝率 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|")

	var ratios := [0.0, 0.15, 0.3, 0.5]
	for hr in ratios:
		var keys := ["pressure_over_1", "food_low", "degraded", "store_empty", "death"]
		var acc := {}
		for k in keys:
			acc[k] = []
		var pop6: Array = []
		var pop12: Array = []
		var fr_end: Array = []
		var extinct_n := 0
		for tr in TRIALS:
			Genome.seed_rng(BASE_SEED + int(hr * 1000.0) * 7 + tr * 7919)
			var w := WorldState.new()
			w.record_history = true
			if not w.setup(START_NODE, FOUNDERS, true, 24, 2):
				continue
			w.hunt_bias = hr / 0.15
			var seen_pressure := -1
			for _d in MAX_DAYS:
				if w.extinct:
					break
				w.tick_day()
				if seen_pressure < 0 and w.pressure_ratio() > 1.0:
					seen_pressure = w.day
			if w.extinct:
				extinct_n += 1
			acc["pressure_over_1"].append(seen_pressure)
			acc["food_low"].append(w.first_food_low)
			acc["degraded"].append(w.first_degraded)
			acc["store_empty"].append(w.first_store_empty)
			acc["death"].append(w.first_death)
			pop6.append(float(_pop_at_year(w, 6)))
			pop12.append(float(_pop_at_year(w, 12)))
			fr_end.append(w.region.food_ratio())

		var p1 := _median(acc["pressure_over_1"])
		print("  %4.0f%%  压力>1 %s   食物低 %s   退化 %s   仓空 %s   饿死 %s   人口(6年) %2.0f (12年) %2.0f  灭绝 %2.0f%%" % [
			hr * 100.0, _fmt_day(p1), _fmt_day(_median(acc["food_low"])),
			_fmt_day(_median(acc["degraded"])), _fmt_day(_median(acc["store_empty"])),
			_fmt_day(_median(acc["death"])), _median(pop6), _median(pop12),
			float(extinct_n) / float(TRIALS) * 100.0])
		_lines.append("| %.0f%% | %s | %s | %s | %s | %s | %.0f | %.0f | %.0f%% | %.0f%% |" % [
			hr * 100.0, _fmt_day(p1), _fmt_day(_median(acc["food_low"])),
			_fmt_day(_median(acc["degraded"])), _fmt_day(_median(acc["store_empty"])),
			_fmt_day(_median(acc["death"])), _median(pop6), _median(pop12),
			_median(fr_end) * 100.0, float(extinct_n) / float(TRIALS) * 100.0])
	_lines.append("")


func _pop_at_year(w: WorldState, y: int) -> int:
	var target := y * WorldState.DAYS_PER_YEAR
	for h in w.history:
		if int(h["day"]) >= target:
			return int(h["population"])
	return w.population()


# ==========================================================================
# 实验 G：起始人口 / 营地容量 的敏感度
# ==========================================================================

func _exp_g_founding() -> void:
	print("── 实验 G：起始人口与营地容量")
	_lines.append("## 实验 G：起始人口与营地容量\n")
	_lines.append("狩猎劳动分配固定 15%。看「食物首次跌破两成」落在第几个游戏年、第几分钟。\n")
	_lines.append("| 起始人口 | 营地容量 | 压力>1 首现 | 食物<20% | 首次饿死 | 第12年人口 | 灭绝率 |")
	_lines.append("|---|---|---|---|---|---|---|")

	for founders in [8, 12, 16, 20]:
		for cap in [16, 24, 32]:
			var acc := {"p": [], "f": [], "d": []}
			var pops: Array = []
			var ext := 0
			for tr in TRIALS:
				Genome.seed_rng(BASE_SEED + founders * 101 + cap * 7 + tr * 7919)
				var w := WorldState.new()
				if not w.setup(START_NODE, founders, true, cap):
					continue
				w.hunt_bias = 1.0
				var sp := -1
				for _d in MAX_DAYS:
					if w.extinct:
						break
					w.tick_day()
					if sp < 0 and w.pressure_ratio() > 1.0:
						sp = w.day
				if w.extinct:
					ext += 1
				acc["p"].append(sp)
				acc["f"].append(w.first_food_low)
				acc["d"].append(w.first_death)
				pops.append(float(_pop_at_year(w, 12)))
			print("  起始%2d人 容量%2d: 压力>1 %s  食物低 %s  饿死 %s  人口(12年) %2.0f  灭绝 %2.0f%%" % [
				founders, cap, _fmt_day(_median(acc["p"])), _fmt_day(_median(acc["f"])),
				_fmt_day(_median(acc["d"])), _median(pops),
				float(ext) / float(TRIALS) * 100.0])
			_lines.append("| %d | %d | %s | %s | %s | %.0f | %.0f%% |" % [
				founders, cap, _fmt_day(_median(acc["p"])), _fmt_day(_median(acc["f"])),
				_fmt_day(_median(acc["d"])), _median(pops),
				float(ext) / float(TRIALS) * 100.0])
	_lines.append("")


# ==========================================================================
# 判定
# ==========================================================================

func _verdict() -> void:
	_lines.append("## 节奏判定\n")
	var start := RegionDB.make(START_NODE)
	var cap := start.carrying_capacity_adults()
	var over := cap / 8.0
	_lines.append("- 起始节点承载力 **%.1f 人**，开局 8 人 → 压力 **%.2f**。" % [cap, 8.0 / cap])
	_lines.append("  压力 < 1 意味着开局是**可持续**的：土地养得起这个部落，所以初期不会有任何资源压力。")
	if 8.0 / cap < 1.0:
		_lines.append("  → 部落必须先**长大**才会撞上土地的天花板，这正是设计支柱「你被自己的成功推着往前走」。")
	_lines.append("- 设计目标：**第一次被迫迁徙落在第 5–8 个游戏年**（1x 档下约 20–32 现实分钟）。")
	_lines.append("- 时间尺度的自洽性检查：若 4x 是常用档（1 游戏年 = 1 分钟），")
	_lines.append("  那么 120–180 年的单局只需 2–3 小时，与文档 06.1 写的「单局 8–15 小时」**互相矛盾**。")
	_lines.append("  结论：**1x 才是常用档**，「常用档是 4x」这句话应当删掉。")
	_lines.append("")


# ==========================================================================
# 单次逐月追踪
# ==========================================================================

func _run_trace() -> void:
	Genome.seed_rng(BASE_SEED)
	var w := WorldState.new()
	w.setup(START_NODE, FOUNDERS, true, 24, 2)
	w.hunt_bias = 1.0
	print("起始节点：", w.region.name, "  承载力 %.1f 人" % w.capacity())
	print("劳动分配：15%% 狩猎")
	print("%-26s %-6s %-8s %-10s %-8s" % ["", "人口", "食物%", "猎物%", "饱食"])
	for d in 2400:
		if w.extinct:
			print("→ 第 %d 天灭绝" % w.day)
			break
		w.tick_day()
		if w.day % 120 == 0 or w.day == 1:
			var m := w.metrics()
			print("%-26s %-6d %-8.0f %-10.0f %-8.0f" % [
				"第%d年%s 第%d天" % [m["year"], "", m["day"]],
				m["population"], m["food_ratio"] * 100.0,
				m["prey_ratio"] * 100.0, m["satiety"]])
	print("")
	print("时间线：食物<20%% 第%s天  退化 第%s天  仓空 第%s天  饿死 第%s天" % [
		str(w.first_food_low), str(w.first_degraded),
		str(w.first_store_empty), str(w.first_death)])
	print("最终：", w.snapshot())
	for entry in w.log:
		print("  [%5d] %s" % [entry["day"], entry["msg"]])


# ==========================================================================
# 输出
# ==========================================================================

func _header() -> void:
	_lines.append("# 《万相缇洛斯》区域资源与迁徙节奏实测\n")
	_lines.append("> 由 `tools/resource_sim.gd` 自动生成，请勿手工编辑。\n")
	_lines.append("| 参数 | 值 |")
	_lines.append("|---|---|")
	_lines.append("| 起始节点 | `%s` |" % START_NODE)
	_lines.append("| 每次试验上限 | %d 天 ≈ %.0f 个游戏年（1 年 = %d 日） |" % [MAX_DAYS, MAX_DAYS / float(WorldState.DAYS_PER_YEAR), WorldState.DAYS_PER_YEAR])
	_lines.append("| 试验次数 | 每组 %d 次，取中位数 |" % TRIALS)
	_lines.append("| 时间换算 | 1 游戏日 = %.0f 秒 @1x；1 游戏年 = %.1f 现实分钟 @1x |" % [SEC_PER_DAY, float(WorldState.DAYS_PER_YEAR) * SEC_PER_DAY / 60.0])
	_lines.append("| 采集/狩猎速率 | 每人每日 %.1f / %.1f 食物单位 |" % [Region.GATHER_RATE, Region.HUNT_RATE])
	_lines.append("| 每人每日消耗 | %.1f |" % WorldState.FOOD_PER_PERSON_DAY)
	_lines.append("")


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		print("！无法写入 %s" % OUT_PATH)
		return
	f.store_string("\n".join(_lines) + "\n")
	f.close()


# ==========================================================================

func _fmt_day(d: float) -> String:
	if d < 0:
		return "从未"
	var years := d / float(WorldState.DAYS_PER_YEAR)
	var minutes := d * SEC_PER_DAY / 60.0
	return "第%.1f年(%.0f分@1x)" % [years, minutes]


static func _median(arr: Array) -> float:
	var vals: Array = []
	for v in arr:
		if float(v) >= 0.0:
			vals.append(float(v))
	if vals.is_empty():
		return -1.0
	vals.sort()
	var n := vals.size()
	if n % 2 == 1:
		return vals[n / 2]
	return (vals[n / 2 - 1] + vals[n / 2]) * 0.5
