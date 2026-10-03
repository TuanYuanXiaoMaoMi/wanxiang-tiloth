extends SceneTree
## 工作点与指派诊断 + 节奏验证（确认换成个体指派后，第 24 分钟的迁徙决策没跑掉）
func _initialize() -> void:
	BloodlineDB.ensure_loaded()
	WorldGen.ensure_loaded()
	Genome.seed_rng(4242)
	var world := WorldGen.generate(4242, 4)
	RegionDB.load_world(world)
	var start: StringName = world["start_node"]
	print("大陆种子 4242：%d 节点，起点 %s（%s）" % [
		world["node_count"], start, RegionDB.node_display_name(start)])
	print("起点承载力 %.1f 人" % (RegionDB.make(start).carrying_capacity_adults()))
	print("")

	var w := WorldState.new()
	w.setup(start, 12, true, 24, 2)
	print("局部地图：", w.site_map.summary())
	for s in w.site_map.sites:
		print("  #%-2d %-6s 距营地 %5.0f  名额 %d  效率 %.2f" % [
			int(s["id"]), w.site_map.kind_name(int(s["kind"])),
			float(s["dist"]), int(s["slots"]), w.site_map.efficiency(s)])
	print("")
	print("自动派工后（%d 人）：" % w.population())
	for s in w.site_map.sites:
		var ws: Array = s["workers"]
		if ws.is_empty(): continue
		var names: Array = []
		for id in ws: names.append(w.tribe.beasts[id].name)
		print("  %-6s ← %s" % [w.site_map.kind_name(int(s["kind"])), ", ".join(names)])
	print("")

	print("=== 节奏验证（工作点模式）===")
	var marks := [120, 240, 360, 480, 600, 720, 840]
	for _d in 960:
		if w.extinct: break
		w.tick_day()
		if marks.has(w.day):
			print("第%4d天(第%d年%s) 人=%2d 压力=%.2f 食物=%3.0f%% 猎物=%3.0f%% 仓=%4.0f 士气=%.0f 信仰=%.0f" % [
				w.day, w.year()+1, w.region.season_name(), w.population(), w.pressure_ratio(),
				w.region.food_ratio()*100.0, w.region.prey_ratio()*100.0,
				w.food_store, w.morale, w.faith])
	print("")
	print("时间线：食物<20%% 第%d天（=%.0f 现实分钟 @1x）  仓空 第%d天  首次饿死 第%d天" % [
		w.first_food_low, WorldState.day_to_real_minutes(w.first_food_low, 1.0),
		w.first_store_empty, w.first_death])
	quit()
