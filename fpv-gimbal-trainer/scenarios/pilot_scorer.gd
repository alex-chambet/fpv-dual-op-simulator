class_name PilotScorer
extends RefCounted
## Scores the pilot of a 2-player session: he must give the gimbal operator an easy shot.
##   Distance   : time spent at a good distance from the subject (depends on the lens)
##   Fluidity   : smooth flight (acceleration and jerk of the drone)
##   Line of sight : the direction drone -> subject changes slowly, and the subject is not hidden
##   Crashes    : each one removes points

const ACCEL_REF := 8.0      ## m/s², comfortable
const ACCEL_SCALE := 15.0
const JERK_REF := 50.0      ## m/s³
const JERK_SCALE := 150.0
const LOS_REF := 25.0       ## deg/s the gimbal operator can follow easily
const LOS_MAX := 90.0
const CRASH_PENALTY := 8.0

## Good distance (m): between 0.5 x and 1.6 x this value.
var ideal_distance := 14.0

var _t := 0.0
var _dist_sum := 0.0
var _los_sum := 0.0
var _excess_a_sq := 0.0
var _excess_j_sq := 0.0
var _hidden := 0.0
var _prev_v := Vector3.ZERO
var _prev_a := Vector3.ZERO
var _prev_dir := Vector3.ZERO
var _has_v := false
var _has_a := false
var _has_dir := false
var mean_distance_sum := 0.0


func update(dt: float, drone_pos: Vector3, drone_vel: Vector3, subject_pos: Vector3, hidden: bool) -> void:
	if dt <= 0.0:
		return
	_t += dt
	var to_subject := subject_pos - drone_pos
	var d := to_subject.length()
	mean_distance_sum += d * dt
	var lo := 0.5 * ideal_distance
	var hi := 1.6 * ideal_distance
	var v := 1.0
	if d < lo:
		v = clampf((d - 0.25 * ideal_distance) / (lo - 0.25 * ideal_distance), 0.0, 1.0)
	elif d > hi:
		v = clampf(1.0 - (d - hi) / (hi * 1.2), 0.0, 1.0)
	_dist_sum += v * dt

	if _has_v:
		var a := (drone_vel - _prev_v) / dt
		_excess_a_sq += pow(maxf(0.0, a.length() - ACCEL_REF), 2.0) * dt
		if _has_a:
			var j := (a - _prev_a).length() / dt
			_excess_j_sq += pow(maxf(0.0, j - JERK_REF), 2.0) * dt
		_prev_a = a
		_has_a = true
	_prev_v = drone_vel
	_has_v = true

	var los := 1.0
	if d > 0.01:
		var dir := to_subject / d
		if _has_dir:
			var rate := rad_to_deg(acos(clampf(dir.dot(_prev_dir), -1.0, 1.0))) / dt
			los = 1.0 - clampf((rate - LOS_REF) / (LOS_MAX - LOS_REF), 0.0, 1.0)
		_prev_dir = dir
		_has_dir = true
	if hidden:
		los *= 0.3
		_hidden += dt
	_los_sum += los * dt


func results(crashes: int) -> Dictionary:
	var t := maxf(_t, 0.001)
	var distance := 100.0 * _dist_sum / t
	var fluidity := 100.0 * (1.0 - clampf(sqrt(_excess_a_sq / t) / ACCEL_SCALE + sqrt(_excess_j_sq / t) / JERK_SCALE, 0.0, 1.0))
	var los := 100.0 * _los_sum / t
	var overall := clampf(0.3 * distance + 0.3 * fluidity + 0.4 * los - CRASH_PENALTY * crashes, 0.0, 100.0)
	return {
		"distance": distance, "fluidity": fluidity, "los": los, "crashes": crashes,
		"mean_distance": mean_distance_sum / t, "overall": roundf(overall),
	}
