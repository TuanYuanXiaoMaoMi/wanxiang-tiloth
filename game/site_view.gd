extends Control
## 局部地图视图：把 SiteMap 画出来，并让每个兽人**看得见地走到自己被我指派的地方**。
##
## 这一层只负责表现，不改任何模拟数值 —— 但它是「安排某人过去某地」这件事的反馈：
## 玩家点一个工作点，选中的人就会开始往那边走；到了就开始干活，头顶转采集进度环。

const AGENT_RADIUS := 9.0
const WALK_LERP := 3.2          ## 每秒向目标位置逼近的比例（只是视觉，不影响产出）
const SITE_RADIUS := 26.0

const KIND_COLOR := {
	SiteMap.Kind.GATHER: Color(0.42, 0.68, 0.36),
	SiteMap.Kind.HUNT: Color(0.72, 0.44, 0.28),
	SiteMap.Kind.WOOD: Color(0.45, 0.55, 0.32),
	SiteMap.Kind.STONE: Color(0.52, 0.52, 0.56),
	SiteMap.Kind.CRYSTAL: Color(0.58, 0.42, 0.78),
	SiteMap.Kind.HERB: Color(0.40, 0.66, 0.58),
	SiteMap.Kind.CAMP: Color(0.78, 0.68, 0.38),
	SiteMap.Kind.REST: Color(0.72, 0.50, 0.60),
	SiteMap.Kind.ALTAR: Color(0.62, 0.58, 0.80),
}

var world: WorldState = null
var selected_site: int = -1
var selected_beasts: Array = []      ## 成员列表里勾选的人（用于「派到这里」）
var show_labels := true
## 由 main.gd 注入的全局 UI 缩放。字号阈值要按**屏幕像素**判，不能按画布单位。
var ui_scale: float = 1.0

var _visual: Dictionary = {}         ## beast_id -> Vector2 当前像素位置
var _time := 0.0
var _hover_site: int = -1

signal site_clicked(site_id: int)
signal turn_animation_finished

# --- 回合结算动画：出发 → 干活 → 返回 ---
const ANIM_TRAVEL := 0.85
const ANIM_WORK := 1.30
var skip_animation: bool = false     ## 无头自检用：跳过动画，直接结算
var _anim: int = 0        ## 0 空闲 / 1 出发 / 2 干活 / 3 返回
var _anim_t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_world(w: WorldState) -> void:
	world = w
	_visual.clear()
	selected_site = -1
	if world != null and world.site_map != null:
		for id in world.tribe.beasts:
			_visual[id] = world.site_map.camp_pos
	queue_redraw()


## 播放一个回合的结算动画。走完会发 turn_animation_finished。
func play_turn() -> void:
	if _anim != 0:
		return
	if skip_animation:
		# 无头自检：每个回合 3 秒动画会让 32 回合的自检跑 100 秒，直接跳过
		turn_animation_finished.emit.call_deferred()
		return
	_anim = 1
	_anim_t = 0.0


func is_animating() -> bool:
	return _anim != 0


func _process(delta: float) -> void:
	_time += delta
	if world == null or world.site_map == null:
		return
	if _anim != 0:
		_anim_t += delta
		var span := ANIM_TRAVEL if _anim != 2 else ANIM_WORK
		if _anim_t >= span:
			_anim_t = 0.0
			_anim += 1
			if _anim > 3:
				_anim = 0
				turn_animation_finished.emit()
	# 视觉插值：朝自己被指派的工作点走
	for id in world.tribe.beasts:
		if not _visual.has(id):
			_visual[id] = world.site_map.camp_pos
		var b: Beast = world.tribe.beasts[id]
		var target: Vector2 = _target_of(b)
		_visual[id] = (_visual[id] as Vector2).lerp(target, clampf(delta * WALK_LERP, 0.0, 1.0))
		b.visual_pos = _visual[id]
		# 活动状态：还没走到就是「赶路」，到了就是「干活」
		if b.site_id < 0:
			b.activity = Beast.Activity.IDLE
		elif (_visual[id] as Vector2).distance_to(target) > 12.0:
			b.activity = Beast.Activity.WALKING
		else:
			b.activity = (Beast.Activity.RESTING
				if int(world.site_map.site(b.site_id)["kind"]) == SiteMap.Kind.REST
				else Beast.Activity.WORKING)
	# 清掉已死的人
	for id in _visual.keys():
		if not world.tribe.beasts.has(id):
			_visual.erase(id)
	queue_redraw()


func _target_of(b: Beast) -> Vector2:
	# 回合结算的「返回」阶段：所有人先回营地
	if _anim == 3:
		return world.site_map.camp_pos
	if b.site_id < 0:
		return world.site_map.camp_pos
	var s := world.site_map.site(b.site_id)
	if s.is_empty():
		return world.site_map.camp_pos
	# 同名工作点上的人稍微散开，不然会叠成一个点
	var n: int = maxi((s["workers"] as Array).size(), 1)
	var i: int = (s["workers"] as Array).find(b.id)
	var ang := TAU * float(i) / float(n)
	return (s["pos"] as Vector2) + Vector2(cos(ang), sin(ang)) * (SITE_RADIUS + 8.0)


# --------------------------------------------------------------------------
# 绘制
# --------------------------------------------------------------------------

func _draw() -> void:
	if world == null or world.site_map == null:
		return
	var m := world.site_map
	var font := get_theme_default_font()
	var fs := 14

	# 自适应：把 1280×700 的地图缩放进这个控件
	var sc := minf(size.x / m.WIDTH, size.y / m.HEIGHT)
	var sc_size := sc * ui_scale
	if sc <= 0.0:
		return
	draw_set_transform(Vector2((size.x - m.WIDTH * sc) * 0.5, (size.y - m.HEIGHT * sc) * 0.5),
		0.0, Vector2(sc, sc))
	draw_rect(Rect2(Vector2.ZERO, Vector2(m.WIDTH, m.HEIGHT)), Color(0.10, 0.12, 0.11), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(m.WIDTH, m.HEIGHT)), Color(0.22, 0.26, 0.24), false, 2.0)

	# 工作点
	for s in m.sites:
		var kind := int(s["kind"])
		var pos: Vector2 = s["pos"]
		var col: Color = KIND_COLOR.get(kind, Color.GRAY)
		var occupied := (s["workers"] as Array).size()
		var slots := int(s["slots"])
		var is_sel := int(s["id"]) == selected_site

		# 距离惩罚可视化：越远点越暗
		col = col.darkened((1.0 - m.efficiency(s)) * 0.9)
		draw_circle(pos, SITE_RADIUS, col)
		draw_arc(pos, SITE_RADIUS, 0.0, TAU, 32, Color(0.05, 0.06, 0.06), 2.0)
		if is_sel:
			draw_arc(pos, SITE_RADIUS + 5.0, 0.0, TAU, 40, Color(0.95, 0.85, 0.45), 3.0)
		elif int(s["id"]) == _hover_site:
			draw_arc(pos, SITE_RADIUS + 4.0, 0.0, TAU, 40, Color(0.8, 0.8, 0.8, 0.5), 2.0)

		# 名额占用：外圈画小格
		for i in slots:
			var a := -PI * 0.5 + TAU * float(i) / float(maxi(slots, 1))
			var p := pos + Vector2(cos(a), sin(a)) * (SITE_RADIUS + 11.0)
			draw_circle(p, 3.0, Color(0.9, 0.9, 0.9) if i < occupied else Color(0.3, 0.32, 0.3))

		if show_labels and SITE_RADIUS * sc_size > 20.0:
			var label := "%s %d/%d" % [m.kind_name(kind), occupied, slots]
			draw_string(font, pos + Vector2(-SITE_RADIUS - 6, -SITE_RADIUS - 6), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.86, 0.90, 0.86))

	# 兽人
	for id in world.tribe.beasts:
		var b: Beast = world.tribe.beasts[id]
		var p: Vector2 = _visual.get(id, m.camp_pos)
		var body := Color(0.85, 0.85, 0.88) if b.is_male() else Color(0.92, 0.80, 0.84)
		# 血浓最高的血脉给个色相，玩家扫一眼就知道谁是猫系谁是羽系
		var top := b.genome.top_bloodline()
		var clade := BloodlineDB.clade_of(top)
		body = body.lerp(_clade_color(clade), 0.55)

		draw_circle(p, AGENT_RADIUS, body)
		draw_arc(p, AGENT_RADIUS, 0.0, TAU, 20, Color(0.08, 0.09, 0.09), 1.5)

		# 回合结算时强制显示"在干活"，让玩家看到这一回合的产出从哪来
		if _anim == 2 and b.site_id >= 0:
			var tt := fmod(_time * 2.2, 1.0)
			draw_arc(p, AGENT_RADIUS + 6.0, -PI * 0.5, -PI * 0.5 + TAU * tt, 24,
				Color(0.98, 0.90, 0.50), 3.0)
			draw_line(p, _target_of(b), Color(0.9, 0.85, 0.5, 0.45), 1.5)
			continue

		# 采集动画：干活的头顶转一圈进度环
		match b.activity:
			Beast.Activity.WORKING:
				var t := fmod(_time * 0.9, 1.0)
				draw_arc(p, AGENT_RADIUS + 6.0, -PI * 0.5, -PI * 0.5 + TAU * t, 24,
					Color(0.95, 0.86, 0.45), 2.5)
			Beast.Activity.RESTING:
				var pulse := 0.5 + 0.5 * sin(_time * 2.4)
				draw_arc(p, AGENT_RADIUS + 7.0, 0.0, TAU, 24,
					Color(0.95, 0.55, 0.65, 0.4 + 0.5 * pulse), 2.5)
			Beast.Activity.WALKING:
				draw_line(p, _target_of(b), Color(0.6, 0.6, 0.6, 0.25), 1.0)

		if b.pregnant:
			draw_circle(p + Vector2(0, -AGENT_RADIUS - 9), 3.5, Color(0.95, 0.75, 0.45))


func _clade_color(clade: StringName) -> Color:
	match String(clade):
		"shadow": return Color(0.55, 0.45, 0.72)
		"pack": return Color(0.72, 0.55, 0.35)
		"swift": return Color(0.62, 0.72, 0.45)
		"horn": return Color(0.55, 0.62, 0.40)
		"feather": return Color(0.45, 0.62, 0.78)
		"scale": return Color(0.45, 0.70, 0.55)
		"heavy": return Color(0.68, 0.48, 0.38)
	return Color(0.7, 0.7, 0.7)


# --------------------------------------------------------------------------
# 交互
# --------------------------------------------------------------------------

## 屏幕坐标 → 地图坐标（要考虑 _draw 里的缩放与居中偏移）
func _to_map(p: Vector2) -> Vector2:
	if world == null or world.site_map == null:
		return p
	var m := world.site_map
	var sc := minf(size.x / m.WIDTH, size.y / m.HEIGHT)
	var sc_size := sc * ui_scale
	if sc <= 0.0:
		return p
	var off := Vector2((size.x - m.WIDTH * sc) * 0.5, (size.y - m.HEIGHT * sc) * 0.5)
	return (p - off) / sc


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _site_at(_to_map(event.position))
		if h != _hover_site:
			_hover_site = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _site_at(_to_map(event.position))
		if hit >= 0:
			selected_site = hit
			site_clicked.emit(hit)
			queue_redraw()


func _site_at(p: Vector2) -> int:
	if world == null or world.site_map == null:
		return -1
	for s in world.site_map.sites:
		if (s["pos"] as Vector2).distance_to(p) <= SITE_RADIUS + 6.0:
			return int(s["id"])
	return -1
