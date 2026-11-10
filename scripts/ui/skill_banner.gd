extends PanelContainer
## Presentation queue only; it never delays battle actions.
var pending: Array[String] = []
var caption: Label
var remaining := 0.0
var duration := 0.0
var controlled := false

func _ready() -> void:
	name = "SkillBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.94)
	style.set_corner_radius_all(0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("f4e6bc"))
	add_child(caption)
	get_parent().resized.connect(_layout)
	_layout()
	visible = false

func _layout() -> void:
	var width := minf(580.0, get_parent().size.x * 0.46)
	position = Vector2((get_parent().size.x - width) * 0.5, 8)
	size = Vector2(width, 50)

func push(text: String) -> void:
	pending.append(text)
	if remaining <= 0.0:
		_next()

func _next() -> void:
	if pending.is_empty():
		remaining = 0.0
		visible = false
		return
	caption.text = pending.pop_front()
	duration = 0.75 if pending.size() > 1 else 1.1
	remaining = duration
	modulate.a = 1.0
	visible = true

func remaining_time() -> float:
	return remaining + pending.size() * 1.1

func _process(delta: float) -> void:
	if controlled:
		return
	if remaining <= 0.0:
		return
	remaining -= delta
	if remaining <= 0.0:
		_next()
	else:
		modulate.a = minf(1.0, remaining / 0.18)

func present(text: String) -> void:
	controlled = true
	pending.clear()
	caption.text = text
	modulate.a = 1.0
	visible = true

func dismiss() -> void:
	controlled = false
	remaining = 0.0
	pending.clear()
	visible = false
