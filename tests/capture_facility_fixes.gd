extends SceneTree
var app
var screen

func _initialize() -> void:
	call_deferred("_run")

func _click(button: Control) -> void:
	await process_frame
	await process_frame
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		Input.parse_input_event(event)
		await process_frame
	await process_frame

func _click_cell(cell: Vector2i) -> void:
	var point: Vector2 = screen.board.get_global_transform() * screen.board.cell_center(cell)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		Input.parse_input_event(event)
		await process_frame
	await process_frame

func _skill_case(skill: String, from: Vector2i, to: Vector2i, water: bool) -> bool:
	var next = load("res://scripts/ui/battle_screen.gd").new()
	next.state = TestScenario.make_state(["electric_starter" if water else "fire_starter"], [["rock_wild1", to]])
	var caster: CombatUnit = next.state.unit_by_uid(1)
	caster.cell = from
	if not caster.skills.has(skill):
		caster.skills.append(skill)
	var victim: CombatUnit = next.state.unit_by_uid(100)
	victim.hp = 999
	if water:
		next.state.set_terrain(Vector2i(1, 4), TerrainDB.WATER)
	app._switch(next)
	screen = next
	screen.select_unit(caster.uid)
	screen._on_skill_pressed(skill)
	await process_frame
	await _click_cell(to)
	if victim.hp >= 999:
		push_error("Mouse targeting failed: " + skill)
		quit(1)
		return false
	await screen._wait_playback()
	await _shot("fixed_" + skill)
	return true

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + name + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	root.add_child(app)
	app.set_anchors_preset(Control.PRESET_FULL_RECT)
	app.run = RunState.new_run(4242)
	app.run.region_mode = true
	app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
	var region = app.run.get_region()
	var id := "event_1" if region.nodes["event_1"].has("merchant") else "event_2"
	region.nodes[id]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node(id)
	app.show_preview([1, 2, 3])
	app.current_screen._on_start()
	screen = app.current_screen
	var state: BattleState = screen.state
	state.merchant["cell"] = Vector2i(4, 3)
	state.set_terrain(Vector2i(3, 3), TerrainDB.PLAIN)
	state.trainer().cell = Vector2i(3, 3)
	screen.playback.finish_all()
	screen.refresh_all()
	screen.select_unit(state.trainer().uid)
	await _shot("merchant_adjacent_action")
	await _click(screen.skill_box.find_child("MerchantInteractButton", true, false))
	var uid := int(app.run.carried[1]["uid"])
	var expected := Merchant.monster_price(app.run.record_by_uid(uid))
	var balance: int = app.run.essence
	var sale: Button = screen.modal_layer.find_child("SellMonster_%d" % uid, true, false)
	var scroll: ScrollContainer = screen.modal_layer.get_child(0).get_child(0).get_child(1)
	await process_frame
	scroll.ensure_control_visible(sale)
	await _click(sale)
	var confirm: Button = screen.modal_layer.find_child("ConfirmMonsterSaleButton", true, false)
	if confirm == null:
		push_error("Sale confirmation did not open from mouse click")
		quit(1)
		return
	await _shot("merchant_sale_confirm")
	await _click(screen.modal_layer.find_child("CancelMonsterSaleButton", true, false))
	if app.run.record_by_uid(uid).is_empty() or app.run.essence != balance:
		push_error("Cancel sale changed member or balance")
		quit(1)
		return
	sale = screen.modal_layer.find_child("SellMonster_%d" % uid, true, false)
	scroll = screen.modal_layer.get_child(0).get_child(0).get_child(1)
	await process_frame
	scroll.ensure_control_visible(sale)
	await _click(sale)
	confirm = screen.modal_layer.find_child("ConfirmMonsterSaleButton", true, false)
	await _click(confirm)
	if not app.run.record_by_uid(uid).is_empty() or app.run.essence != balance + expected:
		push_error("Sale did not complete from mouse click")
		quit(1)
		return
	await _shot("merchant_sale_complete")
	print("MONSTER_SALE_MOUSE_OK uid=", uid, " gained=", expected)
	app.show_region()
	region = app.run.get_region()
	region.complete_visit()
	region.nodes["boss"]["unlocked"] = true
	app.run.region_data = region.to_dict()
	app.enter_region_node("boss")
	app.show_preview([1, 3])
	app.current_screen._on_start()
	screen = app.current_screen
	state = screen.state
	var boss := state.unit_by_uid(state.boss_uid)
	state.kill_unit(boss, "传送门交互验证", "player", 1)
	screen.refresh_all()
	await screen._wait_playback()
	var portal: Vector2i = state.boss_portal_cell
	for cell in GridSpec.neighbors4(portal):
		if state.unit_at(cell) == null:
			state.set_terrain(cell, TerrainDB.PLAIN)
			state.trainer().cell = cell
			break
	screen.refresh_all()
	screen.select_unit(state.trainer().uid)
	await _shot("portal_adjacent_action")
	app.run.storage.append(app.run._make_record("fire_starter"))
	await _click(screen.skill_box.find_child("PortalInteractButton", true, false))
	var portal_confirm: Button = screen.modal_layer.find_child("ConfirmPortalButton", true, false)
	if portal_confirm == null:
		push_error("Portal storage confirmation missing")
		quit(1)
		return
	await _click(portal_confirm)
	await create_timer(0.7).timeout
	if not state.ended or app.current_screen == screen:
		push_error("Portal action did not advance scene")
		quit(1)
		return
	print("PORTAL_ADJACENT_MOUSE_OK")
	app.run = RunState.new_run(42)
	if not await _skill_case("flame_charge", Vector2i(6, 3), Vector2i(7, 3), false):
		return
	if not await _skill_case("electric_arc", Vector2i(1, 3), Vector2i(3, 3), true):
		return
	print("EDGE_CHARGE_AND_DRY_ARC_MOUSE_OK")
	app.queue_free()
	await process_frame
	quit()
