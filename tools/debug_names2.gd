extends SceneTree
## 新姓名池的抽样与多样性检查
func _initialize() -> void:
	BloodlineDB.ensure_loaded()
	print("姓池 %d 个　名池 %d 种（原来：20 姓 / 300 名）" % [
		Naming.SURNAMES.size(), Naming.pool_size()])
	print("")
	Genome.seed_rng(20240930)
	print("=== 各族群的名字样本（看类群气味）===")
	for clade in BloodlineDB.clade_ids():
		var bl: Array = BloodlineDB._clade_members[clade]
		var b0: StringName = bl[0]
		var names: Array = []
		for i in 10:
			names.append(Naming.roll_given_name("", clade))
		print("  %-4s(%s)：%s" % [BloodlineDB.clade_name(clade),
			BloodlineDB.bloodline_name(b0), " ".join(names)])
	print("")
	# 一整个部落的实际姓名
	var t := Tribe.new()
	t.found_family(12, BloodlineDB.region_pool(&"green_throat"), 0.35, 24, 2)
	print("=== 开局 12 人的姓名 ===")
	var i := 0
	for id in t.beasts:
		var b: Beast = t.beasts[id]
		i += 1
		print("  %2d. %-14s  %s" % [i, b.display_name(),
			BloodlineDB.clade_name(BloodlineDB.clade_of(b.genome.top_bloodline()))])
	print("")
	# 重名率：生成 3000 个名看重复
	print("=== 多样性抽样 ===")
	for tag in ["姓", "名"]:
		var seen := {}
		var chars := {}
		for _k in 4000:
			var v: String = Naming.roll_surname({}) if tag == "姓" else String(Naming.roll_given_name(""))
			seen[v] = true
			for j in v.length(): chars[v.substr(j,1)] = true
		print("  4000 次抽样：%s 共 %d 种不同，用到 %d 个不同汉字" % [tag, seen.size(), chars.size()])
	quit()
