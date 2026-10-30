extends Control
## Transient presentation only; event cells are immutable even after death/movement.
var elapsed := 0.0
var entries: Array = []
var slots: Dictionary = {}
const COLORS := {"experience": Color("80c9ff"), "essence": Color("ffdd75"), "damage": Color("ff6868"), "heal": Color("72ed9a"), "zero": Color("bbc4d0"), "status": Color("ffc45d"), "clear": Color("9fd9ed"), "buff": Color("89e6b0"), "death": Color("ff995e"), "action": Color("c8bcff")}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20

func push(event: Dictionary) -> void:
	var cell: Vector2i = event["cell"]
	var start := maxf(elapsed, float(slots.get(cell, elapsed)))
	slots[cell] = start + 0.15
	var row := 0
	for entry in entries:
		if entry["cell"] == cell:
			row += 1
	var label := Label.new()
	label.text = String(event["text"])
	if event["kind"] == "buff" and int(event["value"]) > 0 and label.text in ["额外施法", "火焰增幅"]:
		label.text += " +%d" % int(event["value"])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", COLORS.get(event["kind"], Color.WHITE))
	label.add_theme_color_override("font_outline_color", Color("18202e"))
	label.add_theme_constant_override("outline_size", 5)
	label.visible = false
	add_child(label)
	entries.append({"cell": cell, "start": start, "duration": 1.3 if event["kind"] == "death" else 1.0, "row": row % 3, "label": label})

func remaining_time() -> float:
	var remaining := 0.0
	for entry in entries:
		remaining = maxf(remaining, entry["start"] + entry["duration"] - elapsed)
	return remaining

func _process(delta: float) -> void:
	elapsed += delta
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		var age: float = elapsed - entry["start"]
		var label: Label = entry["label"]
		if age >= entry["duration"]:
			label.queue_free()
			entries.remove_at(i)
			continue
		if age < 0:
			continue
		label.visible = true
		var origin := (Vector2(entry["cell"]) + Vector2(0.5, 0.08)) * BoardView.TILE
		var rise: float = age / entry["duration"] * 28.0
		var row_offset: float = entry["row"] * 24.0
		var desired := origin - Vector2(label.size.x * 0.5, rise + row_offset)
		if entry["cell"].y == 0:
			desired.y = maxf(0.0, origin.y - rise) + row_offset
		label.position = desired.clamp(Vector2.ZERO, (size - label.size).max(Vector2.ZERO))
		label.modulate.a = clampf((entry["duration"] - age) / 0.3, 0.0, 1.0)
	# Keep only the slots of active cells.
	for cell in slots.keys():
		if float(slots[cell]) < elapsed:
			slots.erase(cell)
