extends Control
## 六边形大陆地图。
##
## 玩家在这里看到的每一格都是可以扎营的地方：颜色是生态，数字是承载力，
## 金环是部落现在的位置，带虚线框的是**今天就能走到的邻格**。
## 点一格看详情；如果它是邻格，就能直接迁过去。

const PAD := 14.0

## 生态配色。越冷的色越贫瘠，越暖的色越丰饶；紫色系=高魔素。
const BIOME_COLOR := {
	"temperate_forest": Color(0.36, 0.55, 0.32),
	"old_growth_forest": Color(0.24, 0.44, 0.26),
	"conifer_forest": Color(0.28, 0.42, 0.34),
	"tundra": Color(0.62, 0.68, 0.72),
	"coast": Color(0.32, 0.52, 0.62),
	"salt_marsh": Color(0.42, 0.52, 0.44),
	"river_ford": Color(0.38, 0.53, 0.48),
	"mana_waste": Color(0.48, 0.34, 0.62),
	"scorched_flat": Color(0.52, 0.38, 0.30),
	"ash_plain": Color(0.44, 0.42, 0.40),
	"bone_field": Color(0.64, 0.62, 0.52),
	"great_rift": Color(0.46, 0.36, 0.50),
	"underground_river": Color(0.30, 0.40, 0.58),
	"coastal_town": Color(0.56, 0.50, 0.34),
}

const FACTION_COLOR := {
	"iron_fang": Color(0.75, 0.35, 0.30),
	"nine_tails": Color(0.85, 0.70, 0.30),
	"feather_burial": Color(0.55, 0.50, 0.75),
	"forest_mother": Color(0.40, 0.70, 0.45),
	"lizard_swamp": Color(0.45, 0.70, 0.55),
	"dune_dynasty": Color(0.80, 0.60, 0.35),
}

## 空值安全的字符串转换。
## 注意：生成出来的节点里 `"owner": null` 是**存在的 null**，
## 所以 `d.get("owner", "")` 会返回 null 而不是 "" —— 默认值根本不会生效。
static func _s(v: Variant) -> String:
	return "" if v == null else str(v)


var world: WorldState = null
var world_data: Dictionary = {}
var current_node: StringName = &""
var selected_node: StringName = &""
var _hover_node: StringName = &""
var _reachable: Dictionary = {}          ## 邻格 -> 天数

# --- 视野：缩放与平移 ---
## 只用「适应窗口」会把近似正方形的大陆压进又宽又扁的面板里，六边形小得看不清。
## 所以要能自己放大看。
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _sc: float = 1.0
var _off: Vector2 = Vector2.ZERO
var _dragging: bool = false
var ui_scale: float = 1.0    ## 由 main.gd 注入；阈值要按屏幕像素判，而不是画布单位
const ZOOM_MIN := 1.0
const ZOOM_MAX := 6.0

signal node_clicked(node_id: StringName)


func set_world(w: WorldState, data: Dictionary) -> void:
	world = w
	world_data = data
	current_node = RegionDB.start_node()
	selected_node = &""
	_hover_node = &""
	_refresh_reachable()
	queue_redraw()


func set_current(node_id: StringName) -> void:
	current_node = node_id
	selected_node = &""
	_refresh_reachable()
	queue_redraw()


func _refresh_reachable() -> void:
	_reachable = RegionDB.reachable_within(current_node, 1)


func _process(_delta: float) -> void:
	queue_redraw()


# --------------------------------------------------------------------------
# 绘制
# --------------------------------------------------------------------------

func _bounds() -> Array:
	var size_h := RegionDB.hex_size()
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for nid in world_data.get("positions", {}):
		var p: Vector2 = world_data["positions"][nid]
		minp.x = minf(minp.x, p.x - size_h); minp.y = minf(minp.y, p.y - size_h)
		maxp.x = maxf(maxp.x, p.x + size_h); maxp.y = maxf(maxp.y, p.y + size_h)
	if minp.x > maxp.x:
		return [Vector2.ZERO, Vector2.ONE]
	return [minp, maxp - minp]


## 刷新当前变换：基准缩放（适应窗口）× 用户的缩放，再加平移。
func _update_transform() -> void:
	var b := _bounds()
	var minp: Vector2 = b[0]
	var span: Vector2 = b[1]
	if span.x <= 0.0 or span.y <= 0.0 or size.x <= 1.0 or size.y <= 1.0:
		return
	var base := minf((size.x - PAD * 2.0) / span.x, (size.y - PAD * 2.0) / span.y)
	_sc = base * _zoom
	_off = (size - span * _sc) * 0.5 - minp * _sc + _pan


func _to_screen(p: Vector2) -> Vector2:
	return p * _sc + _off


func _to_map(p: Vector2) -> Vector2:
	return (p - _off) / maxf(_sc, 0.0001)


func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()


## 以光标为中心缩放：保证光标下的那一点不动。
func _zoom_at(cursor: Vector2, factor: float) -> void:
	var before := _to_map(cursor)
	var old := _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old, _zoom):
		return
	var b := _bounds()
	var minp: Vector2 = b[0]
	var span: Vector2 = b[1]
	var base := minf((size.x - PAD * 2.0) / span.x, (size.y - PAD * 2.0) / span.y)
	var sc2 := base * _zoom
	var ct := (size - span * sc2) * 0.5 - minp * sc2
	_pan = cursor - before * sc2 - ct
	queue_redraw()


func _hex_at_screen(p: Vector2) -> StringName:
	_update_transform()
	var mp := _to_map(p)
	var h := Hex.from_pixel(mp, RegionDB.hex_size())
	var nid := StringName("h_%d_%d" % [h.x, h.y])
	return nid if world_data.get("positions", {}).has(_s(nid)) else &""


## 当前缩放下一个格子的屏幕尺寸（供各级字号阈值判断）。
func screen_hsize_of_all(sc: float) -> float:
	return RegionDB.hex_size() * sc * ui_scale


func _draw() -> void:
	if world_data.is_empty():
		return
	_update_transform()
	var font := get_theme_default_font()
	var sc := _sc
	var hsize := RegionDB.hex_size() * sc

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.09), true)
	if _zoom > 1.02:
		draw_string(font, Vector2(10, size.y - 12), "缩放 %.1f×　（滚轮缩放 · 右键拖动平移 · 双击复位）" % _zoom,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.75, 0.8))

	for nid in world_data.get("positions", {}):
		var key := StringName(nid)
		var pos := _to_screen(world_data["positions"][nid])
		var d: Dictionary = RegionDB.node_data(key)
		if d.is_empty():
			continue
		var biome := _s(d.get("biome", ""))
		var col: Color = BIOME_COLOR.get(biome, Color(0.35, 0.35, 0.35))
		# 危险度 → 变暗
		col = col.darkened(clampf(float(d.get("danger", 1)) / 8.0, 0.0, 0.35))
		# 魔素浓度 → 往紫色偏
		col = col.lerp(Color(0.55, 0.35, 0.75), float(d.get("magic_density", 0.3)) * 0.30)

		var pts := Hex.corners(pos, hsize)
		var fill := col
		if key == current_node:
			fill = col.lerp(Color(0.95, 0.85, 0.45), 0.35)
		draw_colored_polygon(pts, fill)

		# 边界：有主 → 势力色；可达邻格 → 金色虚线感（用亮边代替）
		var border := Color(0.08, 0.09, 0.10)
		var bw := 1.5
		if key == current_node:
			border = Color(0.98, 0.86, 0.40); bw = 3.5
		elif key == selected_node:
			border = Color(0.95, 0.95, 0.95); bw = 3.0
		elif key == _hover_node:
			border = Color(0.85, 0.85, 0.85, 0.8); bw = 2.5
		elif _reachable.has(key):
			border = Color(0.85, 0.78, 0.45, 0.9); bw = 2.5
		elif _s(d.get("owner", "")) != "":
			border = FACTION_COLOR.get(_s(d.get("owner", "")), Color.GRAY); bw = 2.5
		draw_polyline(pts + PackedVector2Array([pts[0]]), border, bw)

		# 阈值按**屏幕像素**判：content_scale_factor 会把画布整体放大，
		# 用画布单位判会让 UI 放大之后格子名反而消失（踩过）。
		var screen_hsize := hsize * ui_scale

		# 承载力数字
		if screen_hsize > 16.0:
			var cap := WorldGen.capacity_of(d)
			var label := "%.0f" % cap
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, pos + Vector2(-w * 0.5, 5), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.06, 0.07, 0.07, 0.78))
			# 名字只在格够大时画
			if screen_hsize > 34.0:
				var nm := _s(d.get("name", ""))
				var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				draw_string(font, pos + Vector2(-nw * 0.5, -7), nm,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.96, 0.97, 0.95, 0.95))

		# 部落所在地：画一个小营地图标
		if key == current_node:
			draw_circle(pos + Vector2(0, hsize * 0.42), maxf(hsize * 0.13, 3.0),
				Color(0.98, 0.90, 0.55))
			draw_arc(pos + Vector2(0, hsize * 0.42), maxf(hsize * 0.13, 3.0),
				0.0, TAU, 16, Color(0.15, 0.12, 0.05), 1.5)

	# 区域名
	if screen_hsize_of_all(sc) > 14.0:
		for rid in world_data.get("region_centers", {}):
			var c := _to_screen(world_data["region_centers"][rid])
			var rn := RegionDB.region_name(StringName(rid))
			var w2 := font.get_string_size(rn, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(font, c + Vector2(-w2 * 0.5, 0), rn,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.22))


# --------------------------------------------------------------------------
# 交互
# --------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			queue_redraw()
			return
		var h := _hex_at_screen(event.position)
		if h != _hover_node:
			_hover_node = h
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click:
				reset_view()
				return
			var hit := _hex_at_screen(mb.position)
			if hit != &"":
				selected_node = hit
				node_clicked.emit(hit)
				queue_redraw()


## 供外部（main.gd）查询：这一格能不能迁过去。
func travel_days_to(node_id: StringName) -> int:
	if node_id == &"" or node_id == current_node:
		return 0
	return RegionDB.travel_days(current_node, node_id)


func hovered_node() -> StringName:
	return _hover_node


func describe(node_id: StringName) -> String:
	if node_id == &"":
		return ""
	var d := RegionDB.node_data(node_id)
	if d.is_empty():
		return ""
	var biome := WorldGen.biome(_s(d.get("biome", "")))
	var cap := WorldGen.capacity_of(d)
	var days := travel_days_to(node_id)
	var t := "[b]%s[/b]　%s（%s）\n" % [
		_s(d.get("name", "?")), _s(biome.get("name", d.get("biome", "?"))),
		RegionDB.region_name(RegionDB.region_of_node(node_id))]
	t += "承载力 [b]%.1f[/b] 人　危险 %d　魔素 %.2f\n" % [
		cap, int(d.get("danger", 0)), float(d.get("magic_density", 0.0))]
	t += "木 %.0f　石 %.0f　魔晶 %.0f　药草 %.0f\n" % [
		float(d.get("wood", 0)), float(d.get("stone", 0)),
		float(d.get("crystal", 0)), float(d.get("herb", 0))]
	var owner := _s(d.get("owner", ""))
	if owner != "":
		t += "[color=#e0a05a]已被势力占据：%s[/color]\n" % owner
	if days <= 0:
		t += "[color=#e0d05a]部落现在就在这里。[/color]"
	elif days == 1:
		t += "[color=#8fd18a]邻格，随时可以迁过去（1 天路程）。[/color]"
	else:
		t += "[color=#8a9490]%d 天路程，需要先迁到更近的格子。[/color]" % days
	return t
