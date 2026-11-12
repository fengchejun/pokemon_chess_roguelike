extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1280,720)
	RenderingServer.set_default_clear_color(Color("11111b"))
	var board := BoardView.new()
	board.position = Vector2(200,68)
	board.biome = "grass"
	board.terrain.resize(64)
	board.terrain.fill(TerrainDB.PLAIN)
	for cell in [Vector2i(1,2),Vector2i(2,2),Vector2i(3,2),Vector2i(2,3),Vector2i(3,3)]: board.burning_cells[cell] = 3
	for cell in [Vector2i(5,4),Vector2i(6,4),Vector2i(5,5),Vector2i(6,5)]: board.terrain[GridSpec.index(cell)] = TerrainDB.BLUE_FIRE
	var unit := CombatUnit.make("fire_starter","player",1)
	unit.cell = Vector2i(2,3)
	board.units = [unit]
	board.selected_uid = 1
	board.terrain[GridSpec.index(Vector2i(1,5))] = TerrainDB.TREE
	board.terrain[GridSpec.index(Vector2i(4,1))] = TerrainDB.OBSTACLE
	root.add_child(board)
	var label := Label.new()
	label.text = "整格像素火焰 · 动态效果预览\n普通火 / 蓝火 · 交错火焰面 · 保留单位与血条"
	label.position = Vector2(22,12)
	label.add_theme_font_override("font",UIKit.font())
	label.add_theme_font_size_override("font_size",20)
	root.add_child(label)
	board.set_process(false)
	var hashes: Dictionary = {}
	for frame in 8:
		board.fire_clock = frame*0.1+0.001
		board.queue_redraw()
		await process_frame
		await process_frame
		var shot := root.get_texture().get_image()
		hashes[hash(shot.get_data())] = true
		shot.save_png("res://sample/fire-frame-%d.png" % frame)
	print("FIRE_FRAMES unique=",hashes.size())
	if "--interactive" in OS.get_cmdline_user_args():
		board.set_process(true)
		return
	quit(0 if hashes.size()==8 else 1)
