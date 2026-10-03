class_name Naming
extends RefCounted
## 姓名素材库与生成器。
##
## 第一版只有 20 个姓 × 300 个名，而且名的模板只有一种（「[色/质][身体部位]」），
## 念到第十个就腻了。这一版把四个池子分开，并且让**名字沾上类群的气味**：
## 猫系多「爪耳尾」，鹰系多「羽喙翼」，蛇系多「鳞舌」——
## 于是名字本身就带信息量，玩家扫一眼列表就能猜到谁是哪一系。
##
## 注：名前缀池与姓池**刻意允许重叠**（都取材于自然与质感）。
## 同一个人的姓名撞字由 roll_given_name() 里的 _clashes() 挡掉，
## 不需要在池子层面预先排除 —— 那样会把前缀池砍到只剩十几个字。

const SURNAMES: Array = [
	"石", "岩", "崖", "谷", "林", "泽", "泉", "溪", "沙", "泥",
	"尘", "雾", "云", "霜", "雪", "雨", "雷", "风", "潮", "浪",
	"火", "焰", "烬", "灰", "冰", "露", "星", "月", "日", "山",
	"川", "原", "野", "沼", "渊", "洞", "峰", "岭", "坡", "岸",
	"狼", "熊", "豹", "虎", "鹿", "鹰", "鸦", "蛇", "蜥", "獭",
	"牛", "羊", "兔", "鼠", "猫", "犬", "狐", "鲸", "蛛", "螳",
	"铁", "铜", "玉", "骨", "角", "皮", "羽", "鳞", "木", "藤",
	"麻", "陶", "刃", "齿", "甲", "革", "竹", "苇", "苔", "长",
	"短", "高", "深", "远", "重", "轻", "明", "暗", "幽", "寒",
	"暖", "苍", "赤", "白", "玄", "素", "沉", "浮", "虚", "生",
	"死", "夜", "曙", "暮", "晨", "静", "喧", "柔", "烈", "清",
	"浊", "空", "满", "断", "续", "孤", "群", "疾", "徐",
]

const HEADS: Array = [
	"灰", "长", "短", "铁", "风", "暗", "火", "石", "雪", "苔",
	"血", "夜", "霜", "烬", "潮", "砂", "苍", "碎", "沉", "荒",
	"赤", "白", "玄", "青", "幽", "寒", "暖", "明", "清", "浊",
	"重", "轻", "深", "远", "静", "喧", "柔", "烈", "孤", "疾",
	"徐", "断", "续", "空", "满", "高", "低", "硬", "软", "冷",
	"烫", "干", "湿", "亮", "哑", "尖", "钝", "厚", "薄",
]

const BODY_TAILS: Array = [
	"耳", "牙", "尾", "爪", "角", "羽", "眼", "脊", "喉", "掌",
	"鬃", "须", "蹄", "喙", "鳞", "心", "骨", "血", "脉", "魂",
	"步", "影", "息", "声", "齿", "皮", "筋", "胆", "舌", "翼",
]

const NATURE_TAILS: Array = [
	"风", "霜", "雪", "雨", "雾", "岩", "林", "潮", "汐", "星",
	"月", "焰", "尘", "灰", "烬", "雷", "冰", "露", "泉", "谷",
	"云", "岸", "沙", "藤",
]

const SOLO_NAMES: Array = [
	"烬", "苔", "潮", "霜", "岩", "岚", "汐", "霭", "燧", "垠",
	"岑", "泠", "霏", "曜", "曦", "暝", "濯", "磐", "蘅", "鸢",
	"隼", "鸦", "貂", "獾", "麂", "鼬", "鲛", "螭", "骁", "骧",
	"徵", "徽", "攸", "翎", "玥", "琰", "玦", "琅",
]

## 每个类群偏好的尾字：45% 概率从这里取，其余从通用池取。
const CLADE_TAILS := {
	&"shadow": ["爪", "耳", "尾", "眼", "步", "影"],
	&"pack": ["牙", "喉", "耳", "鬃", "声"],
	&"swift": ["耳", "蹄", "尾", "眼", "息"],
	&"horn": ["角", "蹄", "脊", "鬃", "骨"],
	&"feather": ["羽", "喙", "眼", "翼", "声"],
	&"scale": ["鳞", "尾", "喉", "舌", "皮"],
	&"heavy": ["掌", "蹄", "脊", "爪", "皮"],
}


## 掷一个部落里还没人用过的姓。
static func roll_surname(used: Dictionary) -> String:
	for _try in 80:
		var cand: String = SURNAMES[Genome.rng.randi_range(0, SURNAMES.size() - 1)]
		if not used.has(cand):
			used[cand] = true
			return cand
	var fallback: String = SURNAMES[Genome.rng.randi_range(0, SURNAMES.size() - 1)]
	used[fallback] = true
	return fallback


## 掷一个名。**避开姓里已有的字** —— 姓与名的池子有重叠，
## 不避让会出现「烬霜·烬喙」这种姓名共用一个字的名字。
static func roll_given_name(surname: String, clade: StringName = &"") -> String:
	for _try in 60:
		var r := Genome.rng.randf()
		var candidate := ""
		if r < 0.14:
			candidate = String(SOLO_NAMES[Genome.rng.randi_range(0, SOLO_NAMES.size() - 1)])
		elif r < 0.42:
			candidate = _head() + _tail(clade, NATURE_TAILS)
		else:
			candidate = _head() + _tail(clade, BODY_TAILS)
		if not _clashes(candidate, surname):
			return candidate
	# 极端情况下退而求其次：只保证和姓不撞
	for _try in 60:
		var c := _head() + _tail(clade, BODY_TAILS)
		if not _clashes(c, surname):
			return c
	return _head() + String(BODY_TAILS[0])


static func _head() -> String:
	return String(HEADS[Genome.rng.randi_range(0, HEADS.size() - 1)])


static func _tail(clade: StringName, pool: Array) -> String:
	var pref: Array = CLADE_TAILS.get(clade, [])
	if not pref.is_empty() and Genome.rng.randf() < 0.45:
		return String(pref[Genome.rng.randi_range(0, pref.size() - 1)])
	return String(pool[Genome.rng.randi_range(0, pool.size() - 1)])


static func _clashes(name: String, surname: String) -> bool:
	if surname == "":
		return false
	for i in name.length():
		if surname.contains(name.substr(i, 1)):
			return true
	return false


## 全部可用组合数，供工具显示。
static func pool_size() -> int:
	return HEADS.size() * BODY_TAILS.size() + HEADS.size() * NATURE_TAILS.size() \
		+ SOLO_NAMES.size()
