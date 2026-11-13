extends RefCounted

func run(t: TestContext) -> void:
	t.begin("技能悬停血条预览与真实伤害一致")
	var state := TestScenario.make_state(["grass_starter"], [["rock_wild1", Vector2i(2, 3)]])
	var caster := state.unit_by_uid(1)
	var target := state.unit_by_uid(100)
	caster.cell = Vector2i(1, 3)
	caster.skills = ["drain"]
	target.max_hp = 100
	target.hp = 100
	var screen = load("res://scripts/ui/battle_screen.gd").new()
	screen.state = state
	screen.board = BoardView.new()
	screen.hint_label = Label.new()
	screen.skill_box = VBoxContainer.new()
	screen.add_child(screen.board)
	screen.add_child(screen.hint_label)
	screen.add_child(screen.skill_box)
	screen.selected_uid = caster.uid
	screen.aim_skill = "drain"
	screen.aim_entries = state.skill_targets(caster, "drain")
	screen._on_board_hovered(target.cell)
	var predicted := int(screen.board.damage_preview.get(target.uid, 0))
	t.check(predicted > 0, "技能悬停敌方接入血条预计扣血")
	t.eq(target.hp, 100, "悬停不会真正扣血")
	var interval: Vector2 = screen.board.damage_preview_interval(target)
	t.approx(interval.x, float(100 - predicted) / 100, "高亮从预计剩余血量开始")
	t.approx(interval.y, 1.0, "高亮到当前血量结束")
	var actual := state.clone()
	actual.cast_skill(actual.unit_by_uid(1), "drain", screen.aim_entries[0])
	t.eq(100 - actual.unit_by_uid(100).hp, predicted, "预览等于实际生命损失")
	screen._on_board_hovered(Vector2i(-1, -1))
	t.check(screen.board.damage_preview.is_empty(), "移出棋盘清除血条预览")
	screen._on_board_hovered(target.cell)
	screen._clear_aim()
	t.check(screen.board.damage_preview.is_empty(), "取消技能清除血条预览")
	var entry := {"type": "unit", "unit": target.uid, "cell": target.cell}
	target.shield_hp = 1000
	var shielded := state.preview_skill(caster, "drain", entry)
	t.check(not shielded.get("hp_damage", {}).has(target.uid), "全额护盾吸收不错误标出扣血")
	target.shield_hp = 0
	target.hp = 1
	var lethal := state.preview_skill(caster, "drain", entry)
	screen.board.damage_preview = lethal.get("hp_damage", {})
	t.eq(screen.board.damage_preview.get(target.uid), 1, "致死预览限制到剩余生命")
	t.approx(screen.board.damage_preview_interval(target).x, 0, "预计击杀高亮全部剩余血条")
	caster.skills.append("fire_burst")
	target.hp = 100
	target.cell = Vector2i(3, 3)
	var channel := state.preview_skill(caster, "fire_burst", {"type": "cell", "cell": target.cell})
	t.check(int(channel.get("hp_damage", {}).get(target.uid, 0)) > 0, "吟唱技能按当前站位预估释放伤害")
	t.eq(target.hp, 100, "吟唱预估也不提前扣血")
	t.check(state.pending_casts.is_empty(), "悬停不生成真实吟唱任务")
	screen.free()
	t.finish()
