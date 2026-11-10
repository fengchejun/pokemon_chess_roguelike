extends RefCounted
## Shared by every dynamically constructed screen through the root Window.
static func box(background: Color, border: Color, padding: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(padding)
	style.shadow_color = Color("11111b")
	style.shadow_size = 2
	style.shadow_offset = Vector2(2, 2)
	style.anti_aliasing = false
	return style

static func build() -> Theme:
	var theme := Theme.new()
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var bg := Color("313244")
			var edge := Color("585b70")
			if state in ["hover", "hover_pressed", "focus"]:
				bg = Color("45475a")
				edge = Color("f9e2af")
			if state == "pressed":
				bg = Color("11111b")
			if state == "disabled":
				bg = Color("1e1e2e")
				edge = Color("313244")
			var style := box(bg, edge)
			if state in ["pressed", "hover_pressed"]:
				style.content_margin_top = 10
				style.content_margin_bottom = 6
				style.shadow_size = 0
			if state == "disabled":
				style.shadow_size = 0
			theme.set_stylebox(state, type, style)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(key, type, Color("cdd6f4"))
		theme.set_color("font_disabled_color", type, Color("6c7086"))
	for type in ["Panel", "PanelContainer", "PopupPanel", "TooltipPanel"]:
		theme.set_stylebox("panel", type, box(Color("1e1e2e"), Color("585b70")))
	theme.set_color("font_color", "TooltipLabel", Color("cdd6f4"))
	theme.set_stylebox("background", "ProgressBar", box(Color("11111b"), Color("45475a"), 0))
	theme.set_stylebox("fill", "ProgressBar", box(Color("f38ba8"), Color("f38ba8"), 0))
	for type in ["HBoxContainer", "VBoxContainer", "GridContainer"]:
		for key in ["separation", "h_separation", "v_separation"]:
			theme.set_constant(key, type, 6)
	for type in ["HSeparator", "VSeparator"]:
		theme.set_stylebox("separator", type, box(Color("313244"), Color("313244"), 0))
	return theme
