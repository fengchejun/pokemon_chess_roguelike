extends RefCounted

const CONVERSION := {"common": 6, "rare": 10, "legendary": 16}
const POINT_NAMES := {"common": "普通奖励点", "medium": "中级奖励点", "high": "高级奖励点"}


static func grant_random_relic(run: RunState, rarity: String, rng: RandomNumberGenerator) -> String:
	var pool := RelicDB.ids_of_rarity(rarity).filter(func(id): return RelicDB.rank(run.relic_stacks, id) < RelicDB.MAX_RANK)
	if pool.is_empty():
		var compensation := int(CONVERSION[rarity])
		run.essence += compensation
		return "%d 原质（该稀有度遗物均已满级）" % compensation
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	run.relic_stacks[id] = RelicDB.rank(run.relic_stacks, id) + 1
	return RelicDB.display_name_of(id)


static func _award_medium_item(run: RunState, rng: RandomNumberGenerator) -> String:
	var id := "xp_candy_medium"
	var skills := {}
	for member in run.carried:
		for skill in run.available_new_skills(int(member["uid"])):
			skills[skill] = true
	if rng.randi_range(0, 1) == 1 and not skills.is_empty():
		var pool := skills.keys()
		pool.sort()
		var skill: String = pool[rng.randi_range(0, pool.size() - 1)]
		id = Merchant.BOOK_PREFIX + skill
		run.trainer_items[id] = int(run.trainer_items.get(id, 0)) + 1
		return "技能书 · " + SkillDB.name_of(skill)
	run.trainer_items[id] = int(run.trainer_items.get(id, 0)) + 1
	return Merchant.ITEMS[id][0]


static func _queue_legendary(run: RunState, rng: RandomNumberGenerator) -> void:
	var pool := RelicDB.ids_of_rarity(RelicDB.LEGENDARY)
	var available := pool.filter(func(id): return RelicDB.rank(run.relic_stacks, id) < RelicDB.MAX_RANK)
	var offers := []
	while offers.size() < 3:
		var candidates := available if not available.is_empty() else pool
		var id = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		offers.append(id)
		pool.erase(id)
	run.legendary_offers.append(offers)
	run.pending_reward_choices += 1


static func redeem(run: RunState, tier: String, source_key: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("battle-loot:%d:%s" % [run.seed, source_key])
	var results := []
	var essence := 0
	match tier:
		"common":
			essence = rng.randi_range(3, 7)
			var upgrade := rng.randf() < 0.10
			var candy := rng.randf() < 0.50
			results.append(grant_random_relic(run, RelicDB.RARE if upgrade else RelicDB.COMMON, rng))
			if candy:
				run.trainer_items["xp_candy_small"] = int(run.trainer_items.get("xp_candy_small", 0)) + 1
				results.append(Merchant.ITEMS["xp_candy_small"][0])
		"medium":
			essence = rng.randi_range(7, 12)
			var upgrade := rng.randf() < 0.10
			var bonus := rng.randf() < 0.50
			results.append(grant_random_relic(run, RelicDB.LEGENDARY if upgrade else RelicDB.RARE, rng))
			if bonus:
				results.append(_award_medium_item(run, rng))
		"high":
			essence = rng.randi_range(12, 20)
			var common := rng.randf() < 0.50
			var rare := rng.randf() < 0.10
			_queue_legendary(run, rng)
			results.append("传奇遗物三选一")
			results.append(_award_medium_item(run, rng))
			if common:
				results.append(grant_random_relic(run, RelicDB.COMMON, rng))
			if rare:
				results.append(grant_random_relic(run, RelicDB.RARE, rng))
	run.essence += essence
	results.push_front("%d 原质" % essence)
	return results
