extends "res://scripts/ui/preview_screen.gd"

const MAX_DEPLOY := Balance.DEPLOY_LIMIT
var deploy_selection: Array = []
var check_boxes: Dictionary = {}
var team_box: VBoxContainer
var team_scroll: ScrollContainer

func _ready() -> void:
	var desired: Array = app.prep_deploy_preset if not app.prep_deploy_preset.is_empty() else app.run.deployed_uids
	app.prep_deploy_preset = []
	for record in app.run.carried:
		var uid := int(record["uid"])
		if deploy_selection.size() < MAX_DEPLOY and int(record["hp"]) > 0 and desired.has(uid):
			deploy_selection.append(uid)
	deploy_uids = deploy_selection.duplicate()
	super._ready()
	name = "PrepScreen"

func _build_roster() -> Control:
	var column := UIKit.vbox(8)
	column.name = "TeamPreparationPanel"
	column.add_child(UIKit.label("队伍与招式", 18, UIKit.ACCENT))
	column.add_child(UIKit.wrapped("训练师生命 %d/%d · 最多选择 %d 只出战；濒死成员不可选。" % [app.run.trainer_hp, app.run.trainer_max_hp(), MAX_DEPLOY], 13))
	var relic_names: Array = []
	for relic_id in app.run.relic_stacks:
		if RelicDB.owned(app.run.relic_stacks, String(relic_id)):
			relic_names.append("%s【%s】" % [RelicDB.name_of(String(relic_id)), RelicDB.rarity_name(String(relic_id))])
	column.add_child(UIKit.wrapped("本局遗物 %d 件：%s" % [relic_names.size(), "、".join(relic_names) if not relic_names.is_empty() else "尚无"], 12, UIKit.TEXT_DIM))
	team_scroll = UIKit.scroll()
	column.add_child(team_scroll)
	team_box = UIKit.vbox(6)
	team_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_scroll.add_child(team_box)
	_rebuild_roster()
	return column

func _rebuild_roster() -> void:
	check_boxes.clear()
	UIKit.clear_children(team_box)
	for record in app.run.carried:
		team_box.add_child(_team_row(record))
	for uid in deploy_selection:
		if check_boxes.has(uid):
			check_boxes[uid].set_pressed_no_signal(true)

func show_prep_after_mode_change() -> void:
	var scroll := team_scroll.scroll_vertical
	_rebuild_roster()
	team_scroll.set_deferred("scroll_vertical", scroll)
	_refresh()

func _team_row(record: Dictionary) -> Control:
	var species_id := String(record["species_id"])
	var row := UIKit.panel(UIKit.PANEL_LIGHT)
	var line := UIKit.hbox(10)
	row.add_child(line)
	var box := CheckBox.new()
	box.name = "Deploy_%d" % int(record["uid"])
	if int(record["hp"]) <= 0:
		box.disabled = true
		box.tooltip_text = "濒死：在营地休息后恢复至半血。" if app.run.region_mode else "濒死：留守一场后恢复到 5 HP。"
	box.toggled.connect(func(pressed: bool) -> void: _on_toggle(int(record["uid"]), pressed))
	line.add_child(box)
	check_boxes[int(record["uid"])] = box
	var info := UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	var title_line := UIKit.hbox(10)
	info.add_child(title_line)
	title_line.add_child(UIKit.label(SpeciesDB.name_of(species_id), 17))
	title_line.add_child(UIKit.element_chip(SpeciesDB.element_of(species_id)))
	var engraving_total: int = app.run.monster_engraving_slots(record)
	var engraving_empty: int = app.run.monster_empty_engraving_slots(record)
	info.add_child(UIKit.wrapped("本局 Lv.%d · 经验 %d/%d · 生命 %d/%d · 基础移动 %d · 刻印槽 %d/%d · 亲密度 %d（强化折扣）" % [
		int(record.get("level", 1)), int(record.get("xp", 0)), MonsterProgression.threshold_for_level(int(record.get("level", 1)) + 1),
		int(record["hp"]), app.run.monster_max_hp(record), SpeciesDB.move_of(species_id),
		engraving_empty, engraving_total, int(record.get("affinity", 0)),
	], 13, UIKit.TEXT_DIM))
	if int(record["hp"]) <= 0:
			title_line.add_child(UIKit.label("濒死（营地休息恢复半血）" if app.run.region_mode else "濒死（留守一场后恢复到 5 HP）", 13, UIKit.BAD))
	var upgrade_names: Array = []
	for upgrade_id in record.get("upgrades_taken", []):
		var info_entry: Dictionary = RunState.upgrade_info(String(upgrade_id))
		if not info_entry.is_empty():
			upgrade_names.append(String(info_entry.get("name", upgrade_id)))
	info.add_child(UIKit.wrapped("本局强化：%s" % ("、".join(upgrade_names) if not upgrade_names.is_empty() else "尚无"), 12, UIKit.TEXT_DIM))
	if bool(record.get("trait_upgrade_claimed", false)):
		info.add_child(UIKit.wrapped("Lv10 特性强化：已领取（具体效果待配置）", 12, UIKit.TEXT_DIM))
	var known: Array = record.get("known_skills", SpeciesDB.skills_of(species_id))
	var equipped: Array = record.get("equipped_skills", SpeciesDB.skills_of(species_id))
	var library_names: Array = []
	for skill_id in known:
		var id := String(skill_id)
		var enhanced := (record.get("upgrades_taken", []) as Array).has(RunState.upgrade_id_for_skill(id))
		library_names.append("%s%s%s" % [SkillDB.name_of(id), "★" if enhanced else "", "（特殊）" if SkillDB.is_special(id) else ""])
	info.add_child(UIKit.wrapped("本局招式库：" + "、".join(library_names), 12, UIKit.TEXT_DIM))
	for slot in range(RunState.MAX_EQUIPPED_SKILLS):
		var selector := OptionButton.new()
		selector.name = "SkillSlot_%d_%d" % [int(record["uid"]), slot]
		selector.add_item("装备位 %d：空" % (slot + 1))
		selector.set_item_metadata(0, "")
		var selected_index := 0
		for skill_id in known:
			var id := String(skill_id)
			if equipped.has(id) and (slot >= equipped.size() or String(equipped[slot]) != id):
				continue
			var enhanced := (record.get("upgrades_taken", []) as Array).has(RunState.upgrade_id_for_skill(id))
			selector.add_item("装备位 %d：%s%s" % [slot + 1, SkillDB.name_of(id), " ★" if enhanced else ""])
			selector.set_item_metadata(selector.item_count - 1, id)
			if slot < equipped.size() and String(equipped[slot]) == id:
				selected_index = selector.item_count - 1
		selector.select(selected_index)
		selector.item_selected.connect(_on_skill_slot_selected.bind(record, slot, selector))
		info.add_child(selector)
	if Elements.MATCHUPS_ENABLED:
		info.add_child(UIKit.wrapped(Elements.counter_hint(SpeciesDB.element_of(species_id)), 12))
	return row


func _on_skill_slot_selected(index: int, record: Dictionary, slot: int, selector: OptionButton) -> void:
	var skill_id := String(selector.get_item_metadata(index))
	var changed: bool = app.run.equip_monster_skill(int(record["uid"]), slot, skill_id)
	if changed:
		app.autosave()
		show_prep_after_mode_change()


func _on_toggle(uid: int, pressed: bool) -> void:
	if pressed:
		var record: Dictionary = app.run.record_by_uid(uid)
		if not record.is_empty() and int(record["hp"]) <= 0:
			var box: CheckBox = check_boxes[uid]
			box.set_pressed_no_signal(false)
			hint_label.text = "濒死的宝可梦无法出战：请在营地休息。" if app.run.region_mode else "濒死的宝可梦无法出战：留守一场后恢复到 5 HP。"
			return
		if deploy_selection.size() >= MAX_DEPLOY:
			var box: CheckBox = check_boxes[uid]
			box.set_pressed_no_signal(false)
			hint_label.text = "最多出战 %d 只。" % MAX_DEPLOY
			return
		if not deploy_selection.has(uid):
			deploy_selection.append(uid)
	else:
		deploy_selection.erase(uid)
	hint_label.text = ""
	deploy_uids = deploy_selection.duplicate()
	_refresh()


func _on_start() -> void:
	if app.run.run_lost():
		hint_label.text = "没有可出战的宝可梦，本局结束。"
		return
	if deploy_selection.is_empty():
		hint_label.text = "至少选择 1 只出战宝可梦。"
		return
	deploy_uids = deploy_selection.duplicate()
	super._on_start()
