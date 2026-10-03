extends Control
## 《万相缇洛斯》M1 垂直切片主界面。
##
## 这一版只做一件事：验证**玩家会不会在 20-30 分钟内自己意识到「我得搬走了」**。
## 所以界面上只有三块：脚下的土地（资源曲线）、部落的人（血脉与谱系）、以及迁徙按钮。
##
##   ./tools/godot.sh                      跑游戏
##   ./tools/godot.sh --headless -- --self-test   无头自检（构建界面 + 跑 400 天）

const JOB := [&"gather", &"hunt", &"craft", &"rest"]

var world: WorldState
var _member_ids: Array = []
var _picker_ids: Array = []          # 下拉框里每一项对应的人（用于按 id 而非索引保持选择）
var _pick_a_id: int = -1
var _pick_b_id: int = -1
var _self_test := false
var rng_seed: int = 0
var _test_days := 0

# --- 界面引用 ---
var _date_label: Label
var _metrics_label: Label
var _end_turn_button: Button
var _transit_label: Label
var _resolving := false
var _member_tree: Tree
var _parent_a: OptionButton
var _parent_b: OptionButton
var _planner_text: RichTextLabel
var _region_text: RichTextLabel
var _hunt_slider: HSlider
var _hunt_label: Label
var _dest_picker: OptionButton
var _migrate_button: Button
var _descent_text: RichTextLabel
var _descent_pick: OptionButton
var _reform_btn: Button
var _descent_choices: Array = []
var _load_btn: Button

## 存档位置。用 user:// 而不是 res:// —— 打包后 res:// 是只读的。
const SAVE_PATH := "user://wanxiang_save.dat"
var _knowledge_tree: Tree
var _knowledge_detail: RichTextLabel
var _adopt_btn: Button
var _log_text: RichTextLabel
var _site_view: Control
var _continent_view: Control
var _continent_info: RichTextLabel
var _continent: Dictionary = {}
var _pending_dest: StringName = &""
var _tabs: TabContainer
var _fullscreen_button: Button
var _fullscreen_map := false
var ui_scale: float = 1.25          ## 全局 UI 缩放（字体、间距、地图一起放大）
var _left_col: VBoxContainer
var _center_col: VBoxContainer
var _right_col: VBoxContainer
var _bottom_box: VBoxContainer
var _center_extra: VBoxContainer
var _site_info: RichTextLabel
var _crew_label: Label
var _faith_label: Label
var _hunt_bias_slider: HSlider


func _ready() -> void:
	_self_test = OS.get_cmdline_user_args().has("--self-test")
	_apply_ui_scale(ui_scale)
	_apply_cjk_font()
	_build_ui()
	_new_game()
	if _self_test:
		_run_self_test()
	elif OS.get_cmdline_user_args().has("--screenshot"):
		_run_screenshot(17, false)    # 第 17 回合：压力接近 1.0，土地开始明显下滑
	elif OS.get_cmdline_user_args().has("--screenshot-full"):
		_run_screenshot(17, true)     # 全屏大陆图
	elif OS.get_cmdline_user_args().has("--screenshot-lineage"):
		_run_screenshot(17, false, 2) # 谱系页
	elif OS.get_cmdline_user_args().has("--screenshot-knowledge"):
		_run_screenshot(17, false, 3) # 知识页


# ==========================================================================
# 界面构建
# ==========================================================================

## 全局 UI 缩放。
## 逐个去改字号会漏（而且以后每加一个控件都要记得放大），
## 用 content_scale_factor 一次性把整个界面放大，地图视图也会跟着变大。
func _apply_ui_scale(f: float) -> void:
	ui_scale = clampf(f, 0.8, 2.2)
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_factor = ui_scale
	if _site_view != null:
		_site_view.ui_scale = ui_scale
	if _continent_view != null:
		_continent_view.ui_scale = ui_scale


func _bump_ui_scale(delta: float) -> void:
	_apply_ui_scale(ui_scale + delta)


## Godot 内置字体不含中文字形，直接用系统字体，免去打包字体文件。
func _apply_cjk_font() -> void:
	var t := Theme.new()
	t.default_font = UIFont.build()
	t.default_font_size = 14
	theme = t


func _mk_label(text: String, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _mk_rich(expand: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	if expand:
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# ---------- 顶栏 ----------
	# HFlowContainer：UI 放大之后顶栏会放不下，让它自己换行，不要挤到出界
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 10)
	top.add_theme_constant_override("v_separation", 4)
	root.add_child(top)

	_date_label = _mk_label("", 16)
	top.add_child(_date_label)

	top.add_child(VSeparator.new())
	_end_turn_button = Button.new()
	_end_turn_button.text = "结束回合 ▶"
	_end_turn_button.add_theme_font_size_override("font_size", 16)
	_end_turn_button.custom_minimum_size = Vector2(140, 34)
	_end_turn_button.pressed.connect(_on_end_turn)
	top.add_child(_end_turn_button)

	top.add_child(VSeparator.new())
	_fullscreen_button = Button.new()
	_fullscreen_button.text = "全屏地图 ⛶"
	_fullscreen_button.tooltip_text = "把地图铺满整个窗口（Esc 退出）"
	_fullscreen_button.pressed.connect(_toggle_fullscreen_map)
	top.add_child(_fullscreen_button)

	top.add_child(VSeparator.new())
	_metrics_label = _mk_label("", 14)
	_metrics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_metrics_label)

	var minus := Button.new()
	minus.text = "A−"
	minus.tooltip_text = "缩小界面"
	minus.pressed.connect(func(): _bump_ui_scale(-0.1))
	top.add_child(minus)
	var plus := Button.new()
	plus.text = "A+"
	plus.tooltip_text = "放大界面"
	plus.pressed.connect(func(): _bump_ui_scale(0.1))
	top.add_child(plus)

	var savebtn := Button.new()
	savebtn.text = "存档"
	savebtn.tooltip_text = "把这一局写到 %s" % SAVE_PATH
	savebtn.pressed.connect(_on_save_game)
	top.add_child(savebtn)

	_load_btn = Button.new()
	_load_btn.text = "读档"
	_load_btn.pressed.connect(_on_load_game)
	top.add_child(_load_btn)

	var newgame := Button.new()
	newgame.text = "重开"
	newgame.pressed.connect(_new_game)
	top.add_child(newgame)

	# ---------- 主区 ----------
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	# 左：部落成员
	_left_col = VBoxContainer.new()
	_left_col.custom_minimum_size = Vector2(310, 0)
	_left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_left_col)
	_left_col.add_child(_mk_label("部落成员", 15))
	# 用 Tree 而不是 ItemList：一行里要放「名 + 血脉 + 近交系数」，
	# 挤成一串文本根本读不出来，分列之后才能扫。
	_member_tree = Tree.new()
	_member_tree.columns = 3
	_member_tree.hide_root = true
	_member_tree.select_mode = Tree.SELECT_MULTI
	_member_tree.column_titles_visible = true
	# 第一层只放「身份 + 状态」：血脉属于要看细节时再查的东西，放第二层。
	_member_tree.set_column_title(0, "名字")
	_member_tree.set_column_title(1, "年龄")
	_member_tree.set_column_title(2, "近交")
	# 名字列用**最小宽度**而不是伸缩比例：比例太小时列宽放不下「♂ 碎影」，
	# Tree 会整格不渲染，看起来像名字全丢了。固定最小宽度才可靠。
	_member_tree.set_column_expand(0, true)
	_member_tree.set_column_custom_minimum_width(0, 132)
	_member_tree.set_column_expand(1, false)
	_member_tree.set_column_custom_minimum_width(1, 56)
	_member_tree.set_column_expand(2, false)
	_member_tree.set_column_custom_minimum_width(2, 52)
	_member_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_member_tree.custom_minimum_size = Vector2(0, 250)
	_member_tree.item_selected.connect(_on_member_selection_changed)
	_member_tree.multi_selected.connect(func(_i, _c, _sel): _on_member_selection_changed())
	_left_col.add_child(_member_tree)

	# 编年史放在左栏底部：它和成员列表同属「部落状态」，而且这样纵向空间全留给地图
	_bottom_box = VBoxContainer.new()
	_bottom_box.add_theme_constant_override("separation", 2)
	_left_col.add_child(_bottom_box)
	_bottom_box.add_child(_mk_label("编年史", 15))
	_log_text = _mk_rich(false)
	_log_text.custom_minimum_size = Vector2(0, 150)
	_bottom_box.add_child(_log_text)

	# 中：地图（占大头，可全屏）+ 谱系规划器
	_center_col = VBoxContainer.new()
	_center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_col.size_flags_stretch_ratio = 2.6
	main.add_child(_center_col)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 420)
	_tabs.add_theme_font_size_override("font_size", 14)
	_center_col.add_child(_tabs)

	_site_view = load("res://game/site_view.gd").new()
	_site_view.name = "营地"
	_site_view.site_clicked.connect(_on_site_clicked)
	_tabs.add_child(_site_view)

	_continent_view = load("res://game/continent_view.gd").new()
	_continent_view.name = "大陆"
	_continent_view.node_clicked.connect(_on_continent_clicked)
	_tabs.add_child(_continent_view)

	# 地图下方的所有控件（全屏时整块收起）
	_center_extra = VBoxContainer.new()
	_center_extra.add_theme_constant_override("separation", 5)
	_center_col.add_child(_center_extra)

	# 「谱系」标签页：规划器内容很长（最多 6 条血脉 + 嵌合 + 近交 + 突变），
	# 挤在纵向会让底部的信息被顶出屏幕。单独开一页，配对的时候本来也不需要看地图。
	var planner_panel := VBoxContainer.new()
	planner_panel.name = "谱系"
	planner_panel.add_theme_constant_override("separation", 6)
	_tabs.add_child(planner_panel)

	var picks := HBoxContainer.new()
	picks.add_theme_constant_override("separation", 8)
	planner_panel.add_child(picks)
	picks.add_child(_mk_label("一方"))
	_parent_a = OptionButton.new()
	_parent_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parent_a.item_selected.connect(func(_i): _refresh_planner())
	picks.add_child(_parent_a)
	picks.add_child(_mk_label("另一方"))
	_parent_b = OptionButton.new()
	_parent_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parent_b.item_selected.connect(func(_i): _refresh_planner())
	picks.add_child(_parent_b)

	_planner_text = _mk_rich()
	planner_panel.add_child(_planner_text)

	# ---------- 知识标签页 ----------
	var know_panel := VBoxContainer.new()
	know_panel.name = "知识"
	know_panel.add_theme_constant_override("separation", 6)
	_tabs.add_child(know_panel)

	_knowledge_tree = Tree.new()
	_knowledge_tree.columns = 3
	_knowledge_tree.hide_root = true
	_knowledge_tree.select_mode = Tree.SELECT_ROW
	_knowledge_tree.column_titles_visible = true
	_knowledge_tree.set_column_title(0, "知识")
	_knowledge_tree.set_column_title(1, "状态")
	_knowledge_tree.set_column_title(2, "信仰")
	_knowledge_tree.set_column_expand(0, true)
	_knowledge_tree.set_column_expand(1, false)
	_knowledge_tree.set_column_custom_minimum_width(1, 76)
	_knowledge_tree.set_column_expand(2, false)
	_knowledge_tree.set_column_custom_minimum_width(2, 52)
	_knowledge_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_knowledge_tree.item_selected.connect(_on_knowledge_selected)
	know_panel.add_child(_knowledge_tree)

	_knowledge_detail = _mk_rich(false)
	_knowledge_detail.scroll_active = false
	_knowledge_detail.fit_content = true
	_knowledge_detail.custom_minimum_size = Vector2(0, 132)
	know_panel.add_child(_knowledge_detail)

	_adopt_btn = Button.new()
	_adopt_btn.text = "采纳"
	_adopt_btn.pressed.connect(_on_adopt)
	know_panel.add_child(_adopt_btn)

	_continent_info = _mk_rich(false)
	_continent_info.fit_content = true
	_continent_info.scroll_active = false
	_continent_info.custom_minimum_size = Vector2(0, 70)
	_center_extra.add_child(_continent_info)

	_transit_label = _mk_label("", 14)
	_transit_label.visible = false
	_center_extra.add_child(_transit_label)

	_crew_label = _mk_label("在地图上点一个工作点，再在左边选人，就能把人派过去。", 13)
	_center_extra.add_child(_crew_label)

	var site_row := HBoxContainer.new()
	site_row.add_theme_constant_override("separation", 8)
	_center_extra.add_child(site_row)
	var assign_btn := Button.new()
	assign_btn.text = "把选中的人派到这个工作点"
	assign_btn.pressed.connect(_on_assign_selected)
	site_row.add_child(assign_btn)
	var rest_btn := Button.new()
	rest_btn.text = "派两人去休息所（提高配对率）"
	rest_btn.pressed.connect(_on_send_to_rest)
	site_row.add_child(rest_btn)
	var force_btn := Button.new()
	force_btn.text = "法术强制配对"
	force_btn.pressed.connect(_on_force_pair)
	site_row.add_child(force_btn)

	_site_info = _mk_rich(false)
	_site_info.fit_content = true
	_site_info.scroll_active = false
	_site_info.custom_minimum_size = Vector2(0, 38)
	_center_extra.add_child(_site_info)

	# 右：土地与迁徙
	_right_col = VBoxContainer.new()
	_right_col.custom_minimum_size = Vector2(295, 0)
	_right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_right_col)
	_right_col.add_child(_mk_label("脚下的土地", 15))

	_region_text = _mk_rich(false)
	_region_text.scroll_active = false
	_region_text.fit_content = true
	_region_text.custom_minimum_size = Vector2(0, 210)
	_right_col.add_child(_region_text)

	var hunt_row := HBoxContainer.new()
	hunt_row.add_theme_constant_override("separation", 8)
	_right_col.add_child(hunt_row)
	hunt_row.add_child(_mk_label("狩猎倾向"))
	_hunt_bias_slider = HSlider.new()
	_hunt_bias_slider.min_value = 0.4
	_hunt_bias_slider.max_value = 2.5
	_hunt_bias_slider.step = 0.1
	_hunt_bias_slider.value = 1.0
	_hunt_bias_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hunt_bias_slider.value_changed.connect(_on_hunt_bias_changed)
	hunt_row.add_child(_hunt_bias_slider)
	_hunt_label = _mk_label("1.0×（按可持续产量）")
	hunt_row.add_child(_hunt_label)

	_faith_label = _mk_label("")
	_right_col.add_child(_faith_label)

	_right_col.add_child(_mk_label("迁往（也可直接点大陆图）"))
	_dest_picker = OptionButton.new()
	_right_col.add_child(_dest_picker)

	_migrate_button = Button.new()
	_migrate_button.text = "迁徙（丢掉一切建筑）"
	_migrate_button.add_theme_font_size_override("font_size", 15)
	_migrate_button.pressed.connect(_on_migrate)
	_right_col.add_child(_migrate_button)

	# ---------- 继嗣制度 ----------
	_right_col.add_child(_mk_label("制度", 15))
	_descent_text = _mk_rich(false)
	_descent_text.scroll_active = false
	_descent_text.fit_content = true
	_descent_text.custom_minimum_size = Vector2(0, 96)
	_right_col.add_child(_descent_text)

	var reform_row := HBoxContainer.new()
	reform_row.add_theme_constant_override("separation", 6)
	_right_col.add_child(reform_row)
	_descent_pick = OptionButton.new()
	_descent_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_descent_pick.item_selected.connect(func(_i): _refresh_reform_button())
	reform_row.add_child(_descent_pick)
	_reform_btn = Button.new()
	_reform_btn.text = "改制"
	_reform_btn.pressed.connect(_on_reform)
	reform_row.add_child(_reform_btn)



## 全屏地图：把左右栏、底部日志、以及地图下方的控件全部收起，让地图铺满窗口。
## 这是解决「地图太小」的正解 —— 光靠调面板尺寸没用，因为大陆近似正方形，
## 而中间那一栏永远是又宽又扁的。
func _toggle_fullscreen_map() -> void:
	_fullscreen_map = not _fullscreen_map
	_left_col.visible = not _fullscreen_map
	_right_col.visible = not _fullscreen_map
	_bottom_box.visible = not _fullscreen_map
	_center_extra.visible = not _fullscreen_map
	_fullscreen_button.text = "退出全屏 ⛶" if _fullscreen_map else "全屏地图 ⛶"


func _unhandled_input(event: InputEvent) -> void:
	if _fullscreen_map and event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_toggle_fullscreen_map()

func _new_game() -> void:
	# 固定种子 = 可复现的一局。玩家能把这个数字报给别人，让对方看到同一个世界。
	rng_seed = int(Time.get_unix_time_from_system()) % 1000000
	Genome.seed_rng(rng_seed)
	# 肉鸽：每一局整片大陆从种子重新生成
	WorldGen.ensure_loaded()
	var continent := WorldGen.generate(rng_seed, 4)
	RegionDB.load_world(continent)
	_continent = continent
	world = WorldState.new()
	# 一家人：两对父母 + 8 名子女 = 12 人。见 docs/10 的实测修正。
	world.setup(RegionDB.start_node(), 12, true, 24, 2)
	world.hunt_bias = _hunt_bias_slider.value if _hunt_bias_slider != null else 1.0
	if _site_view != null:
		_site_view.ui_scale = ui_scale
		_site_view.set_world(world)
	if _continent_view != null:
		_continent_view.ui_scale = ui_scale
		_continent_view.set_world(world, continent)
	_pending_dest = &""
	_pick_a_id = -1
	_pick_b_id = -1
	_picker_ids.clear()
	_rebuild_members()
	_sync_parent_pickers()
	_rebuild_destinations()
	_refresh()


func _process(_delta: float) -> void:
	# 界面只在「结束回合」和交互时刷新。地图视图各自在 _process 里 queue_redraw，
	# 不需要这里每帧重建整个 UI —— 那既浪费，也会把陈旧数据的报错刷成满屏。
	pass


## 结束一个回合：先播结算动画（大家走出去干活、再回来），动画结束才真正推进 30 天。
## 顺序很重要 —— 动画展示的是「这一回合你派他们去干了什么」，不是已经发生过的结果。
func _on_end_turn() -> void:
	if world == null or world.extinct or _resolving:
		return
	_resolving = true
	_end_turn_button.disabled = true
	_end_turn_button.text = "结算中…"
	_site_view.play_turn()
	await _site_view.turn_animation_finished
	if world != null and not world.extinct:
		world.end_turn()
	_resolving = false
	_end_turn_button.disabled = false
	_end_turn_button.text = "结束回合 ▶"
	_pending_dest = &""
	_migrate_button.text = "迁徙（丢掉一切建筑）"
	_rebuild_members()
	_rebuild_destinations()
	if _continent_view != null:
		_continent_view.set_current(world.region.id)
	if _site_view != null:
		_site_view.ui_scale = ui_scale
		_site_view.set_world(world)
	_refresh()


# ==========================================================================
# 刷新
# ==========================================================================

func _rebuild_members() -> void:
	var keep_ids: Array = _selected_ids()
	_member_ids.clear()
	for id in world.tribe.beasts:
		_member_ids.append(id)
	# 劳动能力强的排前面
	_member_ids.sort_custom(func(a, b):
		return world.tribe.beasts[a].labor_capacity() > world.tribe.beasts[b].labor_capacity())

	_member_tree.clear()
	var root := _member_tree.create_item()

	# **按姓氏分组。** 这是款讲血脉的游戏，姓氏本来就该是组织方式：
	# 一眼就能看出「火苍氏有 4 个人」「砂骨氏只剩 1 个」。
	# 顺带解决了列宽问题 —— 子行只需要写名，不用重复姓氏。
	var groups: Dictionary = {}
	var order: Array = []
	for id in _member_ids:
		var sn := world.tribe.group_of(world.tribe.beasts[id])
		if not groups.has(sn):
			groups[sn] = []
			order.append(sn)
		(groups[sn] as Array).append(id)
	order.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size())

	for sn in order:
		var ids: Array = groups[sn]
		var head := _member_tree.create_item(root)
		head.set_text(0, "%s（%d）" % [sn if sn != "" else "无姓", ids.size()])
		head.set_text(1, "氏族")
		head.set_text(2, "")
		head.set_custom_color(0, Color(0.96, 0.87, 0.56))
		head.set_selectable(0, false)
		head.set_selectable(1, false)
		head.set_selectable(2, false)
		head.set_tooltip_text(0, "%s氏 · %d 人" % [sn if sn != "" else "无姓", ids.size()])

		for id in ids:
			var b: Beast = world.tribe.beasts[id]
			var g: Genome = b.genome
			var item := _member_tree.create_item(head)
			var mark := ""
			if not g.chimeras().is_empty():
				mark += "★"
			if not g.defects.is_empty():
				mark += "⚠"
			if b.pregnant:
				mark += "孕"
			item.set_text(0, "%s %s%s" % ["♂" if b.is_male() else "♀", b.name,
				("  " + mark) if mark != "" else ""])
			# 年龄按人生阶段上色：幼崽 / 壮年 / 老年 / 风烛残年。
			# 年龄决定劳动能力、能不能生育、以及大概什么时候会死，必须一直看得见。
			item.set_text(1, "%.0f" % b.age)
			item.set_custom_color(1, _age_color(b))
			item.set_text(2, "%.2f" % g.inbreeding)
			item.set_metadata(0, id)
			item.set_metadata(1, sn)

			var tips: Array = ["%s·%s" % [sn, b.name] if sn != "" else b.name]
			tips.append("年龄 %.0f / 寿命 %.0f　劳动 %.0f%%" % [
				b.age, b.lifespan, b.labor_capacity() * 100.0])
			if not g.chimeras().is_empty():
				var cn: Array = []
				for c in g.chimeras():
					cn.append(BloodlineDB.chimera_name(c))
				tips.append("嵌合：" + "、".join(cn))
			if not g.defects.is_empty():
				tips.append("缺陷：" + _defects(b))
			if b.pregnant:
				tips.append("怀孕中")
			if b.father >= 0:
				tips.append("父 %d　母 %d" % [b.father, b.mother])
			item.set_tooltip_text(0, "\n".join(tips))
			item.set_tooltip_text(1, "%.0f 岁 / 寿命 %.0f　剩余约 %.0f 年" % [
				b.age, b.lifespan, maxf(0.0, b.lifespan - b.age)])
			item.set_tooltip_text(2, "近交系数 %.3f" % g.inbreeding)
			if keep_ids.has(id):
				item.select(0)


## 自检/截图用：选中成员列表里最先出现的 n 个人。
func _select_first_members(n: int) -> void:
	var root := _member_tree.get_root()
	if root == null:
		return
	var picked := 0
	var group := root.get_first_child()
	while group != null and picked < n:
		var it := group.get_first_child()
		while it != null and picked < n:
			it.select(0)
			picked += 1
			it = it.get_next()
		group = group.get_next()
	_on_member_selection_changed()


func _selected_ids() -> Array:
	var out: Array = []
	if _member_tree == null:
		return out
	var it := _member_tree.get_next_selected(null)
	while it != null:
		var v: Variant = it.get_metadata(0)
		if v != null:
			out.append(int(v))
		it = _member_tree.get_next_selected(it)
	return out


## 一句话说明这个人现在处在人生哪个阶段。
func _age_word(b: Beast) -> String:
	var a := b.effective_age()
	if a < Tribe.MATURITY_AGE:
		return "未成年"
	if a > b.lifespan * 0.85:
		return "风烛残年"
	if a > 45.0:
		return "老年"
	return "壮年"


## 年龄配色。用的是 effective_age()，所以「早衰」缺陷的人会显示得更老。
func _age_color(b: Beast) -> Color:
	var a := b.effective_age()
	if a < Tribe.MATURITY_AGE:
		return Color(0.62, 0.82, 0.98)          # 未成年：还干不满勤
	if a > b.lifespan * 0.85:
		return Color(0.96, 0.50, 0.42)          # 风烛残年：随时会走
	if a > 45.0:
		return Color(0.94, 0.79, 0.46)          # 老年：干活开始打折
	return Color(0.88, 0.93, 0.88)              # 壮年：满勤


func _top_bloodlines(g: Genome, n: int) -> String:
	var parts: Array = []
	var keys := g.sorted_bloodlines()
	for i in mini(n, keys.size()):
		var k: StringName = keys[i]
		parts.append("%s%d" % [BloodlineDB.bloodline_name(k), int(g.titers[k])])
	return " ".join(parts)


func _defects(b: Beast) -> String:
	if b.genome.defects.is_empty():
		return ""
	var names: Array = []
	for d in b.genome.defects:
		names.append(String(d))
	return "[" + "/".join(names) + "]"


func _refresh() -> void:
	if world == null:
		return
	_date_label.text = "第 %d 回合 · %s · 第 %d 年　[种子 %d]" % [
		world.turn + 1, world.season_name(), world.year() + 1, rng_seed]
	_metrics_label.text = "人口 %d　劳力 %.1f　饱食 %.0f　仓 %.0f/%.0f　压力 %.2f　平均F %.3f%s" % [
		world.population(), world.workers(), world.satiety,
		world.food_store, world.granary_cap(), world.pressure_ratio(),
		world.mean_inbreeding(),
		"　【已灭绝】" if world.extinct else ""]
	if world.pressure_ratio() > 1.0:
		_metrics_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
	elif world.mean_inbreeding() > 0.125:
		_metrics_label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.45))
	else:
		_metrics_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	_sync_parent_pickers_if_needed()
	_refresh_region()
	_refresh_site_info()
	_refresh_descent_panel()
	_refresh_knowledge()
	_refresh_save_buttons()
	_refresh_planner()
	_refresh_log()
	if _transit_label != null:
		if world.in_transit:
			_transit_label.visible = true
			_transit_label.text = "【在途】还剩 %d 回合抵达 %s　途经：%s" % [
				world.transit_turns_left, RegionDB.node_display_name(world.transit_target),
				world.transit_route_names()]
			_transit_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		else:
			_transit_label.visible = false
	if _faith_label != null:
		_faith_label.text = "信仰 %.0f／100　士气 %.0f／100　强制配对 %d 次" % [
			world.faith, world.morale, world.forced_pairs]


func _bar(ratio: float, width: int = 22) -> String:
	var filled := clampi(int(ratio * width), 0, width)
	var color := "8fd18a"
	if ratio < 0.2:
		color = "e06c5a"
	elif ratio < 0.45:
		color = "e0b45a"
	return "[color=#%s]%s[/color]%s" % [color, "█".repeat(filled), "░".repeat(width - filled)]


func _refresh_region() -> void:
	var r := world.region
	var t := ""
	t += "[b]%s[/b]（%s）\n" % [r.name, RegionDB.region_name(r.region_id)]
	t += "食物 %s %.0f%%\n" % [_bar(r.food_ratio()), r.food_ratio() * 100.0]
	t += "猎物 %s %.0f%%\n" % [_bar(r.prey_ratio()), r.prey_ratio() * 100.0]
	t += "粮仓 %s %.0f/%.0f\n\n" % [_bar(world.food_store / maxf(world.granary_cap(), 1.0)),
		world.food_store, world.granary_cap()]
	t += "采集上限 %5.1f / 天　　狩猎上限 %5.1f / 天\n" % [r.food_msy(), r.prey_msy()]
	t += "承载力 [b]%.1f[/b] 人　　当前 [b]%d[/b] 人　　压力 [b]%.2f[/b]\n" % [
		world.capacity(), world.population(), world.pressure_ratio()]
	if world.pressure_ratio() > 1.0:
		t += "[color=#e06c5a]→ 正在吃老本。土地会记住这件事。[/color]\n"
	if r.degraded:
		t += "[color=#e06c5a]→ 生态已永久退化，承载力只剩七成。[/color]\n"
	if r.prey_migration_left > 0:
		t += "[color=#e0b45a]→ 猎物迁徙中，还剩 %d 天。[/color]\n" % r.prey_migration_left
	if world.extinct:
		t += "\n[color=#e06c5a][b]部落已灭绝。[/b][/color]\n"
	_region_text.text = t


## 选中一个人 → 看他的档案；选中两个 → 看配对分析 + 两份档案。
## 人格层的价值全在这里：想法、性情、关系、个人史，都必须能被读到。
func _refresh_planner() -> void:
	var ids := _selected_ids()
	if ids.is_empty() or not world.tribe.beasts.has(ids[0]):
		_planner_text.text = "[color=#8a9490]在左边点一个人，看他的性情、关系和故事；点两个人看配对。[/color]"
		return
	if ids.size() == 1:
		_planner_text.text = _profile_text(ids[0], true)
		return
	var ida: int = ids[0]
	var idb: int = ids[1]
	if not world.tribe.beasts.has(idb):
		_planner_text.text = _profile_text(ida, true)
		return
	_planner_text.text = _pair_text(ida, idb) + "\n\n" + \
		_profile_text(ida, false) + "\n" + _profile_text(idb, false)


## 两个人的配对分析（原来的内容）。
func _pair_text(ida: int, idb: int) -> String:
	var a: Beast = world.tribe.beasts[ida]
	var b: Beast = world.tribe.beasts[idb]
	var kin := world.tribe.pedigree.kinship(ida, idb)
	var expect := Genome.expected_titers(a.genome, b.genome)

	var t := ""
	t += "[b]%s[/b]　%.0f 岁 / 寿命 %.0f　劳动 %.0f%%　心情 %.0f　%s\n" % [
		a.display_name(), a.age, a.lifespan, a.labor_capacity() * 100.0, a.mood, _age_word(a)]
	t += "[b]%s[/b]　%.0f 岁 / 寿命 %.0f　劳动 %.0f%%　心情 %.0f　%s\n" % [
		b.display_name(), b.age, b.lifespan, b.labor_capacity() * 100.0, b.mood, _age_word(b)]

	var rel := world.tribe.relation(ida, idb)
	var kw := world.tribe.kin_word(ida, idb)
	t += "两人关系：%s %+.0f%s\n\n" % [
		world.tribe.relation_label(ida, idb), rel,
		"（%s）" % kw if kw != "" else ""]

	t += "[b]血浓期望[/b]（子代）\n"
	for k in expect:
		var v := float(expect[k])
		var band := "无"
		if v >= 60: band = "显征"
		elif v >= 35: band = "潜征"
		elif v >= 15: band = "隐没"
		elif v > 0: band = "暗池"
		t += "  %-6s %s %5.1f  %s\n" % [BloodlineDB.bloodline_name(k), _bar(v / 100.0, 14), v, band]

	t += "\n[b]嵌合潜力[/b] %.0f%%\n" % (Genome.chimera_score(expect) * 100.0)
	t += "[b]近交系数 I = %.3f[/b]　" % kin
	if kin < 0.0625:
		t += "[color=#8fd18a]干净[/color]\n"
	elif kin < 0.125:
		t += "[color=#e0b45a]轻度：生育率 −10%%[/color]\n"
	elif kin < 0.25:
		t += "[color=#e0a05a]中度：生育率 −25%%，缺陷 15%%[/color]\n"
	else:
		t += "[color=#e06c5a]重度：生育率 −50%%，不育 20%%，死胎 30%%[/color]\n"
	t += "突变概率 %.0f%%（本节点魔力浓度 %.2f）\n" % [
		(Genome.MUT_NEW_BASE + Genome.MUT_NEW_PER_MAGIC * world.region.magic_density) * 100.0,
		world.region.magic_density]
	return t


## 一个人的档案：性情、爱好、想法、关系、个人史。
func _profile_text(id: int, detailed: bool) -> String:
	if not world.tribe.beasts.has(id):
		return ""
	var b: Beast = world.tribe.beasts[id]
	var t := "[b]%s[/b]　%s　%.0f 岁 / 寿命 %.0f　心情 %.0f\n" % [
		b.display_name(), "♂" if b.is_male() else "♀", b.age, b.lifespan, b.mood]

	# 血脉：从第一层的列表里挪到这里 —— 列表要给身份和状态让位，
	# 血浓是"要看细节时再查"的信息。
	var g: Genome = b.genome
	t += "\n[b]血脉[/b]\n"
	for k in g.sorted_bloodlines():
		var v := float(g.titers[k])
		var band := "暗池"
		if v >= 60:
			band = "显征"
		elif v >= 35:
			band = "潜征"
		elif v >= 15:
			band = "隐没"
		t += "    %-6s %s %5.0f  %s\n" % [
			BloodlineDB.bloodline_name(k), _bar(v / 100.0, 12), v, band]
	if not g.chimeras().is_empty():
		var cn: Array = []
		for c in g.chimeras():
			cn.append(BloodlineDB.chimera_name(c))
		t += "    [color=#e0d05a]嵌合：%s[/color]\n" % "、".join(cn)
	if not g.defects.is_empty():
		t += "    [color=#e06c5a]缺陷：%s[/color]\n" % _defects(b)

	# 性情
	if b.traits.is_empty():
		t += "性情：无\n"
	else:
		var parts: Array = []
		for tr in b.traits:
			parts.append(Persona.trait_name(tr))
		t += "性情：%s\n" % " · ".join(parts)
		if detailed:
			for tr in b.traits:
				t += "    [color=#9aa8a0]%s —— %s[/color]\n" % [
					Persona.trait_name(tr), Persona.trait_desc(tr)]

	# 爱好
	if not b.hobbies.is_empty():
		var hs: Array = []
		for k in b.hobbies:
			hs.append(Persona.hobby_name(int(k)))
		t += "爱好：%s（干对口的工作产出 +18%%）\n" % " · ".join(hs)
	if b.pregnant:
		t += "[color=#e0b45a]怀孕中[/color]\n"
	t += "想法：「%s」\n" % b.thought

	if not detailed:
		return t

	# 关系：按绝对值排序，最亲近与最敌对的都会露出来
	var rels: Array = []
	for other in world.tribe.beasts:
		if other == id:
			continue
		rels.append([world.tribe.relation(id, other), other])
	rels.sort_custom(func(x, y): return absf(float(x[0])) > absf(float(y[0])))

	t += "\n[b]关系[/b]\n"
	var shown := 0
	for r in rels:
		if absf(float(r[0])) < 6.0 or shown >= 6:
			break
		shown += 1
		var o: Beast = world.tribe.beasts[r[1]]
		var kw := world.tribe.kin_word(id, r[1])
		t += "    %-14s %s %+5.0f%s\n" % [o.display_name(),
			world.tribe.relation_label(id, r[1]), r[0],
			("（%s）" % kw) if kw != "" else ""]
	if shown == 0:
		t += "    [color=#8a9490]和谁都还没什么交情。[/color]\n"

	t += "\n[b]个人史[/b]\n"
	var lines := b.story_lines(10)
	if lines.is_empty():
		t += "    [color=#8a9490]还没什么可说的。[/color]\n"
	else:
		for e in lines:
			t += "    [color=#8a9490]第%2d回合[/color]  %s\n" % [e["turn"], e["text"]]
	return t


func _refresh_log() -> void:
	var lines: Array = []
	var start := maxi(0, world.log.size() - 14)
	for i in range(start, world.log.size()):
		var e: Dictionary = world.log[i]
		lines.append("[color=#8a9490]第 %d 天[/color] %s" % [e["day"], e["msg"]])
	_log_text.text = "\n".join(lines)


# ==========================================================================
# 交互
# ==========================================================================

## 列表选中即「这两个人」：选一个就是配对的一方，选两个就是一对。
## 派工、休息所、法术强制配对都读这个选择。
func _on_member_selection_changed() -> void:
	var ids := _selected_ids()
	if ids.size() >= 1:
		_pick_a_id = ids[0]
	if ids.size() >= 2:
		_pick_b_id = ids[1]
	_refresh_planner()


func _on_hunt_bias_changed(v: float) -> void:
	_hunt_label.text = "%.1f×" % v + ("（按可持续产量）" if absf(v - 1.0) < 0.05
		else "（超额打猎，猎物会崩）" if v > 1.0 else "（偏保守）")
	if world != null:
		world.hunt_bias = v


func _on_continent_clicked(nid: StringName) -> void:
	if _continent_info == null:
		return
	_continent_info.text = _continent_view.describe(nid)
	var days: int = _continent_view.travel_days_to(nid)
	if days == 1:
		_pending_dest = nid
		_migrate_button.text = "迁往 %s（1 天路程）" % RegionDB.node_display_name(nid)
	else:
		_pending_dest = &""
		_migrate_button.text = "迁徙（在大陆图上点一个邻格）"


func _on_site_clicked(site_id: int) -> void:
	_refresh_site_info()


## 制度面板：当前阶段、现行制度、可选的改制方向。
## 知识树。**未发现的节点显示为 ???** —— 让玩家看见树有形状，
## 但不知道那一格是什么、也不知道怎么触发。这是"发现"这件事的乐趣所在。
func _refresh_knowledge() -> void:
	if _knowledge_tree == null:
		return
	var keep := _selected_knowledge()
	_knowledge_tree.clear()
	var root := _knowledge_tree.create_item()
	for br in Knowledge.BRANCH_ORDER:
		var head := _knowledge_tree.create_item(root)
		var ids0 := Knowledge.ids_in_branch(br)
		var done := 0
		for kid0 in ids0:
			if world.adopted.has(kid0):
				done += 1
		head.set_text(0, "%s　%d/%d" % [String(Knowledge.BRANCH_NAMES[br]), done, ids0.size()])
		head.set_text(1, "")
		head.set_text(2, "")
		head.set_custom_color(0, Color(0.96, 0.87, 0.56))
		head.set_selectable(0, false)
		head.set_selectable(1, false)
		head.set_selectable(2, false)
		var ids := Knowledge.ids_in_branch(br)
		ids.sort_custom(func(a, b): return Knowledge.tier_of(a) < Knowledge.tier_of(b))
		for kid in ids:
			var it := _knowledge_tree.create_item(head)
			var is_known: bool = world.known.has(kid)
			var is_adopted: bool = world.adopted.has(kid)
			var ready: bool = world.can_adopt(kid)
			it.set_text(0, "    " + (Knowledge.node_name(kid) if is_known else "？？？"))
			if is_adopted:
				it.set_text(1, "已采纳")
				it.set_custom_color(1, Color(0.55, 0.88, 0.60))
			elif ready:
				it.set_text(1, "可采纳")
				it.set_custom_color(1, Color(0.96, 0.87, 0.56))
			elif is_known:
				it.set_text(1, "已发现")
				it.set_custom_color(1, Color(0.72, 0.78, 0.74))
			else:
				it.set_text(1, "未发现")
				it.set_custom_color(1, Color(0.45, 0.50, 0.48))
			# 未发现的知识连开销都不该让玩家看到 —— 那等于剧透
			if is_adopted or not is_known:
				it.set_text(2, "—")
			else:
				it.set_text(2, "%.0f" % Knowledge.cost_of(kid))
			it.set_metadata(0, kid)
			it.set_collapsed(false)
			if keep != &"" and kid == keep:
				it.select(0)
	# 没选任何东西时，默认落在第一项「可采纳」上 —— 那是最该被看到的一格
	if _selected_knowledge() == &"":
		for br2 in Knowledge.BRANCH_ORDER:
			var hit := false
			for kid2 in Knowledge.ids_in_branch(br2):
				if world.can_adopt(kid2):
					_find_knowledge_item(kid2).select(0)
					hit = true
					break
			if hit:
				break
	_refresh_knowledge_detail()


## 在树里找某一项知识的节点。树不深，直接遍历。
func _find_knowledge_item(id: StringName) -> TreeItem:
	var root := _knowledge_tree.get_root()
	if root == null:
		return null
	var br := root.get_first_child()
	while br != null:
		var it := br.get_first_child()
		while it != null:
			var md: Variant = it.get_metadata(0)
			if md != null and StringName(md) == id:
				return it
			it = it.get_next()
		br = br.get_next()
	return null


func _selected_knowledge() -> StringName:
	if _knowledge_tree == null:
		return &""
	var it := _knowledge_tree.get_selected()
	if it == null:
		return &""
	var md: Variant = it.get_metadata(0)
	return &"" if md == null else StringName(md)


func _on_knowledge_selected() -> void:
	_refresh_knowledge_detail()


func _refresh_knowledge_detail() -> void:
	var id := _selected_knowledge()
	if id == &"":
		_knowledge_detail.text = "[color=#8a9490]在上面选一项知识，看它的来历、开销和作用。[/color]"
		_adopt_btn.disabled = true
		_adopt_btn.text = "采纳"
		return
	var is_known: bool = world.known.has(id)
	var is_adopted: bool = world.adopted.has(id)
	var t := "[b]%s[/b]\n" % (Knowledge.node_name(id) if is_known else "？？？")
	if not is_known:
		t += "[color=#8a9490]还没被发现。部落得先经历点什么，才会想到这一层。[/color]\n"
	else:
		t += "%s\n" % Knowledge.node_desc(id)
		t += "[color=#9aa8a0]来历：%s[/color]\n" % Knowledge.trigger_text(id)
	var reqs: Array = Knowledge.requires_of(id)
	if not reqs.is_empty():
		var names: Array = []
		for r in reqs:
			names.append("%s%s" % [Knowledge.node_name(r),
				"✓" if world.adopted.has(r) else "✗"])
		t += "前置：%s\n" % "、".join(names)
	var eff: Dictionary = Knowledge.effects_of(id)
	if not eff.is_empty() and is_known:
		var parts: Array = []
		for k in eff:
			parts.append(Knowledge.effect_text(String(k), eff[k]))
		t += "作用：%s\n" % "、".join(parts)
	var dm := Knowledge.unlocks_descent(id)
	if dm >= 0 and is_known:
		t += "[color=#9aa8a0]解锁制度：%s[/color]\n" % Descent.mode_name(dm)
	_knowledge_detail.text = t

	var reason := world.adopt_blocked_reason(id)
	_adopt_btn.disabled = reason != ""
	if is_adopted:
		_adopt_btn.text = "已采纳"
	elif not is_known:
		_adopt_btn.text = "未发现"
	elif reason == "":
		_adopt_btn.text = "采纳（%d 信仰）" % int(Knowledge.cost_of(id))
	else:
		_adopt_btn.text = "采纳"
	_adopt_btn.tooltip_text = reason


func _on_adopt() -> void:
	var id := _selected_knowledge()
	if id == &"":
		return
	if world.adopt(id):
		_rebuild_members()
	_refresh()


## 没有存档文件时把「读档」按钮灰掉 —— 点了没反应比灰着更让人困惑。
func _refresh_save_buttons() -> void:
	if _load_btn != null:
		_load_btn.disabled = not FileAccess.file_exists(SAVE_PATH)
		_load_btn.tooltip_text = ("读取 %s" % SAVE_PATH) if not _load_btn.disabled \
			else "还没有存档"


func _refresh_descent_panel() -> void:
	if _descent_text == null:
		return
	var pop := world.population()
	var st := world.social_stage()
	var cur := world.tribe.descent_mode
	var t := "[b]%s[/b]（人口 %d）\n" % [world.stage_name(), pop]
	t += "[color=#9aa8a0]%s[/color]\n" % String(Descent.STAGE_DESC.get(st, ""))
	t += "现行：[b]%s[/b] —— %s\n" % [Descent.mode_name(cur), Descent.mode_blurb(cur)]
	t += "[color=#9aa8a0]已出生的人不改名；新规矩只管之后出生的孩子。[/color]"
	_descent_text.text = t

	# 只列出「本阶段已解锁」的制度，未解锁的显示为灰字提示
	var keep: int = _descent_pick.get_selected_id() if _descent_pick.item_count > 0 else -1
	_descent_pick.clear()
	_descent_choices.clear()
	for m in Descent.ALL_MODES:
		var unlocked := world.descent_unlocked(m)
		var label := Descent.mode_name(m)
		if m == cur:
			label += "（现行）"
		elif not unlocked:
			label += "（未知）"
		_descent_pick.add_item(label)
		var idx := _descent_pick.item_count - 1
		_descent_pick.set_item_metadata(idx, m)
		_descent_pick.set_item_disabled(idx, m == cur or not unlocked)
		_descent_choices.append(m)
		if m == keep:
			_descent_pick.select(idx)
	if _descent_pick.get_selected_id() < 0 and _descent_pick.item_count > 0:
		_descent_pick.select(0)
	_refresh_reform_button()


func _refresh_reform_button() -> void:
	var idx := _descent_pick.get_selected_id()
	if idx < 0:
		_reform_btn.disabled = true
		return
	var m: int = int(_descent_pick.get_item_metadata(idx))
	var reason := world.reform_blocked_reason(m)
	_reform_btn.disabled = reason != ""
	if world.tribe.descent_mode == m:
		_reform_btn.text = "现行"
	elif reason == "":
		_reform_btn.text = "改制 %d" % int(Descent.reform_cost(world.tribe.descent_mode, m))
	else:
		_reform_btn.text = "改制"
	_reform_btn.tooltip_text = reason if reason != "" else Descent.mode_desc(m)


## 界面产生的消息也要进同一条编年史，格式跟 WorldState._say() 一致。
func _ui_note(msg: String) -> void:
	world.log.append({"day": world.day, "msg": msg})
	if world.log.size() > 400:
		world.log.pop_front()
	_refresh_log()


func _on_save_game() -> void:
	if world.save_to_file(SAVE_PATH):
		_ui_note("【存档】已写入 %s。" % SAVE_PATH)
	else:
		_ui_note("【存档】写入失败：%s" % SAVE_PATH)


func _on_load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_ui_note("【读档】没有找到存档（%s）。" % SAVE_PATH)
		return
	var next_world := WorldState.new()
	if not next_world.load_from_file(SAVE_PATH):
		_ui_note("【读档】存档损坏或版本不符，读不出来。")
		return
	world = next_world
	_clear_ui_selection()
	_rebuild_members()
	_refresh()
	_ui_note("【读档】回到第 %d 回合（%s）。" % [world.turn, world.season_name()])


## 读档后成员 id 全变了，旧的选中状态必须清掉，否则面板上会显示已经不存在的人。
func _clear_ui_selection() -> void:
	_pick_a_id = -1
	_pick_b_id = -1


func _on_reform() -> void:
	var idx := _descent_pick.get_selected_id()
	if idx < 0:
		return
	var m: int = int(_descent_pick.get_item_metadata(idx))
	if world.reform_descent(m):
		_rebuild_members()
	_refresh()


func _refresh_site_info() -> void:
	if world == null or world.site_map == null:
		return
	var sid: int = _site_view.selected_site
	if sid < 0:
		_site_info.text = "[color=#8a9490]在地图上点一个工作点查看详情。[/color]"
		return
	var s := world.site_map.site(sid)
	if s.is_empty():
		return
	var ws: Array = s["workers"]
	var names: Array = []
	for id in ws:
		# 名单可能比实际人口「旧一步」：饥饿与衰老会在同一个 tick 里把人杀掉，
		# 而 _sync_sites() 是在 tick 开头重建名单的。所以这里必须防一手。
		if world.tribe.beasts.has(id):
			names.append(world.tribe.beasts[id].display_name())
	_site_info.text = "[b]%s[/b]（#%d）　离营地 %.0f　效率 %.0f%%　名额 %d/%d\n已派：%s" % [
		world.site_map.kind_name(int(s["kind"])), sid, float(s["dist"]),
		world.site_map.efficiency(s) * 100.0, ws.size(), int(s["slots"]),
		"、".join(names) if not names.is_empty() else "[color=#8a9490]（没人）[/color]"]


func _on_assign_selected() -> void:
	if world == null or _site_view.selected_site < 0:
		_crew_label.text = "先在地图上点一个工作点。"
		return
	var ids := _selected_ids()
	if ids.is_empty():
		_crew_label.text = "先在左边选人（可按住多选）。"
		return
	var ok := 0
	for id in ids:
		if world.assign(id, _site_view.selected_site):
			ok += 1
	world.auto_assign = false        # 玩家一旦手动指派，自动派工就不再覆盖
	_crew_label.text = "派了 %d 人过去（%d 人因名额已满没派成）。" % [ok, ids.size() - ok]
	_refresh()


func _on_send_to_rest() -> void:
	var ids := _selected_ids()
	if ids.size() != 2:
		_crew_label.text = "休息所要正好选两个人。"
		return
	var rest := world.site_map.sites_of_kind(SiteMap.Kind.REST)
	if rest.is_empty():
		return
	var rid := int(rest[0]["id"])
	world.unassign(ids[0])
	world.unassign(ids[1])
	world.assign(ids[0], rid)
	world.assign(ids[1], rid)
	world.auto_assign = false
	_crew_label.text = "%s 和 %s 被送进了休息所。" % [
		world.tribe.beasts[ids[0]].name, world.tribe.beasts[ids[1]].name]
	_refresh()


func _on_force_pair() -> void:
	var ids := _selected_ids()
	if ids.size() != 2:
		_crew_label.text = "法术强制配对要正好选两个人。"
		return
	var res := world.force_pair(ids[0], ids[1])
	if bool(res.get("ok", false)):
		_crew_label.text = "法术生效。士气 −%d，信仰 −%d。" % [
			int(WorldState.FORCE_PAIR_MORALE_COST), int(WorldState.FORCE_PAIR_FAITH)]
	else:
		_crew_label.text = String(res.get("reason", "失败"))
	_refresh()


func _rebuild_destinations() -> void:
	_dest_picker.clear()
	var nb := RegionDB.neighbors(world.region.id)
	for nid in nb:
		_dest_picker.add_item("%s（%d 天）" % [RegionDB.node_display_name(nid), nb[nid]])
		_dest_picker.set_item_metadata(_dest_picker.item_count - 1, String(nid))


## 重建两个父母下拉框。**必须按 beast id 保持选择**：
## 成员列表每次刷新都会按劳动能力重排，如果按索引记忆，选中的就会变成另一个人。
func _sync_parent_pickers() -> void:
	# 先把当前选中项翻译成 id
	if _parent_a.selected >= 0 and _parent_a.selected < _picker_ids.size():
		_pick_a_id = _picker_ids[_parent_a.selected]
	if _parent_b.selected >= 0 and _parent_b.selected < _picker_ids.size():
		_pick_b_id = _picker_ids[_parent_b.selected]

	_picker_ids = _member_ids.duplicate()
	for ob in [_parent_a, _parent_b]:
		ob.clear()
		for id in _picker_ids:
			var b: Beast = world.tribe.beasts[id]
			ob.add_item("%s %s" % ["♂" if b.is_male() else "♀", b.display_name()])

	if _picker_ids.is_empty():
		return
	var ia := _picker_ids.find(_pick_a_id)
	var ib := _picker_ids.find(_pick_b_id)
	if ia < 0:
		ia = 0
	if ib < 0 or ib == ia:
		ib = 1 if _picker_ids.size() > 1 else 0
	_parent_a.select(ia)
	_parent_b.select(ib)
	_pick_a_id = _picker_ids[ia]
	_pick_b_id = _picker_ids[ib]


## 只在成员集合真的变了的时候才重建下拉框（16x 下每帧重建太浪费）。
func _sync_parent_pickers_if_needed() -> void:
	if _member_ids.size() != _picker_ids.size():
		_sync_parent_pickers()
		return
	for i in _member_ids.size():
		if _member_ids[i] != _picker_ids[i]:
			_sync_parent_pickers()
			return


func _on_migrate() -> void:
	var nid: StringName = _pending_dest
	if nid == &"":
		if _dest_picker.item_count == 0:
			return
		nid = StringName(String(_dest_picker.get_item_metadata(_dest_picker.selected)))
	var res := world.start_migration(nid)
	if bool(res.get("ok", false)):
		_pending_dest = &""
		_migrate_button.text = "迁徙（丢掉一切建筑）"
		_rebuild_destinations()
		_crew_label.text = "部落拔营了。%s" % str(res.get("reason", ""))
		if _continent_view != null:
			_continent_view.set_current(world.region.id)
		if _site_view != null:
			_site_view.set_world(world)
	_refresh()


## 截一张图，用来确认界面真的渲染出来了（而不是只有逻辑能跑）。
func _run_screenshot(turns: int, fullscreen: bool = false, tab: int = 1) -> void:
	for _t in turns:
		if world.extinct:
			break
		world.end_turn()
	if fullscreen:
		_tabs.current_tab = 1
		if not _fullscreen_map:
			_toggle_fullscreen_map()
	_rebuild_members()
	_refresh()
	if _tabs != null and not fullscreen:
		_tabs.current_tab = tab
	if tab == 2:
		_select_first_members(1)   # 谱系页：默认选中一个人，展示他的档案
	# 顺便选中一个邻格，让信息面板也有内容
	var nb := RegionDB.neighbors(world.region.id)
	if not nb.is_empty():
		_on_continent_clicked(nb.keys()[0])
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("！渲染不可用（无显示驱动），截图失败")
	else:
		DirAccess.make_dir_recursive_absolute("res://reports")
		var path := "res://reports/ui_fullscreen.png"
		if not fullscreen:
			match tab:
				2: path = "res://reports/ui_lineage.png"
				3: path = "res://reports/ui_knowledge.png"
				_: path = "res://reports/ui_screenshot.png"
		var err := img.save_png(path)
		print("截图 → %s：第 %d 回合（%s 第%d年），人口 %d，压力 %.2f，save_png=%d" % [
			path, world.turn, world.season_name(), world.year() + 1,
			world.population(), world.pressure_ratio(), err])
	print("成员列表项 %d，界面节点 %d，大陆格数 %d" % [
		_member_ids.size(), _count_nodes(self), RegionDB.node_ids().size()])
	get_tree().quit()


# ==========================================================================
# 无头自检
# ==========================================================================

## 没有显示器时也能验证：界面能构建、模拟能推进、关键节点会触发。
func _run_self_test() -> void:
	if _site_view != null:
		_site_view.skip_animation = true
	print("=== M1 垂直切片自检（种子 %d）===" % rng_seed)
	print("起始：", world.snapshot())
	# 强制选中一个工作点：这样每一回合都会走 _refresh_site_info()，
	# 覆盖「工人名单里有人已经死了」这条最容易出错的路径。
	if _site_view != null:
		_site_view.selected_site = 0
	var marks := [4, 8, 12, 16, 20, 24, 28]
	for _t in 32:
		if world.extinct:
			break
		# 走完整的「结束回合」链路：播放动画 → await → 结算 → 刷新
		await _on_end_turn()
		if marks.has(world.turn):
			print("第%2d回合(%s 第%d年) 人=%2d 压力=%.2f 食物=%3.0f%% 猎物=%3.0f%% 仓=%4.0f 饱食=%3.0f" % [
				world.turn, world.season_name(), world.year() + 1,
				world.population(), world.pressure_ratio(),
				world.region.food_ratio() * 100.0, world.region.prey_ratio() * 100.0,
				world.food_store, world.satiety])
	print("")
	print("动画链路验证：结束回合按钮 disabled=%s，_resolving=%s" % [
		str(_end_turn_button.disabled), str(_resolving)])
	print("时间线（回合）：食物<20%% 第%d回合　永久退化 第%d回合　仓空 第%d回合　首次饿死 第%d回合" % [
		world.first_food_low / WorldState.DAYS_PER_TURN,
		world.first_degraded / WorldState.DAYS_PER_TURN if world.first_degraded > 0 else -1,
		world.first_store_empty / WorldState.DAYS_PER_TURN,
		world.first_death / WorldState.DAYS_PER_TURN])
	print("终局：", world.snapshot())
	print("界面节点数：", _count_nodes(self), "　成员列表项：", _member_ids.size())
	print("=== 自检结束 ===")
	get_tree().quit()


func _first_pressure_day() -> int:
	for h in world.history:
		if float(h["pressure"]) > 1.0:
			return int(h["day"])
	return -1


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
