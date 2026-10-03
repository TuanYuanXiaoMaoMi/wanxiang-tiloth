extends SceneTree
## sim/ 层的单元测试。运行：
##   ./tools/godot.sh --headless --script res://tools/run_tests.gd
## 退出码非 0 表示有失败项。

var _pass := 0
var _fail := 0
var _section := ""


func _test_descent() -> void:
	section("继嗣制度")
	# 六种模式各自产出什么名字
	check(Descent.child_surname(Descent.Mode.MATRONYMIC, "雪潮", "石", "空喉", "苔", true)
		== "空喉子", "母名制：名字挂母亲的名")
	check(Descent.child_surname(Descent.Mode.MATRONYMIC, "雪潮", "石", "空喉", "苔", false)
		== "空喉女", "母名制：女儿用「女」")
	check(Descent.child_surname(Descent.Mode.PATRONYMIC, "雪潮", "石", "空喉", "苔", true)
		== "雪潮子", "父名制：名字挂父亲的名")
	check(Descent.child_surname(Descent.Mode.MATRILINEAL, "雪潮", "石", "空喉", "苔", true)
		== "苔", "母系：原样继承母姓（不取首字）")
	check(Descent.child_surname(Descent.Mode.PATRILINEAL, "雪潮", "石", "空喉", "苔", true)
		== "石", "父系：原样继承父姓")
	check(Descent.child_surname(Descent.Mode.BILATERAL, "雪潮", "石", "空喉", "苔", true)
		== "石苔", "双系：父姓首字 + 母姓首字")
	check(Descent.child_surname(Descent.Mode.BILATERAL, "雪潮", "石", "空喉", "石", true)
		== "石", "双系：同字不重复")

	# 阶段与解锁
	check(Descent.stage_for_population(10) == Descent.Stage.BAND, "人口 10 → 游团")
	check(Descent.stage_for_population(20) == Descent.Stage.CLAN, "人口 20 → 氏族")
	check(Descent.stage_for_population(30) == Descent.Stage.CHIEFDOM, "人口 30 → 酋邦")
	check(Descent.is_unlocked(Descent.Mode.MATRONYMIC, 8), "游团可用母名制")
	check(not Descent.is_unlocked(Descent.Mode.BILATERAL, 8), "游团不能用双系")
	check(Descent.is_unlocked(Descent.Mode.MATRILINEAL, 18), "氏族可用母系")
	check(not Descent.is_unlocked(Descent.Mode.DOUBLE, 18), "氏族不能用双重继嗣")
	check(Descent.is_unlocked(Descent.Mode.DOUBLE, 30), "酋邦可用双重继嗣")

	# 改制开销随跨阶段数增加
	check(Descent.reform_cost(Descent.Mode.MATRONYMIC, Descent.Mode.MATRILINEAL)
		< Descent.reform_cost(Descent.Mode.MATRONYMIC, Descent.Mode.BILATERAL),
		"跨阶段改制更贵")
	check(Descent.reform_cost(Descent.Mode.PATRILINEAL, Descent.Mode.PATRILINEAL) == 0.0,
		"不改制不要钱")

	# 机制后果
	check(Descent.incoming_sex(Descent.Mode.MATRILINEAL) == Beast.Sex.MALE,
		"母系是从妻居：嫁进来的是男人")
	check(Descent.incoming_sex(Descent.Mode.PATRILINEAL) == Beast.Sex.FEMALE,
		"父系是从夫居：嫁进来的是女人")
	check(Descent.has_clan_exogamy(Descent.Mode.DOUBLE), "双重继嗣有同姓不婚")
	check(not Descent.has_clan_exogamy(Descent.Mode.BILATERAL), "双系没有同姓不婚")

	# 兄弟姐妹要归到同一组（不能因为「子 / 女」被拆开）
	var son := Beast.new(); son.name = "冷声"; son.surname = "空喉子"
	var dau := Beast.new(); dau.name = "轻尾"; dau.surname = "空喉女"
	check(Descent.group_label(son, Descent.Mode.MATRONYMIC)
		== Descent.group_label(dau, Descent.Mode.MATRONYMIC),
		"母名制下兄弟姐妹归到同一个「家」")


## 防止存档静默丢状态。
##
## 存档原来是一份**手写的关键词白名单**，后果是：每加一个新系统，
## 它的状态就悄悄掉出存档，而**没有任何测试会说话**。
## 这个测试把「漏存」变成「测试挂掉」。
##
## 已经漏掉的先记进 KNOWN_UNSAVED（这是一笔明确的债），
## 但**新加的字段必须二选一**：进 to_dict，或者进这两份清单之一。
## 把整个世界的状态压成一个字符串，用于逐字段比对。
## 有一条漏掉字段，两条轨迹的指纹就会不一样。
func _fingerprint(w: WorldState) -> String:
	var L: Array = []
	L.append("world turn=%d day=%d food=%.6f sat=%.6f starve=%.6f" % [
		w.turn, w.day, w.food_store, w.satiety, w._starve_debt])
	L.append("faith=%.6f morale=%.6f forced=%d migr=%d extinct=%s" % [
		w.faith, w.morale, w.forced_pairs, w.migrations, str(w.extinct)])
	L.append("hunt_ratio=%.6f bias=%.6f policy=%d flow=%.6f camp=%d" % [
		w.hunt_ratio, w.hunt_bias, w.policy, w.gene_flow_per_year, w.camp_capacity])
	L.append("transit=%s target=%s left=%d route=%s" % [
		str(w.in_transit), String(w.transit_target), w.transit_turns_left,
		str(w.transit_route)])
	L.append("timeline=%d,%d,%d,%d,%d" % [w.first_food_low, w.first_degraded,
		w.first_store_empty, w.first_satiety_low, w.first_death])
	var kn: Array = []
	for k in w.known: kn.append(String(k))
	kn.sort()
	var ad: Array = []
	for k in w.adopted: ad.append(String(k))
	ad.sort()
	L.append("known=%s" % ",".join(kn))
	L.append("adopted=%s" % ",".join(ad))
	var sk: Array = w.stats.keys()
	sk.sort()
	for k in sk:
		L.append("stat %s=%.6f" % [k, float(w.stats[k])])
	L.append("region food=%.6f prey=%.6f wood=%.6f stone=%.6f cry=%.6f herb=%.6f low=%d" % [
		w.region.food_stock, w.region.prey_stock, w.region.wood, w.region.stone,
		w.region.crystal, w.region.herb, w.region.low_stock_days])
	var sites: Array = []
	for st in w.site_map.sites:
		sites.append("%d:%d:%d" % [int(st["id"]), int(st["kind"]), (st["workers"] as Array).size()])
	L.append("sites=%s" % ",".join(sites))
	var asg: Array = []
	var akeys: Array = w.assignments.keys()
	akeys.sort()
	for k in akeys:
		asg.append("%d>%d" % [int(k), int(w.assignments[k])])
	L.append("assign=%s" % ",".join(asg))

	L.append("tribe mode=%d next=%d year=%d kin=%.4f defect=%.4f planned=%s exo=%s" % [
		w.tribe.descent_mode, w.tribe.next_id, w.tribe.year, w.tribe.kin_avoid,
		w.tribe.defect_resist, str(w.tribe.planned_pairing), str(w.tribe.clan_exogamy)])
	L.append("tribe stat=%d/%d/%d/%d/%d extinct=%s" % [w.tribe.stat_births,
		w.tribe.stat_deaths, w.tribe.stat_defect_births, w.tribe.stat_inbreed_births,
		w.tribe.stat_chimera_births, str(w.tribe.extinct)])
	var rk: Array = w.tribe.relations.keys()
	rk.sort()
	for k in rk:
		L.append("rel %s=%.6f" % [String(k), float(w.tribe.relations[k])])
	var ids: Array = w.tribe.beasts.keys()
	ids.sort()
	for id in ids:
		var b: Beast = w.tribe.beasts[id]
		L.append("b %d|%s|%s|%s|gen%d|f%d|m%d|age%.4f|life%.4f|cd%.2f|preg%s|sid%d|act%d|" % [
			b.id, str(b.sex), b.surname, b.name, b.generation, b.father, b.mother,
			b.age, b.lifespan, b.breed_cooldown, str(b.pregnant), b.site_id, b.activity])
		L.append("b %d traits=%s hobb=%s mood=%.4f partner=%d forced=%d pf=%d/%s/%s" % [
			b.id, str(b.traits), str(b.hobbies), b.mood, b.partner_id,
			b.forced_pair_with, b.pending_father, b.pending_father_surname,
			b.pending_father_name])
		L.append("b %d thought=%s story=%s" % [b.id, b.thought, str(b.story)])
		var g: Genome = b.genome
		if g != null:
			var tk: Array = g.titers.keys()
			tk.sort()
			var ts: Array = []
			for k in tk: ts.append("%s=%d" % [String(k), int(g.titers[k])])
			L.append("b %d g %s F=%.6f def=%s" % [b.id, ",".join(ts), g.inbreeding, str(g.defects)])
	return "\n".join(L)


func _test_save_trajectory() -> void:
	section("存档轨迹（抓遗漏字段的唯一可靠方法）")
	Genome.seed_rng(20250101)
	var wd := WorldGen.generate(20250101, 4)
	RegionDB.load_world(wd)
	var a := WorldState.new()
	a.setup(wd["start_node"], 12, true, 24, 2)
	# 先跑出一局有内容的状态：关系、生育、知识、制度、退化
	for _t in 14:
		if a.extinct: break
		a.end_turn()
	for id in Knowledge.ALL_IDS:
		if a.can_adopt(id):
			a.adopt(id)
	for m in Descent.ALL_MODES:
		if a.can_reform_to(m):
			a.reform_descent(m)
			break
	check(a.turn > 10, "轨迹测试的前置世界已跑到第 10 回合以上", "实际 %d" % a.turn)
	check(a.tribe.beasts.size() > 8, "前置世界人口足够",
		"实际 %d" % a.tribe.beasts.size())

	var snap := a.to_dict()
	# 存档必须真的能变成字节（Vector2 / StringName / 嵌套字典）
	var bytes := var_to_bytes(snap)
	check(bytes.size() > 1000, "存档能序列化成字节", "%d 字节" % bytes.size())
	var reparsed: Variant = bytes_to_var(bytes)
	check(typeof(reparsed) == TYPE_DICTIONARY, "存档能反序列化回来")

	var b := WorldState.new()
	check(b.load_from_dict(reparsed), "读档成功")

	# 走一遍真正的写盘/读盘。内存往返过了不代表文件往返也过 ——
	# store_var 那条路径要处理 Vector2 / StringName，是另一套编码。
	var tmp := "user://__test_save.dat"
	check(a.save_to_file(tmp), "写盘成功")
	check(FileAccess.file_exists(tmp), "存档文件已生成")
	var c := WorldState.new()
	check(c.load_from_file(tmp), "从文件读档成功")
	check(_fingerprint(a) == _fingerprint(c), "文件往返后的状态与内存一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# 两条轨迹各自持有随机数状态 —— Genome.rng 是全局的，
	# 不分开管理的话，跑 A 会污染 B 的随机流。
	var rng_a := {"seed": int(snap["rng"]["seed"]), "state": int(snap["rng"]["state"])}
	var rng_b := {"seed": rng_a["seed"], "state": rng_a["state"]}

	check(_fingerprint(a) == _fingerprint(b), "读档瞬间的状态与原世界一致")

	var diverged_at := -1
	for step in 8:
		Genome.rng.seed = rng_a["seed"]
		Genome.rng.state = rng_a["state"]
		a.end_turn()
		rng_a = {"seed": Genome.rng.seed, "state": Genome.rng.state}

		Genome.rng.seed = rng_b["seed"]
		Genome.rng.state = rng_b["state"]
		b.end_turn()
		rng_b = {"seed": Genome.rng.seed, "state": Genome.rng.state}

		var fa := _fingerprint(a)
		var fb := _fingerprint(b)
		if fa != fb and diverged_at < 0:
			diverged_at = step
			# 打出第一个不同的那一行，方便定位
			var la := fa.split("\n")
			var lb := fb.split("\n")
			for i in mini(la.size(), lb.size()):
				if la[i] != lb[i]:
					print("      首个差异（第 %d 回合，第 %d 行）" % [step + 1, i])
					print("        A: %s" % la[i])
					print("        B: %s" % lb[i])
					break
			if la.size() != lb.size():
				print("      行数不同：A %d 行，B %d 行" % [la.size(), lb.size()])
	check(diverged_at < 0, "读档后跑 8 回合与原轨迹逐字段完全相同",
		"第 %d 回合开始分岔" % (diverged_at + 1) if diverged_at >= 0 else "")


func _test_save_coverage() -> void:
	section("存档覆盖（防状态静默漏存）")

	# 可以由其他状态重建、或者本来就该每局重来的，不必持久化
	# 可以由其他状态重建、或者本来就该每局重来的，不必持久化
	var transient := [
		"region", "site_map",           # 由 node_id 重建
		"assignments", "auto_assign",   # 每回合重新派工
		"last_gathered", "last_hunted", # 只用于本回合统计
		"new_discoveries", "turn_log", "record_history",
		"transit_route",                # 由 transit_target 重建
	]
	# 已知的债：**确实该存但这一版还没存**。
	# 新增的漏存不许往这里加 —— 往 to_dict 里加，或者写进 transient 并说明理由。
	# **这份债已经还清了。** 现在不该再有"该存却没存"的字段 ——
	# 将来若真的要往这里加，必须同时写清楚为什么它可以不存。
	var known_unsaved := []
	# 存是存了，只是放在 to_dict 的某个子字典里（测试只看顶层键，所以要单独点名）
	var nested := [
		"first_food_low", "first_degraded", "first_store_empty",
		"first_satiety_low", "first_death",       # → to_dict()["timeline"]
	]

	var w := WorldState.new()
	WorldGen.ensure_loaded()
	var wd := WorldGen.generate(4242, 4)
	RegionDB.load_world(wd)
	w.setup(wd["start_node"], 12, true, 24, 2)

	var saved := {}
	for k in w.to_dict().keys():
		saved[String(k)] = true

	var undeclared: Array = []
	for p in w.get_script().get_script_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var nm := String(p.get("name", ""))
		if nm == "" or nm.begins_with("_"):
			continue
		if saved.has(nm) or transient.has(nm) or known_unsaved.has(nm) or nested.has(nm):
			continue
		undeclared.append(nm)

	check(undeclared.is_empty(),
		"新增状态字段必须二选一：进 to_dict，或进 transient / known_unsaved 清单",
		"没归属的有：%s" % ", ".join(undeclared))

	# 清单本身不该留僵尸条目（字段删了、清单还在）
	var all_names := {}
	for p in w.get_script().get_script_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			all_names[String(p.get("name", ""))] = true
	var stale: Array = []
	for nm in transient + known_unsaved + nested:
		if not all_names.has(nm):
			stale.append(nm)
	check(stale.is_empty(), "清单里没有已删除的僵尸字段", "僵尸：%s" % ", ".join(stale))


func _test_knowledge() -> void:
	section("知识树")
	# 每个节点都要自洽：前置存在、分支合法、开销非负
	var bad_req := 0
	var bad_tier := 0
	for id in Knowledge.ALL_IDS:
		for r in Knowledge.requires_of(id):
			if not Knowledge.NODES.has(r):
				bad_req += 1
		if Knowledge.tier_of(id) < 0:
			bad_tier += 1
	check(bad_req == 0, "所有前置知识都存在", "坏引用 %d 个" % bad_req)
	check(bad_tier == 0, "所有节点层级合法")
	check(Knowledge.ALL_IDS.size() >= 20, "至少 20 个知识节点",
		"实际 %d" % Knowledge.ALL_IDS.size())

	# 前置必须比自身早（不能成环、不能倒挂）
	var inverted := 0
	for id in Knowledge.ALL_IDS:
		for r in Knowledge.requires_of(id):
			if Knowledge.tier_of(r) >= Knowledge.tier_of(id):
				inverted += 1
	check(inverted == 0, "前置的层级严格小于自身（无环、不倒挂）",
		"倒挂 %d 处" % inverted)

	# 触发条件：开局项之外，都不该在空统计下触发
	var stats := {}
	var free_starts := 0
	for id in Knowledge.ALL_IDS:
		var kind := String(Knowledge.trigger_of(id).get("kind", ""))
		if kind == "start":
			free_starts += 1
			check(Knowledge.trigger_met(id, stats), "开局项在空统计下即满足：%s" % Knowledge.node_name(id))
			check(Knowledge.cost_of(id) <= 0.0, "开局项不该收费：%s" % Knowledge.node_name(id))
		else:
			check(not Knowledge.trigger_met(id, stats),
				"未经历事件时不该触发：%s" % Knowledge.node_name(id))
	check(free_starts == 2, "恰好两项开局知识（用火、母名制）", "实际 %d" % free_starts)

	# 触发条件必须能真的被满足
	var full := {
		"gathered": 99999.0, "hunted": 99999.0, "hunt_crew_max": 99.0,
		"deaths": 99.0, "defect_births": 99.0, "inbreed_births": 99.0,
		"chimera_births": 99.0, "max_pop": 99.0, "migrations": 99.0,
		"faith_peak": 999.0, "dominant_male": 99.0, "forced_pairs": 99.0,
	}
	var unmet := 0
	for id in Knowledge.ALL_IDS:
		if not Knowledge.trigger_met(id, full):
			unmet += 1
	check(unmet == 0, "所有触发条件都能被满足", "永远触发不了的有 %d 项" % unmet)

	# 效果键必须在界面上有可读文案（否则会漏成 granary_mult 1.35）
	var no_text := 0
	for id in Knowledge.ALL_IDS:
		for k in Knowledge.effects_of(id):
			if not Knowledge.EFFECT_TEXT.has(String(k)):
				no_text += 1
	check(no_text == 0, "所有效果键都有中文说明", "缺说明 %d 个" % no_text)

	# k_value / k_flag 类效果键**只能有一个节点定义**。
	# 因为 k_value() 返回的是第一个匹配，两个节点抢同一个键时，
	# 结果取决于字典遍历顺序 —— 不确定，而且静默错。
	# （这个约束是实测加第七种制度时撞出来的。）
	var value_keys := ["transit_forage", "kin_avoid", "gene_flow", "morale_base"]
	var flag_keys := ["clan_exogamy", "planned_pairing", "force_pair_mercy"]
	var owners := {}
	var dup_keys: Array = []
	for id in Knowledge.ALL_IDS:
		for k in Knowledge.effects_of(id):
			var ks := String(k)
			if not (value_keys.has(ks) or flag_keys.has(ks)):
				continue
			if owners.has(ks):
				dup_keys.append("%s（%s 与 %s）" % [ks, owners[ks], Knowledge.node_name(id)])
			else:
				owners[ks] = Knowledge.node_name(id)
	check(dup_keys.is_empty(), "单选类效果键没有被两个节点重复定义",
		"重复：%s" % ", ".join(dup_keys))

	# 制度解锁：每个制度都要有知识能解锁
	for m in Descent.ALL_MODES:
		var found := false
		for id in Knowledge.ALL_IDS:
			if Knowledge.unlocks_descent(id) == m:
				found = true
		check(found, "制度「%s」有知识可以解锁" % Descent.mode_name(m))

	check(Knowledge.effect_text("granary_mult", 1.35) == "粮仓上限 ×1.35",
		"效果文案可读")
	check(Knowledge.effect_text("gene_flow", 0.10) == "每年 10% 概率有外来者加入",
		"百分比类效果文案正确")


func _initialize() -> void:
	print("")
	print("=== 《万相缇洛斯》sim 层单元测试 ===")
	if not BloodlineDB.ensure_loaded():
		print("✗ 数据加载失败：", BloodlineDB.load_error())
		quit(1)
		return

	_test_db()
	_test_bands()
	_test_chimera_rules()
	_test_kinship()
	_test_purify_and_dilution()
	_test_atavism_rate()
	_test_trim()
	_test_diversity()
	_test_save_roundtrip()
	_test_determinism()
	_test_tribe_smoke()
	_test_descent()
	_test_knowledge()
	_test_save_coverage()
	_test_save_trajectory()

	print("")
	print("=== 通过 %d / 失败 %d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --------------------------------------------------------------------------

func check(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		print("  ✗ ", name, "   ", detail)


func check_approx(actual: float, expected: float, tol: float, name: String) -> void:
	check(absf(actual - expected) <= tol, name,
		"实际 %.5f，期望 %.5f（容差 %.5f）" % [actual, expected, tol])


func section(title: String) -> void:
	_section = title
	print("")
	print("── ", title)


# --------------------------------------------------------------------------

func _test_db() -> void:
	section("数据完整性")
	# **断言不变量，不断言内容。**
	# 这里原来写死了「7 个类群 / 16 条血脉 / 21 组嵌合」，后果是：
	# 往 genetics.json 里加一条血脉（本来只是改数据）会让测试挂掉。
	# 内容会变，不变量不该变。
	var nc := BloodlineDB.clade_ids().size()
	check(nc >= 2, "至少有 2 个类群", "实际 %d" % nc)
	check(BloodlineDB.bloodline_ids().size() >= nc, "血脉数不少于类群数",
		"%d 条血脉 / %d 个类群" % [BloodlineDB.bloodline_ids().size(), nc])

	var all_mapped := true
	for b in BloodlineDB.bloodline_ids():
		if BloodlineDB.clade_of(b) == &"":
			all_mapped = false
	check(all_mapped, "每条血脉都归属某个类群")

	# 每一对类群都应**恰好**有一条嵌合：翅膀数 = C(n,2)
	var pairs := {}
	for c1 in BloodlineDB.clade_ids():
		for c2 in BloodlineDB.clade_ids():
			if c1 == c2:
				continue
			pairs[BloodlineDB.pair_key(c1, c2)] = true
	var expect_chimeras := nc * (nc - 1) / 2
	check(pairs.size() == expect_chimeras, "类群两两组合数 = C(%d,2)" % nc,
		"实际 %d，期望 %d" % [pairs.size(), expect_chimeras])
	check(BloodlineDB.chimera_count() == expect_chimeras,
		"嵌合组数恰好覆盖所有类群对",
		"实际 %d 组，类群对 %d 组" % [BloodlineDB.chimera_count(), expect_chimeras])
	check(BloodlineDB.chimera_for(&"fel_cat", &"acc_hawk").get("id", &"") == &"chimera_sky_hunter",
		"影类 × 羽类 → 天猎")
	check(BloodlineDB.chimera_for(&"can_wolf", &"vul_fox").is_empty(),
		"群类内部（狼 × 狐）不构成嵌合")


func _test_bands() -> void:
	section("血浓区间边界（文档 02.3）")
	var cases := {1: Genome.Band.DARK, 14: Genome.Band.DARK, 15: Genome.Band.HIDDEN,
		34: Genome.Band.HIDDEN, 35: Genome.Band.LATENT, 59: Genome.Band.LATENT,
		60: Genome.Band.EXPRESSED, 100: Genome.Band.EXPRESSED}
	for t in cases:
		var g := Genome.from_titers({"fel_cat": t})
		check(g.band(&"fel_cat") == cases[t], "血浓 %d → 区间 %d" % [t, cases[t]],
			"实际 %d" % g.band(&"fel_cat"))
	var zero := Genome.from_titers({"fel_cat": 0})
	check(zero.band(&"fel_cat") == Genome.Band.NONE, "血浓 0 → 无")
	check(Genome.from_titers({"fel_cat": 20}).is_dilute(), "只有血浓 20 → 血脉稀薄")
	check(not Genome.from_titers({"fel_cat": 35}).is_dilute(), "血浓 35 → 不算稀薄")


func _test_chimera_rules() -> void:
	section("嵌合三条件（文档 02.4）")
	check(not Genome.from_titers({"fel_cat": 50, "acc_hawk": 50}).chimeras().is_empty(),
		"50/50 不同类群 → 嵌合成立")
	check(Genome.from_titers({"fel_cat": 50, "acc_hawk": 65}).chimeras().is_empty() == false,
		"差 15 → 嵌合成立（边界内）")
	check(Genome.from_titers({"fel_cat": 50, "acc_hawk": 66}).chimeras().is_empty(),
		"差 16 → 嵌合不成立（越界）")
	check(Genome.from_titers({"fel_cat": 34, "acc_hawk": 40}).chimeras().is_empty(),
		"一条低于 35 → 嵌合不成立")
	check(Genome.from_titers({"fel_cat": 50, "fel_leo": 50}).chimeras().is_empty(),
		"同类群（猫 × 大猫）→ 嵌合不成立")
	check(Genome.from_titers({"fel_cat": 20, "acc_hawk": 20}).is_dilute(),
		"全部血浓 20 → 稀薄且不可能嵌合")


func _test_kinship() -> void:
	section("亲缘系数 φ（Wright 递推）")
	# 建立一份手工谱系：
	#   1♂ 2♀ 6♀ 8♂ 10♀ 为互无血缘的奠基者
	#   3,4 = (1,2) 全同胞 ; 5 = (1,6) 与 3,4 为半同胞
	#   7 = (3,8) ; 9 = (4,10) ; 7 与 9 为表亲
	var p := Pedigree.new()
	for f in [1, 2, 6, 8, 10]:
		p.add(f, -1, -1, 0.0)
	p.add(3, 1, 2, p.offspring_inbreeding(1, 2))
	p.add(4, 1, 2, p.offspring_inbreeding(1, 2))
	p.add(5, 1, 6, p.offspring_inbreeding(1, 6))
	p.add(7, 3, 8, p.offspring_inbreeding(3, 8))
	p.add(9, 4, 10, p.offspring_inbreeding(4, 10))

	check_approx(p.kinship(1, 2), 0.0, 1e-9, "无血缘奠基者 φ = 0")
	check_approx(p.kinship(1, 3), 0.25, 1e-9, "父女 φ = 0.25")
	check_approx(p.kinship(3, 4), 0.25, 1e-9, "全同胞 φ = 0.25")
	check_approx(p.kinship(3, 5), 0.125, 1e-9, "半同胞 φ = 0.125")
	check_approx(p.kinship(7, 9), 0.0625, 1e-9, "表亲 φ = 0.0625")
	check_approx(p.offspring_inbreeding(3, 4), 0.25, 1e-9, "全同胞交配的子代 F = 0.25")
	check_approx(p.offspring_inbreeding(7, 9), 0.0625, 1e-9, "表亲交配的子代 F = 0.0625")

	# 记忆化应显著减少重复计算
	p.clear_cache()
	var before := p.call_count()
	for _i in 50:
		p.kinship(7, 9)
	check(p.call_count() - before < 50 * 20, "递推有记忆化（50 次重复查询调用数有限）",
		"调用数 %d" % (p.call_count() - before))


func _test_purify_and_dilution() -> void:
	section("纯化加固与混血稀释（文档 02.5）")
	# 纯化：父母双方同血脉均 ≥60 → 期望值 +6
	Genome.seed_rng(12345)
	var total := 0.0
	var n := 20000
	for _i in n:
		total += float(Genome._inherit_one(60, 60, 0.0))
	check_approx(total / float(n), 66.0, 0.35, "父母血浓均 60 → 子代期望 ≈ 66（60+6）")

	Genome.seed_rng(999)
	var total2 := 0.0
	for _i in n:
		total2 += float(Genome._inherit_one(50, 50, 0.0))
	check_approx(total2 / float(n), 50.0, 0.35, "父母血浓均 50（未达 60）→ 无纯化，期望 ≈ 50")

	# 稀释：不同类群各有一条 ≥40 的血脉 → 各 −3
	var child := Genome.from_titers({"fel_cat": 50, "acc_hawk": 50})
	var pa := Genome.from_titers({"fel_cat": 90})
	var pb := Genome.from_titers({"acc_hawk": 90})
	Genome._apply_dilution(child, pa, pb)
	check(int(child.titers[&"fel_cat"]) == 47 and int(child.titers[&"acc_hawk"]) == 47,
		"跨类群强血脉 → 各 −3", "实际 %s" % str(child.titers))

	# 同类群不触发稀释
	var child2 := Genome.from_titers({"fel_cat": 50, "fel_leo": 50})
	var pa2 := Genome.from_titers({"fel_cat": 90})
	var pb2 := Genome.from_titers({"fel_leo": 90})
	Genome._apply_dilution(child2, pa2, pb2)
	check(int(child2.titers[&"fel_cat"]) == 50 and int(child2.titers[&"fel_leo"]) == 50,
		"同类群强血脉 → 不稀释", "实际 %s" % str(child2.titers))

	# 只有一方有强血脉 → 不稀释
	var child3 := Genome.from_titers({"fel_cat": 50, "acc_hawk": 50})
	Genome._apply_dilution(child3, Genome.from_titers({"fel_cat": 90}),
		Genome.from_titers({"acc_hawk": 20}))
	check(int(child3.titers[&"fel_cat"]) == 50, "只有一方达 40 → 不稀释")


func _test_atavism_rate() -> void:
	section("暗池返祖概率（文档 02.5）")
	Genome.seed_rng(4242)
	var hits := 0
	var n := 100000
	for _i in n:
		if Genome._inherit_one(10, 14, 0.0) >= 25:
			hits += 1
	check_approx(float(hits) / float(n), Genome.ATAVISM_CHANCE, 0.01,
		"暗池(10,14) 返祖率 ≈ 15%")

	Genome.seed_rng(4243)
	var hits2 := 0
	for _i in n:
		if Genome._inherit_one(20, 25, 0.0) >= 25 and Genome._inherit_one(20, 25, 0.0) > 0:
			hits2 += 1
	# 20/25 不落在暗池区间，返祖不应触发
	check(float(hits2) / float(n) < 0.35, "非暗池区间不触发返祖（仅噪声影响）")


func _test_trim() -> void:
	section("血脉条数上限")
	var d := {}
	var names := ["fel_cat", "acc_hawk", "can_wolf", "bov_ox", "ser_snake", "urs_bear", "lep_hare"]
	for i in names.size():
		d[names[i]] = 10 * (i + 1)   # 10..70
	var g := Genome.from_titers(d)
	Genome._trim_to_limit(g)
	check(g.titers.size() == 6, "裁剪到 6 条", "实际 %d" % g.titers.size())
	check(not g.titers.has(&"fel_cat"), "被裁掉的是血浓最低的那条")
	check(g.titers.has(&"lep_hare"), "血浓最高的被保留")


func _test_diversity() -> void:
	section("血脉多样性指数")
	var g := Genome.from_titers({"fel_cat": 50})
	check_approx(float(g.diversity_contribution()["simpson"]), 0.0, 1e-9, "单血脉 → BDI 0")
	var g2 := Genome.from_titers({"fel_cat": 50, "acc_hawk": 50})
	check_approx(float(g2.diversity_contribution()["simpson"]), 0.5, 1e-9, "两条均等 → 0.5")
	var g3 := Genome.from_titers({"fel_cat": 25, "acc_hawk": 25, "can_wolf": 25, "bov_ox": 25})
	check_approx(float(g3.diversity_contribution()["simpson"]), 0.75, 1e-9, "四条均等 → 0.75")


func _test_save_roundtrip() -> void:
	section("存档往返")
	var g := Genome.from_titers({"fel_cat": 68, "acc_hawk": 55, "can_wolf": 12})
	g.inbreeding = 0.19
	g.defects.append(&"aberrant")
	g.beast_id = 77
	var back := Genome.from_dict(g.to_dict())
	check(back.titers == g.titers, "血浓一致")
	check_approx(back.inbreeding, g.inbreeding, 1e-9, "近交系数一致")
	check(back.defects == g.defects, "缺陷一致")
	check(back.beast_id == g.beast_id, "个体 id 一致")
	check(back.describe() == g.describe(), "describe() 一致")

	var b := Beast.new(3, Beast.Sex.MALE, g)
	b.generation = 4
	b.father = 1
	b.mother = 2
	var b2 := Beast.from_dict(b.to_dict())
	check(b2.id == b.id and b2.sex == b.sex and b2.generation == b.generation,
		"Beast 往返一致")
	check(b2.genome.titers == g.titers, "Beast 内嵌基因组一致")


func _test_determinism() -> void:
	section("RNG 可复现性")
	var a := Genome.from_titers({"fel_cat": 62, "acc_hawk": 55})
	var b := Genome.from_titers({"can_wolf": 70, "bov_ox": 40})
	Genome.seed_rng(2024)
	var c1 := Genome.breed(a, b, 0.1, 0.4, [&"fel_cat", &"acc_hawk"])
	Genome.seed_rng(2024)
	var c2 := Genome.breed(a, b, 0.1, 0.4, [&"fel_cat", &"acc_hawk"])
	check(c1.titers == c2.titers, "同种子 → 同结果")


func _test_tribe_smoke() -> void:
	section("部落冒烟测试（重叠世代，200 年）")
	Genome.seed_rng(31337)
	var t := Tribe.new()
	t.found(12, BloodlineDB.region_pool(&"green_throat"),
		BloodlineDB.region_magic(&"green_throat"), 24)
	check(t.population() == 12, "奠基 12 人")
	var years := 200
	for _y in years:
		t.step(Tribe.Policy.AVOID_INBREEDING, 0.0)
	check(not t.extinct, "200 年后未灭绝（人口 %d，第 %d 代）" % [t.population(), t.current_generation()])
	check(t.history.size() == years + 1, "history 每年一行（%d）" % (years + 1),
		"实际 %d" % t.history.size())
	var m := t.metrics()
	check(m["bdi"] > 0.0 and m["bdi"] < 1.0, "BDI 落在 (0,1)")
	check(t.current_generation() >= 3, "200 年内推进了至少 3 个世代",
		"实际第 %d 代" % t.current_generation())
	var row0: Dictionary = t.history[0]
	var rowN: Dictionary = t.history[years]
	check(float(rowN["mean_f"]) > float(row0["mean_f"]),
		"封闭部落近交系数上升（%.3f → %.3f）" % [row0["mean_f"], rowN["mean_f"]])
	# 性别比例不应长期失衡（重叠世代 + 一夫多妻的缓冲作用）
	check(float(rowN["sex_ratio"]) > 0.2 and float(rowN["sex_ratio"]) < 0.8,
		"性别比例未失衡（雄 %.0f%%）" % (float(rowN["sex_ratio"]) * 100.0))
