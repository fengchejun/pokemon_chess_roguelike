class_name Merchant
extends RefCounted

const RARITIES := {"common": ["普通", 10], "rare": ["稀有", 15], "precious": ["珍稀", 25]}
const PP_TONIC_RESTORE := 5
const BATTLE_ITEMS := ["potion", "pp_tonic", "capture_aid"]
const INTEL_ID := "rare_intel"
const RARE_CANDY := "rare_candy"
const CANDY_XP := {"xp_candy_small": 6, "xp_candy_medium": 30, "xp_candy_large": 70}
const ITEM_SHOP_ADDITIONS := {RARE_CANDY: 1, "xp_candy_small": 2, "xp_candy_medium": 1, "xp_candy_large": 1, INTEL_ID: 1}
const ITEMS := {
	"pp_tonic": ["技能药剂", 7, "为三格内一个存活己方单位的每项已装备技能恢复5 PP。"],
	"potion": ["治疗药", 5, "恢复三格内一个存活己方单位15 HP，不能复活。"],
	"capture_aid": ["捕获辅助", 6, "本次探索下一次捕获概率增加20个百分点。"],
	RARE_CANDY: ["神奇糖果", 28, "提升一级，保留当前等级内的经验进度。"],
	"xp_candy_small": ["经验糖果（小）", 9, "增加6经验。"],
	"xp_candy_medium": ["经验糖果（中）", 20, "增加30经验。"],
	"xp_candy_large": ["经验糖果（大）", 36, "增加70经验。"],
	INTEL_ID: ["神秘宝可梦情报", 28, "解锁本层一次性的神秘栖息地。进入消耗1次行动。"],
}

const BOOK_PREFIX := "skill_book:"
const BOOK_PRICE := 18

static func use_intel(run: RunState) -> bool:
	if int(run.trainer_items.get(INTEL_ID, 0)) <= 0 or not run.region_mode or not run.battle_snapshot.is_empty():
		return false
	var region: RegionState = run.get_region()
	if region.flow_version != 2 or not preload("res://scripts/run/exploration_flow.gd").unlock_rare_habitat(region, run.seed):
		return false
	run.trainer_items[INTEL_ID] -= 1
	run.region_data = region.to_dict()
	return true


static func use_skill_book(run: RunState, skill_id: String, uid: int) -> bool:
	var id := BOOK_PREFIX + skill_id
	var member := run.record_by_uid(uid)
	if member.is_empty() or int(run.trainer_items.get(id, 0)) <= 0 or not run.available_new_skills(uid).has(skill_id):
		return false
	var known: Array = member.get("known_skills", []).duplicate()
	var equipped: Array = member.get("equipped_skills", []).duplicate()
	known.append(skill_id)
	if equipped.size() < RunState.MAX_EQUIPPED_SKILLS:
		equipped.append(skill_id)
	member["known_skills"] = known
	member["equipped_skills"] = equipped
	run.trainer_items[id] -= 1
	return true

static func use_potion_outside_battle(run: RunState, uid: int) -> bool:
	if int(run.trainer_items.get("potion", 0)) <= 0:
		return false
	if uid == Balance.TRAINER_UID:
		if run.trainer_hp <= 0 or run.trainer_hp >= run.trainer_max_hp():
			return false
		run.trainer_hp = mini(run.trainer_max_hp(), run.trainer_hp + 15)
	else:
		var member := run.record_by_uid(uid)
		if member.is_empty() or int(member["hp"]) <= 0 or int(member["hp"]) >= run.monster_max_hp(member):
			return false
		member["hp"] = mini(run.monster_max_hp(member), int(member["hp"]) + 15)
	run.trainer_items["potion"] -= 1
	return true

static func candy_xp(id: String, member: Dictionary) -> int:
	var level := int(member.get("level", MonsterProgression.MAX_LEVEL))
	if level >= MonsterProgression.MAX_LEVEL:
		return 0
	if id == RARE_CANDY:
		return MonsterProgression.threshold_for_level(level + 1) - MonsterProgression.threshold_for_level(level)
	return int(CANDY_XP.get(id, 0))


static func use_candy(run: RunState, id: String, uid: int) -> Dictionary:
	if not run.battle_snapshot.is_empty() or int(run.trainer_items.get(id, 0)) <= 0:
		return {}
	var member := run.record_by_uid(uid)
	var amount := candy_xp(id, member)
	if amount <= 0:
		return {}
	var growth := MonsterProgression.award_xp(member, amount)
	run.trainer_items[id] -= 1
	return growth


static func item_requires_unit_target(id: String) -> bool:
	return id in ["potion", "pp_tonic"]


static func item_target_valid(state: BattleState, target: CombatUnit, id: String = "potion") -> bool:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	if state.is_free_exploration():
		return false
	if not ITEMS.has(id) or target == null or not target.is_alive() or target.side != "player" or GridSpec.manhattan(trainer.cell, target.cell) > 3:
		return false
	if id == "potion" and target.hp >= target.max_hp:
		return false
	if id == "potion" and RelicDB.owned(state.relic_stacks, "blood_dragon_dance"):
		return false
	if id == "pp_tonic" and not target.has_pp_deficit():
		return false
	var delta := target.cell - trainer.cell
	var steps := maxi(absi(delta.x), absi(delta.y))
	for i in range(1, steps):
		var cell := Vector2i(Vector2(trainer.cell).lerp(Vector2(target.cell), float(i) / steps).round())
		if state.is_blocking_ray(cell):
			return false
	return true

static func use_item(run: RunState, state: BattleState, id: String, target_uid: int = -1) -> Dictionary:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	var free_heal := id == "potion" and state.is_free_exploration()
	if state.ended or state.phase != BattleState.PHASE_PLAYER or trainer == null or not trainer.is_alive() or (not free_heal and (not trainer.can_act_skill() or trainer.capture_used or trainer.channel_lock_round == state.round)) or id not in BATTLE_ITEMS or int(run.trainer_items.get(id, 0)) <= 0:
		return {"ok": false, "reason": "道具不足或训练师本回合无法行动。"}
	if id == "potion":
		var target := state.unit_by_uid(target_uid)
		if not item_target_valid(state, target, id):
			return {"ok": false, "reason": "请选择三格内视线可达、受伤且存活的己方单位。"}
		var healed := state.relic_heal(target, 15)
	elif id == "pp_tonic":
		var target := state.unit_by_uid(target_uid)
		if not item_target_valid(state, target, id):
			return {"ok": false, "reason": "请选择三格内视线可达、仍有 PP 缺失的己方单位。"}
		var restored := target.restore_pp(PP_TONIC_RESTORE)
		state.emit_feedback(target, "buff", "PP +%d" % restored, restored)
	else:
		if state.capture_aid:
			return {"ok": false, "reason": "捕获辅助已经生效。"}
		state.capture_aid = true
	state.commit_actions()
	if not free_heal:
		trainer.skill_used = true
		trainer.capture_used = true
	run.trainer_items[id] -= 1
	state.log_event("训练师使用了%s。" % ITEMS[id][0])
	return {"ok": true, "reason": "道具使用成功。"}

static func rarity(species: String) -> String:
	return String(SpeciesDB.get_species(species).get("rarity", "common"))

static func monster_price(record: Dictionary) -> int:
	return price_for(rarity(String(record["species_id"])), int(record.get("level", 1)))

static func price_for(rarity_id: String, level: int) -> int:
	var base := int(RARITIES.get(rarity_id, RARITIES["common"])[1])
	return base * (4 + clampi(level, 1, 10)) / 5


static func skill_upgrade_cost(run: RunState, record: Dictionary) -> int:
	return run.merchant_skill_upgrade_cost(record)


static func item_price(run: RunState, id: String) -> int:
	var base := int(ITEMS.get(id, ["", -1])[1])
	return base


static func relic_price(relic_id: String) -> int:
	return {"common": 12, "rare": 20, "legendary": 32}.get(RelicDB.rarity_of(relic_id), -1)


static func upgrade_skill(run: RunState, state: BattleState, uid: int, skill_id: String) -> Dictionary:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	if state.ended or state.phase != BattleState.PHASE_PLAYER or state.node_kind != "event" or state.merchant.is_empty() or trainer == null or not trainer.is_alive() or not state.can_interact_at(state.merchant["cell"]):
		return {"ok": false, "reason": "训练师需在收集区商人相邻格交易。"}
	var record := run.record_by_uid(uid)
	if record.is_empty():
		return {"ok": false, "reason": "只能强化当前携带的宝可梦。"}
	if run.monster_empty_engraving_slots(record) <= 0:
		return {"ok": false, "reason": "该宝可梦没有空刻印槽。"}
	if not run.available_monster_upgrades(uid).has(RunState.upgrade_id_for_skill(skill_id)):
		return {"ok": false, "reason": "该技能不可强化或已经强化。"}
	var cost := skill_upgrade_cost(run, record)
	if run.essence < cost:
		return {"ok": false, "reason": "原质不足，需要 %d。" % cost}
	if not run.apply_merchant_skill_upgrade(uid, skill_id):
		return {"ok": false, "reason": "技能强化失败。"}
	run.essence -= cost
	var battle_unit := state.unit_by_uid(uid)
	if battle_unit != null:
		battle_unit.upgrades = (record.get("upgrades", {}) as Dictionary).duplicate()
	return {
		"ok": true,
		"reason": "%s的%s强化完成，消耗 %d 原质。" % [
			SpeciesDB.name_of(String(record["species_id"])), SkillDB.name_of(skill_id), cost,
		],
	}


static func ensure_region(region: RegionState, seed_value: int, relic_stacks: Dictionary = {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("merchant:%d:%d" % [seed_value, region.floor_index])
	var id := "event_%d" % rng.randi_range(1, 2)
	if region.nodes[id].has("merchant"):
		var existing_stock: Dictionary = region.nodes[id]["merchant"].get("stock", {})
		for stock_id in existing_stock.keys():
			var key := String(stock_id)
			if key.begins_with("relic:") and not RelicDB.DEFINITIONS.has(key.trim_prefix("relic:")):
				existing_stock.erase(stock_id)
			elif key.begins_with("relic:") and not RelicDB.merchant_allowed(key.trim_prefix("relic:")):
				existing_stock.erase(stock_id)
			elif not key.begins_with("relic:") and not ITEMS.has(key):
				existing_stock.erase(stock_id)
		if not existing_stock.has("pp_tonic"):
			existing_stock["pp_tonic"] = 1
		if not existing_stock.keys().any(func(key): return String(key).begins_with("relic:")):
			var offered := RelicDB.weighted_random_id(hash("merchant-relic:%d:%d" % [seed_value, region.floor_index]), relic_stacks, {}, false)
			if offered != "":
				existing_stock["relic:%s" % offered] = 1
		return
	var stock := {"potion": 2, "pp_tonic": 1, "capture_aid": 2}
	var relic_id := RelicDB.weighted_random_id(hash("merchant-relic:%d:%d" % [seed_value, region.floor_index]), relic_stacks, {}, false)
	if relic_id != "":
		stock["relic:%s" % relic_id] = 1
	region.nodes[id]["merchant"] = {"stock": stock, "cell": [-1, -1]}

static func choose_battle_cell(state: BattleState, positions: Dictionary = {}) -> Vector2i:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	if trainer == null:
		return Vector2i(-1, -1)
	for cell in state.move_options(trainer):
		if GridSpec.manhattan(trainer.cell, cell) >= 2 and not state.deploy_area.has(cell) and not positions.values().has(cell) and not state.food_cells.has(cell) and not state.is_nest_cell(cell):
			return cell
	for cell in GridSpec.neighbors4(trainer.cell):
		if state.unit_at(cell) == null and not state.deploy_area.has(cell) and not state.is_nest_cell(cell) and not state.terrain_blocks_move(cell) and TerrainDB.can_stand(state.terrain_at(cell), ""):
			return cell
	return Vector2i(-1, -1)

static func trade(run: RunState, state: BattleState, operation: String, id: String, quantity: int = 1) -> Dictionary:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	if state.ended or state.phase != BattleState.PHASE_PLAYER or state.node_kind != "event" or state.merchant.is_empty() or trainer == null or not trainer.is_alive() or not state.can_interact_at(state.merchant["cell"]):
		return {"ok": false, "reason": "训练师需在收集区商人相邻格交易。"}
	if quantity <= 0:
		return {"ok": false, "reason": "数量必须大于零。"}
	if operation == "buy":
		var is_relic := id.begins_with("relic:")
		var relic_id := id.trim_prefix("relic:")
		var cost := relic_price(relic_id) if is_relic else item_price(run, id)
		if cost < 0 or quantity != 1 or int(state.merchant["stock"].get(id, 0)) < 1 or run.essence < cost:
			return {"ok": false, "reason": "原质不足或商品已售罄。"}
		if is_relic:
			if not RelicDB.DEFINITIONS.has(relic_id) or RelicDB.owned(run.relic_stacks, relic_id):
				return {"ok": false, "reason": "该遗物已经拥有或无效。"}
			if not RelicDB.merchant_allowed(relic_id):
				return {"ok": false, "reason": "该遗物需要立即完成选择，不能从商人处购买。"}
			var requires := String(RelicDB.get_def(relic_id).get("requires", ""))
			if requires != "" and not RelicDB.owned(run.relic_stacks, requires):
				return {"ok": false, "reason": "尚未满足遗物进化条件。"}
			if not run.acquire_relic(relic_id, "merchant"):
				return {"ok": false, "reason": "遗物领取失败。"}
			state.relic_stacks = run.relic_stacks.duplicate()
			state.relic_state["merchant_notice"] = RelicDB.name_of(relic_id)
			if relic_id == "blood_orb":
				state.relic_state["blood_orb_active_floor"] = true
			run.sync_relic_effects_to_battle(state)
		else:
			run.trainer_items[id] = int(run.trainer_items.get(id, 0)) + 1
		run.essence -= cost
		state.merchant["stock"][id] -= 1
	elif operation == "food":
		if int(run.food_inventory.get(id, 0)) < quantity:
			return {"ok": false, "reason": "食物不足。"}
		run.food_inventory[id] -= quantity
		run.food = run.total_food()
		run.essence += quantity
	elif operation == "monster":
		var record := run.record_by_uid(int(id))
		if record.is_empty() or run.is_garrisoned(int(id)) or quantity != 1 or String(record.get("species_id", "")) in ["trainer", "tree_summon"]:
			return {"ok": false, "reason": "只能出售背包宝可梦。"}
		var remaining := run.carried.filter(func(member): return int(member["uid"]) != int(id) and int(member["hp"]) > 0)
		if remaining.is_empty():
			return {"ok": false, "reason": "至少保留一只可出战成员。"}
		run.essence += monster_price(record)
		run.sold_monster_uids.append(int(id))
		run.carried.erase(record)
		state.units = state.units.filter(func(unit): return unit.uid != int(id))
	else:
		return {"ok": false, "reason": "未知交易。"}
	return {"ok": true, "reason": "交易完成，当前原质 %d。" % run.essence}
