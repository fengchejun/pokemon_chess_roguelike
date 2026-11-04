class_name DebugTools
extends RefCounted

## F7 控制台调用的受检规则入口。仅由调试界面开放；正式玩法不引用。


static func add_monster(run: RunState, species_id: String) -> Dictionary:
	if run == null or SpeciesDB.get_species(species_id).is_empty() or SpeciesDB.is_trainer(species_id) or species_id == "tree_summon":
		return {"ok": false, "message": "不是可携带的怪物。"}
	if run.carried.size() >= Balance.CARRIED_LIMIT:
		return {"ok": false, "message": "携带队伍已满（6 只）；请先移出一只。"}
	var record := run._make_record(species_id)
	record["debug_spawned"] = true
	run.carried.append(record)
	run.debug_tainted = true
	return {"ok": true, "message": "已加入 %s（UID %d）；仅属于本局调试队伍。" % [SpeciesDB.name_of(species_id), int(record["uid"])], "uid": record["uid"]}


static func move_to_storage(run: RunState, uid: int) -> Dictionary:
	if run == null or run.storage.size() >= Balance.STORAGE_LIMIT:
		return {"ok": false, "message": "仓库已满。"}
	for index in range(run.carried.size()):
		var record: Dictionary = run.carried[index]
		if int(record["uid"]) == uid:
			run.carried.remove_at(index)
			run.storage.append(record)
			run.deployed_uids.erase(uid)
			run.debug_tainted = true
			return {"ok": true, "message": "%s 已移入仓库。" % SpeciesDB.name_of(String(record["species_id"]))}
	return {"ok": false, "message": "该怪物不在携带队伍中。"}


static func add_skill(run: RunState, uid: int, skill_id: String) -> Dictionary:
	if run == null or SkillDB.get_def(skill_id).is_empty():
		return {"ok": false, "message": "未知技能 ID。"}
	var record := run.owned_record_by_uid(uid)
	if record.is_empty():
		return {"ok": false, "message": "未找到目标怪物。"}
	var known: Array = record.get("known_skills", []).duplicate()
	if known.has(skill_id):
		return {"ok": false, "message": "这只怪物已经学会该技能。"}
	known.append(skill_id)
	record["known_skills"] = known
	run.debug_tainted = true
	var equipped: Array = record.get("equipped_skills", []).duplicate()
	if equipped.size() < RunState.MAX_EQUIPPED_SKILLS:
		equipped.append(skill_id)
		record["equipped_skills"] = equipped
		return {"ok": true, "message": "已学会并装备 %s。" % SkillDB.name_of(skill_id)}
	return {"ok": true, "message": "已学会 %s；装备位已满，可在整备页换装。" % SkillDB.name_of(skill_id)}


static func add_xp(run: RunState, uid: int, amount: int) -> Dictionary:
	if run == null or amount <= 0:
		return {"ok": false, "message": "经验增量必须大于 0。"}
	var record := run.owned_record_by_uid(uid)
	if record.is_empty():
		return {"ok": false, "message": "未找到目标怪物。"}
	var growth := MonsterProgression.award_xp(record, amount, run.level_cap_for_floor())
	run.debug_tainted = true
	return {"ok": true, "message": "%s：+%d XP，现为 Lv.%d（%d XP）；2、5、7级学习机会在战后结算领取。" % [
		SpeciesDB.name_of(String(record["species_id"])), int(growth["gained"]), int(growth["level_after"]), int(growth["xp_after"]),
	]}


static func set_damage_bonus(battle: BattleState, side: String, bonus: int) -> Dictionary:
	if battle == null or battle.ended or battle.phase != BattleState.PHASE_PLAYER or not ["player", "enemy"].has(side):
		return {"ok": false, "message": "只能在我方行动阶段调整伤害。"}
	battle.debug_skill_damage_bonus[side] = clampi(bonus, -20, 20)
	battle._forecast_signature = ""
	return {"ok": true, "message": "%s技能直伤调整为 %+d；仅本场有效。" % ["我方" if side == "player" else "敌方", int(battle.debug_skill_damage_bonus[side])]}


static func set_capture_percent(battle: BattleState, percent: int) -> Dictionary:
	if battle == null or battle.ended or battle.phase != BattleState.PHASE_PLAYER or percent < -1 or percent > 100:
		return {"ok": false, "message": "仅我方阶段可设置 0–100%，或 -1 恢复正常。"}
	battle.debug_capture_percent = percent
	return {"ok": true, "message": "捕获率：%s；仅本场有效。" % ("正常规则" if percent < 0 else "%d%%" % percent)}


static func heal_players(battle: BattleState) -> Dictionary:
	if battle == null or battle.ended or battle.phase != BattleState.PHASE_PLAYER:
		return {"ok": false, "message": "只能在我方行动阶段回复。"}
	var count := 0
	for unit in battle.alive_units("player"):
		unit.hp = unit.max_hp
		count += 1
	battle.log_event("调试：%d 名存活己方单位生命回满。" % count)
	return {"ok": true, "message": "已回复 %d 名存活己方单位。濒死单位不会复活。" % count}


static func soften_enemies(battle: BattleState) -> Dictionary:
	if battle == null or battle.ended or battle.phase != BattleState.PHASE_PLAYER:
		return {"ok": false, "message": "只能在我方行动阶段调整敌人生命。"}
	var count := 0
	for unit in battle.alive_units("enemy"):
		unit.hp = 1
		count += 1
	battle._forecast_signature = ""
	battle.log_event("调试：%d 名敌人生命降至 1，未计入击杀。" % count)
	return {"ok": true, "message": "已将 %d 名存活敌人设为 1 HP，可测试捕获。" % count}


static func win_battle(battle: BattleState) -> Dictionary:
	if battle == null or battle.ended or battle.phase != BattleState.PHASE_PLAYER:
		return {"ok": false, "message": "只能在我方行动阶段直接获胜。"}
	battle.commit_actions()
	battle.log_event("调试：直接结束本场战斗。")
	battle.end_battle("victory")
	return {"ok": true, "message": "已直接获胜；未击杀的敌人不计入击杀经验。"}
