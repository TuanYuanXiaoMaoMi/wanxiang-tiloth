extends SceneTree
## 继嗣制度诊断：六种模式各自产生什么样的氏族结构
func _initialize() -> void:
	BloodlineDB.ensure_loaded()
	print("=== 六种继嗣模式的姓氏行为（同一批奠基者，只换制度）===")
	for mode in Descent.ALL_MODES:
		Genome.seed_rng(4242)
		var t := Tribe.new()
		t.descent_mode = mode
		t.found_family(12, BloodlineDB.region_pool(&"green_throat"), 0.35, 24, 2)
		for _g in 6:
			t.step(Tribe.Policy.PLANNED_CHIMERA, 0.0)
		var groups := {}
		for id in t.beasts:
			var k := t.group_of(t.beasts[id])
			groups[k] = int(groups.get(k, 0)) + 1
		var sorted: Array = []
		for k in groups: sorted.append([groups[k], k])
		sorted.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
		var top := ""
		for i in mini(4, sorted.size()):
			top += "%s(%d) " % [sorted[i][1], sorted[i][0]]
		var sample: Array = []
		var n := 0
		for id in t.beasts:
			if n >= 3: break
			n += 1
			sample.append(t.beasts[id].display_name())
		print("  %-8s  阶段=%-4s  氏族 %2d 个  %-28s  例：%s" % [
			Descent.mode_name(mode), Descent.stage_name(Descent.stage_of_mode(mode)),
			groups.size(), top, "、".join(sample)])
	print("")
	print("=== 阶段解锁 ===")
	for pop in [10, 16, 25, 40]:
		var names: Array = []
		for m in Descent.unlocked_modes(pop):
			names.append(Descent.mode_name(m))
		print("  人口 %2d → %-4s  可选：%s" % [pop,
			Descent.stage_name(Descent.stage_for_population(pop)), "、".join(names)])
	print("")
	print("=== 改制开销 ===")
	for pair in [[Descent.Mode.MATRONYMIC, Descent.Mode.MATRILINEAL],
			[Descent.Mode.MATRONYMIC, Descent.Mode.BILATERAL],
			[Descent.Mode.PATRILINEAL, Descent.Mode.MATRILINEAL]]:
		print("  %s → %s ：信仰 %.0f" % [Descent.mode_name(pair[0]),
			Descent.mode_name(pair[1]), Descent.reform_cost(pair[0], pair[1])])
	print("")
	print("=== 联姻外来者的性别方向 ===")
	for mode in Descent.ALL_MODES:
		print("  %-8s  嫁进来的是 %s（%s）" % [Descent.mode_name(mode),
			"男性" if Descent.incoming_sex(mode) == Beast.Sex.MALE else "女性",
			"从妻居" if Descent.incoming_sex(mode) == Beast.Sex.MALE else "从夫居"])
	quit()
