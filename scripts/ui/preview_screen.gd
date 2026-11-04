extends Control
const Deployment = preload("res://scripts/rules/deployment.gd")

## 地形改造工具表：允许的来源地形与目标地形（悬停时会在提示栏显示结算内容）。
const MOD_RULES := {
	"water": {"name": "注水", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.WATER},
	"grass": {"name": "种草", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.GRASS},
	"rock": {"name": "立岩", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.OBSTACLE},
	"clear": {"name": "开垦", "ok_from": TerrainDB.OBSTACLE, "to": TerrainDB.PLAIN},
	"deep": {"name": "深水", "ok_from": TerrainDB.WATER, "to": TerrainDB.DEEP},
	"lava": {"name": "熔岩", "ok_from": TerrainDB.PLAIN, "to": TerrainDB.LAVA},
}

var app = null
var deploy_uids: Array = []
var map: Dictionary = {}
var base_map: Dictionary = {}
var mod_used: int = 0
var mod_kind: String = "water"
var board: BoardView = null
var hint_label: Label = null
var mod_count_label: Label = null
var mod_buttons: Dictionary = {}
var card_selector: OptionButton = null
var card_use_button: Button = null
var card_status_label: Label = null
var card_header_label: Label = null
var card_result: Dictionary = {}
var persistent_node := false
var deployment_mode := true
var deploy_selected_uid := 0
var deploy_players: Array = []
var deploy_enemies: Array = []
var deploy_positions: Dictionary = {}
var deployment_toggle: Button
var start_button: Button
var board_host: Control
var tools_scroll: ScrollContainer


func _ready() -> void:
	name = "PreviewScreen"
	UIKit.fill_background(self)
	var run: RunState = app.run
	var map_salt := 0
	if run.region_mode:
		var active_id: String = run.get_region().active_node
		if active_id.begins_with("event_"):
			map_salt = 100 + int(active_id.trim_prefix("event_"))
	var nest_count := 1
	map = MapGenerator.generate(run.seed, run.battle_index, map_salt, [], run.current_theme(), nest_count)
	if run.region_mode:
		var region = run.get_region()
		var saved: BattleState = region.load_battle(region.active_node)
		if saved != null:
			persistent_node = true
			map["terrain"] = saved.terrain.duplicate()
			map["nest_cell"] = saved.nest["cell"]
			map["nest_cells"] = saved.all_nests().map(func(current): return current["cell"])
			map["nests"] = saved.all_nests().duplicate(true)
			map["mentor_cell"] = saved.mentor.get("cell", Vector2i(-1, -1))
			map["merchant_cell"] = saved.merchant.get("cell", Vector2i(-1, -1))
			map["portal_cell"] = saved.boss_portal_cell
			map["nest_exits"] = []
			map["nest_alive"] = bool(saved.nest.get("alive", false))
			map["nest_hp"] = int(saved.nest.get("hp", 0))
			map["reward_cell"] = saved.reward.get("cell", Vector2i(-1, -1))
			map["reward"] = saved.reward.duplicate(true)
			map["extra_rewards"] = saved.extra_rewards.duplicate(true)
			map["chests"] = saved.chests.duplicate()
			map["treasure_generated"] = true
			map["food_cells"] = saved.food_cells.duplicate()
			map["obstacle_cells"] = saved.obstacle_durability.keys()
		elif region.node_mode(region.active_node) == "event":
			map["nests"] = []
		if region.nodes[region.active_node].has("merchant") and saved == null:
			var position_data: Array = region.nodes[region.active_node]["merchant"].get("cell", [-1, -1])
			map["merchant_cell"] = Vector2i(int(position_data[0]), int(position_data[1]))
	if run.preview_used_reward_item.begins_with("map:"):
		card_result = MapGenerator.generate_card_preview(run.seed, run.battle_index, run.preview_used_reward_item.trim_prefix("map:"), map)
		map = (card_result["map"] as Dictionary).duplicate(true)
	_prepare_treasure()
	base_map = map.duplicate(true)
	for modification in run.preview_modifications:
		if typeof(modification) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = modification
		var cell := Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))
		if MapGenerator.apply_modification(map, cell, String(entry.get("kind", ""))):
			mod_used += 1
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var page := UIKit.vbox(8)
	margin.add_child(page)
	var location: String = run.get_region().display_name(run.get_region().active_node) if run.region_mode else "%d/6 战" % (run.battle_in_floor() + 1)
	page.add_child(UIKit.label("战前整备与地图预览 · 第 %d 层 · %s · %s" % [run.floor_index() + 1, location, run.region_name()], 22, UIKit.ACCENT))
	var columns := UIKit.hbox(14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	var roster := _build_roster()
	if roster != null:
		roster.custom_minimum_size.x = 400
		roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roster.size_flags_stretch_ratio = 1.0
		columns.add_child(roster)
	var preview := UIKit.vbox(6)
	preview.name = "MapPreviewPanel"
	preview.custom_minimum_size.x = 520
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_stretch_ratio = 1.2
	columns.add_child(preview)
	board_host = Control.new()
	board_host.custom_minimum_size.y = 280
	board_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(board_host)
	board = BoardView.new()
	board.name = "BoardView"
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	board_host.add_child(board)
	board_host.resized.connect(_layout_preview_board)
	preview.add_child(UIKit.wrapped("绿框：部署/撤离区（区外队员撤离损失25%最大生命，可能濒死并掉落奖励） · 蓝框：部署选位 · 紫色：巢穴 · ★：奖励 · 粮：食物；悬停单位查看招式。", 12))
	deployment_toggle = UIKit.small_button("部署选位 · 点击单位，再点击蓝框格")
	deployment_toggle.name = "DeploymentModeButton"
	deployment_toggle.pressed.connect(func() -> void:
		deployment_mode = true
		deployment_toggle.text = "部署选位 · 点击单位，再点击蓝框格"
		hint_label.text = "可交换我方单位；部署不消耗移动或改造次数。"
	)
	preview.add_child(deployment_toggle)
	var tools_toggle := UIKit.small_button("消耗品与地图改造 ▸")
	tools_toggle.name = "PreviewToolsToggle"
	preview.add_child(tools_toggle)
	tools_scroll = UIKit.scroll()
	tools_scroll.custom_minimum_size.y = 180
	tools_scroll.size_flags_vertical = Control.SIZE_FILL
	tools_scroll.visible = false
	preview.add_child(tools_scroll)
	tools_toggle.pressed.connect(func() -> void:
		tools_scroll.visible = not tools_scroll.visible
		tools_toggle.text = "消耗品与地图改造 ▾" if tools_scroll.visible else "消耗品与地图改造 ▸"
	)
	var content := UIKit.vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_scroll.add_child(content)
	content.add_child(_cards_box())
	var mod_box := UIKit.panel(UIKit.PANEL)
	var mod_column := UIKit.vbox(6)
	mod_box.add_child(mod_column)
	mod_column.add_child(UIKit.label("地形改造（悬停查看结算，点击应用）", 17, UIKit.ACCENT))
	var mod_row := UIKit.hbox(6)
	mod_column.add_child(mod_row)
	var mod_row2 := UIKit.hbox(6)
	mod_column.add_child(mod_row2)
	var row_index := 0
	for kind in MOD_RULES:
		var id := String(kind)
		var rule: Dictionary = MOD_RULES[id]
		var button := UIKit.small_button(String(rule["name"]))
		button.name = "ModButton_%s" % id
		button.toggle_mode = true
		button.button_pressed = id == mod_kind
		button.disabled = run.mod_points() <= 0
		button.tooltip_text = "%s：%s → %s" % [
			rule["name"], "平地/冰面" if id in ["water", "grass", "rock"] else TerrainDB.name_of(int(rule["ok_from"])), TerrainDB.name_of(int(rule["to"])),
		]
		button.pressed.connect(func() -> void: _set_mod_kind(id))
		if row_index < 3:
			mod_row.add_child(button)
		else:
			mod_row2.add_child(button)
		mod_buttons[id] = button
		row_index += 1
	mod_count_label = UIKit.label("", 14, UIKit.TEXT_DIM)
	mod_column.add_child(mod_count_label)
	var mod_actions := UIKit.hbox(8)
	mod_column.add_child(mod_actions)
	var reset_button := UIKit.small_button("重置改造")
	reset_button.pressed.connect(_on_reset)
	mod_actions.add_child(reset_button)
	content.add_child(mod_box)
	hint_label = UIKit.wrapped("", 13, UIKit.TEXT_DIM)
	hint_label.custom_minimum_size.y = 34
	page.add_child(hint_label)
	var actions := UIKit.hbox(8)
	page.add_child(actions)
	if run.region_mode:
		var back := UIKit.small_button("返回区域路线")
		back.name = "BackButton"
		back.pressed.connect(func() -> void: app.cancel_region_entry())
		actions.add_child(back)
	start_button = UIKit.button("开始战斗", 18)
	start_button.name = "StartBattleButton"
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(_on_start)
	actions.add_child(start_button)
	_refresh()
	call_deferred("_layout_preview_board")


func _build_roster() -> Control:
	return null

func _layout_preview_board() -> void:
	if board_host == null or board == null:
		return
	var factor := minf(board_host.size.x / (GridSpec.W * BoardView.TILE), board_host.size.y / (GridSpec.H * BoardView.TILE))
	board.scale = Vector2.ONE * factor
	board.position = (board_host.size - Vector2(GridSpec.W, GridSpec.H) * BoardView.TILE * factor) * 0.5


func _cards_box() -> Control:
	var run: RunState = app.run
	var box := UIKit.panel(UIKit.PANEL)
	var column := UIKit.vbox(6)
	box.add_child(column)
	card_header_label = UIKit.label("战前消耗品背包（%d 张）" % run.reward_inventory.size(), 17, UIKit.ACCENT)
	column.add_child(card_header_label)
	card_selector = OptionButton.new()
	card_selector.name = "RewardItemOption"
	if run.preview_used_reward_item != "":
		card_selector.add_item("本场已使用：%s" % RewardDB.name_of(run.preview_used_reward_item))
	else:
		card_selector.add_item("选择一张消耗品")
		var selected_index := 0
		for reward_id in run.reward_inventory:
			var id := String(reward_id)
			card_selector.add_item(RewardDB.name_of(id))
			if id == run.selected_reward_item and selected_index == 0:
				selected_index = card_selector.item_count - 1
		card_selector.select(selected_index)
	card_selector.disabled = run.preview_used_reward_item != ""
	card_selector.item_selected.connect(func(_index: int) -> void: _refresh_card_status())
	column.add_child(card_selector)
	card_use_button = UIKit.small_button("使用并消耗")
	card_use_button.name = "UseRewardItemButton"
	card_use_button.disabled = run.preview_used_reward_item != "" or run.reward_inventory.is_empty()
	card_use_button.pressed.connect(_on_use_reward_item)
	column.add_child(card_use_button)
	card_status_label = UIKit.wrapped("", 13)
	column.add_child(card_status_label)
	_refresh_card_status()
	return box


func _on_use_reward_item() -> void:
	if persistent_node:
		return
	var run: RunState = app.run
	var index := card_selector.selected - 1
	if index < 0 or index >= run.reward_inventory.size():
		hint_label.text = "请先选择一张背包里的消耗品。"
		return
	var reward_id := String(run.reward_inventory[index])
	if not run.use_reward_item_in_preview(reward_id):
		hint_label.text = "本场已经使用过消耗品，或这张卡已不在背包。"
		return
	if reward_id.begins_with("map:"):
		card_result = MapGenerator.generate_card_preview(run.seed, run.battle_index, reward_id.trim_prefix("map:"), map)
		map = (card_result["map"] as Dictionary).duplicate(true)
		_prepare_treasure()
		base_map = map.duplicate(true)
	card_selector.disabled = true
	card_selector.clear()
	card_selector.add_item("本场已使用：%s" % RewardDB.name_of(reward_id))
	card_use_button.disabled = true
	card_header_label.text = "战前消耗品背包（%d 张）" % run.reward_inventory.size()
	_refresh_card_status()
	_refresh()
	app.autosave()


func _refresh_card_status() -> void:
	if card_status_label == null:
		return
	var used := String(app.run.preview_used_reward_item)
	if used == "":
		var index := card_selector.selected - 1
		if index >= 0 and index < app.run.reward_inventory.size():
			var selected := String(app.run.reward_inventory[index])
			card_status_label.text = "%s：%s" % [RewardDB.name_of(selected), RewardDB.description_of(selected)]
		else:
			card_status_label.text = "未使用。站位卡在本场战斗生效；改造工具可在此页改造地形。"
		return
	card_status_label.text = "已消耗：%s。%s" % [RewardDB.name_of(used), RewardDB.description_of(used)]
	if used.begins_with("map:") and not card_result.is_empty():
		var before: Dictionary = card_result["before"]
		var after: Dictionary = card_result["after"]
		var details: Array = []
		var terrain_names := {"water": "浅水", "grass": "草丛", "rock": "岩障", "steam": "蒸汽"}
		for key in MapGenerator.card_targets(used.trim_prefix("map:")):
			details.append("%s %d→%d" % [terrain_names.get(String(key), key), int(before[key]), int(after[key])])
		card_status_label.text += "\n对应地形：%s。" % "、".join(details)
		if not bool(card_result["guaranteed"]):
			card_status_label.text += "本图空间受限，未能全部增加；卡已消耗。"


func _set_mod_kind(kind: String) -> void:
	deployment_mode = false
	deployment_toggle.text = "返回部署选位"
	mod_kind = kind
	for key in mod_buttons:
		var button: Button = mod_buttons[key]
		button.button_pressed = String(key) == kind
	hint_label.text = ""


func _on_cell_clicked(cell: Vector2i) -> void:
	if deployment_mode:
		_deploy_click(cell)
		return
	if persistent_node:
		hint_label.text = "重访节点保留已有地形，不能重新进行战前改造。"
		return
	var run: RunState = app.run
	if mod_used >= run.mod_points():
		hint_label.text = "未使用地形改造工具，或本场改造次数已用尽。"
		return
	if MapGenerator.mod_protected(map, cell):
		hint_label.text = "部署区、巢穴与奖励格受保护，不能改造。"
		return
	if MapGenerator.apply_modification(map, cell, mod_kind):
		mod_used += 1
		run.preview_modifications.append({"x": cell.x, "y": cell.y, "kind": mod_kind})
		app.autosave()
		hint_label.text = ""
		_refresh()
	elif deployment_mode:
		hint_label.text = "部署格：先点击我方单位，再点击此格放置。" if (map.get("deploy_area", []) as Array).has(cell) else "此格不在部署区域。"
	else:
		hint_label.text = _mod_hover_text(cell)


func _on_cell_hovered(cell: Vector2i) -> void:
	if cell == Vector2i(-1, -1):
		return
	var unit: CombatUnit = null
	for candidate in board.units:
		if candidate.cell == cell:
			unit = candidate
			break
	if unit != null:
		var skills: Array = []
		for id in unit.skills:
			skills.append(SkillDB.name_of(String(id)))
		hint_label.text = "%s · Lv.%d · HP %d/%d · %s" % [unit.display_name, unit.combat_level, unit.hp, unit.max_hp, "、".join(skills)]
		if unit.corrupted:
			hint_label.text += " · 黑化：生命/威力+10%，击杀无经验"
		if unit.reward_carrier:
			hint_label.text += " · 携带奖励点"
	else:
		hint_label.text = _mod_hover_text(cell)
	hint_label.add_theme_color_override("font_color", UIKit.TEXT)
	board.queue_redraw()


func _mod_hover_text(cell: Vector2i) -> String:
	var run: RunState = app.run
	var rule: Dictionary = MOD_RULES.get(mod_kind, {})
	var tool_name := String(rule.get("name", mod_kind))
	if (map.get("chests", {}) as Dictionary).has(cell):
		return "宝箱：不可站立，命中一次攻击后破坏，在原格留下不可被攻击摧毁的奖励点。"
	if (map.get("nest_cells", [map.get("nest_cell", Vector2i(-1, -1))]) as Array).has(cell):
		if run.region_mode and run.get_region().node_mode(run.get_region().active_node) == "event":
			return "该格为后续占领事件保留，暂不能改造。"
		return "巢穴不可站立或叠加其他地形；每两轮在上下左右空格生成增援，无空格则积压，出生轮待机。巢穴三层生命30/50/70；邻接敌人可消耗技能机会守护，巢穴承担一半伤害，其余由有效守军均分，持续到下次敌方阶段。第9轮起出生的增援击杀无经验。"
	if MapGenerator.mod_protected(map, cell):
		return "【%s】该格受保护（部署区 / 巢穴 / 奖励 / 果实），不能改造。" % tool_name
	var terrain := int(map["terrain"][GridSpec.index(cell)])
	var from_terrain := int(rule.get("ok_from", TerrainDB.PLAIN))
	var to_terrain := int(rule.get("to", TerrainDB.PLAIN))
	var accepts_ice := terrain == TerrainDB.ICE and mod_kind in ["water", "grass", "rock"]
	if terrain != from_terrain and not accepts_ice:
		return "【%s】需要%s（当前：%s），该格不能改造。" % [
			tool_name, "平地/冰面" if mod_kind in ["water", "grass", "rock"] else TerrainDB.name_of(from_terrain), TerrainDB.name_of(terrain),
		]
	if mod_used >= run.mod_points():
		return "【%s】%s → %s：未使用改造工具，或次数已用尽。" % [tool_name, TerrainDB.name_of(terrain), TerrainDB.name_of(to_terrain)]
	return "【%s】%s → %s：点击应用，消耗 1 次（剩余 %d 次）。" % [
		tool_name, TerrainDB.name_of(terrain), TerrainDB.name_of(to_terrain),
		run.mod_points() - mod_used,
	]


func _on_reset() -> void:
	if persistent_node:
		return
	map = base_map.duplicate(true)
	mod_used = 0
	app.run.preview_modifications.clear()
	app.autosave()
	hint_label.text = ""
	_refresh()


func _prepare_treasure() -> void:
	if persistent_node:
		return
	var run: RunState = app.run
	var region = run.get_region() if run.region_mode else null
	var mode: String = region.node_mode(region.active_node) if region != null else "battle"
	MapGenerator.populate_treasure(map, run.place_region_enemies(run.battle_config(), map), run.seed, run.battle_index, mode, region.active_node if region != null else "")


func _refresh() -> void:
	var run: RunState = app.run
	map["nest_max_hp"] = Balance.nest_max_hp(run.battle_index)
	_prepare_treasure()
	deploy_enemies = _preview_units(run)
	deploy_players = run.build_deploy_units(deploy_uids)
	var placement := Deployment.prepare(map, deploy_enemies, deploy_players, run.preview_deploy_positions)
	deploy_positions = placement["positions"]
	map["deploy_area"] = placement["area"]
	map["deploy_positions"] = deploy_positions.duplicate()
	run.preview_deploy_positions = deploy_positions.duplicate()
	for unit in deploy_players:
		unit.cell = deploy_positions.get(unit.uid, Vector2i(-1, -1))
	if run.region_mode:
		var region = run.get_region()
		var id: String = region.active_node
		var mode: String = region.node_mode(id)
		if not persistent_node:
			var sample := BattleState.new()
			var cfg := run.battle_config().duplicate(true)
			if mode == "event":
				cfg["enemies"] = []
				cfg["reinforce"] = []
				cfg["boss_index"] = -1
			cfg = run.place_region_enemies(cfg, map)
			sample.node_kind = mode
			sample.setup(map, cfg, run.seed, run.battle_index, run.build_deploy_units(deploy_uids), run.effects(), {}, cfg.get("reinforce", []))
			sample.seed_initial_food()
			map["food_cells"] = sample.food_cells.duplicate()
			if mode == "event":
				# 收集区同样可以生成宝箱和奖励点。
				if region.nodes[id].has("merchant") and not GridSpec.is_inside(map.get("merchant_cell", Vector2i(-1, -1))):
					map["merchant_cell"] = Merchant.choose_battle_cell(sample, deploy_positions)
		if mode == "event":
			map["nests"] = []
	if run.region_mode:
		var region = run.get_region()
		if region.nodes[region.active_node].has("mentor"):
			var sample := BattleState.new()
			sample.node_kind = region.node_mode(region.active_node)
			var cfg := run.place_region_enemies(run.battle_config(), map) if sample.node_kind != "event" else {"enemies": []}
			sample.setup(map, cfg, run.seed, run.battle_index, run.build_deploy_units(deploy_uids), {}, {}, [])
			var data: Dictionary = region.nodes[region.active_node]["mentor"]
			var point: Array = data["cell"]
			sample.food_cells = map.get("food_cells", []).duplicate()
			map["mentor_cell"] = Vector2i(point[0], point[1]) if point[0] >= 0 else SkillMentor.choose_cell(sample, deploy_positions)
		else:
			map["mentor_cell"] = Vector2i(-1, -1)
	map["extraction_cells"] = BattleState.extraction_area(map) if int(run.battle_config().get("boss_index", -1)) < 0 else []
	board.set_map_preview(map, deploy_enemies + deploy_players)
	board.selected_uid = deploy_selected_uid
	if start_button != null:
		start_button.disabled = not Deployment.valid(map, deploy_enemies, deploy_players, deploy_positions)
	if start_button != null:
		start_button.text = "开始战斗（已选 %d/%d）" % [deploy_uids.size(), Balance.DEPLOY_LIMIT]
	mod_count_label.text = "剩余改造次数：%d / %d" % [maxi(0, run.mod_points() - mod_used), run.mod_points()]
	for button in mod_buttons.values():
		(button as Button).disabled = run.mod_points() <= 0 or mod_used >= run.mod_points()
	var lethal := int(map.get("lethal_count", 0))
	var obstacle_count: int = (map.get("obstacle_cells", []) as Array).size()
	hint_label.text = hint_label.text if hint_label.text != "" else "致死地形 %d 格｜障碍 %d 格（种子可复现）" % [lethal, obstacle_count]


func _preview_units(run: RunState) -> Array:
	var units: Array = []
	if run.region_mode:
		var region = run.get_region()
		var saved: BattleState = region.load_battle(region.active_node)
		if saved != null:
			var cfg := run.place_region_enemies(run.battle_config(), map)
			var restored: BattleState = region.resume_node(region.active_node, [], cfg)
			return restored.alive_units("enemy") if restored != null else []
		if region.node_mode(region.active_node) == "event":
			return []
	var cfg := run.place_region_enemies(run.battle_config(), map)
	var index := 0
	for pair in cfg.get("enemies", []):
		var unit := CombatUnit.make(String(pair[0]), "enemy", 100 + index)
		BattleDB.configure_enemy(unit, run.seed, run.battle_index, index, index == int(cfg.get("boss_index", -1)))
		var bonus := int(cfg.get("enemy_level_bonus", 0))
		if bonus > 0:
			unit.enemy_level += bonus
			unit.combat_level = unit.enemy_level
			unit.skills = BattleDB.enemy_skills_for_level(unit.species_id, unit.enemy_level)
			unit.max_hp = MonsterProgression.enemy_max_hp(unit.species_id, unit.enemy_level) + (Balance.BOSS_HP_BONUS if unit.is_boss else 0)
			unit.hp = unit.max_hp
		unit.set_corrupted(bool(cfg.get("corrupted", false)))
		unit.reward_carrier = unit.uid == int(map.get("carrier_uid", -1)) and not unit.is_boss
		unit.cell = pair[1]
		units.append(unit)
		index += 1
	return units


func _on_start() -> void:
	if not Deployment.valid(map, deploy_enemies, deploy_players, deploy_positions):
		hint_label.text = "无法开战：请为全员选择互不重叠的合法部署格。"
		return
	app.begin_battle(deploy_uids, map)


func _deploy_click(cell: Vector2i) -> void:
	var occupant: CombatUnit = null
	var selected: CombatUnit = null
	for unit in deploy_players:
		if unit.cell == cell:
			occupant = unit
		if unit.uid == deploy_selected_uid:
			selected = unit
	if selected == null or (occupant != null and occupant.uid == selected.uid):
		if occupant != null:
			deploy_selected_uid = occupant.uid
			board.selected_uid = occupant.uid
			board.queue_redraw()
			hint_label.text = "已选%s：点击蓝框格放置，点击我方单位交换。" % occupant.display_name
		return
	if not (map["deploy_area"] as Array).has(cell) or not Deployment.legal(map, deploy_enemies, selected, cell):
		hint_label.text = "该格不在部署区或此单位无法站立。"
		return
	if occupant != null:
		if not Deployment.legal(map, deploy_enemies, occupant, selected.cell):
			hint_label.text = "交换后有单位无法站立，不能交换。"
			return
		app.run.preview_deploy_positions[occupant.uid] = selected.cell
	app.run.preview_deploy_positions[selected.uid] = cell
	deploy_selected_uid = 0
	_refresh()
	app.autosave()
