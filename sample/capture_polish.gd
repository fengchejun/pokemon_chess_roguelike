extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1280,720)
	RenderingServer.set_default_clear_color(Color("11111b"))
	var catalogue = preload("res://sample/unit_catalogue.gd").new()
	catalogue.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(catalogue)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://sample/units-complete.png")
	catalogue.queue_free()
	await process_frame
	var board := BoardView.new()
	board.position = Vector2(200,64)
	board.biome = "grass"
	board.terrain.resize(64)
	board.terrain.fill(TerrainDB.PLAIN)
	var ids := ["trainer","rock_starter","electric_wild1","grass_starter","grass_wild2","fire_wild1"]
	var positions := [Vector2i(1,1),Vector2i(3,1),Vector2i(5,2),Vector2i(6,5),Vector2i(3,3),Vector2i(6,1)]
	for i in ids.size():
		var unit := CombatUnit.make(ids[i],"enemy" if i==4 else "player",i+1)
		unit.cell = positions[i]
		board.units.append(unit)
	board.terrain[GridSpec.index(Vector2i(0,4))] = TerrainDB.TREE
	board.terrain[GridSpec.index(Vector2i(1,5))] = TerrainDB.OBSTACLE
	board.pending_casts = [{"uid":5,"side":"enemy","skill_id":"fire_burst","cells":[Vector2i(3,3)],"due_round":2},{"uid":4,"side":"player","skill_id":"herbal_heal","cells":[Vector2i(6,5)],"due_round":2}]
	board.selected_uid = 2
	root.add_child(board)
	board.set_process(false)
	var label := Label.new()
	label.text = "吟唱范围提示 · 红橙危险区 / 绿色治疗区\n完整受影响格预警，保留地形纹理与角色可读性"
	label.position = Vector2(22,12)
	label.add_theme_font_override("font",UIKit.font())
	label.add_theme_font_size_override("font_size",19)
	root.add_child(label)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://sample/channel-warning.png")
	print("POLISH_CAPTURED species=",SpeciesDB.SPECIES.size())
	quit()
