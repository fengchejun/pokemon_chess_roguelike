extends SceneTree

## 正常三只初始队伍、零额外资金的可复现交易样本；不是战斗平衡结论。
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for seed_value in [4242, 4243, 4244]:
		var app = load("res://scripts/main.gd").new()
		app.autosave_enabled = false
		root.add_child(app)
		app.run = RunState.new_run(seed_value, CollectionState.defaults().select_records([1, 2, 3]))
		app.run.region_mode = true
		app.run.choose_floor_theme(String(app.run.offered_floor_themes[0]))
		var region = app.run.get_region()
		var id := "event_1" if region.nodes["event_1"].has("merchant") else "event_2"
		# 路线夹具仅解锁商人区，队伍生命、食物和资金使用正常初值。
		region.nodes[id]["unlocked"] = true
		app.run.region_data = region.to_dict()
		app.enter_region_node(id)
		app.show_preview([1, 2, 3])
		app.current_screen._on_start()
		var state: BattleState = app.current_screen.state
		var trainer := state.unit_by_uid(Balance.TRAINER_UID)
		while not state.ended and GridSpec.manhattan(trainer.cell, state.merchant["cell"]) != 1:
			for ally in state.alive_units("player"):
				if ally.is_trainer:
					continue
				for cell in state.move_options(ally):
					if GridSpec.manhattan(cell, state.merchant["cell"]) > 2:
						state.move_unit(ally, cell)
						break
			for cell in state.move_options(trainer):
				if GridSpec.manhattan(cell, state.merchant["cell"]) == 1:
					state.move_unit(trainer, cell)
					break
			if GridSpec.manhattan(trainer.cell, state.merchant["cell"]) != 1:
				state.begin_enemy_phase()
				while not state.enemy_phase_finished():
					state.step_enemy_phase()
				state.end_enemy_phase()
		var food_sale: Dictionary = app.merchant_trade(state, "food", "basic", 1)
		var monster_sale: Dictionary = app.merchant_trade(state, "monster", str(app.run.carried[2]["uid"]))
		var potion: Dictionary = app.merchant_trade(state, "buy", "potion")
		var aid: Dictionary = app.merchant_trade(state, "buy", "capture_aid")
		print("NORMAL_MERCHANT_SAMPLE %s" % JSON.stringify({"seed": seed_value, "round": state.round, "food_sale": food_sale["ok"], "monster_sale": monster_sale["ok"], "potion": potion["ok"], "aid": aid["ok"], "balance": app.run.essence, "food": app.run.total_food(), "party": app.run.carried.size()}))
		app.queue_free()
		await process_frame
	quit()
