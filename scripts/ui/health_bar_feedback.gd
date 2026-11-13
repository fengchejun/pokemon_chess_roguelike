extends RefCounted

const HOLD := 0.18
const SHRINK := 0.55
var previous: Dictionary = {}
var trails: Dictionary = {}

func sync(units: Array) -> void:
	var present := {}
	for unit in units:
		present[unit.uid] = true
		var ratio := clampf(float(unit.hp) / maxi(1, unit.max_hp), 0.0, 1.0)
		if previous.has(unit.uid):
			var old: Dictionary = previous[unit.uid]
			if unit.max_hp == old["max_hp"] and unit.hp < old["hp"]:
				trails[unit.uid] = {"from": maxf(float(old["ratio"]), displayed_ratio(unit.uid, ratio)), "to": ratio, "age": 0.0}
			elif unit.hp > old["hp"] or unit.max_hp != old["max_hp"]:
				trails.erase(unit.uid)
		previous[unit.uid] = {"hp": unit.hp, "max_hp": unit.max_hp, "ratio": ratio}
	for uid in previous.keys():
		if not present.has(uid):
			previous.erase(uid)
			trails.erase(uid)

func advance(delta: float) -> void:
	for uid in trails.keys():
		trails[uid]["age"] += delta
		if trails[uid]["age"] >= HOLD + SHRINK: trails.erase(uid)

func displayed_ratio(uid: int, current: float) -> float:
	if not trails.has(uid): return current
	var trail: Dictionary = trails[uid]
	var progress := clampf((float(trail["age"]) - HOLD) / SHRINK, 0, 1)
	return maxf(current, lerpf(trail["from"], trail["to"], progress))
