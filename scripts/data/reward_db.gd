class_name RewardDB
extends RefCounted

## 战后奖励统一 ID。当前奖励池只有本局消耗品；强化由经验阈值另行解锁。
const MOD_ITEM := "mod:field_kit"


static func consumable_ids() -> Array:
	var result: Array = []
	for card_id in CardDB.ALL_IDS:
		result.append("position:%s" % card_id)
	for card_id in MapCardDB.ALL_IDS:
		result.append("map:%s" % card_id)
	result.append(MOD_ITEM)
	return result


static func is_consumable(reward_id: String) -> bool:
	return consumable_ids().has(reward_id)


static func name_of(reward_id: String) -> String:
	if reward_id.begins_with("position:"):
		return "站位卡·%s" % CardDB.name_of(reward_id.trim_prefix("position:"))
	if reward_id.begins_with("map:"):
		return "地貌卡·%s" % MapCardDB.get_card(reward_id.trim_prefix("map:")).get("name", reward_id)
	if reward_id == MOD_ITEM:
		return "地形改造工具"
	return reward_id


static func description_of(reward_id: String) -> String:
	if reward_id.begins_with("position:"):
		var card := CardDB.get_card(reward_id.trim_prefix("position:"))
		return "%s：%s。预览页使用后立即消耗，本场战斗生效。" % [card.get("anchor", ""), card.get("effect", "")]
	if reward_id.begins_with("map:"):
		return "%s 预览页使用后立即消耗、刷新地图；对应地形数量比当前图更多。" % MapCardDB.get_card(reward_id.trim_prefix("map:")).get("desc", "")
	if reward_id == MOD_ITEM:
		return "预览页使用后立即消耗，可在本场预览地图改造最多 %d 格。" % Balance.MOD_POINTS
	return ""


static func offer(seed_value: int, battle_index: int, choice_index: int, count: int = 3) -> Array:
	## 三张不同消耗品；同种卡可在不同战斗再次获得。
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("reward:%d:%d:%d" % [seed_value, battle_index, choice_index])
	var pool := consumable_ids()
	var result: Array = []
	while result.size() < count and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result
