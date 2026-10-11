extends SceneTree

const MapGenerator = preload("res://scripts/map_generator.gd")
const Cards = preload("res://scripts/environment_card_system.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var center_grass := 0
	var outer_grass := 0
	var deep_water := 0
	for region_id in MapGenerator.REGIONS.keys():
		for seed_value in 40:
			var layout: Dictionary = MapGenerator.generate(region_id, [], seed_value + 100)
			if not MapGenerator.is_playable(layout) or layout["info"]["region_id"] != region_id:
				_fail("Generated layout is not playable or region metadata is wrong")
				return
			if layout != MapGenerator.generate(region_id, [], seed_value + 100):
				_fail("Same seed and deck produced different maps")
				return
			if layout.get("nest", {}).is_empty() or layout.get("reward", {}).is_empty() or not MapGenerator.is_playable(layout):
				_fail("Nest or accessible reward was missing")
				return
			for y in 8:
				for x in 8:
					var cell := Vector2i(x, y)
					if layout["ground"].get(cell, "ground") == "deep_water":
						deep_water += 1
					if layout["ground"].get(cell, "ground") == "grass":
						if x >= 2 and x <= 5 and y >= 2 and y <= 5:
							center_grass += 1
						else:
							outer_grass += 1
	if deep_water == 0 or center_grass <= outer_grass / 3:
		_fail("Deep water was absent or grass did not favor the center")
		return
	if MapGenerator.is_playable({"ground": {Vector2i(1, 3): "fragile"}, "objects": {}}) or MapGenerator.is_playable({"ground": {}, "objects": {Vector2i(1, 3): {"type": "rock"}}}):
		_fail("Invalid deployment cells were accepted")
		return
	var base_water := 0
	var card_water := 0
	var base_steam := 0
	var combo_steam := 0
	var changed_maps := 0
	for seed_value in 100:
		var base: Dictionary = MapGenerator.generate("forest", [], seed_value + 800)
		var wet: Dictionary = MapGenerator.generate("forest", ["water"], seed_value + 800)
		var combo: Dictionary = MapGenerator.generate("forest", ["water", "fire"], seed_value + 800)
		base_water += base["info"]["counts"]["water"]
		card_water += wet["info"]["counts"]["water"]
		base_steam += base["info"]["counts"]["steam"]
		combo_steam += combo["info"]["counts"]["steam"]
		if base["ground"] != wet["ground"]:
			changed_maps += 1
	if card_water <= base_water or changed_maps < 20 or combo_steam <= base_steam:
		_fail("Cards did not measurably change water or steam generation tendency")
		return
	var run := RunState.new()
	run.run_seed = 456
	var choices: Array[String] = Cards.offer([], 456)
	var chosen_id: String = choices[0]
	run.offered_environment_cards = choices
	if choices.size() != 3 or run.can_start_battle() or run.choose_environment_card("invalid") or not run.choose_environment_card(chosen_id) or run.environment_cards != [chosen_id] or not run.can_start_battle():
		_fail("Card reward selection or run persistence failed")
		return
	var generated: Dictionary = MapGenerator.generate("wetland", run.environment_cards, 1234)
	var battle := BattleState.new(run, generated)
	if battle.map_info["cards"] != run.environment_cards or battle.terrain.ground != generated["ground"] or battle.terrain.objects != generated["objects"]:
		_fail("Battle did not consume the completed generated layout")
		return
	if not RunState.new().environment_cards.is_empty():
		_fail("Fresh run retained environment cards")
		return
	print("STAGE5_ENVIRONMENT_CARDS passed; base water=", base_water, ", water card=", card_water, ", base steam=", base_steam, ", combo steam=", combo_steam, ", changed maps=", changed_maps, ", center grass=", center_grass, ", outer grass=", outer_grass, ", deep water=", deep_water)
	quit(0)


func _fail(message: String) -> void:
	push_error("STAGE5_ENVIRONMENT_CARDS failed: " + message)
	quit(1)
