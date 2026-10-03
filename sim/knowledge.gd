class_name Knowledge
extends RefCounted
## 知识树。部落不是"人口到了就自动学会"，而是**经历了什么才想明白**。
##
## 每个节点有两把锁：
##   ① 前置知识 —— 树结构。没学会走的，学不会跑的。
##   ② 触发条件 —— **必须在模拟里真实发生过某件事**。
##      第一个畸形儿出生，部落才第一次意识到"近亲结合会遭报应"。
##
## 发现之后**不自动生效**，要玩家花资源采纳。
## 所以有三种状态：未发现（???）/ 已发现待采纳 / 已采纳。
##
## 设计红线同 docs/14：每个知识都必须有真实的机制后果，
## 不能只是图鉴里多一行字。effects 里的每一项都要在 sim 里有对应的读取点。

enum Branch { LIVELIHOOD, SOCIETY, BLOOD, SPIRIT }

const BRANCH_NAMES := {
	Branch.LIVELIHOOD: "生计",
	Branch.SOCIETY: "社会",
	Branch.BLOOD: "血脉",
	Branch.SPIRIT: "祖灵",
}

const BRANCH_ORDER: Array = [Branch.LIVELIHOOD, Branch.SOCIETY, Branch.BLOOD, Branch.SPIRIT]

## 效果键分两类，**这个区分很要紧**：
##   · k_mult 键 —— 可以叠加，多个节点各乘一次（food_mult、hunt_mult…）
##   · k_value / k_flag 键 —— **只能有一个节点定义**。
##     k_value() 返回的是"第一个匹配"，如果两个节点都设同一个键，
##     结果就取决于字典遍历顺序 —— 不确定，而且静默错。
##     单元测试里有一条专门守这个约束。
##
## 触发条件的种类。value 的含义见 trigger_met()。
const NODES := {
	# ---------------- 生计 ----------------
	&"fire": {
		"name": "用火", "branch": Branch.LIVELIHOOD, "tier": 0,
		"requires": [], "trigger": {"kind": "start"},
		"cost": 0.0,
		"desc": "火塘是营地的心脏。熟食让人省下消化的力气。",
		"effects": {"food_mult": 0.94},
	},
	&"storage": {
		"name": "窖藏", "branch": Branch.LIVELIHOOD, "tier": 1,
		"requires": [&"fire"], "trigger": {"kind": "gathered", "value": 700,
			"why": "采回来的东西一次吃不完，堆在地上烂掉了。"},
		"cost": 45.0,
		"desc": "挖地窖，把吃不完的埋起来。粮仓能装下更多。",
		"effects": {"granary_mult": 1.35},
	},
	&"bone_tools": {
		"name": "骨器", "branch": Branch.LIVELIHOOD, "tier": 0,
		"requires": [], "trigger": {"kind": "hunted", "value": 260,
			"why": "猎物越打越多，用手撕已经不够用了。"},
		"cost": 40.0,
		"desc": "把骨头磨成尖。剥皮、分割、投掷都利索得多。",
		"effects": {"hunt_mult": 1.12},
	},
	&"basketry": {
		"name": "编笼", "branch": Branch.LIVELIHOOD, "tier": 0,
		"requires": [], "trigger": {"kind": "gathered", "value": 380,
			"why": "两只手捧不下更多果子了。"},
		"cost": 35.0,
		"desc": "用藤条编出能背的容器。一次能带回更多。",
		"effects": {"gather_mult": 1.12},
	},
	&"drive_hunt": {
		"name": "围猎", "branch": Branch.LIVELIHOOD, "tier": 2,
		"requires": [&"bone_tools"], "trigger": {"kind": "hunt_crew", "value": 3,
			"why": "三个人一起追一头鹿，跑散了。得有个章法。"},
		"cost": 70.0,
		"desc": "约好谁拦、谁赶、谁下手。一群人比一个人能打到更大的东西。",
		"effects": {"hunt_mult": 1.18},
	},
	&"rationing": {
		"name": "配给制度", "branch": Branch.LIVELIHOOD, "tier": 2,
		"requires": [&"storage"], "trigger": {"kind": "deaths", "value": 2,
			"why": "饿死过人之后，才有人提出：分着吃，别谁抢到算谁的。"},
		"cost": 58.0,
		"desc": "按人头分粮。真正饿死的人会少很多。",
		"effects": {"starve_debt_mult": 0.45},
	},
	&"migration_lore": {
		"name": "迁徙知识", "branch": Branch.LIVELIHOOD, "tier": 1,
		"requires": [&"fire"], "trigger": {"kind": "migrations", "value": 1,
			"why": "搬过一次家，才知道路上该带什么、走哪条道。"},
		"cost": 50.0,
		"desc": "记住路、记住水、记住哪种林子能歇脚。路上饿不死人。",
		"effects": {"transit_forage": 0.78},
	},

	# ---------------- 社会 ----------------
	&"matronymic": {
		"name": "母名制", "branch": Branch.SOCIETY, "tier": 0,
		"requires": [], "trigger": {"kind": "start"},
		"cost": 0.0,
		"desc": "父亲是谁说不准，母亲是确定的。名字后面挂母亲的名。",
		"unlocks_descent": Descent.Mode.MATRONYMIC,
	},
	&"matrilineal": {
		"name": "母系氏族", "branch": Branch.SOCIETY, "tier": 1,
		"requires": [&"matronymic"], "trigger": {"kind": "max_pop", "value": 14,
			"why": "人多了，光靠「谁生的」已经认不过来了，得有个稳定的说法。"},
		"cost": 55.0,
		"desc": "孩子随母姓，姓氏沿母系传下去。氏族由女性血脉组织。",
		"unlocks_descent": Descent.Mode.MATRILINEAL,
	},
	&"patronymic": {
		"name": "父名制", "branch": Branch.SOCIETY, "tier": 1,
		"requires": [&"matronymic"], "trigger": {"kind": "dominant_male", "value": 4,
			"why": "有一个男人，他的孩子活下来了一大半。大家开始拿他的名认人。"},
		"cost": 55.0,
		"desc": "名字后面挂父亲的名。认父系，但还没有稳定的氏族。",
		"unlocks_descent": Descent.Mode.PATRONYMIC,
	},
	&"patrilineal": {
		"name": "父系氏族", "branch": Branch.SOCIETY, "tier": 2,
		"requires": [&"patronymic"], "trigger": {"kind": "dominant_male", "value": 6,
			"why": "那条父系的线越来越粗，已经粗到能当财产和地位的凭据了。"},
		"cost": 75.0,
		"desc": "孩子随父姓，姓氏沿父系传。有东西要往下传的时候，父系才有意义。",
		"unlocks_descent": Descent.Mode.PATRILINEAL,
	},
	&"bilateral": {
		"name": "双系继嗣", "branch": Branch.SOCIETY, "tier": 3,
		"requires": [&"matrilineal", &"patrilineal"],
		"trigger": {"kind": "chimera_births", "value": 1,
			"why": "两条血脉合出来的孩子身上同时有双方的记号。为什么不都记下来？"},
		"cost": 90.0,
		"desc": "两边的血统都记在名字里，姓氏本身就是混血记录。",
		"unlocks_descent": Descent.Mode.BILATERAL,
	},
	&"exogamy": {
		"name": "外婚禁忌", "branch": Branch.SOCIETY, "tier": 3,
		"requires": [&"inbreed_taboo"], "trigger": {"kind": "inbreed_births", "value": 2,
			"why": "第二次了。同一个氏族的两个人结合，生下来的还是不对劲。"},
		"cost": 80.0,
		"desc": "同一个氏族的人不许通婚。哪怕血缘上早就隔远了。",
		"effects": {"clan_exogamy": true},
	},
	&"ambilineal": {
		"name": "两可继嗣", "branch": Branch.SOCIETY, "tier": 3,
		"requires": [&"matrilineal", &"patrilineal"],
		"trigger": {"kind": "max_pop", "value": 22,
			"why": "两边氏族大小差得越来越远。有人开始挑跟哪边。"},
		"cost": 95.0,
		"desc": "孩子随氏族更大的那一方。哪边亲戚多，就跟哪边。",
		"unlocks_descent": Descent.Mode.AMBILINEAL,
	},
	&"double_descent": {
		"name": "双重继嗣", "branch": Branch.SOCIETY, "tier": 4,
		"requires": [&"bilateral", &"exogamy"],
		"trigger": {"kind": "max_pop", "value": 24,
			"why": "氏族多到要分清「谁跟谁是一家」了，一套关系不够用。"},
		"cost": 110.0,
		"desc": "父姓构成外婚单位，母姓记录血统来源。两套关系并行。",
		"unlocks_descent": Descent.Mode.DOUBLE,
	},
	&"marriage_alliance": {
		"name": "联姻", "branch": Branch.SOCIETY, "tier": 2,
		"requires": [&"matronymic"], "trigger": {"kind": "max_pop", "value": 16,
			"why": "总在同一批人里找配偶，已经开始出问题了。得往外看看。"},
		"cost": 65.0,
		"desc": "跟外面的部落交换配偶。带来新的血脉，也带来新的姓氏。",
		"effects": {"gene_flow": 0.10},
	},

	# ---------------- 血脉 ----------------
	&"inbreed_taboo": {
		"name": "近交禁忌", "branch": Branch.BLOOD, "tier": 0,
		"requires": [], "trigger": {"kind": "defect_births", "value": 1,
			"why": "第一个畸形儿出生了。没人说得出为什么，但大家开始避开血亲。"},
		"cost": 50.0,
		"desc": "血亲之间不结合。没人懂道理，只是祖灵不高兴。",
		"effects": {"kin_avoid": 2.5},
	},
	&"herblore": {
		"name": "草药", "branch": Branch.BLOOD, "tier": 0,
		"requires": [], "trigger": {"kind": "deaths", "value": 3,
			"why": "死了三个人之后，有人开始试着用草根敷伤口。"},
		"cost": 45.0,
		"desc": "有些草能压住胎里的毛病，也能止血。",
		"effects": {"defect_resist": 0.80},
	},
	&"chimera_lore": {
		"name": "嵌合认知", "branch": Branch.BLOOD, "tier": 1,
		"requires": [], "trigger": {"kind": "chimera_births", "value": 1,
			"why": "一个孩子身上同时显出了两条血脉。祖灵在说话。"},
		"cost": 60.0,
		"desc": "开始有人琢磨：哪一种配对能生出这样的孩子？",
		"effects": {"faith_rate": 1.15},
	},
	&"selective_breeding": {
		"name": "选育", "branch": Branch.BLOOD, "tier": 2,
		"requires": [&"chimera_lore", &"inbreed_taboo"],
		"trigger": {"kind": "chimera_births", "value": 2,
			"why": "第二次了。这次有人记下了是哪两个人生的。"},
		"cost": 85.0,
		"desc": "主动安排配对，为的是生出某种孩子。部落开始替你安排婚事。",
		"effects": {"planned_pairing": true},
	},

	# ---------------- 祖灵 ----------------
	&"ancestor_rite": {
		"name": "祭祀", "branch": Branch.SPIRIT, "tier": 0,
		"requires": [], "trigger": {"kind": "faith_peak", "value": 88,
			"why": "信仰攒满过，没处用 —— 堆着堆着就成了仪式。"},
		"cost": 40.0,
		"desc": "定期给祖灵上供。信仰积得更快。",
		"effects": {"faith_rate": 1.30},
	},
	&"totem": {
		"name": "图腾", "branch": Branch.SPIRIT, "tier": 1,
		"requires": [&"ancestor_rite"], "trigger": {"kind": "max_pop", "value": 18,
			"why": "人多了，需要一个所有人都认的记号。"},
		"cost": 60.0,
		"desc": "全族认一个兽为祖。人心齐一些。",
		"effects": {"morale_base": 7.0},
	},
	&"spirit_pact": {
		"name": "祖灵契约", "branch": Branch.SPIRIT, "tier": 2,
		"requires": [&"totem"], "trigger": {"kind": "forced_pairs", "value": 2,
			"why": "强行结合的两个人后来都过得不好。有人在想：这笔账该怎么还。"},
		"cost": 85.0,
		"desc": "把强制结合的代价摊到全族身上，而不是只压在那两个人身上。",
		"effects": {"force_pair_mercy": true},
	},
}

const ALL_IDS: Array = [&"rationing", &"fire", &"storage", &"bone_tools", &"basketry", &"drive_hunt",
	&"migration_lore", &"matronymic", &"matrilineal", &"patronymic", &"patrilineal",
	&"bilateral", &"ambilineal", &"exogamy", &"double_descent", &"marriage_alliance",
	&"inbreed_taboo", &"herblore", &"chimera_lore", &"selective_breeding",
	&"ancestor_rite", &"totem", &"spirit_pact"]


static func node(id: StringName) -> Dictionary:
	return NODES.get(id, {})


static func node_name(id: StringName) -> String:
	return String(node(id).get("name", String(id)))


static func node_desc(id: StringName) -> String:
	return String(node(id).get("desc", ""))


static func branch_of(id: StringName) -> int:
	return int(node(id).get("branch", Branch.LIVELIHOOD))


static func tier_of(id: StringName) -> int:
	return int(node(id).get("tier", 0))


static func requires_of(id: StringName) -> Array:
	return node(id).get("requires", [])


static func cost_of(id: StringName) -> float:
	return float(node(id).get("cost", 0.0))


static func trigger_of(id: StringName) -> Dictionary:
	return node(id).get("trigger", {})


static func effects_of(id: StringName) -> Dictionary:
	return node(id).get("effects", {})


static func unlocks_descent(id: StringName) -> int:
	return int(node(id).get("unlocks_descent", -1))


## 把效果键名翻成人话。界面上直接显示 granary_mult 1.35 是给程序员看的，不是给玩家看的。
const EFFECT_TEXT := {
	"food_mult": "全族口粮消耗 ×%.2f",
	"granary_mult": "粮仓上限 ×%.2f",
	"hunt_mult": "狩猎产出 ×%.2f",
	"gather_mult": "采集产出 ×%.2f",
	"transit_forage": "在途觅食率提到 %.0f%%",
	"kin_avoid": "择偶避亲强度 ×%.1f",
	"defect_resist": "缺陷出生概率 ×%.2f",
	"faith_rate": "信仰积攒速度 ×%.2f",
	"morale_base": "全族士气基准 +%.0f",
	"gene_flow": "每年 %.0f%% 概率有外来者加入",
	"clan_exogamy": "同姓不婚",
	"planned_pairing": "自动配对改为按嵌合潜力择优",
	"force_pair_mercy": "法术强制配对的士气代价降到 30%%",
	"starve_debt_mult": "饿死速度 ×%.2f",
}


static func effect_text(key: String, value: Variant) -> String:
	var fmt: String = String(EFFECT_TEXT.get(key, "%s = %s"))
	if not EFFECT_TEXT.has(key):
		return "%s = %s" % [key, str(value)]
	if key == "transit_forage":
		return fmt % (float(value) * 100.0)
	if key == "gene_flow":
		return fmt % (float(value) * 100.0)
	return fmt % float(value)


static func ids_in_branch(b: int) -> Array:
	var out: Array = []
	for id in ALL_IDS:
		if branch_of(id) == b:
			out.append(id)
	return out


# --------------------------------------------------------------------------
# 触发条件
# --------------------------------------------------------------------------

## 触发条件的文字说明 —— 玩家要能看到"为什么现在能想到这个了"。
static func trigger_text(id: StringName) -> String:
	var t := trigger_of(id)
	match String(t.get("kind", "")):
		"start":
			return "部落从一开始就知道。"
		"gathered":
			return "累计采集 %d 之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"hunted":
			return "累计狩猎 %d 之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"hunt_crew":
			return "同一狩猎点上有 %d 个人之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"deaths":
			return "部落死过 %d 个人之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"defect_births":
			return "出生过 %d 个畸形儿之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"inbreed_births":
			return "出现过 %d 次近亲生育之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"chimera_births":
			return "生出过 %d 个嵌合体之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"max_pop":
			return "人口到过 %d 之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"migrations":
			return "搬过 %d 次家之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"faith_peak":
			return "信仰攒到过 %d 之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"dominant_male":
			return "有一个男人留下 %d 个活着的后代之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
		"forced_pairs":
			return "用过 %d 次法术强制配对之后：%s" % [int(t.get("value", 0)), String(t.get("why", ""))]
	return "？"


## 这个知识的触发条件满足了吗。stats 由 WorldState 每回合填。
static func trigger_met(id: StringName, stats: Dictionary) -> bool:
	var t := trigger_of(id)
	var want := float(t.get("value", 0))
	match String(t.get("kind", "")):
		"start":
			return true
		"gathered":
			return float(stats.get("gathered", 0.0)) >= want
		"hunted":
			return float(stats.get("hunted", 0.0)) >= want
		"hunt_crew":
			return float(stats.get("hunt_crew_max", 0.0)) >= want
		"deaths":
			return float(stats.get("deaths", 0.0)) >= want
		"defect_births":
			return float(stats.get("defect_births", 0.0)) >= want
		"inbreed_births":
			return float(stats.get("inbreed_births", 0.0)) >= want
		"chimera_births":
			return float(stats.get("chimera_births", 0.0)) >= want
		"max_pop":
			return float(stats.get("max_pop", 0.0)) >= want
		"migrations":
			return float(stats.get("migrations", 0.0)) >= want
		"faith_peak":
			return float(stats.get("faith_peak", 0.0)) >= want
		"dominant_male":
			return float(stats.get("dominant_male", 0.0)) >= want
		"forced_pairs":
			return float(stats.get("forced_pairs", 0.0)) >= want
	return false


## 一个新计数器从 0 到 1 时，返回所有因此被发现的节点。
static func find_discoverables(stats: Dictionary, known: Dictionary) -> Array:
	var out: Array = []
	for id in ALL_IDS:
		if known.has(id):
			continue
		if trigger_met(id, stats):
			out.append(id)
	return out
