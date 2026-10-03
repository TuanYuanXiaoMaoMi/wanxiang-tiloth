class_name Persona
extends RefCounted
## 个体的性情、爱好、想法与关系标签。
##
## 设计红线：**每一个性情都必须挂在已有的系统上。**
## 随机生成一堆形容词、但它们不影响任何决策，那不是"有思想"，那是噪音。
## 所以下面每条性情都明确写了它改的是哪个数：
##
##   勤勉/怠惰   → 劳动产出（Beast.labor_capacity）
##   贪食/节食   → 每人每日口粮（WorldState.tick_day）
##   亲和/孤僻   → 关系增长速率（Tribe.add_affinity）
##   恋家/远行癖 → 距离惩罚（工作点产出）
##   好奇/守旧   → 学习与凝聚（留给蜕变/魔法系统）
##   勇猛/怯懦   → 危险耐受（留给灾祸与冒险派遣）
##
## 爱好（偏好工作类型）直接改工作点的产出，并且让"把谁派到哪里"变成一个真决策。

# --------------------------------------------------------------------------
# 性情表
# --------------------------------------------------------------------------

const TRAITS := {
	&"diligent": {
		"name": "勤勉", "desc": "活着就是为了把活干完。",
		"labor": 1.12,
		"think": ["还有活没干完。", "闲着难受。"],
	},
	&"lazy": {
		"name": "怠惰", "desc": "能躺着绝不站着。",
		"labor": 0.88, "mood_bonus": 8.0,
		"think": ["什么时候能歇会儿。", "今天能不能少干点。"],
	},
	&"warm": {
		"name": "亲和", "desc": "和谁都能处得来。",
		"bond": 1.9,
		"think": ["人多热闹，挺好。", "想找人说说话。"],
	},
	&"aloof": {
		"name": "孤僻", "desc": "一个人待着最舒服。",
		"bond": 0.35, "solo": 1.12,
		"think": ["别来烦我。", "一个人清静。"],
	},
	&"curious": {
		"name": "好奇", "desc": "什么都想弄明白。",
		"study": 1.6,
		"think": ["那边到底是什么？", "我想弄明白这是怎么回事。"],
	},
	&"traditional": {
		"name": "守旧", "desc": "祖宗怎么做，就怎么做。",
		"cohesion": 1.25,
		"think": ["以前不是这样的。", "祖灵看着呢。"],
	},
	&"brave": {
		"name": "勇猛", "desc": "越危险越往前。",
		"danger": 1.0,
		"think": ["怕什么，上就是了。"],
	},
	&"timid": {
		"name": "怯懦", "desc": "听见风声就想躲。",
		"danger": -1.0, "labor": 0.97,
		"think": ["这地方不太对劲。", "我想回营地。"],
	},
	&"glutton": {
		"name": "贪食", "desc": "一个人吃两个人的份。",
		"food": 1.12,
		"think": ["饿。", "今天还有吃的吗。"],
	},
	&"frugal": {
		"name": "节食", "desc": "半碗就饱。",
		"food": 0.90,
		"think": ["够吃了，别浪费。"],
	},
	&"homebody": {
		"name": "恋家", "desc": "不愿走远。",
		"near": 1.14, "far": 0.90,
		"think": ["营地边上就挺好。", "不想走那么远。"],
	},
	&"wanderer": {
		"name": "远行癖", "desc": "越远越有精神。",
		"near": 0.93, "far": 1.16,
		"think": ["远处肯定有更好的东西。", "想看看山那边是什么。"],
	},
}

## 互斥的性情不会同时出现在一个人身上。
const TRAIT_CONFLICTS := {
	&"diligent": [&"lazy"], &"lazy": [&"diligent"],
	&"warm": [&"aloof"], &"aloof": [&"warm"],
	&"curious": [&"traditional"], &"traditional": [&"curious"],
	&"brave": [&"timid"], &"timid": [&"brave"],
	&"glutton": [&"frugal"], &"frugal": [&"glutton"],
	&"homebody": [&"wanderer"], &"wanderer": [&"homebody"],
}

const TRAIT_IDS: Array = [&"diligent", &"lazy", &"warm", &"aloof", &"curious",
	&"traditional", &"brave", &"timid", &"glutton", &"frugal", &"homebody", &"wanderer"]


static func trait_name(id: StringName) -> String:
	var t: Dictionary = TRAITS.get(id, {})
	return String(t.get("name", String(id)))


static func trait_desc(id: StringName) -> String:
	var t: Dictionary = TRAITS.get(id, {})
	return String(t.get("desc", ""))


static func trait_tags(beast: Beast) -> String:
	var parts: Array = []
	for t in beast.traits:
		parts.append(trait_name(t))
	return "·".join(parts)


# --------------------------------------------------------------------------
# 抽取
# --------------------------------------------------------------------------

## 掷 2–3 条互不冲突的性情。可以传父母的性情做轻微偏向（孩子像父母）。
static func roll_traits(rng: RandomNumberGenerator, count: int = 3,
		from_father: Array = [], from_mother: Array = []) -> Array:
	var out: Array = []
	var banned := {}
	# 三成概率继承父母之一的性情
	for pool in [from_father, from_mother]:
		if out.size() >= count:
			break
		if not pool.is_empty() and rng.randf() < 0.30:
			var pick: StringName = pool[rng.randi_range(0, pool.size() - 1)]
			if not banned.has(pick):
				out.append(pick)
				banned[pick] = true
				for c in TRAIT_CONFLICTS.get(pick, []):
					banned[c] = true
	for _try in 80:
		if out.size() >= count:
			break
		var cand: StringName = TRAIT_IDS[rng.randi_range(0, TRAIT_IDS.size() - 1)]
		if banned.has(cand):
			continue
		out.append(cand)
		banned[cand] = true
		for c in TRAIT_CONFLICTS.get(cand, []):
			banned[c] = true
	return out


## 掷 1–2 个偏好工作类型（爱好）。
static func roll_hobbies(rng: RandomNumberGenerator) -> Array:
	var pool: Array = [SiteMap.Kind.GATHER, SiteMap.Kind.HUNT, SiteMap.Kind.WOOD,
		SiteMap.Kind.STONE, SiteMap.Kind.CRYSTAL, SiteMap.Kind.HERB]
	var n := 1 + (1 if rng.randf() < 0.45 else 0)
	var out: Array = []
	for _i in n:
		var k: int = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(k):
			out.append(k)
	return out


static func hobby_name(kind: int) -> String:
	match kind:
		SiteMap.Kind.GATHER: return "采集"
		SiteMap.Kind.HUNT: return "狩猎"
		SiteMap.Kind.WOOD: return "伐木"
		SiteMap.Kind.STONE: return "采石"
		SiteMap.Kind.CRYSTAL: return "采晶"
		SiteMap.Kind.HERB: return "采药"
	return "?"


static func hobby_tags(beast: Beast) -> String:
	var parts: Array = []
	for k in beast.hobbies:
		parts.append(hobby_name(int(k)))
	return "·".join(parts)


# --------------------------------------------------------------------------
# 性情对各个系统的影响（全部返回倍率）
# --------------------------------------------------------------------------

static func labor_mult(beast: Beast) -> float:
	var m := 1.0
	for t in beast.traits:
		m *= float((TRAITS.get(t, {}) as Dictionary).get("labor", 1.0))
	return m


static func food_mult(beast: Beast) -> float:
	var m := 1.0
	for t in beast.traits:
		m *= float((TRAITS.get(t, {}) as Dictionary).get("food", 1.0))
	return m


static func bond_mult(beast: Beast) -> float:
	var m := 1.0
	for t in beast.traits:
		m *= float((TRAITS.get(t, {}) as Dictionary).get("bond", 1.0))
	return m


## 距离相关的产出倍率：恋家的人靠近营地更强，远行癖在远处更强。
static func distance_mult(beast: Beast, dist: float) -> float:
	var t := clampf(dist / 250.0, 0.0, 1.0)
	var near := 1.0
	var far := 1.0
	for tr in beast.traits:
		var d: Dictionary = TRAITS.get(tr, {})
		near *= float(d.get("near", 1.0))
		far *= float(d.get("far", 1.0))
	return lerpf(near, far, t)


## 在不在自己喜欢的工作类型上。
static func likes_kind(beast: Beast, kind: int) -> bool:
	return beast.hobbies.has(kind)


## 工作点偏好倍率：对口 +18%，不对口 −5%。
static func site_pref_mult(beast: Beast, kind: int) -> float:
	if beast.hobbies.is_empty():
		return 1.0
	return 1.18 if likes_kind(beast, kind) else 0.95


# --------------------------------------------------------------------------
# 关系标签
# --------------------------------------------------------------------------

static func relation_label(v: float, is_kin: bool = false) -> String:
	# 亲属单独一套说法：母亲和女儿显示成「好友」很怪
	if is_kin:
		if v >= 60.0:
			return "骨肉至亲"
		if v >= 20.0:
			return "至亲"
		if v > -20.0:
			return "亲戚"
		if v > -60.0:
			return "亲情淡薄"
		return "反目"
	if v >= 70.0:
		return "生死之交"
	if v >= 45.0:
		return "挚友"
	if v >= 20.0:
		return "好友"
	if v >= 6.0:
		return "说得来"
	if v > -6.0:
		return "一般"
	if v > -20.0:
		return "不太对付"
	if v > -45.0:
		return "有摩擦"
	if v > -70.0:
		return "仇视"
	return "不共戴天"


static func relation_color(v: float) -> Color:
	if v >= 45.0:
		return Color(0.55, 0.88, 0.60)
	if v >= 6.0:
		return Color(0.78, 0.88, 0.62)
	if v > -6.0:
		return Color(0.80, 0.82, 0.80)
	if v > -45.0:
		return Color(0.92, 0.74, 0.48)
	return Color(0.95, 0.50, 0.44)


# --------------------------------------------------------------------------
# 当前想法
# --------------------------------------------------------------------------

## 按优先级生成一句「他现在在想什么」。
## ctx 由 WorldState 填：{"satiety", "morale", "turn", "site_kind", "partner_name",
##   "partner_dead", "just_forced", "forced_with", "child_born", "in_transit", "migrated"}
static func think(beast: Beast, ctx: Dictionary) -> String:
	var rng := Genome.rng
	var forced := String(ctx.get("forced_with", ""))
	if bool(ctx.get("just_forced", false)) and forced != "":
		return "祖灵把我和%s按在一起。这件事我不想提。" % forced
	if float(ctx.get("satiety", 100.0)) < 35.0:
		return ["肚子空得发慌。", "今天还能吃上东西吗。", "饿。"][rng.randi_range(0, 2)]
	if bool(ctx.get("in_transit", false)):
		return ["还要走多久？", "脚底板磨破了。", "前面那片林子看着还行。"][rng.randi_range(0, 2)]
	if bool(ctx.get("partner_dead", false)):
		return "他不在了。剩下的事得我自己扛。"
	var partner := String(ctx.get("partner_name", ""))
	if partner != "":
		return ["和%s一起干活，日子还过得去。" % partner,
			"只要%s还在，就还行。" % partner][rng.randi_range(0, 1)]
	if bool(ctx.get("child_born", false)):
		return "我的孩子。希望他别像我一样。"
	if beast.age > beast.lifespan * 0.85:
		return ["我活得够久了。", "该让年轻人上了。"][rng.randi_range(0, 1)]
	var kind := int(ctx.get("site_kind", -1))
	if kind >= 0 and likes_kind(beast, kind):
		return ["这活儿我干得顺手。", "干这个不觉得累。"][rng.randi_range(0, 1)]
	if kind >= 0 and not beast.hobbies.is_empty():
		return ["这活儿真烦。", "我更想干别的。"][rng.randi_range(0, 1)]
	# 退回按性情说话
	var pool: Array = []
	for t in beast.traits:
		for line in (TRAITS.get(t, {}) as Dictionary).get("think", []):
			pool.append(line)
	if pool.is_empty():
		pool = ["今天和昨天一样。"]
	return String(pool[rng.randi_range(0, pool.size() - 1)])
