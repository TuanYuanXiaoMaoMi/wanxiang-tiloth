extends SceneTree
## 字体覆盖检查：把项目里所有文案中的汉字逐个喂给界面用的字体，
## 报出「没有字形」的字。
##
## 为什么需要它：缺字不会报错、不会崩，只会静默地渲染成豆腐块或错误的替代字形。
## 这类问题在自检里永远是 0 错误，只有肉眼能发现 —— 而这个工具能替肉眼先看一遍。
##
##   ./tools/godot.sh --headless --script res://tools/check_fonts.gd

## 字体来自 game/ui_font.gd —— 和界面用的是同一个构建函数，
## 否则这里验的是一个字体、界面上用的是另一个，缺字照样漏过去。

const SCAN_DIRS := ["res://sim", "res://game", "res://data", "res://tools", "res://docs"]
const SCAN_EXT := [".gd", ".json", ".md", ".tscn", ".godot"]


func _initialize() -> void:
	var font := UIFont.build()

	var chars := {}
	for dir in SCAN_DIRS:
		_collect(dir, chars)
	print("扫描到唯一汉字 %d 个" % chars.size())

	var missing: Array = []
	var ok := 0
	for ch in chars:
		if font.has_char(String(ch).unicode_at(0)):
			ok += 1
		else:
			missing.append(ch)
	missing.sort()

	print("有字形 %d 个　[b]缺字形 %d 个[/b]" % [ok, missing.size()])
	if missing.is_empty():
		print("✅ 全部覆盖")
		quit()
		return

	print("")
	print("缺字清单（括号里出现的次数）：")
	for ch in missing:
		print("    %s  U+%04X  ×%d" % [ch, String(ch).unicode_at(0), chars[ch]])

	# 只保留一个名字的对照测试：确认是"清单里所有字体都没有"还是"某个字体缺"
	print("")
	print("逐个字体对照（缺字前 12 个）：")
	var probe := missing.slice(0, mini(12, missing.size()))
	for name in UIFont.CANDIDATES:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([name])
		var hit := 0
		for ch in probe:
			if f.has_char(String(ch).unicode_at(0)):
				hit += 1
		print("    %-18s 覆盖 %d/%d" % [name, hit, probe.size()])
	quit()


func _collect(path: String, out: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := path.path_join(name)
		if d.current_is_dir():
			_collect(full, out)
		else:
			var ext := "." + name.get_extension()
			if SCAN_EXT.has(ext):
				_scan_file(full, out)
		name = d.get_next()
	d.list_dir_end()


func _scan_file(path: String, out: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0x4E00 and c <= 0x9FFF:      # CJK 统一表意文字基本区
			var s := String.chr(c)
			out[s] = int(out.get(s, 0)) + 1
