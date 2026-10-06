extends Node
## Autoload "ControllerInput".
## Reads raw joystick axes, applies per-axis deadzone / expo / invert, and maps
## physical axes to 3 logical channels: pan_input, tilt_input, roll_input (-1..1).

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
	channels_updated.emit(pan_input, tilt_input, roll_input)


# --- Devices -----------------------------------------------------------------

func get_devices() -> Array:
	var out := []
	for id in Input.get_connected_joypads():
		out.append({"id": id, "name": Input.get_joy_name(id), "guid": Input.get_joy_guid(id)})
	return out


func set_active_device(device_id: int) -> void:
	active_device = device_id
	active_device_name = Input.get_joy_name(device_id) if device_id >= 0 else ""


func _refresh_devices() -> void:
	var devices := get_devices()
	for d in devices:
		print("[ControllerInput] #%d  %s  (%s)" % [d.id, d.name, d.guid])
	if devices.is_empty():
		print("[ControllerInput] no joystick detected")
		active_device = -1
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
	devices_changed.emit(devices)


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
func process_axis(axis: int, raw: float) -> float:
	var s: Dictionary = axis_settings[axis]
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


func set_deadzone(axis: int, value: float) -> void:
	axis_settings[axis].deadzone = clampf(value, 0.0, 0.99)


func set_expo(axis: int, value: float) -> void:
	axis_settings[axis].expo = clampf(value, 0.0, 1.0)


func set_invert(axis: int, value: bool) -> void:
	axis_settings[axis].invert = value


func map_channel(channel: String, axis: int) -> void:
	if channel in CHANNELS:
		mapping[channel] = axis


# --- Config ------------------------------------------------------------------

func save_config(path: String = CONFIG_PATH) -> Error:
	var axes := {}
	for a in AXIS_COUNT:
		axes[str(a)] = axis_settings[a]
	var data := {
		"version": 1,
		"device_name": active_device_name,
		"mapping": mapping,
		"axes": axes,
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
	config_loaded.emit(path)
	return OK
