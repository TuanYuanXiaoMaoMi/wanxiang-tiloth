extends SceneTree
## 改制流程验证：信仰够不够、守旧者反应、改制后新生儿的名字形式
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	Genome.seed_rng(999)
	var wd := WorldGen.generate(999, 4)
	RegionDB.load_world(wd)
	var w := WorldState.new()
	w.setup(wd["start_node"], 12, true, 24, 2)
	print("开局：阶段=%s  制度=%s  人口=%d  信仰=%.0f" % [
		w.stage_name(), w.descent_name(), w.population(), w.faith])
	print("可选制度：")
	for m in Descent.ALL_MODES:
		var reason := w.reform_blocked_reason(m)
		print("  %-8s %s" % [Descent.mode_name(m),
			"✓ 可改制（%d 信仰）" % int(Descent.reform_cost(w.tribe.descent_mode, m))
			if reason == "" else "✗ " + reason])
	print("")
	# 涨人口到氏族阶段
	for _t in 10:
		if w.extinct: break
		w.end_turn()
	print("第 %d 回合：阶段=%s  人口=%d  信仰=%.0f" % [w.turn, w.stage_name(), w.population(), w.faith])
	var before := {}
	for id in w.tribe.beasts:
		before[id] = w.tribe.beasts[id].mood
	var target := Descent.Mode.MATRILINEAL
	var old_name := w.descent_name()
	print("改制：%s → %s" % [old_name, Descent.mode_name(target)])
	var ok := w.reform_descent(target)
	print("  结果=%s" % ("成功" if ok else "失败"))
	if ok:
		print("  信仰 %.0f" % w.faith)
		var down := 0; var up := 0
		for id in w.tribe.beasts:
			var d: float = w.tribe.beasts[id].mood - float(before[id])
			if d < -1.0: down += 1
			elif d > 1.0: up += 1
		print("  心情变化：%d 人变差，%d 人变好（守旧者不满 / 好奇者支持）" % [down, up])
		print("  制度现在是：%s" % w.descent_name())
	print("")
	print("改制后继续跑 8 回合，看新生儿的名字形式：")
	var seen_before := {}
	for id in w.tribe.beasts: seen_before[id] = true
	for _t in 8:
		if w.extinct: break
		w.end_turn()
	var born := 0
	for id in w.tribe.beasts:
		if not seen_before.has(id):
			born += 1
			var b: Beast = w.tribe.beasts[id]
			if born <= 6:
				print("  新生的 %-14s （生于第%d回合的制度：%s）" % [b.display_name(),
					b.descent_mode, Descent.mode_name(b.descent_mode)])
	print("  共 %d 个新生儿" % born)
	print("")
	print("对比：老人仍用旧形式")
	var old_count := 0
	for id in w.tribe.beasts:
		var b: Beast = w.tribe.beasts[id]
		if b.descent_mode == Descent.Mode.MATRONYMIC and old_count < 4:
			old_count += 1
			print("  %-14s ← 母名制时期出生的" % b.display_name())
	quit()
