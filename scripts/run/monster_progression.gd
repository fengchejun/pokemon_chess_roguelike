class_name MonsterProgression
extends RefCounted

## 怪物局内等级与跨局亲密度。
## 我方实例按本局等级成长；敌方配置也使用同一生命曲线。
const XP_THRESHOLDS := [0, 6, 18, 38, 68, 110, 166, 238, 328, 400]
const MAX_LEVEL := 10
const HP_PER_ODD_LEVEL := 10


static func threshold_for_level(level: int) -> int:
	if level <= 1:
		return 0
	return XP_THRESHOLDS[mini(level, MAX_LEVEL) - 1]

static func migrate_legacy_xp(record: Dictionary) -> void:
	var level := clampi(int(record.get("level", 1)), 1, MAX_LEVEL)
	var xp := clampi(int(record.get("xp", 0)), 0, 108)
	while level < MAX_LEVEL and xp >= legacy_threshold(level + 1):
		level += 1
	if level == MAX_LEVEL:
		record["xp"] = threshold_for_level(MAX_LEVEL)
	else:
		var old_start := legacy_threshold(level)
		var fraction := clampf(float(xp - old_start) / float(legacy_threshold(level + 1) - old_start), 0.0, 1.0)
		var start := threshold_for_level(level)
		record["xp"] = start + floori(fraction * (threshold_for_level(level + 1) - start))
	record["level"] = level

static func legacy_threshold(level: int) -> int:
	var steps := clampi(level, 1, MAX_LEVEL) - 1
	return steps * 4 + steps * (steps - 1)


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
	return SpeciesDB.hp_of(species_id) + int((clampi(level, 1, MAX_LEVEL) - 1) / 2) * HP_PER_ODD_LEVEL


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
