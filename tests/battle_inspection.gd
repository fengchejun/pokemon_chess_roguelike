extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle scene did not open")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := BattleState.new()
	battle.set("state", state)
	battle.call("_refresh")
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var terrain_detail := battle.find_child("TerrainDetailLabel", true, false) as Label
	var enemy_detail := battle.find_child("EnemyDetailLabel", true, false) as Label
	var preview := battle.find_child("PreviewLabel", true, false) as Label
	var info_scroll := battle.find_child("InfoScroll", true, false) as ScrollContainer
	var log_scroll := battle.find_child("LogScroll", true, false) as ScrollContainer
	var log_label := battle.find_child("LogLabel", true, false) as Label
	if board == null or terrain_detail == null or enemy_detail == null or preview == null or info_scroll == null or log_scroll == null or log_label == null:
		return _fail("Inspection controls are missing")
	if info_scroll.is_ancestor_of(log_label) or not log_scroll.is_ancestor_of(log_label):
		return _fail("Battle log still shares the inspection scroll region")
	var terrain_cases := {
		Vector2i(3, 1): "浅水",
		Vector2i(4, 1): "易碎地块",
		Vector2i(5, 3): "岩石",
		Vector2i(5, 4): "树木"
	}
	for cell in terrain_cases:
		board.cell_hovered.emit(cell)
		if not terrain_detail.text.contains(terrain_cases[cell]):
			return _fail("Hover did not describe %s" % terrain_cases[cell])
	state.terrain.ground[Vector2i(0, 0)] = "deep_water"
	state.terrain.ground[Vector2i(0, 1)] = "collapsed"
	state.terrain.ground[Vector2i(0, 2)] = "grass"
	state.terrain.ignite_plant(Vector2i(0, 2))
	state.terrain.add_steam(Vector2i(3, 1))
	state.nest = {"cell": Vector2i(7, 7), "exit": Vector2i(7, 6), "hp": 3}
	state.reward_cell = Vector2i(0, 6)
	state.reward_state = "ground"
	for case in [
		[Vector2i(0, 0), "溺亡"],
		[Vector2i(0, 1), "深坑"],
		[Vector2i(0, 2), "燃烧"],
		[Vector2i(3, 1), "蒸汽雾"],
		[Vector2i(7, 7), "巢穴"],
		[Vector2i(7, 6), "巢穴出口"],
		[Vector2i(0, 6), "战斗 Buff 奖励"]
	]:
		board.cell_hovered.emit(case[0])
		if not terrain_detail.text.contains(case[1]):
			return _fail("Hover did not describe %s" % case[1])
	board.mouse_exited.emit()
	if not terrain_detail.text.contains("悬停特殊地块"):
		return _fail("Terrain details remained after pointer left board")
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	board.cell_pressed.emit(enemy.cell)
	if board.inspected_enemy_id != enemy.unit_id or not enemy_detail.text.contains("生命 4/4") or not enemy_detail.text.contains("火球术") or not enemy_detail.text.contains("喷射火焰") or not preview.text.contains("可移动"):
		return _fail("Enemy click did not show detail and movement range")
	board.cell_hovered.emit(Vector2i(4, 1))
	if not enemy_detail.text.contains("火球术") or not terrain_detail.text.contains("易碎地块"):
		return _fail("Enemy detail did not persist alongside terrain hover")
	enemy.wet = true
	enemy.burned = true
	battle.call("_refresh")
	if not enemy_detail.text.contains("浸湿") or not enemy_detail.text.contains("灼烧"):
		return _fail("Enemy statuses did not refresh")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("res://artifacts/battle_inspection.png")
	for index in 24:
		state.events.append("历史事件 %02d" % index)
	battle.call("_refresh")
	await process_frame
	await process_frame
	if not log_label.text.contains("历史事件 00") or not log_label.text.contains("历史事件 23") or log_scroll.scroll_vertical <= 0:
		return _fail("Independent battle log did not retain and scroll its full history (first=%s, last=%s, scroll=%d, max=%f)" % [str(log_label.text.contains("历史事件 00")), str(log_label.text.contains("历史事件 23")), log_scroll.scroll_vertical, log_scroll.get_v_scroll_bar().max_value])
	board.cell_pressed.emit(state.unit_by_id("trainer").cell)
	if not enemy_detail.text.contains("点击敌人查看"):
		return _fail("Selecting an ally did not clear enemy inspection")
	print("BATTLE_INSPECTION passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("BATTLE_INSPECTION failed: " + message)
	quit(1)
