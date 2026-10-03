extends SceneTree
## 人格层诊断：性情是否真的影响了产出、关系是否在生长、故事是否真实
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	Genome.seed_rng(4242)
	var wd := WorldGen.generate(4242, 4)
	RegionDB.load_world(wd)
	var w := WorldState.new()
	w.setup(wd["start_node"], 12, true, 24, 2)
	print("=== 开局：性情与爱好 ===")
	for id in w.tribe.beasts:
		var b: Beast = w.tribe.beasts[id]
		print("  %-14s %-4s %-10s 爱好:%-8s 劳动%.0f%% 口粮×%.2f 心情%.0f" % [
			b.display_name(), "♂" if b.is_male() else "♀",
			Persona.trait_tags(b), Persona.hobby_tags(b),
			b.labor_capacity() * 100.0, Persona.food_mult(b), b.mood])
	var t0 := Time.get_ticks_msec()
	for _t in 12:
		if w.extinct: break
		w.end_turn()
	print("")
	print("=== 第 %d 回合 ===" % w.turn)
	var i := 0
	for id in w.tribe.beasts:
		if i >= 6: break
		i += 1
		var b: Beast = w.tribe.beasts[id]
		print("  %-14s 心情%.0f  想法：「%s」" % [b.display_name(), b.mood, b.thought])
	print("")
	print("=== 关系网（最好的 5 对 / 最差的 3 对）===")
	var pairs: Array = []
	var ids: Array = w.tribe.beasts.keys()
	for a in ids.size():
		for c in range(a + 1, ids.size()):
			pairs.append([w.tribe.relation(ids[a], ids[c]), ids[a], ids[c]])
	pairs.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	for k in mini(5, pairs.size()):
		print("  %-14s ↔ %-14s %+6.1f  %s" % [
			w.tribe.beasts[pairs[k][1]].display_name(),
			w.tribe.beasts[pairs[k][2]].display_name(),
			pairs[k][0], w.tribe.relation_label(pairs[k][1], pairs[k][2])])
	for k in range(maxi(0, pairs.size() - 3), pairs.size()):
		print("  %-14s ↔ %-14s %+6.1f  %s" % [
			w.tribe.beasts[pairs[k][1]].display_name(),
			w.tribe.beasts[pairs[k][2]].display_name(),
			pairs[k][0], w.tribe.relation_label(pairs[k][1], pairs[k][2])])
	print("")
	print("=== 个人史样本 ===")
	for id in w.tribe.beasts:
		var b: Beast = w.tribe.beasts[id]
		if b.story.size() >= 2:
			print("  【%s】" % b.display_name())
			for e in b.story_lines(4):
				print("    第%2d回合  %s" % [e["turn"], e["text"]])
			break
	print("")
	print("耗时 %.1f 秒" % [(Time.get_ticks_msec() - t0) / 1000.0])
	quit()
