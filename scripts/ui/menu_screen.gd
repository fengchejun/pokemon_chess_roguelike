extends Control

var app = null
var help_box: PanelContainer = null

const HELP_TEXT := "流程：编成（出战名单 6 只、每场勾选 1 至 3 只作战）→ 地图预览与可选改造 → 战斗 → 战后结算 → 下一场。\n" \
	+ "属性克制暂时关闭：七种元素仍影响技能、状态与地形反应，直接伤害不按属性增减。\n" \
	+ "地形：浅水在双方行动阶段交接时赋予浸湿；草丛、藤蔓和树木可被点燃；水面蒸汽禁止站在其中的单位施法。易碎地面可塌陷；深水与深坑可造成坠落。\n" \
	+ "行动：每只宝可梦每回合 1 次移动 + 1 次技能；训练家每回合 1 次捕获。第 %d 回合结束后野生逃离。\n" \
	+ "消耗品：战后取得三选一卡，可留在本局背包；每场在地图预览页最多使用一张，点击即消耗。地貌卡刷新地图并使对应地形比旧图更多，改造工具提供两次手动改造。\n" \
	+ "捕获：训练家周围八格每回合可尝试 1 次；整备页可分别启用半血保证捕获与捕获后原地转阵营。默认使用 v2 概率判定与离场处理。\n" \
	+ "战损：宝可梦倒下进入濒死；训练家倒下则整局立即失败，本场未收容的捕获和奖励失效，需重新开始。\n" \
	+ "冒险：一次冒险＝从开始战斗到回到基地。战后恢复：训练家每次冒险前回满；出战过的宝可梦冒险结束恢复 30%%，留守基地的成员与仓库回满 100%%；每 %d 场进入补给点。\n" \
	+ "永久收藏：本局结束时携带队伍与仓库里的怪物进入收藏；新局从收藏中选三只开局。\n" \
	+ "威胁预告：默认关闭，可在战斗中打开；红色骷髅表示致死威胁。"


func _ready() -> void:
	name = "MenuScreen"
	UIKit.fill_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var column := UIKit.vbox(12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)
	column.add_child(UIKit.title("宝可梦战棋肉鸽", 44))
	var subtitle := UIKit.label("濒死与基地休养 · 七属性 · 两种环境卡模式", 18, UIKit.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	column.add_child(spacer)
	var buttons := UIKit.vbox(10)
	buttons.custom_minimum_size = Vector2(340, 0)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(buttons)
	var new_button := UIKit.button("新的一局")
	new_button.name = "NewRunButton"
	new_button.pressed.connect(_on_new_run)
	buttons.add_child(new_button)
	var continue_button := UIKit.button("继续上一局")
	continue_button.name = "ContinueButton"
	continue_button.disabled = not SaveSystem.has_save()
	continue_button.pressed.connect(_on_continue)
	buttons.add_child(continue_button)
	var stats_button := UIKit.button("技能使用统计")
	stats_button.name = "SkillStatsButton"
	stats_button.pressed.connect(func() -> void: app.show_skill_stats())
	buttons.add_child(stats_button)
	var help_button := UIKit.button("玩法说明")
	help_button.name = "HelpButton"
	help_button.pressed.connect(_on_help)
	buttons.add_child(help_button)
	var quit_button := UIKit.button("退出游戏")
	quit_button.pressed.connect(func() -> void: app.quit_game())
	buttons.add_child(quit_button)
	help_box = UIKit.panel(UIKit.PANEL)
	help_box.name = "HelpBox"
	help_box.visible = false
	column.add_child(help_box)
	help_box.add_child(UIKit.wrapped(HELP_TEXT % [Balance.MAX_ROUNDS, Balance.SUPPLY_INTERVAL], 14, UIKit.TEXT))


func _on_new_run() -> void:
	app.start_new_run()


func _on_continue() -> void:
	app.continue_run()


func _on_help() -> void:
	help_box.visible = not help_box.visible
