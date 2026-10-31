extends Control
var screen: Control
var entries: Array = []

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
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f1e9d5")
	style.border_color = Color("78664c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
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

func _process(delta: float) -> void:
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
