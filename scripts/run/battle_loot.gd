extends RefCounted

const CONVERSION := {"common": 6, "rare": 10, "legendary": 16}
const POINT_NAMES := {"common": "普通奖励点", "medium": "中级奖励点", "high": "高级奖励点"}

static func available_relics(run: RunState, rarity: String) -> Array:
	return RelicDB.available_ids(run.relic_stacks).filter(func(id): return RelicDB.rarity_of(id) == rarity)

static func grant_random_relic(run: RunState, rarity: String, rng: RandomNumberGenerator) -> String:
	var pool := available_relics(run, rarity)
	if pool.is_empty():
		var compensation := int(CONVERSION[rarity])
		run.essence += compensation
		return "%d 原质（该档遗物池已耗尽）" % compensation
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	run.acquire_relic(id, "random_reward")
	return RelicDB.display_name_of(id)

static func _relic_offer(run: RunState, rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool := available_relics(run, rarity)
	if pool.is_empty():
		var compensation := int(CONVERSION[rarity])
		return {"kind": "essence", "amount": compensation, "label": "原质 ×%d（遗物池已耗尽）" % compensation}
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	return {"kind": "relic", "id": id, "label": RelicDB.display_name_of(id)}

static func _item_offer(run: RunState, rng: RandomNumberGenerator) -> Dictionary:
	var id := "xp_candy_medium"
	var skills := {}
	for member in run.carried:
		for skill in run.available_new_skills(int(member["uid"])):
			skills[skill] = true
	if rng.randi_range(0, 1) == 1 and not skills.is_empty():
		var pool := skills.keys()
		pool.sort()
		id = Merchant.BOOK_PREFIX + String(pool[rng.randi_range(0, pool.size() - 1)])
	var label := "技能书 · " + SkillDB.name_of(id.trim_prefix(Merchant.BOOK_PREFIX)) if id.begins_with(Merchant.BOOK_PREFIX) else String(Merchant.ITEMS[id][0])
	return {"kind": "item", "id": id, "amount": 1, "label": label}

# Preview selects rewards without triggering any acquisition effects.
static func preview(run: RunState, tier: String, source_key: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("battle-loot:%d:%s" % [run.seed, source_key])
	var offers: Array = []
	match tier:
		"common":
			offers.append({"kind": "essence", "amount": rng.randi_range(3, 7)})
			var rarity := RelicDB.RARE if rng.randf() < 0.10 else RelicDB.COMMON
			var candy := rng.randf() < 0.50
			offers.append(_relic_offer(run, rarity, rng))
			if candy:
				offers.append({"kind": "item", "id": "xp_candy_small", "amount": 1, "label": String(Merchant.ITEMS["xp_candy_small"][0])})
		"medium":
			offers.append({"kind": "essence", "amount": rng.randi_range(7, 12)})
			var rarity := RelicDB.LEGENDARY if rng.randf() < 0.10 else RelicDB.RARE
			var bonus := rng.randf() < 0.50
			offers.append(_relic_offer(run, rarity, rng))
			if bonus:
				offers.append(_item_offer(run, rng))
		"high":
			offers.append({"kind": "essence", "amount": rng.randi_range(12, 20)})
			var common := rng.randf() < 0.50
			var rare := rng.randf() < 0.10
			var pool := available_relics(run, RelicDB.LEGENDARY)
			var choices: Array = []
			while choices.size() < 3 and not pool.is_empty():
				choices.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			if choices.is_empty():
				offers.append({"kind": "essence", "amount": 16})
			else:
				offers.append({"kind": "legendary", "offers": choices, "label": "传奇遗物三选一"})
			offers.append(_item_offer(run, rng))
			if common: offers.append(_relic_offer(run, RelicDB.COMMON, rng))
			if rare: offers.append(_relic_offer(run, RelicDB.RARE, rng))
	for offer in offers:
		if not offer.has("label"):
			offer["label"] = "原质 ×%d" % int(offer["amount"])
	return offers

static func grant_offer(run: RunState, offer: Dictionary) -> void:
	match String(offer["kind"]):
		"essence":
			run.essence += int(offer["amount"])
		"item":
			var id := String(offer["id"])
			run.trainer_items[id] = int(run.trainer_items.get(id, 0)) + int(offer["amount"])
		"relic":
			var id := String(offer["id"])
			if not run.acquire_relic(id, "battle_reward"):
				run.essence += int(CONVERSION.get(RelicDB.rarity_of(id), 6))
		"relic_choice":
			run.pending_reward_choices += 1
		"legendary":
			var available := RelicDB.available_ids(run.relic_stacks)
			var choices: Array = offer["offers"].filter(func(id): return available.has(id))
			if choices.is_empty():
				run.essence += 16
			else:
				run.legendary_offers.append(choices)
				run.pending_reward_choices += 1

static func redeem(run: RunState, tier: String, source_key: String) -> Array:
	var labels: Array = []
	for offer in preview(run, tier, source_key):
		grant_offer(run, offer)
		labels.append(offer["label"])
	return labels
