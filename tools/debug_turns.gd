extends SceneTree
## 回合制验证 + 在途状态机测试
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	Genome.seed_rng(4242)
	var world := WorldGen.generate(4242, 4)
	RegionDB.load_world(world)
	var w := WorldState.new()
	w.record_history = false
	w.setup(world["start_node"], 12, true, 24, 2)
	print("一回合 = %d 天（一季）。起点 %s，承载力 %.1f 人" % [
		WorldState.DAYS_PER_TURN, RegionDB.node_display_name(world["start_node"]), w.capacity()])
	print("")
	print("回合  季节  人口  压力   食物%  猎物%  粮仓   里程碑")
	var pinch := -1
	for t in 30:
		if w.extinct: break
		var s: Dictionary = w.end_turn()
		if w.first_food_low > 0 and pinch < 0:
			pinch = t + 1
			print("%4d  %-4s  %4d  %.2f  %5.0f  %5.0f  %5.0f  ← 土地跌破两成" % [
				t + 1, s["season"], s["population"], s["pressure"],
				w.region.food_ratio() * 100.0, w.region.prey_ratio() * 100.0, w.food_store])
		elif t % 4 == 3:
			print("%4d  %-4s  %4d  %.2f  %5.0f  %5.0f  %5.0f" % [
				t + 1, s["season"], s["population"], s["pressure"],
				w.region.food_ratio() * 100.0, w.region.prey_ratio() * 100.0, w.food_store])
	print("")
	print("第一次被迫迁徙：第 %d 回合 = %.1f 游戏年  —— docs/11 的目标是第 24 回合" % [pinch, pinch / 4.0])
	print("")
	print("=== 在途状态机测试（新世界，避免被饥荒干扰）===")
	Genome.seed_rng(99)
	var w2 := WorldState.new()
	w2.record_history = false
	w2.setup(world["start_node"], 12, true, 24, 2)
	# 找一个 3 格远的目标
	var far := ""
	for nid in RegionDB.node_ids():
		var p := RegionDB.path_to(w2.region.id, nid)
		if p.size() == 3:
			far = nid; break
	if far == "":
		for nid in RegionDB.node_ids():
			var p2 := RegionDB.path_to(w2.region.id, nid)
			if p2.size() >= 2: far = nid; break
	var res: Dictionary = w2.start_migration(far)
	print("启程去 %s：%s" % [RegionDB.node_display_name(far), str(res)])
	print("途经：", w2.transit_route_names())
	for i in 5:
		if not w2.in_transit:
			break
		var s2: Dictionary = w2.end_turn()
		print("  回合 %2d  在途=%s  剩 %d 回合  粮仓 %5.0f  饱食 %3.0f  食物产出(在途) " % [
			s2["turn"], str(s2["in_transit"]), s2["transit_turns_left"],
			w2.food_store, s2["satiety"]])
	print("现在在：%s（%s）" % [w2.region.name, RegionDB.region_name(w2.region.region_id)])
	quit()
