extends RefCounted
const Iso = preload("res://sample/iso_projection.gd")

func run(t: TestContext) -> void:
	t.begin("旋转棋盘点击、初始阵线、施法朝向与火谷禁水木")
	var board := BoardView.new()
	for cell in GridSpec.all_cells():
		t.eq(board.cell_at(BoardView.cell_center(cell)), cell, "旋转后点击反算")
	t.check(BoardView.cell_center(Vector2i(0, 3)).y > BoardView.cell_center(Vector2i(7, 3)).y, "我方部署边位于下方")
	var actor := CombatUnit.make("fire_starter", "player", 777)
	actor.cell = Vector2i(3, 3)
	var state := BattleState.new()
	state.units = [actor]
	for dir in GridSpec.DIRS4:
		board.face_skill({"uid": actor.uid, "target": {"dir": dir}}, state)
		var delta := BoardView.cell_center(actor.cell + dir) - BoardView.cell_center(actor.cell)
		t.eq(board.facing_right[actor.uid], delta.x > 0, "施法方向决定左右朝向")
	board.units = [actor]
	for seed_value in 24:
		var map := MapGenerator.generate(seed_value, 0, 0, ["water", "rock"], "fire")
		t.eq(map["region"], "火谷", "检查火谷主题")
		t.check(not map["terrain"].has(TerrainDB.WATER) and not map["terrain"].has(TerrainDB.TREE), "环境卡不能重新引入自然水木")
	board.free()

	t.finish()
