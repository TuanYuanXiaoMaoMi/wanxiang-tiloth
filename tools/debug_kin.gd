extends SceneTree
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	Genome.seed_rng(816149)
	var wd := WorldGen.generate(816149, 4)
	RegionDB.load_world(wd)
	var w := WorldState.new()
	w.setup(wd["start_node"], 12, true, 24, 2)
	for _t in 18:
		if w.extinct: break
		w.end_turn()
	print("检查每个人的姓氏是否 = 父姓首字 + 母姓首字")
	print("本人            父(姓)          母(姓)          期望   实际   对?")
	var bad := 0
	var checked := 0
	for id in w.tribe.beasts:
		var b: Beast = w.tribe.beasts[id]
		if b.father < 0 or b.mother < 0: continue
		if not w.tribe.beasts.has(b.father) or not w.tribe.beasts.has(b.mother): continue
		var f: Beast = w.tribe.beasts[b.father]
		var m: Beast = w.tribe.beasts[b.mother]
		var expect := ""
		var fr := f.surname.substr(0, 1)
		var mr := m.surname.substr(0, 1)
		expect = fr if fr == mr else fr + mr
		checked += 1
		var ok := expect == b.surname
		if not ok: bad += 1
		if checked <= 20:
			print("%-14s  %-4s(%-6s)  %-4s(%-6s)  %-6s %-6s %s" % [
				b.display_name(), "♂" if f.is_male() else "♀", f.display_name(),
				"♂" if m.is_male() else "♀", m.display_name(),
				expect, b.surname, "✓" if ok else "✗"])
	print("")
	print("检查 %d 人，不符 %d 人" % [checked, bad])
	quit()
