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
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(4, 4)]])
	var caster := state.unit_by_uid(1)
	caster.cell = Vector2i(3, 4)
	caster.skills = ["drain"]
	var target := state.unit_by_uid(100)
	target.max_hp = 24
	target.hp = 24
	var board := BoardView.new()
	board.position = Vector2(52, 95)
	root.add_child(board)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.set_from_state(state)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	screen.board = board
	screen.hint_label = Label.new()
	screen.selected_uid = caster.uid
	screen.aim_skill = "drain"
	screen.aim_entries = state.skill_targets(caster, "drain")
	screen._on_board_hovered(target.cell)
	var title := Label.new()
	title.text = "施法前悬停目标：血条橙色刻纹表示预计扣除的生命"
	title.position = Vector2(30, 20)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	var hint: Label = screen.hint_label
	hint.position = Vector2(30, 60)
	root.add_child(hint)
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("res://sample/skill-damage-preview.png")
	print("SKILL_DAMAGE_PREVIEW_RENDERED")
	screen.free()
	quit()
