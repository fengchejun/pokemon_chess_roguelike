extends Control

var app = null
var help_box: PanelContainer = null

const HELP_TEXT := "流程：编成（出战名单 6 只、每场勾选 1 至 3 只作战）→ 地图预览与改造（默认 2 次）→ 战斗 → 战后结算 → 下一场。\n" \
	+ "属性克制：火克草、草克岩、岩克电、电克水、水克火；克制 +1、逆克制 −1（最低 1），只作用于直接伤害。\n" \
	+ "地形：平地、水面、深水、草丛、障碍、熔岩。深水与熔岩被推入即倒下（我方濒死、野生淘汰）；障碍耐久 2，可被碎岩或推击碰撞破坏。\n" \
	+ "草丛隐蔽：草丛中的单位不能被 2 格以外的远程单体技能选中，射线与近战不受影响。\n" \
	+ "行动：每只宝可梦每回合 1 次移动 + 1 次技能；训练家每回合 1 次捕获。第 %d 回合结束后野生逃离。\n" \
	+ "环境卡：每场战斗前在地图预览界面从五张中任选两张生效（增益只对我方）。\n" \
	+ "捕获：概率判定，目标生命越低成功率越高；训练家在 2 格内每回合可尝试 1 次；名单满员时战后可选替换或放入仓库。\n" \
	+ "战损：战斗中倒下进入濒死（无永久死亡，留守一个冒险周期后回满）；战斗失败（训练家倒下）时不结算本场经验、出战宝可梦生命减半并退回基地（捕获保留）。\n" \
	+ "冒险：一次冒险＝从开始战斗到回到基地。战后恢复：训练家每次冒险前回满；出战过的宝可梦冒险结束恢复 30%%，留守基地的成员与仓库回满 100%%；每 %d 场进入补给点。\n" \
	+ "威胁预告：敌方下一步动作可以预读，红色骷髅表示致死威胁。"


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
	var subtitle := UIKit.label("濒死与基地休养 · 属性克制 · 六类地形 · 环境卡构筑", 18, UIKit.TEXT_DIM)
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
