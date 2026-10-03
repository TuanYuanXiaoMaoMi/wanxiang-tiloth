extends SceneTree
## 知识树诊断：什么事件触发了什么知识、采纳后的效果
func _initialize() -> void:
	BloodlineDB.ensure_loaded(); WorldGen.ensure_loaded()
	Genome.seed_rng(31337)
	var wd := WorldGen.generate(31337, 4)
	RegionDB.load_world(wd)
	var w := WorldState.new()
	w.setup(wd["start_node"], 12, true, 24, 2)
	print("开局已采纳：")
	for id in w.adopted:
		print("   %s —— %s" % [Knowledge.node_name(id), Knowledge.node_desc(id)])
	print("")
	var seen := {}
	for id in w.adopted: seen[id] = true
	print("回合  人口  已发现  新发现")
	for _t in 22:
		if w.extinct: break
		w.end_turn()
		for id in w.new_discoveries:
			print("%4d  %4d  %5d   ★ %s" % [w.turn, w.population(), w.known.size(),
				Knowledge.node_name(id)])
			print("        %s" % Knowledge.trigger_text(id))
	for id in w.known: seen[id] = true
	print("")
	print("已知 %d / %d 项" % [w.known.size(), Knowledge.ALL_IDS.size()])
	print("")
	print("统计计数器：")
	var keys: Array = w.stats.keys()
	keys.sort()
	for k in keys:
		print("   %-16s %.0f" % [k, float(w.stats[k])])
	print("")
	print("尝试采纳所有「已发现且前置满足」的知识：")
	var guard := 0
	while guard < 40:
		guard += 1
		var did := false
		for id in Knowledge.ALL_IDS:
			if w.can_adopt(id):
				w.adopt(id)
				did = true
		if not did: break
	print("  最终已采纳 %d 项，信仰 %.0f" % [w.adopted.size(), w.faith])
	var modes: Array = []
	for m in w.unlocked_descent_modes():
		modes.append(Descent.mode_name(m))
	print("  可选的继嗣制度：%s" % ", ".join(modes))
	print("  效果倍率：采集 ×%.2f  狩猎 ×%.2f  口粮 ×%.2f  粮仓 ×%.2f  信仰 ×%.2f" % [
		w.k_mult("gather_mult"), w.k_mult("hunt_mult"), w.k_mult("food_mult"),
		w.k_mult("granary_mult"), w.k_mult("faith_rate")])
	quit()
