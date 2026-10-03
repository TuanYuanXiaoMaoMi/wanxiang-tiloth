extends SceneTree
## 姓氏系统的代际演化诊断。
## 用纯遗传模拟（不带资源压力）跑 20 代 —— 资源层的部落活不到那么久，
## 而姓氏是否逐代坍缩是一个**跨代**问题，必须跑够代数才看得出来。
func _initialize() -> void:
	BloodlineDB.ensure_loaded()
	_run("封闭部落（无联姻）", 0.0)
	print("")
	_run("有联姻（每年 40% 引入外来者，放大以看清效果）", 0.40)
	quit()


func _run(title: String, gene_flow: float) -> void:
	print("=== %s ===" % title)
	Genome.seed_rng(20240930)
	var t := Tribe.new()
	t.found_family(12, BloodlineDB.region_pool(&"green_throat"), 0.35, 24, 2)
	print("代  人口  唯一姓  最常见姓          单字姓  带·N后缀  姓名撞字")
	for gen in 20:
		var counts := {}
		var dup := 0
		var single := 0
		var clash := 0
		for id in t.beasts:
			var b: Beast = t.beasts[id]
			var sn: String = b.surname if b.surname != "" else "(无姓)"
			counts[sn] = int(counts.get(sn, 0)) + 1
			if b.name.contains("·"): dup += 1
			if sn.length() == 1: single += 1
			# 姓与名共用同一个字
			for i in b.name.length():
				if sn.contains(b.name.substr(i, 1)):
					clash += 1
					break
		var sorted: Array = []
		for k in counts: sorted.append([counts[k], k])
		sorted.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
		var top := ""
		for i in mini(4, sorted.size()):
			top += "%s(%d) " % [sorted[i][1], sorted[i][0]]
		print("%2d  %4d  %5d   %-18s %5d  %5d  %5d" % [gen, t.beasts.size(),
			counts.size(), top, single, dup, clash])
		t.step(Tribe.Policy.PLANNED_CHIMERA, gene_flow)
	print("")
	print("=== 第 20 代的样本 ===")
	var rows: Array = []
	for id in t.beasts:
		var b: Beast = t.beasts[id]
		rows.append([b.generation, b.display_name(), b.father, b.mother])
	rows.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	for k in mini(12, rows.size()):
		print("  第%2d代  %-18s 父=%-4d 母=%-4d" % [rows[k][0], rows[k][1], rows[k][2], rows[k][3]])
