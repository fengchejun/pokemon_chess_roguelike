class_name CollectionState
extends RefCounted

## 跨局收藏。每个实例有独立 ID 和永久亲密度；等级、经验与生命不会跨局继承。

const SAVE_PATH := "user://collection_v1.json"
const VERSION := 2

var owned: Array = []
var next_id: int = 1
var skill_use_counts: Dictionary = {"player": {}, "enemy": {}}
var recorded_skill_battles: Dictionary = {}


static func defaults() -> CollectionState:
	var profile := CollectionState.new()
	for species_id in SpeciesDB.STARTER_TEAM:
		profile._add(String(species_id), "starter:%s" % species_id)
	return profile


static func load_profile(path: String = SAVE_PATH) -> CollectionState:
	if not FileAccess.file_exists(path):
		return defaults()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return defaults()
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return defaults()
	var saved_version := int(parsed.get("version", -1))
	if saved_version != 1 and saved_version != VERSION:
		return defaults()
	var profile := CollectionState.new()
	profile.next_id = maxi(1, int(parsed.get("next_id", 1)))
	var saved_counts: Dictionary = parsed.get("skill_use_counts", {}) if parsed.get("skill_use_counts", {}) is Dictionary else {}
	for side in ["player", "enemy"]:
		var counts: Dictionary = saved_counts.get(side, {}) if saved_counts.get(side, {}) is Dictionary else {}
		for raw_id in counts:
			var skill_id := String(raw_id)
			var amount := maxi(0, int(counts[raw_id]))
			if skill_id != "" and amount > 0:
				(profile.skill_use_counts[side] as Dictionary)[skill_id] = amount
	var saved_battles: Dictionary = parsed.get("recorded_skill_battles", {}) if parsed.get("recorded_skill_battles", {}) is Dictionary else {}
	for raw_key in saved_battles:
		if bool(saved_battles[raw_key]):
			profile.recorded_skill_battles[String(raw_key)] = true
	var seen := {}
	for raw in parsed.get("owned", []):
		if not raw is Dictionary:
			continue
		var species_id := String(raw.get("species_id", ""))
		var id := int(raw.get("id", -1))
		if SpeciesDB.get_species(species_id).is_empty() or id <= 0 or seen.has(id):
			continue
		seen[id] = true
		var record := {
			"id": id,
			"species_id": species_id,
			"source": String(raw.get("source", "")),
			## v1 的永久等级/经验已废止，迁移只继承实例与物种。
			"affinity": maxi(0, int(raw.get("affinity", 0))) if saved_version == VERSION else 0,
		}
		profile.owned.append(record)
		profile.next_id = maxi(profile.next_id, id + 1)
	if profile.owned.size() < 3:
		return defaults()
	return profile


func save(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var serialized: Array = []
	for record in owned:
		serialized.append({
			"id": int(record["id"]),
			"species_id": String(record["species_id"]),
			"source": String(record.get("source", "")),
			"affinity": maxi(0, int(record.get("affinity", 0))),
		})
	file.store_string(JSON.stringify({"version": VERSION, "next_id": next_id, "owned": serialized,
		"skill_use_counts": skill_use_counts, "recorded_skill_battles": recorded_skill_battles}, "\t"))
	file.close()
	return true


func record_battle_skill_usage(battle: BattleState) -> bool:
	if battle == null or not battle.ended:
		return false
	var key := "%d:%d" % [battle.run_seed, battle.battle_index]
	if recorded_skill_battles.has(key):
		return false
	for side in ["player", "enemy"]:
		var source: Dictionary = battle.skill_use_counts.get(side, {})
		var total: Dictionary = skill_use_counts[side]
		for raw_id in source:
			var amount := maxi(0, int(source[raw_id]))
			if amount > 0:
				var skill_id := String(raw_id)
				total[skill_id] = int(total.get(skill_id, 0)) + amount
	recorded_skill_battles[key] = true
	return true


func skill_use_total(side: String) -> int:
	var total := 0
	var counts: Dictionary = skill_use_counts.get(side, {})
	for amount in counts.values():
		total += int(amount)
	return total


func _add(species_id: String, source: String) -> int:
	var id := next_id
	next_id += 1
	owned.append({"id": id, "species_id": species_id, "source": source, "affinity": 0})
	return id


func record_by_id(id: int) -> Dictionary:
	for record in owned:
		if int(record["id"]) == id:
			return record
	return {}


func select_records(ids: Array) -> Array:
	if ids.size() != Balance.DEPLOY_LIMIT:
		return []
	var selected: Array = []
	for id in ids:
		if selected.any(func(record: Dictionary) -> bool: return int(record["id"]) == int(id)):
			return []
		var record := record_by_id(int(id))
		if record.is_empty():
			return []
		selected.append(record.duplicate())
	return selected


func absorb_run(run: RunState) -> int:
	## 战斗结束后同步亲密度，并登记携带与仓库（含濒死）里的新怪物。
	var added := 0
	for group in [run.carried, run.storage]:
		for record in group:
			var collection_id := int(record.get("collection_id", -1))
			var existing := record_by_id(collection_id)
			if not existing.is_empty():
				_sync_affinity(existing, record)
				continue
			var source := "run:%d:%d" % [run.seed, int(record.get("uid", -1))]
			var existing_id := -1
			for owned_record in owned:
				if String(owned_record.get("source", "")) == source:
					existing_id = int(owned_record["id"])
					break
			if existing_id < 0:
				existing_id = _add(String(record["species_id"]), source)
				added += 1
			record["collection_id"] = existing_id
			_sync_affinity(record_by_id(existing_id), record)
	return added


func _sync_affinity(destination: Dictionary, source: Dictionary) -> void:
	## 旧局存档再次吸收时不会覆盖更高的永久亲密度。
	destination["affinity"] = maxi(
		maxi(0, int(destination.get("affinity", 0))),
		maxi(0, int(source.get("affinity", 0)))
	)
