class_name SessionRecorder
extends RefCounted
## Records, frame by frame, what drives the gimbal during a run: the time step and the three
## channel inputs (pan / tilt / roll, after keyboard + controller mixing) that the GimbalRig
## consumed, plus speed-profile changes and the initial gimbal state. With the same scenario and
## seed, replaying these reproduces the run exactly (ScenarioBase replay mode).

var _dt: Array = []
var _pan: Array = []
var _tilt: Array = []
var _roll: Array = []
var _profiles: Array = []  # [frame, pan_profile, tilt_profile, roll_profile] at each change
var _initial := {}
var _last_profile := [-1, -1, -1]


func start(rig: GimbalRig, flight: FlightPath) -> void:
	_initial = {
		"angles": rig.angles.duplicate(),
		"velocities": rig.velocities.duplicate(),
		"filtered": rig.filtered.duplicate(),
		"flight_t": flight._t,
	}


func add_frame(delta: float, inputs: Array, rig: GimbalRig) -> void:
	var prof := [rig.pan_profile, rig.tilt_profile, rig.roll_profile]
	if prof != _last_profile:
		_profiles.append([_dt.size(), prof[0], prof[1], prof[2]])
		_last_profile = prof
	_dt.append(snappedf(delta, 0.0000001))
	_pan.append(snappedf(inputs[0], 0.00001))
	_tilt.append(snappedf(inputs[1], 0.00001))
	_roll.append(snappedf(inputs[2], 0.00001))


func frame_count() -> int:
	return _dt.size()


func build_record(scn: ScenarioBase, results: Dictionary) -> Dictionary:
	var now := Time.get_datetime_dict_from_system()
	var date := "%04d-%02d-%02d %02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute]
	var id := "%04d%02d%02d_%02d%02d%02d_%s" % [now.year, now.month, now.day, now.hour, now.minute,
			now.second, scn.scenario_id]
	return {
		"version": 2,
		"flight": DroneDifficulty.FLIGHT_VERSION,
		"id": id,
		"timestamp": int(Time.get_unix_time_from_system()),
		"date": date,
		"scenario": {
			"id": scn.scenario_id,
			"title": scn.scenario_title,
			"scene": scn.scene_file_path,
			"matrix": scn.matrix.to_dict() if scn.matrix != null else null,
		},
		"scores": results,
		"initial": _initial,
		"profiles": _profiles,
		"frames": {"dt": _dt, "pan": _pan, "tilt": _tilt, "roll": _roll},
	}
