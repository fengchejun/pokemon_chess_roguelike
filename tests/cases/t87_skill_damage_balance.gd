extends RefCounted


func run(t: TestContext) -> void:
	t.begin("技能伤害平衡与低层击杀阈值")
	var expected := {
		"water_flow": 9,
		"rock_push": 11,
		"push": 11,
		"discharge": 11,
		"fire_burst": 15,
		"rock_slide": 20,
		"earth_shake": 13,
		"lightning": 13,
		"tsunami": 15,
		"windfire_breath": 10,
	}
	for skill_id in expected:
		t.eq(SkillDB.damage_of(String(skill_id)), int(expected[skill_id]), "%s 使用新平衡数值" % skill_id)
	t.eq(int(SkillDB.get_def("fire_burst").get("splash_damage", 0)), 8, "火球外围伤害与中心分离")
	t.eq(Balance.PUSH_DAMAGE, 11, "推击兼容常量同步")

	for skill_id in ["water_flow", "rock_push", "discharge", "ice_shard"]:
		var damage := SkillDB.damage_of(String(skill_id))
		t.check(damage >= 9 and damage <= 13, "%s 单体基础伤害处于 9–13 档" % skill_id)
	for skill_id in ["ice_breath", "electric_spark", "windfire_breath", "skyfire"]:
		var damage := SkillDB.damage_of(String(skill_id))
		t.check(damage >= 8 and damage <= 10, "%s 多目标单次伤害处于 8–10 档" % skill_id)

	var state := TestScenario.make_state(["fire_starter"], [["grass_wild1", Vector2i(4, 3)]])
	var caster := state.unit_by_uid(1)
	t.eq(SkillResolver.fireball_base_damage(caster, true), 15, "未强化火球中心伤害")
	t.eq(SkillResolver.fireball_base_damage(caster, false), 8, "未强化火球外围伤害")
	caster.upgrades["fireball_damage"] = 5
	t.eq(SkillResolver.fireball_base_damage(caster, true), 20, "火球强化只提高中心伤害")
	t.eq(SkillResolver.fireball_base_damage(caster, false), 8, "火球强化不提高外围伤害")
	t.check(
		Elements.direct_damage(SkillDB.damage_of("fire_burst"), "fire", "grass") < 20,
		"火球克制 20 HP 低层目标时不会未强化直接击倒"
	)
	t.finish()
