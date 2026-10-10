extends Node
## Autoload "SessionScorer". Scores a run on three axes and shows a result screen.
##   Framing  : per frame, where the subject is in the green frame (the guide). Inside the safe zone (the frame
##              minus a 15% margin) it counts as "in frame"; between the safe zone and the frame edge it is
##              penalised; outside the frame it scores 0.
##   Fluidity : angular acceleration AND jerk (change of acceleration) of the GimbalRig; whatever is above a
##              comfortable reference is penalised (jerky moves)
##   Tracking : "subject lost" events = subject outside the frame (each exit counts, loss_threshold_ms = 0)
## Usage: start_run(rig, subject_provider)  ...  end_run(extras)

signal run_finished(results: Dictionary)
signal restart_requested
signal menu_requested
signal next_requested

# --- Tunables ---------------------------------------------------------------------
## Half-size of the guide frame (0..1 of the half screen), set by the scenario (same as FrameGuide.fraction).
var frame_fraction := 0.6
## Safety margin inside the frame (share of its half-size): beyond it the subject is "too close to the edge".
var safe_margin := 0.15
## Within the safe zone the score falls only from 1 to this value (centre -> safe limit)...
var safe_edge_score := 0.85
## ...and from there to this value at the frame edge (danger zone). Outside the frame: 0.
var edge_score := 0.15
## Out of the frame for longer than this counts as one "subject lost" event (0 = every exit counts at once).
var loss_threshold_ms := 0.0
## Angular acceleration (deg/s²) considered comfortable; above it counts as jerky.
var accel_reference := 60.0
## RMS excess acceleration (deg/s²) that gives a fluidity score of 0.
var accel_scale := 120.0
## Angular jerk (deg/s³) considered comfortable; above it counts as jerky (sudden starts, stops, corrections).
var jerk_reference := 1500.0
## RMS excess jerk (deg/s³) that gives a fluidity score of 0.
var jerk_scale := 4000.0
## Fluidity peaks are only recorded above this acceleration.
var peak_threshold := 100.0
## Points removed from the tracking score per lost-subject event.
var loss_penalty := 20.0
var weights := {"framing": 0.45, "fluidity": 0.35, "tracking": 0.2}

# --- State ------------------------------------------------------------------------
const BEST_PATH := "user://best_scores.json"

var active := false
var results := {}
var scenario_id := ""
## When non-empty, the result screen shows a third button with this text (training sessions).
var next_label := ""
## Peak angular accelerations (deg/s²) recorded during the run.
var accel_peaks: Array[float] = []

var in_view_now := false   ## inside the guide frame
var in_safe_now := false   ## inside the safe zone (frame minus margin)
var center_distance_now := 1.0

var _rig: GimbalRig
var _camera: Camera3D
var _subject: Callable
var _run_time := 0.0
var _in_view_time := 0.0
var _safe_time := 0.0
var _excess_jerk_sq_sum := 0.0
var _max_jerk := 0.0
var _dist_sum := 0.0
var _framing_sum := 0.0
var _out_time := 0.0
var _loss_counted := false
var _loss_events := 0
var _total_lost := 0.0
var _excess_sq_sum := 0.0
var _max_accel := 0.0
var _prev_v := Vector3.ZERO
var _has_prev_v := false
var _has_prev_a := false
var _prev_a := 0.0
var _prev_prev_a := 0.0

var _layer: CanvasLayer


func _ready() -> void:
	process_priority = 1000  # after the rig has moved this frame
	Neon.apply(get_tree())  # the look of every menu and HUD of the game (this autoload is loaded first)


## subject_provider: Callable returning the world position of the tracked subject.
func start_run(rig: GimbalRig, subject_provider: Callable, id := "") -> void:
	reset()
	scenario_id = id
	_rig = rig
	_camera = rig.camera
	_subject = subject_provider
	active = true


func reset() -> void:
	active = false
	results = {}
	accel_peaks.clear()
	_run_time = 0.0
	_in_view_time = 0.0
	_safe_time = 0.0
	_excess_jerk_sq_sum = 0.0
	_max_jerk = 0.0
	_dist_sum = 0.0
	_framing_sum = 0.0
	_out_time = 0.0
	_loss_counted = false
	_loss_events = 0
	_total_lost = 0.0
	_excess_sq_sum = 0.0
	_max_accel = 0.0
	_has_prev_v = false
	_has_prev_a = false
	_prev_a = 0.0
	_prev_prev_a = 0.0
	in_view_now = false
	in_safe_now = false
	center_distance_now = 1.0
	if _layer:
		_layer.queue_free()
		_layer = null


## Live framing score so far (0..100), for HUDs.
func live_framing_score() -> float:
	return 100.0 * _framing_sum / maxf(_run_time, 0.001)


func _process(delta: float) -> void:
	if not active or delta <= 0.0 or not is_instance_valid(_rig):
		return
	_run_time += delta
	_track_framing(delta)
	_track_fluidity(delta)


## Framing score (0..1) of a subject at normalised distance d from the centre (0 centre .. 1 screen edge).
func framing_value(d: float) -> float:
	var r := d / frame_fraction  # 1 = on the frame edge
	var safe := 1.0 - safe_margin
	if r > 1.0:
		return 0.0
	if r <= safe:
		return lerpf(1.0, safe_edge_score, clampf(r / safe, 0.0, 1.0))
	return lerpf(safe_edge_score, edge_score, (r - safe) / safe_margin)


func _track_framing(delta: float) -> void:
	var target: Vector3 = _subject.call()
	var d := 1.0
	var visible_now := false
	if not _camera.is_position_behind(target):
		var half := _camera.get_viewport().get_visible_rect().size * 0.5
		var p := _camera.unproject_position(target)
		d = maxf(absf(p.x - half.x) / half.x, absf(p.y - half.y) / half.y)
		visible_now = d <= 1.0
	in_view_now = visible_now and d <= frame_fraction
	in_safe_now = visible_now and d <= frame_fraction * (1.0 - safe_margin)
	center_distance_now = d

	if in_view_now:
		_in_view_time += delta
		if in_safe_now:
			_safe_time += delta
		_dist_sum += d * delta
		_framing_sum += framing_value(d) * delta
		_out_time = 0.0
		_loss_counted = false
	else:
		_out_time += delta
		_total_lost += delta
		if not _loss_counted and _out_time * 1000.0 >= loss_threshold_ms:
			_loss_events += 1
			_loss_counted = true


func _track_fluidity(delta: float) -> void:
	var v := Vector3(_rig.velocities[0], _rig.velocities[1], _rig.velocities[2])
	if _has_prev_v:
		var a := (v - _prev_v).length() / delta
		_excess_sq_sum += pow(maxf(0.0, a - accel_reference), 2.0) * delta
		_max_accel = maxf(_max_accel, a)
		if _has_prev_a:
			var j := absf(a - _prev_a) / delta
			_excess_jerk_sq_sum += pow(maxf(0.0, j - jerk_reference), 2.0) * delta
			_max_jerk = maxf(_max_jerk, j)
		_has_prev_a = true
		# local maximum of the previous sample
		if _prev_a > _prev_prev_a and _prev_a >= a and _prev_a > peak_threshold:
			accel_peaks.append(_prev_a)
		_prev_prev_a = _prev_a
		_prev_a = a
	_prev_v = v
	_has_prev_v = true

## partner_overall >= 0: 2-player session, the score of the pilot (the team score is the mean of both).
func end_run(extras: Dictionary = {}, partner_overall := -1.0) -> Dictionary:
	if not active:
		return results
	active = false
	var t := maxf(_run_time, 0.001)
	var framing := 100.0 * _framing_sum / t
	var rms_excess := sqrt(_excess_sq_sum / t)
	var rms_jerk := sqrt(_excess_jerk_sq_sum / t)
	var fluidity := 100.0 * (1.0 - clampf(rms_excess / accel_scale + rms_jerk / jerk_scale, 0.0, 1.0))
	var tracking := clampf(100.0 - loss_penalty * _loss_events, 0.0, 100.0)
	var overall := roundf(framing * weights.framing + fluidity * weights.fluidity
			+ tracking * weights.tracking)
	var best := _save_best(overall)
	results = {
		"best": best,
		"framing": framing,
		"fluidity": fluidity,
		"tracking": tracking,
		"overall": overall,
		"grade": _grade(overall),
		"run_time": _run_time,
		"in_view_percent": 100.0 * _in_view_time / t,
		"in_safe_percent": 100.0 * _safe_time / t,
		"mean_center_distance": 100.0 * _dist_sum / maxf(_in_view_time, 0.001),
		"accel_peaks": accel_peaks.size(),
		"max_accel": _max_accel,
		"max_jerk": _max_jerk,
		"loss_events": _loss_events,
		"lost_time": _total_lost,
		"extras": extras,
		"team": -1.0 if partner_overall < 0.0 else roundf(0.5 * (overall + partner_overall)),
	}
	print("[SessionScorer] overall %d (%s)  framing %.0f  fluidity %.0f  tracking %.0f  | lost events %d, peaks %d" % [
		overall, results.grade, framing, fluidity, tracking, _loss_events, accel_peaks.size()])
	_show_results()
	run_finished.emit(results)
	return results


func _grade(score: float) -> String:
	if score >= 90.0: return "S"
	if score >= 80.0: return "A"
	if score >= 65.0: return "B"
	if score >= 50.0: return "C"
	return "D"


# --- Result screen ------------------------------------------------------------------

func _show_results() -> void:
	if _layer:
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.0, 0.13, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 520
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "RUN RESULT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.caps(title, 22)
	box.add_child(title)

	var overall := Label.new()
	overall.text = "%d / 100    [ %s ]" % [results.overall, results.grade]
	overall.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Neon.title(overall, 56)
	box.add_child(overall)

	box.add_child(HSeparator.new())
	_add_row(box, "Framing", results.framing,
			"safe zone %.0f%% - in frame %.0f%% - mean distance from centre %.0f%%" % [results.get("in_safe_percent", 0.0), results.in_view_percent, results.mean_center_distance])
	_add_row(box, "Fluidity", results.fluidity,
			"%d jerk peaks - max %.0f deg/s² / %.0f deg/s³" % [results.accel_peaks, results.max_accel, results.get("max_jerk", 0.0)])
	_add_row(box, "Tracking", results.tracking,
			"%d exits from the frame - %.1f s outside the frame" % [results.loss_events, results.lost_time])

	var extras: Dictionary = results.extras
	if not extras.is_empty():
		box.add_child(HSeparator.new())
		for k in extras:
			var l := Label.new()
			l.text = "%s: %s" % [k, extras[k]]
			box.add_child(l)

	if float(results.get("team", -1.0)) >= 0.0:
		var team_l := Label.new()
		team_l.text = "TEAM SCORE: %d / 100" % results.team
		Neon.caps(team_l, 24, Neon.SUN)
		box.add_child(team_l)
	if scenario_id != "":
		var best_l := Label.new()
		best_l.text = "Best score: %d / 100" % results.best
		box.add_child(best_l)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var btn := Button.new()
	btn.text = "Play again (Enter)"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): restart_requested.emit())
	buttons.add_child(btn)
	var menu_btn := Button.new()
	menu_btn.text = "Menu (Esc)"
	menu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_btn.pressed.connect(func(): menu_requested.emit())
	buttons.add_child(menu_btn)
	if next_label != "":
		var next_btn := Button.new()
		next_btn.text = next_label
		next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		next_btn.pressed.connect(func(): next_requested.emit())
		buttons.add_child(next_btn)


func _add_row(parent: Control, title: String, value: float, detail: String) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var head := HBoxContainer.new()
	row.add_child(head)
	var name_l := Label.new()
	name_l.text = title
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_font_override("font", Neon.bold_font())
	head.add_child(name_l)
	var val_l := Label.new()
	val_l.text = "%.0f / 100" % value
	var col: Color = Neon.GOOD if value >= 80.0 else (Neon.MID if value >= 55.0 else Neon.BAD)
	val_l.add_theme_font_override("font", Neon.bold_font())
	val_l.add_theme_color_override("font_color", col)
	head.add_child(val_l)
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14
	bar.add_theme_stylebox_override("fill", Neon.box(col, Color(0, 0, 0, 0), 0, 8))
	row.add_child(bar)
	var d := Label.new()
	d.text = detail
	d.modulate = Color(1, 1, 1, 0.65)
	row.add_child(d)


# --- Best scores ---------------------------------------------------------------------

func get_best(id: String) -> int:
	return int(_load_best().get(id, 0))


func _load_best() -> Dictionary:
	if not FileAccess.file_exists(BEST_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BEST_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Stores the score if it beats the previous best of this scenario; returns the best.
func _save_best(score: float) -> int:
	if scenario_id == "":
		return int(score)
	var data := _load_best()
	var best := maxi(int(data.get(scenario_id, 0)), int(score))
	data[scenario_id] = best
	var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
	return best