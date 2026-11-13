extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1000, 760)
	root.content_scale_size = Vector2i(1000, 760)
	var background := ColorRect.new()
	background.color = Color("171923")
	background.size = Vector2(1000, 760)
	root.add_child(background)
	var board := BoardView.new()
	board.position = Vector2(52, 95)
	board.terrain = TestScenario.plain_terrain()
	root.add_child(board)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var labels := ["正常", "灼烧", "麻痹", "冰冻", "感电", "浸湿", "禁锢", "寄生"]
	var cells := [Vector2i(6,1), Vector2i(6,3), Vector2i(6,5), Vector2i(6,7), Vector2i(3,1), Vector2i(3,3), Vector2i(3,5), Vector2i(3,7)]
	for i in 8:
		var unit := CombatUnit.make("fire_wild1", "player", i + 1)
		unit.cell = cells[i]
		match i:
			1: unit.burn_ticks = 2
			2: unit.paralyzed_ticks = 2
			3: unit.frozen = true
			4: unit.shock_ticks = 2
			5: unit.slow_ticks = 2
			6: unit.imprison_ticks = 2
			7: unit.parasite_source_uid = 99
		board.units.append(unit)
		var label := Label.new()
		label.text = labels[i]
		label.position = board.position + BoardView.cell_center(unit.cell) + Vector2(-16, 33)
		root.add_child(label)
	for cell in [Vector2i(0,2),Vector2i(0,4),Vector2i(0,6)]:
		board.electric_flowers[cell] = true
	var combined := CombatUnit.make("fire_wild1", "player", 99)
	combined.cell = Vector2i(1, 7)
	combined.imprison_ticks = 1
	combined.shock_ticks = 1
	combined.parasite_source_uid = 1
	board.units.append(combined)
	var title := Label.new()
	title.text = "电电花与异常状态外观预览"
	title.position = Vector2(30, 20)
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("res://sample/status-flower-preview.png")
	print("STATUS_FLOWER_RENDERED")
	quit()
