class_name Merchant
extends RefCounted

const RARITIES := {"common": ["普通", 10], "rare": ["稀有", 15], "precious": ["珍稀", 25]}
const ITEMS := {"potion": ["治疗药", 5, "恢复三格内一个存活己方单位15 HP，不能复活。"], "capture_aid": ["捕获辅助", 6, "本次探索下一次捕获概率增加20个百分点。"]}

static func item_target_valid(state: BattleState, target: CombatUnit) -> bool:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	if target == null or not target.is_alive() or target.side != "player" or target.hp >= target.max_hp or GridSpec.manhattan(trainer.cell, target.cell) > 3:
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
	if state.ended or state.phase != BattleState.PHASE_PLAYER or trainer == null or not trainer.is_alive() or not trainer.can_act_skill() or trainer.capture_used or trainer.channel_lock_round == state.round or not ITEMS.has(id) or int(run.trainer_items.get(id, 0)) <= 0:
		return {"ok": false, "reason": "道具不足或训练师本回合无法行动。"}
	if id == "potion":
		var target := state.unit_by_uid(target_uid)
		if not item_target_valid(state, target):
			return {"ok": false, "reason": "请选择三格内视线可达、受伤且存活的己方单位。"}
		var healed := mini(target.max_hp - target.hp, 15)
		target.hp += healed
		state.feedback_heal(target, healed)
	else:
		if state.capture_aid:
			return {"ok": false, "reason": "捕获辅助已经生效。"}
		state.capture_aid = true
	state.commit_actions()
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

static func ensure_region(region: RegionState, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("merchant:%d:%d" % [seed_value, region.floor_index])
	var id := "event_%d" % rng.randi_range(1, 2)
	if region.nodes[id].has("merchant"):
		return
	var pool: Array = RelicDB.DEFINITIONS.keys()
	var stock := {"potion": 2, "capture_aid": 2}
	for i in 3:
		var relic: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		stock["relic:" + relic] = 1
	region.nodes[id]["merchant"] = {"stock": stock, "cell": [-1, -1]}

static func trade(run: RunState, state: BattleState, operation: String, id: String, quantity: int = 1) -> Dictionary:
	var trainer := state.unit_by_uid(Balance.TRAINER_UID)
	if state.ended or state.phase != BattleState.PHASE_PLAYER or state.node_kind != "event" or state.merchant.is_empty() or trainer == null or not trainer.is_alive() or not state.can_interact_at(state.merchant["cell"]):
		return {"ok": false, "reason": "训练师需在收集区商人相邻格交易。"}
	if quantity <= 0:
		return {"ok": false, "reason": "数量必须大于零。"}
	if operation == "buy":
		var cost := 16 if id.begins_with("relic:") else int(ITEMS.get(id, ["", -1])[1])
		if cost < 0 or quantity != 1 or int(state.merchant["stock"].get(id, 0)) < 1 or run.essence < cost:
			return {"ok": false, "reason": "原质不足或商品已售罄。"}
		if id.begins_with("relic:"):
			var relic := id.trim_prefix("relic:")
			if RelicDB.rank(run.relic_stacks, relic) >= RelicDB.MAX_RANK:
				return {"ok": false, "reason": "遗物已满级。"}
			run.relic_stacks[relic] = RelicDB.rank(run.relic_stacks, relic) + 1
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
	elif operation == "relic":
		if quantity != 1 or RelicDB.rank(run.relic_stacks, id) <= 0:
			return {"ok": false, "reason": "没有可出售的遗物。"}
		run.relic_stacks[id] -= 1
		run.essence += 8
	elif operation == "monster":
		var record := run.record_by_uid(int(id))
		if record.is_empty() or quantity != 1 or String(record.get("species_id", "")) in ["trainer", "tree_summon"]:
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
	state.relic_stacks = run.relic_stacks.duplicate()
	return {"ok": true, "reason": "交易完成，当前原质 %d。" % run.essence}
