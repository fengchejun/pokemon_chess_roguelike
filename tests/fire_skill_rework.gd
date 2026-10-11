extends SceneTree

const CombatConfig = preload("res://scripts/combat_config.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _fireball_damage_and_limit() or not _enemy_fireball_limit() or not _fireball_terrain() or not _flamethrower_line():
		quit(1)
		return
	if not await _once_button():
		quit(1)
		return
	print("FIRE_SKILL_REWORK passed")
	quit(0)


func _clean_state() -> BattleState:
	var state := BattleState.new()
	state.terrain.ground.clear()
	state.terrain.objects.clear()
	state.terrain.steam.clear()
	state.terrain.burning.clear()
	state.unit_by_id("trainer").cell = Vector2i(0, 7)
	state.unit_by_id("ally_fire").cell = Vector2i(1, 3)
	state.unit_by_id("ally_water").cell = Vector2i(0, 6)
	state.unit_by_id("ally_rock").cell = Vector2i(0, 5)
	state.unit_by_id("wild_a").cell = Vector2i(4, 3)
	state.unit_by_id("wild_b").cell = Vector2i(4, 4)
	state.unit_by_id("wild_c").cell = Vector2i(7, 7)
	return state


func _fireball_damage_and_limit() -> bool:
	var state := _clean_state()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var center: CombatUnit = state.unit_by_id("wild_a")
	var side: CombatUnit = state.unit_by_id("wild_b")
	state.terrain.objects[Vector2i(2, 3)] = TerrainManager.make_rock()
	state.terrain.ground[side.cell] = "grass"
	state.terrain.ground[Vector2i(5, 3)] = "fragile"
	if state.projected_skill_impact(fire, "fire_burst", center.cell) != center.cell:
		return _fail("Fireball failed to cross an intervening rock")
	if EnvironmentResolver.skill_area(state, "fire_burst", center.cell, fire.cell).size() != 5:
		return _fail("Occupied fireball center did not show five affected cells")
	if not state.try_use_skill(fire.unit_id, "fire_burst", center.cell):
		return _fail("Fireball could not cast")
	if center.hp != center.max_hp - 2 or side.hp != side.max_hp - 1 or state.terrain.object_at(Vector2i(2, 3)).get("hp") != 2:
		return _fail("Fireball direct damage or obstacle crossing was wrong")
	if not state.terrain.is_collapsed(Vector2i(5, 3)) or not state.terrain.is_burning(side.cell) or state.terrain.is_burning(center.cell):
		return _fail("Fireball fragile collapse or flammable-only ignition was wrong")
	fire.skill_points = CombatConfig.SKILL_POINTS_PER_TURN
	state.turn_number += 1
	if state.can_use_skill(fire, "fire_burst", center.cell) or state.try_use_skill(fire.unit_id, "fire_burst", center.cell) or int(fire.battle_skill_uses.get("fire_burst", 0)) != 1:
		return _fail("Once-per-battle fireball limit did not persist across turns")
	if int(_clean_state().unit_by_id("ally_fire").battle_skill_uses.get("fire_burst", 0)) != 0:
		return _fail("Fireball limit did not reset in a new battle")
	return true


func _fireball_terrain() -> bool:
	var state := _clean_state()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	state.unit_by_id("wild_a").cell = Vector2i(7, 6)
	state.unit_by_id("wild_b").cell = Vector2i(7, 5)
	state.terrain.ground[Vector2i(4, 3)] = "shallow_water"
	state.terrain.ground[Vector2i(4, 4)] = "grass"
	state.terrain.objects[Vector2i(5, 3)] = TerrainManager.make_plant()
	if not state.try_use_skill(fire.unit_id, "fire_burst", Vector2i(4, 3)):
		return _fail("Fireball could not target water")
	if not state.terrain.is_steam(Vector2i(4, 3)) or state.terrain.is_burning(Vector2i(4, 3)) or not state.terrain.is_burning(Vector2i(4, 4)) or not state.terrain.is_burning(Vector2i(5, 3)):
		return _fail("Fireball steam, empty grass, or tree ignition was wrong")
	if state.terrain.is_burning(Vector2i(3, 3)) or state.terrain.object_at(Vector2i(5, 3)).get("hp") != 1:
		return _fail("Ordinary ground burned or tree durability was wrong")
	return true


func _enemy_fireball_limit() -> bool:
	var state := _clean_state()
	var enemy: CombatUnit = state.unit_by_id("wild_a")
	enemy.cell = Vector2i(6, 3)
	state.unit_by_id("trainer").cell = Vector2i(3, 3)
	state.phase = "enemy_attack"
	if not state.try_use_skill(enemy.unit_id, "fire_burst", Vector2i(3, 3)):
		return _fail("Enemy fireball could not cast")
	enemy.skill_points = CombatConfig.SKILL_POINTS_PER_TURN
	if state.can_use_skill(enemy, "fire_burst", Vector2i(3, 3)) or state.try_use_skill(enemy.unit_id, "fire_burst", Vector2i(3, 3)):
		return _fail("Enemy bypassed the once-per-battle fireball limit")
	return true


func _flamethrower_line() -> bool:
	var state := _clean_state()
	var fire: CombatUnit = state.unit_by_id("ally_fire")
	var front: CombatUnit = state.unit_by_id("wild_b")
	var middle: CombatUnit = state.unit_by_id("wild_c")
	var behind: CombatUnit = state.unit_by_id("wild_a")
	front.cell = Vector2i(2, 3)
	middle.cell = Vector2i(3, 3)
	behind.cell = Vector2i(5, 3)
	state.terrain.objects[Vector2i(4, 3)] = TerrainManager.make_rock()
	if state.can_use_skill(fire, "flame_jet", Vector2i(3, 4)) or not state.can_use_skill(fire, "flame_jet", Vector2i(2, 3)):
		return _fail("Flamethrower axis or adjacent direction was wrong")
	var expected: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	if EnvironmentResolver.skill_area(state, "flame_jet", Vector2i(2, 3), fire.cell) != expected:
		return _fail("Flamethrower area did not stop at the first obstacle")
	if not state.try_use_skill(fire.unit_id, "flame_jet", Vector2i(2, 3)):
		return _fail("Flamethrower could not cast toward the adjacent cell")
	if front.hp != front.max_hp - 1 or middle.hp != middle.max_hp - 1 or not front.burned or not middle.burned:
		return _fail("Flamethrower missed units along its line or failed to burn them")
	if behind.hp != behind.max_hp or state.terrain.object_at(Vector2i(4, 3)).get("hp") != 1 or state.terrain.is_burning(Vector2i(2, 3)):
		return _fail("Flamethrower passed the obstacle, missed durability, or ignited ground")
	return true


func _once_button() -> bool:
	if change_scene_to_file("res://scenes/battle.tscn") != OK:
		return _fail("Battle scene did not load")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	var state := _clean_state()
	state.unit_by_id("ally_fire").battle_skill_uses["fire_burst"] = 1
	battle.set("state", state)
	battle.set("selected_unit_id", "ally_fire")
	battle.call("_refresh")
	var button := battle.find_child("SkillButton_fire_burst", true, false) as Button
	if button == null or not button.disabled or not button.text.contains("本场已用"):
		return _fail("Spent fireball was not clearly disabled in the skill bar")
	state.unit_by_id("wild_a").battle_skill_uses["fire_burst"] = 1
	var board := battle.find_child("BattleBoard", true, false) as BattleBoard
	var enemy_detail := battle.find_child("EnemyDetailLabel", true, false) as Label
	board.cell_pressed.emit(state.unit_by_id("wild_a").cell)
	if enemy_detail == null or not enemy_detail.text.contains("火球术（本场已用）"):
		return _fail("Enemy detail did not show the spent fireball")
	return true


func _fail(message: String) -> bool:
	push_error("FIRE_SKILL_REWORK failed: " + message)
	return false
