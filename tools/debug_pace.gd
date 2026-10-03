extends SceneTree
## 回合制节奏分布：8 个随机大陆，测「第几回合被迫迁徙」
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	print("种子  起点承载力  土地<20%回合  游戏年  现实分钟@1x  灭绝回合")
	var turns: Array = []
	for seed_v in [11, 22, 33, 44, 55, 66, 77, 88]:
		Genome.seed_rng(seed_v * 13 + 1)
		var wd := WorldGen.generate(seed_v, 4)
		RegionDB.load_world(wd)
		var st: StringName = wd["start_node"]
		var cap: float = RegionDB.make(st).carrying_capacity_adults()
		var w := WorldState.new()
		w.record_history = false
		w.setup(st, 12, true, 24, 2)
		for _t in 60:
			if w.extinct: break
			w.end_turn()
		var tk: int = int(w.first_food_low / WorldState.DAYS_PER_TURN) if w.first_food_low > 0 else -1
		if tk > 0: turns.append(tk)
		print("%4d  %8.1f  %10d  %7.1f  %12.0f  %8d" % [seed_v, cap, tk, tk / 4.0,
			WorldState.day_to_real_minutes(w.first_food_low, 1.0), w.turn])
	turns.sort()
	print("")
	print("回合分布：最小 %d  中位 %d  最大 %d（目标 15-40 回合）" % [
		turns[0], turns[turns.size()/2], turns[-1]])
	quit()
