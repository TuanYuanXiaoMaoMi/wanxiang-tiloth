extends SceneTree
## 临时诊断工具：逐年打印人口、性别比例与世代。

func _initialize() -> void:
	BloodlineDB.ensure_loaded()
	Genome.seed_rng(31337)
	var t := Tribe.new()
	t.found(12, BloodlineDB.region_pool(&"green_throat"),
		BloodlineDB.region_magic(&"green_throat"), 24)
	print("奠基：", t.population(), " 人")
	for y in 120:
		t.step(Tribe.Policy.AVOID_INBREEDING, 0.0)
		if y % 5 == 0 or t.extinct:
			var m := t.metrics()
			print("第%3d年 代=%d pop=%2d 雄=%.0f%% F=%.3f BDI=%.3f 嵌合=%.0f%% 稀薄=%.0f%% 最高=%2d" % [
				m["year"], m["generation"], m["population"], m["sex_ratio"] * 100.0,
				m["mean_f"], m["bdi"], m["chimera_rate"] * 100.0,
				m["dilute_rate"] * 100.0, m["max_top_titer"]])
		if t.extinct:
			print("→ 第 %d 年灭绝" % t.extinction_year)
			break
	print("最终：", t.snapshot())
	quit()
