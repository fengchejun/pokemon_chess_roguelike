class_name ThreatProjection
extends RefCounted

## 将动态敌方计划收敛为目标与危险格；不泄漏逐步行动和确切伤害。
static func from_plan(state: BattleState, plan: Array) -> Dictionary:
	var intentions: Array = []
	var danger: Array = []
	for action in plan:
		var actor := state.unit_by_uid(int(action.get("uid", -1)))
		if actor == null:
			continue
		var skill: Dictionary = action.get("skill", {})
		if skill.is_empty():
			var pursuit := state.unit_by_uid(int(action.get("pursuit_uid", -1)))
			if pursuit != null:
				intentions.append("%s → 追击 %s" % [actor.display_name, pursuit.display_name])
			continue
		var entry: Dictionary = skill.get("target", {})
		var targets: Array = []
		var meta: Dictionary = action.get("meta", {})
		for hit in meta.get("hits", []):
			var hit_uid := int(hit.get("uid", -1))
			var unit := state.unit_by_uid(hit_uid)
			if unit != null and unit.side == "player" and not targets.has(unit.display_name):
				targets.append(unit.display_name)
		if targets.is_empty() and entry.has("unit"):
			var target := state.unit_by_uid(int(entry["unit"]))
			if target != null and target.side == "player":
				targets.append(target.display_name)
		if targets.is_empty() and entry.has("cell"):
			targets.append("(%d,%d)" % [entry["cell"].x, entry["cell"].y])
		intentions.append("%s → %s" % [actor.display_name, "、".join(targets) if not targets.is_empty() else "区域压制"])
		var def := SkillDB.get_def(String(skill.get("id", "")))
		if int(def.get("damage", 0)) <= 0 and not ["wind_gust", "freeze_ray", "wild_vines", "leech_seed"].has(String(skill.get("id", ""))):
			continue
		for cell in meta.get("area_cells", []):
			if GridSpec.is_inside(cell) and not danger.has(cell):
				danger.append(cell)
		for hit in meta.get("hits", []):
			var cell: Vector2i = hit.get("cell", Vector2i(-1, -1))
			if GridSpec.is_inside(cell) and not danger.has(cell):
				danger.append(cell)
		if danger.is_empty() and entry.has("cell") and GridSpec.is_inside(entry["cell"]):
			danger.append(entry["cell"])
	return {"intentions": intentions, "danger": danger}
