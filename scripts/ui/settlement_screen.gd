extends Control

var app = null

var battle: BattleState = null
var outcome: Dictionary = {}
var choice_box: VBoxContainer = null
var step_label: Label = null
var continue_button: Button = null
var processing := false
var mage_note_selected: Array = []
var magic_end_uid := -1


func _ready() -> void:
	name = "SettlementScreen"
	UIKit.fill_background(self)
	var data: Dictionary = app.pending_settlement
	battle = data.get("battle")
	outcome = data.get("outcome", {})
	var run: RunState = app.run
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var columns := UIKit.hbox(16)
	margin.add_child(columns)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UIKit.label(_result_title(), 30, UIKit.ACCENT))
	left.add_child(_summary_box(run))
	var right := UIKit.vbox(10)
	right.custom_minimum_size = Vector2(500, 0)
	columns.add_child(right)
	step_label = UIKit.label("", 19, UIKit.ACCENT)
	right.add_child(step_label)
	var scroll := UIKit.scroll()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	choice_box = UIKit.vbox(8)
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_box.custom_minimum_size.x = 500
	scroll.add_child(choice_box)
	continue_button = UIKit.button("继续", 18)
	continue_button.name = "ContinueButton"
	continue_button.disabled = true
	continue_button.pressed.connect(func() -> void:
		app.continue_after_settlement()
	)
	right.add_child(continue_button)
	_show_next_step()


func _result_title() -> String:
	match String(outcome.get("reason", "")):
		"victory":
			return "战斗胜利"
		"forced_retreat":
			return "强制撤退（战斗失败）"
		"escape":
			return "主动撤离 · 返回区域（敌人留守）" if app.run.region_mode else "主动撤离"
		"explored":
			return "收集结束 · 返回区域"
	return "战斗结束"


func _summary_box(run: RunState) -> Control:
	var box := UIKit.panel(UIKit.PANEL)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UIKit.vbox(4)
	box.add_child(column)
	var lines: Array = []
	if String(outcome.get("reason", "")) == "forced_retreat":
		lines.append("本场已入账的击杀、捕获经验保留；失败不追加战后目标经验。")
	else:
		lines.append("本场怪物经验合计：+%d（按击败、捕获与战场目标的实际贡献结算）" % int(outcome.get("exp", 0)))
	if outcome.has("trainer_exp"):
		var gained: Dictionary = outcome["trainer_exp"]
		lines.append("训练家：Lv.%d · 累计经验 %d · 本场已保留 +%d" % [int(gained["level"]), int(gained["xp"]), int(gained["gained"])])
	if bool(outcome.get("growth_migrated", false)):
		lines.append("旧本局存档已迁移：旧经验、等级与全队强化清零，保留关卡和奖励。")
	if bool(outcome.get("upgrade_migrated", false)):
		lines.append("局内强化规则已更新：旧通用强化退还为待选升级，原技能强化保留。")
	for growth in outcome.get("monster_exp", []):
		var level_text := "，升级至 Lv.%d" % int(growth["level_after"]) if int(growth["level_after"]) > int(growth["level_before"]) else ""
		var record := run.owned_record_by_uid(int(growth.get("uid", -1)))
		var affinity := int(record.get("affinity", 0))
		lines.append("%s：本局经验 +%d（%d/%d）%s；永久亲密度 %d" % [
			growth["name"], int(growth["gained"]), int(growth["xp_after"]),
			MonsterProgression.threshold_for_level(int(growth["level_after"]) + 1), level_text, affinity,
		])
	if not (outcome.get("escape_penalties", []) as Array).is_empty():
		lines.append("撤离代价：" + "、".join(outcome["escape_penalties"].map(func(p): return "%s %d→%d HP" % [p["name"], p["from"], p["to"]] if p.has("from") else "%s（旧版已结算记录）" % p["name"])))
	lines.append("击败：%d　捕获：%d" % [int(outcome.get("kills", 0)), int(outcome.get("captures", 0))])
	if int(outcome.get("boss_blood", 0)) > 0:
		lines.append("捕获首领：永久首领之血 +%d（当前 %d 份）" % [int(outcome["boss_blood"]), app.collection.boss_blood])
	if int(outcome.get("reward_points_earned", 0)) > 0:
		lines.append("奖励点：本场取得 %d 点，每名存活原出战成员额外获得 %d 经验" % [
			int(outcome["reward_points_earned"]), int(outcome["reward_points_earned"]),
		])
	if int(outcome.get("relic_reward_count", 0)) > 0:
		lines.append("遗物机会：+%d" % int(outcome["relic_reward_count"]))
	for notice in outcome.get("relic_notices", []):
		lines.append(String(notice))
	var pending_monster_levels: Array = run.pending_monster_levels()
	if not pending_monster_levels.is_empty():
		lines.append("待选怪物学招：%d 次（按怪物与等级顺序逐项处理）" % pending_monster_levels.size())
	var captured_names: Array = outcome.get("captured_names", [])
	if not captured_names.is_empty():
		lines.append("本场捕获：" + "、".join(captured_names))
	var flee_penalty: Array = outcome.get("flee_penalty", [])
	if not flee_penalty.is_empty():
		var punished: Array = []
		for entry in flee_penalty:
			punished.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("失败惩罚（出战宝可梦生命减半）：" + "；".join(punished))
	var recovery: Array = outcome.get("recovery", [])
	if not recovery.is_empty():
		var parts: Array = []
		for entry in recovery:
			parts.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("战后恢复：" + "；".join(parts))
	var base_rest: Array = outcome.get("base_rest", [])
	if not base_rest.is_empty():
		var rested: Array = []
		for entry in base_rest:
			rested.append("%s %d→%d" % [entry["name"], int(entry["from"]), int(entry["to"])])
		lines.append("备战席休养（存活者恢复 50% 上限；濒死者恢复到 5 HP）：" + "；".join(rested))
	var trainer_to := int(outcome.get("trainer_to", 0))
	var storage_rest := int(outcome.get("storage_rest", 0))
	if storage_rest > 0:
		lines.append("仓库休养：%d 只回满 100%%" % storage_rest)
	var trainer_from := int(outcome.get("trainer_from", trainer_to))
	if trainer_to > 0 and trainer_from < trainer_to:
		lines.append("训练家每次出征前回满：%d→%d" % [trainer_from, trainer_to])
	var death_entries: Array = outcome.get("deaths", [])
	if death_entries.size() > 0:
		lines.append("—— 本场濒死（营地休息恢复半血）——" if app.run.region_mode else "—— 本场濒死（留守一场后恢复到 5 HP）——")
		for entry in death_entries:
			lines.append("%s（%s）" % [entry.get("name", "?"), entry.get("cause", "?")])
	column.add_child(UIKit.wrapped("\n".join(lines), 14))
	return box


func _show_next_step() -> void:
	processing = false
	UIKit.clear_children(choice_box)
	var run: RunState = app.run
	if not run.pending_captures.is_empty():
		if run.region_mode and run.carried.size() >= Balance.CARRIED_LIMIT:
			run.capture_to_storage()
			app.autosave()
			_show_next_step()
			return
		# 名单未满：直接入队（不打断流程）
		if run.carried.size() < Balance.CARRIED_LIMIT:
			run.capture_join_team()
			app.autosave()
			_show_next_step()
			return
		_show_capture_step(run)
		return
	var pending_monster_levels: Array = run.pending_monster_levels()
	if not pending_monster_levels.is_empty():
		_show_monster_level_step(run, pending_monster_levels[0], pending_monster_levels.size())
		return
	if run.has_pending_relic_actions():
		_show_relic_action_step(run)
		return
	if run.pending_reward_choices > 0:
		var choices := run.reward_choices()
		if choices.is_empty():
			var discarded := run.discard_unavailable_reward_choices()
			step_label.text = "遗物奖励：暂无可领取项目"
			choice_box.add_child(UIKit.wrapped("全部可提供遗物均已获得，%d 次机会已跳过。" % discarded, 13, UIKit.TEXT_DIM))
			app.autosave()
			continue_button.disabled = false
			return
		step_label.text = "遗物三选一（剩余 %d 次）" % run.pending_reward_choices
		choice_box.add_child(UIKit.wrapped("选择一件本局唯一遗物。进化型遗物会替换其前置遗物；效果立即生效并随本局保存。", 13))
		for reward_id in choices:
			var id := String(reward_id)
			var button := UIKit.button("%s【%s】\n%s" % [
				RelicDB.name_of(id), RelicDB.rarity_name(id), RelicDB.description_of(id),
			], 14)
			button.name = "RelicChoice_%s" % id
			button.custom_minimum_size = Vector2(0, 92)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(_choose_settlement_relic.bind(id))
			choice_box.add_child(button)
		continue_button.disabled = true
		return
	step_label.text = "全部处理完成，可以进入下一场。"
	choice_box.add_child(UIKit.wrapped("战斗结算顺序已完成：怪物经验 → 捕获 → 怪物升级 → 遗物选择 → 下一场准备。", 13))
	continue_button.disabled = false


func _choose_settlement_relic(relic_id: String) -> void:
	if processing:
		return
	processing = true
	if app.run.choose_reward(relic_id):
		app.autosave()
		_show_next_step()
	else:
		processing = false


func _show_relic_action_step(run: RunState) -> void:
	var action := run.pending_relic_action()
	match String(action.get("kind", "")):
		"mage_notes":
			_show_mage_notes_step(run)
		"unbalanced_scales":
			_show_unbalanced_step(run)
		"magic_end":
			_show_magic_end_step(run)
		_:
			run.pending_relic_actions.pop_front()
			app.autosave()
			_show_next_step()


func _show_mage_notes_step(run: RunState) -> void:
	var eligible := run.mage_note_eligible_uids()
	var required := mini(3, eligible.size())
	step_label.text = "法师笔记：选择 %d 只宝可梦（%d/%d）" % [required, mage_note_selected.size(), required]
	choice_box.add_child(UIKit.wrapped("每名被选成员会随机学会 1 个尚未掌握的本属性普通技能；新技能进入招式库。", 13))
	if required == 0:
		choice_box.add_child(UIKit.wrapped("当前没有可学习新技能的成员，本次法师笔记自动跳过。", 13, UIKit.TEXT_DIM))
		var skip := UIKit.small_button("跳过法师笔记")
		skip.pressed.connect(func() -> void:
			run.resolve_mage_notes([])
			app.autosave()
			_show_next_step()
		)
		choice_box.add_child(skip)
		continue_button.disabled = true
		return
	for record in run.carried:
		var uid := int(record["uid"])
		var selected := mage_note_selected.has(uid)
		var button := UIKit.small_button("%s %s · 可学 %d 个" % [
			"✓" if selected else "○",
			SpeciesDB.name_of(String(record["species_id"])),
			run.mage_note_candidates(uid).size(),
		])
		button.disabled = selected or run.mage_note_candidates(uid).is_empty()
		button.pressed.connect(func() -> void:
			if not mage_note_selected.has(uid):
				mage_note_selected.append(uid)
			if mage_note_selected.size() >= required:
				var result := run.resolve_mage_notes(mage_note_selected)
				mage_note_selected.clear()
				if bool(result.get("ok", false)):
					app.autosave()
				_show_next_step()
			else:
				_show_next_step()
		)
		choice_box.add_child(button)
	var reset := UIKit.small_button("重置选择")
	reset.disabled = mage_note_selected.is_empty()
	reset.pressed.connect(func() -> void:
		mage_note_selected.clear()
		_show_next_step()
	)
	choice_box.add_child(reset)
	continue_button.disabled = true


func _show_unbalanced_step(run: RunState) -> void:
	step_label.text = "不平天秤：选择 1 件遗物摧毁"
	var candidates := run.unbalanced_candidates()
	if candidates.is_empty():
		run.pending_relic_actions.pop_front()
		app.autosave()
		_show_next_step()
		return
	choice_box.add_child(UIKit.wrapped("摧毁后随机获得 2 件遗物：普通 50%、稀有 30%、传奇 20%。", 13))
	for relic_id in candidates:
		var id := String(relic_id)
		var button := UIKit.small_button("摧毁 %s【%s】\n%s" % [
			RelicDB.name_of(id), RelicDB.rarity_name(id), RelicDB.description_of(id),
		])
		button.pressed.connect(func() -> void:
			var result := run.resolve_unbalanced_scales(id)
			if bool(result.get("ok", false)):
				app.autosave()
			_show_next_step()
		)
		choice_box.add_child(button)
	continue_button.disabled = true


func _show_magic_end_step(run: RunState) -> void:
	if magic_end_uid < 0:
		step_label.text = "术之尽头：选择学习魔法的成员"
		choice_box.add_child(UIKit.wrapped("先选择 1 名我方成员，再从 3 个魔法中选择 1 个。", 13))
		for record in run.carried:
			var uid := int(record["uid"])
			var button := UIKit.small_button("选择 %s" % SpeciesDB.name_of(String(record["species_id"])))
			button.pressed.connect(func() -> void:
				magic_end_uid = uid
				_show_next_step()
			)
			choice_box.add_child(button)
	else:
		var record := run.owned_record_by_uid(magic_end_uid)
		step_label.text = "术之尽头：%s 选择魔法" % SpeciesDB.name_of(String(record.get("species_id", "")))
		for magic_id in ["ultra_death_ray", "time_mirror_leap", "mage_key"]:
			var button := UIKit.small_button("%s\n%s" % [SkillDB.name_of(magic_id), SkillDB.get_def(magic_id).get("desc", "")])
			button.pressed.connect(func() -> void:
				var result := run.resolve_magic_end(magic_end_uid, magic_id)
				magic_end_uid = -1
				if bool(result.get("ok", false)):
					app.autosave()
				_show_next_step()
			)
			choice_box.add_child(button)
	continue_button.disabled = true


func _show_monster_level_step(run: RunState, entry: Dictionary, remaining: int) -> void:
	var uid := int(entry.get("uid", -1))
	var level := int(entry.get("level", 1))
	var record := run.owned_record_by_uid(uid)
	var monster_name := SpeciesDB.name_of(String(record.get("species_id", ""))) if not record.is_empty() else "怪物 #%d" % uid
	step_label.text = "%s · Lv.%d 升级选择（剩余 %d 项）" % [monster_name, level, remaining]
	if level == 10:
		choice_box.add_child(UIKit.wrapped("Lv10 特性强化入口。当前版本暂不增加生命值以外的实际效果，领取后记录本次特性强化。", 13))
		var trait_button := UIKit.button("领取特性强化入口", 16)
		trait_button.name = "MonsterTrait_%d_10" % uid
		trait_button.pressed.connect(func() -> void:
			if not processing and run.claim_monster_trait_upgrade(uid, 10):
				processing = true
				app.autosave()
				_show_next_step()
		)
		choice_box.add_child(trait_button)
		continue_button.disabled = true
		return
	var slots := run.monster_engraving_slots(record)
	choice_box.add_child(UIKit.wrapped("已自动获得刻印槽，当前共 %d 个。请从以下三招中选择一招学习；选择后进入招式库，装备位仍为 3 个。" % slots, 13))
	var candidates := run.monster_level_choices(uid, level)
	if candidates.is_empty():
		var skip := UIKit.small_button("没有可学习技能，领取本等级")
		skip.name = "MonsterLearnSkip_%d_%d" % [uid, level]
		skip.pressed.connect(func() -> void:
			if not processing and run.skip_monster_skill_choice(uid, level):
				processing = true
				app.autosave()
				_show_next_step()
		)
		choice_box.add_child(skip)
		continue_button.disabled = true
		return
	for candidate in candidates:
		var skill_id := String(candidate)
		var button := UIKit.button("%s\n%s" % [SkillDB.name_of(skill_id), SkillDB.get_def(skill_id).get("desc", "")], 14)
		button.name = "MonsterLearn_%d_%d_%s" % [uid, level, skill_id]
		button.pressed.connect(_choose_monster_skill.bind(run, uid, level, skill_id))
		_fit_growth_button(button)
		choice_box.add_child(button)
	continue_button.disabled = true


func _fit_growth_button(button: Button) -> void:
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.x = 0


func _show_growth_replace(run: RunState, uid: int, level: int, new_skill_id: String) -> void:
	UIKit.clear_children(choice_box)
	step_label.text = "三招已满：选择卸下的一招"
	choice_box.add_child(UIKit.wrapped("卸下的招式留在本局招式库，已取得的强化也会保留；下场战斗前可在整备页换回。", 13))
	var back := UIKit.small_button("返回学招选择")
	back.pressed.connect(func() -> void: _show_monster_level_step(run, {"uid": uid, "level": level}, run.pending_monster_levels().size()))
	choice_box.add_child(back)
	for equipped_id in run.owned_record_by_uid(uid).get("equipped_skills", []):
		var old_id := String(equipped_id)
		var button := UIKit.button("卸下 %s → 装备 %s" % [SkillDB.name_of(old_id), SkillDB.name_of(new_skill_id)], 14)
		button.name = "MonsterReplace_%d_%d_%s_%s" % [uid, level, new_skill_id, old_id]
		button.pressed.connect(_replace_monster_skill.bind(run, uid, level, new_skill_id, old_id))
		choice_box.add_child(button)
	continue_button.disabled = true


func _choose_monster_skill(run: RunState, uid: int, level: int, skill_id: String) -> void:
	var equipped: Array = run.owned_record_by_uid(uid).get("equipped_skills", [])
	if equipped.size() >= RunState.MAX_EQUIPPED_SKILLS:
		_show_growth_replace(run, uid, level, skill_id)
	elif not processing and run.learn_monster_skill(uid, level, skill_id):
		processing = true
		app.autosave()
		_show_next_step()


func _replace_monster_skill(run: RunState, uid: int, level: int, new_skill_id: String, old_skill_id: String) -> void:
	if not processing and run.learn_monster_skill(uid, level, new_skill_id, old_skill_id):
		processing = true
		app.autosave()
		_show_next_step()


func _show_capture_step(run: RunState) -> void:
	## 名单已满：给出「替换（被替换者入仓库）」或「放入仓库」两个选项。
	var target: Dictionary = run.pending_capture()
	if target.is_empty():
		_show_next_step()
		return
	step_label.text = "捕获处理：名单已满（%d 只），选择替换或放入仓库" % Balance.CARRIED_LIMIT
	choice_box.add_child(UIKit.wrapped("新捕获：%s（生命 %d/%d，另有 %d 只待处理）" % [
		SpeciesDB.name_of(String(target["species_id"])), int(target["hp"]),
		SpeciesDB.hp_of(String(target["species_id"])), run.pending_captures.size(),
	], 15))
	var storage_room := run.storage.size() < Balance.STORAGE_LIMIT
	choice_box.add_child(UIKit.label("替换（选定成员将进入仓库）：", 13, UIKit.TEXT_DIM))
	var replace_row := UIKit.vbox(4)
	choice_box.add_child(replace_row)
	for record in run.carried:
		var faint_tag := "（濒死）" if int(record["hp"]) <= 0 else ""
		var button := UIKit.small_button("替换掉 %s%s（%d/%d，其入仓库）" % [
			SpeciesDB.name_of(String(record["species_id"])), faint_tag, int(record["hp"]),
			SpeciesDB.hp_of(String(record["species_id"])),
		])
		var replace_uid := int(record["uid"])
		if not storage_room:
			button.disabled = true
			button.tooltip_text = "仓库已满：先放生或选择放弃。"
		button.pressed.connect(func() -> void:
			if run.capture_replace(replace_uid):
				app.autosave()
				_show_next_step()
		)
		replace_row.add_child(button)
	var to_storage := UIKit.small_button("放入仓库（%d/%d）" % [run.storage.size(), Balance.STORAGE_LIMIT])
	to_storage.name = "CaptureToStorageButton"
	to_storage.disabled = not storage_room
	if not storage_room:
		to_storage.tooltip_text = "仓库已满：可先放生一名仓库成员或选择放弃。"
	to_storage.pressed.connect(func() -> void:
		if run.capture_to_storage():
			app.autosave()
			_show_next_step()
	)
	choice_box.add_child(to_storage)
	choice_box.add_child(UIKit.wrapped("仓库成员会随本局跨层保留，但本局结束时默认被抛弃；结束时仍留在仓库者不会自动进入永久收藏。", 13, UIKit.BAD))
	if not storage_room:
		choice_box.add_child(UIKit.label("仓库已满：放生一名仓库成员后可继续放入：", 13, UIKit.BAD))
		for record in run.storage.slice(0, mini(10, run.storage.size())):
			var release := UIKit.small_button("放生 %s（%d/%d）" % [
				SpeciesDB.name_of(String(record["species_id"])), int(record["hp"]),
				SpeciesDB.hp_of(String(record["species_id"])),
			])
			var release_uid := int(record["uid"])
			release.pressed.connect(func() -> void:
				if run.release_storage(release_uid):
					app.autosave()
					_show_next_step()
			)
			choice_box.add_child(release)
	var give_up := UIKit.small_button("放弃本次捕获")
	give_up.pressed.connect(func() -> void:
		run.capture_discard()
		app.autosave()
		_show_next_step()
	)
	choice_box.add_child(give_up)
	continue_button.disabled = true
