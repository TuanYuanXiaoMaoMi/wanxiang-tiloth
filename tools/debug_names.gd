extends SceneTree
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	Genome.seed_rng(4242)
	var wd := WorldGen.generate(4242, 4)
	RegionDB.load_world(wd)
	var w := WorldState.new()
	w.setup(wd["start_node"], 12, true, 24, 2)
	print("=== 开局 ===")
	for id in w.tribe.beasts:
		var b: Beast = w.tribe.beasts[id]
		print("  id=%-3d 姓=%-4s 名=%-6s 全名=%-12s 父=%d 母=%d 世代=%d" % [
			b.id, "\"%s\"" % b.surname, "\"%s\"" % b.name, b.display_name(),
			b.father, b.mother, b.generation])
	for t in 6:
		w.end_turn()
	print("")
	print("=== 第 %d 回合 ===" % w.turn)
	for id in w.tribe.beasts:
		var b: Beast = w.tribe.beasts[id]
		print("  id=%-3d 姓=%-4s 名=%-6s 全名=%-12s 父=%d 母=%d 世代=%d" % [
			b.id, "\"%s\"" % b.surname, "\"%s\"" % b.name, b.display_name(),
			b.father, b.mother, b.generation])
	quit()
