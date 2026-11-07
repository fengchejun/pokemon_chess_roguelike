class_name BattleState
extends RefCounted

signal presentation_started(info: Dictionary)
signal presentation_finished(meta: Dictionary)
signal feedback(event: Dictionary)
signal enemy_defeated(entry: Dictionary)
signal enemy_captured(entry: Dictionary)
var feedback_enabled := false

func enable_feedback() -> void:
	feedback_enabled = true
	for unit in units:
		_watch_feedback(unit)

func _watch_feedback(unit: CombatUnit) -> void:
	var callback := _relay_feedback.bind(unit.uid)
	if feedback_enabled and not unit.feedback_changed.is_connected(callback):
		unit.feedback_changed.connect(callback)

func _relay_feedback(kind: String, text: String, value: int, cell: Vector2i, uid: int) -> void:
	if not feedback_enabled:
		return
	feedback.emit({"kind": kind, "uid": uid, "cell": cell, "text": text, "value": value})

func emit_collision(mover: CombatUnit, cell: Vector2i, blocker: Vector2i, blocker_uid: int = -1, start: Vector2i = Vector2i(-1, -1), kind: String = "unit") -> void:
	if not feedback_enabled:
		return
	feedback.emit({"kind": "collision", "uid": mover.uid if mover != null else -1, "cell": cell, "text": "边界受阻" if kind == "edge" else "碰撞", "value": 0, "blocker_cell": blocker, "blocker_uid": blocker_uid, "start_cell": start if start.x >= 0 else cell, "object_kind": kind})


func emit_feedback(unit: CombatUnit, kind: String, text: String, value: int = 0) -> void:
	if feedback_enabled and unit != null:
		_relay_feedback(kind, text, value, unit.cell, unit.uid)

func feedback_heal(unit: CombatUnit, amount: int) -> void:
	if amount > 0:
		emit_feedback(unit, "heal", "+%d" % amount, amount)


## 一场战斗的全部状态与规则入口。
## 回合结构：我方阶段（自由顺序）→ 敌方阶段（固定顺序执行预告的同一计划）→ 环境结算 → 下一回合。
## 第八轮结束预告落雷，下一轮末打击固定地格；战斗不再限时结束。

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
var exploration_started: bool = false
var enemy_level_bonus: int = 0
var corruption_active: bool = false
var timed_corruption_triggered: bool = false
var occupation_applied: bool = false
var extraction_cells: Array = []
var escape_penalties: Array = []
var node_kind: String = "" # 空值沿用旧逐场流程；battle / boss / event 使用区域规则。
var food_cells: Array = []
var food_wait: Dictionary = {}
var food_collected: int = 0
var food_applied: int = 0
var boss_power_percent: int = 0 # 仅为旧快照兼容保留；新版不使用百分比强化。

var terrain: Array = []
var exploration_v2 := false
var exploration_role := ""
var preserve_node_terrain := false
var capture_deadline := 0
var capture_exits: Array = []
var capture_alerted := false
var capture_exit_wait: Dictionary = {}
var retreat_disabled := false
var is_camp_map := false
var camp_facilities: Dictionary = {}
var obstacle_durability: Dictionary = {}
var obstacle_origin: Dictionary = {}
var obstacle_expire_round: Dictionary = {}
var electric_flowers: Dictionary = {}
var burning_cells: Dictionary = {}
var burning_origin: Dictionary = {}
var burning_forced: Dictionary = {}
var steam_cells: Dictionary = {}
var vine_origin: Dictionary = {}
var vine_expire_round: Dictionary = {}
var nest: Dictionary = {} # Primary nest retained for old snapshots and callers.
var extra_nests: Array = []
var deploy_area: Array = []
var speech_seen: Dictionary = {}
var enemy_origins: Dictionary = {} # uid -> original node entry cell; persisted for revisits.
var enemy_outcomes: Dictionary = {} # Defeat/capture is recorded once per enemy identity.
var boss_uid: int = -1
var storm_strikes: Array = [] # {cell, due_round}；属于独立环境威胁，不占吟唱名额。
var storm_last_round: int = 0
var boss_retreat_used: bool = false
var _boss_effect_depth: int = 0
var boss_portal_cell: Vector2i = Vector2i(-1, -1)
var mentor: Dictionary = {}
var merchant: Dictionary = {}
var essence_earned: int = 0
var essence_applied: int = 0
var essence_claims: Dictionary = {}
var natural_essence_cells: Array = []
var obstacle_reward_origins: Dictionary = {} # 当前岩障格 -> 天然障碍原始资源格
var capture_aid: bool = false
var burning_sources: Dictionary = {}


func earn_essence(key: String, amount: int, at: Vector2i = Vector2i(-1, -1)) -> void:
	if node_kind == "" or essence_claims.has(key):
		return
	essence_claims[key] = true
	essence_earned += amount
	log_event("原质 +%d。" % amount)
	if amount > 0:
		var cell := at
		if not GridSpec.is_inside(cell):
			var trainer := unit_by_uid(Balance.TRAINER_UID)
			cell = trainer.cell if trainer != null else Vector2i.ZERO
		_relay_feedback("essence", "原质 +%d" % amount, amount, cell, -1)
var inspiration_triggered: bool = false
var reward: Dictionary = {}
var extra_rewards: Array = []
var chests: Dictionary = {}
var fruits: Array = []
var units: Array = []
var deploy_cells: Array = []

var next_enemy_uid: int = 100
var events: Array = []
var deaths: Array = []
var enemy_kills: Array = []
var captured: Array = []
var effects: Dictionary = {}
var relic_stacks: Dictionary = {}
var upgrades: Dictionary = {}
var capture_options: Dictionary = {}
var debug_skill_damage_bonus: Dictionary = {"player": 0, "enemy": 0} # 仅本场调试覆盖，不写入本局存档。
var debug_capture_percent: int = -1 # -1 表示使用常规捕获率。
var reinforcement_pool: Array = []
var undo_stack: Array = []
var pending_casts: Array = [] # {uid, side, skill_id, cells, due_round}
var channel_claims: Dictionary = {} # side -> {round, uid}，中断后本回合仍占名额。
var skill_use_counts: Dictionary = {"player": {}, "enemy": {}}
var spawn_rng := RandomNumberGenerator.new()
var capture_rng := RandomNumberGenerator.new()
var terrain_rng := RandomNumberGenerator.new()

var experience_level_cap: int = 10
var experience_recipients: Array = []
var experience_events: Dictionary = {}
var experience_gains: Dictionary = {}
var _pending_actions: Array = []
var _pending_index: int = 0
var _forecast_cache: Array = []
var _forecast_signature: String = ""


func setup(map_data: Dictionary, cfg: Dictionary, seed_value: int, battle_index_value: int, player_units: Array, effects_value: Dictionary, upgrades_value: Dictionary, pool_value: Array, capture_options_value: Dictionary = {}, relic_stacks_value: Dictionary = {}) -> void:
	run_seed = seed_value
	battle_index = battle_index_value
	experience_level_cap = MonsterProgression.MAX_LEVEL
	corruption_active = bool(cfg.get("corrupted", false))
	enemy_level_bonus = maxi(0, int(cfg.get("enemy_level_bonus", 0)))
	skill_use_counts = {"player": {}, "enemy": {}}
	effects = effects_value.duplicate()
	relic_stacks = relic_stacks_value.duplicate()
	upgrades = upgrades_value.duplicate()
	capture_options = capture_options_value.duplicate()
	reinforcement_pool = pool_value.duplicate()
	load_map(map_data)
	if node_kind == "boss" or int(cfg.get("boss_index", -1)) >= 0:
		extra_nests.clear()
	deploy_cells = map_data.get("deploy_cells", Balance.DEPLOY_CELLS.duplicate())
	deploy_area = map_data.get("deploy_area", Balance.DEPLOY_AREA).duplicate()
	var slot := 0
	for unit in player_units:
		if slot >= deploy_cells.size():
			break
		unit.cell = map_data.get("deploy_positions", {}).get(unit.uid, deploy_cells[slot])
		if is_nest_cell(unit.cell):
			for fallback in deploy_cells:
				if not is_nest_cell(fallback) and unit_at(fallback) == null:
					unit.cell = fallback
					break
		unit.reg_index = units.size()
		units.append(unit)
		experience_recipients.append(unit.uid)
		_watch_feedback(unit)
		slot += 1
	var enemy_index := 0
	for pair in cfg.get("enemies", []):
		var enemy := CombatUnit.make(pair[0], "enemy", next_enemy_uid)
		next_enemy_uid += 1
		_configure_enemy(enemy, enemy_index, enemy_index == int(cfg.get("boss_index", -1)))
		if enemy.is_boss:
			boss_uid = enemy.uid
		enemy.reward_carrier = enemy.uid == int(map_data.get("carrier_uid", -1)) and not enemy.is_boss
		enemy.cell = pair[1]
		enemy_origins[enemy.uid] = enemy.cell
		enemy.reg_index = units.size()
		units.append(enemy)
		set_enemy_level_bonus(enemy_level_bonus)
		_watch_feedback(enemy)
		enemy_index += 1
	spawn_rng.seed = hash("spawn:%d:%d" % [seed_value, battle_index_value])
	capture_rng.seed = hash("capture:%d:%d" % [seed_value, battle_index_value])
	terrain_rng.seed = hash("terrain:%d:%d" % [seed_value, battle_index_value])
	log_event("战斗开始：%s，敌方 %d 只。" % [String(cfg.get("region", "?")), cfg.get("enemies", []).size()])
	relocate_nest_occupants()
	start_round()


func _configure_enemy(enemy: CombatUnit, spawn_index: int, make_boss: bool = false) -> void:
	BattleDB.configure_enemy(enemy, run_seed, battle_index, spawn_index, make_boss)
	if inspiration_triggered:
		_grant_inspiration(enemy)
	if corruption_active:
		enemy.set_corrupted(true)


func _grant_inspiration(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive() or unit.side != "enemy" or unit.is_boss or unit.inspired:
		return
	var was_corrupted: bool = unit.corrupted
	unit.set_corrupted(false)
	unit.inspired = true
	unit.max_hp += Balance.INSPIRATION_HP_BONUS
	unit.hp += Balance.INSPIRATION_HP_BONUS
	unit.set_corrupted(was_corrupted)


func _trigger_inspiration() -> void:
	if inspiration_triggered:
		return
	inspiration_triggered = true
	var boss := unit_by_uid(boss_uid)
	if boss != null:
		say_once("boss_roar", boss.uid, boss.cell, "吼！！！！！")
	for ally in units:
		_grant_inspiration(ally)
	log_event("首领鼓舞：其他敌方单位移动力 +1，生命上限与当前生命各 +%d，持续本场。" % Balance.INSPIRATION_HP_BONUS)


func sheltered_boss() -> CombatUnit:
	var boss := unit_by_uid(boss_uid)
	return boss if boss != null and boss.is_alive() and boss.sheltered else null


func _try_shelter_boss() -> void:
	var boss := unit_by_uid(boss_uid)
	if boss_retreat_used or boss == null or not boss.is_on_board() or boss.side != "enemy" or boss.hp * 2 > boss.max_hp or not bool(nest.get("alive", false)):
		return
	boss_retreat_used = true
	boss.sheltered = true
	boss.last_move_direction = Vector2i.ZERO
	nest["boss_sheltered"] = true
	cancel_channel(boss, "首领回巢")
	_refresh_reward_guard()
	emit_feedback(boss, "action", "半血回巢")
	log_event("%s 半血回巢！摧毁主巢穴后才能继续攻击或捕获；巢内不行动，异常暂停。" % boss.display_name)


func try_release_boss() -> void:
	if _boss_effect_depth > 0 or ended:
		return
	var boss := sheltered_boss()
	if boss == null or bool(nest.get("alive", false)):
		return
	var origin: Vector2i = nest["cell"]
	var candidates := GridSpec.all_cells()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := GridSpec.manhattan(a, origin)
		var db := GridSpec.manhattan(b, origin)
		return da < db if da != db else _cell_order(a) < _cell_order(b))
	for cell in candidates:
		if unit_at(cell) != null or is_interaction_cell(cell) or is_nest_cell(cell) or terrain_blocks_move(cell) or not TerrainDB.can_stand(terrain_at(cell), boss.element):
			continue
		boss.cell = cell
		boss.sheltered = false
		boss.moved = false
		boss.skill_used = false
		boss.capture_used = false
		boss.extra_casts = 0
		boss.fresh_spawn = false
		nest["boss_sheltered"] = false
		apply_vine_on_landing(boss)
		emit_feedback(boss, "action", "首领出巢")
		log_event("主巢穴已毁，%s 在 (%d,%d) 出巢；生命不恢复，本场不再回巢。" % [boss.display_name, cell.x, cell.y])
		return


func capture_roll() -> float:
	return capture_rng.randf()


func load_map(map_data: Dictionary) -> void:
	terrain = map_data["terrain"].duplicate()
	extraction_cells = map_data.get("extraction_cells", extraction_area(map_data)).duplicate()
	burning_cells = {}
	burning_origin = {}
	burning_forced = {}
	burning_sources = {}
	steam_cells = map_data.get("steam_cells", {}).duplicate()
	vine_origin = {}
	vine_expire_round = {}
	obstacle_durability = {}
	obstacle_origin = {}
	obstacle_expire_round = {}
	obstacle_reward_origins = {}
	for cell in map_data.get("obstacle_cells", []):
		obstacle_durability[cell] = Balance.TREE_DURABILITY if terrain_at(cell) == TerrainDB.TREE else Balance.OBSTACLE_DURABILITY
	electric_flowers = map_data.get("electric_flowers", {}).duplicate()
	for cell in electric_flowers:
		obstacle_durability[cell] = electric_flower_max_hp(cell)
	obstacle_durability.merge(map_data.get("obstacle_durability", {}), true)
	natural_essence_cells = obstacle_durability.keys().duplicate()
	nest = {
		"cell": map_data["nest_cell"],
		"exits": [], # Legacy snapshot field; spawning uses cell only.
		"hp": Balance.nest_max_hp(battle_index),
		"max_hp": Balance.nest_max_hp(battle_index),
		"alive": true,
		"pending_waves": 0,
	}
	extra_nests = []
	for cell in map_data.get("nest_cells", [map_data["nest_cell"]]):
		if cell != nest["cell"]:
			var other := nest.duplicate(true)
			other["cell"] = cell
			extra_nests.append(other)
	normalize_nest_terrain()
	reward = map_data.get("reward", {"state": "absent", "cell": Vector2i(-1, -1), "owner_uid": -1, "guard_uid": -1}).duplicate(true)
	extra_rewards = map_data.get("extra_rewards", []).duplicate(true)
	chests = map_data.get("chests", {}).duplicate()
	for cell in chests:
		electric_flowers.erase(cell)
		terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
		obstacle_durability[cell] = 1
		natural_essence_cells.erase(cell)
	if GridSpec.is_inside(map_data.get("mentor_cell", Vector2i(-1, -1))):
		mentor = {"cell": map_data["mentor_cell"], "services": 0}
	fruits = []


# ---------------------------------------------------------------- 查询

func normalize_nest_terrain() -> void:
	# 存活巢穴独占格子；平地仅作内部底板，不保留其他地形或临时效果。
	for current in all_nests():
		if not bool(current.get("alive", false)):
			continue
		var cell: Vector2i = current["cell"]
		if not GridSpec.is_inside(cell):
			continue
		terrain[GridSpec.index(cell)] = TerrainDB.PLAIN
		for effects_by_cell in [electric_flowers, obstacle_durability, obstacle_origin, obstacle_expire_round, burning_cells, burning_sources, steam_cells, vine_origin, vine_expire_round, obstacle_reward_origins]:
			effects_by_cell.erase(cell)
		natural_essence_cells.erase(cell)


func clear_node_temporaries() -> void:
	# 节点离场清理，不结算伤害或奖励；恢复地形后由重访流程重新安置敌军。
	if is_camp_map or preserve_node_terrain:
		# 营地的地形布置跨访问保留；入侵后的地形仍按正常回合结算。
		obstacle_expire_round.clear()
		vine_expire_round.clear()
	var cells: Array = obstacle_expire_round.keys()
	for cell in vine_expire_round:
		if not cells.has(cell):
			cells.append(cell)
	for cell in cells:
		var origin := int(obstacle_origin.get(cell, TerrainDB.PLAIN)) if obstacle_expire_round.has(cell) else int(vine_origin.get(cell, TerrainDB.PLAIN))
		if origin == TerrainDB.VINES:
			origin = int(vine_origin.get(cell, TerrainDB.PLAIN))
		if not is_nest_cell(cell):
			var previous := terrain_at(cell)
			terrain[GridSpec.index(cell)] = origin
			_adjust_electric_flower_hp(cell, previous, origin)
		if not electric_flowers.has(cell):
			obstacle_durability.erase(cell)
			natural_essence_cells.erase(cell)
		obstacle_origin.erase(cell)
		obstacle_expire_round.erase(cell)
		obstacle_reward_origins.erase(cell)
		vine_origin.erase(cell)
		vine_expire_round.erase(cell)
		burning_cells.erase(cell)
		burning_sources.erase(cell)
		steam_cells.erase(cell)
		for unit in units:
			unit.vine_sources.erase(cell)
			_refresh_vine_ticks(unit)
	for unit in units:
		if unit.summon_owner_uid >= 0:
			enemy_origins.erase(unit.uid)
	units = units.filter(func(unit: CombatUnit) -> bool: return unit.summon_owner_uid < 0)


func terrain_at(cell: Vector2i) -> int:
	return int(terrain[GridSpec.index(cell)])


func set_terrain(cell: Vector2i, value: int) -> void:
	if is_nest_cell(cell) or is_chest_cell(cell) or camp_facility_at(cell) != "":
		return
	var previous := terrain_at(cell)
	var was_vines := previous == TerrainDB.VINES
	terrain[GridSpec.index(cell)] = value
	_adjust_electric_flower_hp(cell, previous, value)
	if was_vines and value != TerrainDB.VINES:
		vine_origin.erase(cell)
		vine_expire_round.erase(cell)
		for unit in units:
			if unit.vine_reapply_cell == cell:
				unit.vine_reapply_round = 0
				unit.vine_reapply_cell = Vector2i(-1, -1)
			if unit.vine_sources.has(cell):
				unit.vine_sources.erase(cell)
				_refresh_vine_ticks(unit)
				if unit.is_alive():
					log_event("%s 来源于 (%d,%d) 的禁锢解除。" % [unit.display_name, cell.x, cell.y])
		var occupant := unit_at(cell)
		if occupant != null and occupant.vine_ticks > 0 and occupant.vine_sources.is_empty():
			# 兼容旧战场状态中尚未记录束缚来源的单位。
			occupant.vine_ticks = 0
		if occupant != null and not occupant.has_buff("flight") and TerrainDB.is_lethal(value) and (value != TerrainDB.DEEP or occupant.element != "water"):
			kill_unit(occupant, "藤蔓消失后落入" + TerrainDB.name_of(value))
	if not TerrainDB.is_flammable(value):
		burning_cells.erase(cell)
		burning_origin.erase(cell)
		burning_forced.erase(cell)
	if value == TerrainDB.OBSTACLE or value == TerrainDB.TREE:
		steam_cells.erase(cell)
	if value == TerrainDB.VINES:
		apply_vine_bind(unit_at(cell))


func place_temp_vines(cell: Vector2i) -> void:
	if is_nest_cell(cell) or is_chest_cell(cell) or camp_facility_at(cell) != "":
		return
	if terrain_at(cell) != TerrainDB.VINES:
		vine_origin[cell] = terrain_at(cell)
	set_terrain(cell, TerrainDB.VINES)
	vine_expire_round[cell] = round + 1


func ignite(cell: Vector2i, source_side: String = "", force: bool = false) -> bool:
	if is_nest_cell(cell) or is_chest_cell(cell) or camp_facility_at(cell) != "":
		return false
	if not GridSpec.is_inside(cell):
		return false
	var current_terrain := terrain_at(cell)
	if current_terrain == TerrainDB.BLUE_FIRE:
		return false
	var flammable := TerrainDB.is_flammable(current_terrain)
	if not flammable and not force:
		return false
	var was_burning := burning_cells.has(cell)
	if not was_burning:
		burning_origin[cell] = current_terrain
		burning_forced[cell] = force
	elif force:
		burning_forced[cell] = true
	burning_cells[cell] = Balance.BURN_TICKS
	burning_sources[cell] = source_side
	if not was_burning:
		log_event("(%d,%d) %s。" % [cell.x, cell.y, "生成魔法火焰" if force else "的可燃物被点燃"])
	return true


func add_steam(cell: Vector2i) -> void:
	if is_nest_cell(cell) or is_chest_cell(cell) or camp_facility_at(cell) != "":
		return
	if not GridSpec.is_inside(cell):
		return
	if TerrainDB.blocks_move(terrain_at(cell)):
		return
	steam_cells[cell] = 2
	log_event("(%d,%d) 产生蒸汽；站在雾中不能施法。" % [cell.x, cell.y])


func nest_at_cell(cell: Vector2i) -> Dictionary:
	for current in all_nests():
		if bool(current.get("alive", false)) and current["cell"] == cell:
			return current
	return {}


func is_nest_cell(cell: Vector2i) -> bool:
	return not nest_at_cell(cell).is_empty()


func unit_at(cell: Vector2i) -> CombatUnit:
	for unit in units:
		if unit.is_on_board() and unit.cell == cell:
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
		if unit.is_on_board() and (side == "" or unit.side == side):
			result.append(unit)
	return result


func trainer() -> CombatUnit:
	for unit in units:
		if unit.is_trainer:
			return unit
	return null


func all_rewards() -> Array:
	return [reward] + extra_rewards


func reward_owner() -> CombatUnit:
	return unit_by_uid(int(reward.get("owner_uid", -1)))


func add_reward_point(cell: Vector2i, source_id: String) -> void:
	if all_rewards().any(func(point): return point.get("id", "") == source_id):
		return
	var point := {"id": source_id, "state": "map", "cell": cell, "owner_uid": -1, "guard_uid": -1, "credited": false}
	if reward.get("state", "absent") == "absent":
		reward.merge(point, true)
	else:
		extra_rewards.append(point)
	_relay_feedback("buff", "奖励点出现", 0, cell, -1)
	log_event("(%d,%d) 出现奖励点，拾取并保住持有者后可兑换一次三选一。" % [cell.x, cell.y])


func damage_reward_at(_cell: Vector2i) -> void:
	# 奖励点不再被攻击摧毁；兼容既有技能调用入口。
	pass


func _begin_reward_guard(side: String = "player") -> void:
	for point in all_rewards():
		if point.get("state") != "map":
			continue
		var unit := unit_at(point["cell"])
		if unit != null and unit.side == side:
			point["state"] = "guarding"
			point["guard_uid"] = unit.uid
			point["guard_side"] = side
			log_event("%s 开始守住奖励点。" % unit.display_name)


func _finish_reward_guard(side: String = "player") -> void:
	for point in all_rewards():
		if point.get("state") != "guarding" or point.get("guard_side", "player") != side:
			continue
		var unit := unit_by_uid(int(point.get("guard_uid", -1)))
		if unit != null and unit.is_on_board() and unit.side == side and unit.cell == point["cell"]:
			point["state"] = "carried"
			point["owner_uid"] = unit.uid
			emit_feedback(unit, "buff", "获得战场奖励")
			log_event(("%s 取得奖励点，存活离场可额外三选一。" if side == "player" else "%s 拾取并携带了奖励点，击杀后可夺回。") % unit.display_name)
		else:
			point["state"] = "map"
			point["guard_uid"] = -1


func _refresh_reward_guard() -> void:
	for point in all_rewards():
		if point.get("state") != "guarding":
			continue
		var unit := unit_by_uid(int(point.get("guard_uid", -1)))
		if unit == null or not unit.is_on_board() or unit.side != point.get("guard_side", "player") or unit.cell != point["cell"]:
			point["state"] = "map"
			point["guard_uid"] = -1


func earned_reward_points(uncredited_only: bool = false) -> Array:
	if not ended or end_reason in ["forced_retreat", "boss_timeout"]:
		return []
	return all_rewards().filter(func(point):
		var holder := unit_by_uid(int(point.get("owner_uid", -1)))
		return point.get("state") == "carried" and holder != null and holder.is_alive() and holder.side == "player" and (not uncredited_only or not bool(point.get("credited", false))))


func reward_count_held(side: String) -> int:
	var count := 0
	for point in all_rewards():
		var holder := unit_by_uid(int(point.get("owner_uid", -1)))
		if point.get("state") == "carried" and not bool(point.get("credited", false)) and holder != null and holder.is_alive() and holder.side == side:
			count += 1
	for unit in alive_units(side):
		if unit.reward_carrier:
			count += 1
	return count


func reward_bonus_earned() -> bool:
	return not earned_reward_points().is_empty()


func is_chest_cell(cell: Vector2i) -> bool:
	return chests.has(cell)


func terrain_blocks_move(cell: Vector2i) -> bool:
	return electric_flowers.has(cell) or TerrainDB.blocks_move(terrain_at(cell))


func _adjust_electric_flower_hp(cell: Vector2i, previous: int, next: int) -> void:
	if electric_flowers.has(cell) and TerrainDB.is_grass(previous) != TerrainDB.is_grass(next):
		var bonus := 1 if TerrainDB.is_grass(next) else -1
		obstacle_durability[cell] = maxi(1, int(obstacle_durability[cell]) + bonus)


func electric_flower_max_hp(cell: Vector2i) -> int:
	return 2 if TerrainDB.is_grass(terrain_at(cell)) else 1


func is_burning_ground(cell: Vector2i) -> bool:
	return burning_cells.has(cell) or terrain_at(cell) == TerrainDB.BLUE_FIRE


func is_blocking_ray(cell: Vector2i) -> bool:
	if terrain_blocks_move(cell):
		return true
	if is_nest_cell(cell) or is_chest_cell(cell) or camp_facility_at(cell) != "":
		return true
	return unit_at(cell) != null


func camp_facility_at(cell: Vector2i) -> String:
	for id in camp_facilities:
		if camp_facilities[id]["cell"] == cell and not bool(camp_facilities[id].get("destroyed", false)):
			return String(id)
	return ""


func is_interaction_cell(cell: Vector2i) -> bool:
	return (GridSpec.is_inside(boss_portal_cell) and cell == boss_portal_cell) or (not mentor.is_empty() and cell == mentor["cell"]) or (node_kind == "event" and not merchant.is_empty() and cell == merchant["cell"])

func can_interact_at(cell: Vector2i) -> bool:
	var actor := trainer()
	return not ended and phase == PHASE_PLAYER and is_interaction_cell(cell) and (mentor.is_empty() or cell != mentor["cell"] or node_kind == "event") and actor != null and actor.is_alive() and GridSpec.manhattan(actor.cell, cell) == 1


func move_cost_for(unit: CombatUnit, cell: Vector2i) -> int:
	if is_interaction_cell(cell) or (is_nest_cell(cell) and not unit.has_buff("flight")):
		return -1
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
	return GridSpec.W * GridSpec.H * 3 if is_free_exploration() and unit.side == "player" else unit.effective_move()


func terrain_travel_mode(unit: CombatUnit) -> int:
	if unit == null:
		return -1
	var terrain := terrain_at(unit.cell)
	if terrain == TerrainDB.ICE and unit.ice_glide_until_round > 0 and unit.ice_glide_until_round >= round:
		return TerrainDB.ICE
	if TerrainDB.is_water_body(terrain) and unit.surf_until_round > 0 and unit.surf_until_round >= round:
		return TerrainDB.WATER
	return -1


func mirror_water_travel_active(unit: CombatUnit) -> bool:
	return unit != null and unit.mirror_until_round > 0 and unit.mirror_until_round >= round


func can_move_unit_now(unit: CombatUnit) -> bool:
	if is_free_exploration():
		return unit != null and unit.is_alive() and unit.side == "player"
	return unit != null and unit.channel_lock_round != round and unit.can_move_now(terrain_travel_mode(unit) >= 0 or mirror_water_travel_active(unit))


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
		if unit.side == "enemy" and unit.is_alive() and unit.summon_owner_uid < 0:
			count += 1
	return count


func active_summon(owner_uid: int) -> CombatUnit:
	for unit in units:
		if unit.summon_owner_uid == owner_uid and unit.is_alive():
			return unit
	return null


func summon_tree(owner: CombatUnit, cell: Vector2i) -> CombatUnit:
	if owner == null or not owner.is_alive() or active_summon(owner.uid) != null or not GridSpec.is_inside(cell) or unit_at(cell) != null or is_interaction_cell(cell) or is_nest_cell(cell) or terrain_blocks_move(cell) or not TerrainDB.can_stand(terrain_at(cell), "grass"):
		return null
	if owner.side == "player" and is_nest_cell(cell):
		return null
	var next_uid := 1
	for existing in units:
		next_uid = maxi(next_uid, existing.uid + 1)
	var summon := CombatUnit.make("tree_summon", owner.side, next_uid)
	next_enemy_uid = maxi(next_enemy_uid, next_uid + 1)
	summon.summon_owner_uid = owner.uid
	summon.cell = cell
	summon.reg_index = units.size()
	summon.fresh_spawn = true
	summon.max_hp += int(owner.upgrades.get("tree_man_hp_bonus", 0))
	var absorb_cells: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var neighbor := cell + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and GridSpec.is_inside(neighbor):
				absorb_cells.append(neighbor)
	for absorb_cell in absorb_cells:
		var terrain_type := terrain_at(absorb_cell)
		if terrain_type == TerrainDB.WATER or terrain_type == TerrainDB.DEEP:
			summon.max_hp += Balance.TREE_WATER_HP
		elif terrain_type == TerrainDB.GRASS or terrain_type == TerrainDB.VINES:
			summon.max_hp += Balance.TREE_GRASS_HP
		elif terrain_type == TerrainDB.TREE:
			summon.max_hp += 5
			summon.summon_power_bonus += 5
	summon.hp = summon.max_hp
	if inspiration_triggered:
		_grant_inspiration(summon)
	if summon.side == "enemy" and corruption_active:
		summon.set_corrupted(true)
	units.append(summon)
	_watch_feedback(summon)
	apply_vine_on_landing(summon)
	log_event("%s 召唤树人于 (%d,%d)，生命 %d；出生轮不能行动。" % [owner.display_name, cell.x, cell.y, summon.hp])
	return summon


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
	if feedback_enabled:
		presentation_started.emit({"kind": "result", "uid": unit.uid})
	_kill_unit_rules(unit, cause, killer_side, killer_uid)
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit({})


func _kill_unit_rules(unit: CombatUnit, cause: String, killer_side: String = "", killer_uid: int = -1) -> void:
	if unit.sheltered:
		return
	if unit.side == "enemy" and enemy_outcomes.has(unit.uid):
		return
	var terrain_kind := terrain_at(unit.cell)
	var text := "消散" if unit.summon_owner_uid >= 0 else "倒下"
	if unit.hp > 0 and terrain_kind == TerrainDB.PIT:
		text = "坠落"
	elif unit.hp > 0 and terrain_kind == TerrainDB.DEEP and unit.element != "water" and not unit.has_buff("flight"):
		text = "溺水"
	elif unit.hp > 0 and terrain_kind == TerrainDB.LAVA and not unit.has_buff("flight"):
		text = "落入熔岩"
	emit_feedback(unit, "death", text)
	cancel_channel(unit, "施法者倒下")
	for point in all_rewards():
		if point.get("state") == "guarding" and int(point.get("guard_uid", -1)) == unit.uid:
			point["state"] = "map"
			point["guard_uid"] = -1
		if point.get("state") == "carried" and int(point.get("owner_uid", -1)) == unit.uid:
			if unit.side == "enemy" and not TerrainDB.is_lethal(terrain_kind):
				point["state"] = "map"
				point["cell"] = unit.cell
				point["owner_uid"] = -1
				point["guard_uid"] = -1
				_relay_feedback("buff", "奖励点掉落", 0, unit.cell, -1)
			else:
				point["state"] = "lost"
	if unit.side == "enemy" and unit.reward_carrier:
		unit.reward_carrier = false
		if not TerrainDB.is_lethal(terrain_kind):
			add_reward_point(unit.cell, "enemy:%d" % unit.uid)
	if unit.is_trainer:
		unit.hp = 0
		log_event("训练家落入致死地形，本局立即失败。")
		end_battle("forced_retreat")
		return
	unit.hp = 0
	if unit.summon_owner_uid >= 0:
		if unit.side == "enemy" and killer_side == "player":
			award_battle_experience("kill:%d" % unit.uid, 0 if unit.corrupted else 1)
		log_event("%s 消散（%s）。" % [unit.display_name, cause])
		return
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
		enemy_outcomes[unit.uid] = "defeated"
		var killer := unit_by_uid(killer_uid)
		if killer_side == "player":
			earn_essence("enemy:%d" % unit.uid, 10 if unit.is_boss else 3, unit.cell)
		if killer != null and killer.summon_owner_uid >= 0:
			killer_uid = killer.summon_owner_uid
		enemy_kills.append({
			"uid": unit.uid,
			"enemy_level": unit.enemy_level,
			"xp_reward": 0 if unit.corrupted or (unit.spawned_from_nest and unit.spawn_round > Balance.REINFORCEMENT_XP_LAST_ROUND) else Balance.xp_for_enemy_level(unit.enemy_level),
			"corrupted": unit.corrupted,
			"species_id": unit.species_id,
			"by_player": killer_side == "player",
			"killer_side": killer_side,
			"killer_uid": killer_uid if killer_side == "player" else -1,
			"level": unit.enemy_level,
			"is_boss": unit.is_boss,
			"is_summon": unit.summon_owner_uid >= 0,
			"cause": cause,
		})
		if killer_side == "player":
			award_kill_experience(enemy_kills.back())
		log_event("野生 %s 被击败（%s）。" % [unit.display_name, cause])
		if feedback_enabled:
			enemy_defeated.emit(enemy_kills.back().duplicate())


func award_battle_experience(event_id: String, amount: int, include_fainted: bool = false, recipient_amounts: Dictionary = {}) -> void:
	if experience_events.has(event_id):
		return
	experience_events[event_id] = {}
	for uid in experience_recipients:
		var unit := unit_by_uid(int(uid))
		if unit == null or unit.side != "player" or unit.summon_owner_uid >= 0 or (not include_fainted and not unit.is_alive()):
			continue
		var old_xp := unit.combat_xp
		var old_level := unit.combat_level
		unit.combat_xp = mini(MonsterProgression.threshold_for_level(10), unit.combat_xp + maxi(0, int(recipient_amounts.get(uid, amount))))
		unit.combat_level = maxi(old_level, MonsterProgression.level_for_xp(unit.combat_xp))
		var added := MonsterProgression.max_hp(unit.species_id, unit.combat_level) - MonsterProgression.max_hp(unit.species_id, old_level)
		unit.max_hp += added
		if unit.is_alive():
			unit.hp += added
		experience_events[event_id][uid] = unit.combat_xp - old_xp
		experience_gains[uid] = int(experience_gains.get(uid, 0)) + unit.combat_xp - old_xp
		if unit.combat_xp > old_xp:
			emit_feedback(unit, "experience", "经验 +%d" % (unit.combat_xp - old_xp), unit.combat_xp - old_xp)
		if unit.combat_level > old_level:
			emit_feedback(unit, "buff", "升至Lv.%d · 生命+%d" % [unit.combat_level, added])


func on_captured(unit: CombatUnit, species_id: String, keep_hp: int) -> void:
	if unit.side != "enemy" or not unit.is_on_board() or enemy_outcomes.has(unit.uid):
		return
	unit.guard_nest = Vector2i(-1, -1)
	unit.guard_charge = false
	unit.reward_carrier = false
	unit.set_corrupted(false)
	for point in all_rewards():
		if point.get("state") == "carried" and int(point.get("owner_uid", -1)) == unit.uid:
			point["state"] = "lost"
		if point.get("state") == "guarding" and int(point.get("guard_uid", -1)) == unit.uid:
			point["state"] = "map"
			point["guard_uid"] = -1
	enemy_outcomes[unit.uid] = "captured"
	cancel_channel(unit, "阵营改变")
	emit_feedback(unit, "action", "捕获成功")
	var join_cell := _find_capture_join_cell(unit) if is_nest_cell(unit.cell) else unit.cell
	var field_join := bool(capture_options.get("capture_field_join", false))
	var was_boss := unit.is_boss
	captured.append({"species_id": species_id, "hp": keep_hp, "uid": unit.uid, "on_field": field_join, "was_boss": was_boss, "enemy_level": unit.enemy_level, "xp_reward": Balance.EXP_PER_CAPTURE})
	award_battle_experience("capture:%d" % unit.uid, Balance.xp_for_event(captured.back()))
	if feedback_enabled:
		enemy_captured.emit(captured.back().duplicate())
	if unit.inspired:
		unit.inspired = false
		unit.max_hp = maxi(1, unit.max_hp - Balance.INSPIRATION_HP_BONUS)
	if unit.side == "enemy":
		unit.max_hp = SpeciesDB.hp_of(species_id)
		unit.hp = mini(unit.hp, unit.max_hp)
		unit.enemy_level = 1
		unit.combat_level = 1
		unit.is_boss = false
		unit.upgrades.clear()
	if field_join:
		if GridSpec.is_inside(join_cell):
			unit.cell = join_cell
		unit.side = "player"
		unit.hp = clampi(keep_hp, 1, unit.max_hp)
		unit.moved = false
		unit.skill_used = false
		unit.capture_used = false
		unit.fresh_spawn = false
		log_event("%s 被捕获，%s，本回合可移动和施法。" % [unit.display_name, "转到附近合法格后加入我方" if GridSpec.is_inside(join_cell) else "原地加入我方"])
	else:
		unit.hp = 0
		log_event("%s 被捕获，%s。" % [unit.display_name, "巢穴格不能由我方占据，改为离开战场" if is_nest_cell(unit.cell) else "离开战场"])


func _find_capture_join_cell(unit: CombatUnit) -> Vector2i:
	var candidates := GridSpec.all_cells()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := GridSpec.manhattan(a, unit.cell)
		var db := GridSpec.manhattan(b, unit.cell)
		return da < db if da != db else _cell_order(a) < _cell_order(b)
	)
	for cell in candidates:
		if cell == unit.cell or unit_at(cell) != null or is_nest_cell(cell) or is_interaction_cell(cell):
			continue
		if not terrain_blocks_move(cell) and TerrainDB.can_stand(terrain_at(cell), unit.element):
			return cell
	return Vector2i(-1, -1)


func enforce_player_nest_landing_rule() -> void:
	for unit in alive_units("player"):
		if not is_nest_cell(unit.cell):
			continue
		var destination := _find_capture_join_cell(unit)
		if GridSpec.is_inside(destination):
			unit.cell = destination
			log_event("%s 位于旧存档的巢穴格，已转移到附近合法格。" % unit.display_name)


# ---------------------------------------------------------------- 伤害

func damage_unit(source: CombatUnit, target: CombatUnit, base: int, opts: Dictionary) -> Dictionary:
	if target == null or not target.is_on_board() or base <= 0:
		return {"amount": 0, "killed": false}
	if source != null and source.side == "player" and target.side == "enemy":
		preload("res://scripts/rules/capture_encounter.gd").alert(self)
	var break_frozen := target.frozen and bool(opts.get("break_frozen", false))
	var was_frozen_before_hit := target.frozen
	var hit_element := String(opts.get("element", ""))
	var was_burning := target.burn_ticks > 0
	var matchup_modifier := 0 if bool(opts.get("no_element", false)) else Elements.modifier(hit_element, target.element)
	var amount := calculate_damage(source, target, base, opts)
	if bool(opts.get("guard_share_half", false)):
		amount = amount / 2
	var guard_divisor := maxi(1, int(opts.get("guard_divisor", 1)))
	if guard_divisor > 1:
		amount = amount / guard_divisor + (1 if int(opts.get("guard_rank", 0)) < amount % guard_divisor else 0)
	if amount > 0 and target.mirror_until_round > 0 and target.mirror_until_round >= round:
		target.mirror_until_round = 0
		emit_feedback(target, "shield", "镜花水月·免疫", 0)
		log_event("镜花水月的镜影替 %s 承受了 %d 点伤害。" % [target.display_name, amount])
		return {"amount": 0, "killed": false, "previous_hp": target.hp, "hp": target.hp, "mirror_immune": true}
	var shield_absorbed := 0
	var shield_broken := false
	var shield_burst_hits: Array = []
	if amount > 0 and target.shield_hp > 0:
		shield_absorbed = mini(amount, target.shield_hp)
		target.shield_hp -= shield_absorbed
		amount -= shield_absorbed
		emit_feedback(target, "shield", "护盾 -%d" % shield_absorbed, shield_absorbed)
		log_event("%s 的护盾抵挡了 %d 点伤害，剩余护盾 %d。" % [target.display_name, shield_absorbed, target.shield_hp])
		if target.shield_hp <= 0:
			var shield_source := unit_by_uid(target.shield_source_uid)
			target.shield_ticks = 0
			target.shield_source_uid = -1
			shield_broken = true
			shield_burst_hits = _trigger_guard_rock_break(target, shield_source)
	if shield_absorbed > 0 and amount <= 0:
		return {
			"amount": 0,
			"killed": false,
			"previous_hp": target.hp,
			"hp": target.hp,
			"shield_absorbed": shield_absorbed,
			"shield_broken": shield_broken,
			"shield_burst_hits": shield_burst_hits,
		}
	var absorbed_from_uid := -1
	var absorbed_by_uid := -1
	if amount > 0:
		var mountain_bearer := _mountain_form_bearer(target)
		if mountain_bearer != null:
			absorbed_from_uid = target.uid
			absorbed_by_uid = mountain_bearer.uid
			amount = mountain_form_reduced_damage(amount)
			if mountain_bearer.uid != target.uid:
				emit_feedback(target, "shield", "山岳形态·转移", 0)
				log_event("%s 的山岳形态吸收 %s 受到的伤害，减免至 %d 并由自身承受。" % [
					mountain_bearer.display_name, target.display_name, amount,
				])
				target = mountain_bearer
				break_frozen = false
				was_frozen_before_hit = target.frozen
				was_burning = target.burn_ticks > 0
				matchup_modifier = 0
			else:
				log_event("%s 的山岳形态将受到的伤害减免至 %d。" % [target.display_name, amount])
	if amount > 0:
		damage_reward_at(target.cell)
	if break_frozen:
		amount *= int(opts.get("frozen_multiplier", 1))
	if amount > 0 and target.frozen:
		target.frozen_ticks = 0
		target.frozen = false
		cancel_channel(target, "受到伤害解除冰冻")
		log_event("%s 受到 %d 点伤害，冰冻解除。" % [target.display_name, amount])
	if amount > 0 and not bool(opts.get("parasite_tick", false)) and target.parasite_source_uid >= 0:
		target.parasite_source_uid = -1
		target.parasite_source_side = ""
		target.parasite_ticks = 0
		log_event("%s 受到其他伤害，寄生解除。" % target.display_name)
	var cause: String = opts.get("cause", "伤害")
	var previous_hp := target.hp
	target.hp -= amount
	if bool(opts.get("collision", false)):
		emit_feedback(target, "collision_damage", "碰撞 -%d" % amount if amount > 0 else "碰撞未受伤", amount)
	else:
		emit_feedback(target, "damage" if amount > 0 else "zero", "-%d" % amount if amount > 0 else "未受伤", amount)
	if amount > 0 and source != null and bool(opts.get("skill_direct", false)) and not bool(opts.get("no_element", false)) and matchup_modifier != 0:
		emit_feedback(target, "effective" if matchup_modifier > 0 else "resisted", "效果拔群（克制）" if matchup_modifier > 0 else "效果不佳（抵抗）", matchup_modifier)
	if target.uid == boss_uid and target.side == "enemy" and amount > 0 and previous_hp * 2 > target.max_hp and target.hp > 0 and target.hp * 2 <= target.max_hp:
		_trigger_inspiration()
	var source_name := source.display_name if source != null else "环境"
	var matchup_text := ""
	if matchup_modifier > 0:
		matchup_text = "（属性克制 ×1.25）"
	elif matchup_modifier < 0:
		matchup_text = "（属性逆克制 ×0.75）"
	log_event("%s 对 %s 造成 %d 伤害%s。" % [source_name, target.display_name, amount, matchup_text])
	var killed := false
	var relic_healed := 0
	if target.is_trainer and target.hp <= 0:
		target.hp = 0
		emit_feedback(target, "death", "倒下")
		log_event("训练家倒下！本局立即失败。")
		end_battle("forced_retreat")
		return {"amount": amount, "killed": true}
	if target.hp <= 0:
		killed = true
		var killer_side: String = source.side if source != null else String(opts.get("killer_side", ""))
		kill_unit(target, cause, killer_side, source.uid if source != null else int(opts.get("killer_uid", -1)))
	var thawed_wet := false
	if amount > 0 and was_frozen_before_hit and target.is_alive() and source != null and bool(opts.get("skill_direct", false)) and hit_element == "fire":
		thawed_wet = apply_wet(target, 1)
	if source != null and source.side == "player" and target.side == "enemy" and bool(opts.get("skill_direct", false)) and amount > 0:
		if killed and was_burning and source.is_alive():
			var healed := mini(source.max_hp - source.hp, 4 * RelicDB.rank(relic_stacks, "ember_recovery"))
			if healed > 0:
				source.hp += healed
				feedback_heal(source, healed)
				relic_healed = healed
				log_event("余烬：%s 恢复 %d HP。" % [source.display_name, healed])
		elif not killed:
			if hit_element == "fire" and RelicDB.rank(relic_stacks, "fire_mark") > 0 and target.burn_ticks <= 0:
				apply_burn(target, source)
			if hit_element == "water" and RelicDB.rank(relic_stacks, "water_mark") > 0 and target.slow_ticks <= 0:
				apply_slow(target)
	if amount > 0 and target.uid == boss_uid:
		_try_shelter_boss()
	return {
		"amount": amount,
		"killed": killed,
		"previous_hp": previous_hp,
		"hp": target.hp,
		"relic_healed": relic_healed,
		"thawed_wet": thawed_wet,
		"absorbed_from_uid": absorbed_from_uid,
		"absorbed_by_uid": absorbed_by_uid,
		"shield_absorbed": shield_absorbed,
		"shield_broken": shield_broken,
		"shield_burst_hits": shield_burst_hits,
	}


func _trigger_guard_rock_break(target: CombatUnit, shield_source: CombatUnit) -> Array:
	var hits: Array = []
	var source := shield_source if shield_source != null and shield_source.is_alive() and shield_source.side == target.side else null
	emit_feedback(target, "shield", "守岩破盾", Balance.GUARD_ROCK_BREAK_DAMAGE)
	log_event("%s 的护盾被破坏，向四邻格敌人释放守岩冲击。" % target.display_name)
	for cell in GridSpec.neighbors4(target.cell):
		var enemy := unit_at(cell)
		if enemy == null or not enemy.is_alive() or enemy.side == target.side:
			continue
		var result := damage_unit(source, enemy, Balance.GUARD_ROCK_BREAK_DAMAGE, {
			"no_element": true,
			"cause": "守岩破盾",
			"killer_side": target.side,
			"killer_uid": source.uid if source != null else -1,
		})
		hits.append({
			"uid": enemy.uid,
			"name": enemy.display_name,
			"cell": cell,
			"damage": int(result.get("amount", 0)),
			"killed": bool(result.get("killed", false)),
		})
	return hits


static func mountain_form_reduced_damage(amount: int) -> int:
	return maxi(1, ceili(float(amount) * 2.0 / 3.0))


func _mountain_form_bearer(target: CombatUnit) -> CombatUnit:
	if target == null or not target.is_alive():
		return null
	if target.mountain_form_ticks > 0:
		return target
	for unit in alive_units(target.side):
		if unit.mountain_form_ticks <= 0:
			continue
		var offset: Vector2i = target.cell - unit.cell
		var radius := 1 + int(unit.upgrades.get("mountain_form_radius", 0))
		if absi(offset.x) <= radius and absi(offset.y) <= radius:
			return unit
	return null


func apply_guard_rock_shield(target: CombatUnit, amount: int, source_uid: int = -1) -> bool:
	if target == null or not target.is_alive() or amount <= 0:
		return false
	var was_active := target.shield_hp > 0
	target.shield_hp = maxi(target.shield_hp, amount)
	target.shield_ticks = Balance.SHIELD_TICKS
	target.shield_source_uid = source_uid
	log_event("%s 获得 %d 点护盾，持续 %d 回合%s。" % [
		target.display_name,
		target.shield_hp,
		target.shield_ticks,
		"（刷新）" if was_active else "",
	])
	return true


func clear_guard_rock_shield(target: CombatUnit, expired: bool = false) -> void:
	if target == null:
		return
	var had_shield := target.shield_hp > 0
	target.shield_hp = 0
	target.shield_ticks = 0
	target.shield_source_uid = -1
	if expired and had_shield:
		log_event("%s 的护盾持续两回合后消失。" % target.display_name)


func apply_burn(target: CombatUnit, source: CombatUnit) -> bool:
	if target.has_buff("status_immune"):
		return false
	if target.element == "fire":
		return false
	if not target.is_alive():
		return false
	var was_burning := target.burn_ticks > 0
	var burn_ticks := Balance.BURN_TICKS
	target.burn_ticks = burn_ticks
	target.burn_source_uid = source.uid if source != null else -1
	target.burn_source_side = source.side if source != null else ""
	if not was_burning:
		log_event("%s 被点燃（灼烧 %d 回合）。" % [target.display_name, burn_ticks])
	return true


func apply_burning_ground(unit: CombatUnit) -> bool:
	if unit == null or not unit.is_alive() or unit.has_buff("flight"):
		return false
	if unit.burn_ticks > 0 or not is_burning_ground(unit.cell):
		return false
	if not apply_burn(unit, null):
		return false
	unit.burn_source_side = String(burning_sources.get(unit.cell, ""))
	return true


func clear_burn(target: CombatUnit) -> void:
	if target == null:
		return
	target.burn_ticks = 0
	target.burn_source_uid = -1
	target.burn_source_side = ""


func apply_root(target: CombatUnit) -> void:
	target.root_pending = true
	log_event("%s 被定身：下一次移动机会将被取消。" % target.display_name)


func apply_imprison(target: CombatUnit, after_movement: bool = false) -> bool:
	if target == null or not target.is_alive():
		return false
	var ticks := 2
	if phase == target.side and (after_movement or target.moved):
		ticks = 3
	if ticks <= target.imprison_ticks:
		return false
	target.imprison_ticks = ticks
	log_event("%s 被禁锢 %d 回合：不能普通移动，但仍可进行其他行动。" % [target.display_name, ticks])
	return true


func apply_freeze(target: CombatUnit) -> bool:
	if target == null or not target.is_alive():
		return false
	var was_frozen := target.frozen
	target.frozen_ticks = Balance.FREEZE_TICKS
	target.frozen = true
	target.paralyzed_ticks = 0
	cancel_channel(target, "冰冻")
	if not was_frozen:
		log_event("%s 被冰冻 %d 回合，无法行动。" % [target.display_name, Balance.FREEZE_TICKS])
	return true


func apply_shock(target: CombatUnit, ticks: int = 1) -> bool:
	if target == null or not target.is_alive() or target.has_buff("status_immune"):
		return false
	if target.paralyzed_ticks > 0:
		target.shock_ticks = 0
		log_event("%s 仍处于麻痹，麻痹消除前不能施加感电。" % target.display_name)
		return false
	if target.shock_ticks > 0:
		target.shock_ticks = 0
		apply_paralysis(target)
		log_event("%s 的感电叠层转为麻痹。" % target.display_name)
		return true
	target.shock_ticks = maxi(1, ticks)
	log_event("%s 获得感电。" % target.display_name)
	return true


func apply_paralysis(target: CombatUnit, ticks: int = Balance.PARALYSIS_TICKS) -> bool:
	if target == null or not target.is_alive():
		return false
	var next_ticks := maxi(1, ticks)
	var changed := next_ticks > target.paralyzed_ticks
	target.shock_ticks = 0
	target.paralyzed_ticks = maxi(target.paralyzed_ticks, next_ticks)
	cancel_channel(target, "麻痹")
	if changed:
		log_event("%s 被麻痹 %d 回合。" % [target.display_name, target.paralyzed_ticks])
	return changed


func apply_wet(target: CombatUnit, ticks: int = 2) -> bool:
	if target == null or not target.is_alive() or target.element == "water" or target.has_buff("status_immune"):
		return false
	var was_wet := target.slow_ticks > 0
	target.slow_ticks = maxi(target.slow_ticks, maxi(1, ticks))
	if not was_wet:
		log_event("%s 获得浸湿：下一次移动力 -1。" % target.display_name)
	return true


func apply_slow(target: CombatUnit) -> void:
	apply_wet(target, 2)


func clear_wet(target: CombatUnit) -> void:
	if target != null:
		target.slow_ticks = 0


func has_removable_debuff(target: CombatUnit) -> bool:
	if target == null:
		return false
	return (
		target.burn_ticks > 0
		or target.slow_ticks > 0
		or target.shock_ticks > 0
		or target.paralyzed_ticks > 0
		or target.root_pending
		or target.move_cancelled
		or target.imprison_ticks > 0
		or target.vine_ticks > 0
		or not target.vine_sources.is_empty()
		or target.vine_reapply_round > 0
		or target.parasite_source_uid >= 0
	)


func clear_debuff_status(target: CombatUnit) -> bool:
	## 解药等净化效果共用入口；冰冻与正向 Buff 不在清除范围内。
	if target == null:
		return false
	var removed := has_removable_debuff(target)
	var ended_imprison := target.imprison_ticks > 0
	var remains_on_vines: bool = not target.has_buff("flight") and GridSpec.is_inside(target.cell) and terrain_at(target.cell) == TerrainDB.VINES
	clear_burn(target)
	clear_wet(target)
	target.shock_ticks = 0
	target.paralyzed_ticks = 0
	target.root_pending = false
	target.move_cancelled = false
	target.imprison_ticks = 0
	target.vine_sources.clear()
	target.vine_ticks = 0
	target.vine_reapply_round = 0
	target.vine_reapply_cell = Vector2i(-1, -1)
	target.parasite_source_uid = -1
	target.parasite_source_side = ""
	if ended_imprison and remains_on_vines:
		target.vine_reapply_round = round + 2
		target.vine_reapply_cell = target.cell
	return removed


func _apply_shallow_wet(side: String, ticks: int) -> void:
	# 阶段交接时只检查即将行动的一方；我方在敌方阶段结束后检查。
	# 地形只补足一层；离水后完成所属方行动即解除。
	for unit in alive_units(side):
		_apply_shallow_wet_to_unit(unit, ticks)


func _apply_shallow_wet_to_unit(unit: CombatUnit, ticks: int) -> void:
	if unit == null or not unit.is_alive() or unit.element == "water" or unit.has_buff("flight") or unit.has_buff("status_immune"):
		return
	if unit.side == "player" and int(effects.get("water_ignore", 0)) > 0:
		return
	if terrain_at(unit.cell) != TerrainDB.WATER:
		return
	if unit.slow_ticks == 0:
		log_event("%s 站在浅水中，获得浸湿（下一次移动力 -1）。" % unit.display_name)
	unit.slow_ticks = maxi(unit.slow_ticks, ticks)


func _movement_effect_ticks(unit: CombatUnit) -> int:
	# 己方阶段内还可移动，效果覆盖本次机会；已经移动则保留到下次机会。
	# 在对方阶段或整轮结算获得效果时，下一次己方阶段就是目标机会。
	if phase != unit.side:
		return 1
	if unit.moved or unit.fresh_spawn or unit.frozen or unit.paralyzed_ticks > 0 or unit.move_cancelled or unit.vine_ticks > 0:
		return 2
	return 1


func apply_vine_bind(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive() or unit.has_buff("flight"):
		return
	unit.vine_reapply_round = 0
	unit.vine_reapply_cell = Vector2i(-1, -1)
	apply_imprison(unit)


func apply_vine_on_landing(unit: CombatUnit, after_movement: bool = true) -> void:
	if unit != null: capture_exit_wait.erase(unit.uid)
	if unit != null and unit.guard_nest.x >= 0 and GridSpec.manhattan(unit.cell, unit.guard_nest) != 1:
		unit.guard_charge = false
	_refresh_reward_guard()
	apply_burning_ground(unit)
	if unit == null:
		return
	if unit.vine_reapply_round > 0 and unit.cell != unit.vine_reapply_cell:
		unit.vine_reapply_round = 0
		unit.vine_reapply_cell = Vector2i(-1, -1)
	if not unit.has_buff("flight") and GridSpec.is_inside(unit.cell) and terrain_at(unit.cell) == TerrainDB.VINES:
		if apply_imprison(unit, after_movement):
			unit.vine_reapply_round = 0
			unit.vine_reapply_cell = Vector2i(-1, -1)


func _refresh_vine_ticks(unit: CombatUnit) -> void:
	unit.vine_ticks = 0
	for ticks in unit.vine_sources.values():
		unit.vine_ticks = maxi(unit.vine_ticks, int(ticks))


func apply_haste(unit: CombatUnit) -> void:
	if unit == null or not unit.is_alive():
		return
	unit.haste_ticks = maxi(unit.haste_ticks, _movement_effect_ticks(unit))


func _finish_movement_effects(side: String) -> void:
	for unit in units:
		if unit.side != side or unit.sheltered:
			continue
		if unit.vine_sources.is_empty():
			unit.vine_ticks = maxi(0, unit.vine_ticks - 1)
		else:
			for cell in unit.vine_sources.keys().duplicate():
				var ticks := int(unit.vine_sources[cell]) - 1
				if ticks <= 0:
					unit.vine_sources.erase(cell)
				else:
					unit.vine_sources[cell] = ticks
			_refresh_vine_ticks(unit)
		unit.haste_ticks = maxi(0, unit.haste_ticks - 1)
		var had_imprison: bool = unit.imprison_ticks > 0
		unit.imprison_ticks = maxi(0, unit.imprison_ticks - 1)
		if had_imprison and unit.imprison_ticks <= 0 and not unit.has_buff("flight") and GridSpec.is_inside(unit.cell) and terrain_at(unit.cell) == TerrainDB.VINES:
			unit.vine_reapply_round = round + 2
			unit.vine_reapply_cell = unit.cell


func claim_obstacle_essence(cell: Vector2i, source_side: String) -> void:
	if natural_essence_cells.has(cell):
		natural_essence_cells.erase(cell)
		var original: Vector2i = obstacle_reward_origins.get(cell, cell)
		if source_side == "player":
			earn_essence("terrain:%d:%d" % [original.x, original.y], 1, cell)
	obstacle_reward_origins.erase(cell)


func damage_obstacle(cell: Vector2i, amount: int, source_side: String = "", skill_id: String = "", summary: Dictionary = {}) -> bool:
	if electric_flowers.has(cell) and amount > 0:
		return _hit_electric_flower(cell, amount, source_side, skill_id, summary)
	var facility_id := camp_facility_at(cell)
	if facility_id != "" and amount > 0:
		var left := maxi(0, int(obstacle_durability.get(cell, 0)) - amount)
		if left > 0:
			obstacle_durability[cell] = left
		else:
			camp_facilities[facility_id]["destroyed"] = true
			obstacle_durability.erase(cell)
			terrain[GridSpec.index(cell)] = TerrainDB.PLAIN
		log_event("%s耐久剩余%d；被毁后本层永久失去服务。" % [camp_facilities[facility_id]["name"], left])
		return left == 0
	if amount > 0 and is_chest_cell(cell):
		chests.erase(cell)
		obstacle_origin.erase(cell)
		obstacle_expire_round.erase(cell)
		obstacle_reward_origins.erase(cell)
		natural_essence_cells.erase(cell)
		obstacle_durability.erase(cell)
		set_terrain(cell, TerrainDB.PLAIN)
		add_reward_point(cell, "chest:%d:%d" % [cell.x, cell.y])
		log_event("宝箱被打开，原格生成奖励点。")
		return true
	if not obstacle_durability.has(cell):
		return false
	var left := int(obstacle_durability[cell]) - amount
	if left <= 0:
		claim_obstacle_essence(cell, source_side)
		var drop_food := node_kind != "" and terrain_at(cell) == TerrainDB.TREE and terrain_rng.randf() < 0.25 and not food_cells.has(cell)
		obstacle_durability.erase(cell)
		burning_cells.erase(cell)
		burning_origin.erase(cell)
		burning_forced.erase(cell)
		var origin := int(obstacle_origin.get(cell, TerrainDB.PLAIN))
		obstacle_origin.erase(cell)
		obstacle_expire_round.erase(cell)
		set_terrain(cell, origin)
		if drop_food and food_cell_valid(cell):
			food_cells.append(cell)
		log_event("障碍被破坏，恢复为%s。" % TerrainDB.name_of(origin))
		return true
	obstacle_durability[cell] = left
	log_event("障碍耐久 -%d（剩 %d）。" % [amount, left])
	return false


func _hit_electric_flower(cell: Vector2i, amount: int, source_side: String, skill_id: String, summary: Dictionary) -> bool:
	var remaining := maxi(0, int(obstacle_durability[cell]) - amount)
	if remaining == 0:
		claim_obstacle_essence(cell, source_side)
		obstacle_durability.erase(cell)
		electric_flowers.erase(cell)
	else:
		obstacle_durability[cell] = remaining
	log_event("电电花耐久剩余 %d。" % remaining)
	if skill_id.is_empty():
		return remaining == 0
	var fire_hit := SkillDB.element_of(skill_id) == "fire"
	var wide := fire_hit or TerrainDB.is_water_body(terrain_at(cell))
	var adjacent := GridSpec.neighbors8(cell) if wide else GridSpec.neighbors4(cell)
	log_event("电电花%s。" % ("向八邻爆燃" if fire_hit else "释放闪电"))
	for near in adjacent:
		var target := unit_at(near)
		if target == null:
			continue
		var damage := 0
		var killed := false
		var statuses: Array = []
		if fire_hit:
			var hit := damage_unit(null, target, ceili(target.max_hp * 0.10), {
				"no_element": true, "ignore_grass_cover": true,
				"cause": "电电花爆燃", "killer_side": source_side, "killer_uid": int(summary.get("caster_uid", -1)),
			})
			damage = int(hit.get("amount", 0))
			killed = bool(hit.get("killed", false))
		else:
			# 敌方行动后立即跨轮，需保留到下一次我方行动。
			var ticks := 2 if phase == PHASE_ENEMY and target.side == "player" else 1
			if apply_paralysis(target, ticks):
				statuses.append("麻痹")
				emit_feedback(target, "status", "麻痹 1 回合")
		if summary.has("hits"):
			summary["hits"].append({"uid": target.uid, "name": target.display_name, "cell": near,
				"damage": damage, "killed": killed, "modifier": 0, "statuses": statuses, "push": null})
	return remaining == 0


func damage_nest(amount: int, source_side: String = "", target_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	var target_nest: Dictionary = nest if target_cell.x < 0 else nest_at_cell(target_cell)
	if not bool(target_nest.get("alive", false)):
		return false
	if amount <= 0:
		return false
	var actual := mini(amount, int(target_nest["hp"]))
	target_nest["hp"] = maxi(0, int(target_nest["hp"]) - amount)
	_relay_feedback("damage", "生命 -%d" % actual, actual, target_nest["cell"], -1)
	if int(target_nest["hp"]) <= 0:
		if source_side == "player":
			earn_essence("nest" if target_nest == nest else "nest:%d:%d" % [target_nest["cell"].x, target_nest["cell"].y], 8, target_nest["cell"])
		target_nest["alive"] = false
		add_reward_point(target_nest["cell"], "nest:%d:%d" % [target_nest["cell"].x, target_nest["cell"].y])
		target_nest["destroyed_by_player"] = source_side == "player"
		set_terrain(target_nest["cell"], TerrainDB.PLAIN)
		log_event("巢穴被摧毁，永久停止生成。")
		try_release_boss()
		if node_kind == "" and boss_uid < 0 and not has_live_nests():
			end_battle("victory")
		return true
	log_event("巢穴生命 -%d（剩 %d/%d）。" % [actual, target_nest["hp"], target_nest.get("max_hp", Balance.nest_max_hp(battle_index))])
	return false


func nest_covered(_target_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	# 兼容旧技能汇总字段；巢穴现在不允许占格，守护由主动分伤处理。
	return false


func active_nest_guards(cell: Vector2i) -> Array:
	var guards: Array = []
	if not is_nest_cell(cell):
		return guards
	for unit in alive_units("enemy"):
		if unit.guard_charge and unit.guard_nest == cell and GridSpec.manhattan(unit.cell, cell) == 1 and not unit.fresh_spawn and not unit.frozen and unit.paralyzed_ticks <= 0:
			guards.append(unit)
	guards.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool: return a.uid < b.uid)
	return guards


func nest_guard_charges(cell: Vector2i) -> int:
	return active_nest_guards(cell).size() # 兼容旧名称，现返回守军数量，不是消耗次数。


func can_guard_nest(unit: CombatUnit, cell: Vector2i) -> bool:
	return unit != null and unit.side == "enemy" and unit.can_act_skill() and unit.channel_lock_round != round and is_nest_cell(cell) and GridSpec.manhattan(unit.cell, cell) == 1


func begin_nest_guard(unit: CombatUnit, cell: Vector2i) -> bool:
	if not can_guard_nest(unit, cell):
		return false
	unit.guard_nest = cell
	unit.guard_charge = true
	unit.skill_used = true
	unit.extra_casts = 0
	emit_feedback(unit, "buff", "守护巢穴")
	log_event("%s 放弃本阶段施法，守护巢穴至下次敌方阶段；巢穴承受一半，其余由守军均分。" % unit.display_name)
	return true


func relocate_nest_occupants() -> void:
	for unit in units:
		if not unit.is_on_board() or not is_nest_cell(unit.cell):
			continue
		var origin: Vector2i = unit.cell
		var candidates := GridSpec.all_cells()
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := GridSpec.manhattan(a, origin)
			var db := GridSpec.manhattan(b, origin)
			return da < db if da != db else _cell_order(a) < _cell_order(b))
		for cell in candidates:
			if is_nest_cell(cell) or is_interaction_cell(cell) or unit_at(cell) != null or terrain_blocks_move(cell) or not TerrainDB.can_stand(terrain_at(cell), unit.element):
				continue
			unit.cell = cell
			unit.last_move_direction = Vector2i.ZERO
			break


func place_temp_obstacle(cell: Vector2i, origin: int, expire_round: int) -> void:
	if electric_flowers.has(cell) or is_nest_cell(cell) or is_chest_cell(cell) or camp_facility_at(cell) != "":
		return
	natural_essence_cells.erase(cell)
	obstacle_reward_origins.erase(cell)
	set_terrain(cell, TerrainDB.OBSTACLE)
	obstacle_durability[cell] = Balance.OBSTACLE_DURABILITY
	obstacle_origin[cell] = origin
	obstacle_expire_round[cell] = expire_round


# ---------------------------------------------------------------- 我方移动

func move_options(unit: CombatUnit) -> Dictionary:
	if not can_move_unit_now(unit):
		return {}
	return PathFinder.stop_cells(self, unit)


func move_unit(unit: CombatUnit, dest: Vector2i) -> bool:
	if feedback_enabled:
		var options := move_options(unit) if unit != null else {}
		presentation_started.emit({"kind": "move", "uid": unit.uid if unit != null else -1, "path": options.get(dest, {}).get("path", [dest])})
	var result := _move_unit_rules(unit, dest)
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit({"ok": result})
	return result


func _move_unit_rules(unit: CombatUnit, dest: Vector2i) -> bool:
	if phase != PHASE_PLAYER or ended or not can_move_unit_now(unit):
		return false
	var options := PathFinder.stop_cells(self, unit)
	if not options.has(dest):
		return false
	var path: Array = options[dest]["path"]
	var movement_used_before := unit.moved
	var free_terrain_move := bool(options[dest].get("terrain_travel", false))
	var from_cell := unit.cell
	var food_wait_before := food_wait.duplicate()
	food_wait.erase(from_cell)
	var burn_ticks_before := unit.burn_ticks
	var burn_source_uid_before := unit.burn_source_uid
	var burn_source_side_before := unit.burn_source_side
	var direction_before := unit.last_move_direction
	var imprison_ticks_before := unit.imprison_ticks
	var vine_reapply_round_before := unit.vine_reapply_round
	var vine_reapply_cell_before := unit.vine_reapply_cell
	var vine_ticks_before := unit.vine_ticks
	var vine_sources_before := unit.vine_sources.duplicate()
	for step in path:
		unit.last_move_direction = step - unit.cell
		unit.cell = step
	unit.moved = movement_used_before if free_terrain_move else true
	apply_vine_on_landing(unit)
	var pickup := try_pickup_fruit(unit)
	undo_stack.append({
		"uid": unit.uid,
		"food_wait_before": food_wait_before,
		"from": from_cell,
		"burn_ticks": burn_ticks_before,
		"burn_source_uid": burn_source_uid_before,
		"burn_source_side": burn_source_side_before,
		"direction": direction_before,
		"moved_before": movement_used_before,
		"imprison_ticks": imprison_ticks_before,
		"vine_reapply_round": vine_reapply_round_before,
		"vine_reapply_cell": vine_reapply_cell_before,
		"vine_ticks": vine_ticks_before,
		"vine_sources": vine_sources_before,
		"fruit_cell": pickup.get("cell", Vector2i(-1, -1)),
		"fruit_gained": int(pickup.get("gained", 0)),
	})
	if is_free_exploration():
		reset_exploration_actions()
		_pickups()
		_begin_reward_guard()
		_refresh_reward_guard()
		_finish_reward_guard()
		commit_actions()
	log_event("%s 移动到 (%d,%d)。" % [unit.display_name, dest.x, dest.y])
	return true


func undo_last_move() -> bool:
	if phase != PHASE_PLAYER or ended or undo_stack.is_empty():
		return false
	var entry: Dictionary = undo_stack.pop_back()
	food_wait = (entry.get("food_wait_before", food_wait) as Dictionary).duplicate()
	var unit := unit_by_uid(int(entry["uid"]))
	if unit == null:
		return false
	var feedback_was_enabled := feedback_enabled
	feedback_enabled = false
	unit.cell = entry["from"]
	unit.burn_ticks = int(entry["burn_ticks"])
	unit.burn_source_uid = int(entry["burn_source_uid"])
	unit.burn_source_side = String(entry["burn_source_side"])
	unit.last_move_direction = entry.get("direction", Vector2i.ZERO)
	unit.imprison_ticks = int(entry.get("imprison_ticks", unit.imprison_ticks))
	unit.vine_reapply_round = int(entry.get("vine_reapply_round", unit.vine_reapply_round))
	unit.vine_reapply_cell = entry.get("vine_reapply_cell", unit.vine_reapply_cell)
	unit.vine_ticks = int(entry.get("vine_ticks", 0))
	unit.vine_sources = (entry.get("vine_sources", {}) as Dictionary).duplicate()
	var fruit_cell: Vector2i = entry.get("fruit_cell", Vector2i(-1, -1))
	if fruit_cell != Vector2i(-1, -1):
		fruits.append(fruit_cell)
		unit.hp = maxi(1, unit.hp - int(entry.get("fruit_gained", 0)))
	unit.moved = bool(entry.get("moved_before", false))
	feedback_enabled = feedback_was_enabled
	log_event("%s 撤回到 (%d,%d)。" % [unit.display_name, unit.cell.x, unit.cell.y])
	return true


func commit_actions() -> void:
	undo_stack.clear()


func can_undo() -> bool:
	return phase == PHASE_PLAYER and not ended and not undo_stack.is_empty()


# ---------------------------------------------------------------- 技能与捕获

func skill_targets(unit: CombatUnit, skill_id: String) -> Array:
	if unit == null or unit.channel_lock_round == round or not unit.skills.has(skill_id) or (steam_cells.has(unit.cell) and not is_free_exploration()):
		return []
	var entries := SkillResolver.targets(self, unit, skill_id)
	return entries


func preview_skill(unit: CombatUnit, skill_id: String, target_entry: Dictionary) -> Dictionary:
	if unit == null or unit.channel_lock_round == round or not unit.skills.has(skill_id):
		return {"ok": false}
	var clone := clone()
	var clone_unit := clone.unit_by_uid(unit.uid)
	if clone_unit == null:
		return {"ok": false}
	return SkillResolver.apply(clone, clone_unit, skill_id, target_entry, true)


func cast_skill(unit: CombatUnit, skill_id: String, target_entry: Dictionary) -> Dictionary:
	if unit == null or ended or unit.channel_lock_round == round or not unit.can_act_skill() or not unit.skills.has(skill_id):
		return {"ok": false}
	if steam_cells.has(unit.cell) and not is_free_exploration():
		return {"ok": false}
	if not unit.can_use_in_battle(skill_id):
		return {"ok": false}
	var skill_used_before := unit.skill_used
	var result := SkillResolver.apply(self, unit, skill_id, target_entry, false)
	if bool(result.get("ok", false)):
		_record_skill_use(unit.side, skill_id)
		if skill_used_before and unit.extra_casts > 0:
			unit.extra_casts -= 1
		else:
			unit.skill_used = true
		commit_actions()
		check_battle_end()
		if is_free_exploration():
			reset_exploration_actions()
			_pickups()
	return result


func _record_skill_use(side: String, skill_id: String) -> void:
	if not skill_use_counts.has(side):
		return
	var counts: Dictionary = skill_use_counts[side]
	counts[skill_id] = int(counts.get(skill_id, 0)) + 1


func can_begin_channel(caster: CombatUnit) -> bool:
	if caster == null or caster.guard_nest.x >= 0:
		return false
	var claim: Dictionary = channel_claims.get(caster.side, {})
	return int(claim.get("round", -1)) != round or int(claim.get("uid", -1)) == caster.uid


func begin_channel(caster: CombatUnit, skill_id: String, cells: Array) -> bool:
	if not can_begin_channel(caster):
		return false
	channel_claims[caster.side] = {"round": round, "uid": caster.uid}
	pending_casts.append({"uid": caster.uid, "side": caster.side, "skill_id": skill_id,
		"cells": cells.duplicate(), "due_round": round + 1})
	caster.channel_lock_round = round + 1
	caster.moved = true
	caster.skill_used = true
	emit_feedback(caster, "skill", "%s开始吟唱%s" % [caster.display_name, SkillDB.name_of(skill_id)])
	emit_feedback(caster, "action", "开始吟唱")
	log_event("%s 开始吟唱%s，落点已标记；下次本方阶段不能行动。" % [caster.display_name, SkillDB.name_of(skill_id)])
	return true


func cancel_channel(unit: CombatUnit, reason: String) -> void:
	for index in range(pending_casts.size() - 1, -1, -1):
		if int(pending_casts[index]["uid"]) == unit.uid:
			pending_casts.remove_at(index)
			emit_feedback(unit, "action", "吟唱中断")
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
		if ended or is_free_exploration():
			break
		pending_casts.erase(entry)
		var caster := unit_by_uid(int(entry["uid"]))
		if caster == null or not caster.is_on_board() or caster.side != side:
			continue
		var result := SkillResolver.resolve_channel(self, caster, String(entry["skill_id"]), entry["cells"])
		emit_feedback(caster, "action", "吟唱完成")
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
	var info := {"kind": "environment", "uid": -1}
	if feedback_enabled:
		presentation_started.emit(info)
	_start_round_rules()
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit({})


func _start_round_rules() -> void:
	if is_free_exploration():
		reset_exploration_actions()
		return
	round += 1
	for unit in units:
		if not unit.is_on_board():
			continue
		if unit.ice_glide_until_round < round:
			unit.ice_glide_until_round = 0
		if unit.surf_until_round < round:
			unit.surf_until_round = 0
		if unit.mirror_until_round < round:
			unit.mirror_until_round = 0
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
		if unit.move_cancelled and not unit.sheltered:
			unit.move_cancelled = false
	for unit in units:
		if unit.root_pending and unit.is_on_board():
			unit.move_cancelled = true
			unit.root_pending = false
			log_event("%s 受到定身影响，本回合无法移动。" % unit.display_name)
	phase = PHASE_PLAYER
	for unit in units:
		if unit.vine_reapply_round <= 0 or unit.vine_reapply_round > round:
			continue
		var same_vine: bool = unit.is_alive() and not unit.has_buff("flight") and unit.cell == unit.vine_reapply_cell and terrain_at(unit.cell) == TerrainDB.VINES
		unit.vine_reapply_round = 0
		unit.vine_reapply_cell = Vector2i(-1, -1)
		if same_vine and unit.imprison_ticks <= 0:
			apply_imprison(unit)
	if RelicDB.rank(relic_stacks, "root_rest") > 0:
		for unit in units:
			if unit.side == "player" and unit.is_alive() and RelicDB.on_grass_or_vines(self, unit):
				var restored := mini(unit.max_hp - unit.hp, 2 * RelicDB.rank(relic_stacks, "root_rest"))
				if restored > 0:
					unit.hp += restored
					feedback_heal(unit, restored)
					log_event("根息：%s 恢复 %d HP。" % [unit.display_name, restored])
	if boss_portal_cell == Vector2i(-1, -1) and Balance.nest_warning_due(round):
		log_event("巢穴预警：下回合将尝试产怪。")
	for current in all_nests():
		if not bool(current.get("alive", false)):
			continue
		var scheduled: Array = current.get("scheduled_waves", [])
		if boss_portal_cell == Vector2i(-1, -1) and Balance.nest_wave_due(round) and (node_kind == "" or not scheduled.has(round)):
			current["pending_waves"] = int(current.get("pending_waves", 0)) + 1
			if node_kind != "":
				scheduled.append(round)
				current["scheduled_waves"] = scheduled
		if int(current.get("pending_waves", 0)) > 0:
			_try_spawn_wave(current)
	_resolve_due_channels("player")


func _try_spawn_wave(target: Dictionary = {}) -> void:
	var current: Dictionary = nest if target.is_empty() else target
	if not bool(current.get("alive", false)) or reinforcement_pool.is_empty():
		return
	var species_id: String = reinforcement_pool[spawn_rng.randi_range(0, reinforcement_pool.size() - 1)]
	var candidates: Array = GridSpec.neighbors4(current["cell"])
	for cell in candidates:
		if not GridSpec.is_inside(cell):
			continue
		if is_interaction_cell(cell) or is_nest_cell(cell) or terrain_blocks_move(cell):
			continue
		if unit_at(cell) != null:
			continue
		if terrain_blocks_move(cell) or not TerrainDB.can_stand(terrain_at(cell), SpeciesDB.element_of(species_id)):
			continue
		var enemy := CombatUnit.make(species_id, "enemy", next_enemy_uid)
		next_enemy_uid += 1
		_configure_enemy(enemy, enemy.uid)
		enemy.cell = cell
		enemy.fresh_spawn = true
		enemy.spawned_from_nest = true
		enemy.spawn_round = round
		enemy.reg_index = units.size()
		units.append(enemy)
		enemy_origins[enemy.uid] = cell
		set_enemy_level_bonus(enemy_level_bonus)
		_watch_feedback(enemy)
		current["pending_waves"] = maxi(0, int(current.get("pending_waves", 0)) - 1)
		apply_vine_on_landing(enemy)
		log_event("巢穴生成 1 只野生宝可梦（%s）；出生轮在巢穴相邻格待机，下一回合才能行动。" % enemy.display_name)
		return
	log_event("巢穴上下左右没有合法空格，本次产怪积压。")


func _cell_order(cell: Vector2i) -> int:
	return cell.y * GridSpec.W + cell.x


func begin_enemy_phase() -> Array:
	var info := {"kind": "environment", "uid": -1}
	if feedback_enabled:
		presentation_started.emit(info)
	var result := _begin_enemy_phase_rules()
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit({})
	return result


func _begin_enemy_phase_rules() -> Array:
	if ended or is_free_exploration() or phase != PHASE_PLAYER:
		return []
	commit_actions()
	_begin_reward_guard()
	_finish_status_effects("player")
	if ended:
		return []
	_finish_movement_effects("player")
	_apply_shallow_wet("enemy", 1)
	_refresh_reward_guard()
	_finish_reward_guard("enemy")
	phase = PHASE_ENEMY
	for unit in units:
		unit.guard_nest = Vector2i(-1, -1)
		unit.guard_charge = false
	_resolve_due_channels("enemy")
	_refresh_reward_guard()
	if ended or is_free_exploration():
		_pending_actions = []
		_pending_index = 0
		return []
	_pending_actions = EnemyAI.plan(self)
	_pending_index = 0
	log_event("敌方开始行动（%d 个动作）。" % _pending_actions.size())
	return _pending_actions


func enemy_phase_finished() -> bool:
	return ended or is_free_exploration() or _pending_index >= _pending_actions.size()


func step_enemy_phase() -> Dictionary:
	var action: Dictionary = _pending_actions[_pending_index] if not enemy_phase_finished() else {}
	var info := {"kind": "move", "uid": int(action.get("uid", -1)), "path": action.get("move_path", [])}
	if feedback_enabled:
		presentation_started.emit(info)
	var result := _step_enemy_phase_rules()
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit(result if result is Dictionary else {})
	return result


func _step_enemy_phase_rules() -> Dictionary:
	if ended or phase != PHASE_ENEMY or enemy_phase_finished():
		return {}
	var action: Dictionary = _pending_actions[_pending_index]
	_pending_index += 1
	var unit := unit_by_uid(int(action.get("uid", -1)))
	if unit == null or not unit.is_on_board():
		return action
	if bool(action.get("capture_flee", false)):
		preload("res://scripts/rules/capture_encounter.gd").act(self, unit, action)
		return action
	var path: Array = action.get("move_path", [])
	for cell in path:
		unit.last_move_direction = cell - unit.cell
		unit.cell = cell
	if not path.is_empty():
		unit.moved = unit.moved if bool(action.get("free_terrain_move", false)) else true
		apply_vine_on_landing(unit)
		log_event("%s 移动 %d 格。" % [unit.display_name, path.size()])
	if action.has("guard"):
		begin_nest_guard(unit, action["guard"])
	var skill: Dictionary = action.get("skill", {})
	if not skill.is_empty() and unit.can_act_skill() and not ended:
		var skill_used_before := unit.skill_used
		var result := SkillResolver.apply(self, unit, String(skill["id"]), skill["target"], false)
		if bool(result.get("ok", false)):
			_record_skill_use(unit.side, String(skill["id"]))
			if skill_used_before and unit.extra_casts > 0:
				unit.extra_casts -= 1
			else:
				unit.skill_used = true
	unit.fresh_spawn = false
	_refresh_reward_guard()
	check_battle_end()
	return action


func end_enemy_phase() -> void:
	var info := {"kind": "environment", "uid": -1}
	if feedback_enabled:
		presentation_started.emit(info)
	_end_enemy_phase_rules()
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit({})


func _end_enemy_phase_rules() -> void:
	if ended:
		return
	_finish_status_effects("enemy")
	if ended:
		return
	_finish_movement_effects("enemy")
	_apply_shallow_wet("player", 2)
	_finish_reward_guard()
	_begin_reward_guard("enemy")
	_finish_round()


func _finish_round() -> void:
	if exploration_v2 and exploration_role == "capture" and round >= capture_deadline:
		for enemy in alive_units("enemy"):
			enemy.hp = 0
		log_event("野生宝可梦逃走了，本次捕捉结束。")
		end_battle("explored")
		return
	if is_free_exploration():
		reset_exploration_actions()
		return
	phase = PHASE_SETTLE
	settle_round()
	for unit in units:
		unit.fresh_spawn = false
	if ended:
		phase = PHASE_ENDED
	else:
		start_round()


func settle_round() -> void:
	var info := {"kind": "environment", "uid": -1}
	if feedback_enabled:
		presentation_started.emit(info)
	_settle_round_rules()
	if feedback_enabled:
		check_speech_events()
		presentation_finished.emit({})


func _finish_status_effects(_side: String) -> void:
	# Status durations and periodic damage settle once at the end of a whole round.
	pass


func _settle_round_rules() -> void:
	if is_free_exploration():
		_pickups()
		return
	var ice_sources: Array = []
	for cell in GridSpec.all_cells():
		if terrain_at(cell) == TerrainDB.ICE:
			ice_sources.append(cell)
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
			obstacle_reward_origins.erase(cell)
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
			damage_unit(null, unit, Balance.burn_damage_for(unit.max_hp), {"no_element": true, "cause": "灼烧", "killer_side": unit.burn_source_side})
	if ended:
		return
	for unit in alive_units():
		if ended:
			return
		if unit.parasite_source_uid < 0:
			continue
		var source := unit_by_uid(unit.parasite_source_uid)
		var source_uid: int = unit.parasite_source_uid
		var source_side: String = unit.parasite_source_side
		var parasite_bonus := int(source.upgrades.get("leech_seed_tick_bonus", 0)) if source != null and source.side == source_side else 0
		var result := damage_unit(null, unit, Balance.PARASITE_DAMAGE + parasite_bonus, {"no_element": true, "parasite_tick": true, "cause": "寄生", "killer_side": source_side, "killer_uid": source_uid})
		if int(result.get("amount", 0)) > 0 and source != null and source.is_alive() and source.side == source_side:
			var healed := mini(source.max_hp - source.hp, Balance.PARASITE_HEAL + parasite_bonus)
			if healed > 0:
				source.hp += healed
				feedback_heal(source, healed)
				log_event("%s 从寄生中恢复 %d HP。" % [source.display_name, healed])
	_settle_burning_cells()
	if ended:
		return
	_settle_temp_vines()
	if ended:
		return
	_settle_ice_growth(ice_sources)
	for cell in steam_cells.keys().duplicate():
		steam_cells[cell] = int(steam_cells[cell]) - 1
		if int(steam_cells[cell]) <= 0:
			steam_cells.erase(cell)
	# 4. 减速衰减
	for unit in units:
		if unit.sheltered:
			continue
		if unit.slow_ticks > 0:
			unit.slow_ticks = maxi(0, unit.slow_ticks - 1)
		if unit.mountain_form_ticks > 0:
			unit.mountain_form_ticks = maxi(0, unit.mountain_form_ticks - 1)
		if unit.shield_ticks > 0:
			unit.shield_ticks -= 1
			if unit.shield_ticks <= 0:
				clear_guard_rock_shield(unit, true)
		if unit.shock_ticks > 0:
			unit.shock_ticks -= 1
		if unit.frozen and unit.frozen_ticks > 0:
			unit.frozen_ticks -= 1
			if unit.frozen_ticks <= 0:
				unit.frozen = false
	# 5. 停留拾取食物
	_pickups()
	# 6. 胜负、黑化与持续天雷压力
	if check_battle_end():
		return
	if is_free_exploration():
		return
	_trigger_timed_corruption()
	_settle_storm()
	if ended or is_free_exploration():
		return
	log_event("环境结算完成。")


func _trigger_timed_corruption() -> void:
	if (exploration_v2 and exploration_role != "hunt") or ended or is_free_exploration() or round < Balance.CORRUPTION_ROUND or timed_corruption_triggered:
		return
	timed_corruption_triggered = true
	corruption_active = true
	for unit in units:
		if unit.side == "enemy" and unit.is_alive():
			unit.set_corrupted(true)
			emit_feedback(unit, "buff", "黑化 · 生命与威力+10%")
	log_event("第8轮已结束：敌军黑化，最大生命与技能威力+10%，击杀无经验。全面占领按区域移动次数触发。")


func _settle_storm() -> void:
	if ended or is_free_exploration() or round < Balance.STORM_START_ROUND or storm_last_round >= round:
		return
	storm_last_round = round
	var due: Array = []
	var later: Array = []
	for strike in storm_strikes:
		if int(strike["due_round"]) <= round:
			due.append(strike["cell"])
		else:
			later.append(strike)
	storm_strikes = later
	for cell in due:
		if ended:
			return
		_relay_feedback("action", "天雷落下", 0, cell, -1)
		var target := unit_at(cell)
		if target == null:
			continue
		var amount := ceili(target.max_hp * 0.5)
		damage_unit(null, target, amount, {"no_element": true, "cause": "天雷轰击"})
	if check_battle_end() or is_free_exploration():
		storm_strikes.clear()
		return
	var marked := {}
	for unit in alive_units("player"):
		if not marked.has(unit.cell):
			marked[unit.cell] = true
			storm_strikes.append({"cell": unit.cell, "due_round": round + 1})
	if not marked.is_empty():
		log_event("天雷预告：锁定 %d 格，第 %d 轮双方行动结束后造成落点单位最大生命 50%% 伤害（向上取整，敌我均可命中）。" % [marked.size(), round + 1])


func ice_slide_outcome(unit: CombatUnit) -> Dictionary:
	if unit == null or not unit.is_on_board() or unit.last_move_direction == Vector2i.ZERO or unit.has_buff("flight"):
		return {}
	if not GridSpec.is_inside(unit.cell) or terrain_at(unit.cell) != TerrainDB.ICE:
		return {}
	var next: Vector2i = unit.cell + unit.last_move_direction
	var blocked := not GridSpec.is_inside(next)
	if not blocked:
		blocked = unit_at(next) != null or is_interaction_cell(next) or is_nest_cell(next) or terrain_blocks_move(next)
	var lethal := false
	if not blocked:
		lethal = TerrainDB.is_lethal(terrain_at(next)) and (terrain_at(next) != TerrainDB.DEEP or unit.element != "water")
	return {"from": unit.cell, "to": next, "direction": unit.last_move_direction, "blocked": blocked, "lethal": lethal}


func _settle_ice_slides() -> void:
	for unit in units:
		var slide := ice_slide_outcome(unit)
		unit.last_move_direction = Vector2i.ZERO
		if slide.is_empty() or bool(slide["blocked"]):
			continue
		var next: Vector2i = slide["to"]
		unit.cell = next
		if unit.guard_nest.x >= 0 and GridSpec.manhattan(unit.cell, unit.guard_nest) != 1:
			unit.guard_charge = false
		_refresh_reward_guard()
		log_event("%s 从冰面滑行到 (%d,%d)。" % [unit.display_name, next.x, next.y])
		if bool(slide["lethal"]):
			kill_unit(unit, "冰面滑入致死地形")
		else:
			if terrain_at(next) == TerrainDB.WATER and not unit.has_buff("flight"):
				unit.burn_ticks = 0
				# 浅水阶段检查已发生；滑行入水仍须影响下一次移动。
				_apply_shallow_wet_to_unit(unit, 2)
			apply_vine_on_landing(unit)


func _settle_burning_cells() -> void:
	var current := burning_cells.keys()
	for cell in GridSpec.all_cells():
		if terrain_at(cell) == TerrainDB.BLUE_FIRE and not current.has(cell):
			current.append(cell)
	var newly_lit: Array = []
	var spread_sources := {}
	for cell in current:
		for near in GridSpec.neighbors4(cell):
			if not burning_cells.has(near) and TerrainDB.is_flammable(terrain_at(near)):
				newly_lit.append(near)
				spread_sources[near] = burning_sources.get(cell, "")
		if terrain_at(cell) == TerrainDB.BLUE_FIRE:
			continue
		var occupant := unit_at(cell)
		if occupant == null and is_nest_cell(cell):
			damage_nest(1, String(burning_sources.get(cell, "")), cell)
		burning_cells[cell] = int(burning_cells[cell]) - 1
		if int(burning_cells[cell]) <= 0:
			if not electric_flowers.has(cell):
				claim_obstacle_essence(cell, String(burning_sources.get(cell, "")))
			burning_sources.erase(cell)
			burning_cells.erase(cell)
			var was_vines := terrain_at(cell) == TerrainDB.VINES
			var forced := bool(burning_forced.get(cell, false))
			var origin := int(burning_origin.get(cell, TerrainDB.PLAIN))
			var restored := origin if forced and not TerrainDB.is_flammable(origin) else (int(vine_origin.get(cell, TerrainDB.PLAIN)) if was_vines else TerrainDB.PLAIN)
			burning_origin.erase(cell)
			burning_forced.erase(cell)
			if restored not in [TerrainDB.OBSTACLE, TerrainDB.TREE] and not electric_flowers.has(cell):
				obstacle_durability.erase(cell)
			if was_vines:
				log_event("藤蔓烧尽，(%d,%d) 恢复为%s。" % [cell.x, cell.y, TerrainDB.name_of(restored)])
			set_terrain(cell, restored)
			if ended:
				return
	for cell in newly_lit:
		if not burning_cells.has(cell):
			ignite(cell, String(spread_sources.get(cell, "")))
	for unit in alive_units():
		apply_burning_ground(unit)


func _settle_temp_vines() -> void:
	var cells: Array = vine_expire_round.keys().duplicate()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in cells:
		if int(vine_expire_round[cell]) > round:
			continue
		var origin := int(vine_origin.get(cell, TerrainDB.PLAIN))
		log_event("藤蔓到期，(%d,%d) 恢复为%s。" % [cell.x, cell.y, TerrainDB.name_of(origin)])
		set_terrain(cell, origin)
		if ended:
			return


func _settle_ice_growth(sources: Array) -> void:
	for source in sources:
		if terrain_at(source) != TerrainDB.ICE:
			continue
		var candidates: Array = []
		for near in GridSpec.neighbors4(source):
			if TerrainDB.is_water_body(terrain_at(near)):
				candidates.append(near)
		if candidates.is_empty():
			continue
		var target: Vector2i = candidates[terrain_rng.randi_range(0, candidates.size() - 1)]
		set_terrain(target, TerrainDB.ICE)
		log_event("冰面从 (%d,%d) 扩张，冻结 (%d,%d) 的水域。" % [source.x, source.y, target.x, target.y])


func try_pickup_fruit(unit: CombatUnit) -> Dictionary:
	# 保留旧调用入口用于读取历史撤回记录；恢复果实已删除。
	return {}


func _pickups() -> void:
	if exploration_v2 and is_free_exploration():
		for point in all_rewards():
			if point.get("state") not in ["map", "guarding"]: continue
			var holder := _player_unit_at(point["cell"])
			if holder != null:
				point["state"] = "carried"
				point["owner_uid"] = holder.uid
				emit_feedback(holder, "buff", "拾取宝藏")
	for cell in food_cells.duplicate():
		var picker := _player_unit_at(cell)
		if picker != null:
			food_cells.erase(cell)
			food_wait.erase(cell)
			food_collected += 1
			emit_feedback(picker, "buff", "食物 +1")
			log_event("%s 收集了 1 份食物。" % picker.display_name)
		else:
			food_wait.erase(cell)
	for fruit_cell in fruits.duplicate():
		var picker := _player_unit_at(fruit_cell)
		if picker != null:
			try_pickup_fruit(picker)


func _player_unit_at(cell: Vector2i) -> CombatUnit:
	for unit in units:
		if unit.side == "player" and unit.is_alive() and unit.cell == cell:
			return unit
	return null


func reward_safe_portal_cell(preferred: Vector2i) -> Vector2i:
	if not all_rewards().any(func(point): return point.get("cell") == preferred and point.get("state") in ["map", "guarding"]):
		return preferred
	var cells := GridSpec.all_cells()
	cells.sort_custom(func(a, b):
		var da := GridSpec.manhattan(a, preferred)
		var db := GridSpec.manhattan(b, preferred)
		return da < db if da != db else a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in cells:
		if is_nest_cell(cell) or is_interaction_cell(cell) or terrain_blocks_move(cell) or not TerrainDB.can_stand(terrain_at(cell), "rock"):
			continue
		if all_rewards().any(func(point): return point.get("cell") == cell and point.get("state") in ["map", "guarding"]):
			continue
		var occupant := unit_at(cell)
		if occupant != null and occupant.side == "player":
			continue
		return cell
	return preferred


func check_battle_end() -> bool:
	try_release_boss()
	if not ended and is_free_exploration():
		if not exploration_started:
			exploration_started = true
			reset_exploration_actions()
			_pickups()
			log_event("进入自由探索：回合停止计数，可无限移动与施法；恢复技能禁用。")
		return false
	if ended:
		return true
	if exploration_v2 and exploration_role in ["boss", "hunt"]:
		if battle_objective_met():
			end_battle("victory")
			return true
		return false
	if boss_uid >= 0:
		var boss := unit_by_uid(boss_uid)
		if boss != null and (not boss.is_alive() or boss.side == "player"):
			if node_kind != "boss":
				end_battle("victory")
				return true
			if boss_portal_cell == Vector2i(-1, -1):
				boss_portal_cell = reward_safe_portal_cell(boss.cell)
				units = units.filter(func(unit: CombatUnit) -> bool: return unit.side != "enemy" or not unit.is_alive())
				stop_nests()
				pending_casts = pending_casts.filter(func(cast: Dictionary) -> bool: return String(cast.get("side", "")) != "enemy")
				log_event("首领已被击败，剩余敌人撤离。训练师相邻后可点击传送门或使用互动行为前往下一层。")
			return false
	if node_kind in ["battle", "event"]:
		return false
	if alive_enemy_count() == 0:
		var any_resolved := not enemy_kills.is_empty() or not captured.is_empty()
		if any_resolved:
			end_battle("victory")
			return true
	return ended


func battle_objective_met() -> bool:
	return alive_enemy_count() == 0 and not has_live_nests()


func is_boss_encounter() -> bool:
	return node_kind == "boss" or boss_uid >= 0 or (exploration_v2 and exploration_role in ["boss", "hunt"])


func uses_extraction() -> bool:
	return not is_boss_encounter() and node_kind in ["", "battle"] and not (exploration_v2 and exploration_role in ["capture", "group"])


func can_leave_node() -> bool:
	if ended or phase != PHASE_PLAYER or is_boss_encounter(): return false
	return not uses_extraction() or battle_objective_met()


static func extraction_area(map: Dictionary) -> Array:
	return (map.get("deploy_area", Balance.DEPLOY_AREA) as Array).duplicate()


func can_escape() -> bool:
	var actor := trainer()
	return not ended and phase == PHASE_PLAYER and uses_extraction() and actor != null and actor.is_alive() and extraction_cells.has(actor.cell)


func escape_stragglers() -> Array:
	var actor := trainer()
	if actor == null:
		return []
	return alive_units("player").filter(func(u): return not u.is_trainer and u.summon_owner_uid < 0 and not extraction_cells.has(u.cell))


func escape_hp_after(unit: CombatUnit) -> int:
	return maxi(0, unit.hp - ceili(unit.max_hp / 4.0))


func escape_losses() -> Array:
	var ids := escape_stragglers().filter(func(u): return escape_hp_after(u) == 0).map(func(u): return u.uid)
	return all_rewards().filter(func(p): return p.get("state") == "carried" and ids.has(int(p.get("owner_uid", -1))) and not bool(p.get("credited", false)))


func leave_node(emergency: bool = false) -> bool:
	if exploration_v2 and exploration_role in ["capture", "treasure"] and can_leave_node():
		end_battle("explored")
		return true
	if can_leave_node():
		end_battle("victory" if node_kind == "battle" and battle_objective_met() else "explored")
	elif can_escape():
		var missing := escape_stragglers()
		if not missing.is_empty() and not emergency:
			return false
		for unit in missing:
			var before: int = unit.hp
			var after := escape_hp_after(unit)
			if after == 0:
				for point in all_rewards():
					if point.get("state") == "carried" and int(point.get("owner_uid", -1)) == unit.uid and not bool(point.get("credited", false)):
						point["state"] = "map"
						point["cell"] = unit.cell
						point["owner_uid"] = -1
						point["guard_uid"] = -1
						log_event("%s 撤离濒死，携带奖励留在 (%d,%d)。" % [unit.display_name, unit.cell.x, unit.cell.y])
				kill_unit(unit, "撤离：区外队员损失25%最大生命")
			else:
				unit.hp = after
			escape_penalties.append({"uid": unit.uid, "name": unit.display_name, "from": before, "to": unit.hp})
			emit_feedback(unit, "damage", "撤离 -%d" % (before - unit.hp), before - unit.hp)
		end_battle("escape")
	else:
		return false
	return ended


func add_garrison(count: int, species_pool: Array, preferred_cells: Array = []) -> int:
	var added := 0
	var cells := preferred_cells.duplicate()
	for cell in GridSpec.all_cells():
		if cell.x >= 4 and not cells.has(cell):
			cells.append(cell)
	for cell in cells:
		if added >= count:
			break
		if not GridSpec.is_inside(cell) or unit_at(cell) != null or is_interaction_cell(cell) or is_nest_cell(cell) or species_pool.is_empty():
			continue
		var species_id := String(species_pool[next_enemy_uid % species_pool.size()])
		if terrain_blocks_move(cell) or not TerrainDB.can_stand(terrain_at(cell), SpeciesDB.element_of(species_id)):
			continue
		var enemy := CombatUnit.make(species_id, "enemy", next_enemy_uid)
		next_enemy_uid += 1
		_configure_enemy(enemy, enemy.uid)
		enemy.cell = cell
		enemy.reg_index = units.size()
		units.append(enemy)
		enemy_origins[enemy.uid] = cell
		_watch_feedback(enemy)
		added += 1
	set_enemy_level_bonus(enemy_level_bonus)
	return added


func set_enemy_level_bonus(bonus: int) -> void:
	enemy_level_bonus = maxi(0, bonus)
	for unit in units:
		if unit.side != "enemy" or not unit.is_alive():
			continue
		var base_level := 1 + BattleDB.floor_of(battle_index) * 2 + (1 if unit.is_boss else 0)
		var target_level := base_level + maxi(0, bonus)
		if unit.enemy_level == target_level:
			continue
		var was_corrupted: bool = unit.corrupted
		unit.set_corrupted(false)
		var old_max: int = unit.max_hp
		unit.enemy_level = target_level
		unit.combat_level = target_level
		unit.skills = BattleDB.enemy_skills_for_level(unit.species_id, target_level)
		unit.max_hp = MonsterProgression.max_hp(unit.species_id, target_level) + (Balance.BOSS_HP_BONUS if unit.is_boss else 0) + (Balance.INSPIRATION_HP_BONUS if unit.inspired else 0)
		unit.hp = clampi(unit.hp + unit.max_hp - old_max, 1, unit.max_hp)
		var upgrades := {}
		for upgrade_id in BattleDB.enemy_upgrade_ids_at_level(run_seed, battle_index, unit.uid, unit.species_id, target_level):
			var info := RunState.upgrade_info(String(upgrade_id))
			if not info.is_empty():
				upgrades[String(info["key"])] = int(info["value"])
		unit.upgrades = upgrades
		unit.set_corrupted(was_corrupted)
	if corruption_active:
		for unit in units:
			if unit.side == "enemy" and unit.is_alive():
				unit.set_corrupted(true)


func end_battle(reason: String) -> void:
	if reason == "escape" and (node_kind == "boss" or boss_uid >= 0):
		return
	if ended:
		return
	ended = true
	storm_strikes.clear()
	pending_casts.clear()
	end_reason = reason
	phase = PHASE_ENDED
	var text: String = {
		"victory": "清场或摧毁巢穴，区域目标完成！",
		"forced_retreat": "训练家倒下，本局失败。",
		"boss_timeout": "旧版首领超时失败记录。",
		"escape": "主动撤离当前战斗。",
	}.get(reason, reason)
	log_event("战斗结束：" + text)


func battle_exp() -> int:
	if end_reason in ["forced_retreat", "boss_timeout"]:
		return 0
	var xp := 0
	for entry in enemy_kills:
		if bool(entry.get("by_player", false)):
			xp += Balance.xp_for_event(entry)
	for entry in captured:
		xp += Balance.xp_for_event(entry)
	return xp


func forecast() -> Array:
	var signature := _signature()
	if signature != _forecast_signature:
		var preview := clone()
		_forecast_cache = preview.begin_enemy_phase() if phase == PHASE_PLAYER else []
		_forecast_signature = signature
	return _forecast_cache


func _signature() -> String:
	var parts: PackedStringArray = ["%d|%s|%s|%s" % [round, phase, ended, end_reason]]
	parts.append("mode:%s|level:%d|corruption:%s:%s" % [node_kind, enemy_level_bonus, corruption_active, timed_corruption_triggered])
	var terrain_text := ""
	for value in terrain:
		terrain_text += str(int(value))
	parts.append(terrain_text)
	var fog_keys: Array = steam_cells.keys().duplicate()
	fog_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in fog_keys:
		parts.append("fog:%d,%d:%d" % [cell.x, cell.y, int(steam_cells[cell])])
	var vine_keys: Array = vine_expire_round.keys().duplicate()
	vine_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in vine_keys:
		parts.append("vine:%d,%d:%d:%d" % [cell.x, cell.y, int(vine_origin.get(cell, TerrainDB.PLAIN)), int(vine_expire_round[cell])])
	var fire_keys: Array = burning_cells.keys().duplicate()
	fire_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in fire_keys:
		parts.append("burning:%d,%d:%d:%d:%d" % [cell.x, cell.y, int(burning_cells[cell]), int(burning_origin.get(cell, TerrainDB.PLAIN)), int(bool(burning_forced.get(cell, false)))])
	parts.append("nests:%s" % str(all_nests()))
	parts.append("exits:%s" % str(extraction_cells))
	parts.append("terrain_rng:%d" % terrain_rng.state)
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
		parts.append("control:%d:%d:%d:%s" % [unit.uid, unit.shock_ticks, unit.paralyzed_ticks, str(unit.frozen)])
		parts.append("guard:%d:%s:%s:%s:%d" % [unit.uid, str(unit.guard_nest), str(unit.guard_charge), str(unit.spawned_from_nest), unit.spawn_round])
		parts.append("carrier:%d:%s" % [unit.uid, str(unit.reward_carrier)])
		parts.append("corrupted:%d:%s:%d" % [unit.uid, unit.corrupted, unit.corruption_hp_bonus])
		parts.append("sheltered:%d:%s" % [unit.uid, str(unit.sheltered)])
		parts.append("parasite_layers:%d:%d" % [unit.uid, unit.parasite_ticks])
		parts.append("new_status:%d:%d:%s:%d:%d:%d:%d:%d" % [unit.uid, unit.parasite_source_uid, unit.parasite_source_side, unit.ice_glide_until_round, unit.surf_until_round, unit.fire_amp_stacks, unit.electric_resonance_bonus, unit.summon_owner_uid])
		parts.append("mountain_form:%d:%d" % [unit.uid, unit.mountain_form_ticks])
		parts.append("shield:%d:%d:%d:%d" % [unit.uid, unit.shield_hp, unit.shield_ticks, unit.shield_source_uid])
		parts.append("last_skill:%d:%s:%s:%s" % [unit.uid, unit.last_skill_id, str(unit.last_skill_from), str(unit.last_skill_target)])
		parts.append("imprison:%d:%d" % [unit.uid, unit.imprison_ticks])
		parts.append("vine_reapply:%d:%d:%d,%d" % [unit.uid, unit.vine_reapply_round, unit.vine_reapply_cell.x, unit.vine_reapply_cell.y])
		parts.append("frozen:%d:%d:%d" % [unit.uid, int(unit.frozen), unit.frozen_ticks])
		parts.append("mirror:%d:%d" % [unit.uid, unit.mirror_until_round])
		parts.append("summon_power:%d:%d" % [unit.uid, unit.summon_power_bonus])
		parts.append("vine_source:%d:%s:%d" % [unit.uid, str(unit.vine_sources), unit.vine_ticks])
	parts.append("xp:%s:%s:%s" % [str(experience_events), str(experience_gains), str(units.map(func(u): return [u.uid, u.combat_xp, u.combat_level]))])
	parts.append("treasure:%s:%s" % [str(all_rewards()), str(chests)])
	parts.append("storm:%d:%s" % [storm_last_round, str(storm_strikes)])
	parts.append("boss_phase:%s" % str(boss_retreat_used))
	parts.append("pending:%s" % str(pending_casts))
	parts.append("relics:%s" % str(relic_stacks))
	parts.append("camp:%s:%s" % [is_camp_map, str(camp_facilities)])
	parts.append("channel_claims:%s:%s" % [str(channel_claims.get("player", {})), str(channel_claims.get("enemy", {}))])
	var obstacle_keys: Array = obstacle_durability.keys().duplicate()
	obstacle_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
	for cell in obstacle_keys:
		parts.append("rock:%s:%d:%s:%s:%s" % [str(cell), int(obstacle_durability[cell]), str(obstacle_origin.get(cell, TerrainDB.PLAIN)), str(obstacle_expire_round.get(cell, -1)), str(obstacle_reward_origins.get(cell, cell))])
	return "|".join(parts)


func clone() -> BattleState:
	var copy := BattleState.new()
	copy.experience_level_cap = experience_level_cap
	copy.experience_recipients = experience_recipients.duplicate()
	copy.experience_events = experience_events.duplicate()
	copy.experience_gains = experience_gains.duplicate()
	copy.node_kind = node_kind
	copy.extraction_cells = extraction_cells.duplicate()
	copy.escape_penalties = escape_penalties.duplicate(true)
	copy.mentor = mentor.duplicate(true)
	copy.merchant = merchant.duplicate(true)
	copy.essence_earned = essence_earned
	copy.essence_applied = essence_applied
	copy.essence_claims = essence_claims.duplicate()
	copy.natural_essence_cells = natural_essence_cells.duplicate()
	copy.obstacle_reward_origins = obstacle_reward_origins.duplicate()
	copy.capture_aid = capture_aid
	copy.burning_sources = burning_sources.duplicate()
	copy.food_cells = food_cells.duplicate()
	copy.food_wait = food_wait.duplicate()
	copy.food_collected = food_collected
	copy.food_applied = food_applied
	copy.boss_power_percent = boss_power_percent
	copy.run_seed = run_seed
	copy.battle_index = battle_index
	copy.round = round
	copy.phase = phase
	copy.ended = ended
	copy.end_reason = end_reason
	copy.terrain = terrain.duplicate()
	copy.exploration_v2 = exploration_v2
	copy.exploration_role = exploration_role
	copy.retreat_disabled = retreat_disabled
	copy.capture_deadline = capture_deadline
	copy.capture_exits = capture_exits.duplicate()
	copy.capture_alerted = capture_alerted
	copy.capture_exit_wait = capture_exit_wait.duplicate(true)
	copy.preserve_node_terrain = preserve_node_terrain
	copy.is_camp_map = is_camp_map
	copy.camp_facilities = camp_facilities.duplicate(true)
	copy.obstacle_durability = obstacle_durability.duplicate()
	copy.obstacle_origin = obstacle_origin.duplicate()
	copy.obstacle_expire_round = obstacle_expire_round.duplicate()
	copy.electric_flowers = electric_flowers.duplicate()
	copy.burning_cells = burning_cells.duplicate()
	copy.burning_origin = burning_origin.duplicate()
	copy.burning_forced = burning_forced.duplicate()
	copy.steam_cells = steam_cells.duplicate()
	copy.vine_origin = vine_origin.duplicate()
	copy.vine_expire_round = vine_expire_round.duplicate()
	copy.nest = nest.duplicate(true)
	copy.extra_nests = extra_nests.duplicate(true)
	copy.deploy_area = deploy_area.duplicate()
	copy.speech_seen = speech_seen.duplicate(true)
	copy.enemy_origins = enemy_origins.duplicate(true)
	copy.enemy_outcomes = enemy_outcomes.duplicate()
	copy.storm_strikes = storm_strikes.duplicate(true)
	copy.storm_last_round = storm_last_round
	copy.boss_retreat_used = boss_retreat_used
	copy.boss_uid = boss_uid
	copy.boss_portal_cell = boss_portal_cell
	copy.inspiration_triggered = inspiration_triggered
	copy.reward = reward.duplicate(true)
	copy.extra_rewards = extra_rewards.duplicate(true)
	copy.chests = chests.duplicate()
	copy.fruits = fruits.duplicate()
	copy.deploy_cells = deploy_cells.duplicate()
	copy.next_enemy_uid = next_enemy_uid
	copy.events = events.duplicate()
	copy.deaths = deaths.duplicate(true)
	copy.enemy_kills = enemy_kills.duplicate(true)
	copy.captured = captured.duplicate(true)
	copy.effects = effects.duplicate()
	copy.relic_stacks = relic_stacks.duplicate()
	copy.upgrades = upgrades.duplicate()
	copy.capture_options = capture_options.duplicate()
	copy.debug_skill_damage_bonus = debug_skill_damage_bonus.duplicate()
	copy.debug_capture_percent = debug_capture_percent
	copy.reinforcement_pool = reinforcement_pool.duplicate()
	copy.undo_stack = undo_stack.duplicate(true)
	copy.pending_casts = pending_casts.duplicate(true)
	copy.exploration_started = exploration_started
	copy.enemy_level_bonus = enemy_level_bonus
	copy.corruption_active = corruption_active
	copy.timed_corruption_triggered = timed_corruption_triggered
	copy.occupation_applied = occupation_applied
	copy.channel_claims = channel_claims.duplicate(true)
	copy.skill_use_counts = skill_use_counts.duplicate(true)
	for unit in units:
		copy.units.append(unit.dup())
	copy.spawn_rng.seed = spawn_rng.seed
	copy.spawn_rng.state = spawn_rng.state
	copy.capture_rng.seed = capture_rng.seed
	copy.capture_rng.state = capture_rng.state
	copy.terrain_rng.seed = terrain_rng.seed
	copy.terrain_rng.state = terrain_rng.state
	copy._pending_actions = _pending_actions.duplicate(true)
	copy._pending_index = _pending_index
	return copy


func is_free_exploration() -> bool:
	return node_kind == "event" or (node_kind == "battle" and battle_objective_met()) or (node_kind == "boss" and GridSpec.is_inside(boss_portal_cell))


func recovery_skill_blocked(skill_id: String) -> bool:
	return is_free_exploration() and skill_id in ["herbal_heal", "first_aid", "antidote"]


func reset_exploration_actions() -> void:
	storm_strikes.clear()
	round = maxi(1, round)
	phase = PHASE_PLAYER
	pending_casts.clear()
	channel_claims.clear()
	for unit in alive_units("player"):
		unit.moved = false
		unit.skill_used = false
		unit.capture_used = false
		unit.channel_lock_round = -1
		unit.fresh_spawn = false
		unit.frozen = false
		unit.frozen_ticks = 0
		unit.paralyzed_ticks = 0
		unit.shield_hp = 0
		unit.shield_ticks = 0
		unit.shield_source_uid = -1
		unit.move_cancelled = false
		unit.root_pending = false
		unit.vine_ticks = 0
		unit.vine_sources.clear()
		unit.battle_skill_uses.clear()


func all_nests() -> Array:
	return ([nest] if not nest.is_empty() else []) + extra_nests

func has_live_nests() -> bool:
	return all_nests().any(func(current): return bool(current.get("alive", false)))

func stop_nests() -> void:
	for current in all_nests():
		current["alive"] = false
		current["pending_waves"] = 0

func food_cell_valid(cell: Vector2i) -> bool:
	return GridSpec.is_inside(cell) and not all_nests().any(func(current): return current["cell"] == cell) and not deploy_area.has(cell) and not electric_flowers.has(cell) and not is_interaction_cell(cell) and not all_rewards().any(func(point): return point.get("cell") == cell and point.get("state") in ["map", "guarding"]) and terrain_at(cell) in [TerrainDB.PLAIN, TerrainDB.GRASS, TerrainDB.SHALLOW_GRASS, TerrainDB.WATER, TerrainDB.ICE]

func seed_initial_food() -> void:
	for cell in GridSpec.all_cells():
		if food_cell_valid(cell) and terrain_at(cell) == TerrainDB.PLAIN and unit_at(cell) == null and terrain_rng.randf() < 0.05 and food_cells.size() < 2:
			food_cells.append(cell)

func repair_food() -> void:
	for cell in food_cells.duplicate():
		if food_cell_valid(cell):
			continue
		food_cells.erase(cell)
		food_wait.erase(cell)
		var candidates := GridSpec.all_cells()
		candidates.sort_custom(func(a, b):
			var da := GridSpec.manhattan(a, cell)
			var db := GridSpec.manhattan(b, cell)
			return da < db if da != db else _cell_order(a) < _cell_order(b))
		for target in candidates:
			if food_cell_valid(target) and unit_at(target) == null and not food_cells.has(target):
				food_cells.append(target)
				break
		log_event("已修复与巢穴、设施或部署区重叠的粮食。")


func say_once(key: String, uid: int, cell: Vector2i, text: String) -> void:
	if not feedback_enabled or speech_seen.has(key):
		return
	speech_seen[key] = true
	log_event(text)
	feedback.emit({"kind": "speech", "uid": uid, "cell": cell, "text": text, "value": 0, "speech_key": key})

func check_speech_events() -> void:
	if not feedback_enabled or ended:
		return
	var actor := trainer()
	if actor != null and actor.is_alive():
		if round == 1:
			say_once("trainer_start", actor.uid, actor.cell, "好好大干一场吧！")
		if round == 7 and not is_free_exploration():
			say_once("trainer_warning", actor.uid, actor.cell, "天雷要来了！注意脚下的预告！")
	if node_kind == "event" and not merchant.is_empty():
		var cell: Vector2i = merchant["cell"]
		var threatened := alive_units("enemy").any(func(unit): return GridSpec.manhattan(unit.cell, cell) <= 3)
		if threatened:
			say_once("merchant_help", -2, cell, "救命！快帮我赶走它们！")
		else:
			say_once("merchant_sell", -2, cell, "好货便宜卖，过来看看！")


func calculate_damage(source: CombatUnit, target: CombatUnit, base: int, opts: Dictionary) -> int:
	# 纯数值计算，巢穴使用无属性目标复用技能与遗物加成，不施加状态或触发击杀。
	var amount := base
	if source != null and source.side == "enemy" and source.corrupted and bool(opts.get("skill_direct", false)):
		amount = roundi(amount * Balance.CORRUPTION_MULTIPLIER)
	if source != null and bool(opts.get("skill_direct", false)):
		amount = Balance.skill_damage_for_side(amount, source.side)
	if not bool(opts.get("no_element", false)):
		var skill_element: String = opts.get("element", "")
		if source != null and bool(opts.get("skill_direct", false)):
			amount = Elements.direct_damage(amount, skill_element, target.element)
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
			amount = maxi(0, amount - Balance.DIRECT_GUARD_REDUCTION)
	if source != null and source.side == "player" and int(effects.get("grass_strike", 0)) > 0:
		## 密林：站在草丛中的我方单位造成的直接伤害 +1。
		if not bool(opts.get("no_element", false)):
			if GridSpec.is_inside(source.cell) and terrain_at(source.cell) == TerrainDB.GRASS:
				amount += int(effects["grass_strike"])
	if source != null and bool(opts.get("skill_direct", false)):
		amount += int(debug_skill_damage_bonus.get(source.side, 0))
	if source != null and bool(opts.get("skill_direct", false)):
		amount += RelicDB.damage_bonus(self, source, target, opts)
		amount -= RelicDB.incoming_reduction(self, source, target, opts)
	amount = maxi(0, amount)
	if amount > 0 and source != null and not bool(opts.get("no_element", false)) and target.has_buff("direct_guard") and not bool(opts.get("conductive", false)):
		amount = maxi(0, amount - Balance.DIRECT_GUARD_REDUCTION)
	if target_in_grass and not bool(opts.get("ignore_grass_cover", false)):
		amount = roundi(amount * 0.9)
	return amount




func award_kill_experience(event: Dictionary, include_fainted: bool = false) -> void:
	var level := int(event.get("enemy_level", event.get("level", 1)))
	var normal := MonsterProgression.enemy_xp_reward(level)
	var amount := 1 if bool(event.get("is_summon", false)) else MonsterProgression.enemy_participation_xp(level)
	var amounts := {}
	var killer_uid := int(event.get("killer_uid", -1))
	if killer_uid >= 0:
		amounts[killer_uid] = 1 if bool(event.get("is_summon", false)) else normal + (2 if bool(event.get("is_boss", false)) else 0)
	if int(event.get("xp_reward", normal)) <= 0 or bool(event.get("corrupted", false)):
		amount = 0
		amounts.clear()
	award_battle_experience("kill:%d" % int(event.get("uid", -1)), amount, include_fainted, amounts)
