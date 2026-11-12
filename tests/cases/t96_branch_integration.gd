extends RefCounted

const Flow = preload("res://scripts/run/exploration_flow.gd")
const Loot = preload("res://scripts/run/battle_loot.gd")

func run(t: TestContext) -> void:
	t.begin("分支整合：可选领奖、遗物后续、旧档与完整伤害")
	var run := RunState.new_run(96113)
	var saved := run.to_dict()
	Loot.preview(run, "high", "read-only")
	t.eq(run.to_dict(), saved, "预览奖励不会提前触发遗物或改变存档")
	t.eq(Balance.skill_damage_for_side(15, "enemy"), 15, "敌方采用同伴分支的完整伤害倍率")
	t.eq(SkillDB.damage_of("rock_slide"), 20, "落石基础伤害采用同伴数值")
	t.eq(SkillDB.damage_of("earth_shake"), 13, "地震基础伤害采用同伴数值")

	var old := run.to_dict()
	old["version"] = 19
	old["relic_stacks"] = {"fire_mark": 3}
	old["pending_reward_choices"] = 2
	old["legendary_offers"] = [["old_legendary"]]
	old["pending_battle_loot"] = [{"kind": "relic", "id": "fire_mark", "status": "pending", "label": "旧遗物"}]
	var restored := RunState.from_dict(old)
	t.check(not restored.relic_stacks.has("fire_mark"), "已移除的旧遗物不进入新池")
	t.eq(restored.pending_reward_choices, 2, "尚未领取的遗物次数保留")
	t.check(not restored.reward_choices().is_empty() and restored.reward_choices().all(func(id): return RelicDB.DEFINITIONS.has(id)), "旧传奇候选迁移到新池")
	t.check(RelicDB.DEFINITIONS.has(restored.pending_battle_loot[0].get("id", "")), "旧固定遗物战利品迁移到新池")

	var legendary: String = Loot.available_relics(run, "legendary")[0]
	run.relic_stacks[legendary] = 1
	run.legendary_offers = [[legendary]]
	run.pending_reward_choices = 2
	var money := run.essence
	t.eq(run.discard_unavailable_reward_choices(), 1, "耗尽的特定候选只处理自身")
	t.eq(run.pending_reward_choices, 1, "其后的普通遗物选择不被吞掉")
	t.eq(run.essence, money + 16, "耗尽传奇候选折算原质")

	var app = load("res://scripts/main.gd").new()
	app.autosave_enabled = false
	t.tree.root.add_child(app)
	app.run = RunState.new_run(96114)
	app.run.region_mode = true
	app.run.region_data = Flow.create(0, "fire").to_dict()
	var visits: int = app.run.get_region().visits
	t.check(app.run.acquire_relic("mage_notes", "garrison"), "驻守可获得需要后续选择的遗物")
	app.show_region()
	t.eq(app.current_screen.name, "SettlementScreen", "地图先处理遗物后续选择")
	t.eq(app.run.last_settlement.get("return_to"), "region", "后续界面记住返回位置")
	var eligible: Array = app.run.mage_note_eligible_uids().slice(0, 3)
	t.check(app.run.resolve_mage_notes(eligible).get("ok", false), "后续选择能正常完成")
	app.current_screen._show_next_step()
	app.continue_after_settlement()
	t.eq(app.current_screen.name, "RegionScreen", "完成后返回地图")
	t.eq(app.run.get_region().visits, visits, "遗物后续选择不额外消耗探索行动")
	app.run.acquire_relic("magic_end", "garrison")
	app.show_run_end()
	t.eq(app.current_screen.name, "SettlementScreen", "本局结束也先处理驻守遗物后续")
	t.check(app.run.resolve_magic_end(1, "ultra_death_ray").get("ok", false), "最终遗物可选定成员并学习技能")
	app.run.record_by_uid(1)["equipped_skills"] = ["ultra_death_ray"]
	var magic_loaded := RunState.from_dict(app.run.to_dict())
	t.check(magic_loaded.record_by_uid(1)["known_skills"].has("ultra_death_ray"), "遗物无属性魔法续档后仍在招式库")
	t.check(magic_loaded.record_by_uid(1)["equipped_skills"].has("ultra_death_ray"), "遗物无属性魔法续档后仍可使用")
	app.continue_after_settlement()
	t.eq(app.current_screen.name, "RunEndScreen", "选择完成后回到仓库保留结局")
	app.free()
	t.finish()
