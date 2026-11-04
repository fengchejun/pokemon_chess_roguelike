class_name MonsterProgression
extends RefCounted

## 怪物局内等级与跨局亲密度。累计经验：0、6、16、30、48、70、96、126、160、198。
## 我方实例按本局等级成长；敌方配置也使用同一生命曲线。
const FIRST_LEVEL_XP := 6
const XP_STEP_GROWTH := 4
const MAX_LEVEL := 10
const LEARN_LEVELS := [2, 4, 6, 8]



static func threshold_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var steps := mini(level, MAX_LEVEL) - 1
	return steps * FIRST_LEVEL_XP + (steps * (steps - 1) / 2) * XP_STEP_GROWTH


static func level_for_xp(xp: int) -> int:
	var level := 1
	var earned := clampi(xp, 0, threshold_for_level(MAX_LEVEL))
	while level < MAX_LEVEL and earned >= threshold_for_level(level + 1):
		level += 1
	return level


static func enemy_xp_reward(level: int, is_boss: bool = false) -> int:
	var reward := 1 + ceili(float(maxi(1, level)) / 2.0)
	return reward + (2 if is_boss else 0)


static func enemy_participation_xp(level: int) -> int:
	return maxi(1, floori(float(enemy_xp_reward(level)) / 2.0))


static func normalize_record(record: Dictionary, _level_cap: int = MAX_LEVEL) -> void:
	## 补齐旧存档字段；不再按楼层限制等级。
	var saved_level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	var xp := clampi(int(record.get("xp", 0)), 0, threshold_for_level(MAX_LEVEL))
	xp = maxi(xp, threshold_for_level(saved_level))
	record["xp"] = xp
	record["level"] = maxi(saved_level, level_for_xp(xp))
	record["affinity"] = maxi(0, int(record.get("affinity", 0)))


static func max_hp(species_id: String, level: int) -> int:
	var steps := clampi(level, 1, MAX_LEVEL) - 1
	return SpeciesDB.hp_of(species_id) + steps * (steps + 5)


static func enemy_max_hp(species_id: String, level: int) -> int:
	return max_hp(species_id, level)


static func max_hp_for_record(record: Dictionary) -> int:
	return max_hp(String(record.get("species_id", "")), int(record.get("level", 1)))


static func award_xp(record: Dictionary, amount: int, _level_cap: int = MAX_LEVEL) -> Dictionary:
	var saved_level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	if not record.has("xp"):
		record["xp"] = 0
	var before_xp := int(record["xp"])
	var before_level := saved_level
	var before_max_hp := max_hp_for_record(record)
	record["xp"] = mini(threshold_for_level(MAX_LEVEL), before_xp + maxi(0, amount))
	record["level"] = maxi(saved_level, level_for_xp(int(record["xp"])))
	var after_max_hp := max_hp_for_record(record)
	if int(record.get("hp", 0)) > 0 and after_max_hp > before_max_hp:
		record["hp"] = int(record["hp"]) + after_max_hp - before_max_hp
	return {
		"xp_before": before_xp,
		"xp_after": int(record["xp"]),
		"level_before": before_level,
		"level_after": int(record["level"]),
		"gained": int(record["xp"]) - before_xp,
	}


static func unlock_for_level_cap(record: Dictionary, _level_cap: int) -> Dictionary:
	var before_level := int(record.get("level", 1))
	var before_max_hp := max_hp_for_record(record)
	normalize_record(record)
	var after_max_hp := max_hp_for_record(record)
	if int(record.get("hp", 0)) > 0 and after_max_hp > before_max_hp:
		record["hp"] = int(record["hp"]) + after_max_hp - before_max_hp
	return {
		"level_before": before_level,
		"level_after": int(record.get("level", 1)),
	}


static func award_affinity(record: Dictionary, amount: int) -> Dictionary:
	var before := maxi(0, int(record.get("affinity", 0)))
	var after := before + maxi(0, amount)
	record["affinity"] = after
	return {"before": before, "after": after, "gained": after - before}


static func migrate_legacy_xp(record: Dictionary) -> void:
	# Legacy 108-XP saves preserve their level and fractional progress.
	migrate_mainline_xp(record, false)


static func migrate_mainline_xp(record: Dictionary, mainline: bool = true) -> void:
	var old_thresholds := [0, 6, 18, 38, 68, 110, 166, 238, 328, 400] if mainline else [0, 4, 10, 18, 28, 40, 54, 70, 88, 108]
	var level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	var xp := int(record.get("xp", 0))
	while level < MAX_LEVEL and xp >= int(old_thresholds[level]):
		level += 1
	var fraction := 0.0
	if level < MAX_LEVEL:
		fraction = clampf(float(xp - int(old_thresholds[level - 1])) / float(int(old_thresholds[level]) - int(old_thresholds[level - 1])), 0.0, 1.0)
	record["level"] = level
	record["xp"] = threshold_for_level(level) + (floori(fraction * (threshold_for_level(level + 1) - threshold_for_level(level))) if level < MAX_LEVEL else 0)
