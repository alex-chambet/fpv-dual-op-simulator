extends Node
## Autoload "ControllerInput".
## Reads raw joystick axes, applies per-axis deadzone / expo / invert, and maps
## physical axes to 3 logical channels: pan_input, tilt_input, roll_input (-1..1).
## A second controller can be assigned to the "pilot" role (FPV drone, 2-player mode): 4 channels
## throttle (0..1), yaw, pitch, roll (-1..1), with its own mapping and axis settings.

signal devices_changed(devices: Array)
signal axis_raw(device: int, axis: int, value: float)
signal channels_updated(pan: float, tilt: float, roll: float)
signal config_saved(path: String)
signal config_loaded(path: String)

const CONFIG_PATH := "user://controller_config.json"
const CHANNELS: Array[String] = ["pan", "tilt", "roll"]
const AXIS_COUNT := JOY_AXIS_MAX
const DEFAULT_DEADZONE := 0.05
const DEFAULT_EXPO := 0.0
## Raw change below this threshold does not emit axis_raw.
const RAW_EPSILON := 0.0005

var pan_input := 0.0
var tilt_input := 0.0
var roll_input := 0.0

## --- Pilot role (second controller) ---
const PILOT_CHANNELS: Array[String] = ["throttle", "yaw", "pitch", "roll"]
## throttle 0..1, yaw / pitch / roll -1..1 (pitch + = stick forward, yaw + = right, roll + = right).
var pilot_inputs := [0.0, 0.0, 0.0, 0.0]
var pilot_device := -1
var pilot_device_name := ""
## Default AETR order of an EdgeTX / OpenTX radio used as a USB joystick (check it in the controller setup).
var pilot_mapping := {"throttle": 2, "yaw": 3, "pitch": 1, "roll": 0}
var pilot_axis_settings := {}

## Device used for the logical channels (Godot device id).
var active_device := -1
## Name of the device stored in the config, used to re-select it on next launch.
var active_device_name := ""

## channel name -> physical axis index (-1 = unmapped)
var mapping := {"pan": -1, "tilt": -1, "roll": -1}
## axis index -> {"deadzone": float, "expo": float, "invert": bool}
var axis_settings := {}

var _last_raw := {}  # "device:axis" -> float


func _ready() -> void:
	for a in AXIS_COUNT:
		axis_settings[a] = _default_axis_settings()
		pilot_axis_settings[a] = _default_axis_settings()
	pilot_axis_settings[1].invert = true  # stick forward = axis negative on most devices
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	load_config()
	_refresh_devices()


func _process(_delta: float) -> void:
	for device in Input.get_connected_joypads():
		for axis in AXIS_COUNT:
			var v := Input.get_joy_axis(device, axis)
			var key := "%d:%d" % [device, axis]
			if absf(v - _last_raw.get(key, 0.0)) > RAW_EPSILON:
				_last_raw[key] = v
				axis_raw.emit(device, axis, v)

	pan_input = get_channel_value("pan")
	tilt_input = get_channel_value("tilt")
	roll_input = get_channel_value("roll")
	_update_pilot()
	channels_updated.emit(pan_input, tilt_input, roll_input)


# --- Pilot role ----------------------------------------------------------------

func has_pilot_device() -> bool:
	return pilot_device >= 0 and Input.get_connected_joypads().has(pilot_device)


func _update_pilot() -> void:
	if not has_pilot_device():
		pilot_inputs = [0.0, 0.0, 0.0, 0.0]  # no controller: throttle at minimum
		return
	var vals := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var axis: int = pilot_mapping.get(PILOT_CHANNELS[i], -1)
		if axis < 0 or axis >= AXIS_COUNT:
			vals[i] = 0.0
			continue
		var raw := Input.get_joy_axis(pilot_device, axis)
		if i == 0:  # throttle does not self-centre: no dead zone, no expo
			var t := -raw if pilot_axis_settings[axis].invert else raw
			vals[i] = clampf((t + 1.0) * 0.5, 0.0, 1.0)
		else:
			vals[i] = process_axis(axis, raw, "pilot")
	pilot_inputs = vals


# --- Devices -----------------------------------------------------------------

func get_devices() -> Array:
	var out := []
	for id in Input.get_connected_joypads():
		out.append({"id": id, "name": Input.get_joy_name(id), "guid": Input.get_joy_guid(id)})
	return out


func set_active_device(device_id: int) -> void:
	active_device = device_id
	active_device_name = Input.get_joy_name(device_id) if device_id >= 0 else ""


func set_pilot_device(device_id: int) -> void:
	pilot_device = device_id
	pilot_device_name = Input.get_joy_name(device_id) if device_id >= 0 else ""


## Device and settings of a role ("gimbal" or "pilot"): generic access for the setup screen.
func device_of(role: String) -> int:
	return pilot_device if role == "pilot" else active_device


func set_device_of(role: String, device_id: int) -> void:
	if role == "pilot":
		set_pilot_device(device_id)
	else:
		set_active_device(device_id)


func channels_of(role: String) -> Array[String]:
	return PILOT_CHANNELS if role == "pilot" else CHANNELS


func mapping_of(role: String) -> Dictionary:
	return pilot_mapping if role == "pilot" else mapping


func settings_of(role: String) -> Dictionary:
	return pilot_axis_settings if role == "pilot" else axis_settings


func _refresh_devices() -> void:
	var devices := get_devices()
	for d in devices:
		print("[ControllerInput] #%d  %s  (%s)" % [d.id, d.name, d.guid])
	if devices.is_empty():
		print("[ControllerInput] no joystick detected")
		active_device = -1
		pilot_device = -1
	else:
		var found := false
		if active_device_name != "":
			for d in devices:
				if d.name == active_device_name:
					active_device = d.id
					found = true
					break
		if not found and not devices.any(func(d): return d.id == active_device):
			set_active_device(devices[0].id)
	_assign_pilot(devices)
	devices_changed.emit(devices)


## The pilot controller: the one saved by name, else the first controller that is not the gimbal one.
func _assign_pilot(devices: Array) -> void:
	if devices.is_empty():
		return
	var found := false
	if pilot_device_name != "":
		for d in devices:
			if d.name == pilot_device_name and d.id != active_device:
				pilot_device = d.id
				found = true
				break
	if found:
		return
	if devices.any(func(d): return d.id == pilot_device and d.id != active_device):
		return
	pilot_device = -1
	for d in devices:
		if d.id != active_device:
			pilot_device = d.id
			break


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_devices()


# --- Axis processing ---------------------------------------------------------

func _default_axis_settings() -> Dictionary:
	return {"deadzone": DEFAULT_DEADZONE, "expo": DEFAULT_EXPO, "invert": false}


func get_raw(axis: int, device: int = -1) -> float:
	if device < 0:
		device = active_device
	if device < 0:
		return 0.0
	return Input.get_joy_axis(device, axis)


## Deadzone (rescaled so output starts at 0 at the edge) then expo curve:
## out = sign(x) * (expo * |x|^3 + (1 - expo) * |x|), expo in 0..1.
func process_axis(axis: int, raw: float, role := "gimbal") -> float:
	var s: Dictionary = settings_of(role)[axis]
	var dz: float = clampf(s.deadzone, 0.0, 0.99)
	var a := absf(raw)
	if a <= dz:
		return 0.0
	a = (a - dz) / (1.0 - dz)
	var e: float = clampf(s.expo, 0.0, 1.0)
	a = e * a * a * a + (1.0 - e) * a
	var v := signf(raw) * a
	return -v if s.invert else v


func get_processed(axis: int, device: int = -1) -> float:
	return process_axis(axis, get_raw(axis, device))


func get_channel_value(channel: String) -> float:
	var axis: int = mapping.get(channel, -1)
	if axis < 0 or axis >= AXIS_COUNT:
		return 0.0
	return get_processed(axis)


func set_deadzone(axis: int, value: float, role := "gimbal") -> void:
	settings_of(role)[axis].deadzone = clampf(value, 0.0, 0.99)


func set_expo(axis: int, value: float, role := "gimbal") -> void:
	settings_of(role)[axis].expo = clampf(value, 0.0, 1.0)


func set_invert(axis: int, value: bool, role := "gimbal") -> void:
	settings_of(role)[axis].invert = value


func map_channel(channel: String, axis: int, role := "gimbal") -> void:
	if channel in channels_of(role):
		mapping_of(role)[channel] = axis


# --- Config ------------------------------------------------------------------

func save_config(path: String = CONFIG_PATH) -> Error:
	var axes := {}
	for a in AXIS_COUNT:
		axes[str(a)] = axis_settings[a]
	var pilot_axes := {}
	for a in AXIS_COUNT:
		pilot_axes[str(a)] = pilot_axis_settings[a]
	var data := {
		"version": 1,
		"device_name": active_device_name,
		"mapping": mapping,
		"axes": axes,
		"pilot": {"device_name": pilot_device_name, "mapping": pilot_mapping, "axes": pilot_axes},
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ControllerInput: cannot write %s" % path)
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	config_saved.emit(path)
	return OK


func load_config(path: String = CONFIG_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ControllerInput: invalid config %s" % path)
		return ERR_PARSE_ERROR
	active_device_name = str(parsed.get("device_name", ""))
	var m: Dictionary = parsed.get("mapping", {})
	for c in CHANNELS:
		mapping[c] = int(m.get(c, -1))
	var axes: Dictionary = parsed.get("axes", {})
	for a in AXIS_COUNT:
		var s: Dictionary = axes.get(str(a), {})
		axis_settings[a] = {
			"deadzone": float(s.get("deadzone", DEFAULT_DEADZONE)),
			"expo": float(s.get("expo", DEFAULT_EXPO)),
			"invert": bool(s.get("invert", false)),
		}
	var pj: Dictionary = parsed.get("pilot", {})
	pilot_device_name = str(pj.get("device_name", ""))
	var pm: Dictionary = pj.get("mapping", {})
	for c in PILOT_CHANNELS:
		pilot_mapping[c] = int(pm.get(c, pilot_mapping[c]))
	var pax: Dictionary = pj.get("axes", {})
	for a in AXIS_COUNT:
		if pax.has(str(a)):
			var s2: Dictionary = pax[str(a)]
			pilot_axis_settings[a] = {
				"deadzone": float(s2.get("deadzone", DEFAULT_DEADZONE)),
				"expo": float(s2.get("expo", DEFAULT_EXPO)),
				"invert": bool(s2.get("invert", false)),
			}
	config_loaded.emit(path)
	return OK
