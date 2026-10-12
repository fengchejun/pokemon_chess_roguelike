class_name BattleState
extends RefCounted

## 一场战斗的全部状态与规则入口。
## 回合结构：我方阶段（自由顺序）→ 敌方阶段（固定顺序执行预告的同一计划）→ 环境结算 → 下一回合。
## 第 MAX_ROUNDS 回合结算后仍存活的野生宝可梦逃离。

const PHASE_PLAYER := "player"
const PHASE_ENEMY := "enemy"
const PHASE_SETTLE := "settle"
const PHASE_ENDED := "ended"

var run_seed: int = 0
var battle_index: int = 0
var round: int = 0
var phase: String = PHASE_PLAYER
var ended: bool = false
var end_reason: String = ""

var terrain: Array = []
var obstacle_durability: Dictionary = {}
var obstacle_origin: Dictionary = {}
var obstacle_expire_round: Dictionary = {}
var nest: Dictionary = {}
var reward: Dictionary = {}
var fruits: Array = []
var units: Array = []
var deploy_cells: Array = []

var next_enemy_uid: int = 100
var events: Array = []
var deaths: Array = []
var enemy_kills: Array = []
var captured: Array = []
var effects: Dictionary = {}
var upgrades: Dictionary = {}
var capture_options: Dictionary = {}
var reinforcement_pool: Array = []
var undo_stack: Array = []
var spawn_rng := RandomNumberGenerator.new()
var capture_rng := RandomNumberGenerator.new()

var _pending_actions: Array = []
var _pending_index: int = 0
var _forecast_cache: Array = []
var _forecast_signature: String = ""


func setup(map_data: Dictionary, cfg: Dictionary, seed_value: int, battle_index_value: int, player_units: Array, effects_value: Dictionary, upgrades_value: Dictionary, pool_value: Array, capture_options_value: Dictionary = {}) -> void:
	run_seed = seed_value
	battle_index = battle_index_value
	effects = effects_value.duplicate()
	upgrades = upgrades_value.duplicate()
	capture_options = capture_options_value.duplicate()
	reinforcement_pool = pool_value.duplicate()
	load_map(map_data)
	deploy_cells = map_data.get("deploy_cells", Balance.DEPLOY_CELLS.duplicate())
	var slot := 0
	for unit in player_units:
		if slot >= deploy_cells.size():
			break
		unit.cell = deploy_cells[slot]
		unit.reg_index = units.size()
		units.append(unit)
		slot += 1
	for pair in cfg.get("enemies", []):
		var enemy := CombatUnit.make(pair[0], "enemy", next_enemy_uid)
		next_enemy_uid += 1
		enemy.cell = pair[1]
		enemy.reg_index = units.size()
		units.append(enemy)
	spawn_rng.seed = hash("spawn:%d:%d" % [seed_value, battle_index_value])
	capture_rng.seed = hash("capture:%d:%d" % [seed_value, battle_index_value])
	log_event("战斗开始：%s，敌方 %d 只。" % [String(cfg.get("region", "?")), cfg.get("enemies", []).size()])
	start_round()


func capture_roll() -> float:
	return capture_rng.randf()


func load_map(map_data: Dictionary) -> void:
	terrain = map_data["terrain"].duplicate()
	obstacle_durability = {}
	obstacle_origin = {}
	obstacle_expire_round = {}
	for cell in map_data.get("obstacle_cells", []):
		obstacle_durability[cell] = Balance.OBSTACLE_DURABILITY
	nest = {
		"cell": map_data["nest_cell"],
		"exits": map_data["nest_exits"].duplicate(),
		"hp": Balance.NEST_DURABILITY,
		"alive": true,
	}
	reward = {
		"state": "map",  # map / carried / dropped / gone
		"cell": map_data["reward_cell"],
		"carrier_uid": -1,
	}
	fruits = map_data.get("fruit_cells", []).duplicate()


# ---------------------------------------------------------------- 查询

func terrain_at(cell: Vector2i) -> int:
	return int(terrain[GridSpec.index(cell)])


func set_terrain(cell: Vector2i, value: int) -> void:
	terrain[GridSpec.index(cell)] = value


func is_nest_cell(cell: Vector2i) -> bool:
	return bool(nest.get("alive", false)) and nest["cell"] == cell


func unit_at(cell: Vector2i) -> CombatUnit:
	for unit in units:
		if unit.is_alive() and unit.cell == cell:
			return unit
	return null


func unit_by_uid(uid: int) -> CombatUnit:
	for unit in units:
		if unit.uid == uid:
			return unit
	return null


func alive_units(side: String = "") -> Array:
	var result: Array = []
	for unit in units:
		if unit.is_alive() and (side == "" or unit.side == side):
			result.append(unit)
	return result


func trainer() -> CombatUnit:
	for unit in units:
		if unit.is_trainer:
			return unit
	return null


func carrier_uid() -> int:
	if reward.get("state", "") == "carried":
		return int(reward.get("carrier_uid", -1))
	return -1


func is_blocking_ray(cell: Vector2i) -> bool:
	if terrain_at(cell) == TerrainDB.OBSTACLE:
		return true
	if is_nest_cell(cell):
		return true
	return unit_at(cell) != null


func move_cost_for(unit: CombatUnit, cell: Vector2i) -> int:
	## 主动移动进入该格的消耗；-1 表示不可进入。
	## 潮汐效果：我方单位进入水面不额外消耗移动力。
	var terrain := terrain_at(cell)
	if terrain == TerrainDB.WATER and unit.side == "player" and int(effects.get("water_ignore", 0)) > 0:
		return 1
	return TerrainDB.move_cost(terrain, unit.element)


func move_budget_for(unit: CombatUnit) -> int:
	## 移动预算的统一入口（寻路与界面共用；未来的机动类效果在此接线）。
	return unit.effective_move()


func adjacent_to_terrain(unit: CombatUnit, terrain_value: int) -> bool:
	for cell in GridSpec.neighbors4(unit.cell):
		if terrain_at(cell) == terrain_value:
			return true
	return false


func adjacent_to_obstacle(unit: CombatUnit) -> bool:
	return adjacent_to_terrain(unit, TerrainDB.OBSTACLE)


func has_hazard_guard(unit: CombatUnit) -> bool:
	## 熔脉 / 潮汐：紧邻致死地形的我方单位不被强制位移。
	if unit.side != "player":
		return false
	if int(effects.get("deep_guard", 0)) > 0 and adjacent_to_terrain(unit, TerrainDB.DEEP):
		return true
	if int(effects.get("lava_guard", 0)) > 0 and adjacent_to_terrain(unit, TerrainDB.LAVA):
		return true
	return false


func alive_enemy_count() -> int:
	var count := 0
	for unit in units:
		if unit.side == "enemy" and unit.is_alive():
			count += 1
	return count


# ---------------------------------------------------------------- 日志与死亡

func log_event(text: String) -> void:
	var tag := "准备"
	match phase:
		PHASE_PLAYER:
			tag = "我方"
		PHASE_ENEMY:
			tag = "敌方"
		PHASE_SETTLE:
			tag = "结算"
		PHASE_ENDED:
			tag = "结束"
	events.append("[第%d回合·%s] %s" % [maxi(1, round), tag, text])


func kill_unit(unit: CombatUnit, cause: String, killer_side: String = "") -> void:
	if unit.is_trainer:
		return
	unit.hp = 0
	if unit.side == "player":
		deaths.append({
			"uid": unit.uid,
			"species_id": unit.species_id,
			"name": unit.display_name,
			"cause": cause,
			"battle": battle_index + 1,
			"cell": unit.cell,
		})
		log_event("%s 倒下（濒死）（%s），可在基地休养恢复。" % [unit.display_name, cause])
	else:
		enemy_kills.append({
			"species_id": unit.species_id,
			"by_player": killer_side == "player",
			"cause": cause,
		})
		log_event("野生 %s 被击败（%s）。" % [unit.display_name, cause])
	if reward.get("state", "") == "carried" and int(reward["carrier_uid"]) == unit.uid:
		reward["state"] = "dropped"
		reward["cell"] = unit.cell
		reward["carrier_uid"] = -1
		log_event("奖励从 %s 身上掉落。" % unit.display_name)


func on_captured(unit: CombatUnit, species_id: String, keep_hp: int) -> void:
	var field_join := bool(capture_options.get("capture_field_join", false))
	captured.append({"species_id": species_id, "hp": keep_hp, "uid": unit.uid, "on_field": field_join})
	if field_join:
		unit.side = "player"
		unit.hp = keep_hp
		unit.moved = false
		unit.skill_used = false
		unit.capture_used = false
		unit.fresh_spawn = false
		log_event("%s 被捕获，原地加入我方，本回合可移动和施法。" % unit.display_name)
	else:
		unit.hp = 0
		log_event("%s 被捕获，离开战场。" % unit.display_name)
	if reward.get("state", "") == "carried" and int(reward["carrier_uid"]) == unit.uid:
		reward["state"] = "dropped"
		reward["cell"] = unit.cell
		reward["carrier_uid"] = -1


# ---------------------------------------------------------------- 伤害

func damage_unit(source: CombatUnit, target: CombatUnit, base: int, opts: Dictionary) -> Dictionary:
	if target == null or not target.is_alive() or base <= 0:
		return {"amount": 0, "killed": false}
	var amount := base
	var is_lethal_check := true
	if not bool(opts.get("no_element", false)):
		var skill_element: String = opts.get("element", "")
		amount = maxi(1, amount + Elements.modifier(skill_element, target.element))
		if skill_element == "fire" and int(effects.get("fire_bonus", 0)) > 0:
			if source != null and source.side == "player":
				amount += int(effects["fire_bonus"])
	var target_in_grass := GridSpec.is_inside(target.cell) and terrain_at(target.cell) == TerrainDB.GRASS
	if bool(opts.get("ranged", false)) and target.side == "player":
		## 密林（草丛中）与岩脊（障碍旁）的远程减伤取其一，不叠加。
		var covered := false
		if target_in_grass and int(effects.get("grass_reduction", 0)) > 0:
			covered = true
		if int(effects.get("obstacle_cover", 0)) > 0 and adjacent_to_obstacle(target):
			covered = true
		if covered:
			amount = maxi(0, amount - 1)
	if source != null and source.side == "player" and int(effects.get("grass_strike", 0)) > 0:
		## 密林：站在草丛中的我方单位造成的直接伤害 +1。
		if not bool(opts.get("no_element", false)):
			if GridSpec.is_inside(source.cell) and terrain_at(source.cell) == TerrainDB.GRASS:
				amount += int(effects["grass_strike"])
	amount = maxi(0, amount)
	var cause: String = opts.get("cause", "伤害")
	var previous_hp := target.hp
	target.hp -= amount
	var source_name := source.display_name if source != null else "环境"
	log_event("%s 对 %s 造成 %d 伤害。" % [source_name, target.display_name, amount])
	var killed := false
	if target.is_trainer and target.hp <= 0:
		target.hp = 1
		log_event("训练家倒下！以 1 生命保留，战斗强制撤退（视为失败）。")
		end_battle("forced_retreat")
		return {"amount": amount, "killed": false}
	if target.hp <= 0:
		killed = true
		var killer_side: String = source.side if source != null else String(opts.get("killer_side", ""))
		kill_unit(target, cause, killer_side)
	return {"amount": amount, "killed": killed, "previous_hp": previous_hp, "hp": target.hp}


func apply_burn(target: CombatUnit, source: CombatUnit) -> void:
	if target.element == "fire":
		return
	if not target.is_alive():
		return
	var burn_ticks := Balance.BURN_TICKS
	target.burn_ticks = burn_ticks
	target.burn_source_uid = source.uid if source != null else -1
	target.burn_source_side = source.side if source != null else ""
	log_event("%s 被点燃（灼烧 %d 回合）。" % [target.display_name, burn_ticks])


func apply_root(target: CombatUnit) -> void:
	target.root_pending = true
	log_event("%s 被定身：下一次移动机会将被取消。" % target.display_name)


func apply_slow(target: CombatUnit) -> void:
	target.slow_ticks = 2
	log_event("%s 被减速 1 回合。" % target.display_name)


func damage_obstacle(cell: Vector2i, amount: int) -> bool:
	if not obstacle_durability.has(cell):
		return false
	var left := int(obstacle_durability[cell]) - amount
	if left <= 0:
		obstacle_durability.erase(cell)
		var origin := int(obstacle_origin.get(cell, TerrainDB.PLAIN))
		obstacle_origin.erase(cell)
		obstacle_expire_round.erase(cell)
		set_terrain(cell, origin)
		log_event("障碍被破坏，恢复为%s。" % TerrainDB.name_of(origin))
		return true
	obstacle_durability[cell] = left
	log_event("障碍耐久 -%d（剩 %d）。" % [amount, left])
	return false


func damage_nest(amount: int) -> bool:
	if not bool(nest.get("alive", false)):
		return false
	nest["hp"] = int(nest["hp"]) - amount
	if int(nest["hp"]) <= 0:
		nest["alive"] = false
		set_terrain(nest["cell"], TerrainDB.PLAIN)
		log_event("巢穴被摧毁，永久停止生成。")
		return true
	log_event("巢穴耐久 -%d（剩 %d）。" % [amount, nest["hp"]])
	return false


func place_temp_obstacle(cell: Vector2i, origin: int, expire_round: int) -> void:
	terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
	obstacle_durability[cell] = Balance.OBSTACLE_DURABILITY
	obstacle_origin[cell] = origin
	obstacle_expire_round[cell] = expire_round


# ---------------------------------------------------------------- 我方移动

func move_options(unit: CombatUnit) -> Dictionary:
	if not unit.can_move_now():
		return {}
	return PathFinder.stop_cells(self, unit)


func move_unit(unit: CombatUnit, dest: Vector2i) -> bool:
	if phase != PHASE_PLAYER or ended or not unit.can_move_now():
		return false
	var options := PathFinder.stop_cells(self, unit)
	if not options.has(dest):
		return false
	var path: Array = options[dest]["path"]
	var from_cell := unit.cell
	var burn_ticks_before := unit.burn_ticks
	var burn_source_uid_before := unit.burn_source_uid
	var burn_source_side_before := unit.burn_source_side
	for step in path:
		unit.cell = step
		if terrain_at(step) == TerrainDB.WATER or terrain_at(step) == TerrainDB.DEEP:
			if unit.burn_ticks > 0:
				log_event("%s 进入水域，灼烧解除。" % unit.display_name)
			unit.burn_ticks = 0
	unit.moved = true
	var pickup := try_pickup_fruit(unit)
	undo_stack.append({
		"uid": unit.uid,
		"from": from_cell,
		"burn_ticks": burn_ticks_before,
		"burn_source_uid": burn_source_uid_before,
		"burn_source_side": burn_source_side_before,
		"fruit_cell": pickup.get("cell", Vector2i(-1, -1)),
		"fruit_gained": int(pickup.get("gained", 0)),
	})
	log_event("%s 移动到 (%d,%d)。" % [unit.display_name, dest.x, dest.y])
	return true


func undo_last_move() -> bool:
	if phase != PHASE_PLAYER or ended or undo_stack.is_empty():
		return false
	var entry: Dictionary = undo_stack.pop_back()
	var unit := unit_by_uid(int(entry["uid"]))
	if unit == null:
		return false
	unit.cell = entry["from"]
	unit.burn_ticks = int(entry["burn_ticks"])
	unit.burn_source_uid = int(entry["burn_source_uid"])
	unit.burn_source_side = String(entry["burn_source_side"])
	var fruit_cell: Vector2i = entry.get("fruit_cell", Vector2i(-1, -1))
	if fruit_cell != Vector2i(-1, -1):
		fruits.append(fruit_cell)
		unit.hp = maxi(1, unit.hp - int(entry.get("fruit_gained", 0)))
	unit.moved = false
	log_event("%s 撤回到 (%d,%d)。" % [unit.display_name, unit.cell.x, unit.cell.y])
	return true


func commit_actions() -> void:
	undo_stack.clear()


func can_undo() -> bool:
	return phase == PHASE_PLAYER and not ended and not undo_stack.is_empty()


# ---------------------------------------------------------------- 技能与捕获

func skill_targets(unit: CombatUnit, skill_id: String) -> Array:
	return SkillResolver.targets(self, unit, skill_id)


func preview_skill(unit: CombatUnit, skill_id: String, target_entry: Dictionary) -> Dictionary:
	var clone := clone()
	var clone_unit := clone.unit_by_uid(unit.uid)
	if clone_unit == null:
		return {"ok": false}
	return SkillResolver.apply(clone, clone_unit, skill_id, target_entry, true)


func cast_skill(unit: CombatUnit, skill_id: String, target_entry: Dictionary) -> Dictionary:
	if ended or not unit.can_act_skill():
		return {"ok": false}
	var result := SkillResolver.apply(self, unit, skill_id, target_entry, false)
	if bool(result.get("ok", false)):
		unit.skill_used = true
		commit_actions()
		check_battle_end()
	return result


func capture_attempt(trainer_unit: CombatUnit, target: CombatUnit, forced_roll: float = -1.0) -> Dictionary:
	if ended:
		return {"ok": false}
	var result := CaptureSystem.attempt(self, trainer_unit, target, forced_roll)
	if bool(result.get("ok", false)):
		commit_actions()
		check_battle_end()
	return result


# ---------------------------------------------------------------- 阶段流程

func start_round() -> void:
	round += 1
	for unit in units:
		if not unit.is_alive():
			continue
		unit.moved = false
		unit.skill_used = false
		unit.capture_used = false
	for unit in units:
		if unit.move_cancelled:
			unit.move_cancelled = false
	for unit in units:
		if unit.root_pending and unit.is_alive():
			unit.root_pending = false
			unit.move_cancelled = true
			log_event("%s 受到定身影响，本回合无法移动。" % unit.display_name)
	phase = PHASE_PLAYER
	if round == 2 or round == 3:
		_try_spawn_wave()


func _try_spawn_wave() -> void:
	if not bool(nest.get("alive", false)) or reinforcement_pool.is_empty():
		return
	var species_id: String = reinforcement_pool[spawn_rng.randi_range(0, reinforcement_pool.size() - 1)]
	var candidates: Array = []
	for exit_cell in nest.get("exits", []):
		candidates.append(exit_cell)
	var ring := GridSpec.neighbors8(nest["cell"])
	ring.sort_custom(func(a, b): return _cell_order(a) < _cell_order(b))
	for cell in ring:
		candidates.append(cell)
	for cell in candidates:
		if not GridSpec.is_inside(cell):
			continue
		if is_nest_cell(cell) or terrain_at(cell) == TerrainDB.OBSTACLE:
			continue
		if unit_at(cell) != null:
			continue
		if not TerrainDB.can_stand(terrain_at(cell), SpeciesDB.element_of(species_id)):
			continue
		var enemy := CombatUnit.make(species_id, "enemy", next_enemy_uid)
		next_enemy_uid += 1
		enemy.cell = cell
		enemy.fresh_spawn = true
		enemy.reg_index = units.size()
		units.append(enemy)
		log_event("巢穴生成 1 只野生宝可梦（%s）。" % enemy.display_name)
		return
	log_event("巢穴出口被占，生成被阻止。")


func _cell_order(cell: Vector2i) -> int:
	return cell.y * GridSpec.W + cell.x


func begin_enemy_phase() -> Array:
	if ended or phase != PHASE_PLAYER:
		return []
	commit_actions()
	phase = PHASE_ENEMY
	_pending_actions = EnemyAI.plan(self)
	_pending_index = 0
	log_event("敌方开始行动（%d 个动作）。" % _pending_actions.size())
	return _pending_actions


func enemy_phase_finished() -> bool:
	return _pending_index >= _pending_actions.size()


func step_enemy_phase() -> Dictionary:
	if ended or phase != PHASE_ENEMY or enemy_phase_finished():
		return {}
	var action: Dictionary = _pending_actions[_pending_index]
	_pending_index += 1
	var unit := unit_by_uid(int(action.get("uid", -1)))
	if unit == null or not unit.is_alive():
		return action
	var path: Array = action.get("move_path", [])
	for cell in path:
		unit.cell = cell
		if terrain_at(cell) == TerrainDB.WATER or terrain_at(cell) == TerrainDB.DEEP:
			unit.burn_ticks = 0
	if not path.is_empty():
		log_event("%s 移动 %d 格。" % [unit.display_name, path.size()])
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty() and unit.can_act_skill() and not ended:
		SkillResolver.apply(self, unit, String(skill["id"]), skill["target"], false)
		unit.skill_used = true
	unit.fresh_spawn = false
	check_battle_end()
	return action


func end_enemy_phase() -> void:
	if ended:
		return
	phase = PHASE_SETTLE
	settle_round()
	if ended:
		phase = PHASE_ENDED
	else:
		start_round()


func settle_round() -> void:
	# 1. 临时障碍到期（本轮敌方阶段结束）
	for cell in obstacle_expire_round.keys().duplicate():
		if int(obstacle_expire_round[cell]) <= round:
			var origin := int(obstacle_origin.get(cell, TerrainDB.PLAIN))
			obstacle_expire_round.erase(cell)
			obstacle_origin.erase(cell)
			obstacle_durability.erase(cell)
			set_terrain(cell, origin)
			log_event("临时障碍消失（%d,%d）。" % [cell.x, cell.y])
	# 2. 灼烧伤害
	for unit in alive_units():
		if unit.burn_ticks > 0:
			var cell_terrain := terrain_at(unit.cell)
			if cell_terrain == TerrainDB.WATER or cell_terrain == TerrainDB.DEEP:
				log_event("%s 处于水域，灼烧解除。" % unit.display_name)
				unit.burn_ticks = 0
			continue
	# 3. 灼烧与状态计数
	for unit in alive_units():
		if unit.burn_ticks > 0:
			unit.burn_ticks -= 1
			damage_unit(null, unit, Balance.BURN_DAMAGE, {"no_element": true, "cause": "灼烧", "killer_side": unit.burn_source_side})
	# 4. 减速衰减
	for unit in units:
		if unit.slow_ticks > 0:
			unit.slow_ticks = maxi(0, unit.slow_ticks - 1)
	# 5. 拾取
	_pickups()
	# 6. 胜负与时限
	if check_battle_end():
		return
	if round >= Balance.MAX_ROUNDS and alive_enemy_count() > 0:
		end_battle("escape")
		return
	log_event("环境结算完成。")


func try_pickup_fruit(unit: CombatUnit) -> Dictionary:
	## 恢复果实：拾取即恢复（踩上即消耗；撤销移动时回滚）。
	if unit == null or unit.side != "player" or not unit.is_alive():
		return {}
	if not fruits.has(unit.cell):
		return {}
	var healed := mini(unit.max_hp, unit.hp + Balance.FRUIT_HEAL)
	var gained := healed - unit.hp
	fruits.erase(unit.cell)
	unit.hp = healed
	if gained > 0:
		log_event("%s 拾取恢复果实，回复 %d 生命。" % [unit.display_name, gained])
	else:
		log_event("%s 拾取恢复果实（生命已满）。" % unit.display_name)
	return {"cell": unit.cell, "gained": gained}


func _pickups() -> void:
	var reward_state: String = reward.get("state", "map")
	if reward_state == "map" or reward_state == "dropped":
		var picker := _player_unit_at(reward["cell"])
		if picker != null:
			reward["state"] = "carried"
			reward["carrier_uid"] = picker.uid
			log_event("%s 拾取奖励，成为奖励携带者。" % picker.display_name)
	for fruit_cell in fruits.duplicate():
		var picker := _player_unit_at(fruit_cell)
		if picker != null:
			try_pickup_fruit(picker)


func _player_unit_at(cell: Vector2i) -> CombatUnit:
	for unit in units:
		if unit.side == "player" and unit.is_alive() and unit.cell == cell:
			return unit
	return null


func check_battle_end() -> bool:
	if ended:
		return true
	if alive_enemy_count() == 0:
		var any_resolved := not enemy_kills.is_empty() or not captured.is_empty()
		if any_resolved:
			end_battle("victory")
			return true
	return ended


func end_battle(reason: String) -> void:
	if ended:
		return
	ended = true
	end_reason = reason
	phase = PHASE_ENDED
	var text: String = {
		"victory": "全部敌人被击败或捕获，胜利！",
		"forced_retreat": "训练家倒下：强制撤退，视为战斗失败。",
		"escape": "第 %d 回合结束，野生宝可梦逃离。" % Balance.MAX_ROUNDS,
	}.get(reason, reason)
	log_event("战斗结束：" + text)


func battle_exp() -> int:
	if end_reason == "forced_retreat":
		return 0
	var kills := 0
	for entry in enemy_kills:
		if bool(entry.get("by_player", false)):
			kills += 1
	return (kills + captured.size()) * Balance.EXP_PER_KILL


func forecast() -> Array:
	var signature := _signature()
	if signature != _forecast_signature:
		_forecast_cache = EnemyAI.plan(clone())
		_forecast_signature = signature
	return _forecast_cache


func _signature() -> String:
	var parts: PackedStringArray = ["%d|%s|%s|%s" % [round, phase, ended, end_reason]]
	var terrain_text := ""
	for value in terrain:
		terrain_text += str(int(value))
	parts.append(terrain_text)
	for unit in units:
		parts.append("%d:%d,%d:%d:%s:%s:%s:%d:%d:%s" % [
			unit.uid, unit.cell.x, unit.cell.y, unit.hp, unit.side,
			"1" if unit.move_cancelled else "0",
			"1" if unit.root_pending else "0",
			unit.slow_ticks, unit.burn_ticks,
			"1" if unit.fresh_spawn else "0",
		])
	parts.append("%s:%s:%d" % [str(reward.get("state", "")), str(reward.get("cell", Vector2i.ZERO)), int(reward.get("carrier_uid", -1))])
	var obstacle_keys: Array = obstacle_durability.keys().duplicate()
	obstacle_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in obstacle_keys:
		parts.append(str(cell))
	return "|".join(parts)


func clone() -> BattleState:
	var copy := BattleState.new()
	copy.run_seed = run_seed
	copy.battle_index = battle_index
	copy.round = round
	copy.phase = phase
	copy.ended = ended
	copy.end_reason = end_reason
	copy.terrain = terrain.duplicate()
	copy.obstacle_durability = obstacle_durability.duplicate()
	copy.obstacle_origin = obstacle_origin.duplicate()
	copy.obstacle_expire_round = obstacle_expire_round.duplicate()
	copy.nest = nest.duplicate(true)
	copy.reward = reward.duplicate(true)
	copy.fruits = fruits.duplicate()
	copy.deploy_cells = deploy_cells.duplicate()
	copy.next_enemy_uid = next_enemy_uid
	copy.events = events.duplicate()
	copy.deaths = deaths.duplicate(true)
	copy.enemy_kills = enemy_kills.duplicate(true)
	copy.captured = captured.duplicate(true)
	copy.effects = effects.duplicate()
	copy.upgrades = upgrades.duplicate()
	copy.capture_options = capture_options.duplicate()
	copy.reinforcement_pool = reinforcement_pool.duplicate()
	copy.undo_stack = undo_stack.duplicate(true)
	for unit in units:
		copy.units.append(unit.dup())
	copy.spawn_rng.seed = spawn_rng.seed
	copy.spawn_rng.state = spawn_rng.state
	copy.capture_rng.seed = capture_rng.seed
	copy.capture_rng.state = capture_rng.state
	copy._pending_actions = _pending_actions.duplicate(true)
	copy._pending_index = _pending_index
	return copy
