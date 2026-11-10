extends Control
var screen: Control
var entries: Array = []
var suppressed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 25

func push(event: Dictionary) -> void:
	var uid := int(event["uid"])
	if event.get("speech_key", "") == "merchant_help":
		for entry in entries.duplicate():
			if entry["uid"] == uid:
				entry["panel"].queue_free()
				entries.erase(entry)
	var delay := 0.0
	for entry in entries:
		if entry["uid"] == uid:
			delay = maxf(delay, float(entry["remaining"]))
	var panel := preload("res://scripts/ui/speech_bubble_shape.gd").new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.jagged = String(event["text"]).contains("！") or String(event["text"]).contains("!")
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT if panel.jagged else Color("f1e9d5")
	style.border_color = Color.TRANSPARENT if panel.jagged else Color("78664c")
	style.set_border_width_all(0 if panel.jagged else 2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = event["text"]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 220
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("302b24"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.visible = false
	add_child(panel)
	entries.append({"uid": uid, "cell": event["cell"], "remaining": delay + 3.0, "delay": delay, "panel": panel})

func dismiss_on_unit_click() -> void:
	for entry in entries.duplicate():
		if entry["delay"] <= 0:
			entry["panel"].queue_free()
			entries.erase(entry)

func active() -> bool:
	return not entries.is_empty()

func set_suppressed(value: bool) -> void:
	suppressed = value
	for entry in entries:
		entry["panel"].visible = not value and entry["delay"] <= 0

func _process(delta: float) -> void:
	if suppressed:
		return
	for entry in entries.duplicate():
		entry["remaining"] -= delta
		entry["delay"] -= delta
		var panel: PanelContainer = entry["panel"]
		if entry["remaining"] <= 0:
			panel.queue_free()
			entries.erase(entry)
			continue
		if entry["delay"] > 0:
			continue
		panel.visible = true
		var cell: Vector2i = entry["cell"]
		var unit: CombatUnit = screen._display_state().unit_by_uid(entry["uid"])
		if unit != null:
			cell = unit.cell
		var origin: Vector2 = screen.board.position + (Vector2(cell) + Vector2(0.5, 0)) * BoardView.TILE * screen.board.scale.x
		var desired := origin - Vector2(panel.size.x * 0.5, panel.size.y + 8)
		if desired.y < 6:
			desired.y = origin.y + BoardView.TILE * screen.board.scale.x + 8
		panel.position = desired.clamp(Vector2(6, 6), (size - panel.size - Vector2(6, 6)).max(Vector2(6, 6)))
