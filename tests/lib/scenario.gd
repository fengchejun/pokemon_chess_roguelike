class_name TestScenario
extends RefCounted


static func plain_terrain() -> Array:
	var terrain: Array = []
	for index in GridSpec.W * GridSpec.H:
		terrain.append(TerrainDB.PLAIN)
	return terrain


static func with_cells(terrain: Array, entries: Array) -> Array:
	var copy := terrain.duplicate()
	for entry in entries:
		copy[GridSpec.index(entry[0])] = entry[1]
	return copy


static func obstacles_from(terrain: Array) -> Array:
	var cells: Array = []
	for cell in GridSpec.all_cells():
		if int(terrain[GridSpec.index(cell)]) == TerrainDB.OBSTACLE:
			cells.append(cell)
	return cells


static func make_map(terrain: Array, nest_cell: Vector2i = Vector2i(7, 7), reward_cell: Vector2i = Vector2i(6, 4), fruits: Array = []) -> Dictionary:
	return {
		"terrain": terrain,
		"obstacle_cells": obstacles_from(terrain),
		"nest_cell": nest_cell,
		"nest_exits": [nest_cell + Vector2i(-1, 0)],
		"reward_cell": reward_cell,
		"fruit_cells": fruits,
		"deploy_cells": Balance.DEPLOY_CELLS.duplicate(),
	}


static func make_state(player_species: Array, enemies: Array, terrain: Array = [], effects: Dictionary = {}, upgrades: Dictionary = {}, pool: Array = [], seed_value: int = 42) -> BattleState:
	var run := RunState.new()
	run.trainer_hp = SpeciesDB.hp_of("trainer")
	var deploy_units: Array = []
	var uid := 1
	for species_id in player_species:
		var unit := CombatUnit.make(String(species_id), "player", uid)
		uid += 1
		unit.hp = unit.max_hp
		deploy_units.append(unit)
	var trainer := CombatUnit.make("trainer", "player", Balance.TRAINER_UID)
	trainer.hp = run.trainer_hp
	deploy_units.insert(0, trainer)
	var cfg := {"region": "测试", "enemies": enemies}
	var state := BattleState.new()
	var actual_terrain: Array = terrain if not terrain.is_empty() else plain_terrain()
	state.setup(make_map(actual_terrain), cfg, seed_value, 0, deploy_units, effects, upgrades, pool)
	return state


static func enemy_list(pairs: Array) -> Array:
	return pairs
