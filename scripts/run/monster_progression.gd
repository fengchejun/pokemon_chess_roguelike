class_name MonsterProgression
extends RefCounted

## 怪物局内等级与跨局亲密度。经验阈值依次为 4、10、18……。
## 我方实例按本局等级成长；敌方配置也使用同一生命曲线。
const FIRST_LEVEL_XP := 4
const XP_STEP_GROWTH := 2
const MAX_LEVEL := 10
const PLAYER_HP_CURVE := [0, 3, 6, 10, 14, 18, 23, 28, 34, 40]
const ENEMY_HP_PER_ODD_LEVEL := 10


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


static func normalize_record(record: Dictionary, level_cap: int = MAX_LEVEL) -> void:
	## 局内旧存档补字段；超出楼层上限的经验保留，进入下一层后再突破。
	var saved_level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	var xp := clampi(int(record.get("xp", 0)), 0, threshold_for_level(MAX_LEVEL))
	xp = maxi(xp, threshold_for_level(saved_level))
	record["xp"] = xp
	record["level"] = maxi(saved_level, mini(level_for_xp(xp), clampi(level_cap, 1, MAX_LEVEL)))
	record["affinity"] = maxi(0, int(record.get("affinity", 0)))


static func max_hp(species_id: String, level: int) -> int:
	var index := clampi(level, 1, MAX_LEVEL) - 1
	return SpeciesDB.hp_of(species_id) + int(PLAYER_HP_CURVE[index])


static func enemy_max_hp(species_id: String, level: int) -> int:
	return SpeciesDB.hp_of(species_id) + int((clampi(level, 1, MAX_LEVEL) - 1) / 2) * ENEMY_HP_PER_ODD_LEVEL


static func max_hp_for_record(record: Dictionary) -> int:
	return max_hp(String(record.get("species_id", "")), int(record.get("level", 1)))


static func award_xp(record: Dictionary, amount: int, level_cap: int = MAX_LEVEL) -> Dictionary:
	var saved_level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	if not record.has("xp"):
		record["xp"] = 0
	var before_xp := int(record["xp"])
	var before_level := saved_level
	var before_max_hp := max_hp_for_record(record)
	record["xp"] = mini(threshold_for_level(MAX_LEVEL), before_xp + maxi(0, amount))
	record["level"] = maxi(saved_level, mini(level_for_xp(int(record["xp"])), clampi(level_cap, 1, MAX_LEVEL)))
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


static func unlock_for_level_cap(record: Dictionary, level_cap: int) -> Dictionary:
	var before_level := int(record.get("level", 1))
	var before_max_hp := max_hp_for_record(record)
	normalize_record(record, level_cap)
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
