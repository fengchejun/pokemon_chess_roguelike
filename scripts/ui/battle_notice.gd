extends Control
## Presentation queue; battle speed changes the visible duration.
signal finished
signal started
const DURATION := 1.0
var playback_speed := 1.0
var pending: Array = []
var remaining := 0.0
var caption: Label
var subtitle: Label
var band: PanelContainer

func _ready() -> void:
	name = "BattleNotice"
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_STOP
	band = PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(column)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 42)
	caption.add_theme_color_override("font_color", Color("fff2cc"))
	caption.add_theme_color_override("font_outline_color", Color("171a27"))
	caption.add_theme_constant_override("outline_size", 4)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(caption)
	subtitle = Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("ead8ab"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(subtitle)
	resized.connect(_layout)
	_layout()
	visible = false

func _layout() -> void:
	if band == null:
		return
	band.position = Vector2(0, (size.y - 118) * 0.5)
	band.size = Vector2(size.x, 118)

func active() -> bool:
	return remaining > 0 or not pending.is_empty()

func push(text: String, kind: String) -> void:
	pending.append({"text": text, "kind": kind})
	if remaining <= 0:
		_next()

func _next() -> void:
	if pending.is_empty():
		remaining = 0
		visible = false
		finished.emit()
		return
	var item: Dictionary = pending.pop_front()
	caption.text = item["text"]
	subtitle.text = {"player": "PLAYER PHASE", "enemy": "ENEMY PHASE", "victory": "VICTORY", "defeat": "DEFEAT", "escape": "RETREAT"}.get(item["kind"], "")
	var style := StyleBoxFlat.new()
	style.bg_color = {"player": Color("23436b"), "enemy": Color("682b38"), "victory": Color("66502b"), "defeat": Color("472e4f"), "escape": Color("354d57")}.get(item["kind"], Color("24334d"))
	style.border_color = Color("d7bd7f")
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	band.add_theme_stylebox_override("panel", style)
	remaining = DURATION
	visible = true
	_layout()
	started.emit()

func _process(delta: float) -> void:
	advance(delta * playback_speed)

func advance(delta: float) -> void:
	while remaining > 0 and delta >= remaining:
		delta -= remaining
		_next()
	if remaining > 0:
		remaining -= delta

func finish_all() -> void:
	pending.clear()
	remaining = 0
	visible = false
	finished.emit()
