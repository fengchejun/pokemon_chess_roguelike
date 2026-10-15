class_name MonsterProgression
extends RefCounted

## 怪物局内等级与跨局亲密度。经验阈值依次为 4、10、18……。
## 仅出战实例成长；物种基础属性与野生敌人不受影响。
const FIRST_LEVEL_XP := 4
const XP_STEP_GROWTH := 2
const MAX_LEVEL := 10
const HP_PER_ODD_LEVEL := 1


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


static func normalize_record(record: Dictionary) -> void:
	## 局内旧存档补字段；若只有等级没有经验，保留该等级到本局结束。
	var saved_level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	var xp := clampi(int(record.get("xp", 0)), 0, threshold_for_level(MAX_LEVEL))
	xp = maxi(xp, threshold_for_level(saved_level))
	record["xp"] = xp
	record["level"] = level_for_xp(xp)
	record["affinity"] = maxi(0, int(record.get("affinity", 0)))


static func max_hp(species_id: String, level: int) -> int:
	## Lv3/5/7/9 各 +1 HP，Lv2/4/6/8/10 不额外加生命。
	return SpeciesDB.hp_of(species_id) + ((clampi(level, 1, MAX_LEVEL) - 1) / 2) * HP_PER_ODD_LEVEL


static func max_hp_for_record(record: Dictionary) -> int:
	return max_hp(String(record.get("species_id", "")), int(record.get("level", 1)))


static func award_xp(record: Dictionary, amount: int) -> Dictionary:
	normalize_record(record)
	var before_xp := int(record["xp"])
	var before_level := int(record["level"])
	record["xp"] = mini(threshold_for_level(MAX_LEVEL), before_xp + maxi(0, amount))
	record["level"] = level_for_xp(int(record["xp"]))
	return {
		"xp_before": before_xp,
		"xp_after": int(record["xp"]),
		"level_before": before_level,
		"level_after": int(record["level"]),
		"gained": int(record["xp"]) - before_xp,
	}


static func award_affinity(record: Dictionary, amount: int) -> Dictionary:
	var before := maxi(0, int(record.get("affinity", 0)))
	var after := before + maxi(0, amount)
	record["affinity"] = after
	return {"before": before, "after": after, "gained": after - before}
