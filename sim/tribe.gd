class_name Tribe
extends RefCounted
## 部落的人口/繁衍模型 + 配对策略。用于验证遗传系统的宏观行为。
##
## 模型与设计文档 01.3 / 04.5 对齐：
##   * **重叠世代**：同时活着约 4 代人（寿命 45–65 年，世代长 12–15 年）。
##     这一点至关重要——早期版本用了离散世代 + 一夫一妻，结果性别比例漂移
##     会在 10 代内灭族，把遗传信号完全淹没。见 docs/10-遗传平衡实测.md。
##   * **一夫多妻容忍**：一名雄性可与多名雌性交配。小部落若严格一夫一妻，
##     min(雄, 雌) 直接决定出生数，性别漂移 = 灭绝漩涡。
##   * **承载力 k_cap**：超过即饿死（随机淘汰），代表食物天花板。
##   * **不做疾病/灾祸/个体技能**：那些在别的系统里，本模型只看遗传与人口。

enum Policy {
	RANDOM,             ## 随机配对：不作为的玩家
	AVOID_INBREEDING,   ## 选最低亲缘：理性但只看一步的玩家
	PLANNED_CHIMERA,    ## 两代前瞻求嵌合：会规划混血的玩家
	PURE_LINE,          ## 选型交配求纯化：追求单一血脉顶峰的玩家
}

# --- 人口学（文档 01.3）---
const MATURITY_AGE := 8.0
const BREEDING_INTERVAL := 2.0
const CONCEPTION_CHANCE := 0.45
const TWIN_CHANCE := 0.15
const LIFESPAN_MIN := 45.0
const LIFESPAN_MAX := 65.0
const YEARS_PER_GENERATION := 13.0
const FOUNDER_AGE_MIN := 10.0
const FOUNDER_AGE_MAX := 34.0

# --- 配对策略 ---
const LOOKAHEAD_SAMPLE := 4      ## 两代前瞻时采样的潜在配偶数
const CLAN_EXOGAMY_PENALTY := 0.55
const RELATION_MATE_WEIGHT := 0.0006   ## 好感对择偶的影响：量程的 6%
const CHIMERA_KIN_WEIGHT := 3.0
const CHIMERA_KIN_MAX := 0.35    ## 超过此亲缘就不做嵌合前瞻（性能与合理性）
## 近交缺陷表。触发时随机取一项——盲/聋/骨脆会直接削弱劳动能力（见 Beast）。
const DEFECT_TABLE: Array = [&"blind", &"deaf", &"frail_bones", &"manaplague",
	&"early_aging", &"sterile", &"line_locked"]


## 双系制下的姓氏合成。规则本身搬去了 Descent —— 因为姓氏形式现在取决于继嗣制度。
## 这个薄封装保留下来，是因为单元测试和旧代码都在用它。
static func combine_surname(father_surname: String, mother_surname: String) -> String:
	return Descent.combine(father_surname, mother_surname)


## 按当前继嗣制度算一个孩子的姓。
func surname_for(father_name: String, father_surname: String,
		mother_name: String, mother_surname: String, child_is_male: bool) -> String:
	# 两可继嗣要数两边氏族的人数 —— 这不是静态表能表达的东西，
	# 所以「依赖部落状态的继嗣规则」必须在这里开一个分支。
	if descent_mode == Descent.Mode.AMBILINEAL:
		var cf := _group_size(father_surname)
		var cm := _group_size(mother_surname)
		if cf >= cm and father_surname != "":
			return father_surname
		if mother_surname != "":
			return mother_surname
	return Descent.child_surname(descent_mode, father_name, father_surname,
		mother_name, mother_surname, child_is_male)


## 某个姓氏现在有多少活人。
func _group_size(surname: String) -> int:
	if surname == "":
		return 0
	var n := 0
	for id in beasts:
		if group_of(beasts[id]) == surname:
			n += 1
	return n


## 这个人在成员列表里归到哪一组。
func group_of(b: Beast) -> String:
	var m: int = b.descent_mode if b.descent_mode >= 0 else descent_mode
	return Descent.group_label(b, m)


const FOUNDER_TITER_MIN := 45
const FOUNDER_TITER_MAX := 75

var pedigree: Pedigree = Pedigree.new()
var beasts: Dictionary = {}          # int -> Beast（当前活着的所有人）
var year: int = 0
var next_id: int = 1
var pool: Array = []                 # 区域血脉池（Array[StringName]）
var magic: float = 0.35
var k_cap: int = 24
var extinct: bool = false
var history: Array = []              # 每年一行指标
var _used_names: Dictionary = {}     # 防止重名
## 关系网：key = "小id|大id" → 好感度（−100..+100）。
## 亲属加成不存进来，而是读的时候按谱系现算 —— 否则一改谱系就要维护两处。
var relations: Dictionary = {}
var current_turn: int = 0            # 由 WorldState 每次结算时同步，用于个人史的纪年
## 当前的继嗣制度。**只影响之后出生的人** —— 已出生的人保持他们出生时的名字形式。
var descent_mode: int = Descent.Mode.MATRONYMIC

# --- 由知识树驱动的开关。Tribe 不认识 Knowledge，只认这几个数，避免循环依赖 ---
var kin_avoid: float = 1.0          ## 择偶时对血亲的排斥强度（近交禁忌）
var defect_resist: float = 1.0      ## 缺陷概率的倍率（草药）
var planned_pairing: bool = false   ## 自动配对是否按嵌合潜力择优（选育）
var clan_exogamy: bool = false      ## 同姓不婚（外婚禁忌）

# --- 事件计数：知识树的触发条件全靠这些 ---
var stat_births: int = 0
var stat_deaths: int = 0
var stat_defect_births: int = 0     ## 出生时带缺陷的
var stat_inbreed_births: int = 0    ## 亲缘系数 > 0.125 的生育
var stat_chimera_births: int = 0
var extinction_year: int = -1


# --------------------------------------------------------------------------
# 建立部落
# --------------------------------------------------------------------------

func _random_founder_genome() -> Genome:
	var g := Genome.new()
	# 奠基者携带 1–2 条区域血脉，血浓偏高，且彼此互无血缘
	var n := 2 if Genome.rng.randf() < 0.5 else 1
	for _j in n:
		var bl: StringName = pool[Genome.rng.randi_range(0, pool.size() - 1)]
		g.titers[bl] = Genome.rng.randi_range(FOUNDER_TITER_MIN, FOUNDER_TITER_MAX)
	return g


func found(founder_count: int, region_pool: Array, region_magic: float = 0.35, cap: int = 24) -> void:
	BloodlineDB.ensure_loaded()
	pool = region_pool.duplicate()
	magic = region_magic
	k_cap = cap
	beasts.clear()
	_used_names.clear()
	pedigree = Pedigree.new()
	year = 0
	next_id = 1
	extinct = false
	extinction_year = -1
	history.clear()

	var used_names := {}
	for i in founder_count:
		var b := Beast.new()
		b.genome = _random_founder_genome()
		b.sex = Beast.Sex.MALE if (i % 2 == 1) else Beast.Sex.FEMALE
		b.generation = 0
		b.age = Genome.rng.randf_range(FOUNDER_AGE_MIN, FOUNDER_AGE_MAX)
		b.lifespan = Genome.rng.randf_range(LIFESPAN_MIN, LIFESPAN_MAX)
		if Descent.founders_have_surnames(descent_mode):
			b.surname = Naming.roll_surname(used_names)
		b.traits = Persona.roll_traits(Genome.rng, 3)
		b.hobbies = Persona.roll_hobbies(Genome.rng)
		_register(b)
		_log_story(b, "带着一家人离开了旧部落。")
	_record()


## 以「一家人出走另立部落」的方式建立：2 名互无血缘的奠基者 + (n−2) 名他们的子女（全同胞）。
## 这比「n 名互无血缘的奠基者」现实得多，且后果完全不同：
## 第二代个体是**全同胞互配**，F 直接 = 0.25，近交压力从第一代就存在。
func found_family(family_size: int, region_pool: Array, region_magic: float = 0.35,
		cap: int = 24, couples: int = 2) -> void:
	couples = clampi(couples, 1, 4)
	if family_size < couples * 2 + 1:
		family_size = couples * 2 + 1
	BloodlineDB.ensure_loaded()
	pool = region_pool.duplicate()
	magic = region_magic
	k_cap = cap
	beasts.clear()
	_used_names.clear()
	pedigree = Pedigree.new()
	year = 0
	next_id = 1
	extinct = false
	extinction_year = -1
	history.clear()

	# couples 对互无血缘的父母
	var pairs: Array = []
	var used_sn := {}
	for c in couples:
		var pair: Array = []
		for i in 2:
			var pb := Beast.new()
			pb.genome = _random_founder_genome()
			pb.sex = Beast.Sex.MALE if i == 1 else Beast.Sex.FEMALE
			pb.generation = 0
			pb.age = Genome.rng.randf_range(34.0, 44.0)
			pb.lifespan = Genome.rng.randf_range(LIFESPAN_MIN, LIFESPAN_MAX)
			# 每一对父母各有**互不相同**的姓，孩子的双姓才是真的两家合并
			if Descent.founders_have_surnames(descent_mode):
				pb.surname = Naming.roll_surname(used_sn)
			pb.traits = Persona.roll_traits(Genome.rng, 3)
			pb.hobbies = Persona.roll_hobbies(Genome.rng)
			_register(pb)
			_log_story(pb, "决定跟着家人出走，另立门户。")
			pair.append(pb.id)
		pairs.append(pair)

	# 子女轮流分配给各对；同对子女为全同胞，不同对子女互为表亲
	for i in (family_size - couples * 2):
		var pair: Array = pairs[i % couples]
		var g := Genome.breed(beasts[pair[0]].genome, beasts[pair[1]].genome,
			0.0, magic, pool, false)
		var cb := Beast.new()
		cb.genome = g
		cb.sex = Beast.Sex.MALE if (i % 2 == 1) else Beast.Sex.FEMALE
		cb.generation = 1
		# pair[0] 是雌、pair[1] 是雄（见上面 pb.sex 的赋值）。这里写反过一次：
		# 亲缘系数是对称的所以遗传没受影响，但界面上会把母亲标成「父」，
		# 而且奠基那一代的姓氏顺序也跟着反了。
		cb.father = pair[1]
		cb.mother = pair[0]
		cb.age = Genome.rng.randf_range(MATURITY_AGE + 1.0, 30.0)
		cb.lifespan = Genome.rng.randf_range(LIFESPAN_MIN, LIFESPAN_MAX)
		# 奠基子女也要拿到双姓 —— 早期版本他们直接 _register()，没走出生路径，
		# 结果从第二代起姓氏全空了。
		# pair[0] 是雌、pair[1] 是雄 —— 参数顺序要跟 slot 一致。
		# 只改 slot 不改这里，姓氏顺序就还是会反。
		cb.surname = surname_for(beasts[pair[1]].name, beasts[pair[1]].surname,
			beasts[pair[0]].name, beasts[pair[0]].surname, cb.is_male())
		cb.traits = Persona.roll_traits(Genome.rng, 3,
			beasts[pair[1]].traits, beasts[pair[0]].traits)
		cb.hobbies = Persona.roll_hobbies(Genome.rng)
		_register(cb)
		_log_story(cb, "出生在%s氏，跟着家人离开了旧部落。" % [
			cb.surname if cb.surname != "" else "无名"])
	_record()


# --------------------------------------------------------------------------
# 关系
# --------------------------------------------------------------------------

static func rel_key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]


## 亲属之间的基础好感：由谱系亲缘系数换算。父女/全同胞 φ=0.25 → +35。
func kin_bond(a: int, b: int) -> float:
	if a < 0 or b < 0 or a == b:
		return 0.0
	return clampf(pedigree.kinship(a, b) * 140.0, 0.0, 55.0)


func is_kin(a: int, b: int) -> bool:
	return kin_bond(a, b) > 4.0


## 最终好感 = 互动累积 + 亲属基础。
func relation(a: int, b: int) -> float:
	if a < 0 or b < 0 or a == b:
		return 0.0
	return clampf(float(relations.get(rel_key(a, b), 0.0)) + kin_bond(a, b), -100.0, 100.0)


## 用亲属称谓而不是"亲属"两个字 —— 母亲和女儿、堂表亲，分量是不一样的。
func kin_word(a: int, b: int) -> String:
	if a < 0 or b < 0 or a == b or not beasts.has(a) or not beasts.has(b):
		return ""
	var x: Beast = beasts[a]
	var y: Beast = beasts[b]
	if x.father == b or x.mother == b:
		return "父" if y.is_male() else "母"
	if y.father == a or y.mother == a:
		return "子" if x.is_male() else "女"
	var same_f := x.father >= 0 and x.father == y.father
	var same_m := x.mother >= 0 and x.mother == y.mother
	if same_f and same_m:
		return "同胞"
	if same_f or same_m:
		return "半同胞"
	if kin_bond(a, b) > 4.0:
		return "亲戚"
	return ""


func relation_label(a: int, b: int) -> String:
	return Persona.relation_label(relation(a, b), is_kin(a, b))


## 互动改变好感。传入的是「原始累积值」，亲属加成不参与。
func add_affinity(a: int, b: int, delta: float) -> void:
	if a < 0 or b < 0 or a == b:
		return
	if not beasts.has(a) or not beasts.has(b):
		return
	# 亲和的性情让关系涨得更快（孤僻的涨得慢）
	var m := (Persona.bond_mult(beasts[a]) + Persona.bond_mult(beasts[b])) * 0.5
	var k := rel_key(a, b)
	relations[k] = clampf(float(relations.get(k, 0.0)) + delta * m, -100.0, 100.0)
	_try_make_partner(a, b)


## 好感够高就确立伴侣关系（双方都没有伴侣时）。
func _try_make_partner(a: int, b: int) -> void:
	var ba: Beast = beasts[a]
	var bb: Beast = beasts[b]
	if ba.is_male() == bb.is_male():
		return
	if ba.partner_id >= 0 or bb.partner_id >= 0:
		return
	if relation(a, b) >= 62.0:
		ba.partner_id = b
		bb.partner_id = a
		_log_story(ba, "和%s结成了伴侣。" % bb.display_name())
		_log_story(bb, "和%s结成了伴侣。" % ba.display_name())


func partner_name(b: Beast) -> String:
	if b.partner_id < 0 or not beasts.has(b.partner_id):
		return ""
	return beasts[b.partner_id].display_name()


## 每回合更新一次关系网：共事的人变熟，其他人缓慢淡忘。
func update_relations() -> void:
	var by_site := {}
	for id in beasts:
		var b: Beast = beasts[id]
		if b.site_id >= 0:
			if not by_site.has(b.site_id):
				by_site[b.site_id] = []
			(by_site[b.site_id] as Array).append(id)
	for sid in by_site:
		var ids: Array = by_site[sid]
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				add_affinity(ids[i], ids[j], 0.8)
	# 没有互动就慢慢淡忘
	for k in relations.keys():
		relations[k] = float(relations[k]) * 0.985


## 死亡前把需要的信息抄下来 —— 人一删，关系就查不到了。
func _death_record(b: Beast) -> Dictionary:
	var kids: Array = []
	for id in beasts:
		var o: Beast = beasts[id]
		if o.father == b.id or o.mother == b.id:
			kids.append(id)
	return {
		"name": b.display_name(), "id": b.id,
		"partner": b.partner_id, "children": kids, "age": b.age,
	}


## 死亡会在**活着的人**身上留下痕迹：伴侣与子女会难过，并记进各自的个人史。
func _note_death(rec: Dictionary) -> void:
	var nm := String(rec["name"])
	var pid: int = int(rec["partner"])
	if pid >= 0 and beasts.has(pid):
		var p: Beast = beasts[pid]
		_log_story(p, "%s死了（%d 岁）。" % [nm, int(rec["age"])])
		p.mood = maxf(0.0, p.mood - 24.0)
		p.partner_id = -1
	for cid in (rec["children"] as Array):
		if beasts.has(cid):
			_log_story(beasts[cid], "%s死了。" % nm)
			beasts[cid].mood = maxf(0.0, beasts[cid].mood - 11.0)


func _log_story(b: Beast, text: String) -> void:
	b.story.append({"turn": current_turn, "text": text})
	if b.story.size() > 40:
		b.story.pop_front()


## 供外部（WorldState）记一笔个人史。
func note(b: Beast, text: String) -> void:
	if b != null:
		_log_story(b, text)


## 部落的全量快照。**这是存档里最大的一块** ——
## 人、基因组、姓氏、性情、爱好、个人史、关系网、父系表全在这里。
func to_save() -> Dictionary:
	var bs: Array = []
	for id in beasts:
		bs.append(beasts[id].to_dict())
	var names: Array = []
	for k in _used_names:
		names.append(String(k))
	var pool_ids: Array = []
	for b in pool:
		pool_ids.append(String(b))
	var hist: Array = []
	for h in history:
		hist.append(h.duplicate(true))
	return {
		"beasts": bs,
		"next_id": next_id, "year": year, "current_turn": current_turn,
		"descent_mode": descent_mode,
		"relations": relations.duplicate(),
		"used_names": names,
		"pedigree": pedigree.to_save(),
		"kin_avoid": kin_avoid, "defect_resist": defect_resist,
		"planned_pairing": planned_pairing, "clan_exogamy": clan_exogamy,
		"stat_births": stat_births, "stat_deaths": stat_deaths,
		"stat_defect_births": stat_defect_births,
		"stat_inbreed_births": stat_inbreed_births,
		"stat_chimera_births": stat_chimera_births,
		"extinct": extinct, "extinction_year": extinction_year,
		"pool": pool_ids, "magic": magic, "k_cap": k_cap,
		"history": hist,
	}


func load_save(d: Dictionary) -> void:
	beasts.clear()
	for e in d.get("beasts", []):
		var b := Beast.from_dict(e)
		beasts[b.id] = b
	next_id = int(d.get("next_id", 1))
	year = int(d.get("year", 0))
	current_turn = int(d.get("current_turn", 0))
	descent_mode = int(d.get("descent_mode", Descent.Mode.MATRONYMIC))
	relations = (d.get("relations", {}) as Dictionary).duplicate()
	_used_names.clear()
	for k in d.get("used_names", []):
		_used_names[String(k)] = true
	pedigree.load_save(d.get("pedigree", {}))
	kin_avoid = float(d.get("kin_avoid", 1.0))
	defect_resist = float(d.get("defect_resist", 1.0))
	planned_pairing = bool(d.get("planned_pairing", false))
	clan_exogamy = bool(d.get("clan_exogamy", false))
	stat_births = int(d.get("stat_births", 0))
	stat_deaths = int(d.get("stat_deaths", 0))
	stat_defect_births = int(d.get("stat_defect_births", 0))
	stat_inbreed_births = int(d.get("stat_inbreed_births", 0))
	stat_chimera_births = int(d.get("stat_chimera_births", 0))
	extinct = bool(d.get("extinct", false))
	extinction_year = int(d.get("extinction_year", -1))
	pool.clear()
	for b in d.get("pool", []):
		pool.append(StringName(b))
	magic = float(d.get("magic", 0.35))
	k_cap = int(d.get("k_cap", 24))
	history.clear()
	for h in d.get("history", []):
		history.append(h)


func _register(b: Beast) -> void:
	b.id = next_id
	next_id += 1
	if b.name == "":
		# 名字沾上类群的气味：猫系多「爪耳尾」，鹰系多「羽喙翼」
		var clade: StringName = &""
		if b.genome != null and not b.genome.titers.is_empty():
			clade = BloodlineDB.clade_of(b.genome.top_bloodline())
		b.name = Naming.roll_given_name(b.surname, clade)
	if b.genome != null:
		b.genome.beast_id = b.id
	var f := 0.0 if b.genome == null else b.genome.inbreeding
	pedigree.add(b.id, b.father, b.mother, f)
	if b.descent_mode < 0:
		b.descent_mode = descent_mode
	var full := "%s%s" % [b.surname, b.name]
	if _used_names.has(full):
		b.name = "%s·%d" % [b.name, b.id]
		full = "%s%s" % [b.surname, b.name]
	_used_names[full] = true
	beasts[b.id] = b


func _make_outsider() -> Beast:
	var g := Genome.new()
	var n := 2 if Genome.rng.randf() < 0.4 else 1
	for _j in n:
		var bl: StringName = pool[Genome.rng.randi_range(0, pool.size() - 1)]
		g.titers[bl] = Genome.rng.randi_range(40, 70)
	var b := Beast.new()
	b.genome = g
	b.sex = Descent.incoming_sex(descent_mode)
	b.generation = current_generation()
	b.age = Genome.rng.randf_range(MATURITY_AGE + 1.0, 30.0)
	b.lifespan = Genome.rng.randf_range(LIFESPAN_MIN, LIFESPAN_MAX)
	# 外来者要带来**部落里还没有的姓** —— 联姻/收留是姓氏漂移的唯一解药。
	# 如果外来者也抽到已有的姓，姓氏就会一路收敛到只剩一两个。
	if Descent.founders_have_surnames(descent_mode):
		var used_sn := {}
		for id in beasts:
			used_sn[beasts[id].surname] = true
		b.surname = Naming.roll_surname(used_sn)
	b.traits = Persona.roll_traits(Genome.rng, 3)
	b.hobbies = Persona.roll_hobbies(Genome.rng)
	b.father = -1
	b.mother = -1
	return b


# --------------------------------------------------------------------------
# 近交的生理后果（文档 02.6 表格）
# --------------------------------------------------------------------------

static func _fertility_from_kin(kin: float) -> float:
	if kin < 0.0625:
		return 1.0
	if kin < 0.125:
		return 0.90
	if kin < 0.25:
		return 0.75
	return 0.50


static func _stillbirth_from_kin(kin: float) -> float:
	if kin < 0.0625:
		return 0.0
	if kin < 0.125:
		return 0.02
	if kin < 0.25:
		return 0.08
	return 0.30


static func _sterility_from_kin(kin: float) -> float:
	if kin < 0.125:
		return 0.0
	if kin < 0.25:
		return 0.05
	return 0.20


static func _defect_from_kin(kin: float) -> float:
	if kin < 0.0625:
		return 0.0
	if kin < 0.125:
		return 0.05
	if kin < 0.25:
		return 0.15
	return 0.35


# --------------------------------------------------------------------------
# 推进一年
# --------------------------------------------------------------------------

func step(policy: int, gene_flow_per_year: float = 0.0, magic_tide: bool = false) -> void:
	if extinct:
		return
	year += 1

	# 1) 老化与寿终
	var died: Array = []
	for id in beasts.keys():
		var b: Beast = beasts[id]
		b.age += 1.0
		if b.breed_cooldown > 0.0:
			b.breed_cooldown -= 1.0
		if b.age >= b.lifespan:
			died.append(_death_record(b))
			stat_deaths += 1
			beasts.erase(id)
	for rec in died:
		_note_death(rec)

	# 2) 分娩（去年受孕的）
	var births: Array = []
	for id in beasts.keys():
		var mother: Beast = beasts[id]
		if not mother.pregnant:
			continue
		mother.pregnant = false
		mother.breed_cooldown = BREEDING_INTERVAL
		var n := 2 if Genome.rng.randf() < TWIN_CHANCE else 1
		for _i in n:
			if Genome.rng.randf() < _stillbirth_from_kin(mother.pending_kin):
				continue
			var g := Genome.breed(mother.genome, mother.pending_father_genome,
				mother.pending_kin, magic, pool, magic_tide)
			var nb := Beast.new()
			nb.genome = g
			nb.sex = Genome.rng.randi_range(0, 1)
			nb.father = mother.pending_father
			nb.mother = mother.id
			nb.generation = maxi(mother.generation, mother.pending_father_gen) + 1
			nb.surname = surname_for(mother.pending_father_name,
				mother.pending_father_surname, mother.name, mother.surname,
				nb.is_male())
			nb.traits = Persona.roll_traits(Genome.rng, 1 + Genome.rng.randi_range(1, 2),
				mother.pending_father_traits, mother.traits)
			nb.hobbies = Persona.roll_hobbies(Genome.rng)
			nb.mood = 70.0
			nb.traits = Persona.roll_traits(Genome.rng, 1 + Genome.rng.randi_range(1, 2),
				mother.pending_father_traits, mother.traits)
			nb.hobbies = Persona.roll_hobbies(Genome.rng)
			nb.mood = 70.0
			nb.age = 0.0
			nb.lifespan = Genome.rng.randf_range(LIFESPAN_MIN, LIFESPAN_MAX)
			if Genome.rng.randf() < _defect_from_kin(mother.pending_kin) * defect_resist:
				g.defects.append(DEFECT_TABLE[Genome.rng.randi_range(0, DEFECT_TABLE.size() - 1)])
			stat_births += 1
			if not g.defects.is_empty():
				stat_defect_births += 1
			if mother.pending_kin > 0.125:
				stat_inbreed_births += 1
			if not g.chimeras().is_empty():
				stat_chimera_births += 1
			births.append(nb)
	for nb in births:
		_register(nb)
		# 个人史只记**真实发生过的事**，不编造背景。
		_log_story(nb, "出生在%s氏，母亲是%s。" % [
			nb.surname if nb.surname != "" else "无名",
			beasts[nb.mother].display_name() if beasts.has(nb.mother) else "已故之人"])
		if beasts.has(nb.mother):
			var mom: Beast = beasts[nb.mother]
			_log_story(mom, "生下了%s。" % nb.display_name())
			mom.mood = minf(100.0, mom.mood + 9.0)

	# 3) 承载力：超出即饿死
	if beasts.size() > k_cap:
		var ids: Array = beasts.keys()
		_shuffle(ids)
		var excess := beasts.size() - k_cap
		for i in excess:
			beasts.erase(ids[i])

	# 4) 交配与受孕
	var females: Array = []
	for id in beasts:
		var b: Beast = beasts[id]
		if not b.is_male() and b.age >= MATURITY_AGE and b.breed_cooldown <= 0.0 \
				and not b.pregnant and b.is_fertile():
			females.append(id)
	_shuffle(females)
	for fid in females:
		var female: Beast = beasts[fid]
		var mid := _choose_mate(fid, policy)
		if mid < 0:
			continue
		var male: Beast = beasts[mid]
		var kin := pedigree.kinship(fid, mid)
		var p := CONCEPTION_CHANCE * _fertility_from_kin(kin) * (1.0 - _sterility_from_kin(kin))
		if Genome.rng.randf() < p:
			female.pregnant = true
			female.pending_father = mid
			female.pending_father_gen = male.generation
			female.pending_kin = kin
			female.pending_father_genome = male.genome
			female.pending_father_surname = male.surname
			female.pending_father_name = male.name

	# 5) 基因流：外来者（联姻 / 收留 / 掠夺）
	if Genome.rng.randf() < gene_flow_per_year:
		_register(_make_outsider())

	# 6) 灭绝判定
	if beasts.size() < 3 or not _has_breeding_pair():
		extinct = true
		extinction_year = year

	_record()


## 外部触发的受孕：休息所配对、法术强制配对走这条路。
## 自然配对仍然是 step() 里的自主择偶 —— 三条路互不干扰。
func conceive(mother_id: int, father_id: int, chance: float) -> bool:
	if not beasts.has(mother_id) or not beasts.has(father_id):
		return false
	var m: Beast = beasts[mother_id]
	var f: Beast = beasts[father_id]
	if m.is_male() or not f.is_male():
		return false
	if m.age < MATURITY_AGE or m.breed_cooldown > 0.0 or m.pregnant or not m.is_fertile():
		return false
	if f.age < MATURITY_AGE or not f.is_fertile():
		return false
	var kin := pedigree.kinship(mother_id, father_id)
	var p := chance * _fertility_from_kin(kin) * (1.0 - _sterility_from_kin(kin))
	if Genome.rng.randf() >= p:
		return false
	m.pregnant = true
	m.pending_father = father_id
	m.pending_father_gen = f.generation
	m.pending_kin = kin
	m.pending_father_genome = f.genome
	m.pending_father_surname = f.surname
	return true


func _has_breeding_pair() -> bool:
	var has_m := false
	var has_f := false
	for id in beasts:
		var b: Beast = beasts[id]
		if b.age >= MATURITY_AGE and b.is_fertile():
			if b.is_male():
				has_m = true
			else:
				has_f = true
	return has_m and has_f


## 随机移除 n 人（饥饿、灾祸、战斗损失）。
## 返回实际移除的人数。注意：这会直接改写 beasts，调用方负责重建/刷新视图。
func kill_random(n: int) -> int:
	if n <= 0 or beasts.is_empty():
		return 0
	var ids: Array = beasts.keys()
	_shuffle(ids)
	var removed := mini(n, ids.size())
	stat_deaths += removed
	var recs: Array = []
	for i in removed:
		recs.append(_death_record(beasts[ids[i]]))
		beasts.erase(ids[i])
	for rec in recs:
		_note_death(rec)
	_recheck_extinction()
	return removed


## 按优先级移除：先老人，再幼崽，最后成年。残酷但符合饥饿的真实顺序。
func kill_weakest(n: int) -> int:
	if n <= 0 or beasts.is_empty():
		return 0
	# 用标量排序键，避免在 lambda 里访问成员（GDScript 的 lambda 捕获行为容易踩坑）
	var ranked: Array = []
	for id in beasts:
		var b: Beast = beasts[id]
		var key: float = b.age if b.age >= MATURITY_AGE else (1000.0 - b.age)
		ranked.append([key, id])
	ranked.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var removed := mini(n, ranked.size())
	stat_deaths += removed
	var recs: Array = []
	for i in removed:
		var victim: Beast = beasts[ranked[i][1]]
		recs.append(_death_record(victim))
		beasts.erase(ranked[i][1])
	for rec in recs:
		_note_death(rec)
	_recheck_extinction()
	return removed


func _recheck_extinction() -> void:
	if beasts.size() < 3 or not _has_breeding_pair():
		extinct = true
		if extinction_year < 0:
			extinction_year = year


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := Genome.rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --------------------------------------------------------------------------
# 择偶
# --------------------------------------------------------------------------

func _males() -> Array:
	var out: Array = []
	for id in beasts:
		if beasts[id].is_male():
			out.append(id)
	return out


func _females() -> Array:
	var out: Array = []
	for id in beasts:
		if not beasts[id].is_male():
			out.append(id)
	return out


func _choose_mate(fid: int, policy: int) -> int:
	# 学会「选育」之后，部落自己就会按嵌合潜力挑对象
	if planned_pairing and policy == Policy.AVOID_INBREEDING:
		policy = Policy.PLANNED_CHIMERA
	var female: Beast = beasts[fid]
	var males: Array = []
	for id in beasts:
		var b: Beast = beasts[id]
		if b.is_male() and b.age >= MATURITY_AGE and b.is_fertile():
			males.append(id)
	if males.is_empty():
		return -1
	_shuffle(males)

	if policy == Policy.RANDOM:
		return males[0]

	var best_id := -1
	var best_score := -INF
	for mid in males:
		var kin := pedigree.kinship(fid, mid)
		var score := 0.0
		if policy == Policy.AVOID_INBREEDING:
			# 近交禁忌让部落更主动地避开血亲
			score = -kin * kin_avoid
		elif policy == Policy.PURE_LINE:
			# 选型交配：优先与「共享同一条高血浓血脉」的雄性配对。
			# 这模拟玩家为纯化血脉而做的定向配对，也是近交的主要人为来源。
			score = _shared_line_score(female.genome, beasts[mid].genome)
		else:
			if kin > CHIMERA_KIN_MAX:
				continue
			score = _future_chimera(female.genome, beasts[mid].genome, [fid, mid]) \
				- CHIMERA_KIN_WEIGHT * maxf(0.0, kin - 0.0625)
		# 氏族外婚：双重继嗣制下「同姓不婚」。
		# 做成评分惩罚而不是硬禁止 —— 小部落里硬禁止会直接绝后。
		if (Descent.has_clan_exogamy(descent_mode) or clan_exogamy) and female.surname != "" \
				and female.surname == beasts[mid].surname:
			score -= CLAN_EXOGAMY_PENALTY
		# 关系好的人更容易走到一起。
		# **权重必须当作微调，不能当主项**：chimera_score 的量程是 0–1，
		# 之前用 0.004（±0.4）等于让好感盖过遗传优化，择偶退化成"只跟喜欢的人配"，
		# 嵌合率下滑、劳动产出下滑，迁徙节奏中位数被推前了 4 个回合。
		score += relation(fid, mid) * RELATION_MATE_WEIGHT
		if score > best_score:
			best_score = score
			best_id = mid

	if best_id < 0:
		# 所有候选都被亲缘门槛挡掉 → 退化为选最低亲缘
		var best_kin := INF
		for mid in males:
			var kin2 := pedigree.kinship(fid, mid)
			if kin2 < best_kin:
				best_kin = kin2
				best_id = mid
	return best_id


## 两条基因组共享血脉的最高「双方都达到」的血浓。
## 用于模拟玩家为纯化某条血脉而做的定向配对。
static func _shared_line_score(a: Genome, b: Genome) -> float:
	var best := 0.0
	for k in a.titers:
		if not b.titers.has(k):
			continue
		best = maxf(best, float(mini(int(a.titers[k]), int(b.titers[k]))))
	return best


## 这对组合的「两代内达成嵌合」潜力 0..1。## 第一代看直接子代，第二代在当前种群中采样若干潜在配偶看孙辈。
func _future_chimera(gm: Genome, gf: Genome, exclude: Array) -> float:
	var expect := Genome.expected_titers(gm, gf)
	var best := Genome.chimera_score(expect)
	var child_proxy := Genome.from_titers(expect)

	var others: Array = []
	for id in beasts:
		if exclude.has(id):
			continue
		others.append(id)
	_shuffle(others)
	var limit := mini(LOOKAHEAD_SAMPLE, others.size())
	for i in limit:
		var g2: Genome = beasts[others[i]].genome
		best = maxf(best, Genome.chimera_score(Genome.expected_titers(child_proxy, g2)))
	return best


# --------------------------------------------------------------------------
# 指标
# --------------------------------------------------------------------------

func population() -> int:
	return beasts.size()


func current_generation() -> int:
	var g := 0
	for id in beasts:
		g = maxi(g, beasts[id].generation)
	return g


func mean_inbreeding() -> float:
	if beasts.is_empty():
		return 0.0
	var total := 0.0
	for id in beasts:
		total += beasts[id].genome.inbreeding
	return total / float(beasts.size())


func max_inbreeding() -> float:
	var m := 0.0
	for id in beasts:
		m = maxf(m, beasts[id].genome.inbreeding)
	return m


## 只统计已达性成熟者——近交的实际生理后果只由他们承担。
func mean_inbreeding_adult() -> float:
	var total := 0.0
	var n := 0
	for id in beasts:
		var b: Beast = beasts[id]
		if b.age >= MATURITY_AGE:
			total += b.genome.inbreeding
			n += 1
	return total / float(n) if n > 0 else 0.0


## 部落层面的血脉多样性指数（辛普森，对全族血浓求和）。
func tribe_bdi() -> float:
	var totals := {}
	var sum := 0.0
	for id in beasts:
		for k in beasts[id].genome.titers:
			var v := float(beasts[id].genome.titers[k])
			totals[k] = float(totals.get(k, 0.0)) + v
			sum += v
	if sum <= 0.0:
		return 0.0
	var partial := 0.0
	for k in totals:
		var p := float(totals[k]) / sum
		partial += p * p
	return 1.0 - partial


func chimera_rate() -> float:
	if beasts.is_empty():
		return 0.0
	var n := 0
	for id in beasts:
		if beasts[id].has_chimera():
			n += 1
	return float(n) / float(beasts.size())


func dilute_rate() -> float:
	if beasts.is_empty():
		return 0.0
	var n := 0
	for id in beasts:
		if beasts[id].genome.is_dilute():
			n += 1
	return float(n) / float(beasts.size())


func max_top_titer() -> int:
	var m := 0
	for id in beasts:
		m = maxi(m, beasts[id].genome.top_titer())
	return m


func mean_top_titer() -> float:
	if beasts.is_empty():
		return 0.0
	var total := 0.0
	for id in beasts:
		total += float(beasts[id].genome.top_titer())
	return total / float(beasts.size())


func expressed_rate() -> float:
	if beasts.is_empty():
		return 0.0
	var n := 0
	for id in beasts:
		if not beasts[id].genome.expressed().is_empty():
			n += 1
	return float(n) / float(beasts.size())


func sex_ratio() -> float:
	if beasts.is_empty():
		return 0.0
	var m := 0
	for id in beasts:
		if beasts[id].is_male():
			m += 1
	return float(m) / float(beasts.size())


func metrics() -> Dictionary:
	return {
		"year": year,
		"generation": current_generation(),
		"population": population(),
		"mean_f": mean_inbreeding(),
		"mean_f_adult": mean_inbreeding_adult(),
		"max_f": max_inbreeding(),
		"bdi": tribe_bdi(),
		"chimera_rate": chimera_rate(),
		"dilute_rate": dilute_rate(),
		"mean_top_titer": mean_top_titer(),
		"max_top_titer": max_top_titer(),
		"expressed_rate": expressed_rate(),
		"sex_ratio": sex_ratio(),
		"extinct": extinct,
	}


func _record() -> void:
	history.append(metrics())


func beast_list() -> Array:
	var out: Array = []
	for id in beasts:
		out.append(beasts[id])
	return out


func snapshot() -> String:
	var m := metrics()
	return "第%3d年(第%d代) pop=%2d F=%.3f BDI=%.3f 嵌合=%.0f%% 稀薄=%.0f%% 最高血浓=%d" % [
		m["year"], m["generation"], m["population"], m["mean_f"], m["bdi"],
		m["chimera_rate"] * 100.0, m["dilute_rate"] * 100.0, m["max_top_titer"],
	]
