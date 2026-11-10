extends Button

var feedback: Tween

func _ready() -> void:
	mouse_entered.connect(_flash.bind(Color("f9e2af")))
	mouse_exited.connect(_flash.bind(Color.WHITE))
	focus_entered.connect(_flash.bind(Color("f9e2af")))
	focus_exited.connect(_flash.bind(Color.WHITE))

func _flash(tint: Color) -> void:
	if feedback != null:
		feedback.kill()
	feedback = create_tween()
	feedback.tween_property(self, "self_modulate", tint, 0.08)

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var text := Label.new()
	text.text = for_text
	text.custom_minimum_size.x = 240
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(text)
	return panel
