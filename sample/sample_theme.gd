extends RefCounted

static func box(bg: Color, edge: Color, padding: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(2)
	s.border_color = edge
	s.border_width_bottom = 3
	s.set_content_margin_all(padding)
	s.shadow_color = Color("090910")
	s.shadow_size = 3
	s.shadow_offset = Vector2(2, 3)
	s.anti_aliasing = false
	return s

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = UIKit.font()
	t.default_font_size = 16
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var bg := Color("313244")
			var edge := Color("656174")
			if state in ["hover", "focus"]:
				edge = Color("f9e2af")
			if state == "pressed": bg = Color("171721")
			if state == "disabled":
				bg = Color("21212d")
				edge = Color("393947")
			var s := box(bg, edge)
			if state == "pressed":
				s.content_margin_top = 10
				s.content_margin_bottom = 6
				s.shadow_size = 0
			t.set_stylebox(state, type, s)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			t.set_color(state, type, Color("cdd6f4"))
		t.set_color("font_disabled_color", type, Color("777382"))
	t.set_stylebox("background", "ProgressBar", box(Color("11111b"), Color("4d4152"), 0))
	t.set_stylebox("fill", "ProgressBar", box(Color("f38ba8"), Color("f38ba8"), 0))
	return t
