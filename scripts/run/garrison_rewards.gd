extends RefCounted

const Loot = preload("res://scripts/run/battle_loot.gd")
const ACTIONS_PER_REWARD := 3

static func duration(region: RegionState, assignment: Dictionary) -> int:
	return maxi(0, region.visits - int(region.visit_pending) - int(assignment["ready"]))

static func odds(actions: int) -> Dictionary:
	var rare := mini(30, 10 + 2 * maxi(0, actions))
	var legendary := mini(10, 1 + maxi(0, actions) / 2)
	return {"common": 100 - rare - legendary, "rare": rare, "legendary": legendary}

static func reward_pool(rarity: String, run: RunState = null) -> Array:
	var pool: Array = []
	for id in RelicDB.ids_of_rarity(rarity):
		if run != null and not RelicDB.available_ids(run.relic_stacks).has(id):
			continue
		pool.append("relic:" + id)
	for id in Merchant.ITEMS:
		var price := int(Merchant.ITEMS[id][1])
		var tier := "legendary" if price >= 25 else "rare" if price >= 15 else "common"
		if tier == rarity:
			pool.append("item:" + id)
	if rarity == "common":
		pool.append_array(["food", "essence"])
	for id in RewardDB.consumable_ids():
		var tier := "common" if String(id).begins_with("position:") else "rare"
		if tier == rarity:
			pool.append("card:" + id)
	if rarity == "rare":
		var skills: Array = []
		for element in ["fire", "water", "grass", "electric", "rock"]:
			skills.append_array(SkillDB.learnable_ids_for(element))
		for species in SpeciesDB.SPECIES.values():
			for skill in species.get("skills", []):
				if not skills.has(skill) and not SkillDB.is_special(skill):
					skills.append(skill)
		for skill in skills:
			pool.append("item:" + Merchant.BOOK_PREFIX + skill)
	pool.sort()
	return pool

static func grant(run: RunState, id: String) -> String:
	if id == "food":
		run.add_food("basic", 1)
		return "基础食物 ×1"
	if id == "essence":
		run.essence += 3
		return "原质 ×3"
	if id.begins_with("card:"):
		var card := id.trim_prefix("card:")
		run.reward_inventory.append(card)
		return RewardDB.name_of(card)
	if id.begins_with("item:"):
		var item := id.trim_prefix("item:")
		run.trainer_items[item] = int(run.trainer_items.get(item, 0)) + 1
		return "技能书 · " + SkillDB.name_of(item.trim_prefix(Merchant.BOOK_PREFIX)) if item.begins_with(Merchant.BOOK_PREFIX) else String(Merchant.ITEMS[item][0])
	var relic := id.trim_prefix("relic:")
	if not run.acquire_relic(relic, "garrison"):
		var compensation := int(Loot.CONVERSION[RelicDB.rarity_of(relic)])
		run.essence += compensation
		return "原质 ×%d（遗物不可重复折算）" % compensation
	return RelicDB.display_name_of(relic)

static func settle(run: RunState, region: RegionState, uid: int, reason: String, forced: bool = false) -> Array:
	var key := str(uid)
	var assignment: Dictionary = region.garrisons.get(key, {})
	if assignment.is_empty() or assignment.get("reward_settled", false):
		return []
	assignment["reward_settled"] = true
	var actions := duration(region, assignment)
	var credit := int(run.garrison_reward_credits.get(key, 0)) + actions
	var count := credit / ACTIONS_PER_REWARD
	var remainder := credit % ACTIONS_PER_REWARD
	if forced and remainder > 0:
		count += 1
		remainder = 0
	run.garrison_reward_credits[key] = remainder
	var rewards: Array = []
	var chances := odds(actions)
	for index in count:
		var serial := int(run.garrison_reward_rolls.get(key, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("garrison:%d:%s:%d" % [run.seed, key, serial])
		var roll := rng.randi_range(0, 99)
		var rarity := "legendary" if roll < int(chances["legendary"]) else "rare" if roll < int(chances["legendary"]) + int(chances["rare"]) else "common"
		var pool := reward_pool(rarity, run)
		rewards.append(grant(run, pool[rng.randi_range(0, pool.size() - 1)]))
		run.garrison_reward_rolls[key] = serial + 1
	if actions > 0 or not rewards.is_empty():
		var member := run.owned_record_by_uid(uid)
		var message := "%s · %s · 驻守%d行动：%s" % [SpeciesDB.name_of(member.get("species_id", "")), reason, actions, "、".join(rewards) if not rewards.is_empty() else "额度保留 %d/3" % remainder]
		run.garrison_reward_history.append(message)
		if run.garrison_reward_history.size() > 20:
			run.garrison_reward_history.pop_front()
	return rewards

static func finish_all(run: RunState, region: RegionState, reason: String) -> void:
	for key in region.garrisons.keys():
		settle(run, region, int(key), reason, true)
	region.garrisons.clear()
	run.region_data = region.to_dict()

# Entry previews can be cancelled. Keep management and payouts across that rollback.
static func sync_entry_backup(run: RunState, region: RegionState) -> void:
	if not run.pending_region_entry_backup.is_empty():
		run.pending_region_entry_backup["garrisons"] = region.garrisons.duplicate(true)
