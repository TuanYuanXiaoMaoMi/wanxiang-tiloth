extends SceneTree
## 经济账本诊断：定期打印 WorldState 的完整食物账本。
##   ./tools/godot.sh --headless --script res://tools/debug_economy.gd

const EVERY := 60

func _initialize() -> void:
	BloodlineDB.ensure_loaded()
	RegionDB.ensure_loaded()
	Genome.seed_rng(777001)
	var w := WorldState.new()
	w.setup(&"gt_ashwater", 12, true, 24, 2)
	w.hunt_bias = 1.0
	print("承载力 %.1f 人；开局 %d 人，劳力 %.1f" % [w.capacity(), w.population(), w.workers()])
	print("%-7s %-4s %-7s %-7s %-7s %-7s %-7s %-6s %-6s %-6s" % [
		"天", "人", "劳力", "需求", "产出", "仓", "仓上限", "饱食", "食物%", "压力"])
	for _d in 2500:
		if w.extinct:
			print("→ 第 %d 天灭绝" % w.day)
			break
		var need := float(w.population()) * WorldState.FOOD_PER_PERSON_DAY
		var labor := w.workers() * w.labor_efficiency()
		var r: Dictionary = w.tick_day()
		if w.day % EVERY == 0 or w.day == 1:
			print("%-7d %-4d %-7.1f %-7.1f %-7.1f %-7.1f %-7.1f %-6.0f %-6.0f %-6.2f" % [
				w.day, w.population(), labor, need, r["produced"], r["store"],
				w.granary_cap(), r["satiety"], float(r["food_ratio"]) * 100.0,
				w.pressure_ratio()])
	print("")
	for e in w.log:
		print("  [%5d] %s" % [e["day"], e["msg"]])
	quit()
