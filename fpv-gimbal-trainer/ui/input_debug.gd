extends Control
## Debug view: live raw/processed value of every axis of the selected device.
## Move a stick on the TBS Tango: the axis that moves most is highlighted
## ("<< moving") so you can identify it, then assign it to pan/tilt/roll.

const CH: Array[String] = ["pan", "tilt", "roll"]

var _device_option: OptionButton
var _status: Label
var _rows: Array[Dictionary] = []
var _channel_labels := {}
var _peak := {}  # axis -> max |delta| since movement, for highlighting
var _last_vals := {}


func _ready() -> void:
	_build_ui()
	ControllerInput.devices_changed.connect(_on_devices_changed)
	ControllerInput.config_loaded.connect(func(_p): _sync_from_config())
	_on_devices_changed(ControllerInput.get_devices())


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_label("Device:"))
	_device_option = OptionButton.new()
	_device_option.custom_minimum_size.x = 360
	_device_option.item_selected.connect(_on_device_selected)
	top.add_child(_device_option)
	var save := Button.new()
	save.text = "Save config"
	save.pressed.connect(func(): _status.text = "Save: %s" % error_string(ControllerInput.save_config()))
	top.add_child(save)
	var load_btn := Button.new()
	load_btn.text = "Load config"
	load_btn.pressed.connect(func(): _status.text = "Load: %s" % error_string(ControllerInput.load_config()))
	top.add_child(load_btn)
	_status = _label("Esc: menu")
	top.add_child(_status)

	var ch_row := HBoxContainer.new()
	root.add_child(ch_row)
	for c in CH:
		var l := _label("%s: 0.00" % c)
		l.custom_minimum_size.x = 160
		_channel_labels[c] = l
		ch_row.add_child(l)

	root.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 12)
	root.add_child(grid)
	for h in ["Axis", "Raw", "Bar", "Processed", "Deadzone", "Expo", "Inv", "Channel", ""]:
		grid.add_child(_label(h))

	for a in ControllerInput.AXIS_COUNT:
		grid.add_child(_label("Axis %d" % a))
		var raw := _label("+0.000")
		raw.custom_minimum_size.x = 70
		grid.add_child(raw)
		var bar := ProgressBar.new()
		bar.min_value = -1.0
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 18)
		grid.add_child(bar)
		var proc := _label("+0.000")
		proc.custom_minimum_size.x = 70
		grid.add_child(proc)
		var dz := _slider(0.0, 0.5, 0.01, a, "deadzone")
		grid.add_child(dz)
		var ex := _slider(0.0, 1.0, 0.01, a, "expo")
		grid.add_child(ex)
		var inv := CheckBox.new()
		inv.toggled.connect(func(on): ControllerInput.set_invert(a, on))
		grid.add_child(inv)
		var opt := OptionButton.new()
		opt.add_item("-", 0)
		for i in CH.size():
			opt.add_item(CH[i], i + 1)
		opt.item_selected.connect(_on_channel_selected.bind(a, opt))
		grid.add_child(opt)
		var mark := _label("")
		grid.add_child(mark)
		_rows.append({"raw": raw, "bar": bar, "proc": proc, "dz": dz, "ex": ex, "inv": inv, "opt": opt, "mark": mark})
	_sync_from_config()


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _slider(lo: float, hi: float, step: float, axis: int, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(110, 18)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v):
		if key == "deadzone":
			ControllerInput.set_deadzone(axis, v)
		else:
			ControllerInput.set_expo(axis, v))
	return s


func _sync_from_config() -> void:
	if _rows.is_empty():
		return
	for a in _rows.size():
		var s: Dictionary = ControllerInput.axis_settings[a]
		var r := _rows[a]
		r.dz.set_value_no_signal(s.deadzone)
		r.ex.set_value_no_signal(s.expo)
		r.inv.set_pressed_no_signal(s.invert)
		var idx := 0
		for i in CH.size():
			if ControllerInput.mapping[CH[i]] == a:
				idx = i + 1
		r.opt.select(r.opt.get_item_index(idx))


func _on_channel_selected(index: int, axis: int, opt: OptionButton) -> void:
	var id := opt.get_item_id(index)
	for c in CH:  # free this axis and the chosen channel
		if ControllerInput.mapping[c] == axis:
			ControllerInput.map_channel(c, -1)
	if id > 0:
		ControllerInput.map_channel(CH[id - 1], axis)
	_sync_from_config()


func _on_devices_changed(devices: Array) -> void:
	_device_option.clear()
	for d in devices:
		_device_option.add_item("#%d  %s" % [d.id, d.name], d.id)
	if devices.is_empty():
		_device_option.add_item("(no joystick detected)", -1)
	else:
		_device_option.select(_device_option.get_item_index(ControllerInput.active_device))


func _on_device_selected(index: int) -> void:
	ControllerInput.set_active_device(_device_option.get_item_id(index))


func _process(_delta: float) -> void:
	var dev := ControllerInput.active_device
	var best := -1
	var best_delta := 0.03
	for a in _rows.size():
		var raw := ControllerInput.get_raw(a)
		var d := absf(raw - _last_vals.get(a, raw))
		_last_vals[a] = raw
		_peak[a] = maxf(_peak.get(a, 0.0) * 0.9, d)
		if _peak[a] > best_delta:
			best_delta = _peak[a]
			best = a
		var r := _rows[a]
		r.raw.text = "%+.3f" % raw
		r.bar.value = raw
		r.proc.text = "%+.3f" % ControllerInput.process_axis(a, raw)
	for a in _rows.size():
		_rows[a].mark.text = "<< moving" if a == best and dev >= 0 else ""
	_channel_labels.pan.text = "pan: %+.2f" % ControllerInput.pan_input
	_channel_labels.tilt.text = "tilt: %+.2f" % ControllerInput.tilt_input
	_channel_labels.roll.text = "roll: %+.2f" % ControllerInput.roll_input


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
