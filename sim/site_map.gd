class_name SiteMap
extends RefCounted
## 局部地图：把一个大陆节点展开成一张有具体位置的 2D 场地图。
##
## 这是「安排某人过去某地 + 看得见地走过去采集」的数据基础。
##
## 设计要点：**距离是有代价的。** 工作点离营地越远，每人每日的有效产出越低
## （最多打 0.65 折）。所以地图不是装饰，选点是真的取舍：
## 近处的浆果丛安全但贫瘠，远处的猎场丰厚但要走半天。

enum Kind { GATHER, HUNT, WOOD, STONE, CRYSTAL, HERB, CAMP, REST, ALTAR }

const KIND_NAMES := {
	Kind.GATHER: "采集点", Kind.HUNT: "猎场", Kind.WOOD: "林地", Kind.STONE: "石场",
	Kind.CRYSTAL: "魔晶脉", Kind.HERB: "药草丛", Kind.CAMP: "营地",
	Kind.REST: "休息所", Kind.ALTAR: "祭坛",
}

## 只有这些类型的产出直接变成食物。
const FOOD_KINDS := [Kind.GATHER, Kind.HUNT]

const WIDTH := 1000.0
const HEIGHT := 620.0
const CAMP_RADIUS := 70.0
const MAX_TRAVEL_PENALTY := 0.35     ## 最远的点损失 35% 产出
## 标定基准效率：**位于标称距离上的工作点，产出必须正好等于 docs/11 标定的速率。**
## 否则「引入距离惩罚」这件事会悄悄把全族食物产能砍掉 25%，
## 而第 24 分钟被迫迁徙的节奏就废了 —— 只是没人会意识到是这一步弄坏的。
const NOMINAL_EFFICIENCY := 0.80

var node_id: StringName = &""
var sites: Array = []                ## Array[Dictionary]
var camp_pos := Vector2(WIDTH * 0.5, HEIGHT * 0.5)
var _by_id: Dictionary = {}


static func generate(p_node_id: StringName, region: Region, rng: RandomNumberGenerator) -> SiteMap:
	var m := SiteMap.new()
	m.node_id = p_node_id
	m.camp_pos = Vector2(WIDTH * 0.5, HEIGHT * 0.5)
	var next_id := 0

	# 营地
	m._add(next_id, Kind.CAMP, m.camp_pos, 0.0, 99); next_id += 1
	# 休息所与祭坛放在营地边上（玩家要指定两个人去休息所，不该让他们走半天）
	m._add(next_id, Kind.REST, m.camp_pos + Vector2(90, -40), 0.0, 2); next_id += 1
	m._add(next_id, Kind.ALTAR, m.camp_pos + Vector2(-95, -35), 0.0, 1); next_id += 1

	# 生产点：数量随该节点的可持续产量走
	m._scatter(Kind.GATHER, clampi(roundi(region.food_msy() / 3.0), 2, 6), 3, rng, next_id)
	next_id = m.sites.size()
	m._scatter(Kind.HUNT, clampi(roundi(region.prey_msy() / 2.5), 1, 4), 2, rng, next_id)
	next_id = m.sites.size()
	m._scatter(Kind.WOOD, _count_for(region.wood, 120.0), 3, rng, next_id)
	next_id = m.sites.size()
	m._scatter(Kind.STONE, _count_for(region.stone, 120.0), 2, rng, next_id)
	next_id = m.sites.size()
	m._scatter(Kind.CRYSTAL, _count_for(region.crystal, 80.0), 2, rng, next_id)
	next_id = m.sites.size()
	m._scatter(Kind.HERB, _count_for(region.herb, 90.0), 2, rng, next_id)

	m._separate()
	m._reindex()
	return m


## 简单的斥力松弛：把挤在一起的工作点推开，标签才不会打架。
func _separate() -> void:
	for _iter in 14:
		for i in sites.size():
			for j in range(i + 1, sites.size()):
				var a: Dictionary = sites[i]
				var b: Dictionary = sites[j]
				if int(a["kind"]) == Kind.CAMP or int(b["kind"]) == Kind.CAMP:
					continue
				var d: Vector2 = (a["pos"] as Vector2) - (b["pos"] as Vector2)
				var dist := d.length()
				var want := 130.0
				if dist < want and dist > 0.001:
					var push := d.normalized() * ((want - dist) * 0.5)
					a["pos"] = (a["pos"] as Vector2) + push
					b["pos"] = (b["pos"] as Vector2) - push
					a["pos"] = Vector2(clampf(a["pos"].x, 55.0, WIDTH - 55.0),
						clampf(a["pos"].y, 55.0, HEIGHT - 55.0))
					b["pos"] = Vector2(clampf(b["pos"].x, 55.0, WIDTH - 55.0),
						clampf(b["pos"].y, 55.0, HEIGHT - 55.0))
	for s in sites:
		s["dist"] = camp_pos.distance_to(s["pos"])


static func _count_for(amount: float, per: float) -> int:
	if amount <= 0.0:
		return 0
	return clampi(roundi(amount / per), 1, 3)


func _add(id: int, kind: int, pos: Vector2, dist: float, slots: int) -> void:
	sites.append({
		"id": id, "kind": kind, "pos": pos, "slots": slots,
		"dist": dist, "workers": [], "depleted": false,
	})


## 在营地周围撒点，越远越可能出现高价值点。
func _scatter(kind: int, count: int, slots: int, rng: RandomNumberGenerator, start_id: int) -> void:
	if count <= 0:
		return
	for i in count:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(CAMP_RADIUS + 110.0, 250.0)
		var pos := camp_pos + Vector2(cos(angle), sin(angle)) * dist
		pos.x = clampf(pos.x, 55.0, WIDTH - 55.0)
		pos.y = clampf(pos.y, 55.0, HEIGHT - 55.0)
		# 人多的地方放得下更多人
		var s := slots + (1 if dist < 200.0 else 0)
		_add(start_id + i, kind, pos, camp_pos.distance_to(pos), s)


func _reindex() -> void:
	_by_id.clear()
	for s in sites:
		_by_id[int(s["id"])] = s


## 只存工作点的**定义**（位置/类型/名额）。
## workers 是从 assignments 推出来的，不存 —— 存两份迟早会不一致。
func to_save() -> Dictionary:
	var out: Array = []
	for s in sites:
		out.append({
			"id": int(s["id"]), "kind": int(s["kind"]),
			"pos": s["pos"], "dist": float(s["dist"]), "slots": int(s["slots"]),
		})
	return {"node_id": String(node_id), "camp_pos": camp_pos, "sites": out}


func load_save(d: Dictionary) -> void:
	node_id = StringName(d.get("node_id", ""))
	camp_pos = d.get("camp_pos", Vector2(WIDTH * 0.5, HEIGHT * 0.5))
	sites.clear()
	for e in d.get("sites", []):
		sites.append({
			"id": int(e["id"]), "kind": int(e["kind"]), "pos": e["pos"],
			"dist": float(e["dist"]), "slots": int(e["slots"]), "workers": [],
		})
	_reindex()


func site(id: int) -> Dictionary:
	return _by_id.get(id, {})


func sites_of_kind(kind: int) -> Array:
	var out: Array = []
	for s in sites:
		if int(s["kind"]) == kind:
			out.append(s)
	return out


func food_sites() -> Array:
	var out: Array = []
	for s in sites:
		if FOOD_KINDS.has(int(s["kind"])):
			out.append(s)
	return out


## 距离惩罚后的产出系数（0.65 ~ 1.0）。
func efficiency(s: Dictionary) -> float:
	var t := clampf(float(s.get("dist", 0.0)) / 250.0, 0.0, 1.0)
	return 1.0 - t * MAX_TRAVEL_PENALTY


## 相对标定速率的倍率。近处略高于 1，远处略低于 1，**平均等于 1**。
## 这样「地图上的位置有意义」和「数值标定不被破坏」两件事可以同时成立。
func rate_multiplier(s: Dictionary) -> float:
	return efficiency(s) / NOMINAL_EFFICIENCY


func free_slots(s: Dictionary) -> int:
	return int(s["slots"]) - (s["workers"] as Array).size()


func kind_name(kind: int) -> String:
	return KIND_NAMES.get(kind, "?")


## 供 UI 显示的一行摘要。
func summary() -> String:
	var counts := {}
	for s in sites:
		var k := int(s["kind"])
		counts[k] = int(counts.get(k, 0)) + 1
	var parts: Array = []
	for k in counts:
		parts.append("%s×%d" % [kind_name(k), counts[k]])
	return "  ".join(parts)
