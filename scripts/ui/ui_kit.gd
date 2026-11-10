class_name UIKit
extends RefCounted

const BG := Color("16161c")
const PANEL := Color("23232c")
const PANEL_LIGHT := Color("2d2d38")
const ACCENT := Color("ffd166")
const TEXT := Color("eeeef2")
const TEXT_DIM := Color("9a9aa6")
const GOOD := Color("7bd88f")
const BAD := Color("ff6b6b")

static var _font: Font = null


static func font() -> Font:
	if _font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
			"Noto Sans CJK SC", "PingFang SC", "sans-serif",
		])
		_font = system
	return _font


static func setup_theme(window: Window) -> void:
	ThemeDB.fallback_font = font()
	ThemeDB.fallback_font_size = 16
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 16
	window.theme = theme
	RenderingServer.set_default_clear_color(BG)


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func wrapped(text: String, size: int = 14, color: Color = TEXT_DIM) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func title(text: String, size: int = 26) -> Label:
	var node := label(text, size, ACCENT)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func button(text: String, size: int = 16) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.custom_minimum_size = Vector2(0, 36)
	return node


static func small_button(text: String) -> Button:
	var node := button(text, 14)
	node.custom_minimum_size = Vector2(0, 30)
	return node


static func panel(background: Color = PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	node.add_theme_stylebox_override("panel", style)
	return node


static func vbox(separation: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation: int = 8) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func scroll() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return node


static func clear_children(node: Node) -> void:
	## 立即从容器移出（避免同帧内点击到已失效的旧控件），随后延迟释放。
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func element_chip(element: String, size: int = 14) -> Label:
	var text: String = Elements.FULL_NAMES.get(element, "无属性")
	var node := label(text, size, Elements.color_of(element))
	return node


static func fill_background(control: Control, color: Color = BG) -> void:
	var background := ColorRect.new()
	background.color = color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(background)
	control.move_child(background, 0)
