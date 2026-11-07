extends RefCounted
## 捕捉遭遇专用：受惊、撤离规划与停留一轮；复用正常移动规则。
const EXITS := [Vector2i(7, 1), Vector2i(7, 6)]

static func active(state: BattleState) -> bool:
	return state.exploration_v2 and state.exploration_role == "capture"

static func alert(state: BattleState) -> void:
	if not active(state) or state.capture_alerted: return
	state.capture_alerted = true
	state.log_event("野生宝可梦全体受惊，开始向撤离点逃跑！")

static func distance(state: BattleState, unit: CombatUnit, cell: Vector2i) -> int:
	var best := 1 << 30
	for exit_cell in state.capture_exits:
		best = mini(best, PathFinder.path_distance(state, cell, exit_cell, unit.element, unit.has_buff("flight")))
	return best

static func plan(state: BattleState) -> Array:
	var work := state.clone()
	var actions: Array = []
	for unit in work.alive_units("enemy"):
		var action := {"uid": unit.uid, "move_path": [], "skill": {}, "capture_flee": true}
		if work.capture_alerted and not work.capture_exits.has(unit.cell) and work.can_move_unit_now(unit):
			var best := distance(work, unit, unit.cell)
			var best_cost := 1 << 30
			var options := PathFinder.stop_cells(work, unit)
			var cells: Array = options.keys()
			cells.sort_custom(func(a, b): return a.y * GridSpec.W + a.x < b.y * GridSpec.W + b.x)
			for cell in cells:
				var remaining := distance(work, unit, cell)
				var cost := int(options[cell]["cost"])
				if remaining < best or (remaining == best and remaining < distance(work, unit, unit.cell) and cost < best_cost):
					best = remaining; best_cost = cost
					action["move_path"] = options[cell]["path"]
					action["free_terrain_move"] = options[cell].get("terrain_travel", false)
		act(work, unit, action)
		actions.append(action)
	return actions

static func act(state: BattleState, unit: CombatUnit, action: Dictionary) -> void:
	if not state.capture_alerted: return
	var waiting: Dictionary = state.capture_exit_wait.get(unit.uid, {})
	if state.capture_exits.has(unit.cell) and waiting.get("cell", Vector2i(-1, -1)) == unit.cell and int(waiting.get("round", state.round)) < state.round:
		unit.hp = 0 # 逃离不算击倒，不发放击倒原质、经验和掉落。
		state.capture_exit_wait.erase(unit.uid)
		state.emit_feedback(unit, "action", "成功逃脱")
		state.log_event("%s 在撤离点停留至下次行动，成功逃脱。" % unit.display_name)
		if state.alive_enemy_count() == 0: state.end_battle("explored")
		return
	var path: Array = action.get("move_path", [])
	for cell in path:
		unit.last_move_direction = cell - unit.cell
		unit.cell = cell
	if not path.is_empty():
		unit.moved = not bool(action.get("free_terrain_move", false))
		state.apply_vine_on_landing(unit)
		state.log_event("%s 向撤离点移动%d格。" % [unit.display_name, path.size()])
	if unit.is_on_board() and state.capture_exits.has(unit.cell):
		state.capture_exit_wait[unit.uid] = {"cell": unit.cell, "round": state.round}
		state.emit_feedback(unit, "action", "下次行动逃脱")
	else:
		state.capture_exit_wait.erase(unit.uid)
	state.check_battle_end()

static func prepare_map(map: Dictionary) -> void:
	# 用最少的地形修整保证陆地通路，中央仍保留障碍，不再清空整列。
	map["capture_exits"] = EXITS.duplicate()
	var required: Array = EXITS + [Vector2i(5, 2), Vector2i(6, 3), Vector2i(5, 4)]
	for cell in EXITS: map["terrain"][GridSpec.index(cell)] = TerrainDB.PLAIN
	for goal in required:
		var frontier: Array = [Vector2i(1, 3)]
		var costs := {Vector2i(1, 3): 0}
		var routes := {Vector2i(1, 3): []}
		while not frontier.is_empty():
			frontier.sort_custom(func(a, b): return costs[a] < costs[b])
			var current: Vector2i = frontier.pop_front()
			if current == goal: break
			for dir in GridSpec.DIRS4:
				var next: Vector2i = current + dir
				if not GridSpec.is_inside(next) or map.get("chests", {}).has(next): continue
				var terrain: int = map["terrain"][GridSpec.index(next)]
				var cost: int = costs[current] + (8 if TerrainDB.blocks_move(terrain) or TerrainDB.is_lethal(terrain) else 1)
				if cost < int(costs.get(next, 1 << 30)):
					costs[next] = cost
					routes[next] = routes[current] + [next]
					if not frontier.has(next): frontier.append(next)
		for cell in routes.get(goal, []):
			var terrain: int = map["terrain"][GridSpec.index(cell)]
			if TerrainDB.blocks_move(terrain) or TerrainDB.is_lethal(terrain): map["terrain"][GridSpec.index(cell)] = TerrainDB.PLAIN
	map["obstacle_cells"] = GridSpec.all_cells().filter(func(cell): return TerrainDB.blocks_move(map["terrain"][GridSpec.index(cell)]))
