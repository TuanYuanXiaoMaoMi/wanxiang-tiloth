# 07 数据结构与 Godot 实现

> 目标环境：**Godot 4.7.x**（本机已装 4.7.1.stable），GDScript，2D。
> 核心架构原则：**模拟层不依赖节点，视图层只读模拟层。**

## 7.1 为什么必须分层

部落模拟需要在一秒内推进数百个个体、几十个节点的资源结算。同时，遗传系统**必须能离线跑几千代来调平衡**——这件事在编辑器里手动点是不可能完成的。

所以：

| 层 | 基类 | 职责 | 能否 headless |
|---|---|---|---|
| **Sim 层** | `RefCounted` / `Resource` | 血脉、遗传、资源结算、灾祸、AI、世界状态 | ✅ 纯数据，无节点 |
| **View 层** | `Node2D` / `Control` | 渲染、动画、输入、UI | ❌ |

**收益**：可以用 `godot --headless --script res://tools/balance_sim.gd` 直接跑 1000 代遗传模拟，输出 BDI / I 系数 / 嵌合出现率的分布直方图。**遗传系统的平衡只能靠这种方式调，不能靠手感。**

## 7.2 目录结构

**✅ = M0/M1 已实现**（当前仓库里的真实状态）

```
res://
├── project.godot
├── data/
│   ├── ✅ genetics.json       # 7 类群 / 16 血脉 / 21 嵌合
│   └── ✅ regions.json        # 6 大区 × 14 节点，含逻辑斯蒂资源参数与邻接图
│                              #   规模上去后再拆成 data/bloodlines/*.json
├── sim/                       # ★ 纯逻辑，禁止 preload 任何 Node 场景
│   ├── ✅ bloodline_db.gd     # 数据加载、校验、查询（BloodlineDB）
│   ├── ✅ pedigree.gd         # Wright 亲缘系数递推 + 记忆化（Pedigree）
│   ├── ✅ genome.gd           # 血浓、区间、嵌合、遗传、突变（Genome）
│   ├── ✅ beast.gd            # 个体：性别、年龄、寿限、世代、双亲（Beast）
│   ├── ✅ tribe.gd            # 人口模型 + 四种配对策略 + 基因流（Tribe）
│   ├── ✅ region.gd           # 节点资源结算：逻辑斯蒂存量 + 永久生态退化（Region）
│   ├── ✅ region_db.gd        # 区域数据层 + 邻接图 + 旅途天数（RegionDB）
│   ├── ✅ world_state.gd      # 日 tick、粮仓、饱食、饥饿减员、迁徙（WorldState）
│   ├── ⬜ disaster_system.gd
│   ├── ⬜ faction_ai.gd
│   └── ⬜ migration.gd        # 迁徙五阶段（侦察/打包/留守名单/旅途事件）
├── game/                      # 节点层：把 sim 接到引擎
│   ├── ✅ main.tscn / main.gd # M1 垂直切片主界面（资源仪表 / 成员列表 / 谱系规划器 / 迁徙）
│   ├── ⬜ world_controller.gd
│   ├── ⬜ tick_driver.gd
│   └── ⬜ save_manager.gd
├── ui/
│   └── ⬜ pedigree_planner/   # ★ 谱系规划器（最优先的 UI）
├── art/
│   ├── ⬜ parts/              # 部件组合素材（见文档 08）
│   └── ⬜ shaders/portrait_blend.gdshader
├── tools/
│   ├── ✅ godot.sh            # 启动包装（把 HOME 指到 .ghome，见 7.2.1）
│   ├── ✅ run_tests.gd        # 60 项单元测试
│   ├── ✅ balance_sim.gd      # 遗传平衡模拟 → reports/balance_report.md
│   ├── ✅ resource_sim.gd     # 资源与迁徙节奏标定 → reports/resource_report.md
│   ├── ✅ debug_tribe.gd      # 逐年诊断单个部落（只看遗传）
│   └── ✅ debug_economy.gd    # 逐年食物账本（定位「粮仓有粮却饿死」靠它）
└── reports/
    ├── ✅ balance_report.md   # 遗传平衡，自动生成，勿手改
    └── ✅ resource_report.md  # 资源与迁徙节奏，自动生成，勿手改
```

### 7.2.1 为什么需要 `tools/godot.sh`

Godot 启动时要写用户目录（macOS 上是 `~/Library/Application Support/Godot`）。
在沙箱、CI 或容器里这一步会被拒绝，而 Godot 4.7 **在写目录失败后会直接段错误崩溃**，报错信息完全指不到真正的原因。

包装脚本只做一件事：把 `HOME` 指到工作区内的 `.ghome`，然后 `--path` 启动。

```bash
./tools/godot.sh --headless --script res://tools/run_tests.gd
GODOT_BIN=/path/to/godot ./tools/godot.sh --headless --script res://tools/balance_sim.gd
```

**硬规则**：`sim/` 下的任何文件**不允许**出现 `Node`、`get_node`、`@onready`、`preload("*.tscn")`。用 CI 或一个 lint 脚本检查这一点。

## 7.3 Godot 4.7 注意事项

| 事项 | 说明 |
|---|---|
| **用 `TileMapLayer`** | `TileMap` 节点在 4.3+ 已废弃，新项目直接用 `TileMapLayer` |
| **`randfn(mean, deviation)`** | 内置正态分布，遗传噪声直接用，不需要手写 Box-Muller |
| **静态类型** | `sim/` 全部标注类型。类型化 GDScript 在 4.x 有显著性能优势，且能在编译期发现大量错误 |
| **`StringName` 做 id** | 血脉 id、事件 id 全部用 `&"fel_cat"`，字典查找更快且不产生字符串副本 |
| **`Resource` 做数据定义** | 静态定义（血脉、进化节点）可用 `.tres`；但**本方案选 JSON**，理由见 7.4 |
| **存档不用 `ResourceSaver`** | `Resource` 存盘会绑定类路径，版本迁移和模组兼容都很痛苦。用 JSON + `save_version` |
| **`await` 而非 `yield`** | 4.x 语法 |
| **`Callable` + 信号** | 视图层事件总线用 `signal`；`sim/` 层只用直接函数调用，不用信号（保持可测、可 headless 运行） |

## 7.4 为什么数据用 JSON 而不是 .tres

| | JSON | .tres |
|---|---|---|
| 模组作者友好度 | ✅ 任何文本编辑器 | ⚠️ 需要 Godot 或手写资源格式 |
| 版本控制 diff | ✅ 干净 | ⚠️ 嘈杂 |
| 平衡调参 | ✅ 可脚本批量改 | ❌ |
| 类型安全 | ❌ 需校验层 | ✅ |
| 编辑器可视化编辑 | ❌ | ✅ |

**结论**：用 JSON，但在启动时用 `db.gd` 把 JSON 转成类型化的 `Resource` 包装对象，并做 **schema 校验**（缺字段 / 未知 id 直接报错并回退到默认值）。这样既保住模组友好度，又拿到类型安全。

制作期可以额外写一个**极简编辑器插件**（`EditorPlugin` + `@tool`）来可视化编辑 JSON，但这是 M4 的事。

## 7.5 数据定义示例

### `data/bloodlines/fel_cat.json`

```json
{
  "id": "fel_cat",
  "name_key": "BLOODLINE_FEL_CAT",
  "clade": "shadow",
  "main_attr": "agility",
  "sub_attr": "perception",
  "main_coeff": 0.30,
  "sub_coeff": 0.12,
  "innate_trait": {
    "id": "silent_step",
    "name_key": "TRAIT_SILENT_STEP",
    "desc_key": "TRAIT_SILENT_STEP_DESC",
    "effect": { "type": "no_alert_at_night", "value": 1.0 }
  },
  "magic_affinity": ["space"],
  "appearance": {
    "ear": "ear_triangle",
    "tail": "tail_short_fluff",
    "pupil": "pupil_slit",
    "pattern": "pattern_tabby",
    "hue_base": 30.0,
    "hue_range": 20.0,
    "body_scale": 1.0
  },
  "rarity": 1.0,
  "region_weights": { "green_throat": 1.0, "longshore": 0.6, "frost_ridge": 0.3 }
}
```

### `data/clades.json`（含 21 组嵌合）

```json
{
  "clades": {
    "shadow": { "name_key": "CLADE_SHADOW", "bloodlines": ["fel_cat", "fel_leo"] },
    "pack":   { "name_key": "CLADE_PACK",   "bloodlines": ["can_wolf", "can_hound", "vul_fox"] }
  },
  "chimeras": [
    {
      "id": "chimera_sky_hunter",
      "clades": ["shadow", "feather"],
      "name_key": "CHIMERA_SKY_HUNTER",
      "trait": { "type": "glide_dive", "first_hit_mult": 2.5 },
      "evolution_tree": "tree_sky_hunter",
      "cross_school": ["space", "storm"],
      "rarity_mult": 1.0
    },
    {
      "id": "chimera_dragonkin",
      "clades": ["feather", "scale"],
      "name_key": "CHIMERA_DRAGONKIN",
      "trait": { "type": "flight_breath", "element": "auto" },
      "evolution_tree": "tree_dragonkin",
      "cross_school": ["storm", "blood"],
      "rarity_mult": 0.5
    }
  ]
}
```

### `data/regions/green_throat.json`（节选）

```json
{
  "id": "green_throat",
  "nodes": {
    "gt_ashwater": {
      "biome": "temperate_forest",
      "food_K": 800, "food_r": 0.08, "food_stock": 760,
      "prey_K": 90, "prey_r": 0.03, "prey_stock": 85,
      "wood": 400, "stone": 60, "crystal": 0, "herb": 120,
      "magic_density": 0.35,
      "danger": 1,
      "disaster_bias": { "drought": 0.6, "flood": 1.4, "beast_tide": 0.8 },
      "blood_pool": ["can_wolf", "vul_fox", "lepus_hare"],
      "adjacent": { "gt_deeproot": 3, "gt_saltmarsh": 5 },
      "owner": null
    }
  }
}
```

### `data/disasters/winter.json`

```json
{
  "id": "winter",
  "category": "natural",
  "name_key": "DISASTER_WINTER",
  "omen_days": [10, 20],
  "duration_days": [30, 60],
  "omen_text_key": "OMEN_WINTER",
  "effects": {
    "food_consumption_mult": 1.5,
    "daily_cold_death_check": { "attr": "vitality", "dc": 25 },
    "requires": "hide_or_shelter"
  },
  "responses": ["migrate_south", "bear_hibernate", "cave_camp", "hoard_food"],
  "aftermath": [
    { "type": "grant_trait", "trait": "trait_frost", "inherit": true },
    { "type": "morale", "value": 10, "condition": "deaths_over_30pct", "reason": "winter_memory" }
  ]
}
```

## 7.6 运行时数据模型

```gdscript
# sim/genome.gd
class_name Genome
extends RefCounted

const MAX_BLOODLINES := 6
const TITER_EXPRESSED := 60      # 显征
const TITER_LATENT := 35         # 潜征 / 嵌合门槛
const TITER_HIDDEN := 15         # 隐没
const CHIMERA_MAX_DIFF := 15     # 嵌合允许的最大血浓差
const DILUTE_BONUS := 3          # 混血稀释惩罚

var titers: Dictionary = {}          # StringName -> int (1..100)
var inbreeding: float = 0.0          # F 系数
var ancestors: Array[StringName] = []  # 祖先个体 id（用于近亲估算）
var defects: Array[StringName] = []

func expressed() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in titers:
		if titers[k] >= TITER_EXPRESSED: out.append(k)
	return out

func is_dilute() -> bool:
	# 血脉稀薄：没有任何一条达到潜征门槛
	for k in titers:
		if titers[k] >= TITER_LATENT: return false
	return true
```

```gdscript
# sim/genome.gd（续） — 核心遗传函数
static func breed(a: Genome, b: Genome, magic: float,
		region_pool: Array[StringName]) -> Genome:
	var child := Genome.new()
	var keys := {}
	for k in a.titers: keys[k] = true
	for k in b.titers: keys[k] = true

	# 1) 逐血脉继承
	for k in keys:
		var ta: int = a.titers.get(k, 0)
		var tb: int = b.titers.get(k, 0)
		var t := _inherit_one(ta, tb, magic)
		if t > 0:
			child.titers[k] = t

	# 2) 混血稀释：父母各有 >=40 的不同血脉时，各扣 3
	var strong_a := a.strong_bloodlines(40)
	var strong_b := b.strong_bloodlines(40)
	if strong_a.size() > 0 and strong_b.size() > 0 \
			and BloodlineDB.clade_of(strong_a[0]) != BloodlineDB.clade_of(strong_b[0]):
		for k in strong_a + strong_b:
			if child.titers.has(k):
				child.titers[k] = maxi(1, child.titers[k] - DILUTE_BONUS)

	# 3) 突变
	_apply_mutation(child, magic, region_pool)

	# 4) 条数上限
	_trim_to_limit(child)

	# 5) 近交与谱系
	child.ancestors = _merge_ancestors(a, b)
	child.inbreeding = _inbreeding(a, b)
	return child

static func _inherit_one(ta: int, tb: int, magic: float) -> int:
	# 返祖：暗池血脉（1..14）有 15% 概率爆发
	var lo: int = mini(ta, tb)
	var hi: int = maxi(ta, tb)
	if lo >= 1 and hi <= Genome.TITER_HIDDEN and randf() < 0.15:
		return randi_range(25, 45)

	var t := (ta + tb) * 0.5
	if lo >= Genome.TITER_EXPRESSED:
		t += 6.0                                        # 纯化加固
	t += randfn(0.0, 3.0 + 5.0 * magic)                 # 随机扰动
	return clampi(roundi(t), 0, 100)

static func _apply_mutation(child: Genome, magic: float,
		region_pool: Array[StringName]) -> void:
	var surge := MagicTide.is_active()                  # 魔潮期 ×3
	var p_new := (0.02 + 0.08 * magic) * (3.0 if surge else 1.0)
	if randf() < p_new and region_pool.size() > 0:
		var n := 1 + (1 if randf() < 0.25 else 0)
		for i in n:
			var bl: StringName = region_pool.pick_random()
			child.titers[bl] = randi_range(8, 25)
	if randf() < 0.03:                                  # 血浓跃升
		var k: StringName = child.titers.keys().pick_random()
		child.titers[k] = mini(100, child.titers[k] + randi_range(15, 30))
	if randf() < 0.02:                                  # 退化 / 异血
		if randf() < 0.3:
			var ab := StringName("aberrant_" + str(AberrantDB.random_id()))
			child.defects.append(ab)
		else:
			var k2: StringName = child.titers.keys().pick_random()
			child.titers[k2] = maxi(1, child.titers[k2] - randi_range(10, 25))
```

```gdscript
# sim/genome.gd（续） — 嵌合判定与近交
func chimeras() -> Array[StringName]:
	var out: Array[StringName] = []
	var keys := titers.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var ka: StringName = keys[i]
			var kb: StringName = keys[j]
			var ta: int = titers[ka]
			var tb: int = titers[kb]
			if ta < TITER_LATENT or tb < TITER_LATENT: continue
			if absi(ta - tb) > CHIMERA_MAX_DIFF: continue
			var ca := BloodlineDB.clade_of(ka)
			var cb := BloodlineDB.clade_of(kb)
			if ca == cb: continue
			out.append(ChimeraDB.key_for(ca, cb))
	return out

func strong_bloodlines(threshold: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in titers:
		if titers[k] >= threshold: out.append(k)
	out.sort_custom(func(x, y): return titers[x] > titers[y])
	return out

static func _inbreeding(a: Genome, b: Genome) -> float:
	return clampf(0.5 * (a.inbreeding + b.inbreeding) + 0.5 * kinship(a, b), 0.0, 1.0)

static func kinship(a: Genome, b: Genome) -> float:
	# MVP 近似：共同祖先占比映射到 0..0.5。
	# 完整实现应改为 pedigree 路径计数（父子 0.5 / 半同胞 0.25 / 表亲 0.125）。
	var sa := {}
	for id in a.ancestors: sa[id] = true
	var inter := 0
	for id in b.ancestors:
		if sa.has(id): inter += 1
	var denom: int = mini(a.ancestors.size(), b.ancestors.size())
	if denom == 0: return 0.0
	return clampf(float(inter) / float(denom) * 0.5, 0.0, 0.5)
```

> ✅ **已实现**（不再是待办）：`sim/pedigree.gd` 用的是完整的 Wright 亲缘系数递推
> ```
> φ(a,a) = 0.5 × (1 + F_a)
> φ(a,b) = 0.5 × (φ(父_a, b) + φ(母_a, b))      （a 取更年轻的一方）
> F_c    = φ(父_c, 母_c)
> ```
> 带记忆化，因此不会指数爆炸；谱系深度上限默认 40 代（超过按无血缘处理）。
> `tools/run_tests.gd` 会验证已知值：父女 0.25 / 全同胞 0.25 / 半同胞 0.125 / 表亲 0.0625 / 无血缘 0。
>
> `Tribe._choose_mate()` 里剩下的启发式（`chimera_score` 的软评分、`_future_chimera` 只采样 4 名潜在配偶）
> 是**对玩家行为的建模**，不是游戏规则——真实游戏里这些判断由玩家自己做。
> 详见 [10.6 模型的已知简化](10-遗传平衡实测.md)。

## 7.7 性能预算

| 项目 | 规模 | 说明 |
|---|---|---|
| 个体 | ≤ 60/部落，世界内 ≤ 6 部落 → 约 400 | 每个 `Genome` 只存一个 ≤6 项的 `Dictionary`，内存可忽略 |
| 节点 | 6 区 × 10 = 60 | 每季结算一次，不是每帧 |
| Tick 频率 | 日结算 1 次/2 秒 | 把个体工作分配**分批**到 4 个节拍，避免单帧尖峰 |
| 真正瓶颈 | **立绘部件组合渲染** | 见 [08](08-美术音频与开发路线图.md)：必须做部件图集 + 缓存 |
| UI | 兽人列表 60 项 | 用 `ItemList`/自绘而非 60 个 `Control` 场景；或虚拟滚动 |

`sim/` 层跑一个日 tick 的实测目标：**< 1 ms**。这几乎肯定能达到，因为它只是一堆整数运算。

## 7.8 存档

```gdscript
# game/save_manager.gd
const SAVE_VERSION := 1

func save_game(path: String) -> void:
	var payload := {
		"version": SAVE_VERSION,
		"created_at": Time.get_datetime_string_from_system(),
		"world": world_state.to_dict(),      # sim 层每个类都实现 to_dict/from_dict
		"chronicle": chronicle.to_array(),
		"mods": ModLoader.active_mod_ids(),
		"rng_seed": rng.seed,
	}
	var f := FileAccess.open_compressed(path, FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD)
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

func load_game(path: String) -> Error:
	...
	var v: int = payload.get("version", 0)
	if v < SAVE_VERSION:
		payload = SaveMigrations.migrate(payload, v, SAVE_VERSION)
	...
```

**要点**：
- **存 RNG 种子**。模拟经营游戏不存随机种子的存档，读档后行为会漂移，玩家会觉得"游戏在骗我"。
- **在 JSON 里存 `mods` 列表**。缺模组时给出明确警告，而不是静默损坏存档。
- 每个 `sim/` 类都实现 `to_dict()` / `from_dict()`，并且只序列化**数据字段**，不序列化缓存。

## 7.9 模组与本地化

### 模组

- 加载顺序：`res://data/` → `user://mods/*/data/`（后者按 id 覆盖或追加）
- id 命名空间：模组定义的 id 必须写成 `modname:bloodline_id`，避免与官方冲突
- 可模组化范围：血脉、类群嵌合、进化节点、魔法学派、区域、灾祸、事件卡、建筑
- **不做脚本模组**（GDScript 注入风险 + 版本脆弱）。数据模组已足够表达力——这是刻意的取舍

### 本地化

- 从第一天起就用 CSV + `tr()`，**绝不硬编码中文字符串**
- key 前缀规范：`BLOODLINE_*` / `TRAIT_*` / `CHIMERA_*` / `DISASTER_*` / `OMEN_*` / `CHRONICLE_*`
- **编年史生成必须模板化**，否则本地化会变成噩梦：

```json
{
  "chronicle_death_childbirth": {
    "zh_CN": "第{generation}代的「{name}」在{migration}途中死于产褥热，她的血浓 {titer} 的{bloodline}血脉没有传给任何人。",
    "en": "{name} of the {generation}th generation died of puerperal fever during {migration}. Her {bloodline} titer of {titer} passed to no one."
  }
}
```

## 7.10 测试策略

### 1. 遗传平衡模拟（最重要的一个）

```gdscript
# tools/balance_sim.gd —— 用 `godot --headless --script res://tools/balance_sim.gd` 运行
extends SceneTree

const GENERATIONS := 200
const POP_SIZE := 24
const TRIALS := 200

func _init() -> void:
	var closed_f: Array[float] = []
	var closed_bdi: Array[float] = []
	var open_f: Array[float] = []
	for trial in TRIALS:
		closed_f.append(_run(POP_SIZE, GENERATIONS, false).f)   # 封闭部落
		open_f.append(_run(POP_SIZE, GENERATIONS, true).f)      # 每代引入外来血脉
	print("封闭部落 F 中位数: ", closed_f.median())
	print("开放部落 F 中位数: ", open_f.median())
	# 期望：封闭组在 3-4 代内 F > 0.25；开放组长期稳定在 0.1 以下
	quit()
```

**必须验证的三条命题**：

| 命题 | 期望结果 | 若失败说明 |
|---|---|---|
| 封闭部落 3–4 代内 I 系数 > 0.25 | 必须成立 | 近交惩罚太轻，迁移压力不足 |
| 随机配对（不优化）的部落会自然灭绝或血脉稀薄 | 应成立 | 系统太宽容，玩家不需要思考 |
| 有意识规划配对的玩家能稳定跨 10 代 | 必须成立 | 系统太严苛，不可玩 |

这三条是**整个游戏可玩性的地基**。它们应该在 M0 纸面阶段就用手算/表格验证一次，M1 再用 `balance_sim.gd` 自动化。

### 2. 单元测试

`tools/run_tests.gd`，纯 GDScript 断言，不引入 GUT 依赖：

- 血浓阈值边界（34/35/59/60）
- 嵌合判定（差 15 通过，差 16 不通过；同血脉类群不通过）
- 纯化 +6 / 稀释 −3 的叠加顺序
- 返祖概率（10 万次采样，应落在 15% ± 1%）
- 条数上限裁剪保留高血浓
- 存档往返（`to_dict` → `from_dict` → 比较全字段）

### 3. 回归种子测试

固定 RNG 种子跑 50 代，把关键指标快照进 `tools/golden/`。任何改动导致快照变化都要人工 review——**这是防止"调平衡时不小心改坏了遗传"的唯一有效手段**。
