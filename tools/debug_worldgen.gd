extends SceneTree
## 大陆生成器诊断：连通性、承载力分布、邻接合理性。
func _initialize() -> void:
	WorldGen.ensure_loaded()
	var caps: Array = []
	for seed_v in [1, 2, 3, 4, 5]:
		var w := WorldGen.generate(seed_v, 4)
		var total := 0
		var minc := 999.0
		var maxc := 0.0
		for rid in w["regions"]:
			for nid in w["regions"][rid]["nodes"]:
				var d: Dictionary = w["regions"][rid]["nodes"][nid]
				var c: float = float(d["food_r"]) * float(d["food_K"]) / 4.0 \
					+ float(d["prey_r"]) * float(d["prey_K"]) / 8.0
				caps.append(c); total += 1
				minc = minf(minc, c); maxc = maxf(maxc, c)
		# 连通性：从起点 BFS 能否到所有节点
		var start: String = w["start_node"]
		var seen := {start: true}
		var stack: Array = [start]
		while not stack.is_empty():
			var cur: String = stack.pop_back()
			for rid in w["regions"]:
				var nodes: Dictionary = w["regions"][rid]["nodes"]
				if nodes.has(cur):
					for nb in nodes[cur]["adjacent"]:
						if not seen.has(nb):
							seen[nb] = true; stack.append(nb)
					break
		print("种子%d: %d 节点  起点=%s(%s)  可达=%d/%d  承载力 %.1f–%.1f" % [
			seed_v, total, start, w["regions"][w["regions"].keys()[0]]["nodes"][start]["name"] if false else start,
			seen.size(), total, minc, maxc])
	caps.sort()
	print("")
	print("承载力中位数 %.1f  最小 %.1f  最大 %.1f  样本 %d" % [
		caps[caps.size()/2], caps[0], caps[-1], caps.size()])
	quit()
