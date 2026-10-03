class_name Descent
extends RefCounted
## 继嗣制度（descent system）—— 一个部落怎么把「我是谁家的」传下去。
##
## 这不是换个显示方式而已。人类学上继嗣制度决定了：
##   · 谁算「自己人」（氏族边界 → 外婚禁忌 → 择偶范围）
##   · 结婚之后谁搬到谁那里（从夫居 / 从妻居 → 基因流的方向）
##   · 哪些血统能传下去（母系部落里，男性奠基者的姓一代就断了）
##
## 而且它随社会阶段演化。这条曲线是真实的人类学论证：
##   **游团阶段父子关系说不准，只有母亲是确定的，所以只能记母系；
##   等到有了财产要往下传，父系才出现。**
##
## 玩家可以花信仰改制，但守旧的人会不满 —— 见 WorldState.reform_descent()。

enum Mode {
	MATRONYMIC,    ## 母名制：还没有姓，名后挂母亲的名
	PATRONYMIC,    ## 父名制：还没有姓，名后挂父亲的名
	MATRILINEAL,   ## 母系：随母姓，姓氏原样沿母系传
	PATRILINEAL,   ## 父系：随父姓，姓氏原样沿父系传
	BILATERAL,     ## 双系：父姓首字 + 母姓首字，姓氏本身记录混血
	DOUBLE,        ## 双重继嗣：双姓，且父系构成外婚单位
	AMBILINEAL,    ## 两可继嗣：随氏族更大的那一方姓
}

enum Stage { BAND, CLAN, CHIEFDOM }

const STAGE_NAMES := {
	Stage.BAND: "游团",
	Stage.CLAN: "氏族",
	Stage.CHIEFDOM: "酋邦",
}

const STAGE_DESC := {
	Stage.BAND: "人少、常搬家，父子关系说不准，只能靠母系认亲。",
	Stage.CLAN: "人口稳住了，开始有可以往下传的东西，父系才有意义。",
	Stage.CHIEFDOM: "有余粮、有祖灵、有头人，亲戚关系变成一种政治资源。",
}

## 人口阈值：<14 游团，14–23 氏族，≥24 酋邦
const BAND_MAX_POP := 13
const CLAN_MAX_POP := 23

const MODES := {
	Mode.MATRONYMIC: {
		"name": "母名制", "stage": Stage.BAND, "style": "suffix",
		"blurb": "还没有姓。",
		"desc": "父亲是谁说不准，母亲是确定的。所以名字后面挂母亲的名。",
	},
	Mode.PATRONYMIC: {
		"name": "父名制", "stage": Stage.BAND, "style": "suffix",
		"blurb": "还没有姓，但已经认父。",
		"desc": "名字后面挂父亲的名。认同父系，却还没有稳定的氏族。",
	},
	Mode.MATRILINEAL: {
		"name": "母系", "stage": Stage.CLAN, "style": "prefix",
		"blurb": "随母姓，氏族由女性血脉组织。",
		"desc": "孩子随母姓，姓氏原样沿母系传下去。男性奠基者的姓一代就断了。",
	},
	Mode.PATRILINEAL: {
		"name": "父系", "stage": Stage.CLAN, "style": "prefix",
		"blurb": "随父姓，财产与地位沿父系传。",
		"desc": "孩子随父姓，姓氏原样沿父系传下去。女性奠基者的姓一代就断了。",
	},
	Mode.BILATERAL: {
		"name": "双系", "stage": Stage.CHIEFDOM, "style": "prefix",
		"blurb": "父姓首字 + 母姓首字。",
		"desc": "两边的血统都记在名字里，姓氏本身就是混血记录。",
	},
	Mode.AMBILINEAL: {
		"name": "两可继嗣", "stage": Stage.CHIEFDOM, "style": "prefix",
		"blurb": "随人多的一方姓。",
		"desc": "孩子随氏族更大的那一方。哪边的亲戚多，就跟哪边。",
	},
	Mode.DOUBLE: {
		"name": "双重继嗣", "stage": Stage.CHIEFDOM, "style": "prefix",
		"blurb": "双姓，且同姓不婚。",
		"desc": "父姓构成外婚单位：同姓的人不许配对，哪怕血缘上已经隔得很远。",
	},
}

const ALL_MODES: Array = [Mode.MATRONYMIC, Mode.PATRONYMIC, Mode.MATRILINEAL,
	Mode.PATRILINEAL, Mode.BILATERAL, Mode.AMBILINEAL, Mode.DOUBLE]

## 改制的基础信仰开销，再按跨了几级阶段加价。
const REFORM_BASE_COST := 45.0
const REFORM_PER_STAGE_COST := 20.0


static func mode_name(mode: int) -> String:
	return String((MODES.get(mode, {}) as Dictionary).get("name", "?"))


static func mode_desc(mode: int) -> String:
	return String((MODES.get(mode, {}) as Dictionary).get("desc", ""))


static func mode_blurb(mode: int) -> String:
	return String((MODES.get(mode, {}) as Dictionary).get("blurb", ""))


static func stage_of_mode(mode: int) -> int:
	return int((MODES.get(mode, {}) as Dictionary).get("stage", Stage.BAND))


## 这个模式是「姓在前」还是「名后挂父母名」。
static func is_suffix_style(mode: int) -> bool:
	return String((MODES.get(mode, {}) as Dictionary).get("style", "prefix")) == "suffix"


static func stage_for_population(pop: int) -> int:
	if pop <= BAND_MAX_POP:
		return Stage.BAND
	if pop <= CLAN_MAX_POP:
		return Stage.CLAN
	return Stage.CHIEFDOM


static func stage_name(stage: int) -> String:
	return String(STAGE_NAMES.get(stage, "?"))


## 当前阶段能选哪些模式。
static func unlocked_modes(population: int) -> Array:
	var st := stage_for_population(population)
	var out: Array = []
	for m in ALL_MODES:
		if stage_of_mode(m) <= st:
			out.append(m)
	return out


static func is_unlocked(mode: int, population: int) -> bool:
	return stage_of_mode(mode) <= stage_for_population(population)


## 改制要多少信仰。跨阶段越远越贵。
static func reform_cost(from_mode: int, to_mode: int) -> float:
	if from_mode == to_mode:
		return 0.0
	var d: int = absi(stage_of_mode(to_mode) - stage_of_mode(from_mode))
	return REFORM_BASE_COST + REFORM_PER_STAGE_COST * float(d)


# --------------------------------------------------------------------------
# 姓氏的生成规则 —— 每种模式的差别就在这个函数里
# --------------------------------------------------------------------------

## 计算一个新生儿的「姓」字段。
## **传字符串而不是 Beast**：出生时父亲可能已经死了，只能靠受孕当时抄下来的字段。
static func child_surname(mode: int, father_name: String, father_surname: String,
		mother_name: String, mother_surname: String, child_is_male: bool) -> String:
	var suf := "子" if child_is_male else "女"
	match mode:
		Mode.MATRONYMIC:
			return (father_name if mother_name == "" else mother_name) + suf
		Mode.PATRONYMIC:
			return (mother_name if father_name == "" else father_name) + suf
		Mode.MATRILINEAL:
			# 原样继承，不取首字 —— 母系的意义就是这条线一直叫这个名字
			return mother_surname if mother_surname != "" else mother_name
		Mode.PATRILINEAL:
			return father_surname if father_surname != "" else father_name
		Mode.AMBILINEAL:
			# 真正的规则要数两边氏族的人数，静态函数拿不到 —— 见 Tribe.surname_for()
			return combine(father_surname, mother_surname)
		Mode.BILATERAL, Mode.DOUBLE:
			return combine(father_surname, mother_surname)
	return combine(father_surname, mother_surname)


## 双系合成：父姓首字 + 母姓首字。任意一方缺失取另一方，同字不重复。
static func combine(father_surname: String, mother_surname: String) -> String:
	var fr := father_surname.substr(0, 1)
	var mr := mother_surname.substr(0, 1)
	if fr == "":
		return mr if mr != "" else mother_surname
	if mr == "":
		return fr
	return fr if fr == mr else fr + mr


## 奠基者在这个模式下有没有姓？
## 名后挂父母名的制度里没有姓，他们是这条线的起点。
static func founders_have_surnames(mode: int) -> bool:
	return not is_suffix_style(mode)


## 团体的名字：成员列表按这个分组。
static func group_label(beast: Beast, mode: int) -> String:
	if beast.surname == "":
		return "始祖" if is_suffix_style(mode) else "无姓"
	if is_suffix_style(mode):
		# 去掉「子 / 女」的性别后缀，让兄弟姐妹归到同一组。
		# 称呼上保留（"铁风女" 是对的），但分组不该把一家人拆成两半。
		var sn := beast.surname
		if sn.ends_with("子") or sn.ends_with("女"):
			sn = sn.substr(0, sn.length() - 1)
		return sn + "家"
	return beast.surname


## 完整称呼。名后挂父母名的制度里，父母名跟在后面而不是前面。
static func display(beast: Beast, mode: int) -> String:
	if beast.surname == "":
		return beast.name
	if is_suffix_style(mode):
		return "%s·%s" % [beast.name, beast.surname]
	return "%s·%s" % [beast.surname, beast.name]


# --------------------------------------------------------------------------
# 机制后果
# --------------------------------------------------------------------------

## 联姻/收留进来的外来者该是什么性别。
## 从妻居的部落里，嫁进来的是男人；从夫居的部落里，嫁进来的是女人。
## 这直接决定了基因流把哪一半染色体带进来。
static func incoming_sex(mode: int) -> int:
	if mode == Mode.MATRONYMIC or mode == Mode.MATRILINEAL:
		return Beast.Sex.MALE      # 从妻居：男人嫁进来
	return Beast.Sex.FEMALE        # 从夫居：女人嫁进来


## 这个模式有没有「同姓不婚」的氏族外婚禁忌。
static func has_clan_exogamy(mode: int) -> bool:
	return mode == Mode.DOUBLE


## 改制引发的情绪反应。
## 守旧的人把改制当成对祖灵的冒犯，好奇的人乐见其变。
static func reform_mood_delta(traits: Array, magnitude: float) -> float:
	var d := 0.0
	for t in traits:
		match t:
			&"traditional":
				d -= 9.0 * magnitude
			&"curious":
				d += 7.0 * magnitude
			&"timid":
				d -= 3.0 * magnitude
			&"brave":
				d += 2.0 * magnitude
	return d
