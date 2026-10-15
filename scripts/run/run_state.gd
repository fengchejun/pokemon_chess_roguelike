class_name RunState
extends RefCounted

## 一局游戏的持久状态：出战名单、仓库、经验、环境卡、强化、战损记录与统计。

const SAVE_VERSION := 3
const MAX_EQUIPPED_SKILLS := 4
const RETIRED_GENERIC_UPGRADES := ["move_plus", "max_hp_plus", "direct_guard", "collision_guard", "grass_resilience", "recovery_plus"]

const MONSTER_UPGRADES := {
	"push_distance": {
		"name": "推击距离 +1",
		"desc": "推击额外推开 1 格，中途碰撞照常结算。",
		"key": "push_distance",
		"value": 2,
		"requires_skill": "rock_push",
	},
	"rock_create_width": {
		"name": "造岩扩建",
		"desc": "造岩横排由 3 格扩为 4 格。",
		"key": "rock_create_width",
		"value": 4,
		"requires_skill": "rock_create",
	},
	"rain_radius": {
		"name": "造雨扩张",
		"desc": "造雨术范围由 3×3 扩为 5×5。",
		"key": "rain_radius_bonus",
		"value": 1,
		"requires_skill": "rain_call",
	},
	"fireball_damage": {"name": "炽烈火球", "desc": "我方火球术中心直接伤害 +1。", "key": "fireball_damage", "value": 1, "requires_skill": "fire_burst"},
	"flame_jet_length": {"name": "长焰", "desc": "我方喷射火焰直线长度由 3 格增至 4 格。", "key": "flame_jet_length", "value": 1, "requires_skill": "flame_jet"},
	"water_flow_push": {"name": "急流", "desc": "我方水流击退距离由 1 格增至 2 格。", "key": "water_flow_push", "value": 1, "requires_skill": "water_flow"},
	"drain_range": {"name": "蔓延吸取", "desc": "我方吸取射程由 2 格增至 3 格。", "key": "drain_range", "value": 1, "requires_skill": "drain"},
	"herbal_heal_amount": {"name": "丰茂药草", "desc": "我方药草治疗每个目标回复 2 点生命。", "key": "herbal_heal_amount", "value": 1, "requires_skill": "herbal_heal"},
	"ice_shard_damage": {"name": "尖锐冰锥", "desc": "我方冰锥基础伤害 +1。", "key": "ice_shard_damage", "value": 1, "requires_skill": "ice_shard"},
	"ice_ground_reach": {"name": "冰面延展", "desc": "我方冰封大地向前延展至第 4 排。", "key": "ice_ground_reach", "value": 1, "requires_skill": "frozen_ground"},
	"wind_gust_distance": {"name": "强劲推风", "desc": "我方推风击退距离由 1 格增至 2 格。", "key": "wind_gust_distance", "value": 1, "requires_skill": "wind_gust"},
	"electric_arc_damage": {"name": "高压传导", "desc": "我方放电传导基础伤害 +1。", "key": "electric_arc_damage", "value": 1, "requires_skill": "electric_arc"},
	"volt_replace_flex": {"name": "灵活换位", "desc": "伏特替换可与相距 1 或 2 格的单位交换位置。", "key": "volt_replace_flex", "value": 1, "requires_skill": "volt_replace"},
	"tailwind_reach": {"name": "远风", "desc": "加速的前方影响距离由 2 排扩为 3 排。", "key": "tailwind_reach", "value": 1, "requires_skill": "tailwind"},
	"flame_charge_damage": {"name": "冲锋余焰", "desc": "闪焰冲锋经过单位时额外造成 1 点直接伤害。", "key": "flame_charge_damage", "value": 1, "requires_skill": "flame_charge"},
	"wild_vines_reach": {"name": "藤蔓延展", "desc": "疯狂藤蔓向前延长至第 3 格。", "key": "wild_vines_reach", "value": 1, "requires_skill": "wild_vines"},
	"lightning_first_shock": {"name": "首击蓄电", "desc": "闪电的第一个落点额外施加一层感电。", "key": "lightning_first_shock", "value": 1, "requires_skill": "lightning"},
	"rock_break_range": {"name": "长距碎岩", "desc": "碎岩射程由 2 格增至 3 格。", "key": "rock_break_range", "value": 1, "requires_skill": "rock_break"},
	"freeze_ray_range": {"name": "远距急冻", "desc": "急冻光线射程由 4 格增至 5 格。", "key": "freeze_ray_range", "value": 1, "requires_skill": "freeze_ray"},
	"double_cast_range": {"name": "远距加速", "desc": "加速2施放距离由 1 格增至 2 格。", "key": "double_cast_range", "value": 1, "requires_skill": "double_cast"},
}


static func upgrade_info(upgrade_id: String) -> Dictionary:
	if upgrade_id.ends_with("_range"):
		var skill_id := upgrade_id.trim_suffix("_range")
		if SkillDB.is_placeholder(skill_id):
			return {"name": "%s射程强化" % SkillDB.name_of(skill_id), "desc": "此试招射程由 2 格增至 3 格。", "key": upgrade_id, "value": 1, "requires_skill": skill_id}
	return MONSTER_UPGRADES.get(upgrade_id, {})


static func upgrade_id_for_skill(skill_id: String) -> String:
	if SkillDB.is_placeholder(skill_id):
		return skill_id + "_range"
	for upgrade_id in MONSTER_UPGRADES:
		if String(MONSTER_UPGRADES[upgrade_id].get("requires_skill", "")) == skill_id:
			return String(upgrade_id)
	return ""

var seed: int = 0
var battle_index: int = 0
var in_battle: bool = false
var trainer_hp: int = 6
var carried: Array = []
var storage: Array = []
var pending_captures: Array = []
var next_uid: int = 1
var exp: int = 0
var cards: Array = [] # 旧存档字段；新规则不再免费选取站位卡。
var environment_deck: Array = [] # 旧存档字段；读取时按已确认规则清空。
var environment_reward_pending: bool = false # 旧结算字段。
var reward_inventory: Array = []
var selected_reward_item: String = ""
var pending_reward_choices: int = 0
var reward_choice_index: int = 0
var settlement_pending: bool = false
var last_settlement: Dictionary = {}
var pending_bonus_choices: int = 0
var upgrades: Dictionary = {}
var upgrades_taken: Array = []
var xp_upgrades_claimed: int = 0
var deaths: Array = []
var stats := {"kills": 0, "captures": 0, "victories": 0, "escapes": 0, "retreats": 0}
var captured_applied: int = 0
var deployed_uids: Array = []
var pending_supply: bool = false
var options := {"threat_preview": false, "capture_low_hp": false, "capture_field_join": false}


static func new_run(seed_value: int = 0, starting_collection: Array = []) -> RunState:
	var run := RunState.new()
	run.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system() * 1000000.0)
	run.trainer_hp = int(SpeciesDB.get_species("trainer").get("hp", 6))
	if starting_collection.is_empty():
		## 兼容旧代码与旧存档；实际新局由收藏界面传入三只。
		for species_id in SpeciesDB.STARTER_TEAM:
			run.carried.append(run._make_record(String(species_id)))
	else:
		for source in starting_collection:
			var record := run._make_record(String(source["species_id"]))
			record["collection_id"] = int(source["id"])
			record["affinity"] = maxi(0, int(source.get("affinity", 0)))
			run.carried.append(record)
	return run


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
		"level": 1,
		"xp": 0,
		"affinity": 0,
		"known_skills": SpeciesDB.skills_of(species_id).duplicate(),
		"equipped_skills": SpeciesDB.skills_of(species_id).duplicate(),
		"upgrades": {},
		"upgrades_taken": [],
		"claimed_even_levels": [],
		"level_choices": {},
	}
	next_uid += 1
	return record


func record_by_uid(uid: int) -> Dictionary:
	for record in carried:
		if int(record["uid"]) == uid:
			return record
	return {}


func owned_record_by_uid(uid: int) -> Dictionary:
	var record := record_by_uid(uid)
	if not record.is_empty():
		return record
	for stored in storage:
		if int(stored["uid"]) == uid:
			return stored
	return {}


func monster_max_hp(record: Dictionary) -> int:
	return MonsterProgression.max_hp_for_record(record)


func battle_seed() -> int:
	return hash("battle:%d:%d" % [seed, battle_index])


func region_name() -> String:
	return String(BattleDB.config_for(battle_index).get("region", "?"))


func effects() -> Dictionary:
	if selected_reward_item.begins_with("position:"):
		return CardDB.active_effects([selected_reward_item.trim_prefix("position:")])
	return {}


func map_deck() -> Array:
	if selected_reward_item.begins_with("map:"):
		return [selected_reward_item.trim_prefix("map:")]
	return []


func mod_points() -> int:
	return Balance.MOD_POINTS if selected_reward_item == RewardDB.MOD_ITEM else 0


func select_reward_item(reward_id: String) -> bool:
	if reward_id != "" and (not RewardDB.is_consumable(reward_id) or not reward_inventory.has(reward_id)):
		return false
	selected_reward_item = reward_id
	return true


func consume_selected_reward_item() -> String:
	var used := selected_reward_item
	if used == "":
		return ""
	if not reward_inventory.has(used):
		selected_reward_item = ""
		return ""
	reward_inventory.erase(used)
	selected_reward_item = ""
	return used


func reward_choices() -> Array:
	return RewardDB.offer(seed, battle_index, reward_choice_index)


func choose_reward(reward_id: String) -> bool:
	if pending_reward_choices <= 0 or not reward_choices().has(reward_id):
		return false
	if not RewardDB.is_consumable(reward_id):
		return false
	reward_inventory.append(reward_id)
	pending_reward_choices -= 1
	reward_choice_index += 1
	return true


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
		unit.upgrades = (record.get("upgrades", {}) as Dictionary).duplicate()
		unit.skills = (record.get("equipped_skills", SpeciesDB.skills_of(String(record["species_id"]))) as Array).duplicate()
		unit.max_hp = monster_max_hp(record)
		unit.hp = mini(int(record["hp"]), unit.max_hp)
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
	if battle.reward.has("run_settled_outcome"):
		return (battle.reward["run_settled_outcome"] as Dictionary).duplicate(true)
	var outcome := {
		"reason": battle.end_reason,
		"exp": 0,
		"monster_exp": [],
		"monster_affinity": [],
		"kills": battle.enemy_kills.size(),
		"captures": battle.captured.size(),
		"captured_names": [],
		"deaths": battle.deaths.duplicate(true),
		"flee_penalty": [],
		"recovery": [],
		"base_rest": [],
		"trainer_from": trainer_hp,
	}
	for entry in battle.captured:
		(outcome["captured_names"] as Array).append(SpeciesDB.name_of(String(entry.get("species_id", ""))))
	var failure := battle.end_reason == "forced_retreat"
	var bonus_earned := battle.reward_bonus_earned() and not bool(battle.reward.get("credited", false))
	if not failure:
		var gains: Dictionary = {}
		var original: Dictionary = {}
		for uid in deployed_uids:
			var id := int(uid)
			if not record_by_uid(id).is_empty():
				original[id] = true
				gains[id] = 0
		for entry in battle.enemy_kills:
			var killer_side := String(entry.get("killer_side", "player" if bool(entry.get("by_player", false)) else ""))
			if killer_side == "enemy":
				continue
			var killer_uid := int(entry.get("killer_uid", -1))
			if original.has(killer_uid):
				gains[killer_uid] = int(gains[killer_uid]) + Balance.EXP_PER_KILL
			else:
				for id in original:
					gains[id] = int(gains[id]) + 1
		var shared_bonus := battle.captured.size() * Balance.EXP_PER_CAPTURE
		if bonus_earned:
			shared_bonus += 1
		if bool(battle.nest.get("destroyed_by_player", false)):
			shared_bonus += 3
		for id in original:
			var unit := battle.unit_by_uid(int(id))
			if unit != null and unit.is_alive():
				gains[id] = int(gains[id]) + shared_bonus
		for id in original:
			var record := record_by_uid(int(id))
			var growth := MonsterProgression.award_xp(record, int(gains[id]))
			growth["uid"] = int(id)
			growth["name"] = SpeciesDB.name_of(String(record["species_id"]))
			(outcome["monster_exp"] as Array).append(growth)
			outcome["exp"] = int(outcome["exp"]) + int(growth["gained"])
			var affinity_growth := MonsterProgression.award_affinity(record, 1)
			affinity_growth["uid"] = int(id)
			(outcome["monster_affinity"] as Array).append(affinity_growth)
	var kills := 0
	for entry in battle.enemy_kills:
		if bool(entry.get("by_player", false)):
			kills += 1
	stats["kills"] = int(stats["kills"]) + kills
	if bonus_earned:
		pending_bonus_choices += 1
		battle.reward["credited"] = true
	outcome["bonus_choice_earned"] = bonus_earned
	if not failure:
		pending_reward_choices += 1
	pending_reward_choices += pending_bonus_choices
	pending_bonus_choices = 0
	outcome["pending_reward_choices"] = pending_reward_choices
	match battle.end_reason:
		"victory":
			stats["victories"] = int(stats["victories"]) + 1
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
			var max_hp := monster_max_hp(record)
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
		var max_hp := monster_max_hp(record)
		var before := int(record["hp"])
		if before < max_hp:
			rested.append({"name": SpeciesDB.name_of(String(record["species_id"])), "from": before, "to": max_hp})
		record["hp"] = max_hp
	outcome["base_rest"] = rested
	var storage_healed := 0
	for record in storage:
		var max_hp := monster_max_hp(record)
		if int(record["hp"]) < max_hp:
			storage_healed += 1
		record["hp"] = max_hp
	outcome["storage_rest"] = storage_healed
	var trainer_max := int(SpeciesDB.get_species("trainer").get("hp", 7))
	outcome["trainer_from"] = trainer_hp
	trainer_hp = trainer_max
	outcome["trainer_to"] = trainer_max
	in_battle = false
	environment_reward_pending = false
	settlement_pending = true
	last_settlement = outcome.duplicate(true)
	battle.reward["run_settled_outcome"] = outcome.duplicate(true)
	return outcome


func advance_battle() -> void:
	settlement_pending = false
	last_settlement = {}
	battle_index += 1


func run_finished() -> bool:
	return battle_index >= Balance.BATTLES_PER_RUN


func run_lost() -> bool:
	## 全员濒死（无可出战成员）即本局结束；濒死成员需留守基地休养一场才能恢复。
	for record in carried:
		if int(record["hp"]) > 0:
			return false
	return true


func available_monster_upgrades(uid: int) -> Array:
	var record := owned_record_by_uid(uid)
	if record.is_empty():
		return []
	var learned: Array = record.get("known_skills", SpeciesDB.skills_of(String(record["species_id"])))
	var taken: Array = record.get("upgrades_taken", [])
	var pool: Array = []
	for skill_id in learned:
		var upgrade_id := upgrade_id_for_skill(String(skill_id))
		if upgrade_id != "" and not taken.has(upgrade_id):
			pool.append(upgrade_id)
	pool.sort()
	return pool


func available_new_skills(uid: int) -> Array:
	var record := owned_record_by_uid(uid)
	if record.is_empty():
		return []
	var known: Array = record.get("known_skills", SpeciesDB.skills_of(String(record["species_id"])))
	var pool: Array = []
	for skill_id in SkillDB.placeholder_ids_for(SpeciesDB.element_of(String(record["species_id"]))):
		if not known.has(skill_id):
			pool.append(skill_id)
	return pool


func _expected_level(record: Dictionary) -> int:
	for level in [2, 4, 6, 8, 10]:
		if int(record.get("level", 1)) < level:
			break
		if not (record.get("claimed_even_levels", []) as Array).has(level):
			return level
	return -1


func _claim_level(record: Dictionary, level: int) -> void:
	var claimed: Array = record.get("claimed_even_levels", [])
	claimed.append(level)
	record["claimed_even_levels"] = claimed
	record["level_choices"] = {}


func pending_monster_levels() -> Array:
	var pending: Array = []
	var records: Array = carried.duplicate() + storage.duplicate()
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	for record in records:
		for level in [2, 4, 6, 8, 10]:
			if int(record.get("level", 1)) < level:
				break
			if (record.get("claimed_even_levels", []) as Array).has(level):
				continue
			pending.append({"uid": int(record["uid"]), "level": level})
	return pending


func monster_level_choices(uid: int, level: int) -> Array:
	var record := owned_record_by_uid(uid)
	return available_monster_upgrades(uid) if not record.is_empty() and _expected_level(record) == level else []


func take_monster_level_choice(uid: int, level: int, upgrade_id: String) -> bool:
	var record := owned_record_by_uid(uid)
	var info := upgrade_info(upgrade_id)
	if record.is_empty() or info.is_empty():
		return false
	if level != _expected_level(record) or not available_monster_upgrades(uid).has(upgrade_id):
		return false
	var values: Dictionary = record.get("upgrades", {})
	values[String(info["key"])] = int(info["value"])
	record["upgrades"] = values
	var taken: Array = record.get("upgrades_taken", [])
	taken.append(upgrade_id)
	record["upgrades_taken"] = taken
	_claim_level(record, level)
	return true


func enhance_monster_skill(uid: int, level: int, skill_id: String) -> bool:
	return take_monster_level_choice(uid, level, upgrade_id_for_skill(skill_id))


func learn_monster_skill(uid: int, level: int, skill_id: String, replace_skill_id: String = "") -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty() or level != _expected_level(record) or not available_new_skills(uid).has(skill_id):
		return false
	var known: Array = record.get("known_skills", [])
	var equipped: Array = record.get("equipped_skills", [])
	if equipped.size() >= MAX_EQUIPPED_SKILLS:
		if replace_skill_id == "" or not equipped.has(replace_skill_id):
			return false
		equipped[equipped.find(replace_skill_id)] = skill_id
	else:
		if replace_skill_id != "":
			return false
		equipped.append(skill_id)
	known.append(skill_id)
	record["known_skills"] = known
	record["equipped_skills"] = equipped
	_claim_level(record, level)
	return true


func equip_monster_skill(uid: int, slot: int, skill_id: String) -> bool:
	var record := owned_record_by_uid(uid)
	if record.is_empty():
		return false
	var known: Array = record.get("known_skills", [])
	var equipped: Array = record.get("equipped_skills", [])
	if slot < 0 or slot > equipped.size() or slot >= MAX_EQUIPPED_SKILLS:
		return false
	if skill_id == "":
		if slot >= equipped.size() or equipped.size() <= 1:
			return false
		equipped.remove_at(slot)
	elif not known.has(skill_id) or (equipped.has(skill_id) and (slot == equipped.size() or equipped[slot] != skill_id)):
		return false
	elif slot == equipped.size():
		equipped.append(skill_id)
	else:
		equipped[slot] = skill_id
	record["equipped_skills"] = equipped
	return true


func pending_upgrades() -> bool:
	return not pending_monster_levels().is_empty()


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
		"cards": cards.duplicate(),
		"environment_deck": environment_deck.duplicate(),
		"environment_reward_pending": environment_reward_pending,
		"reward_inventory": reward_inventory.duplicate(),
		"selected_reward_item": selected_reward_item,
		"pending_reward_choices": pending_reward_choices,
		"reward_choice_index": reward_choice_index,
		"settlement_pending": settlement_pending,
		"last_settlement": last_settlement.duplicate(true),
		"pending_bonus_choices": pending_bonus_choices,
		"deaths": deaths.duplicate(true),
		"stats": stats.duplicate(),
		"captured_applied": captured_applied,
		"deployed_uids": deployed_uids.duplicate(),
		"pending_supply": pending_supply,
		"options": options.duplicate(),
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	var version := int(data.get("version", 1))
	var legacy_growth := version < 2
	var legacy_upgrade_style := version < 3
	run.seed = int(data.get("seed", 0))
	run.battle_index = int(data.get("battle_index", 0))
	run.in_battle = bool(data.get("in_battle", false))
	run.trainer_hp = clampi(int(data.get("trainer_hp", 6)), 1, SpeciesDB.hp_of("trainer"))
	run.carried = (data.get("carried", []) as Array).duplicate(true)
	run.storage = (data.get("storage", []) as Array).duplicate(true)
	run.pending_captures = (data.get("pending_captures", []) as Array).duplicate(true)
	run.next_uid = int(data.get("next_uid", 1))
	## v1 的全队经验与强化无对应的新规则，迁移时清除。
	run.exp = 0
	run.upgrades = {}
	run.upgrades_taken = []
	run.xp_upgrades_claimed = 0
	run.deaths = (data.get("deaths", []) as Array).duplicate(true)
	run.stats = (data.get("stats", {}) as Dictionary).duplicate()
	run.captured_applied = int(data.get("captured_applied", 0))
	run.deployed_uids = (data.get("deployed_uids", []) as Array).duplicate()
	run.pending_supply = bool(data.get("pending_supply", false))
	run.options.merge((data.get("options", {}) as Dictionary), true)
	run.cards = []
	run.environment_deck = []
	run.environment_reward_pending = false
	run.options.erase("card_mode")
	for reward_id in data.get("reward_inventory", []):
		var id := String(reward_id)
		if RewardDB.is_consumable(id):
			run.reward_inventory.append(id)
	run.selected_reward_item = String(data.get("selected_reward_item", ""))
	if not run.reward_inventory.has(run.selected_reward_item):
		run.selected_reward_item = ""
	run.pending_reward_choices = maxi(0, int(data.get("pending_reward_choices", 0)))
	run.reward_choice_index = maxi(0, int(data.get("reward_choice_index", 0)))
	run.settlement_pending = bool(data.get("settlement_pending", false))
	run.last_settlement = (data.get("last_settlement", {}) as Dictionary).duplicate(true)
	run.pending_bonus_choices = maxi(0, int(data.get("pending_bonus_choices", 0)))
	## 修复历史存档：补齐缺失的 uid（否则名单/仓库相关界面会取键失败）。
	for group in [run.carried, run.storage, run.pending_captures]:
		for record in (group as Array):
			run._ensure_uid(record)
			if legacy_growth:
				record["level"] = 1
				record["xp"] = 0
				record["affinity"] = 0
			MonsterProgression.normalize_record(record)
			run._normalize_record_growth(record, legacy_upgrade_style)
			record["hp"] = mini(maxi(0, int(record.get("hp", 0))), run.monster_max_hp(record))
	if legacy_growth and run.settlement_pending:
		## 旧结算页中已累计的经验/等级文案不能在迁移后继续展示。
		run.last_settlement["exp"] = 0
		run.last_settlement["monster_exp"] = []
		run.last_settlement["growth_migrated"] = true
	elif legacy_upgrade_style and run.settlement_pending:
		run.last_settlement["upgrade_migrated"] = true
	return run


func _normalize_record_growth(record: Dictionary, legacy_upgrade_style: bool) -> void:
	var species_id := String(record.get("species_id", ""))
	var base_skills: Array = SpeciesDB.skills_of(species_id).duplicate()
	var known: Array = base_skills.duplicate()
	if not legacy_upgrade_style:
		for skill_id in record.get("known_skills", []):
			var id := String(skill_id)
			if not known.has(id) and not SkillDB.get_def(id).is_empty() and SkillDB.element_of(id) == SpeciesDB.element_of(species_id):
				known.append(id)
	var equipped: Array = []
	if not legacy_upgrade_style:
		for skill_id in record.get("equipped_skills", []):
			var id := String(skill_id)
			if known.has(id) and not equipped.has(id) and equipped.size() < MAX_EQUIPPED_SKILLS:
				equipped.append(id)
	if equipped.is_empty():
		equipped = base_skills.duplicate()
	record["known_skills"] = known
	record["equipped_skills"] = equipped
	var old_taken: Array = record.get("upgrades_taken", [])
	var old_claimed: Array = record.get("claimed_even_levels", [])
	var kept_taken: Array = []
	var kept_claimed: Array = []
	if legacy_upgrade_style:
		# v2 的每次升级必为强化，两个数组逐项对应；清除通用项时退还对应等级。
		for index in range(mini(old_taken.size(), old_claimed.size())):
			var upgrade_id := String(old_taken[index])
			var info := upgrade_info(upgrade_id)
			var level := int(old_claimed[index])
			if info.is_empty() or not known.has(String(info.get("requires_skill", ""))) or kept_taken.has(upgrade_id) or not [2, 4, 6, 8, 10].has(level):
				continue
			kept_taken.append(upgrade_id)
			kept_claimed.append(level)
	else:
		# v3 的学招也会领取等级，强化记录与已领取等级不再逐项对应。
		for upgrade_id in old_taken:
			var id := String(upgrade_id)
			var info := upgrade_info(id)
			if not info.is_empty() and known.has(String(info.get("requires_skill", ""))) and not kept_taken.has(id):
				kept_taken.append(id)
		for level_value in old_claimed:
			var level := int(level_value)
			if [2, 4, 6, 8, 10].has(level) and level <= int(record.get("level", 1)) and not kept_claimed.has(level):
				kept_claimed.append(level)
	var values := {}
	for upgrade_id in kept_taken:
		var info := upgrade_info(String(upgrade_id))
		values[String(info["key"])] = int(info["value"])
	record["upgrades"] = values
	record["upgrades_taken"] = kept_taken
	record["claimed_even_levels"] = kept_claimed
	record["level_choices"] = {}
