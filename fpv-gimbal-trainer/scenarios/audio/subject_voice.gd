class_name SubjectVoice
extends Node3D
## The sound the subject makes, from where the drone is.
##
## Several recordings mixed at once, not one recording stretched (see SoundLayer): a car at 40 and
## the same car at 160 km/h are different sounds, so the engine crossfades between an idle, a
## mid-range and a top-end loop as the revs climb, with tyre noise laid under them. Skis crossfade
## between carving and skidding. That is what makes it read as a machine changing state.
##
## It is a 3D source on the subject itself, and the listener is the gimbal camera - so the sound
## carries the same information the picture does: how far the subject is, which side it went, and
## whether it is coming or going. Doppler is on, which is the whole point on a flyby: the engine
## note drops as the car passes under the drone, exactly when the operator has to swing the pan
## through. Hearing it start to drop is the cue to begin the move.
##
## Nothing here is scripted per sport. Three families cover the catalogue, chosen from the gear on
## the sheet, and each one is driven by what the subject is actually doing.

## How far the subject can be heard at all, and the distance it plays at full level.
const UNIT := 14.0
const MAX_DIST := 600.0
const GEARS := 6

enum Family { AIR, ENGINE, SNOW }

## An engine crossfade driven by the rev within the current gear (0 idling .. 1 on the limiter),
## with the tyres laid under it on road speed.
const ENGINE_LAYERS := {
	"engine_idle": {"window": [-1.0, -1.0, 0.3, 0.55], "pitch": Vector2(0.8, 1.2), "db": -13.0},
	"engine_mid": {"window": [0.18, 0.42, 0.68, 0.9], "pitch": Vector2(0.82, 1.25), "db": -11.0},
	"engine_high": {"window": [0.6, 0.85, 1.0e9, 1.0e9], "pitch": Vector2(0.86, 1.3),
			"over": Vector2(0.6, 1.0), "db": -10.0},
}
const TYRE_LAYER := {"window": [0.02, 0.22, 1.0e9, 1.0e9], "pitch": Vector2(0.75, 1.5),
		"over": Vector2(0.05, 1.0), "db": -21.0}

## Snow: the edges biting, and the much broader roar of a skid. The skier only slows down by
## skidding, so this crossfade is the one the operator should learn to hear.
const SNOW_LAYERS := {
	"ski_carve": {"window": [0.04, 0.3, 1.0e9, 1.0e9], "pitch": Vector2(0.8, 1.45),
			"over": Vector2(0.05, 1.0), "db": -13.0},
	"ski_skid": {"window": [0.05, 0.4, 1.0e9, 1.0e9], "pitch": Vector2(0.75, 1.15),
			"over": Vector2(0.05, 1.0), "db": -9.0},
}

## Everything else: the air going past, in v squared.
const AIR_LAYERS := {
	"wind_mid": {"window": [0.03, 0.35, 1.0e9, 1.0e9], "pitch": Vector2(0.85, 1.35),
			"over": Vector2(0.03, 1.0), "db": -17.0},
}

var family := Family.AIR
var top_speed := 20.0

var _subject: PathSubject
var _layers := {}
var _prev_speed := 0.0
var _throttle := 0.0
var _gear := 0


func setup(subject: PathSubject, def: SubjectDefinition, params: Dictionary) -> void:
	SoundSettings.ensure_buses()
	_subject = subject
	top_speed = maxf(float(params.get("speed_max", 20.0)), 1.0)
	match str(def.placeholder_gear):
		"car", "race_car", "kart", "moto", "scooter":
			family = Family.ENGINE
		"skis", "snowboard", "sled":
			family = Family.SNOW
		_:
			family = Family.AIR
	var cfgs := {}
	match family:
		Family.ENGINE:
			cfgs = ENGINE_LAYERS.duplicate()
			cfgs["tyres"] = TYRE_LAYER
		Family.SNOW:
			cfgs = SNOW_LAYERS
		_:
			cfgs = AIR_LAYERS
	for name in cfgs:
		var l := SoundLayer.make(self, name, cfgs[name], true)
		if l == null:
			continue
		_tune(l.player)
		l.start()
		_layers[name] = l


## Every layer of the subject is a 3D source on the subject, with Doppler: the note drops as it
## goes past, which is the cue to start the pan.
func _tune(p: AudioStreamPlayer3D) -> void:
	p.bus = SoundSettings.BUS_SUBJECT
	p.unit_size = UNIT
	p.max_distance = MAX_DIST
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP


## Called every frame of the run, after the subject has advanced.
func update(delta: float) -> void:
	if _subject == null or delta <= 0.0 or _layers.is_empty():
		return
	var v: float = _subject.speed_now
	var norm := clampf(v / top_speed, 0.0, 1.2)
	# how hard the subject is working, from what it is actually doing rather than from a script
	var accel := (v - _prev_speed) / delta
	_prev_speed = v
	_throttle = clampf(lerpf(_throttle, clampf(0.35 + accel * 0.25, 0.0, 1.0), delta * 4.0), 0.0, 1.0)
	match family:
		Family.ENGINE:
			_engine_update(norm, delta)
		Family.SNOW:
			_snow_update(norm, delta)
		_:
			_drive("wind_mid", norm * norm, delta)


## A gearbox, so the note rises and drops instead of sliding up forever. The drop at each change is
## what tells the ear the car is accelerating hard rather than just going fast - and because the
## three engine loops are crossfaded by that same rev, the timbre drops with it, not only the pitch.
func _engine_update(norm: float, delta: float) -> void:
	var g := clampf(norm, 0.0, 1.0) * GEARS
	_gear = int(g)
	var rev := lerpf(0.26, 1.0, g - float(_gear))
	if norm < 0.06:
		rev = lerpf(0.1, 0.26, norm / 0.06)   # idling, not crawling in first
	var pull := 0.45 + 0.55 * _throttle
	for name in ENGINE_LAYERS:
		if _layers.has(name):
			_layers[name].gain_mul = pull
			_layers[name].set_value(rev, delta)
	_drive("tyres", norm, delta)


## Carving is a thin, bright hiss; a skid is broad and much louder. Both need speed under them: a
## skier standing still with his skis across the hill makes no noise at all.
func _snow_update(norm: float, delta: float) -> void:
	# The archetype's skid is SIGNED - it carries the side the skis are thrown to (see
	# freeride.gd, _skid_side). Clamping it to 0..1 silenced every skid to one side, i.e. half of
	# them. What the ear hears is the magnitude, so take the absolute value.
	var skid := 0.0
	if _subject != null and _subject.get("state") is Dictionary:
		skid = clampf(absf(float(_subject.get("state").get("skid", 0.0))), 0.0, 1.0)
	var lean := clampf(absf(_subject.lean_deg) / 35.0, 0.0, 1.0)
	var carry := clampf(norm, 0.0, 1.0)
	_drive("ski_carve", carry * (0.25 + 0.75 * lean) * (1.0 - 0.6 * skid), delta)
	_drive("ski_skid", carry * skid, delta)


func _drive(name: String, v: float, delta: float) -> void:
	if _layers.has(name):
		_layers[name].set_value(v, delta)
