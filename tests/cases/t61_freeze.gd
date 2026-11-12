extends RefCounted


func run(t: TestContext) -> void:
	t.begin("冰冻：一回合无法行动且受伤正常结算")
	_blocks_all_actions(t)
	_freeze_ray_damage_and_freeze(t)
	_freeze_ray_upgrade_and_repeat(t)
	_freeze_upgrade_migration(t)
	_damage_breaks_without_immunity(t)
	_skill_damage_breaks_without_immunity(t)
	_ui_explains_release_timing(t)
	_ui_skill_damage_breaks_without_immunity(t)
	_expires_after_one_round(t)
	t.finish()


func _blocks_all_actions(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(6, 6)]])
	var unit := state.unit_by_uid(1)
	t.check(state.apply_freeze(unit), "可对存活单位施加冰冻")
	t.check(unit.frozen, "目标进入冰冻状态")
	t.eq(unit.frozen_ticks, Balance.FREEZE_TICKS, "冰冻初始为一回合")
	t.check(not state.can_move_unit_now(unit), "冰冻单位不能移动")
	t.check(not unit.can_act_skill(), "冰冻单位不能施法")
	t.eq(unit.effective_move(), 0, "冰冻单位移动力显示为零")


func _freeze_ray_damage_and_freeze(t: TestContext) -> void:
	var state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	target.element = ""
	var hp_before := target.hp
	var result := state.cast_skill(caster, "freeze_ray", {"type": "cell", "cell": target.cell})
	t.check(bool(result.get("ok", false)), "急冻光线可命中首个敌人")
	t.eq(target.hp, hp_before - 6, "急冻光线造成六点基础直伤")
	t.check(target.frozen, "急冻光线的自身伤害结算后仍施加冰冻")
	t.check(result.get("text", "").contains("6 伤害") and result.get("text", "").contains("附加冰冻"), "结算文本同时说明伤害与冰冻")


func _freeze_ray_upgrade_and_repeat(t: TestContext) -> void:
	var state := TestScenario.make_state(["ice_starter"], [["rock_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(0, 3)
	caster.upgrades["freeze_ray_damage"] = 4
	target.element = ""
	target.hp = 100
	target.max_hp = 100
	var entry := {"type": "cell", "cell": target.cell}
	SkillResolver.apply(state, caster, "freeze_ray", entry, false)
	t.eq(target.hp, 90, "急冻强化后造成十点伤害")
	t.check(target.frozen, "强化急冻首次命中仍附加冰冻")
	var first_ticks := target.frozen_ticks
	SkillResolver.apply(state, caster, "freeze_ray", entry, false)
	t.eq(target.hp, 80, "再次命中已冰冻目标仍造成十点伤害")
	t.check(not target.frozen and target.frozen_ticks == 0, "急冻伤害使已有冰冻解除且不叠加")
	t.eq(first_ticks, Balance.FREEZE_TICKS, "同一目标只维持一层冰冻")


func _freeze_upgrade_migration(t: TestContext) -> void:
	var run := RunState.new_run(6102)
	var record := run.record_by_uid(2)
	record["known_skills"].append("freeze_ray")
	record["upgrades_taken"] = ["freeze_ray_range"]
	record["upgrades"] = {"freeze_ray_range": 1}
	var restored := RunState.from_dict(run.to_dict())
	var migrated := restored.record_by_uid(2)
	t.eq(int(migrated.get("upgrades", {}).get("freeze_ray_damage", 0)), 4, "旧急冻强化迁移为增伤四点")
	t.check(not (migrated.get("upgrades", {}) as Dictionary).has("freeze_ray_range"), "旧射程强化键不再生效")


func _damage_breaks_without_immunity(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var attacker := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	state.apply_freeze(target)
	var hp_before := target.hp
	var result := state.damage_unit(attacker, target, 10, {"skill_direct": true, "element": "rock", "cause": "测试伤害"})
	t.eq(int(result.get("amount", -1)), 10, "冰冻不再免疫伤害")
	t.eq(target.hp, hp_before - 10, "伤害正常扣除生命")
	t.check(not target.frozen, "受到实际伤害后解除冰冻")
	t.eq(target.frozen_ticks, 0, "解冻后清空持续回合")
	t.eq(target.paralyzed_ticks, 0, "解冻不再额外施加麻痹")
	var guarded := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var guarded_target := guarded.unit_by_uid(100)
	guarded.apply_freeze(guarded_target)
	guarded_target.battle_buffs["direct_guard"] = true
	var zero := guarded.damage_unit(guarded.unit_by_uid(1), guarded_target, 1, {"skill_direct": true, "element": "rock", "cause": "被抵消的伤害"})
	t.eq(int(zero.get("amount", -1)), 0, "减伤可以把伤害降为零")
	t.check(guarded_target.frozen, "没有实际伤害时不会解除冰冻")


func _skill_damage_breaks_without_immunity(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	caster.skills = ["ice_shard"]
	target.element = ""
	state.apply_freeze(target)
	var hp_before := target.hp
	var result := state.cast_skill(caster, "ice_shard", {"type": "unit", "unit": target.uid, "cell": target.cell})
	t.check(bool(result.get("ok", false)), "冰冻目标可被正式技能选中")
	t.eq(target.hp, hp_before - SkillDB.damage_of("ice_shard"), "冰冻目标受到正式技能伤害")
	t.check(not target.frozen, "正式技能命中后冰冻解除")


func _ui_explains_release_timing(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(6103)
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var target := state.unit_by_uid(100)
	state.apply_freeze(target)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.viewed_enemy_uid = target.uid
	screen._update_unit_card()
	t.check(screen.unit_body.text.contains("下次行动后解除"), "冰冻状态说明写明下次行动后解除")
	t.check(screen.unit_body.text.contains("受到实际伤害会提前解除"), "冰冻状态说明保留受伤提前解除条件")
	t.check(String(SkillDB.get_def("freeze_ray").get("desc", "")).contains("下次行动后解除"), "急冻光线说明采用统一下次行动后解除")
	t.check(String(SkillDB.get_def("ice_breath").get("desc", "")).contains("下次行动后解除"), "冰之息说明采用统一下次行动后解除")
	app.free()


func _ui_skill_damage_breaks_without_immunity(t: TestContext) -> void:
	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(6101)
	var state := TestScenario.make_state(["rock_starter"], [["rock_wild1", Vector2i(3, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(2, 3)
	caster.skills = ["ice_shard"]
	target.element = ""
	state.apply_freeze(target)
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	app._switch(screen)
	screen.select_unit(caster.uid)
	screen.action_mode = "skills"
	screen._on_skill_pressed("ice_shard")
	var hp_before := target.hp
	screen._try_cast_at(target.cell)
	t.eq(target.hp, hp_before - SkillDB.damage_of("ice_shard"), "界面点击冰冻目标后实际扣血")
	screen.playback.finish_all()
	t.eq(screen.playback.visual.unit_by_uid(target.uid).hp, target.hp, "播放结束的冰冻受击生命与真实状态一致")
	app.free()


func _expires_after_one_round(t: TestContext) -> void:
	var state := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(7, 6)]])
	var unit := state.unit_by_uid(1)
	state.apply_freeze(unit)
	state._settle_round_rules()
	t.check(not unit.frozen, "一回合结束后解除冰冻")
	t.eq(unit.frozen_ticks, 0, "冰冻持续时间耗尽")
	t.check(unit.can_act_skill() and state.can_move_unit_now(unit), "冰冻结束后恢复正常行动")
	var legacy := TestScenario.make_state(["rock_starter"], [["water_wild1", Vector2i(7, 6)]])
	var legacy_unit := legacy.unit_by_uid(1)
	legacy_unit.frozen = true
	legacy_unit.frozen_ticks = 0
	var restored := BattleSnapshot.load_state(BattleSnapshot.save_state(legacy))
	t.check(restored.unit_by_uid(1).frozen, "旧冰冻状态读档后仍保留")
	t.eq(restored.unit_by_uid(1).frozen_ticks, Balance.FREEZE_TICKS, "旧冰冻状态迁移为一回合")
