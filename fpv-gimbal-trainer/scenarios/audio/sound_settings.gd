class_name SoundSettings
extends RefCounted
## Volumes (Paramètres > Son, and in game Échap > Son), saved with the menu preferences.
##
## Three sliders, three audio buses: the sound of the subject and the sound of the drone are kept
## apart on purpose. They do different jobs - the subject's engine tells the operator where the
## subject is and when it is about to pass, the drone's props are just the seat he is sitting in -
## so someone who wants to hear the first can turn the second right down without going silent.

const PREFS_PATH := "user://menu_prefs.json"
const BUS_SUBJECT := "Sujet"
const BUS_DRONE := "Drone"

## 0 .. 1, linear. The defaults leave room above the subject: it is the one that carries information.
static var master := 0.8
static var subject := 1.0
static var drone := 0.6


# --- Buses --------------------------------------------------------------------------------------

## Creates the two buses the voices play on, once per process. Called before any player is made, so
## a scene opened directly (a test, the editor) has them too.
static func ensure_buses() -> void:
	for name in [BUS_SUBJECT, BUS_DRONE]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	apply()


## Puts the three volumes on their buses. A slider at zero mutes rather than sending -inf dB.
static func apply() -> void:
	_set_bus("Master", master)
	_set_bus(BUS_SUBJECT, subject)
	_set_bus(BUS_DRONE, drone)


static func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var linear := clampf(v, 0.0, 1.0)
	AudioServer.set_bus_mute(i, linear <= 0.005)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.005)))


# --- Saving -------------------------------------------------------------------------------------

static func save() -> void:
	var prefs := {}
	if FileAccess.file_exists(PREFS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			prefs = parsed
	prefs["sound"] = {"master": master, "subject": subject, "drone": drone}
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(prefs, "\t"))


static func load_prefs(prefs: Dictionary) -> void:
	var s = prefs.get("sound", {})
	if typeof(s) == TYPE_DICTIONARY:
		master = clampf(float(s.get("master", master)), 0.0, 1.0)
		subject = clampf(float(s.get("subject", subject)), 0.0, 1.0)
		drone = clampf(float(s.get("drone", drone)), 0.0, 1.0)
	ensure_buses()
