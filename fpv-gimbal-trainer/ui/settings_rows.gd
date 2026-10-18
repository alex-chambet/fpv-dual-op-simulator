class_name SettingsRows
extends VBoxContainer
## The rows the settings panels are made of (GraphicsPanel, SoundPanel): a heading, a greyed note,
## and a labelled control - a dropdown, a switch or a slider with its value beside it. Kept in one
## place so Paramètres and the pause menu look the same wherever a setting is shown.

const LABEL_WIDTH := 250.0


func _heading(t: String) -> void:
	var l := Label.new()
	l.text = t
	if get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		add_child(gap)
	add_child(Neon.caps(l, 20))


func _note(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 560
	l.add_theme_color_override("font_color", Neon.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 15)
	add_child(l)


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(l)
	return row


func _opt(label: String, items: Array, selected: int, on_change: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in items:
		o.add_item(str(t))
	o.select(clampi(selected, 0, items.size() - 1))
	o.item_selected.connect(on_change)
	_row(label).add_child(o)
	return o


func _check(label: String, on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(on_change)
	var row := _row(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(c)
	return c


func _slider(label: String, lo: float, hi: float, step: float, value: float, fmt: Callable,
		on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size.x = 80
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = str(fmt.call(value))
	s.value_changed.connect(func(x):
		v.text = str(fmt.call(x))
		on_change.call(x))
	var row := _row(label)
	row.add_child(s)
	row.add_child(v)
	return s
