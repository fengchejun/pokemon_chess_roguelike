extends RefCounted

static func show_choice(run: RunState, box: VBoxContainer, heading: Label, entry: Dictionary, remaining: int, on_claim: Callable) -> void:
	UIKit.clear_children(box)
	var uid := int(entry["uid"])
	var level := int(entry["level"])
	var record := run.owned_record_by_uid(uid)
	var monster_name := SpeciesDB.name_of(String(record.get("species_id", "")))
	heading.text = "%s · Lv.%d 升级选择（剩余 %d 项）" % [monster_name, level, remaining]
	if level == MonsterProgression.MAX_LEVEL:
		box.add_child(UIKit.wrapped("Lv10 特性强化入口。当前版本暂不增加生命值以外的实际效果，领取后记录本次特性强化。", 13))
		var trait_button := UIKit.button("领取特性强化入口", 16)
		trait_button.name = "MonsterTrait_%d_10" % uid
		trait_button.pressed.connect(func() -> void:
			if run.claim_monster_trait_upgrade(uid, level):
				on_claim.call())
		box.add_child(trait_button)
		return
	var slots := run.monster_engraving_slots(record)
	box.add_child(UIKit.wrapped("已自动获得刻印槽，当前共 %d 个。请从以下三招中选择一招学习；选择后进入招式库，装备位仍为 3 个。" % slots, 13))
	var candidates := run.monster_level_choices(uid, level)
	if candidates.is_empty():
		var skip := UIKit.small_button("没有可学习技能，领取本等级")
		skip.name = "MonsterLearnSkip_%d_%d" % [uid, level]
		skip.pressed.connect(func() -> void:
			if run.skip_monster_skill_choice(uid, level):
				on_claim.call())
		box.add_child(skip)
		return
	for candidate in candidates:
		var skill_id := String(candidate)
		var button := UIKit.button("%s\n%s" % [SkillDB.name_of(skill_id), SkillDB.get_def(skill_id).get("desc", "")], 14)
		button.name = "MonsterLearn_%d_%d_%s" % [uid, level, skill_id]
		button.pressed.connect(func() -> void:
			if run.owned_record_by_uid(uid).get("equipped_skills", []).size() >= RunState.MAX_EQUIPPED_SKILLS:
				_show_replacements(run, box, heading, entry, remaining, skill_id, on_claim)
			elif run.learn_monster_skill(uid, level, skill_id):
				on_claim.call())
		_fit_button(button)
		box.add_child(button)


static func _show_replacements(run: RunState, box: VBoxContainer, heading: Label, entry: Dictionary, remaining: int, new_skill: String, on_claim: Callable) -> void:
	UIKit.clear_children(box)
	var uid := int(entry["uid"])
	var level := int(entry["level"])
	heading.text = "三招已满：选择卸下的一招"
	box.add_child(UIKit.wrapped("卸下的招式留在本局招式库，已取得的强化也会保留；下场战斗前可在整备页换回。", 13))
	var back := UIKit.small_button("返回学招选择")
	back.pressed.connect(show_choice.bind(run, box, heading, entry, remaining, on_claim))
	box.add_child(back)
	for equipped_id in run.owned_record_by_uid(uid).get("equipped_skills", []):
		var old_skill := String(equipped_id)
		var button := UIKit.button("卸下 %s → 装备 %s" % [SkillDB.name_of(old_skill), SkillDB.name_of(new_skill)], 14)
		button.name = "MonsterReplace_%d_%d_%s_%s" % [uid, level, new_skill, old_skill]
		button.pressed.connect(func() -> void:
			if run.learn_monster_skill(uid, level, new_skill, old_skill):
				on_claim.call())
		_fit_button(button)
		box.add_child(button)


static func _fit_button(button: Button) -> void:
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.x = 0
