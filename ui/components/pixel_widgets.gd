extends RefCounted

static func stat(symbol: String, value: String, description: String, tint: Color = Color("f9e2af")) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.tooltip_text = description
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var fallback := UIKit.label(symbol, 16, tint)
	fallback.name = "Placeholder"
	icon.add_child(fallback)
	icon.draw.connect(func() -> void: fallback.visible = icon.texture == null)
	row.add_child(UIKit.label(value, 16))
	return row

static func health(current: int, maximum: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(144, 24)
	bar.max_value = maxi(maximum, 1)
	bar.value = current
	bar.show_percentage = false
	bar.tooltip_text = "生命值"
	var value := UIKit.label("%d / %d" % [current, maximum], 12)
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(value)
	return bar

static func slot(title: String, count: int, symbol: String, description: String, rarity: Color = Color("a6adc8")) -> Button:
	var button := preload("res://ui/components/pixel_button.gd").new()
	button.custom_minimum_size = Vector2(64, 64)
	button.tooltip_text = title + "\n" + description
	button.clip_contents = true
	var style := preload("res://ui/themes/pixel_theme.gd").box(Color("1e1e2e"), rarity, 4)
	button.add_theme_stylebox_override("normal", style)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(12, 8)
	icon.size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var fallback := UIKit.label(symbol, 24, rarity)
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(fallback)
	icon.draw.connect(func() -> void: fallback.visible = icon.texture == null)
	var amount := UIKit.label(str(count), 12)
	amount.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	amount.position = Vector2(34, 42)
	amount.size = Vector2(26, 18)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(amount)
	return button

static func slot_grid(parent: Control, columns: int = 4) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(columns * 70, 76)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	return grid

static func details(parent: Control) -> Label:
	var card := UIKit.panel()
	parent.add_child(card)
	var text := UIKit.wrapped("悬停或聚焦查看详情", 13)
	text.custom_minimum_size = Vector2(180, 48)
	card.add_child(text)
	return text

static func describe(button: Button, detail: Label) -> void:
	button.mouse_entered.connect(func() -> void: detail.text = button.tooltip_text)
	button.focus_entered.connect(func() -> void: detail.text = button.tooltip_text)
