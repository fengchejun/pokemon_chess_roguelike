class_name RunState
extends RefCounted

const CombatConfig = preload("res://scripts/combat_config.gd")
const MonsterCatalog = preload("res://scripts/monster_catalog.gd")
const EnvironmentCardSystem = preload("res://scripts/environment_card_system.gd")

var roster: Array[Dictionary] = []
var active_ids: Array[String] = []
var pending_captures: Array[Dictionary] = []
var battle_count: int = 0
var total_experience: int = 0
var last_reward: Dictionary = {}
var next_capture_serial: int = 1
var environment_cards: Array[String] = []
var offered_environment_cards: Array[String] = []
var pending_bonus_card: bool = false
var bonus_choice_active: bool = false
var run_seed: int = 0


func _init() -> void:
	run_seed = randi()
	roster = [
		MonsterCatalog.make_record("ally_fire", "fire"),
		MonsterCatalog.make_record("ally_water", "water"),
		MonsterCatalog.make_record("ally_rock", "rock"),
	]
	active_ids = ["ally_fire", "ally_water", "ally_rock"]


func active_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance_id in active_ids:
		for record in roster:
			if record["instance_id"] == instance_id:
				result.append(record)
				break
	return result


func make_capture_record(species_id: String) -> Dictionary:
	var record: Dictionary = MonsterCatalog.make_record("captured_%d" % next_capture_serial, species_id)
	next_capture_serial += 1
	return record


func apply_battle_result(state: BattleState) -> Dictionary:
	if state.outcome == "" or state.reward_claimed:
		return {}
	state.reward_claimed = true
	battle_count += 1
	var experience: int = state.defeated_enemy_ids.size() * CombatConfig.EXPERIENCE_PER_KILL + state.captured_records.size() * CombatConfig.EXPERIENCE_PER_CAPTURE
	if state.outcome == "defeat":
		experience = 0
	else:
		for record in roster:
			if active_ids.has(record["instance_id"]):
				record["experience"] = int(record["experience"]) + experience
		total_experience += experience
		for captured in state.captured_records:
			var record: Dictionary = make_capture_record(captured["species_id"])
			if roster.size() < CombatConfig.CARRIED_MONSTER_LIMIT:
				roster.append(record)
			else:
				pending_captures.append(record)
	last_reward = {"outcome": state.outcome, "kills": state.defeated_enemy_ids.size(), "captures": state.captured_records.size(), "escaped": state.escaped_enemy_ids.size(), "experience": experience, "bonus_card": state.bonus_card_earned()}
	if state.outcome != "defeat":
		offered_environment_cards = EnvironmentCardSystem.offer(environment_cards, run_seed + battle_count * 3571)
		pending_bonus_card = state.bonus_card_earned()
		bonus_choice_active = false
	return last_reward


func choose_environment_card(card_id: String) -> bool:
	if not offered_environment_cards.has(card_id):
		return false
	environment_cards.append(card_id)
	offered_environment_cards.clear()
	if pending_bonus_card:
		pending_bonus_card = false
		bonus_choice_active = true
		offered_environment_cards = EnvironmentCardSystem.offer(environment_cards, run_seed + battle_count * 3571 + 100003)
	else:
		bonus_choice_active = false
	return true


func replace_with_pending(pending_id: String, existing_id: String) -> bool:
	var pending_index := -1
	var roster_index := -1
	for index in pending_captures.size():
		if pending_captures[index]["instance_id"] == pending_id:
			pending_index = index
	for index in roster.size():
		if roster[index]["instance_id"] == existing_id:
			roster_index = index
	if pending_index < 0 or roster_index < 0:
		return false
	var incoming: Dictionary = pending_captures.pop_at(pending_index)
	roster[roster_index] = incoming
	var active_index: int = active_ids.find(existing_id)
	if active_index >= 0:
		active_ids[active_index] = incoming["instance_id"]
	return true


func decline_pending(pending_id: String) -> bool:
	for index in pending_captures.size():
		if pending_captures[index]["instance_id"] == pending_id:
			pending_captures.remove_at(index)
			return true
	return false


func toggle_active(instance_id: String) -> bool:
	if not has_roster_member(instance_id):
		return false
	if active_ids.has(instance_id):
		active_ids.erase(instance_id)
		return true
	if active_ids.size() >= CombatConfig.DEPLOYED_MONSTER_LIMIT:
		return false
	active_ids.append(instance_id)
	return true


func has_roster_member(instance_id: String) -> bool:
	for record in roster:
		if record["instance_id"] == instance_id:
			return true
	return false


func can_start_battle() -> bool:
	return pending_captures.is_empty() and offered_environment_cards.is_empty() and not pending_bonus_card and active_ids.size() == CombatConfig.DEPLOYED_MONSTER_LIMIT and active_records().size() == CombatConfig.DEPLOYED_MONSTER_LIMIT
