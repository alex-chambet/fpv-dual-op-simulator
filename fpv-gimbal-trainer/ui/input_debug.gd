extends Control
## Debug view: live raw/processed value of every axis of the selected device.
## Move a stick on the TBS Tango: the axis that moves most is highlighted
## ("<< moving") so you can identify it, then assign it to pan/tilt/roll.

## Which controller is being set up: "gimbal" (pan / tilt / roll) or "pilot" (throttle / yaw / pitch / roll).
var _role := "gimbal"
var _ui_root: Control

var _device_option: OptionButton
var _status: Label
var _rows: Array[Dictionary] = []
var _channel_labels := {}
var _peak := {}  # axis -> max |delta| since movement, for highlighting
var _last_vals := {}


func _ready() -> void:
	var bg := Neon.backdrop()
	bg.material.set_shader_parameter("dim", 0.8)
	add_child(bg)
	_build_ui()
	ControllerInput.devices_changed.connect(_on_devices_changed)
	ControllerInput.config_loaded.connect(func(_p): _sync_from_config())
	_on_devices_changed(ControllerInput.get_devices())


func _ch() -> Array[String]:
	return ControllerInput.channels_of(_role)


func _set_role(index: int) -> void:
	_role = "gimbal" if index == 0 else "pilot"
	_rows.clear()
	_channel_labels.clear()
	_last_vals.clear()
	_peak.clear()
	_ui_root.queue_free()
	_build_ui()
	_on_devices_changed(ControllerInput.get_devices())


func _build_ui() -> void:
	var margin := MarginContainer.new()
	_ui_root = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var role_opt := OptionButton.new()
	role_opt.add_item("Gimbal (cadreur)")
	role_opt.add_item("Drone (pilote FPV)")
	role_opt.select(0 if _role == "gimbal" else 1)
	role_opt.item_selected.connect(_set_role)
	top.add_child(role_opt)
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
	for c in _ch():
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
		inv.toggled.connect(func(on): ControllerInput.set_invert(a, on, _role))
		grid.add_child(inv)
		var opt := OptionButton.new()
		opt.add_item("-", 0)
		for i in _ch().size():
			opt.add_item(_ch()[i], i + 1)
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
			ControllerInput.set_deadzone(axis, v, _role)
		else:
			ControllerInput.set_expo(axis, v, _role))
	return s


func _sync_from_config() -> void:
	if _rows.is_empty():
		return
	for a in _rows.size():
		var s: Dictionary = ControllerInput.settings_of(_role)[a]
		var r := _rows[a]
		r.dz.set_value_no_signal(s.deadzone)
		r.ex.set_value_no_signal(s.expo)
		r.inv.set_pressed_no_signal(s.invert)
		var idx := 0
		for i in _ch().size():
			if ControllerInput.mapping_of(_role)[_ch()[i]] == a:
				idx = i + 1
		r.opt.select(r.opt.get_item_index(idx))


func _on_channel_selected(index: int, axis: int, opt: OptionButton) -> void:
	var id := opt.get_item_id(index)
	for c in _ch():  # free this axis and the chosen channel
		if ControllerInput.mapping_of(_role)[c] == axis:
			ControllerInput.map_channel(c, -1, _role)
	if id > 0:
		ControllerInput.map_channel(_ch()[id - 1], axis, _role)
	_sync_from_config()


func _on_devices_changed(devices: Array) -> void:
	_device_option.clear()
	for d in devices:
		var tag := ""
		if d.id == ControllerInput.active_device:
			tag += "  [GIMBAL]"
		if d.id == ControllerInput.pilot_device:
			tag += "  [PILOTE]"
		_device_option.add_item("#%d  %s%s" % [d.id, d.name, tag], d.id)
	if devices.is_empty():
		_device_option.add_item("(no joystick detected)", -1)
	else:
		var cur := ControllerInput.device_of(_role)
		_device_option.select(maxi(_device_option.get_item_index(cur), 0))


func _on_device_selected(index: int) -> void:
	ControllerInput.set_device_of(_role, _device_option.get_item_id(index))
	_on_devices_changed(ControllerInput.get_devices())


func _process(_delta: float) -> void:
	var dev := ControllerInput.device_of(_role)
	var best := -1
	var best_delta := 0.03
	for a in _rows.size():
		var raw := ControllerInput.get_raw(a, dev)
		var d := absf(raw - _last_vals.get(a, raw))
		_last_vals[a] = raw
		_peak[a] = maxf(_peak.get(a, 0.0) * 0.9, d)
		if _peak[a] > best_delta:
			best_delta = _peak[a]
			best = a
		var r := _rows[a]
		r.raw.text = "%+.3f" % raw
		r.bar.value = raw
		r.proc.text = "%+.3f" % ControllerInput.process_axis(a, raw, _role)
	for a in _rows.size():
		_rows[a].mark.text = "<< moving" if a == best and dev >= 0 else ""
	if _role == "gimbal":
		_channel_labels.pan.text = "pan: %+.2f" % ControllerInput.pan_input
		_channel_labels.tilt.text = "tilt: %+.2f" % ControllerInput.tilt_input
		_channel_labels.roll.text = "roll: %+.2f" % ControllerInput.roll_input
	else:
		var pi: Array = ControllerInput.pilot_inputs
		_channel_labels.throttle.text = "throttle: %3.0f%%" % (100.0 * float(pi[0]))
		_channel_labels.yaw.text = "yaw: %+.2f" % float(pi[1])
		_channel_labels.pitch.text = "pitch: %+.2f" % float(pi[2])
		_channel_labels.roll.text = "roll: %+.2f" % float(pi[3])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/settings.tscn")
