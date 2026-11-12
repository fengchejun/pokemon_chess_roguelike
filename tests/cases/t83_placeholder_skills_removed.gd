extends RefCounted

func run(t: TestContext) -> void:
	t.begin("占位试招删除与旧存档清理")
	_definitions_removed(t)
	_run_migration(t)
	_snapshot_cleanup(t)
	_collection_stats_filtered(t)
	t.finish()


func _definitions_removed(t: TestContext) -> void:
	t.check(SkillDB.get_def("trial_fire_1").is_empty(), "占位试招定义已删除")
	for element in Elements.LIST:
		t.check(not SkillDB.learnable_ids_for(element).any(func(id): return String(id).begins_with("trial_")), "%s学习池不含占位试招" % element)
	var run := RunState.new_run(8301)
	t.check(not run.available_new_skills(1).any(func(id): return String(id).begins_with("trial_")), "成长候选不含占位试招")


func _run_migration(t: TestContext) -> void:
	var data := RunState.new_run(8302).to_dict()
	var record: Dictionary = data["carried"][0]
	record["known_skills"] = ["trial_fire_1", "fire_burst", "flame_jet"]
	record["equipped_skills"] = ["trial_fire_1", "fire_burst"]
	record["upgrades_taken"] = ["trial_fire_1_range", "fireball_damage"]
	record["upgrades"] = {"trial_fire_1_range": 1, "fireball_damage": 1}
	record["level_choices"] = {"2": ["trial_fire_1", "fire_burst", "flame_jet"]}
	var loaded := RunState.from_dict(data)
	var migrated := loaded.record_by_uid(1)
	t.check(not (migrated["known_skills"] as Array).has("trial_fire_1"), "旧本局已学试招被清理")
	t.check(not (migrated["equipped_skills"] as Array).has("trial_fire_1"), "旧本局装备试招被清理")
	t.check(not (migrated["upgrades_taken"] as Array).has("trial_fire_1_range"), "旧试招强化被清理")
	t.check(not (migrated["upgrades"] as Dictionary).has("trial_fire_1_range"), "旧试招强化值被清理")
	t.check(migrated["level_choices"].is_empty(), "包含试招的旧升级候选被丢弃")


func _snapshot_cleanup(t: TestContext) -> void:
	var state := TestScenario.make_state(["fire_starter"], [])
	var unit := state.unit_by_uid(1)
	unit.skills = ["trial_fire_1"]
	unit.upgrades["trial_fire_1_range"] = 1
	unit.last_skill_id = "trial_fire_1"
	state.pending_casts.append({"uid": unit.uid, "side": "player", "skill_id": "trial_fire_1", "cells": [Vector2i(2, 3)], "due_round": 2})
	state.skill_use_counts["player"]["trial_fire_1"] = 1
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(state))
	var restored_unit := restored.unit_by_uid(unit.uid)
	t.check(not restored_unit.skills.has("trial_fire_1"), "旧战斗快照不再装备试招")
	t.eq(restored_unit.skills, SpeciesDB.skills_of("fire_starter").slice(0, 1), "旧单位清空后回退到正式基础技能")
	t.check(not restored_unit.upgrades.has("trial_fire_1_range"), "旧快照试招强化被清理")
	t.eq(restored_unit.last_skill_id, "", "旧快照最后施法记录被清理")
	t.check(restored.pending_casts.is_empty(), "旧试招吟唱被取消")
	t.check(not (restored.skill_use_counts["player"] as Dictionary).has("trial_fire_1"), "旧战斗技能统计被清理")


func _collection_stats_filtered(t: TestContext) -> void:
	var battle := TestScenario.make_state(["fire_starter"], [])
	battle.ended = true
	battle.skill_use_counts["player"]["trial_fire_1"] = 3
	battle.skill_use_counts["player"]["fire_burst"] = 2
	var profile := CollectionState.defaults()
	t.check(profile.record_battle_skill_usage(battle), "战斗统计可写入收藏")
	t.check(not (profile.skill_use_counts["player"] as Dictionary).has("trial_fire_1"), "跨局统计不保留已删除试招")
	t.eq(int((profile.skill_use_counts["player"] as Dictionary).get("fire_burst", 0)), 2, "正式技能统计保持有效")
