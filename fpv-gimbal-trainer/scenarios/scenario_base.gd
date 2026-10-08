class_name ScenarioBase
extends Node3D
## Common logic of every scenario: a PathSubject moves along its own path, a FlightPath drone
## flies alongside (progress locked to the subject), the player controls only the GimbalRig,
## SessionScorer scores the run.
##
## A scenario script overrides _build_scenario() and must set: scenario_id, scenario_title,
## subject (not yet in the tree), subject_pts and drone_pts (same number of points; drone point i
## is the drone position when the subject is at point i). It may fill the occluder lists with
## add_tree_occluder() / add_cylinder_occluder(), set drift_events, and override _extra_occlusion().
## The scene needs the nodes FlightPath, HUD/Label and HUD/FrameGuide.

enum State { COUNTDOWN, RUNNING, FINISHED }

@export_group("Run")
@export_range(0.0, 10.0, 0.5, "suffix:s") var countdown_time := 4.0

@export_group("Drone")
## The drone drifts ahead of / behind its nominal position by up to this much, so the
## camera has to pan. Drift is zero at each of drift_events.
@export_range(0.0, 30.0, 0.5, "suffix:m") var drone_drift := 12.0

@export_group("Scoring")
## Subject must stay inside this central fraction of the screen to count as framed.
@export_range(0.2, 1.0, 0.05) var frame_fraction := 0.6

const PROFILE_NAMES := ["Slow", "Medium", "Fast"]
const MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var flight: FlightPath = $FlightPath
@onready var hud: Label = $HUD/Label
@onready var guide: Control = $HUD/FrameGuide

var scenario_id := ""
var scenario_title := "SCENARIO"
## Varies scenery / layout between generated sessions (set from the matrix seed).
var world_seed := 0
## Training session being played (ScenarioMatrix), null for the fixed scenarios.
var matrix: SessionConfig
var matrix_active := false
var subject: PathSubject
var state := State.COUNTDOWN

var subject_pts := PackedVector3Array()
var drone_pts := PackedVector3Array()
## Path positions (as fraction of the sample index) where the drone drift is zero.
var drift_events: Array[float] = []

# Occluders: kind 0 = vertical cylinder (a = radius, h = height), kind 1 = tree (a = scale)
var occ_pos := PackedVector3Array()  # ground position
var occ_a := PackedFloat32Array()
var occ_h := PackedFloat32Array()
var occ_kind := PackedByteArray()

var _barriers: Array[Dictionary] = []
## 2-player mode (a pilot flies the drone): the helper that owns the drone, null in the other modes.
var duo: DuoSession
var _pause: PauseMenu
var _recorder: SessionRecorder

# Replay mode: a recorded session (SessionStore.start_replay) is played back.
var replay: Dictionary = {}
var replay_active := false
var _replay_ready := false
var _replay_paused := false
var _replay_speed := 1.0
var _replay_idx := 0
var _replay_acc := 0.0
var _replay_prof := 0
var _time := 0.0
var _run_time := 0.0
var _occluded_time := 0.0
var _occluded_now := false
var _in_frame_now := true  ## inside the safe zone of the frame
var _edge_now := false      ## inside the frame but too close to its edge
var _subj_cum := PackedFloat32Array()
var _drone_cum := PackedFloat32Array()
## Slopes of the drone arc length against the subject arc length (cubic interpolation of the mapping
## between the two, so the drone speed has no steps at the samples).
var _map_m := PackedFloat32Array()
## Time constant (s) of the drone following the subject's progress (0 = locked to it): sudden
## accelerations of the subject are not copied by the drone.
var drone_follow_tau := 0.0
## Statistics of the planned drone flight (matrix sessions) and the context it was planned with.
var drone_stats := {}
var plan_ctx := {}
var _fs := 0.0
var _fv := 0.0
var _prev_s := 0.0
var _follow_ready := false


## Override: build the world, the paths and the subject.
func _build_scenario() -> void:
	push_error("ScenarioBase._build_scenario() not overridden")


## Override (matrix mode): apply the session difficulty (speed_scale, turn_scale, occlusion, aggression)
## to this scenario's exports. Called before _build_scenario().
func _apply_difficulty(_params: Dictionary) -> void:
	pass


## Override: Callable(x, z) -> ground height, used to plan the drone path in matrix mode.
func _ground_fn() -> Callable:
	return Callable()


## Override: Callable(x, z) -> height the drone must stay above (ground, tunnel hull...).
func _clearance_fn() -> Callable:
	return _ground_fn()


## Context of the drone planner (see MovementPlanner) for the current session.
func _planner_context() -> Dictionary:
	var ctx := {
		"ground": _clearance_fn(),
		"level": matrix.level,
		"occlusion": matrix.params.occlusion,
		"side": matrix.side,
		"seed": matrix.seed,
		"speed_hint": 8.0,
		"min_height": 3.0,
	}
	ctx.merge(_planner_extras(), true)
	return ctx


## Override: what hides the subject on a line of sight: trees / rocks / walls / players / clouds / none.
func _occluder_kind() -> String:
	return "trees"


## Override: extra entries for the drone planner context (distance_scale, relative_height, min_height).
func _planner_extras() -> Dictionary:
	return {}


## Override: the session to play when the scene is started on its own (no menu).
func _default_config() -> SessionConfig:
	return null


## Override: horizontal push getting a drone sphere out of moving obstacles (traffic...); zero = none.
func dynamic_push(_pos: Vector3, _radius: float) -> Vector3:
	return Vector3.ZERO


## Override: extra line-of-sight blockers (tunnels...). from = camera, to = subject.
func _extra_occlusion(_from: Vector3, _to: Vector3) -> bool:
	return false


func _hud_extra() -> String:
	return ""


func _ready() -> void:
	get_tree().paused = false
	SessionScorer.reset()
	if not SessionScorer.restart_requested.is_connected(_restart):
		SessionScorer.restart_requested.connect(_restart)
	if not SessionScorer.menu_requested.is_connected(_goto_menu):
		SessionScorer.menu_requested.connect(_goto_menu)
	if not SessionScorer.next_requested.is_connected(_next_session):
		SessionScorer.next_requested.connect(_next_session)
	guide.fraction = frame_fraction
	SessionScorer.frame_fraction = frame_fraction
	flight.rig.camera.add_child(MotionBlur.new())
	# The drone flies smoothly: only a hint of turbulence (the camera is stabilised, so it is its position that counts).
	flight.turbulence_pos = 0.05
	flight.turbulence_tilt_deg = 0.5

	SessionScorer.next_label = ""
	replay = SessionStore.replay_record
	SessionStore.replay_record = {}
	replay_active = not replay.is_empty()
	if replay_active:
		countdown_time = 0.0
	matrix = ScenarioMatrix.current
	if matrix == null:
		matrix = _default_config()
	if matrix != null:
		world_seed = matrix.seed
	matrix_active = matrix != null and not matrix.fixed
	if matrix != null and not matrix.fixed:
		flight.rig.camera.fov = SessionConfig.fov_for(matrix.lens)
	if matrix_active:
		drone_drift = 0.0
		SessionScorer.next_label = "" if replay_active else "Next random session (N)"
		_apply_difficulty(matrix.params)

	_build_scenario()

	if matrix_active:
		scenario_id = matrix.scenario_id()
		scenario_title = matrix.title()
		drift_events.clear()
		_place_barriers()

	subject.curve = make_curve(subject_pts)
	add_child(subject)
	flight.curve = make_curve(drone_pts)
	flight.externally_driven = true
	flight.loop_path = false
	flight.playing = true
	flight.restart()
	_subj_cum = cumulative(subject_pts)
	_drone_cum = cumulative(drone_pts)
	_build_ratio_map()
	if matrix_active and matrix.two_player:
		duo = DuoSession.new()
		duo.setup(self)

	# Start with the subject framed (the rig aligns itself on the first frames). The scene may be left
	# (Esc, Enter) before these frames have passed.
	for _i in 2:
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if not is_inside_tree():
		return
	flight.rig.aim_at(subject.torso_position())
	if replay_active:
		_begin_replay()


# --- Helpers for scenarios -------------------------------------------------------------

func make_curve(pts: PackedVector3Array) -> Curve3D:
	var c := Curve3D.new()
	for p in pts:
		c.add_point(p)
	FlightPath.auto_smooth(c)
	return c


static func cumulative(pts: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	return cum


## Fractional sample index at which the cumulative length equals s.
static func index_at(cum: PackedFloat32Array, s: float) -> float:
	var i := clampi(cum.bsearch(s) - 1, 0, cum.size() - 2)
	return i + clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001), 0.0, 1.0)


## Point on a polyline at arc length s (extrapolated along the first segment when s < 0).
static func polyline_at(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	if s <= 0.0:
		return pts[0] + (pts[1] - pts[0]).normalized() * s
	var f := index_at(cum, s)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


## Resamples per-point values to `count` samples uniform in arc length (for PathSubject.speed_profile).
static func profile_from_samples(values: PackedFloat32Array, cum: PackedFloat32Array,
		count := 200) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j in count:
		var f := index_at(cum, cum[cum.size() - 1] * j / float(count - 1))
		var i := mini(int(f), values.size() - 2)
		out.append(lerpf(values[i], values[i + 1], f - i))
	return out


## Curvature (1/m) at each point of a polyline, lightly smoothed.
static func curvature(pts: PackedVector3Array, smooth_passes := 3) -> PackedFloat32Array:
	var k := PackedFloat32Array()
	k.resize(pts.size())
	for i in range(1, pts.size() - 1):
		var a := pts[i] - pts[i - 1]
		var b := pts[i + 1] - pts[i]
		a.y = 0.0
		b.y = 0.0
		var seg := (a.length() + b.length()) * 0.5
		k[i] = absf(a.angle_to(b)) / maxf(seg, 0.001)
	for _p in smooth_passes:
		var s := k.duplicate()
		for i in range(1, k.size() - 1):
			s[i] = (k[i - 1] + 2.0 * k[i] + k[i + 1]) * 0.25
		k = s
	return k


## Drone path for the current matrix session (call from _build_scenario once subject_pts is set).
func plan_drone_path() -> PackedVector3Array:
	var extras := _planner_extras()
	# Fine samples (on the smoothed curve): about 8 per second of subject travel, so the drone flight
	# (a smooth function of time) is sampled accurately.
	var base := make_curve(subject_pts)
	var step := clampf(0.12 * float(extras.get("speed_hint", 8.0)), 0.12, 2.5)
	step = maxf(step, base.get_baked_length() / 2500.0)
	subject_pts = RoadBuilder.sample_curve(base, step)
	var ctx := _planner_context()
	var res := MovementPlanner.plan(matrix.movement, subject_pts, ctx)
	_barriers = res.barriers
	drone_stats = res.stats
	ctx["tau"] = res.stats.tau
	plan_ctx = ctx
	drone_follow_tau = float(res.stats.tau)
	return res.drone


## Obstacles hiding the subject during "reveal" sweeps (planned with the drone path): trees, or
## rocks / walls / players / clouds depending on the environment.
func _place_barriers() -> void:
	if _barriers.is_empty():
		return
	var kind := _occluder_kind()
	if kind == "none":
		return
	var ds := float(_planner_extras().get("distance_scale", 1.0))
	var ground := _ground_fn()
	var rng := RandomNumberGenerator.new()
	rng.seed = 117 + world_seed
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	for b in _barriers:
		var p: Vector3 = b.pos
		var gy := float(ground.call(p.x, p.z)) if ground.is_valid() else 0.0
		if kind == "trees":
			var g := Vector3(p.x, gy, p.z)
			grounds.append(g)
			scales.append(b.scale)
			add_tree_occluder(g, b.scale)
		else:
			if kind == "clouds":
				gy = p.y
			for spec in PropFactory.add_occluder_prop(self, kind, Vector3(p.x, gy, p.z), float(b.get("yaw", 0.0)), rng, maxf(ds, 0.2)):
				add_cylinder_occluder(spec.pos, spec.r, spec.h)
	if kind == "trees":
		PropFactory.build_forest(self, grounds, scales, Color(0.08, 0.28, 0.14), 17)


## Obstacles on the drone->subject line of sight at the given path fractions (in matrix mode,
## where the drone path is arbitrary). With trees: every other event is a rock, the others a row
## of trees; other kinds (rocks / walls / players / clouds) come from the environment.
func add_los_occluders(fractions: Array, rocks := true) -> void:
	var kind := _occluder_kind()
	if kind == "none":
		return
	var ds := float(_planner_extras().get("distance_scale", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + world_seed
	var ground := _ground_fn()
	var grounds := PackedVector3Array()
	var scales := PackedFloat32Array()
	for e in fractions.size():
		var i := clampi(int(float(fractions[e]) * (subject_pts.size() - 1)), 0, subject_pts.size() - 1)
		var s := subject_pts[i]
		var d := drone_pts[i]
		var flat := Vector3(d.x - s.x, 0.0, d.z - s.z)
		if flat.length() < 3.0 * ds:
			continue
		var perp := flat.cross(Vector3.UP).normalized()
		# Pursuit / frontal views look along the path: an obstacle there would sit ON the path.
		if _dist_to_path_xz(s + flat * 0.5) < 7.0 * ds:
			continue
		if kind != "trees":
			var offsets: Array = [-1, 0, 1] if kind == "walls" else [0]
			var at := 0.35 if kind == "rocks" else 0.5
			var yaw := atan2(perp.x, perp.z)
			for k in offsets:
				var tp: Vector3 = s + flat * at + perp * (float(k) * 2.2 * ds + rng.randf_range(-0.5, 0.5) * ds)
				var gy := float(ground.call(tp.x, tp.z)) if ground.is_valid() else s.y
				if kind == "clouds":
					gy = (s.y + d.y) * 0.5 - 6.0
				for spec in PropFactory.add_occluder_prop(self, kind, Vector3(tp.x, gy, tp.z), yaw, rng, maxf(ds, 0.2)):
					add_cylinder_occluder(spec.pos, spec.r, spec.h)
		elif rocks and e % 2 == 1:
			var rp := s + flat * 0.35
			var g := Vector3(rp.x, float(ground.call(rp.x, rp.z)) if ground.is_valid() else s.y, rp.z)
			var size := Vector3(2.2, 2.2, 4.5)
			PropFactory.add_rock(self, g, size)
			add_cylinder_occluder(g, maxf(size.x, size.z) * 0.9, size.y * 1.4)
		else:
			for k in [-2, -1, 0, 1, 2]:
				var tp: Vector3 = s + flat * 0.5 + perp * (k * 2.4 + rng.randf_range(-0.6, 0.6))
				var g := Vector3(tp.x, float(ground.call(tp.x, tp.z)) if ground.is_valid() else s.y, tp.z)
				grounds.append(g)
				scales.append(1.5)
				add_tree_occluder(g, 1.5)
	if kind == "trees":
		PropFactory.build_forest(self, grounds, scales, Color(0.08, 0.3, 0.14), 19)

## Horizontal distance from p to the subject path.
func _dist_to_path_xz(p: Vector3) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for i in subject_pts.size() - 1:
		var a := Vector2(subject_pts[i].x, subject_pts[i].z)
		var ab := Vector2(subject_pts[i + 1].x, subject_pts[i + 1].z) - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


func add_tree_occluder(ground: Vector3, tree_scale: float) -> void:
	occ_pos.append(ground)
	occ_a.append(tree_scale)
	occ_h.append(0.0)
	occ_kind.append(1)


## Deciduous tree (PropFactory.round_tree_radius_at): kind 2.
func add_round_tree_occluder(ground: Vector3, tree_scale: float) -> void:
	occ_pos.append(ground)
	occ_a.append(tree_scale)
	occ_h.append(0.0)
	occ_kind.append(2)


func add_cylinder_occluder(ground: Vector3, radius: float, height: float) -> void:
	occ_pos.append(ground)
	occ_a.append(radius)
	occ_h.append(height)
	occ_kind.append(0)


# --- Run -------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		FrameGuide.show_thirds = not FrameGuide.show_thirds
		guide.queue_redraw()
		return
	if replay_active:
		_replay_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER: _restart()
			KEY_ESCAPE:
				if state == State.FINISHED:
					_goto_menu()
				else:
					_open_pause()
					get_viewport().set_input_as_handled()
			KEY_1: _set_profile(GimbalRig.SpeedProfile.SLOW)
			KEY_2: _set_profile(GimbalRig.SpeedProfile.MEDIUM)
			KEY_3: _set_profile(GimbalRig.SpeedProfile.FAST)
			KEY_F1: hud.visible = not hud.visible
			KEY_N: _next_session()


## Pause menu (Esc): the game tree is paused, the menu keeps running.
func _open_pause() -> void:
	if _pause == null:
		_pause = PauseMenu.new()
		_pause.resume_requested.connect(_close_pause)
		_pause.restart_requested.connect(_restart)
		_pause.quit_requested.connect(_goto_menu)
		add_child(_pause)
	_pause.lens_mm = matrix.lens if matrix != null and not matrix.fixed else 24  # (not editable: scored session)
	get_tree().paused = true
	_pause.open()


func _close_pause() -> void:
	_pause.close()
	get_tree().paused = false


func _restart() -> void:
	get_tree().paused = false
	SessionScorer.reset()
	get_tree().reload_current_scene()


func _next_session() -> void:
	if matrix_active:
		SessionScorer.reset()
		ScenarioMatrix.launch(get_tree(), ScenarioMatrix.next_session(matrix))


func _goto_menu() -> void:
	get_tree().paused = false
	SessionScorer.reset()
	get_tree().change_scene_to_file(MENU_SCENE)


func _set_profile(p: GimbalRig.SpeedProfile) -> void:
	flight.rig.pan_profile = p
	flight.rig.tilt_profile = p
	flight.rig.roll_profile = p


func _process(delta: float) -> void:
	if subject == null or not subject.is_node_ready():
		return
	if replay_active:
		_replay_process(delta)
		return
	var just_finished := false
	var pilot_inputs: Array = []
	if duo and state != State.FINISHED:
		pilot_inputs = duo.current_inputs()
	if state == State.COUNTDOWN:
		_time += delta
		if _time >= countdown_time:
			# The run starts in this very frame (so the recording covers every simulated frame).
			state = State.RUNNING
			SessionScorer.start_run(flight.rig, subject.torso_position, scenario_id)
			if duo:
				duo.start_run()
			_recorder = SessionRecorder.new()
			_recorder.start(flight.rig, flight)
			if duo:
				_recorder.set_initial("drone", duo.state())
	if state == State.RUNNING:
		_run_time += delta
		if _recorder:
			_recorder.add_frame(delta, flight.rig.read_inputs(), flight.rig, pilot_inputs)
		subject.advance(delta)
		if duo:
			duo.step(delta, pilot_inputs, true, _occluded_now)
		else:
			flight.external_ratio = _drone_ratio(delta)
		just_finished = subject.finished
	elif state == State.FINISHED:
		if not duo:
			flight.external_ratio = 1.0
	if duo and state == State.COUNTDOWN:
		duo.step(delta, pilot_inputs, false, false)
	_update_framing_state()
	if duo:
		duo.update_osd()
	if state == State.RUNNING:
		if _occluded_now:
			_occluded_time += delta
		if just_finished:
			state = State.FINISHED
			var extras := {"Hidden behind obstacles": "%.1f s" % _occluded_time}
			if matrix_active:
				extras["Session"] = matrix.title().trim_prefix("TRAINING - ")
			var partner := -1.0
			if duo:
				var pr := duo.results()
				partner = float(pr.overall)
				extras["Pilot"] = "%d / 100  (distance %.0f, fluidity %.0f, line of sight %.0f, %d crashes)" % [pr.overall, pr.distance, pr.fluidity, pr.los, pr.crashes]
				extras["Mean distance to subject"] = "%.0f m" % pr.mean_distance
			SessionScorer.end_run(extras, partner)
			if matrix_active and not duo:
				ScenarioMatrix.record_result(matrix, int(SessionScorer.results.overall))
			if _recorder:
				SessionStore.save(_recorder.build_record(self, SessionScorer.results))
	_update_hud()


## Drone progress: the drone is at point i of its path when the subject is at point i (arc lengths
## mapped with a cubic interpolation, so the drone speed is continuous), plus a drift that is zero at
## drift_events (fixed scenarios). `delta` is the time step: with drone_follow_tau > 0 the drone
## follows the subject's progress through a low-pass (no copy of sudden accelerations).
func _drone_ratio(delta := 0.0) -> float:
	var n := subject_pts.size()
	var total_s: float = _subj_cum[_subj_cum.size() - 1]
	var s: float = clampf(subject.progress_ratio, 0.0, 1.0) * total_s
	s = _follow(s, delta, total_s)
	var drift := 0.0
	if drone_drift > 0.0:
		var u := index_at(_subj_cum, s) / float(n - 1)
		var envelope := smoothstep(0.0, 0.08, u) * smoothstep(1.0, 0.92, u)
		var period := 0.25 if drift_events.size() < 2 else drift_events[1] - drift_events[0]
		var phase0 := 0.0 if drift_events.is_empty() else drift_events[0]
		drift = drone_drift * envelope * sin(TAU * (u - phase0) / period)
	return clampf(_map_eval(clampf(s + drift, 0.0, total_s)) / _drone_cum[_drone_cum.size() - 1], 0.0, 1.0)


## Subject progress seen by the drone: the SPEED is low-passed (time constant drone_follow_tau) and
## integrated, with a slow pull towards the true progress so the lag never accumulates.
func _follow(s_true: float, delta: float, total_s: float) -> float:
	if drone_follow_tau <= 0.0 or delta <= 0.0:
		return s_true
	if not _follow_ready:
		_follow_ready = true
		_fs = s_true
		_fv = subject.speed_now
		_prev_s = s_true
		return _fs
	var v_true := (s_true - _prev_s) / delta
	_prev_s = s_true
	_fv += (v_true - _fv) * (1.0 - exp(-delta / drone_follow_tau))
	_fs += _fv * delta
	_fs += (s_true - _fs) * (1.0 - exp(-delta / DroneDifficulty.FOLLOW_PULL))
	_fs = clampf(_fs, 0.0, total_s)
	return _fs


func _build_ratio_map() -> void:
	var n := _subj_cum.size()
	_map_m.resize(n)
	for i in n:
		var a := maxi(i - 1, 0)
		var b := mini(i + 1, n - 1)
		_map_m[i] = maxf((_drone_cum[b] - _drone_cum[a]) / maxf(_subj_cum[b] - _subj_cum[a], 0.0001), 0.0)


## Arc length along the drone path for the subject at arc length s (cubic Hermite, monotone).
func _map_eval(s: float) -> float:
	var n := _subj_cum.size()
	var i := clampi(_subj_cum.bsearch(s) - 1, 0, n - 2)
	var h: float = _subj_cum[i + 1] - _subj_cum[i]
	if h < 0.0001:
		return _drone_cum[i]
	var u := clampf((s - _subj_cum[i]) / h, 0.0, 1.0)
	var u2 := u * u
	var u3 := u2 * u
	var p := (2.0 * u3 - 3.0 * u2 + 1.0) * _drone_cum[i] + (u3 - 2.0 * u2 + u) * h * _map_m[i] \
			+ (-2.0 * u3 + 3.0 * u2) * _drone_cum[i + 1] + (u3 - u2) * h * _map_m[i + 1]
	return clampf(p, _drone_cum[i], _drone_cum[i + 1])


func _update_framing_state() -> void:
	var cam := flight.rig.camera
	var target := subject.torso_position()
	var d := 9.0  # distance from the centre, 1 = screen edge
	if not cam.is_position_behind(target):
		var half := get_viewport().get_visible_rect().size * 0.5
		var p := cam.unproject_position(target)
		d = maxf(absf(p.x - half.x) / half.x, absf(p.y - half.y) / half.y)
	var in_guide := d <= frame_fraction
	_edge_now = in_guide and d > frame_fraction * (1.0 - SessionScorer.safe_margin)
	_in_frame_now = in_guide and not _edge_now
	guide.danger = _edge_now
	guide.in_frame = in_guide
	_occluded_now = is_occluded(cam.global_position, target)

## True if an obstacle stands on the segment from -> to.
func is_occluded(from: Vector3, to: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	var ab := Vector2(to.x, to.z) - a
	var len2 := ab.length_squared()
	for i in occ_pos.size():
		var c := Vector2(occ_pos[i].x, occ_pos[i].z)
		var t := 0.0 if len2 < 0.0001 else clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		var d := (a + ab * t).distance_to(c)
		var size := occ_a[i]
		if d > size * 3.0 + 1.0:
			continue
		var y := lerpf(from.y, to.y, t) - occ_pos[i].y  # height above the obstacle's ground
		if occ_kind[i] == 0:
			if d < size and y < occ_h[i]:
				return true
		elif occ_kind[i] == 2:
			if d < PropFactory.round_tree_radius_at(y / size) * size:
				return true
		elif d < PropFactory.tree_radius_at(y / size) * size:
			return true
	return _extra_occlusion(from, to)


func _update_hud() -> void:
	var rig := flight.rig
	var head := ""
	match state:
		State.COUNTDOWN:
			head = "GET READY  %.1f   (practice framing, run starts soon)" % maxf(0.0, countdown_time - _time)
		State.RUNNING:
			head = "RUN  %.1fs   %.0f%%" % [_run_time, subject.progress_ratio * 100.0]
		State.FINISHED:
			head = "FINISHED   (Enter: restart - Esc: menu)"
	hud.text = "%s - %s\nSubject %.1f m/s   drone %.1f m/s   [%s]\nFraming: %s   %s   score %.0f%%\nGimbal pan %+.0f°  tilt %+.0f°  roll %+.0f°\n%s\nArrows/WASD: pan+tilt   Q/E: roll   1/2/3: gimbal profile   G: thirds grid   Enter: restart   Esc: pause   F1: hide" % [
		scenario_title, head, subject.speed_now, (duo.drone.velocity.length() if duo else flight.speed_now), PROFILE_NAMES[rig.pan_profile],
		("IN FRAME" if _in_frame_now else ("TOO CLOSE TO THE EDGE" if _edge_now else "OUT OF FRAME")),
		"(HIDDEN)" if _occluded_now else "",
		SessionScorer.live_framing_score(), rig.angles[0], rig.angles[1], rig.angles[2],
		_hud_extra()]


# --- Replay ---------------------------------------------------------------------------------
# The recorded run is re-simulated step by step with the recorded time steps and gimbal inputs, at
# real-time speed (x speed factor). The rig and the flight path are stepped by hand, in the same
# order as in a live run (subject -> drone -> gimbal), so the result is identical.

func _begin_replay() -> void:
	var init: Dictionary = replay.initial
	var rig := flight.rig
	rig.restore_state(init.angles, init.velocities, init.filtered)
	flight._t = float(init.flight_t)
	flight.set_process(false)
	if duo and init.has("drone"):
		duo.restore(init.drone)
	rig.set_process(false)
	state = State.RUNNING
	_replay_ready = true


func _replay_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE: _replay_paused = not _replay_paused
		KEY_ENTER, KEY_KP_ENTER:
			SessionStore.replay_record = replay
			get_tree().reload_current_scene()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/history.tscn")
		KEY_1: _replay_speed = 0.25
		KEY_2: _replay_speed = 0.5
		KEY_3: _replay_speed = 1.0
		KEY_4: _replay_speed = 2.0
		KEY_5: _replay_speed = 4.0
		KEY_F1: hud.visible = not hud.visible


func _replay_process(delta: float) -> void:
	var frames: Dictionary = replay.frames
	var dts: Array = frames.dt
	if _replay_ready and not _replay_paused and _replay_idx < dts.size():
		_replay_acc += delta * _replay_speed
		var steps := 0
		while _replay_idx < dts.size() and _replay_acc >= float(dts[_replay_idx]) and steps < 400:
			_replay_acc -= float(dts[_replay_idx])
			_replay_step(_replay_idx)
			_replay_idx += 1
			steps += 1
		if _replay_idx >= dts.size():
			state = State.FINISHED
	_update_framing_state()
	_update_replay_hud()


func _replay_step(i: int) -> void:
	var frames: Dictionary = replay.frames
	var dt := float(frames.dt[i])
	var rig := flight.rig
	var profiles: Array = replay.profiles
	while _replay_prof < profiles.size() and int(profiles[_replay_prof][0]) <= i:
		rig.pan_profile = int(profiles[_replay_prof][1])
		rig.tilt_profile = int(profiles[_replay_prof][2])
		rig.roll_profile = int(profiles[_replay_prof][3])
		_replay_prof += 1
	rig.input_override = [float(frames.pan[i]), float(frames.tilt[i]), float(frames.roll[i])]
	_run_time += dt
	subject.advance(dt)
	if duo:
		var pil: Array = frames.pilot[i]
		duo.step(dt, [float(pil[0]), float(pil[1]), float(pil[2]), float(pil[3])], false, false)
	else:
		flight.external_ratio = _drone_ratio(dt)
		flight._process(dt)
	rig._process(dt)
	if _occluded_now:
		_occluded_time += dt


func _update_replay_hud() -> void:
	var sc: Dictionary = replay.scores
	var total := 0.0
	for d in replay.frames.dt:
		total += float(d)
	var rig := flight.rig
	var head := "REPLAY  %s  (%s)" % [scenario_title, replay.date]
	var status := "FINISHED" if state == State.FINISHED else ("PAUSED" if _replay_paused else "PLAYING x%s" % _replay_speed)
	hud.text = "%s\n%s   %.1f / %.1f s\nRecorded score: %d / 100 [%s]   framing %.0f   fluidity %.0f   tracking %.0f\nNow: %s   %s\nGimbal pan %+.0f°  tilt %+.0f°  roll %+.0f°\n\nSpace: pause   1-5: speed (x0.25 .. x4)   Enter: restart replay   Esc: history   F1: hide" % [
		head, status, _run_time, total, sc.overall, sc.grade, sc.framing, sc.fluidity, sc.tracking,
		("IN FRAME" if _in_frame_now else ("TOO CLOSE TO THE EDGE" if _edge_now else "OUT OF FRAME")), "(HIDDEN)" if _occluded_now else "",
		rig.angles[0], rig.angles[1], rig.angles[2]]