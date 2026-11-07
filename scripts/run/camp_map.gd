extends RefCounted

static func ensure(run: RunState) -> BattleState:
	var region = run.get_region()
	var state: BattleState = region.load_battle("camp")
	if state == null:
		var map := MapGenerator.generate(run.seed, region.floor_index * 6, 300, [], run.current_theme(), 1)
		map["chests"] = {}
		map["reward"] = {"state": "absent", "cell": Vector2i(-1, -1)}
		map["treasure_generated"] = true
		state = BattleState.new()
		state.node_kind = "event"
		state.setup(map, {"enemies": [], "boss_index": -1}, run.seed, region.floor_index * 6, [], run.effects(), {}, [], run.options, run.relic_stacks)
		state.stop_nests()
	if not state.is_camp_map:
		state.is_camp_map = true
		state.camp_facilities = {
			"fire": {"cell": Vector2i(3, 3), "name": "篝火", "max_hp": 2, "destroyed": false},
			"storage": {"cell": Vector2i(6, 3), "name": "仓库", "max_hp": 5, "destroyed": false},
		}
		for facility in state.camp_facilities.values():
			var cell: Vector2i = facility["cell"]
			state.electric_flowers.erase(cell)
			state.terrain[GridSpec.index(cell)] = TerrainDB.OBSTACLE
			state.obstacle_durability[cell] = facility["max_hp"]
			state.obstacle_origin.erase(cell)
			state.obstacle_expire_round.erase(cell)
			state.natural_essence_cells.erase(cell)
		if state.nest.get("cell", Vector2i(-1, -1)) in [Vector2i(3, 3), Vector2i(6, 3)]:
			state.nest["cell"] = Vector2i(6, 6)
		save(run, state)
	return state

static func save(run: RunState, state: BattleState) -> void:
	var region = run.get_region()
	region.nodes["camp"]["snapshot"] = BattleSnapshot.save_state(state)
	region.nodes["camp"]["facilities"] = BattleSnapshot.encode(state.camp_facilities)
	var positions := {}
	for unit in state.units:
		if unit.side == "player":
			positions[str(unit.uid)] = [unit.cell.x, unit.cell.y]
	region.nodes["camp"]["map_positions"] = positions
	run.region_data = region.to_dict()

static func open(run: RunState) -> BattleState:
	var state := ensure(run)
	var positions := {}
	for unit in state.units:
		if unit.side == "player":
			positions[unit.uid] = unit.cell
	state.units = []
	var players := run.build_deploy_units(run.carried.map(func(record): return int(record["uid"])))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("camp_party:%d:%d" % [run.seed, run.floor_index()])
	var cells := GridSpec.all_cells()
	var occupied := {}
	# 先恢复原站位，再为新增成员寻找可站立的随机空格。
	for unit in players:
		if positions.has(unit.uid) and not occupied.has(positions[unit.uid]) and not state.is_nest_cell(positions[unit.uid]) and not state.terrain_blocks_move(positions[unit.uid]) and TerrainDB.can_stand(state.terrain_at(positions[unit.uid]), unit.element):
			unit.cell = positions[unit.uid]
			state.units.append(unit)
			occupied[unit.cell] = true
	for unit in players:
		if state.units.has(unit):
			continue
		var choices: Array = cells.filter(func(cell): return not occupied.has(cell) and not state.is_nest_cell(cell) and not state.terrain_blocks_move(cell) and TerrainDB.can_stand(state.terrain_at(cell), unit.element))
		if choices.is_empty():
			# 极端布置堵满地图时，只清出新成员脚下的一格，保留设施。
			choices = cells.filter(func(cell): return not occupied.has(cell) and state.camp_facility_at(cell) == "" and not state.electric_flowers.has(cell) and not state.is_nest_cell(cell))
			state.set_terrain(choices[0], TerrainDB.PLAIN)
			choices = [choices[0]]
		unit.cell = choices[rng.randi_range(0, choices.size() - 1)]
		state.units.append(unit)
		occupied[unit.cell] = true
	state.node_kind = "event"
	state.ended = false
	state.end_reason = ""
	state.phase = BattleState.PHASE_PLAYER
	state.stop_nests()
	state.relic_stacks = run.relic_stacks.duplicate()
	for unit in state.units:
		state._watch_feedback(unit)
	state.reset_exploration_actions()
	state.experience_recipients = players.map(func(unit): return unit.uid)
	save(run, state)
	return state
