extends Control


func _on_start_pressed() -> void:
	RunManager.start_new_run()
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _on_preview_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/board_preview.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
