extends SceneTree
## 遗传平衡模拟。运行：
##   ./tools/godot.sh --headless --script res://tools/balance_sim.gd
## 产出：reports/balance_report.md（原始数据）+ 终端摘要
##
## 目的：用数据检验设计文档里写下的断言，而不是靠手感。
## 全部随机数走 Genome.seed_rng，固定 BASE_SEED 即可完全复现。

var trials: int = 40
var years: int = 260              ## 约 20 个世代（13 年/代）
const BASE_SEED := 20240930
const REGION := &"green_throat"
const OUT_PATH := "res://reports/balance_report.md"
const SAMPLE_YEARS := [1, 13, 26, 52, 130, 260]

var _pool: Array = []
var _magic: float = 0.35
var _lines: Array = []


func _initialize() -> void:
	print("")
	print("=== 《万相缇洛斯》遗传平衡模拟 ===")
	if not BloodlineDB.ensure_loaded():
		print("数据加载失败：", BloodlineDB.load_error())
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--quick"):
		trials = 6
		years = 130
		print("（快速模式：%d 次试验 × %d 年，仅用于校验判定逻辑，数字不可引用）" % [trials, years])
	_pool = BloodlineDB.region_pool(REGION)
	_magic = BloodlineDB.region_magic(REGION)

	var t0 := Time.get_ticks_msec()
	print("区域 %s：血脉池 %d 条，魔力浓度 %.2f" % [REGION, _pool.size(), _magic])
	print("每组配置 %d 次试验 × %d 年（约 %.0f 个世代）" % [trials, years, years / Tribe.YEARS_PER_GENERATION])
	print("")

	_header()
	var exp_a := _run_experiment_a()
	var exp_b := _run_experiment_b()
	var exp_c := _run_chimera_reachability()
	var exp_d := _run_experiment_d()
	_verdicts(exp_a, exp_b, exp_d)
	_samples()
	_write_report()

	print("")
	print("总耗时 %.1f 秒，报告已写入 %s" % [(Time.get_ticks_msec() - t0) / 1000.0, OUT_PATH])
	quit()


# ==========================================================================
# 实验 A：近交累积速率 vs 奠基人数 / 营地容量
# ==========================================================================

func _exp_a_configs() -> Array:
	return [
		{"label": "奠基 5 人，容量 24", "founders": 5,  "cap": 24, "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
		{"label": "奠基 8 人，容量 24", "founders": 8,  "cap": 24, "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
		{"label": "奠基 12 人，容量 24", "founders": 12, "cap": 24, "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
		{"label": "奠基 16 人，容量 24", "founders": 16, "cap": 24, "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
		{"label": "奠基 24 人，容量 24", "founders": 24, "cap": 24, "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
		{"label": "奠基 8 人，容量 8（小营地）", "founders": 8, "cap": 8,  "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
		{"label": "奠基 5 人，容量 5（游群）", "founders": 5, "cap": 5,  "policy": Tribe.Policy.RANDOM, "gene_flow": 0.0},
	]


func _run_experiment_a() -> Array:
	print("── 实验 A：近交累积速率 vs 奠基人数 / 营地容量")
	_lines.append("## 实验 A：近交累积速率 vs 奠基人数 / 营地容量\n")
	_lines.append("配对策略固定为**随机配对**，无基因流。每组 %d 次试验，取中位数。\n" % trials)
	_lines.append("| 配置 | 灭绝率 | 第1年 F | 第13年 F | 第26年 F | 第52年 F | 第130年 F | 第260年 F | 第260年世代 | ΔF/代 | 隐含 Ne | F>0.25 所需世代 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")

	var results: Array = []
	for cfg in _exp_a_configs():
		var r := _run_config(cfg)
		results.append(r)
		var f: Dictionary = r["f_by_year"]
		print("  %-28s 灭绝 %2.0f%%  F260=%.3f (%d 代)  ΔF/代=%.4f  Ne≈%.0f" % [
			cfg["label"], r["extinction_rate"] * 100.0, f[260], r["median_generation"],
			r["df_per_gen"], r["implied_ne"]])
		_lines.append("| %s | %.0f%% | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %d | %.4f | %.0f | %s |" % [
			cfg["label"], r["extinction_rate"] * 100.0,
			f[1], f[13], f[26], f[52], f[130], f[260],
			r["median_generation"], r["df_per_gen"], r["implied_ne"],
			("—" if r["gen_f_over_025"] < 0 else "%.0f" % r["gen_f_over_025"])])
	_lines.append("")
	print("")
	return results


# ==========================================================================
# 实验 B：配对策略 × 基因流
# ==========================================================================

func _exp_b_configs() -> Array:
	var out: Array = []
	var policies := [Tribe.Policy.RANDOM, Tribe.Policy.AVOID_INBREEDING,
		Tribe.Policy.PLANNED_CHIMERA, Tribe.Policy.PURE_LINE]
	var flows := [0.0, 0.02]   # 0.02/年 ≈ 每代 23% 概率引入一名外来者
	for p in policies:
		for fl in flows:
			out.append({
				"label": "%s / %s" % [_policy_name(p), "封闭" if fl == 0.0 else "有联姻"],
				"founders": 12, "cap": 24, "policy": p, "gene_flow": fl,
			})
	return out


static func _policy_name(p: int) -> String:
	match p:
		Tribe.Policy.RANDOM: return "随机配对"
		Tribe.Policy.AVOID_INBREEDING: return "避开近亲"
		Tribe.Policy.PLANNED_CHIMERA: return "两代规划嵌合"
		Tribe.Policy.PURE_LINE: return "选型纯化"
	return "?"


func _run_experiment_b() -> Array:
	print("── 实验 B：配对策略 × 基因流（奠基 12 人，容量 24）")
	_lines.append("## 实验 B：配对策略 × 基因流\n")
	_lines.append("奠基 12 人，营地容量 24。`有联姻` = 每年 2% 概率引入一名无血缘外来者（约每代 23%）。\n")
	_lines.append("| 策略 / 基因流 | 灭绝率 | F(260年) | ΔF/代 | 隐含 Ne | BDI | 嵌合率 | 稀薄率 | 最高血浓 | 显征率 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|")

	var results: Array = []
	for cfg in _exp_b_configs():
		var r := _run_config(cfg)
		results.append(r)
		print("  %-22s 灭绝 %2.0f%%  F=%.3f Ne≈%3.0f BDI=%.3f 嵌合=%2.0f%% 稀薄=%2.0f%% 最高=%2d" % [
			cfg["label"], r["extinction_rate"] * 100.0, r["f_by_year"][260],
			r["implied_ne"], r["bdi"], r["chimera_rate"] * 100.0,
			r["dilute_rate"] * 100.0, r["max_top_titer"]])
		_lines.append("| %s | %.0f%% | %.3f | %.4f | %.0f | %.3f | %.0f%% | %.0f%% | %d | %.0f%% |" % [
			cfg["label"], r["extinction_rate"] * 100.0, r["f_by_year"][260],
			r["df_per_gen"], r["implied_ne"], r["bdi"], r["chimera_rate"] * 100.0,
			r["dilute_rate"] * 100.0, r["max_top_titer"], r["expressed_rate"] * 100.0])
	_lines.append("")
	print("")
	return results


# ==========================================================================
# 实验 C：嵌合到底多难达到
# ==========================================================================

func _run_chimera_reachability() -> Dictionary:
	print("── 实验 C：嵌合可达性（20 代内是否出现过嵌合个体）")
	_lines.append("## 实验 C：嵌合可达性\n")
	_lines.append("统计 20 个世代内「种群中至少出现过一只嵌合个体」的试验比例，以及嵌合率的时程。\n")
	_lines.append("| 策略 | 曾出现嵌合 | 第52年嵌合率 | 第130年嵌合率 | 第260年嵌合率 |")
	_lines.append("|---|---|---|---|---|")

	var out: Dictionary = {}
	for p in [Tribe.Policy.RANDOM, Tribe.Policy.AVOID_INBREEDING,
			Tribe.Policy.PLANNED_CHIMERA, Tribe.Policy.PURE_LINE]:
		var ever := 0
		var r52: Array = []
		var r130: Array = []
		var r260: Array = []
		for tr in trials:
			Genome.seed_rng(BASE_SEED + 555 + tr * 7919)
			var t := Tribe.new()
			t.found(12, _pool, _magic, 24)
			var seen := false
			for y in years:
				t.step(p, 0.0)
				if t.chimera_rate() > 0.0:
					seen = true
				if t.extinct:
					break
			if seen:
				ever += 1
			r52.append(_row_at(t, 52).get("chimera_rate", 0.0))
			r130.append(_row_at(t, 130).get("chimera_rate", 0.0))
			r260.append(_row_at(t, 260).get("chimera_rate", 0.0))
		var row := {
			"ever": float(ever) / float(trials),
			"r52": _median(r52), "r130": _median(r130), "r260": _median(r260),
		}
		out[_policy_name(p)] = row
		print("  %-14s 曾出现 %3.0f%%  嵌合率 52年 %2.0f%% / 130年 %2.0f%% / 260年 %2.0f%%" % [
			_policy_name(p), row["ever"] * 100.0, row["r52"] * 100.0,
			row["r130"] * 100.0, row["r260"] * 100.0])
		_lines.append("| %s | %.0f%% | %.0f%% | %.0f%% | %.0f%% |" % [
			_policy_name(p), row["ever"] * 100.0, row["r52"] * 100.0,
			row["r130"] * 100.0, row["r260"] * 100.0])
	_lines.append("")
	print("")
	return out


# ==========================================================================
# 实验 D：奠基者的血缘 —— 近交压力到底什么时候来
# ==========================================================================

func _exp_d_configs() -> Array:
	return [
		{"label": "8 人 / 互无血缘（乐观假设）", "founders": 8, "cap": 24,
			"policy": Tribe.Policy.RANDOM, "gene_flow": 0.0, "family": false},
		{"label": "8 人 / 一家人（2 父母 + 6 全同胞）", "founders": 8, "cap": 24,
			"policy": Tribe.Policy.RANDOM, "gene_flow": 0.0, "family": true},
		{"label": "12 人 / 一家人（2 父母 + 10 全同胞）", "founders": 12, "cap": 24,
			"policy": Tribe.Policy.RANDOM, "gene_flow": 0.0, "family": true},
		{"label": "8 人 / 一家人 + 避开近亲", "founders": 8, "cap": 24,
			"policy": Tribe.Policy.AVOID_INBREEDING, "gene_flow": 0.0, "family": true},
		{"label": "8 人 / 一家人 + 避开近亲 + 联姻", "founders": 8, "cap": 24,
			"policy": Tribe.Policy.AVOID_INBREEDING, "gene_flow": 0.02, "family": true},
	]


func _run_experiment_d() -> Array:
	print("── 实验 D：奠基者血缘对近交压力的影响")
	_lines.append("## 实验 D：奠基者的血缘 —— 近交压力什么时候来\n")
	_lines.append("实验 A/B 假设奠基者**互无血缘**（最乐观的情况）。但现实中出走另立部落的通常**是一家人**：")
	_lines.append("一对父母带着自己的成年子女。这样第二代个体就是**全同胞互配**，F 直接等于 0.25。\n")
	_lines.append("| 配置 | 灭绝率 | 第1年 F | 第13年 F | 第26年 F | 第52年 F | 第130年 F | 第260年 F | 第260年世代 | ΔF/代 | 隐含 Ne | F>0.25 所需世代 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")

	var results: Array = []
	for cfg in _exp_d_configs():
		var r := _run_config(cfg)
		results.append(r)
		var f: Dictionary = r["f_by_year"]
		print("  %-34s 灭绝 %2.0f%%  F1=%.3f F260=%.3f (%d 代)  F>0.25：%s" % [
			cfg["label"], r["extinction_rate"] * 100.0, f[1], f[260], r["median_generation"],
			("从未" if r["gen_f_over_025"] < 0 else "%.0f 代" % r["gen_f_over_025"])])
		_lines.append("| %s | %.0f%% | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %d | %.4f | %.0f | %s |" % [
			cfg["label"], r["extinction_rate"] * 100.0,
			f[1], f[13], f[26], f[52], f[130], f[260],
			r["median_generation"], r["df_per_gen"], r["implied_ne"],
			("—" if r["gen_f_over_025"] < 0 else "%.0f" % r["gen_f_over_025"])])
	_lines.append("")
	print("")
	return results


# ==========================================================================
# 单次运行的通用执行器
# ==========================================================================

func _run_config(cfg: Dictionary) -> Dictionary:
	var f_by_year := {}
	var bdi: Array = []
	var chimera: Array = []
	var dilute: Array = []
	var top_titer: Array = []
	var expressed: Array = []
	var generations: Array = []
	var pops: Array = []
	var f_end: Array = []
	var gen_first_over: Array = []
	var extinct_count := 0

	for tr in trials:
		Genome.seed_rng(BASE_SEED + tr * 7919)
		var t := Tribe.new()
		if bool(cfg.get("family", false)):
			t.found_family(cfg["founders"], _pool, _magic, cfg["cap"])
		else:
			t.found(cfg["founders"], _pool, _magic, cfg["cap"])
		var over_gen := -1
		for _y in years:
			t.step(cfg["policy"], cfg["gene_flow"])
			if over_gen < 0 and t.mean_inbreeding_adult() > 0.25:
				over_gen = t.current_generation()
			if t.extinct:
				break
		if t.extinct:
			extinct_count += 1
		if over_gen >= 0:
			gen_first_over.append(float(over_gen))

		for y in SAMPLE_YEARS:
			var row := _row_at(t, y)
			if not f_by_year.has(y):
				f_by_year[y] = []
			f_by_year[y].append(float(row.get("mean_f_adult", 0.0)))

		var last: Dictionary = _row_at(t, 99999)
		bdi.append(float(last.get("bdi", 0.0)))
		chimera.append(float(last.get("chimera_rate", 0.0)))
		dilute.append(float(last.get("dilute_rate", 0.0)))
		top_titer.append(float(last.get("max_top_titer", 0)))
		expressed.append(float(last.get("expressed_rate", 0.0)))
		generations.append(float(last.get("generation", 0)))
		pops.append(float(last.get("population", 0)))
		f_end.append(float(last.get("mean_f_adult", 0.0)))

	var f_med := {}
	for y in SAMPLE_YEARS:
		f_med[y] = _median(f_by_year[y])

	var med_gen := _median(generations)
	var df: float = (f_med[260] / med_gen) if med_gen > 0.0 else 0.0
	return {
		"extinction_rate": float(extinct_count) / float(trials),
		"f_by_year": f_med,
		"f_end_list": f_end,
		"median_generation": med_gen,
		"median_pop": _median(pops),
		"df_per_gen": df,
		"implied_ne": (1.0 / (2.0 * df)) if df > 0.0 else 0.0,
		"bdi": _median(bdi),
		"chimera_rate": _median(chimera),
		"dilute_rate": _median(dilute),
		"max_top_titer": _median(top_titer),
		"expressed_rate": _median(expressed),
		"gen_f_over_025": _median(gen_first_over) if not gen_first_over.is_empty() else -1.0,
		"gen_f_over_025_rate": float(gen_first_over.size()) / float(trials),
	}


func _row_at(t: Tribe, y: int) -> Dictionary:
	if t.history.is_empty():
		return {}
	if y < t.history.size():
		return t.history[y]
	return t.history[t.history.size() - 1]


# ==========================================================================
# 命题判定
# ==========================================================================

func _verdicts(exp_a: Array, exp_b: Array, exp_d: Array) -> void:
	_lines.append("## 命题判定\n")

	# P1：文档 02.6 声称「封闭部落 3–4 代内 I 系数冲破 0.25」
	var best := 1e9
	var best_label := ""
	for i in exp_a.size():
		var r: Dictionary = exp_a[i]
		if r["gen_f_over_025"] >= 0.0 and r["gen_f_over_025"] < best:
			best = r["gen_f_over_025"]
			best_label = _exp_a_configs()[i]["label"]
	# 文档原设定的部落：奠基 5 人、容量 24
	var cfg5: Dictionary = exp_a[0]
	var p1: bool = float(cfg5["gen_f_over_025"]) >= 0.0 and float(cfg5["gen_f_over_025"]) <= 4.0
	_lines.append("### P1 「封闭部落在 3–4 代内 F > 0.25」 —— **%s**\n" % ("成立" if p1 else "不成立"))
	_lines.append("- 「奠基 5 人 / 容量 24」（文档 06.10 的开局设定）：F 首次超过 0.25 需要 **%s**，260 年后 F = %.3f，隐含 Ne ≈ %.0f。"
		% [("从未发生" if cfg5["gen_f_over_025"] < 0.0 else "%.0f 代" % cfg5["gen_f_over_025"]),
			cfg5["f_by_year"][260], cfg5["implied_ne"]])
	_lines.append("- 全部配置里最快的一组是「%s」，需要 **%s**（该组灭绝率极高，见实验 A 表，属于「在灭绝前恰好越过阈值」而非可持续）。"
		% [best_label, ("从未发生" if best > 1e8 else "%.0f 代" % best)])
	_lines.append("- 真正的解法不在奠基人数，而在**奠基者的血缘**——见实验 D 与命题 P6。")
	_lines.append("")

	# P2：随机配对在封闭条件下会走向稀薄或灭绝
	var rand_closed: Dictionary = exp_b[0]
	var p2: bool = float(rand_closed["dilute_rate"]) > 0.2 or float(rand_closed["extinction_rate"]) > 0.2 or float(rand_closed["bdi"]) > 0.75
	_lines.append("### P2 「随机配对会走向血脉稀薄或灭绝」 —— **%s**\n" % ("成立" if p2 else "不成立"))
	_lines.append("- 随机配对 / 封闭：灭绝率 %.0f%%，260 年后 BDI = %.3f，稀薄率 %.0f%%，嵌合率 %.0f%%。"
		% [rand_closed["extinction_rate"] * 100.0, rand_closed["bdi"],
			rand_closed["dilute_rate"] * 100.0, rand_closed["chimera_rate"] * 100.0])
	_lines.append("")

	# P3：规划配对能跨 20 代存活
	var planned: Dictionary = exp_b[4]
	var p3: bool = float(planned["extinction_rate"]) < 0.2
	_lines.append("### P3 「会规划的玩家能稳定跨 20 代」 —— **%s**\n" % ("成立" if p3 else "不成立"))
	_lines.append("- 两代规划嵌合 / 封闭：灭绝率 %.0f%%，260 年后人口中位数 %.0f 人，最高血浓 %.0f，嵌合率 %.0f%%。"
		% [planned["extinction_rate"] * 100.0, planned["median_pop"],
			planned["max_top_titer"], planned["chimera_rate"] * 100.0])
	_lines.append("")

	# P4：基因流抑制 F
	var avoid_closed: Dictionary = exp_b[2]
	var avoid_open: Dictionary = exp_b[3]
	_lines.append("### P4 「基因流（联姻）抑制近交累积」 —— **%s**\n"
		% ("成立" if avoid_open["f_by_year"][260] < avoid_closed["f_by_year"][260] else "不成立"))
	_lines.append("- 避开近亲：封闭 F = %.3f（Ne ≈ %.0f）→ 有联姻 F = %.3f（Ne ≈ %.0f），降低 %.0f%%。"
		% [avoid_closed["f_by_year"][260], avoid_closed["implied_ne"],
			avoid_open["f_by_year"][260], avoid_open["implied_ne"],
			(1.0 - avoid_open["f_by_year"][260] / maxf(avoid_closed["f_by_year"][260], 1e-6)) * 100.0])
	_lines.append("")

	# P5：选型纯化加速近交
	var pure: Dictionary = exp_b[6]
	_lines.append("### P5 「玩家的纯化优化会加速近交（自己把自己逼出营地）」 —— **%s**\n"
		% ("成立" if pure["f_by_year"][260] > rand_closed["f_by_year"][260] else "不成立"))
	_lines.append("- 选型纯化 / 封闭：F = %.3f（Ne ≈ %.0f），vs 随机配对 F = %.3f（Ne ≈ %.0f）。加速倍数 %.2f×。"
		% [pure["f_by_year"][260], pure["implied_ne"],
			rand_closed["f_by_year"][260], rand_closed["implied_ne"],
			pure["f_by_year"][260] / maxf(rand_closed["f_by_year"][260], 1e-6)])
	_lines.append("")

	# P6：奠基者血缘是决定近交压力到来时间的主变量
	var unrelated: Dictionary = exp_d[0]
	var family: Dictionary = exp_d[1]
	var f52_family: float = family["f_by_year"][52]
	var f52_unrel: float = unrelated["f_by_year"][52]
	var p6: bool = f52_family > 2.0 * maxf(f52_unrel, 1e-6) and float(family["implied_ne"]) < float(unrelated["implied_ne"])
	_lines.append("### P6 「奠基者是否为一家人，决定近交压力何时到来」 —— **%s**\n" % ("成立" if p6 else "不成立"))
	_lines.append("- 8 人互无血缘：第 52 年（约 4 代）F = %.3f，ΔF/代 = %.4f，隐含 Ne ≈ %.0f，F 首次超过 0.25 需要 **%s**。"
		% [f52_unrel, unrelated["df_per_gen"], unrelated["implied_ne"],
			("从未" if unrelated["gen_f_over_025"] < 0 else "%.0f 代" % unrelated["gen_f_over_025"])])
	_lines.append("- 8 人一家人：第 52 年 F = %.3f（**%.1f 倍**），ΔF/代 = %.4f，隐含 Ne ≈ %.0f，F 首次超过 0.25 需要 **%s**。"
		% [f52_family, f52_family / maxf(f52_unrel, 1e-6), family["df_per_gen"],
			family["implied_ne"],
			("从未" if family["gen_f_over_025"] < 0 else "%.0f 代" % family["gen_f_over_025"])])
	_lines.append("- 注：两组的第 1 年 F 都是 0.000。奠基父母的子女本身不是近交产物（父母无血缘），")
	_lines.append("  但他们彼此是**全同胞**，所以从第二代起 F 直接跳到 0.25。压力不是渐进的，是断崖式的。")
	_lines.append("")


# ==========================================================================
# 样例个体
# ==========================================================================

func _samples() -> void:
	_lines.append("## 样例个体（固定种子，第 260 年）\n")
	for p in [Tribe.Policy.RANDOM, Tribe.Policy.AVOID_INBREEDING,
			Tribe.Policy.PLANNED_CHIMERA, Tribe.Policy.PURE_LINE]:
		Genome.seed_rng(BASE_SEED + 999)
		var t := Tribe.new()
		t.found(12, _pool, _magic, 24)
		for _y in years:
			t.step(p, 0.0)
			if t.extinct:
				break
		_lines.append("**%s**（第 %d 代，人口 %d）\n" % [_policy_name(p), t.current_generation(), t.population()])
		_lines.append("```")
		var ids: Array = t.beasts.keys()
		var shown := 0
		for id in ids:
			if shown >= 3:
				break
			_lines.append(t.beasts[id].label())
			shown += 1
		_lines.append("```")
		_lines.append("")
		print("  样例 %s：第 %d 代 人口 %d" % [_policy_name(p), t.current_generation(), t.population()])


# ==========================================================================
# 输出
# ==========================================================================

func _header() -> void:
	_lines.append("# 《万相缇洛斯》遗传平衡实测报告\n")
	_lines.append("> 由 `tools/balance_sim.gd` 自动生成，请勿手工编辑。\n")
	_lines.append("| 参数 | 值 |")
	_lines.append("|---|---|")
	_lines.append("| 区域 | `%s`（血脉池 %d 条，魔力 %.2f） |" % [REGION, _pool.size(), _magic])
	_lines.append("| 每次试验 | %d 年 ≈ %.0f 个世代（%d 年/代） |" % [years, years / Tribe.YEARS_PER_GENERATION, int(Tribe.YEARS_PER_GENERATION)])
	_lines.append("| 试验次数 | 每组 %d 次，取中位数 |" % trials)
	_lines.append("| 随机种子 | %d + trial×7919 |" % BASE_SEED)
	_lines.append("| 人口模型 | 重叠世代，寿命 %.0f–%.0f 年，性成熟 %.0f 岁，繁育间隔 %.0f 年 |"
		% [Tribe.LIFESPAN_MIN, Tribe.LIFESPAN_MAX, Tribe.MATURITY_AGE, Tribe.BREEDING_INTERVAL])
	_lines.append("| 说明 | F 为**已达性成熟个体**的平均近交系数 |")
	_lines.append("")


func _write_report() -> void:
	var text := "\n".join(_lines) + "\n"
	DirAccess.make_dir_recursive_absolute("res://reports")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		print("！无法写入报告：", OUT_PATH)
		return
	f.store_string(text)
	f.close()


# ==========================================================================
# 统计工具
# ==========================================================================

static func _median(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var a: Array = arr.duplicate()
	a.sort()
	var n := a.size()
	if n % 2 == 1:
		return float(a[n / 2])
	return (float(a[n / 2 - 1]) + float(a[n / 2])) * 0.5
