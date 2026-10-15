extends RefCounted


func run(t: TestContext) -> void:
	t.begin("元素附着、反应与阶段时点")
	_test_skill_reactions(t)
	_test_statuses_and_duration(t)
	_test_overload_and_guard(t)
	_test_terrain_and_wind(t)
	_test_self_target_and_immunity(t)
	_test_enemy_self_attachment(t)
	t.finish()


func _duel() -> BattleState:
	var state := TestScenario.make_state(["fire_starter"], [
		["rock_wild1", Vector2i(4, 3)], ["water_wild1", Vector2i(6, 6)],
	])
	state.trainer().cell = Vector2i(0, 0)
	state.unit_by_uid(1).cell = Vector2i(2, 3)
	var target := state.unit_by_uid(100)
	target.hp = 20
	target.max_hp = 20
	return state


func _test_skill_reactions(t: TestContext) -> void:
	var state := _duel()
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.skills.append("trial_water_1")
	state.add_attachment(target, "fire")
	var preview := state.preview_skill(caster, "trial_water_1", {"type": "unit", "unit": 100, "cell": target.cell})
	t.eq(int(preview["hits"][0]["damage"]), 3, "预览：火附着遇水命中，本次水伤 +2")
	t.eq(target.hp, 20, "预览不改变真实生命")
	var result := state.cast_skill(caster, "trial_water_1", {"type": "unit", "unit": 100, "cell": target.cell})
	t.eq(int(result["hits"][0]["damage"]), 3, "实际：蒸发给本次水伤 +2")
	t.eq(ElementAttachmentResolver.stack_count(target, "fire"), 0, "蒸发消耗火附着")
	t.eq(ElementAttachmentResolver.stack_count(target, "water"), 0, "蒸发消耗水附着")
	t.eq(ElementAttachmentResolver.stack_count(caster, "water"), 1, "成功施法给施法者一层技能属性附着")
	var reverse := _duel()
	var reverse_caster := reverse.unit_by_uid(1)
	var reverse_target := reverse.unit_by_uid(100)
	reverse_caster.skills.append("trial_fire_1")
	reverse.add_attachment(reverse_target, "water")
	var reverse_result := reverse.cast_skill(reverse_caster, "trial_fire_1", {"type": "unit", "unit": 100, "cell": reverse_target.cell})
	t.eq(int(reverse_result["hits"][0]["damage"]), 1, "水附着遇火命中仍蒸发，但火伤不加")
	for pair in [["water", "grass", "grass"], ["water", "electric", "electric"], ["fire", "grass", "fire"], ["fire", "ice", "fire"]]:
		var reaction_state := _duel()
		var monster := reaction_state.unit_by_uid(100)
		reaction_state.add_attachment(monster, String(pair[0]))
		var aura := reaction_state.add_attachment(monster, String(pair[1]), reaction_state.unit_by_uid(1), true)
		t.eq(int(aura["bonus"]), 2 if pair[1] == pair[2] else 0, "%s + %s 对应属性伤害条件" % [pair[0], pair[1]])
		t.eq(ElementAttachmentResolver.stack_count(monster, String(pair[0])) + ElementAttachmentResolver.stack_count(monster, String(pair[1])), 0, "反应清除一对附着")


func _test_statuses_and_duration(t: TestContext) -> void:
	var state := _duel()
	var target := state.unit_by_uid(100)
	state.add_attachment(target, "grass")
	t.eq(target.parasite_until_round, 0, "单层草暂不寄生")
	var second := state.add_attachment(target, "grass")
	state.resolve_attachment_effect(target, second)
	t.check(target.parasite_until_round > state.round, "两层草触发寄生")
	var caster := state.unit_by_uid(1)
	caster.hp = 2
	state.damage_unit(caster, target, 2, {"element": "fire", "skill_hit": true})
	t.eq(caster.hp, 4, "攻击寄生目标按实际技能伤害回复")
	state.add_attachment(target, "ice")
	second = state.add_attachment(target, "ice")
	state.resolve_attachment_effect(target, second)
	t.check(target.frozen, "两层冰造成持续冻结")
	state.damage_unit(caster, target, 1, {"element": "fire", "skill_hit": true})
	t.check(not target.frozen, "受攻击解除冻结且本次不造成伤害")
	var thaw_state := _duel()
	var thaw_caster := thaw_state.unit_by_uid(1)
	var thaw_target := thaw_state.unit_by_uid(100)
	thaw_caster.skills.append("trial_ice_1")
	thaw_target.frozen = true
	thaw_state.add_attachment(thaw_target, "ice")
	var thaw_hit := thaw_state.cast_skill(thaw_caster, "trial_ice_1", {"type": "unit", "unit": 100, "cell": thaw_target.cell})
	t.check(bool(thaw_hit.get("ok", false)), "冰系技能可命中已冻结目标")
	t.eq(int(thaw_hit["hits"][0]["damage"]), 0, "已冻结目标受击先解冻，本次不受直伤")
	t.check(not thaw_target.frozen, "同一次冰反应不会立即重新冻结目标")
	var electric_state := _duel()
	var shocked := electric_state.unit_by_uid(100)
	electric_state.add_attachment(shocked, "electric")
	second = electric_state.add_attachment(shocked, "electric")
	electric_state.resolve_attachment_effect(shocked, second)
	t.check(shocked.paralyzed_ticks > 0, "两层电造成麻痹")
	t.eq(shocked.paralyzed_ticks, 1, "我方阶段麻痹敌人只跳过本轮敌方一次行动")
	var immune := electric_state.unit_by_uid(101)
	immune.element = "electric"
	electric_state.add_attachment(immune, "electric")
	second = electric_state.add_attachment(immune, "electric")
	electric_state.resolve_attachment_effect(immune, second)
	t.eq(immune.paralyzed_ticks, 0, "电系免疫麻痹")
	var expiry := _duel()
	var expiring := expiry.unit_by_uid(100)
	expiry.add_attachment(expiring, "grass")
	ElementAttachmentResolver.clear_expired(expiring, expiry.round + 1)
	t.eq(ElementAttachmentResolver.stack_count(expiring, "grass"), 1, "单层附着经过一整轮仍保留")
	ElementAttachmentResolver.clear_expired(expiring, expiry.round + 2)
	t.eq(ElementAttachmentResolver.stack_count(expiring, "grass"), 0, "单层附着经过两整轮到期")


func _test_overload_and_guard(t: TestContext) -> void:
	var state := _duel()
	var target := state.unit_by_uid(100)
	var ally := state.unit_by_uid(1)
	ally.cell = Vector2i(4, 4)
	var ally_hp := ally.hp
	state.add_attachment(target, "fire")
	var aura := state.add_attachment(target, "electric", ally, true)
	state.resolve_attachment_effect(target, aura, ally)
	t.eq(ally.hp, ally_hp - 1, "过载十字爆炸误伤友军")
	t.eq(target.hp, 19, "过载中心 1 点无属性伤害")
	t.eq(ElementAttachmentResolver.stack_count(target, "electric"), 0, "过载爆炸不再次附着或连锁")
	var guard := _duel()
	var defended := guard.unit_by_uid(100)
	guard.add_attachment(defended, "rock")
	aura = guard.add_attachment(defended, "rock")
	guard.resolve_attachment_effect(defended, aura)
	var hp := defended.hp
	guard.damage_unit(guard.unit_by_uid(1), defended, 2, {"element": "fire", "skill_hit": true})
	t.eq(defended.hp, hp - 1, "两层岩只减免技能直伤 1 点")
	guard.damage_unit(null, defended, 1, {"no_element": true, "cause": "环境"})
	t.eq(defended.hp, hp - 2, "岩护不减免环境伤害")


func _test_terrain_and_wind(t: TestContext) -> void:
	var tiles := TestScenario.with_cells(TestScenario.plain_terrain(), [[Vector2i(4, 3), TerrainDB.WATER]])
	var state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(4, 3)]], tiles)
	var target := state.unit_by_uid(100)
	state.begin_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(target, "water"), 1, "我方阶段结束给水格单位水附着")
	t.eq(target.slow_ticks, 0, "水附着尚未在单方阶段结束转浸湿")
	state.end_enemy_phase()
	t.check(target.slow_ticks > 0, "双方阶段结束水附着才转为浸湿")
	var spread := TestScenario.make_state(["wind_starter", "fire_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var wind := spread.unit_by_uid(1)
	wind.cell = Vector2i(1, 3)
	var friend := spread.unit_by_uid(2)
	friend.cell = Vector2i(2, 3)
	var enemy := spread.unit_by_uid(100)
	spread.add_attachment(wind, "grass")
	spread.add_attachment(wind, "rock")
	spread.add_attachment(friend, "ice")
	SkillResolver.apply(spread, wind, "tailwind", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(2, 3)}, false)
	t.eq(wind.attachments.size(), 0, "风扩散后源单位不保留附着，也不获得风附着")
	t.eq(ElementAttachmentResolver.stack_count(friend, "grass"), 1, "风技能范围内友军复制施法者附着")
	t.eq(ElementAttachmentResolver.stack_count(enemy, "rock"), 1, "风技能范围内敌军也复制附着")
	t.eq(ElementAttachmentResolver.stack_count(friend, "ice"), 0, "扩散将目标原附着替换为源状态")


func _test_self_target_and_immunity(t: TestContext) -> void:
	var rain := TestScenario.make_state(["water_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var water := rain.unit_by_uid(1)
	water.cell = Vector2i(2, 3)
	SkillResolver.apply(rain, water, "rain_call", {"type": "cell", "cell": water.cell}, false)
	t.eq(ElementAttachmentResolver.stack_count(water, "water"), 1, "造雨覆盖自己仍只获得一层施法者水附着")
	var heal := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var grass := heal.unit_by_uid(1)
	SkillResolver.apply(heal, grass, "herbal_heal", {"type": "cell", "cell": grass.cell}, false)
	t.eq(ElementAttachmentResolver.stack_count(grass, "grass"), 1, "治疗包括自己时只获得一层草附着")
	var fire := _duel()
	var fire_target := fire.unit_by_uid(100)
	fire_target.element = "fire"
	fire.add_attachment(fire_target, "fire")
	fire._settle_attachments()
	t.eq(fire_target.burn_ticks, 0, "火系免疫火附着转成的灼烧")
	var ice := _duel()
	var ice_target := ice.unit_by_uid(100)
	ice_target.element = "ice"
	ice.add_attachment(ice_target, "ice")
	var second := ice.add_attachment(ice_target, "ice")
	ice.resolve_attachment_effect(ice_target, second)
	t.check(not ice_target.frozen, "冰系免疫两层冰造成的冻结")


func _test_enemy_self_attachment(t: TestContext) -> void:
	var fire_state := TestScenario.make_state(["water_starter"], [
		["fire_wild1", Vector2i(4, 3)], ["rock_wild1", Vector2i(6, 6)],
	])
	var fire_enemy := fire_state.unit_by_uid(100)
	var water_ally := fire_state.unit_by_uid(1)
	water_ally.cell = Vector2i(2, 3)
	fire_state.begin_enemy_phase()
	fire_state._pending_actions = [{
		"uid": fire_enemy.uid, "move_path": [],
		"skill": {"id": "flame_jet", "target": {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(5, 3)}},
	}]
	fire_state._pending_index = 0
	fire_state.step_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(fire_enemy, "fire"), 1, "敌方实际施放火技能后自身立即获得火附着")
	fire_state.end_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(fire_enemy, "fire"), 1, "敌方阶段获得的火附着保留到我方下次行动")
	t.eq(fire_enemy.burn_ticks, 0, "敌方施法后不会在同一整轮立刻转成灼烧")
	var water_hit := fire_state.cast_skill(water_ally, "water_flow", {"type": "cell", "cell": fire_enemy.cell})
	t.check(bool(water_hit.get("ok", false)), "我方可在下一阶段用水技能反制敌方自身火附着")
	t.eq(int(water_hit["hits"][0]["damage"]), 3, "敌方施法暴露的火弱点触发水伤 +2")
	var water_state := TestScenario.make_state(["fire_starter"], [
		["water_wild1", Vector2i(4, 3)], ["rock_wild1", Vector2i(6, 6)],
	])
	var water_enemy := water_state.unit_by_uid(100)
	var water_target := water_state.unit_by_uid(1)
	water_target.cell = Vector2i(2, 3)
	water_state.begin_enemy_phase()
	water_state._pending_actions = [{
		"uid": water_enemy.uid, "move_path": [],
		"skill": {"id": "water_flow", "target": {"type": "cell", "cell": water_target.cell}},
	}]
	water_state._pending_index = 0
	water_state.step_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(water_enemy, "water"), 1, "敌方实际施放水技能后自身立即获得水附着")
	water_state.end_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(water_enemy, "water"), 1, "敌方阶段获得的水附着保留到我方下次行动")
	t.eq(ElementAttachmentResolver.stack_count(water_target, "water"), 0, "敌方技能命中目标的水附着仍在本轮末转化")
	t.eq(water_target.slow_ticks, 1, "命中目标下一次行动照常受到浸湿减速")
	water_state.begin_enemy_phase()
	water_state._pending_actions = []
	water_state._pending_index = 0
	water_state.end_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(water_enemy, "water"), 0, "敌方水附着在下一次整轮末转化")
	var electric_state := TestScenario.make_state(["fire_starter"], [
		["electric_wild1", Vector2i(4, 3)], ["rock_wild1", Vector2i(6, 6)],
	])
	var electric_enemy := electric_state.unit_by_uid(100)
	electric_state.begin_enemy_phase()
	electric_state._pending_actions = [{
		"uid": electric_enemy.uid, "move_path": [],
		"skill": {"id": "lightning", "target": {"type": "multi", "cells": [Vector2i(4, 2), Vector2i(4, 1), Vector2i(3, 1)]}},
	}]
	electric_state._pending_index = 0
	electric_state.step_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(electric_enemy, "electric"), 1, "敌方宣告闪电时自身获得电附着")
	electric_state.end_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(electric_enemy, "electric"), 1, "电附着在我方下一阶段仍可见")
	var player_state := TestScenario.make_state(["fire_starter"], [["rock_wild1", Vector2i(6, 6)]])
	var player_fire := player_state.unit_by_uid(1)
	player_fire.cell = Vector2i(2, 3)
	var player_cast := player_state.cast_skill(player_fire, "flame_jet", {"type": "dir", "dir": Vector2i.RIGHT, "cell": Vector2i(3, 3)})
	t.check(bool(player_cast.get("ok", false)), "我方火技能施放成功")
	t.eq(ElementAttachmentResolver.stack_count(player_fire, "fire"), 1, "我方施法后也立即获得自身火附着")
	player_state.begin_enemy_phase()
	player_state._pending_actions = []
	player_state._pending_index = 0
	player_state.end_enemy_phase()
	t.eq(ElementAttachmentResolver.stack_count(player_fire, "fire"), 0, "我方阶段获得的火附着仍在本轮末转化")
