class_name SubjectVoice
extends Node3D
## The sound the subject makes, from where the drone is.
##
## It is a 3D source on the subject itself, and the listener is the gimbal camera - so the sound
## carries the same information the picture does: how far the subject is, which side it went, and
## whether it is coming or going. Doppler is on, which is the whole point on a flyby: the engine
## note drops as the car passes under the drone, exactly when the operator has to swing the pan
## through. Hearing it start to drop is the cue to begin the move.
##
## Nothing here is scripted per sport. Three families cover the catalogue, chosen from the gear on
## the sheet, and each one is driven by the speed the subject is actually doing.

## How far the subject can be heard at all, and the distance it plays at full level.
const UNIT := 14.0
const MAX_DIST := 600.0

## Engine: pitch at idle and at the red line, as a multiple of the loop's own pitch.
const IDLE_PITCH := 0.55
const RED_PITCH := 2.5
const GEARS := 6
const SILENT_DB := -60.0

enum Family { AIR, ENGINE, SNOW }

var family := Family.AIR
var top_speed := 20.0

var _engine: AudioStreamPlayer3D
var _rumble: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
var _subject: PathSubject
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
	match family:
		Family.ENGINE:
			# a racing car barks, a road car hums: the sheet's top speed is a fair proxy
			_engine = _player(SoundBank.engine(clampf(top_speed / 70.0, 0.25, 0.95)), -6.0)
			_rumble = _player(SoundBank.rolling(), -18.0)
		Family.SNOW:
			_hiss = _player(SoundBank.edges(), -12.0)
		_:
			_hiss = _player(SoundBank.wind(), -20.0)


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.bus = SoundSettings.BUS_SUBJECT
	p.unit_size = UNIT
	p.max_distance = MAX_DIST
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# the reason this class exists: the note drops as the subject goes past
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(p)
	p.play()
	return p


## Called every frame of the run, after the subject has advanced.
func update(delta: float) -> void:
	if _subject == null or delta <= 0.0:
		return
	var v: float = _subject.speed_now
	var norm := clampf(v / top_speed, 0.0, 1.2)
	# how hard the subject is working, from what it is actually doing rather than from a script
	var accel := (v - _prev_speed) / delta
	_prev_speed = v
	_throttle = clampf(lerpf(_throttle, clampf(0.35 + accel * 0.25, 0.0, 1.0), delta * 4.0), 0.0, 1.0)
	match family:
		Family.ENGINE:
			_engine_update(norm)
		Family.SNOW:
			_snow_update(norm)
		_:
			_air_update(norm)


## A gearbox, so the note rises and drops instead of sliding up forever. The drop at each change
## is what tells the ear the car is accelerating hard rather than just going fast.
func _engine_update(norm: float) -> void:
	var g := clampf(norm, 0.0, 1.0) * GEARS
	_gear = int(g)
	var frac := g - float(_gear)
	var rev := lerpf(0.26, 1.0, frac)
	if norm < 0.06:
		rev = lerpf(0.1, 0.26, norm / 0.06)   # idling, not crawling in first
	_engine.pitch_scale = lerpf(IDLE_PITCH, RED_PITCH, rev)
	_engine.volume_db = _db(0.25 + 0.75 * rev * (0.45 + 0.55 * _throttle)) - 4.0
	_rumble.pitch_scale = clampf(0.6 + norm * 0.9, 0.5, 1.8)
	_rumble.volume_db = _db(norm * 0.9) - 14.0


## Snow under the edges. Carving is a thin, bright hiss; a skid is broad and much louder - which is
## the sound the operator should learn to hear, because the skier only slows down by skidding.
func _snow_update(norm: float) -> void:
	var skid := clampf(float(_subject.get("state").get("skid", 0.0)) if _has_state() else 0.0, 0.0, 1.0)
	var lean := clampf(absf(_subject.lean_deg) / 35.0, 0.0, 1.0)
	var bite := maxf(skid, lean * 0.6)
	_hiss.pitch_scale = clampf(0.75 + norm * 0.5 - skid * 0.2, 0.5, 1.6)
	_hiss.volume_db = _db(norm * (0.22 + 0.78 * bite)) - 6.0


func _air_update(norm: float) -> void:
	_hiss.pitch_scale = clampf(0.8 + norm * 0.5, 0.6, 1.5)
	_hiss.volume_db = _db(norm * norm) - 10.0


## Volume in dB, floored instead of running off to -inf when a layer goes silent.
static func _db(linear: float) -> float:
	var v := clampf(linear, 0.0, 1.0)
	return SILENT_DB if v <= 0.002 else maxf(linear_to_db(v), SILENT_DB)


func _has_state() -> bool:
	return _subject != null and _subject.get("state") is Dictionary
