class_name Beast
extends RefCounted
## 一只兽人。基因组之外的部分：性别、年龄、世代、双亲。
## 目前只承载遗传模拟需要的字段；工作/战斗/进化状态在后续里程碑补。

enum Sex { FEMALE = 0, MALE = 1 }

var id: int = -1
var sex: int = Sex.FEMALE
var generation: int = 0          # 出生世代（奠基者 = 0）
var genome: Genome = null
var father: int = -1
var mother: int = -1
var alive: bool = true
var surname: String = ""      ## 姓：父姓首字 + 母姓首字（双姓），记录混血来源
var name: String = ""         ## 名：两个音节，如「灰耳」「长牙」

# --- 人口学字段（重叠世代模型）---
var age: float = 0.0
var lifespan: float = 55.0
var breed_cooldown: float = 0.0
var pregnant: bool = false
var pending_father: int = -1
var pending_father_gen: int = 0
var pending_kin: float = 0.0
var pending_father_genome: Genome = null
var pending_father_surname: String = ""
var pending_father_traits: Array = []

# --- 在地图上的状态（供 SiteMap 与视图层使用）---
enum Activity { IDLE = 0, WALKING = 1, WORKING = 2, RESTING = 3 }
var site_id: int = -1                 ## 被指派到哪个工作点（-1 = 没指派）

# --- 人格层 ---
var traits: Array = []                ## Array[StringName] 性情（2-3 条）
var hobbies: Array = []               ## Array[int] 偏好工作类型（SiteMap.Kind）
var mood: float = 70.0                ## 个人心情 0-100，影响个人产出
var thought: String = ""              ## 当前想法（每回合重算）
var story: Array = []                 ## Array[{turn, text}] 个人史
var partner_id: int = -1              ## 伴侣（关系值到阈值后自动确立）
var pending_father_name: String = ""  ## 父名制/母名制需要父亲的名（父姓制只要姓）
var activity: int = Activity.IDLE
var visual_pos: Vector2 = Vector2.ZERO   ## 视图层的平滑位置（像素）
var forced_pair_with: int = -1        ## 被法术强制结合的对象的 id（-1 = 无）


func _init(p_id: int = -1, p_sex: int = Sex.FEMALE, p_genome: Genome = null) -> void:
	id = p_id
	sex = p_sex
	genome = p_genome


func is_male() -> bool:
	return sex == Sex.MALE


## 出生时的继嗣制度。**一个人一辈子用自己出生时的名字形式** ——
## 部落改制之后，老人还是老样子，新生的孩子才是新规矩。
## 这个过渡在成员列表上直接看得见。
var descent_mode: int = -1

## 完整称呼。具体形式由继嗣制度决定（姓在前，还是父母名挂在后面）。
func display_name() -> String:
	if descent_mode < 0:
		return name if surname == "" else "%s·%s" % [surname, name]
	return Descent.display(self, descent_mode)


## 姓的第一字：传给下一代的那一半。
func surname_root() -> String:
	return surname.substr(0, 1) if surname != "" else ""


## 与另一个个体的姓氏亲缘初判（用于列表排序/分组，不参与遗传计算）。
func shares_surname_with(other: Beast) -> bool:
	return surname != "" and surname == other.surname


## 各类缺陷对劳动能力的折损。近交不是抽象的数值惩罚，它会让人真的干不动活。
const DEFECT_LABOR_PENALTY := {
	&"inbreeding_defect": 0.25,
	&"blind": 0.50,          ## 盲
	&"deaf": 0.10,           ## 聋
	&"frail_bones": 0.40,    ## 骨脆
	&"manaplague": 0.30,     ## 魔素病
	&"early_aging": 0.15,    ## 早衰
	&"sterile": 0.0,         ## 不育：不影响劳动，只影响传承
	&"line_locked": 0.0,     ## 血脉锁死：不影响劳动，只影响进化
}


## 早衰缺陷按更老的年龄结算。
func effective_age() -> float:
	if genome != null and genome.defects.has(&"early_aging"):
		return age * 1.4
	return age


## 劳动能力 0..1。**这是能力，不是「成年/未成年」的硬切分。**
##
##   * 年龄曲线：3 岁起开始搭手，6 岁约 0.35，14 岁满勤，45 岁后缓降，
##     60 岁后继续缓降但**保底 0.15**——只要还能动就在干活。
##   * 伤残系数：近交缺陷真的会削弱产出（盲 ×0.5、骨脆 ×0.6……）。
##
## 所以：**一个瞎了的壮年劳力，不如一个健康的老人。**
## 这也让遗传系统和经济系统真正咬合——玩家追求纯化时，代价会以「干不动活的人」的形式出现。
## 心情对个人产出的影响。
## **必须以基准心情（70）为 1.0 来标定** —— 早期版本写成 0.88 + 0.12×心情/100，
## 结果基准心情下只有 0.964，等于给全员产出凭空砍了 3.6%，把迁徙节奏整体推快了。
func mood_factor() -> float:
	return clampf(1.0 + (mood - 70.0) / 100.0 * 0.25, 0.78, 1.10)


func story_lines(n: int = 8) -> Array:
	var out: Array = []
	var start: int = maxi(0, story.size() - n)
	for i in range(start, story.size()):
		out.append(story[i])
	return out


func labor_capacity() -> float:
	if genome == null:
		return 1.0
	var a := effective_age()
	var by_age := 0.0
	if a < 3.0:
		by_age = 0.0
	elif a < 6.0:
		by_age = (a - 3.0) / 3.0 * 0.35
	elif a < 14.0:
		by_age = 0.35 + (a - 6.0) / 8.0 * 0.65
	elif a < 45.0:
		by_age = 1.0
	elif a < 60.0:
		by_age = 1.0 - (a - 45.0) / 15.0 * 0.30
	else:
		by_age = maxf(0.15, 0.70 - (a - 60.0) / 20.0 * 0.55)

	var penalty := 0.0
	for d in genome.defects:
		penalty += float(DEFECT_LABOR_PENALTY.get(d, 0.25))
	# 性情与心情也乘进来：勤勉的人多干，怠惰的人少干，心情差的人出工不出力
	return clampf(by_age * (1.0 - minf(penalty, 0.85))
		* Persona.labor_mult(self) * mood_factor(), 0.0, 1.0)


func is_fertile() -> bool:
	return genome == null or not genome.defects.has(&"sterile")


func has_chimera() -> bool:
	return genome != null and not genome.chimeras().is_empty()


func label() -> String:
	return "%s#%d %s" % [
		"雄" if is_male() else "雌",
		id,
		genome.describe() if genome != null else "<无基因组>",
	]


## 全字段序列化。**31 个字段一个都不能漏** —— 漏一个，
## 读档后那项就悄悄变回默认值，而且往往要跑几十回合才看得出来。
## 所以有一条"轨迹测试"专门守这件事：存档后跑 N 回合，
## 与读档后再跑 N 回合，两边必须逐字段完全相同。
func to_dict() -> Dictionary:
	var pend_traits: Array = []
	for t in pending_father_traits:
		pend_traits.append(String(t))
	var tr: Array = []
	for t in traits:
		tr.append(String(t))
	var hb: Array = []
	for h in hobbies:
		hb.append(int(h))
	return {
		"id": id, "sex": sex, "generation": generation, "father": father,
		"mother": mother, "alive": alive, "name": name, "surname": surname,
		"descent_mode": descent_mode,
		"genome": genome.to_dict() if genome != null else {},
		"age": age, "lifespan": lifespan, "breed_cooldown": breed_cooldown,
		"pregnant": pregnant,
		"pending_father": pending_father, "pending_father_gen": pending_father_gen,
		"pending_kin": pending_kin, "pending_father_surname": pending_father_surname,
		"pending_father_name": pending_father_name,
		"pending_father_traits": pend_traits,
		"pending_father_genome": (pending_father_genome.to_dict()
			if pending_father_genome != null else {}),
		"site_id": site_id, "activity": activity, "visual_pos": visual_pos,
		"traits": tr, "hobbies": hb, "mood": mood, "thought": thought,
		"story": story.duplicate(true), "partner_id": partner_id,
		"forced_pair_with": forced_pair_with,
	}


static func from_dict(d: Dictionary) -> Beast:
	var b := Beast.new(int(d.get("id", -1)), int(d.get("sex", 0)))
	b.generation = int(d.get("generation", 0))
	b.father = int(d.get("father", -1))
	b.mother = int(d.get("mother", -1))
	b.alive = bool(d.get("alive", true))
	b.name = String(d.get("name", ""))
	b.surname = String(d.get("surname", ""))
	b.descent_mode = int(d.get("descent_mode", -1))
	var gd: Dictionary = d.get("genome", {})
	b.genome = Genome.from_dict(gd) if not gd.is_empty() else null
	b.age = float(d.get("age", 0.0))
	b.lifespan = float(d.get("lifespan", 55.0))
	b.breed_cooldown = float(d.get("breed_cooldown", 0.0))
	b.pregnant = bool(d.get("pregnant", false))
	b.pending_father = int(d.get("pending_father", -1))
	b.pending_father_gen = int(d.get("pending_father_gen", 0))
	b.pending_kin = float(d.get("pending_kin", 0.0))
	b.pending_father_surname = String(d.get("pending_father_surname", ""))
	b.pending_father_name = String(d.get("pending_father_name", ""))
	for t in d.get("pending_father_traits", []):
		b.pending_father_traits.append(StringName(t))
	var pgd: Dictionary = d.get("pending_father_genome", {})
	b.pending_father_genome = Genome.from_dict(pgd) if not pgd.is_empty() else null
	b.site_id = int(d.get("site_id", -1))
	b.activity = int(d.get("activity", Activity.IDLE))
	b.visual_pos = d.get("visual_pos", Vector2.ZERO)
	for t in d.get("traits", []):
		b.traits.append(StringName(t))
	for h in d.get("hobbies", []):
		b.hobbies.append(int(h))
	b.mood = float(d.get("mood", 70.0))
	b.thought = String(d.get("thought", ""))
	for e in d.get("story", []):
		b.story.append({"turn": int(e.get("turn", 0)), "text": String(e.get("text", ""))})
	b.partner_id = int(d.get("partner_id", -1))
	b.forced_pair_with = int(d.get("forced_pair_with", -1))
	return b
