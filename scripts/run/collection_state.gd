class_name CollectionState
extends RefCounted

## 跨局收藏。每个实例有独立 ID；生命与局内强化不会跨局继承。

const SAVE_PATH := "user://collection_v1.json"
const VERSION := 1

var owned: Array = []
var next_id: int = 1


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
	if not parsed is Dictionary or int(parsed.get("version", -1)) != VERSION:
		return defaults()
	var profile := CollectionState.new()
	profile.next_id = maxi(1, int(parsed.get("next_id", 1)))
	var seen := {}
	for raw in parsed.get("owned", []):
		if not raw is Dictionary:
			continue
		var species_id := String(raw.get("species_id", ""))
		var id := int(raw.get("id", -1))
		if SpeciesDB.get_species(species_id).is_empty() or id <= 0 or seen.has(id):
			continue
		seen[id] = true
		profile.owned.append({"id": id, "species_id": species_id, "source": String(raw.get("source", ""))})
		profile.next_id = maxi(profile.next_id, id + 1)
	if profile.owned.size() < 3:
		return defaults()
	return profile


func save(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "next_id": next_id, "owned": owned}, "\t"))
	file.close()
	return true


func _add(species_id: String, source: String) -> int:
	var id := next_id
	next_id += 1
	owned.append({"id": id, "species_id": species_id, "source": source})
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
	## 战斗结束后把携带与仓库（含濒死）里的新怪物登记；重复调用不会复制。
	var added := 0
	for group in [run.carried, run.storage]:
		for record in group:
			var collection_id := int(record.get("collection_id", -1))
			if not record_by_id(collection_id).is_empty():
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
	return added
