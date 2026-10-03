class_name UIFont
extends RefCounted
## 界面字体构建。**单独抽出来是为了让 tools/check_fonts.gd 能验同一个字体** ——
## 如果两处各写一份，早晚会不一致，而缺字是静默的，不一致也发现不了。
##
## 踩过的坑：Godot 的 SystemFont 在 font_names 里**只挑第一个匹配到的字体，不做逐字回退**。
## 而 macOS 的 PingFang SC 竟然缺「远」「敌」「杀」「杂」「稳」「虑」「迟」这些常用字 ——
## 于是界面上「远行癖」会渲染成别的字。修法两条：
##   ① 主字体换成实测能全覆盖的 Hiragino Sans GB；
##   ② 仍然挂一串 fallbacks 兜底，将来换机器也不至于开天窗。

const CANDIDATES := ["Hiragino Sans GB", "Heiti SC", "STHeiti", "Songti SC",
	"PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "Arial Unicode MS"]


static func build() -> Font:
	var primary := SystemFont.new()
	primary.font_names = PackedStringArray(CANDIDATES)
	# 逐字回退链：primary 缺哪个字就往后找
	var fbs: Array = []
	for n in CANDIDATES:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([n])
		fbs.append(f)
	primary.fallbacks = fbs
	return primary


## 给出一个「这个字体是否覆盖了关键汉字」的自检结论。
static func coverage_report(font: Font, probe: Array) -> Dictionary:
	var missing: Array = []
	for ch in probe:
		if not font.has_char(String(ch).unicode_at(0)):
			missing.append(ch)
	return {"total": probe.size(), "missing": missing}
