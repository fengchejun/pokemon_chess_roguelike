extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1000, 760)
	root.content_scale_size = Vector2i(1000, 760)
	var bg := ColorRect.new()
	bg.color = Color("171923")
	bg.size = Vector2(1000, 760)
	root.add_child(bg)
	var board := BoardView.new()
	board.position = Vector2(52, 95)
	board.terrain = TestScenario.plain_terrain()
	board.deploy_cells = Balance.DEPLOY_AREA.duplicate()
	board.terrain[GridSpec.index(Vector2i(4, 2))] = TerrainDB.TREE
	board.terrain[GridSpec.index(Vector2i(3, 5))] = TerrainDB.ROCK_MOUNTAIN
	board.feedback_paused = true
	root.add_child(board)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var actor := CombatUnit.make("fire_wild1", "enemy", 1)
	actor.cell = Vector2i(5, 3)
	actor.hp = 100
	actor.max_hp = 100
	board.units = [actor]
	board.health_feedback.sync(board.units)
	actor.hp = 40
	board.health_feedback.sync(board.units)
	var number := Label.new()
	number.text = "−60"
	number.add_theme_color_override("font_color", Color("ff7975"))
	number.add_theme_font_size_override("font_size", 24)
	number.position = board.position + Vector2(BoardView.cell_center(actor.cell).x - 20, board._unit_head_y(actor) - 48)
	root.add_child(number)
	var title := Label.new()
	title.text = "血条红色扣血段 · 树木与岩山不透明 · 无开局格边框"
	title.position = Vector2(30, 20)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("res://sample/health-bar-feedback.png")
	print("HEALTH_BAR_FEEDBACK_RENDERED")
	quit()
