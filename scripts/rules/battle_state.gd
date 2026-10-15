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
var burning_cells: Dictionary = {}
var steam_cells: Dictionary = {}
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
var pending_casts: Array = [] # {uid, side, skill_id, cells, due_round}
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
	burning_cells = {}
	steam_cells = map_data.get("steam_cells", {}).duplicate()
	obstacle_durability = {}
	obstacle_origin = {}
	obstacle_expire_round = {}
	for cell in map_data.get("obstacle_cells", []):
		obstacle_durability[cell] = Balance.TREE_DURABILITY if terrain_at(cell) == TerrainDB.TREE else Balance.OBSTACLE_DURABILITY
	nest = {
		"cell": map_data["nest_cell"],
		"exits": map_data["nest_exits"].duplicate(),
		"hp": Balance.NEST_DURABILITY,
		"alive": true,
		"pending_waves": 0,
	}
	reward = {
		"state": "map",  # map / guarding / carried / lost / destroyed
		"cell": map_data["reward_cell"],
		"owner_uid": -1,
		"guard_uid": -1,
	}
	fruits = map_data.get("fruit_cells", []).duplicate()


# ---------------------------------------------------------------- 查询

func terrain_at(cell: Vector2i) -> int:
	return int(terrain[GridSpec.index(cell)])


func set_terrain(cell: Vector2i, value: int) -> void:
	var was_vines := terrain_at(cell) == TerrainDB.VINES
	terrain[GridSpec.index(cell)] = value
	if was_vines and value != TerrainDB.VINES:
		var occupant := unit_at(cell)
		if occupant != null and occupant.vine_ticks > 0:
			occupant.vine_ticks = 0
			log_event("%s 脚下的藤蔓消失，束缚解除。" % occupant.display_name)
	if value == TerrainDB.WATER or value == TerrainDB.DEEP or value == TerrainDB.ICE:
		burning_cells.erase(cell)
	if value == TerrainDB.ICE or value == TerrainDB.PIT:
		steam_cells.erase(cell)
	if value == TerrainDB.VINES:
		apply_vine_on_landing(unit_at(cell))


func ignite(cell: Vector2i) -> void:
	if not GridSpec.is_inside(cell):
		return
	if terrain_at(cell) != TerrainDB.GRASS and terrain_at(cell) != TerrainDB.VINES and terrain_at(cell) != TerrainDB.TREE:
		return
	burning_cells[cell] = 2
	log_event("(%d,%d) 的可燃物被点燃。" % [cell.x, cell.y])


func add_steam(cell: Vector2i) -> void:
	if not GridSpec.is_inside(cell):
		return
	steam_cells[cell] = 2
	log_event("(%d,%d) 产生蒸汽；站在雾中不能施法。" % [cell.x, cell.y])


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


func reward_owner() -> CombatUnit:
	return unit_by_uid(int(reward.get("owner_uid", -1)))


func damage_reward_at(cell: Vector2i) -> void:
	if not ["map", "guarding"].has(String(reward.get("state", ""))) or reward.get("cell", Vector2i(-1, -1)) != cell:
		return
	var holder := unit_at(cell)
	if holder != null and holder.side == "player":
		return
	reward["state"] = "destroyed"
	log_event("奖励格受到伤害，奖励被摧毁。")


func _begin_reward_guard() -> void:
	if String(reward.get("state", "")) != "map":
		return
	var unit := unit_at(reward["cell"])
	if unit == null or unit.side != "player":
		return
	reward["state"] = "guarding"
	reward["guard_uid"] = unit.uid
	log_event("%s 开始守住奖励点；敌方行动结束时仍存活并站在此处即可取得战后奖励。" % unit.display_name)


func _finish_reward_guard() -> void:
	if String(reward.get("state", "")) != "guarding":
		return
	var unit := unit_by_uid(int(reward.get("guard_uid", -1)))
	if unit != null and unit.is_alive() and unit.side == "player" and unit.cell == reward["cell"]:
		reward["state"] = "carried"
		reward["owner_uid"] = unit.uid
		log_event("%s 取得战场奖励；若存活到战斗结束，获得一次额外的战后三选一。" % unit.display_name)
	else:
		reward["state"] = "map"
		reward["guard_uid"] = -1
		log_event("奖励点未被守住，可在下回合重新尝试。")


func _refresh_reward_guard() -> void:
	if String(reward.get("state", "")) != "guarding":
		return
	var unit := unit_by_uid(int(reward.get("guard_uid", -1)))
	if unit == null or not unit.is_alive() or unit.cell != reward["cell"] or unit.side != "player":
		reward["state"] = "map"
		reward["guard_uid"] = -1
		log_event("守点者离开奖励格，本次守点中断。")


func reward_bonus_earned() -> bool:
	var unit := reward_owner()
	return ended and end_reason != "forced_retreat" and String(reward.get("state", "")) == "carried" and unit != null and unit.is_alive() and unit.side == "player"


func is_blocking_ray(cell: Vector2i) -> bool:
	if terrain_at(cell) == TerrainDB.OBSTACLE or terrain_at(cell) == TerrainDB.TREE:
		return true
	if is_nest_cell(cell):
		return true
	return unit_at(cell) != null


func move_cost_for(unit: CombatUnit, cell: Vector2i) -> int:
	## 主动移动进入该格的消耗；-1 表示不可进入。
	## 潮汐效果：我方单位进入水面不额外消耗移动力。
	var terrain := terrain_at(cell)
	if unit.has_buff("flight"):
		return 1
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


func kill_unit(unit: CombatUnit, cause: String, killer_side: String = "", killer_uid: int = -1) -> void:
	cancel_channel(unit, "施法者倒下")
	if int(reward.get("guard_uid", -1)) == unit.uid and String(reward.get("state", "")) == "guarding":
		reward["state"] = "destroyed"
		log_event("守点单位倒下，战场奖励失去。")
	if int(reward.get("owner_uid", -1)) == unit.uid and String(reward.get("state", "")) == "carried":
		reward["state"] = "lost"
		log_event("奖励持有者倒下，战后额外奖励失去。")
	if unit.is_trainer:
		unit.hp = 1
		log_event("训练家落入致死地形，强制撤退。")
		end_battle("forced_retreat")
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
			"killer_side": killer_side,
			"killer_uid": killer_uid if killer_side == "player" else -1,
			"cause": cause,
		})
		log_event("野生 %s 被击败（%s）。" % [unit.display_name, cause])


func on_captured(unit: CombatUnit, species_id: String, keep_hp: int) -> void:
	cancel_channel(unit, "阵营改变")
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


# ---------------------------------------------------------------- 伤害

func damage_unit(source: CombatUnit, target: CombatUnit, base: int, opts: Dictionary) -> Dictionary:
	if target == null or not target.is_alive() or base <= 0:
		return {"amount": 0, "killed": false}
	if target.frozen:
		cancel_channel(target, "无法行动")
		if source != null:
			damage_reward_at(target.cell)
		target.frozen = false
		target.paralyzed_ticks = maxi(target.paralyzed_ticks, 1)
		log_event("%s 的冰冻被攻击解除，本轮仍无法行动。" % target.display_name)
		return {"amount": 0, "killed": false}
	var amount := base
	var is_lethal_check := true
	var matchup_modifier := 0
	if not bool(opts.get("no_element", false)):
		var skill_element: String = opts.get("element", "")
		matchup_modifier = Elements.modifier(skill_element, target.element)
		amount = maxi(1, amount + matchup_modifier + int(opts.get("reaction_bonus", 0)))
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
	if amount > 0:
		if source != null and not bool(opts.get("no_element", false)) and target.has_buff("direct_guard") and not bool(opts.get("conductive", false)):
			amount = maxi(0, amount - 1)
		if bool(opts.get("skill_hit", false)) and target.rock_guard_until_round >= round:
			amount = maxi(0, amount - 1)
		if amount > 0:
			damage_reward_at(target.cell)
	var cause: String = opts.get("cause", "伤害")
	var previous_hp := target.hp
	target.hp -= amount
	if source != null and source.is_alive() and bool(opts.get("skill_hit", false)) and target.parasite_until_round >= round and amount > 0:
		var actual_damage := mini(amount, previous_hp - (1 if target.is_trainer else 0))
		var healed := mini(maxi(0, actual_damage), source.max_hp - source.hp)
		if healed > 0:
			source.hp += healed
			log_event("%s 从寄生目标吸取 %d 生命。" % [source.display_name, healed])
	var source_name := source.display_name if source != null else "环境"
	var matchup_text := ""
	if matchup_modifier > 0:
		matchup_text = "（属性克制 +1）"
	elif matchup_modifier < 0:
		matchup_text = "（属性逆克制 -1；最低 1 伤）"
	log_event("%s 对 %s 造成 %d 伤害%s。" % [source_name, target.display_name, amount, matchup_text])
	var killed := false
	if target.is_trainer and target.hp <= 0:
		target.hp = 1
		log_event("训练家倒下！以 1 生命保留，战斗强制撤退（视为失败）。")
		end_battle("forced_retreat")
		return {"amount": amount, "killed": false}
	if target.hp <= 0:
		killed = true
		var killer_side: String = source.side if source != null else String(opts.get("killer_side", ""))
		kill_unit(target, cause, killer_side, source.uid if source != null else int(opts.get("killer_uid", -1)))
	return {"amount": amount, "killed": killed, "previous_hp": previous_hp, "hp": target.hp}


func add_attachment(target: CombatUnit, element: String, source: CombatUnit = null, direct_hit: bool = false) -> Dictionary:
	return ElementAttachmentResolver.add(self, target, element, source, direct_hit)


func resolve_attachment_effect(target: CombatUnit, result: Dictionary, source: CombatUnit = null) -> void:
	if String(result.get("reaction", "")) == "" or target == null:
		return
	match String(result.get("effect", "")):
		"parasite":
			if target.is_alive() and target.element != "grass":
				target.parasite_until_round = maxi(target.parasite_until_round, round + 2)
				log_event("%s 被寄生：技能攻击者按实际伤害回复生命。" % target.display_name)
		"paralyze":
			if target.is_alive() and target.element != "electric":
				# 敌人在我方阶段中招时，本轮敌方行动就是被跳过的一次机会。
				var ticks := 1 if phase == PHASE_PLAYER and target.side == "enemy" else 2
				target.paralyzed_ticks = maxi(target.paralyzed_ticks, ticks)
				cancel_channel(target, "麻痹")
				log_event("%s 麻痹，下一轮无法行动。" % target.display_name)
		"freeze":
			if target.is_alive() and target.element != "ice":
				target.frozen = true
				cancel_channel(target, "冻结")
				log_event("%s 被冻结，受到攻击才会解除。" % target.display_name)
		"rock_guard":
			if target.is_alive():
				target.rock_guard_until_round = maxi(target.rock_guard_until_round, round + 1)
				log_event("%s 获得岩护：技能直接伤害 −1。" % target.display_name)
		"overload":
			var center: Vector2i = result.get("cell", target.cell)
			for cell in [center] + GridSpec.neighbors4(center):
				if not GridSpec.is_inside(cell):
					continue
				var victim := unit_at(cell)
				if victim != null:
					damage_unit(source, victim, 1, {"no_element": true, "cause": "过载", "killer_side": source.side if source != null else ""})


func _apply_terrain_attachments() -> void:
	# 阶段结束时检查全场站位；飞行单位不接触地表。
	for unit in alive_units():
		if unit.has_buff("flight"):
			continue
		var element := ""
		var tile := terrain_at(unit.cell)
		if burning_cells.has(unit.cell):
			element = "fire"
		elif tile == TerrainDB.WATER or tile == TerrainDB.DEEP:
			element = "water"
		elif tile == TerrainDB.VINES:
			element = "grass"
		elif tile == TerrainDB.ICE:
			element = "ice"
		if element != "":
			var reaction := add_attachment(unit, element)
			resolve_attachment_effect(unit, reaction)


func _settle_attachments() -> void:
	# 火/水附着在完整回合结束转化，异常从下一回合起产生作用。
	for unit in alive_units():
		if ElementAttachmentResolver.consume_ready(unit, "fire", round) > 0:
			apply_burn(unit, null)
		if ElementAttachmentResolver.consume_ready(unit, "water", round) > 0 and unit.element != "water" and not unit.has_buff("status_immune") and not (unit.side == "player" and int(effects.get("water_ignore", 0)) > 0):
			unit.slow_ticks = maxi(unit.slow_ticks, 1)
			log_event("%s 的水附着转为浸湿，下次移动力 −1。" % unit.display_name)
	for unit in units:
		ElementAttachmentResolver.clear_expired(unit, round)
		if unit.parasite_until_round <= round:
			unit.parasite_until_round = 0
		if unit.rock_guard_until_round <= round:
			unit.rock_guard_until_round = 0


func apply_burn(target: CombatUnit, source: CombatUnit) -> void:
	if target.has_buff("status_immune"):
		return
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
	if target.element == "water" or target.has_buff("status_immune"):
		return
	target.slow_ticks = 2
	log_event("%s 获得浸湿：下一次移动力 -1。" % target.display_name)


func _movement_effect_ticks(unit: CombatUnit) -> int:
	# 己方阶段内还可移动，效果覆盖本次机会；已经移动则保留到下次机会。
	# 在对方阶段或整轮结算获得效果时，下一次己方阶段就是目标机会。
	if phase != unit.side:
		return 1
	if unit.moved or unit.frozen or unit.paralyzed_ticks > 0 or unit.move_cancelled or unit.vine_ticks > 0:
		return 2
	return 1


func apply_vine_bind(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive() or unit.has_buff("flight"):
		return
	unit.vine_ticks = maxi(unit.vine_ticks, _movement_effect_ticks(unit))
	log_event("%s 被藤蔓束缚，下一次移动机会受阻。" % unit.display_name)


func apply_vine_on_landing(unit: CombatUnit) -> void:
	if unit != null and GridSpec.is_inside(unit.cell) and terrain_at(unit.cell) == TerrainDB.VINES:
		apply_vine_bind(unit)


func apply_haste(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive():
		return
	unit.haste_ticks = maxi(unit.haste_ticks, _movement_effect_ticks(unit))


func _finish_movement_effects(side: String) -> void:
	for unit in units:
		if unit.side != side:
			continue
		unit.vine_ticks = maxi(0, unit.vine_ticks - 1)
		unit.haste_ticks = maxi(0, unit.haste_ticks - 1)


func damage_obstacle(cell: Vector2i, amount: int) -> bool:
	if not obstacle_durability.has(cell):
		return false
	var left := int(obstacle_durability[cell]) - amount
	if left <= 0:
		obstacle_durability.erase(cell)
		burning_cells.erase(cell)
		var origin := int(obstacle_origin.get(cell, TerrainDB.PLAIN))
		obstacle_origin.erase(cell)
		obstacle_expire_round.erase(cell)
		set_terrain(cell, origin)
		log_event("障碍被破坏，恢复为%s。" % TerrainDB.name_of(origin))
		return true
	obstacle_durability[cell] = left
	log_event("障碍耐久 -%d（剩 %d）。" % [amount, left])
	return false


func damage_nest(amount: int, source_side: String = "") -> bool:
	if not bool(nest.get("alive", false)):
		return false
	if amount <= 0:
		return false
	if nest_exit_guarded() and amount == 1:
		log_event("敌方守住巢穴出口，抵消了 %d 点伤害。" % amount)
		return false
	# 守口只决定这次命中能否破防；巢穴每次命中最多损失 1 点耐久。
	nest["hp"] = maxi(0, int(nest["hp"]) - 1)
	if int(nest["hp"]) <= 0:
		nest["alive"] = false
		nest["destroyed_by_player"] = source_side == "player"
		set_terrain(nest["cell"], TerrainDB.PLAIN)
		log_event("巢穴被摧毁，永久停止生成。")
		end_battle("victory")
		return true
	log_event("巢穴耐久 -1（剩 %d）。" % nest["hp"])
	return false


func nest_exit_guarded() -> bool:
	if not bool(nest.get("alive", false)):
		return false
	for cell in nest.get("exits", []):
		var occupant := unit_at(cell)
		if occupant != null and occupant.side == "enemy":
			return true
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
	var direction_before := unit.last_move_direction
	var vine_ticks_before := unit.vine_ticks
	for step in path:
		unit.last_move_direction = step - unit.cell
		unit.cell = step
		if not unit.has_buff("flight") and (terrain_at(step) == TerrainDB.WATER or terrain_at(step) == TerrainDB.DEEP):
			if unit.burn_ticks > 0:
				log_event("%s 进入水域，灼烧解除。" % unit.display_name)
			unit.burn_ticks = 0
	unit.moved = true
	apply_vine_on_landing(unit)
	var pickup := try_pickup_fruit(unit)
	undo_stack.append({
		"uid": unit.uid,
		"from": from_cell,
		"burn_ticks": burn_ticks_before,
		"burn_source_uid": burn_source_uid_before,
		"burn_source_side": burn_source_side_before,
		"direction": direction_before,
		"vine_ticks": vine_ticks_before,
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
	unit.last_move_direction = entry.get("direction", Vector2i.ZERO)
	unit.vine_ticks = int(entry.get("vine_ticks", 0))
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
	if unit == null or not unit.skills.has(skill_id) or steam_cells.has(unit.cell):
		return []
	return SkillResolver.targets(self, unit, skill_id)


func preview_skill(unit: CombatUnit, skill_id: String, target_entry: Dictionary) -> Dictionary:
	if unit == null or not unit.skills.has(skill_id):
		return {"ok": false}
	var clone := clone()
	var clone_unit := clone.unit_by_uid(unit.uid)
	if clone_unit == null:
		return {"ok": false}
	return SkillResolver.apply(clone, clone_unit, skill_id, target_entry, true)


func cast_skill(unit: CombatUnit, skill_id: String, target_entry: Dictionary) -> Dictionary:
	if unit == null or ended or not unit.can_act_skill() or not unit.skills.has(skill_id):
		return {"ok": false}
	if steam_cells.has(unit.cell):
		return {"ok": false}
	if not unit.can_use_in_battle(skill_id):
		return {"ok": false}
	var result := SkillResolver.apply(self, unit, skill_id, target_entry, false)
	if bool(result.get("ok", false)):
		if unit.skill_used and unit.extra_casts > 0:
			unit.extra_casts -= 1
		else:
			unit.skill_used = true
		commit_actions()
		check_battle_end()
	return result


func begin_channel(caster: CombatUnit, skill_id: String, cells: Array) -> void:
	pending_casts.append({"uid": caster.uid, "side": caster.side, "skill_id": skill_id,
		"cells": cells.duplicate(), "due_round": round + 1})
	caster.channel_lock_round = round + 1
	caster.moved = true
	caster.skill_used = true
	caster.extra_casts = 0
	log_event("%s 开始吟唱%s，落点已标记；下次本方阶段不能行动。" % [caster.display_name, SkillDB.name_of(skill_id)])


func cancel_channel(unit: CombatUnit, reason: String) -> void:
	for index in range(pending_casts.size() - 1, -1, -1):
		if int(pending_casts[index]["uid"]) == unit.uid:
			pending_casts.remove_at(index)
			log_event("%s 的吟唱中断：%s；下次本方阶段仍无法行动。" % [unit.display_name, reason])


func _resolve_due_channels(side: String) -> void:
	var due: Array = []
	for entry in pending_casts.duplicate(true):
		if String(entry["side"]) == side and int(entry["due_round"]) <= round:
			due.append(entry)
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := unit_by_uid(int(a["uid"]))
		var right := unit_by_uid(int(b["uid"]))
		return int(left.reg_index if left != null else 9999) < int(right.reg_index if right != null else 9999)
	)
	for entry in due:
		if ended:
			break
		pending_casts.erase(entry)
		var caster := unit_by_uid(int(entry["uid"]))
		if caster == null or not caster.is_alive() or caster.side != side:
			continue
		var result := SkillResolver.resolve_channel(self, caster, String(entry["skill_id"]), entry["cells"])
		log_event("%s 吟唱完成：%s" % [caster.display_name, String(result.get("text", ""))])
		check_battle_end()


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
		unit.extra_casts = 0
		if unit.channel_lock_round == round:
			unit.moved = true
			unit.skill_used = true
			unit.capture_used = true
		if unit.paralyzed_ticks > 0:
			unit.paralyzed_ticks -= 1
	for unit in units:
		if unit.move_cancelled:
			unit.move_cancelled = false
	for unit in units:
		if unit.root_pending and unit.is_alive():
			unit.root_pending = false
			unit.move_cancelled = true
			log_event("%s 受到定身影响，本回合无法移动。" % unit.display_name)
	phase = PHASE_PLAYER
	if Balance.nest_warning_due(round):
		log_event("巢穴预警：下回合将尝试产怪。")
	if Balance.nest_wave_due(round):
		nest["pending_waves"] = int(nest.get("pending_waves", 0)) + 1
	if int(nest.get("pending_waves", 0)) > 0:
		_try_spawn_wave()
	_resolve_due_channels("player")


func _try_spawn_wave() -> void:
	if not bool(nest.get("alive", false)) or reinforcement_pool.is_empty():
		return
	var species_id: String = reinforcement_pool[spawn_rng.randi_range(0, reinforcement_pool.size() - 1)]
	var candidates: Array = []
	for exit_cell in nest.get("exits", []):
		candidates.append(exit_cell)
	for cell in candidates:
		if not GridSpec.is_inside(cell):
			continue
		if is_nest_cell(cell) or TerrainDB.blocks_move(terrain_at(cell)):
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
		nest["pending_waves"] = maxi(0, int(nest.get("pending_waves", 0)) - 1)
		apply_vine_on_landing(enemy)
		log_event("巢穴生成 1 只野生宝可梦（%s）；出生轮在出口待机，下一回合才能行动。" % enemy.display_name)
		return
	log_event("巢穴出口被占，本次产怪排队至下一回合。")


func _cell_order(cell: Vector2i) -> int:
	return cell.y * GridSpec.W + cell.x


func begin_enemy_phase() -> Array:
	if ended or phase != PHASE_PLAYER:
		return []
	commit_actions()
	_begin_reward_guard()
	_finish_movement_effects("player")
	_apply_terrain_attachments()
	phase = PHASE_ENEMY
	_resolve_due_channels("enemy")
	_refresh_reward_guard()
	if ended:
		_pending_actions = []
		_pending_index = 0
		return []
	_pending_actions = EnemyAI.plan(self)
	_pending_index = 0
	log_event("敌方开始行动（%d 个动作）。" % _pending_actions.size())
	return _pending_actions


func enemy_phase_finished() -> bool:
	return ended or _pending_index >= _pending_actions.size()


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
		unit.last_move_direction = cell - unit.cell
		unit.cell = cell
		if not unit.has_buff("flight") and (terrain_at(cell) == TerrainDB.WATER or terrain_at(cell) == TerrainDB.DEEP):
			unit.burn_ticks = 0
	if not path.is_empty():
		unit.moved = true
		apply_vine_on_landing(unit)
		log_event("%s 移动 %d 格。" % [unit.display_name, path.size()])
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty() and unit.can_act_skill() and not ended:
		var result := SkillResolver.apply(self, unit, String(skill["id"]), skill["target"], false)
		if bool(result.get("ok", false)):
			if unit.skill_used and unit.extra_casts > 0:
				unit.extra_casts -= 1
			else:
				unit.skill_used = true
	unit.fresh_spawn = false
	_refresh_reward_guard()
	check_battle_end()
	return action


func end_enemy_phase() -> void:
	if ended:
		return
	_finish_movement_effects("enemy")
	_apply_terrain_attachments()
	_finish_reward_guard()
	_finish_round()


func _finish_round() -> void:
	phase = PHASE_SETTLE
	settle_round()
	for unit in units:
		unit.fresh_spawn = false
	if ended:
		phase = PHASE_ENDED
	else:
		start_round()


func settle_round() -> void:
	_settle_ice_slides()
	if ended:
		return
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
			if not unit.has_buff("flight") and (cell_terrain == TerrainDB.WATER or cell_terrain == TerrainDB.DEEP):
				log_event("%s 处于水域，灼烧解除。" % unit.display_name)
				unit.burn_ticks = 0
			continue
	# 3. 灼烧与状态计数
	for unit in alive_units():
		if unit.burn_ticks > 0:
			unit.burn_ticks -= 1
			damage_unit(null, unit, Balance.BURN_DAMAGE, {"no_element": true, "cause": "灼烧", "killer_side": unit.burn_source_side})
	_settle_burning_cells()
	for cell in steam_cells.keys().duplicate():
		steam_cells[cell] = int(steam_cells[cell]) - 1
		if int(steam_cells[cell]) <= 0:
			steam_cells.erase(cell)
	# 4. 减速衰减
	for unit in units:
		if unit.slow_ticks > 0:
			unit.slow_ticks = maxi(0, unit.slow_ticks - 1)
		if unit.shock_ticks > 0:
			unit.shock_ticks -= 1
	_settle_attachments()
	# 5. 恢复果实
	_pickups()
	# 6. 胜负与时限
	if check_battle_end():
		return
	if round >= Balance.MAX_ROUNDS and alive_enemy_count() > 0:
		end_battle("escape")
		return
	log_event("环境结算完成。")


func _settle_ice_slides() -> void:
	for unit in units:
		if not unit.is_alive():
			unit.last_move_direction = Vector2i.ZERO
			continue
		var direction: Vector2i = unit.last_move_direction
		unit.last_move_direction = Vector2i.ZERO
		if direction == Vector2i.ZERO or terrain_at(unit.cell) != TerrainDB.ICE or unit.has_buff("flight"):
			continue
		var next: Vector2i = unit.cell + direction
		if not GridSpec.is_inside(next) or unit_at(next) != null or is_nest_cell(next) or TerrainDB.blocks_move(terrain_at(next)):
			continue
		unit.cell = next
		log_event("%s 从冰面滑行到 (%d,%d)。" % [unit.display_name, next.x, next.y])
		if not unit.has_buff("flight") and TerrainDB.is_lethal(terrain_at(next)) and (terrain_at(next) != TerrainDB.DEEP or unit.element != "water"):
			kill_unit(unit, "冰面滑入致死地形")
		elif terrain_at(next) == TerrainDB.WATER and not unit.has_buff("flight"):
			unit.burn_ticks = 0
			# 滑行后将在下一次阶段结束获得水附着。
		elif terrain_at(next) == TerrainDB.VINES:
			apply_vine_on_landing(unit)


func _settle_burning_cells() -> void:
	var current := burning_cells.keys().duplicate()
	var newly_lit: Array = []
	for cell in current:
		for near in GridSpec.neighbors4(cell):
			if not burning_cells.has(near) and (terrain_at(near) == TerrainDB.GRASS or terrain_at(near) == TerrainDB.VINES or terrain_at(near) == TerrainDB.TREE):
				newly_lit.append(near)
		burning_cells[cell] = int(burning_cells[cell]) - 1
		if int(burning_cells[cell]) <= 0:
			burning_cells.erase(cell)
			obstacle_durability.erase(cell)
			set_terrain(cell, TerrainDB.PLAIN)
	for cell in newly_lit:
		if not burning_cells.has(cell):
			ignite(cell)


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
	pending_casts.clear()
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
		var preview := clone()
		if phase == PHASE_PLAYER:
			preview._finish_movement_effects("player")
			preview._apply_terrain_attachments()
		_forecast_cache = EnemyAI.plan(preview)
		_forecast_signature = signature
	return _forecast_cache


func _signature() -> String:
	var parts: PackedStringArray = ["%d|%s|%s|%s" % [round, phase, ended, end_reason]]
	var terrain_text := ""
	for value in terrain:
		terrain_text += str(int(value))
	parts.append(terrain_text)
	var fog_keys: Array = steam_cells.keys().duplicate()
	fog_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in fog_keys:
		parts.append("fog:%d,%d:%d" % [cell.x, cell.y, int(steam_cells[cell])])
	for unit in units:
		parts.append("%d:%d,%d:%d:%s:%s:%s:%d:%d:%s" % [
			unit.uid, unit.cell.x, unit.cell.y, unit.hp, unit.side,
			"1" if unit.move_cancelled else "0",
			"1" if unit.root_pending else "0",
			unit.slow_ticks, unit.burn_ticks,
			"1" if unit.fresh_spawn else "0",
		])
	parts.append("%s:%s:%d:%d" % [str(reward.get("state", "")), str(reward.get("cell", Vector2i.ZERO)), int(reward.get("owner_uid", -1)), int(reward.get("guard_uid", -1))])
	for unit in units:
		parts.append("buff:%d:%s" % [unit.uid, str(unit.battle_buffs)])
		parts.append("channel_lock:%d:%d" % [unit.uid, unit.channel_lock_round])
		parts.append("aura:%d:%s:%d:%d" % [unit.uid, str(unit.attachments), unit.parasite_until_round, unit.rock_guard_until_round])
	parts.append("pending:%s" % str(pending_casts))
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
	copy.burning_cells = burning_cells.duplicate()
	copy.steam_cells = steam_cells.duplicate()
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
	copy.pending_casts = pending_casts.duplicate(true)
	for unit in units:
		copy.units.append(unit.dup())
	copy.spawn_rng.seed = spawn_rng.seed
	copy.spawn_rng.state = spawn_rng.state
	copy.capture_rng.seed = capture_rng.seed
	copy.capture_rng.state = capture_rng.state
	copy._pending_actions = _pending_actions.duplicate(true)
	copy._pending_index = _pending_index
	return copy
