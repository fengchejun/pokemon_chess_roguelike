extends Control

const CombatConfig = preload("res://scripts/combat_config.gd")
const MonsterCatalog = preload("res://scripts/monster_catalog.gd")
const EnvironmentCardSystem = preload("res://scripts/environment_card_system.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")

@onready var summary: Label = $Layout/Column/Summary
@onready var pending_title: Label = $Layout/Column/PendingTitle
@onready var pending_row: HBoxContainer = $Layout/Column/PendingRow
@onready var pending_label: Label = $Layout/Column/PendingRow/PendingLabel
@onready var replace_choice: OptionButton = $Layout/Column/PendingRow/ReplaceChoice
@onready var roster_title: Label = $Layout/Column/RosterTitle
@onready var roster_grid: GridContainer = $Layout/Column/RosterGrid
@onready var status_label: Label = $Layout/Column/Status
@onready var next_button: Button = $Layout/Column/BottomRow/NextButton
@onready var card_title: Label = $Layout/Column/CardTitle
@onready var card_row: HBoxContainer = $Layout/Column/CardRow
@onready var deck_label: Label = $Layout/Column/DeckLabel
@onready var next_region_label: Label = $Layout/Column/NextRegionLabel


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	var run: RunState = RunManager.run_state
	var reward: Dictionary = run.last_reward
	var result_name := "胜利" if reward.get("outcome", "") == "victory" else "野生怪物逃离"
	summary.text = "第 %d 场：%s  ·  击败 %d  ·  捕获 %d  ·  逃离 %d%s\n出战怪物各获得 %d 经验；本局累计 %d 经验。等级成长将在阶段 6 实现。" % [run.battle_count, result_name, reward.get("kills", 0), reward.get("captures", 0), reward.get("escaped", 0), " · 额外环境卡" if reward.get("bonus_card", false) else "", reward.get("experience", 0), run.total_experience]
	var has_pending: bool = not run.pending_captures.is_empty()
	pending_title.text = "待收容捕获 %d 只（逐只处理）" % run.pending_captures.size() if has_pending else "捕获收容完毕"
	pending_row.visible = has_pending
	if has_pending:
		var pending: Dictionary = run.pending_captures.front()
		pending_label.text = "%s：携带队伍已满" % MonsterCatalog.SPECIES[pending["species_id"]]["name"]
		replace_choice.clear()
		for record in run.roster:
			var index: int = replace_choice.item_count
			replace_choice.add_item(MonsterCatalog.SPECIES[record["species_id"]]["name"] + " · " + record["instance_id"])
			replace_choice.set_item_metadata(index, record["instance_id"])
	for child in card_row.get_children():
		child.queue_free()
	card_title.text = "选择额外环境卡（奖励携带者存活）" if run.bonus_choice_active and not run.offered_environment_cards.is_empty() else "选择一张环境卡（后续战场持续生效）" if not run.offered_environment_cards.is_empty() else "环境卡奖励已领取"
	for card_id in run.offered_environment_cards:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 70)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = EnvironmentCardSystem.card_text(card_id)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_card_pressed.bind(card_id))
		card_row.add_child(button)
	card_row.visible = not run.offered_environment_cards.is_empty()
	var names: Array[String] = []
	for card_id in run.environment_cards:
		names.append(EnvironmentCardSystem.CARDS[card_id]["name"])
	deck_label.text = "本局卡组：%s" % ["、".join(names) if not names.is_empty() else "暂无；首场战后可选择"]
	var next_region_id: String = MapGenerator.region_for_battle(run.battle_count)
	next_region_label.text = "下一场：%s · 基础倾向 %s · 环境卡只改变权重，不指定布局" % [MapGenerator.REGIONS[next_region_id]["name"], "水域" if next_region_id == "wetland" else "可燃植物" if next_region_id == "forest" else "岩石与易碎地块"]
	for child in roster_grid.get_children():
		child.queue_free()
	for record in run.roster:
		var button := Button.new()
		var species: Dictionary = MonsterCatalog.SPECIES[record["species_id"]]
		button.custom_minimum_size = Vector2(470, 36)
		button.text = "%s  %s  ·  经验 %d" % ["出战" if run.active_ids.has(record["instance_id"]) else "替补", species["name"], record["experience"]]
		button.pressed.connect(_on_roster_pressed.bind(record["instance_id"]))
		roster_grid.add_child(button)
	roster_title.text = "本局携带 %d/%d · 下一场出战 %d/%d" % [run.roster.size(), CombatConfig.CARRIED_MONSTER_LIMIT, run.active_ids.size(), CombatConfig.DEPLOYED_MONSTER_LIMIT]
	next_button.disabled = not run.can_start_battle()


func _on_replace_pressed() -> void:
	var run: RunState = RunManager.run_state
	if run.pending_captures.is_empty() or replace_choice.selected < 0:
		return
	var pending_id: String = run.pending_captures.front()["instance_id"]
	var existing_id: String = replace_choice.get_item_metadata(replace_choice.selected)
	if run.replace_with_pending(pending_id, existing_id):
		status_label.text = "已将新捕获怪物加入携带队伍。被替换怪物已离开本局队伍。"
	_refresh()


func _on_decline_pressed() -> void:
	var run: RunState = RunManager.run_state
	if run.pending_captures.is_empty():
		return
	run.decline_pending(run.pending_captures.front()["instance_id"])
	status_label.text = "已放弃这只待收容怪物；原携带队伍保持不变。"
	_refresh()


func _on_roster_pressed(instance_id: String) -> void:
	if RunManager.run_state.toggle_active(instance_id):
		status_label.text = "出战阵容已更新。"
	else:
		status_label.text = "最多三只出战；请先取消另一只怪物的出战。"
	_refresh()


func _on_card_pressed(card_id: String) -> void:
	if RunManager.run_state.choose_environment_card(card_id):
		status_label.text = "已将 %s 加入本局卡组，下一场生成时生效。" % EnvironmentCardSystem.CARDS[card_id]["name"]
	_refresh()


func _on_next_pressed() -> void:
	if not RunManager.run_state.can_start_battle():
		status_label.text = "请先处理待收容怪物、选择环境卡，并选好三只出战怪物。"
		return
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
