class_name RunState
extends RefCounted

## 一局游戏的持久状态：出战名单、仓库、经验、环境卡、强化、战损记录与统计。

const SAVE_VERSION := 1

const UPGRADES := {
	"push_distance": {
		"name": "推击距离 +1",
		"desc": "推击额外推开 1 格，中途碰撞照常结算。",
		"key": "push_distance",
		"value": 2,
	},
	"rock_create_width": {
		"name": "造岩扩建",
		"desc": "造岩横排由 3 格扩为 4 格。",
		"key": "rock_create_width",
		"value": 4,
	},
	"rain_radius": {
		"name": "造雨扩张",
		"desc": "造雨术范围由 3×3 扩为 5×5。",
		"key": "rain_radius_bonus",
		"value": 1,
	},
	"volt_step": {
		"name": "电光步距离 +1",
		"desc": "电光步瞬移最多 3 格。",
		"key": "volt_step_bonus",
		"value": 1,
	},
}

var seed: int = 0
var battle_index: int = 0
var in_battle: bool = false
var trainer_hp: int = 6
var carried: Array = []
var storage: Array = []
var pending_captures: Array = []
var next_uid: int = 1
var exp: int = 0
var cards: Array = []
var environment_deck: Array = []
var environment_reward_pending: bool = false
var upgrades: Dictionary = {}
var upgrades_taken: Array = []
var deaths: Array = []
var stats := {"kills": 0, "captures": 0, "victories": 0, "escapes": 0, "retreats": 0}
var captured_applied: int = 0
var deployed_uids: Array = []
var pending_supply: bool = false
var options := {"threat_preview": false, "capture_low_hp": false, "capture_field_join": false, "card_mode": "position"}


static func new_run(seed_value: int = 0) -> RunState:
	var run := RunState.new()
	run.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	run.trainer_hp = int(SpeciesDB.get_species("trainer").get("hp", 6))
	for species_id in SpeciesDB.STARTER_TEAM:
		run.carried.append(run._make_record(species_id))
	run.cards = default_card_selection()
	return run


static func default_card_selection() -> Array:
	## 默认取卡表前两张；实际选择在地图预览界面完成。
	return CardDB.ALL_IDS.slice(0, Balance.CARDS_PER_BATTLE)


func supply_due() -> bool:
	## 每完成 SUPPLY_INTERVAL 场战斗进入补给点。
	if battle_index <= 0 or battle_index >= Balance.BATTLES_PER_RUN:
		return false
	return battle_index % Balance.SUPPLY_INTERVAL == 0


func apply_supply_recovery() -> Dictionary:
	## 补给点：训练家恢复 50% 生命上限（四舍五入，至少 1 点）。
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	var before := trainer_hp
	var amount := maxi(1, roundi(float(trainer_max) * Balance.SUPPLY_TRAINER_RECOVERY_RATIO))
	trainer_hp = mini(trainer_max, trainer_hp + amount)
	return {"trainer_from": before, "trainer_to": trainer_hp}


func _make_record(species_id: String, hp: int = -1) -> Dictionary:
	var record := {
		"uid": next_uid,
		"species_id": species_id,
		"hp": hp if hp > 0 else SpeciesDB.hp_of(species_id),
	}
	next_uid += 1
	return record


func record_by_uid(uid: int) -> Dictionary:
	for record in carried:
		if int(record["uid"]) == uid:
			return record
	return {}


func battle_seed() -> int:
	return hash("battle:%d:%d" % [seed, battle_index])


func region_name() -> String:
	return String(BattleDB.config_for(battle_index).get("region", "?"))


func effects() -> Dictionary:
	if String(options.get("card_mode", "position")) == "environment":
		return {}
	return CardDB.active_effects(cards)


func map_deck() -> Array:
	return environment_deck.duplicate() if String(options.get("card_mode", "position")) == "environment" else []


func environment_choices() -> Array:
	return MapCardDB.offer(environment_deck, hash("environment_reward:%d:%d" % [seed, battle_index]))


func choose_environment_card(card_id: String) -> bool:
	if not environment_reward_pending or not environment_choices().has(card_id):
		return false
	environment_deck.append(card_id)
	environment_reward_pending = false
	return true


func mod_points() -> int:
	return Balance.MOD_POINTS + int(effects().get("mod_points", 0))


static func recovery_amount(max_hp: int) -> int:
	## 战后恢复：生命上限的 30%（四舍五入，至少 1 点）。
	return maxi(1, roundi(float(max_hp) * Balance.BATTLE_RECOVERY_RATIO))


func build_deploy_units(deploy_uids: Array) -> Array:
	var units: Array = []
	var trainer := CombatUnit.make("trainer", "player", Balance.TRAINER_UID)
	trainer.hp = trainer_hp
	units.append(trainer)
	for uid in deploy_uids:
		var record := record_by_uid(int(uid))
		if record.is_empty():
			continue
		var unit := CombatUnit.make(String(record["species_id"]), "player", int(record["uid"]))
		unit.hp = int(record["hp"])
		units.append(unit)
	return units


func mark_deployed(deploy_uids: Array) -> void:
	deployed_uids = deploy_uids.duplicate()
	in_battle = true


func sync_from_battle(battle: BattleState) -> void:
	## 战斗中的倒下、捕获与生命变化即时写回（濒死当帧写入）。
	var known_death_uids := {}
	for entry in deaths:
		known_death_uids[int(entry.get("uid", -1))] = true
	for unit in battle.units:
		if unit.side != "player":
			continue
		if unit.is_trainer:
			trainer_hp = unit.hp
			continue
		var record := record_by_uid(unit.uid)
		if record.is_empty():
			continue
		if unit.is_alive():
			record["hp"] = unit.hp
		else:
			record["hp"] = 0
			if not known_death_uids.has(unit.uid):
				known_death_uids[unit.uid] = true
				for entry in battle.deaths:
					if int(entry.get("uid", -1)) == unit.uid:
						deaths.append(entry.duplicate())
						break
	while captured_applied < battle.captured.size():
		var cap: Dictionary = battle.captured[captured_applied]
		if bool(cap.get("on_field", false)) and not battle.ended:
			break
		captured_applied += 1
		stats["captures"] = int(stats["captures"]) + 1
		if bool(cap.get("on_field", false)):
			var survivor := battle.unit_by_uid(int(cap.get("uid", -1)))
			if survivor == null or not survivor.is_alive() or survivor.side != "player":
				continue
			pending_captures.append(_make_record(String(cap["species_id"]), survivor.hp))
		else:
			pending_captures.append(_make_record(String(cap["species_id"]), int(cap["hp"])))


func _add_capture(species_id: String, hp: int) -> void:
	## 便捷注入（测试用）：优先名单、其次仓库、最后进入待处理队列。
	var record := _make_record(species_id, hp)
	if carried.size() < Balance.CARRIED_LIMIT:
		carried.append(record)
	elif storage.size() < Balance.STORAGE_LIMIT:
		storage.append(record)
	else:
		pending_captures.append(record)


func pending_capture() -> Dictionary:
	return pending_captures[0] if not pending_captures.is_empty() else {}


func capture_join_team() -> bool:
	if pending_captures.is_empty() or carried.size() >= Balance.CARRIED_LIMIT:
		return false
	var record: Dictionary = pending_captures.pop_front()
	_ensure_uid(record)
	carried.append(record)
	return true


func capture_to_storage() -> bool:
	if pending_captures.is_empty() or storage.size() >= Balance.STORAGE_LIMIT:
		return false
	var record: Dictionary = pending_captures.pop_front()
	_ensure_uid(record)
	storage.append(record)
	return true


func capture_replace(replace_uid: int) -> bool:
	## 用捕获替换名单中的一名成员：被替换者进入仓库。
	if pending_captures.is_empty() or storage.size() >= Balance.STORAGE_LIMIT:
		return false
	for index in carried.size():
		if int(carried[index]["uid"]) == replace_uid:
			storage.append(carried[index])
			carried.remove_at(index)
			var incoming: Dictionary = pending_captures.pop_front()
			_ensure_uid(incoming)
			carried.append(incoming)
			return true
	return false


func _ensure_uid(record: Dictionary) -> void:
	## 兜底：历史/异常来源的记录可能缺少 uid，补发一个保证唯一。
	if not record.has("uid"):
		record["uid"] = next_uid
		next_uid += 1


func capture_discard() -> void:
	if not pending_captures.is_empty():
		pending_captures.pop_front()


func release_storage(uid: int) -> bool:
	for index in storage.size():
		if int(storage[index]["uid"]) == uid:
			storage.remove_at(index)
			return true
	return false


func settle_battle(battle: BattleState) -> Dictionary:
	## 结算口径：胜利 / 强制撤退（失败） / 野生逃离。
	var outcome := {
		"reason": battle.end_reason,
		"exp": battle.battle_exp(),
		"carrier_exp": 0,
		"flee_penalty": [],
		"recovery": [],
		"base_rest": [],
		"trainer_from": trainer_hp,
	}
	exp += int(outcome["exp"])
	var kills := 0
	for entry in battle.enemy_kills:
		if bool(entry.get("by_player", false)):
			kills += 1
	stats["kills"] = int(stats["kills"]) + kills
	var failure := battle.end_reason == "forced_retreat"
	match battle.end_reason:
		"victory":
			stats["victories"] = int(stats["victories"]) + 1
			var carrier := battle.carrier_uid()
			var carrier_unit := battle.unit_by_uid(carrier)
			if carrier >= 0 and carrier_unit != null and carrier_unit.is_alive():
				outcome["carrier_exp"] = Balance.CARRIER_BONUS_EXP
				exp += Balance.CARRIER_BONUS_EXP
		"escape":
			stats["escapes"] = int(stats["escapes"]) + 1
		"forced_retreat":
			## 战斗失败：不结算经验、出战宝可梦生命减半（不致死）并退回基地。
			stats["retreats"] = int(stats["retreats"]) + 1
			var penalty: Array = []
			for uid in deployed_uids:
				var record := record_by_uid(int(uid))
				if record.is_empty():
					continue
				var before := int(record["hp"])
				if before <= 0:
					continue
				var after := maxi(1, ceili(float(before) * 0.5))
				if after < before:
					penalty.append({"name": SpeciesDB.name_of(String(record["species_id"])), "from": before, "to": after})
				record["hp"] = after
			outcome["flee_penalty"] = penalty
	# 战后恢复：出战过的宝可梦 +30%（仅非失败结局）；留守基地的成员回满 100%；训练家每次出征回满。
	var recovered: Array = []
	for record in carried:
		if deployed_uids.has(int(record["uid"])):
			var max_hp := SpeciesDB.hp_of(String(record["species_id"]))
			var before := int(record["hp"])
			if failure or before <= 0 or before >= max_hp:
				continue
			var after := mini(max_hp, before + recovery_amount(max_hp))
			if after > before:
				recovered.append({"name": SpeciesDB.name_of(String(record["species_id"])), "from": before, "to": after})
			record["hp"] = after
	outcome["recovery"] = recovered
	var rested: Array = []
	for record in carried:
		if deployed_uids.has(int(record["uid"])):
			continue
		var max_hp := SpeciesDB.hp_of(String(record["species_id"]))
		var before := int(record["hp"])
		if before < max_hp:
			rested.append({"name": SpeciesDB.name_of(String(record["species_id"])), "from": before, "to": max_hp})
		record["hp"] = max_hp
	outcome["base_rest"] = rested
	var storage_healed := 0
	for record in storage:
		var max_hp := SpeciesDB.hp_of(String(record["species_id"]))
		if int(record["hp"]) < max_hp:
			storage_healed += 1
		record["hp"] = max_hp
	outcome["storage_rest"] = storage_healed
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	outcome["trainer_from"] = trainer_hp
	trainer_hp = trainer_max
	outcome["trainer_to"] = trainer_max
	in_battle = false
	environment_reward_pending = String(options.get("card_mode", "position")) == "environment" and not failure
	return outcome


func advance_battle() -> void:
	battle_index += 1


func run_finished() -> bool:
	return battle_index >= Balance.BATTLES_PER_RUN


func run_lost() -> bool:
	## 全员濒死（无可出战成员）即本局结束；濒死成员需留守基地休养一场才能恢复。
	for record in carried:
		if int(record["hp"]) > 0:
			return false
	return true


func pending_upgrades() -> bool:
	var eligible := 0
	for threshold in Balance.UPGRADE_THRESHOLDS:
		if exp >= int(threshold):
			eligible += 1
	return eligible > upgrades_taken.size() and upgrades_taken.size() < UPGRADES.size()


func upgrade_choices(rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for upgrade_id in UPGRADES:
		if not upgrades_taken.has(upgrade_id):
			pool.append(upgrade_id)
	var choices: Array = []
	while choices.size() < 3 and not pool.is_empty():
		var pick := rng.randi_range(0, pool.size() - 1)
		choices.append(pool[pick])
		pool.remove_at(pick)
	return choices


func take_upgrade(upgrade_id: String) -> void:
	var info: Dictionary = UPGRADES.get(upgrade_id, {})
	if info.is_empty():
		return
	upgrades[String(info["key"])] = int(info["value"])
	upgrades_taken.append(upgrade_id)


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": seed,
		"battle_index": battle_index,
		"in_battle": in_battle,
		"trainer_hp": trainer_hp,
		"carried": carried.duplicate(true),
		"storage": storage.duplicate(true),
		"pending_captures": pending_captures.duplicate(true),
		"next_uid": next_uid,
		"exp": exp,
		"cards": cards.duplicate(),
		"environment_deck": environment_deck.duplicate(),
		"environment_reward_pending": environment_reward_pending,
		"upgrades": upgrades.duplicate(),
		"upgrades_taken": upgrades_taken.duplicate(),
		"deaths": deaths.duplicate(true),
		"stats": stats.duplicate(),
		"captured_applied": captured_applied,
		"deployed_uids": deployed_uids.duplicate(),
		"pending_supply": pending_supply,
		"options": options.duplicate(),
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.seed = int(data.get("seed", 0))
	run.battle_index = int(data.get("battle_index", 0))
	run.in_battle = bool(data.get("in_battle", false))
	run.trainer_hp = int(data.get("trainer_hp", 6))
	run.carried = (data.get("carried", []) as Array).duplicate(true)
	run.storage = (data.get("storage", []) as Array).duplicate(true)
	run.pending_captures = (data.get("pending_captures", []) as Array).duplicate(true)
	run.next_uid = int(data.get("next_uid", 1))
	run.exp = int(data.get("exp", 0))
	run.upgrades = (data.get("upgrades", {}) as Dictionary).duplicate()
	run.upgrades_taken = (data.get("upgrades_taken", []) as Array).duplicate()
	run.deaths = (data.get("deaths", []) as Array).duplicate(true)
	run.stats = (data.get("stats", {}) as Dictionary).duplicate()
	run.captured_applied = int(data.get("captured_applied", 0))
	run.deployed_uids = (data.get("deployed_uids", []) as Array).duplicate()
	run.pending_supply = bool(data.get("pending_supply", false))
	run.options.merge((data.get("options", {}) as Dictionary), true)
	run.cards = _sanitize_cards(data.get("cards", []))
	run.environment_deck = (data.get("environment_deck", []) as Array).duplicate()
	run.environment_reward_pending = bool(data.get("environment_reward_pending", false))
	if String(run.options.get("card_mode", "position")) != "environment":
		run.options["card_mode"] = "position"
	## 修复历史存档：补齐缺失的 uid（否则名单/仓库相关界面会取键失败）。
	for group in [run.carried, run.storage, run.pending_captures]:
		for record in (group as Array):
			run._ensure_uid(record)
	return run


static func _sanitize_cards(raw) -> Array:
	## 出战卡固定为 2 张：过滤非法项并补齐（兼容旧存档）。
	var picked: Array = []
	for card_id in (raw as Array if raw is Array else []):
		var id := String(card_id)
		if CardDB.CARDS.has(id) and not picked.has(id):
			picked.append(id)
		if picked.size() >= Balance.CARDS_PER_BATTLE:
			break
	for card_id in CardDB.ALL_IDS:
		if picked.size() >= Balance.CARDS_PER_BATTLE:
			break
		if not picked.has(card_id):
			picked.append(card_id)
	return picked
