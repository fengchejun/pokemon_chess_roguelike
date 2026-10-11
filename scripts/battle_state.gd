class_name BattleState
extends RefCounted

const GridSpec = preload("res://scripts/grid_spec.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")
const PushResolver = preload("res://scripts/push_resolver.gd")
const MovementPathfinder = preload("res://scripts/movement_pathfinder.gd")
const TerrainManager = preload("res://scripts/terrain_manager.gd")
const EnvironmentResolver = preload("res://scripts/environment_resolver.gd")
const MonsterCatalog = preload("res://scripts/monster_catalog.gd")
const CaptureSystem = preload("res://scripts/capture_system.gd")
const RunState = preload("res://scripts/run_state.gd")
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var units: Array[CombatUnit] = []
var turn_number: int = 1
var phase: String = "setup"
var outcome: String = ""
var events: Array[String] = []
var terrain: TerrainManager
var map_info: Dictionary = {}
var environment_resolution_depth: int = 0
var defeated_enemy_ids: Array[String] = []
var escaped_enemy_ids: Array[String] = []
var captured_records: Array[Dictionary] = []
var reward_claimed: bool = false
var run_state: RunState
var capture_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var movement_history: Array[Dictionary] = []
var movement_undo_locked: bool = false
var nest: Dictionary = {}
var reward_cell: Vector2i = Vector2i(-1, -1)
var reward_state: String = "none"
var reward_carrier_id: String = ""
var spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var spawned_count: int = 0


func _init(current_run: RunState = null, generated_layout: Dictionary = {}) -> void:
	run_state = current_run if current_run != null else RunState.new()
	capture_rng.seed = 20261009 + run_state.battle_count * 7919
	spawn_rng.seed = run_state.run_seed + run_state.battle_count * 104729 + 81
	terrain = TerrainManager.new(generated_layout)
	map_info = generated_layout.get("info", {})
	nest = generated_layout.get("nest", {}).duplicate(true)
	var reward: Dictionary = generated_layout.get("reward", {})
	if not reward.is_empty():
		reward_cell = reward["cell"]
		reward_state = "ground"
	var trainer := CombatUnit.new("trainer", "训练家", "训", "player", Vector2i(1, 3), CombatConfig.TRAINER_HP, CombatConfig.PLAYER_MOVE_POINTS, 0)
	trainer.speed = CombatConfig.TRAINER_SPEED
	trainer.capture_points = CombatConfig.CAPTURE_ATTEMPTS_PER_TURN
	units.append(trainer)
	var deployment_cells: Array[Vector2i] = [Vector2i(1, 2), Vector2i(1, 4), Vector2i(2, 3)]
	var active_records: Array[Dictionary] = run_state.active_records()
	for index in mini(active_records.size(), CombatConfig.DEPLOYED_MONSTER_LIMIT):
		units.append(MonsterCatalog.make_ally(active_records[index], deployment_cells[index]))
	units.append(MonsterCatalog.make_enemy("wild_a", "fire", Vector2i(6, 2)))
	units.append(MonsterCatalog.make_enemy("wild_b", "water", Vector2i(6, 5)))
	units.append(MonsterCatalog.make_enemy("wild_c", "rock", Vector2i(6, 3)))
	_log("战斗开始：我方整队行动，结束回合后敌人依次移动并施法。")
	_start_round()


func unit_by_id(unit_id: String) -> CombatUnit:
	for unit in units:
		if unit.unit_id == unit_id:
			return unit
	return null


func unit_at(cell: Vector2i) -> CombatUnit:
	for unit in units:
		if unit.is_alive() and unit.cell == cell:
			return unit
	return null


func distance(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)


func current_player_ids() -> Array[String]:
	var ids: Array[String] = []
	if phase == "player":
		for unit in units:
			if unit.team == "player" and unit.is_alive():
				ids.append(unit.unit_id)
	return ids


func can_act_now(unit: CombatUnit) -> bool:
	if unit == null or not unit.is_alive() or outcome != "" or unit.eligible_round > turn_number:
		return false
	return phase == "player" if unit.team == "player" else phase in ["enemy_move", "enemy_attack"]


func can_enter_voluntarily(unit: CombatUnit, cell: Vector2i) -> bool:
	return unit != null and GridSpec.is_inside(cell) and unit_at(cell) == null and not terrain.blocks_move(cell) and not is_nest_at(cell) and not terrain.is_collapsed(cell) and (unit.element_type == "water" or not terrain.is_deep_water(cell))


func can_traverse_voluntarily(unit: CombatUnit, cell: Vector2i) -> bool:
	if unit == null or not GridSpec.is_inside(cell) or terrain.blocks_move(cell) or is_nest_at(cell) or terrain.is_collapsed(cell) or (unit.element_type != "water" and terrain.is_deep_water(cell)):
		return false
	var occupant: CombatUnit = unit_at(cell)
	return occupant == null or unit.team == "player" and occupant.team == "player"


func can_player_move(unit: CombatUnit, target: Vector2i) -> bool:
	return not get_move_path(unit, target).is_empty()


func get_move_path(unit: CombatUnit, target: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not _can_player_act(unit) or unit.move_points <= 0:
		return empty
	return MovementPathfinder.find_path(self, unit, target, unit.move_points)


func preview_push(unit: CombatUnit, target: CombatUnit) -> Dictionary:
	return PushResolver.preview(self, unit, target) if target != null and can_use_skill(unit, "rock_push", target.cell) else {}


func enemy_move_cells(enemy: CombatUnit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if enemy == null or enemy.team != "enemy" or not enemy.is_alive():
		return cells
	var limit: int = effective_move_range(enemy)
	var frontier: Array[Dictionary] = [{"cell": enemy.cell, "steps": 0}]
	var visited: Dictionary = {enemy.cell: true}
	while not frontier.is_empty():
		var entry: Dictionary = frontier.pop_front()
		if int(entry["steps"]) >= limit:
			continue
		for direction in CARDINAL_DIRECTIONS:
			var next_cell: Vector2i = entry["cell"] + direction
			if visited.has(next_cell) or not can_enter_voluntarily(enemy, next_cell):
				continue
			visited[next_cell] = true
			cells.append(next_cell)
			frontier.append({"cell": next_cell, "steps": int(entry["steps"]) + 1})
	return cells


func can_undo_move() -> bool:
	return not movement_undo_locked and not movement_history.is_empty() and not reward_claimed and (phase == "player" or (phase == "finished" and outcome == "defeat"))


func undo_last_move() -> bool:
	if not can_undo_move():
		return false
	var snapshot: Dictionary = movement_history.pop_back()
	var unit: CombatUnit = unit_by_id(snapshot["unit_id"])
	unit.cell = snapshot["cell"]
	unit.hp = snapshot["hp"]
	unit.burned = snapshot["burned"]
	unit.burn_damage_from_round = snapshot["burn_damage_from_round"]
	unit.move_points = snapshot["move_points"]
	phase = snapshot["phase"]
	outcome = snapshot["outcome"]
	events.resize(snapshot["event_count"])
	_log("撤回 %s 的移动，恢复位置、生命值和移动机会。" % unit.display_name)
	return true


func _lock_movement_undo() -> void:
	movement_history.clear()
	movement_undo_locked = true


func try_player_move(unit_id: String, target: Vector2i) -> bool:
	var unit: CombatUnit = unit_by_id(unit_id)
	var path: Array[Vector2i] = get_move_path(unit, target)
	if path.is_empty():
		_log("无法移动：终点不能被占用，路线不能穿过敌人或禁入地形，也不能超出当前移动上限；每回合只能移动一次。")
		return false
	if not movement_undo_locked:
		movement_history.append({"unit_id": unit.unit_id, "cell": unit.cell, "hp": unit.hp, "burned": unit.burned, "burn_damage_from_round": unit.burn_damage_from_round, "move_points": unit.move_points, "phase": phase, "outcome": outcome, "event_count": events.size()})
	unit.move_points = 0
	_log("%s 开始一次性移动，路线长度 %d 格。" % [unit.display_name, path.size()])
	for cell in path:
		unit.cell = cell
		_apply_entry_effects(unit)
		if not unit.is_alive() or outcome != "":
			break
	_log("%s 移动结束于 (%d, %d)。" % [unit.display_name, unit.cell.x + 1, unit.cell.y + 1])
	return true


func effective_skill_range(unit: CombatUnit, skill_id: String) -> int:
	if unit == null or not CombatConfig.SKILLS.has(skill_id):
		return 0
	return int(CombatConfig.SKILLS[skill_id]["range"])


func effective_move_range(unit: CombatUnit) -> int:
	return maxi(0, unit.base_move - (CombatConfig.WET_MOVE_PENALTY if unit.wet and turn_number >= unit.wet_move_from_round else 0)) if unit != null else 0


func projected_skill_impact(unit: CombatUnit, skill_id: String, target: Vector2i) -> Vector2i:
	var invalid := Vector2i(-1, -1)
	if unit == null or not unit.is_alive() or not unit.skill_ids.has(skill_id) or not CombatConfig.SKILLS.has(skill_id) or not GridSpec.is_inside(target):
		return invalid
	if terrain.is_steam(unit.cell):
		return invalid
	if skill_id == "rock_create":
		return target if distance(unit.cell, target) == 1 and effective_skill_range(unit, skill_id) >= 1 else invalid
	if skill_id == "flame_charge":
		return target if distance(unit.cell, target) == 2 and (unit.cell.x == target.x or unit.cell.y == target.y) and unit_at(target) == null and terrain.object_at(target).is_empty() and not is_nest_at(target) else invalid
	var skill: Dictionary = CombatConfig.SKILLS[skill_id]
	var target_distance: int = distance(unit.cell, target)
	if target_distance < int(skill.get("min_range", 1)) or target_distance > effective_skill_range(unit, skill_id):
		return invalid
	if skill_id == "rain_call":
		return target
	if target_distance == 0:
		return invalid
	if skill.get("axis", false) and unit.cell.x != target.x and unit.cell.y != target.y:
		return invalid
	if skill_id in ["fire_burst", "water_flow"]:
		var delta: Vector2i = target - unit.cell
		var direction := Vector2i(signi(delta.x), signi(delta.y))
		var cell: Vector2i = unit.cell + direction
		while true:
			if unit_at(cell) != null or not terrain.object_at(cell).is_empty() or is_nest_at(cell) or cell == target:
				return cell if distance(unit.cell, cell) >= int(skill.get("min_range", 1)) else invalid
			cell += direction
	if not skill.get("ignores_obstacles", false) and (terrain.ranged_blocker(unit.cell, target) != "" or _nest_blocks_ray(unit.cell, target)):
		return invalid
	return target


func can_use_skill(unit: CombatUnit, skill_id: String, target: Vector2i) -> bool:
	if unit == null or not unit.is_alive() or outcome != "" or not unit.skill_ids.has(skill_id) or not CombatConfig.SKILLS.has(skill_id) or not GridSpec.is_inside(target):
		return false
	if unit.team == "player" and phase != "player":
		return false
	if unit.team == "enemy" and phase != "enemy_attack":
		return false
	if not can_act_now(unit):
		return false
	var skill: Dictionary = CombatConfig.SKILLS[skill_id]
	if unit.skill_points < int(skill["cost"]):
		return false
	var impact: Vector2i = projected_skill_impact(unit, skill_id, target)
	if impact == Vector2i(-1, -1):
		return false
	if skill_id == "rock_push":
		var victim: CombatUnit = unit_at(impact)
		return (victim != null and victim.team != unit.team) or is_nest_at(impact)
	return true


func try_use_skill(unit_id: String, skill_id: String, target: Vector2i) -> bool:
	var unit: CombatUnit = unit_by_id(unit_id)
	if not can_use_skill(unit, skill_id, target) or (unit.team == "enemy" and phase != "enemy_attack"):
		_log("无法施放技能：检查技能点、目标、射程和遮挡；站在蒸汽雾中不能施法。")
		return false
	if unit.team == "player":
		_lock_movement_undo()
	unit.skill_points -= int(CombatConfig.SKILLS[skill_id]["cost"])
	var impact: Vector2i = projected_skill_impact(unit, skill_id, target)
	if impact != target:
		_log("%s 的 %s 被 (%d, %d) 的遮挡截断。" % [unit.display_name, CombatConfig.SKILLS[skill_id]["name"], impact.x + 1, impact.y + 1])
	if skill_id == "rock_push":
		if is_nest_at(target):
			hit_cell(target, int(CombatConfig.SKILLS[skill_id]["damage"]), "推击")
			_check_outcome()
		else:
			_resolve_push(unit, unit_at(target))
	else:
		begin_environment_resolution()
		EnvironmentResolver.apply_skill(self, unit, skill_id, impact)
		end_environment_resolution()
	return true


func can_capture(target: CombatUnit) -> bool:
	return CaptureSystem.can_capture(self, target)


func capture_chance(target: CombatUnit) -> float:
	return CaptureSystem.chance(target)


func try_capture(target_id: String) -> bool:
	var target: CombatUnit = unit_by_id(target_id)
	if not can_capture(target):
		_log("无法捕获：训练家须与存活野生怪物相邻、目标生命不高于一半，且本回合仍有捕获机会。")
		return false
	_lock_movement_undo()
	var trainer: CombatUnit = unit_by_id("trainer")
	trainer.capture_points -= 1
	var chance: float = capture_chance(target)
	if capture_rng.randf() >= chance:
		_log("捕获 %s 失败（本次成功率 %d%%）；本回合捕获机会已用。" % [target.display_name, roundi(chance * 100.0)])
		return false
	captured_records.append({"enemy_id": target.unit_id, "species_id": target.element_type})
	target.hp = 0
	_log("成功捕获 %s！战后加入本局携带队伍；满员时先进入待收容。" % target.display_name)
	if environment_resolution_depth == 0:
		_check_outcome()
	return true


func _resolve_push(unit: CombatUnit, victim: CombatUnit) -> void:
	_resolve_push_direction(unit, victim, victim.cell - unit.cell, int(CombatConfig.SKILLS["rock_push"]["damage"]), "推击")


func _resolve_push_direction(unit: CombatUnit, victim: CombatUnit, direction: Vector2i, damage: int, source_name: String) -> void:
	var result: Dictionary = PushResolver.preview_direction(self, victim, direction, damage)
	var obstacle_cell: Vector2i = victim.cell + direction
	var old_cell: Vector2i = victim.cell
	victim.cell = result["destination"]
	_log("%s 对 %s 使用%s：%s。" % [unit.display_name, victim.display_name, source_name, result["description"]])
	_damage_reward_at(old_cell)
	if result["target_damage"] > 0:
		_apply_damage(victim, result["target_damage"], source_name + "及碰撞")
	var collision_unit: CombatUnit = result["collision_unit"]
	if collision_unit != null and result["other_damage"] > 0:
		_apply_damage(collision_unit, result["other_damage"], "碰撞")
		_damage_reward_at(collision_unit.cell)
	if result["collision_object"]:
		if is_nest_at(obstacle_cell):
			hit_cell(obstacle_cell, CombatConfig.PUSH_OBJECT_DAMAGE, "撞击巢穴")
		else:
			EnvironmentResolver.on_push_obstacle(self, obstacle_cell)
	if victim.is_alive() and victim.cell != old_cell:
		_apply_entry_effects(victim)
	if environment_resolution_depth == 0:
		_check_outcome()


func resolve_water_flow(caster: CombatUnit, target: Vector2i) -> void:
	terrain.extinguish_fire(target)
	var victim: CombatUnit = unit_at(target)
	var obstacle_hit: bool = not terrain.object_at(target).is_empty() or is_nest_at(target)
	if victim != null:
		var direction: Vector2i = target - caster.cell
		direction = Vector2i(signi(direction.x), signi(direction.y))
		_resolve_push_direction(caster, victim, direction, int(CombatConfig.SKILLS["water_flow"]["damage"]), "水流")
		apply_skill_wet(victim)
	else:
		hit_cell(target, int(CombatConfig.SKILLS["water_flow"]["damage"]), "水流")
		var object_result: Dictionary = terrain.damage_object(target, int(CombatConfig.SKILLS["water_flow"]["damage"]))
		if not object_result.is_empty():
			_log("水流命中%s，造成 1 耐久伤害（剩余 %d）。" % ["岩石" if object_result["type"] == "rock" else "树木", object_result["hp"]])
	if victim == null:
		var water_cell: Vector2i = target
		if obstacle_hit:
			var direction_to_target: Vector2i = target - caster.cell
			water_cell -= Vector2i(signi(direction_to_target.x), signi(direction_to_target.y))
		if terrain.set_water(water_cell):
			_log("水流在 (%d, %d) 形成浅水。" % [water_cell.x + 1, water_cell.y + 1])
			var occupant: CombatUnit = unit_at(water_cell)
			if occupant != null:
				_apply_entry_effects(occupant)


func apply_skill_burn(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive() or unit.element_type == "fire":
		return
	if not unit.burned:
		unit.burn_damage_from_round = turn_number + 1
	unit.burned = true
	_log("%s 获得灼烧；下一次完整回合结算起每轮失去 1 HP。" % unit.display_name)


func apply_skill_wet(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive() or unit.element_type == "water":
		return
	unit.wet = true
	unit.skill_wet_through_round = maxi(unit.skill_wet_through_round, turn_number + 1)
	unit.wet_move_from_round = turn_number + 1
	_log("%s 获得浸湿；下一轮移动力 -1。" % unit.display_name)


func resolve_flame_charge(caster: CombatUnit, target: Vector2i) -> void:
	var direction: Vector2i = (target - caster.cell) / 2
	var middle: Vector2i = caster.cell + direction
	var passed_unit: CombatUnit = unit_at(middle)
	if passed_unit != null:
		apply_skill_burn(passed_unit)
	caster.cell = target
	_log("%s 闪焰冲锋至 (%d, %d)。" % [caster.display_name, target.x + 1, target.y + 1])
	_apply_entry_effects(caster)


func finish_player_turn() -> bool:
	if phase != "player" or outcome != "":
		return false
	_lock_movement_undo()
	_log("我方回合结束，未使用的行动已放弃。")
	var enemy_ids: Array[String] = []
	for unit in units:
		if unit.team == "enemy" and unit.is_alive() and unit.eligible_round <= turn_number:
			enemy_ids.append(unit.unit_id)
	var ai := EnemyAI.new()
	for enemy_id in enemy_ids:
		if outcome != "":
			break
		var enemy: CombatUnit = unit_by_id(enemy_id)
		if enemy == null or not enemy.is_alive():
			continue
		phase = "enemy_move"
		_log("%s 开始行动：先移动。" % enemy.display_name)
		ai.move_phase(self, [enemy_id])
		if outcome != "" or not enemy.is_alive():
			continue
		phase = "enemy_attack"
		_log("%s 准备施放技能。" % enemy.display_name)
		ai.attack_phase(self, [enemy_id])
	var expired_rocks: Array[Vector2i] = terrain.expire_temporary_rocks(turn_number)
	if not expired_rocks.is_empty():
		_log("敌方行动结束，%d 处临时岩石消失。" % expired_rocks.size())
	if outcome == "":
		_settle_round_and_continue()
	return true


func _start_round() -> void:
	movement_history.clear()
	movement_undo_locked = false
	if turn_number in [2, 4]:
		_spawn_from_nest()
	if outcome != "":
		return
	phase = "player"
	_log("第 %d 回合：我方整队行动。" % turn_number)


func _settle_round_and_continue() -> void:
	phase = "round_settlement"
	begin_environment_resolution()
	EnvironmentResolver.settle_round(self)
	end_environment_resolution()
	if outcome != "":
		return
	if turn_number >= CombatConfig.MAX_PLAYER_ROUNDS:
		for unit in units:
			if unit.team == "enemy" and unit.is_alive():
				escaped_enemy_ids.append(unit.unit_id)
				unit.hp = 0
		outcome = "escape"
		phase = "finished"
		_log("第 %d 回合结算完毕：剩余 %d 只野生怪物逃离，战斗结束。" % [turn_number, escaped_enemy_ids.size()])
		return
	turn_number += 1
	for unit in units:
		if unit.is_alive():
			unit.move_points = effective_move_range(unit)
			if unit.team == "player":
				if unit.unit_id == "trainer":
					unit.capture_points = CombatConfig.CAPTURE_ATTEMPTS_PER_TURN
			unit.skill_points = 0 if unit.unit_id == "trainer" else CombatConfig.SKILL_POINTS_PER_TURN
	_start_round()


func enemy_move(enemy: CombatUnit, target: Vector2i) -> bool:
	var path: Array[Vector2i] = [target]
	return enemy_move_path(enemy, path)


func enemy_move_path(enemy: CombatUnit, path: Array[Vector2i], birth_move: bool = false) -> bool:
	if enemy == null or enemy.team != "enemy" or not enemy.is_alive() or outcome != "" or path.is_empty() or path.size() > enemy.move_points:
		return false
	if birth_move:
		if enemy.eligible_round != turn_number + 1:
			return false
	elif phase != "enemy_move" or not can_act_now(enemy):
		return false
	var previous: Vector2i = enemy.cell
	for cell in path:
		if distance(previous, cell) != 1 or not can_enter_voluntarily(enemy, cell):
			return false
		previous = cell
	enemy.move_points = 0
	for cell in path:
		enemy.cell = cell
		_apply_entry_effects(enemy)
		if not enemy.is_alive() or outcome != "":
			break
	_log("%s 移动 %d 格到 (%d, %d)。" % [enemy.display_name, path.size(), enemy.cell.x + 1, enemy.cell.y + 1])
	return true


func _spawn_from_nest() -> void:
	if nest.is_empty() or int(nest.get("hp", 0)) <= 0:
		return
	var exit_cell: Vector2i = nest["exit"]
	if unit_at(exit_cell) != null or terrain.blocks_move(exit_cell) or terrain.is_deep_water(exit_cell) or terrain.is_collapsed(exit_cell):
		_log("巢穴出口被堵住，本次未生成敌人。")
		return
	var species: Array[String] = ["fire", "water", "rock"]
	var species_id: String = species[spawn_rng.randi_range(0, species.size() - 1)]
	spawned_count += 1
	var spawned: CombatUnit = MonsterCatalog.make_enemy("nest_%d_%d" % [turn_number, spawned_count], species_id, exit_cell)
	spawned.eligible_round = turn_number + 1
	spawned.skill_points = 0
	units.append(spawned)
	_log("巢穴在第 %d 回合生成了 %s：先移动一次，本轮不施法。" % [turn_number, spawned.display_name])
	var path: Array[Vector2i] = EnemyAI.new().plan_move(self, spawned)
	if not path.is_empty():
		enemy_move_path(spawned, path, true)


func _can_player_act(unit: CombatUnit) -> bool:
	return phase == "player" and unit != null and unit.team == "player" and can_act_now(unit)


func _apply_damage(target: CombatUnit, damage: int, source_name: String) -> void:
	target.hp = maxi(0, target.hp - damage)
	_log("%s 攻击 %s，造成 %d 伤害（%d/%d HP）。" % [source_name, target.display_name, damage, target.hp, target.max_hp])
	if not target.is_alive():
		_log("%s 被击败。" % target.display_name)
		if reward_state == "carried" and reward_carrier_id == target.unit_id:
			reward_state = "destroyed"
			reward_carrier_id = ""
			_log("奖励携带者倒下，额外奖励被摧毁。")
		if target.team == "enemy" and not defeated_enemy_ids.has(target.unit_id):
			defeated_enemy_ids.append(target.unit_id)


func _apply_entry_effects(unit: CombatUnit) -> void:
	if terrain.is_water(unit.cell):
		unit.burned = false
		unit.burn_damage_from_round = 0
	if terrain.is_deep_water(unit.cell) and unit.element_type != "water":
		_apply_damage(unit, unit.hp, "深水淹没")
		_log("%s 进入深水，立即淹没。" % unit.display_name)
	elif terrain.is_collapsed(unit.cell):
		_apply_damage(unit, unit.hp, "塌陷深坑")
		_log("%s 进入塌陷深坑，立即坠落。" % unit.display_name)
	if environment_resolution_depth == 0:
		_check_outcome()


func is_nest_at(cell: Vector2i) -> bool:
	return not nest.is_empty() and int(nest.get("hp", 0)) > 0 and nest["cell"] == cell


func _nest_blocks_ray(start: Vector2i, target: Vector2i) -> bool:
	if nest.is_empty() or start.x != target.x and start.y != target.y:
		return false
	var delta: Vector2i = target - start
	var direction := Vector2i(signi(delta.x), signi(delta.y))
	var cell: Vector2i = start + direction
	while cell != target:
		if is_nest_at(cell):
			return true
		cell += direction
	return false


func _damage_reward_at(cell: Vector2i) -> void:
	if reward_state == "ground" and reward_cell == cell:
		reward_state = "destroyed"
		_log("地面奖励受到伤害，已被摧毁。")


func hit_cell(cell: Vector2i, damage: int, source_name: String, ground_strike: bool = false) -> void:
	if damage <= 0:
		return
	_damage_reward_at(cell)
	if ground_strike:
		collapse_fragile(cell, source_name)
	if is_nest_at(cell):
		nest["hp"] = maxi(0, int(nest["hp"]) - damage)
		_log("%s 命中巢穴，造成 %d 伤（剩余 %d 耐久）。" % [source_name, damage, nest["hp"]])
		if nest["hp"] <= 0:
			_log("巢穴被摧毁，之后不再生成敌人。")
	var victim: CombatUnit = unit_at(cell)
	if victim != null:
		_apply_damage(victim, damage, source_name)
	if environment_resolution_depth == 0:
		_check_outcome()


func collapse_fragile(cell: Vector2i, source_name: String) -> bool:
	if not terrain.collapse_fragile(cell):
		return false
	_damage_reward_at(cell)
	_log("%s 击碎易碎地块 (%d, %d)，留下永久深坑。" % [source_name, cell.x + 1, cell.y + 1])
	var victim: CombatUnit = unit_at(cell)
	if victim != null:
		_apply_damage(victim, victim.hp, "地块塌陷")
	if environment_resolution_depth == 0:
		_check_outcome()
	return true


func settle_reward_pickup() -> void:
	if reward_state != "ground":
		return
	var carrier: CombatUnit = unit_at(reward_cell)
	if carrier != null and carrier.team == "player":
		reward_state = "carried"
		reward_carrier_id = carrier.unit_id
		_log("%s 拾取额外环境卡奖励；若在战斗结束前倒下，奖励会失去。" % carrier.display_name)


func bonus_card_earned() -> bool:
	var carrier: CombatUnit = unit_by_id(reward_carrier_id)
	return reward_state == "carried" and carrier != null and carrier.is_alive() and outcome != "defeat"


func reward_carrier() -> CombatUnit:
	return unit_by_id(reward_carrier_id) if reward_state == "carried" else null


func apply_environment_damage(unit: CombatUnit, amount: int, source_name: String) -> void:
	if unit == null or not unit.is_alive() or outcome != "":
		return
	_apply_damage(unit, amount, source_name)
	if environment_resolution_depth == 0:
		_check_outcome()


func begin_environment_resolution() -> void:
	environment_resolution_depth += 1


func end_environment_resolution() -> void:
	environment_resolution_depth -= 1
	if environment_resolution_depth == 0:
		_check_outcome()


func _check_outcome() -> void:
	var trainer: CombatUnit = unit_by_id("trainer")
	if trainer == null or not trainer.is_alive():
		outcome = "defeat"
		phase = "finished"
		_log("战斗失败：训练家被击败。")
		return
	for unit in units:
		if unit.team == "enemy" and unit.is_alive():
			return
	outcome = "victory"
	phase = "finished"
	_log("战斗胜利：所有敌人已被击败。")


func _log(message: String) -> void:
	events.append(message)


func add_event(message: String) -> void:
	_log(message)
