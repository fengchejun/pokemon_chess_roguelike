class_name RelicDB
extends RefCounted

## 旧版遗物已全部删除；保留接口供后续新版遗物池按同一随机与等级协议接入。
const MAX_RANK := 3
const DEFINITIONS := {}


static func ids() -> Array:
	return DEFINITIONS.keys()


static func rank(stacks: Dictionary, relic_id: String) -> int:
	return clampi(int(stacks.get(relic_id, 0)), 0, MAX_RANK)


static func name_of(relic_id: String) -> String:
	return String(DEFINITIONS.get(relic_id, [relic_id, ""])[0])


static func description_of(relic_id: String) -> String:
	return String(DEFINITIONS.get(relic_id, [relic_id, ""])[1])


static func offer(seed_value: int, battle_index: int, choice_index: int, stacks: Dictionary, count: int = 3) -> Array:
	var pool: Array = []
	for relic_id in ids():
		if rank(stacks, relic_id) < MAX_RANK:
			pool.append(relic_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("relic:%d:%d:%d" % [seed_value, battle_index, choice_index])
	var result: Array = []
	while result.size() < count and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result
