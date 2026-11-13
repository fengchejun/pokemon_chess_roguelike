extends RefCounted
const Visuals = preload("res://scripts/ui/status_visuals.gd")

func run(t: TestContext) -> void:
	t.begin("异常染色优先级、恢复原色和透明轮廓")
	var unit := CombatUnit.make("fire_wild1", "player", 1)
	t.eq(Visuals.tint(unit).a, 0.0, "健康单位没有遮罩")
	unit.burn_ticks = 2
	var burn := Visuals.tint(unit)
	t.check(burn.r > burn.b and burn.a > 0, "灼烧呈红色")
	unit.paralyzed_ticks = 1
	var paralysis := Visuals.tint(unit)
	t.check(paralysis.g > burn.g, "麻痹优先于灼烧")
	unit.frozen = true
	t.check(Visuals.tint(unit).b > Visuals.tint(unit).r, "冰冻优先呈冰蓝色")
	unit.frozen = false
	unit.paralyzed_ticks = 0
	t.eq(Visuals.tint(unit), burn, "控制解除后显示仍存在的灼烧")
	unit.burn_ticks = 0
	t.eq(Visuals.tint(unit).a, 0.0, "状态全部解除恢复原色")
	var original: AtlasTexture = BoardView.SampleArt.tile(105)
	var source := original.atlas.get_image().get_region(Rect2i(original.region))
	var painted := Visuals.texture(105, burn)
	t.eq(Visuals.texture(105, burn), painted, "缓存相同染色避免逐帧生成")
	var output := painted.get_image()
	var alpha_matches := true
	var changed := false
	for y in source.get_height():
		for x in source.get_width():
			var before := source.get_pixel(x, y)
			var after := output.get_pixel(x, y)
			if absf(before.a - after.a) > 0.005: alpha_matches = false
			if before.a > 0.5 and before != after: changed = true
	t.check(alpha_matches, "染色保留所有像素的透明度")
	t.check(changed, "不透明角色像素确实变色")
	t.finish()
