extends Control
## History screen: recorded sessions with their scores, sortable by date / scenario / score,
## filterable by scenario, with a progression chart and a Replay button per session.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const ALL := "All scenarios"

var _all: Array = []
var _sort_key := "date"
var _sort_desc := true
var _filter := ALL

var _filter_opt: OptionButton
var _sort_buttons := {}
var _summary: Label
var _chart: Control
var _list: VBoxContainer
var _message: Label


func _ready() -> void:
	SessionScorer.reset()
	SessionScorer.next_label = ""
	ScenarioMatrix.current = null
	SessionStore.replay_record = {}
	_all = SessionStore.index()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	var back := Button.new()
	back.text = "< Menu (Esc)"
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	top.add_child(back)
	var title := Label.new()
	title.text = "HISTORY"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label("Show"))
	_filter_opt = OptionButton.new()
	_filter_opt.custom_minimum_size.x = 240
	_filter_opt.item_selected.connect(func(i):
		_filter = _filter_opt.get_item_text(i)
		_refresh())
	top.add_child(_filter_opt)
	_fill_filter()

	_summary = _label("")
	_summary.modulate = Color(1, 1, 1, 0.75)
	root.add_child(_summary)

	_chart = Control.new()
	_chart.set_script(load("res://ui/score_chart.gd"))
	_chart.custom_minimum_size = Vector2(0, 170)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_chart)

	# Column headers = sort buttons
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	_sort_buttons["date"] = _header(head, "Date", "date", 160)
	_sort_buttons["scenario"] = _header(head, "Scenario", "scenario", 330)
	_sort_buttons["score"] = _header(head, "Score", "score", 110)
	var d := _label("Framing / Fluidity / Tracking")
	d.custom_minimum_size.x = 250
	head.add_child(d)
	var t := _label("Time")
	t.custom_minimum_size.x = 60
	head.add_child(t)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	_message = _label("")
	_message.modulate = Color(1, 0.6, 0.4)
	root.add_child(_message)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _header(parent: Control, text: String, key: String, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = width
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.pressed.connect(func():
		if _sort_key == key:
			_sort_desc = not _sort_desc
		else:
			_sort_key = key
			_sort_desc = key != "scenario"
		_refresh())
	parent.add_child(b)
	return b


func _fill_filter() -> void:
	var groups := {}
	for m in _all:
		groups[m.group] = true
	var names := groups.keys()
	names.sort()
	_filter_opt.clear()
	_filter_opt.add_item(ALL)
	for n in names:
		_filter_opt.add_item(n)


func _sorted(items: Array) -> Array:
	var out := items.duplicate()
	match _sort_key:
		"date":
			out.sort_custom(func(a, b): return a.timestamp < b.timestamp)
		"scenario":
			out.sort_custom(func(a, b): return a.title < b.title if a.title != b.title else a.timestamp < b.timestamp)
		"score":
			out.sort_custom(func(a, b): return a.overall < b.overall if a.overall != b.overall else a.timestamp < b.timestamp)
	if _sort_desc:
		out.reverse()
	return out


func _refresh() -> void:
	var items := _all.filter(func(m): return _filter == ALL or m.group == _filter)

	# Sort button labels show the active key / direction
	for k in _sort_buttons:
		var base: String = {"date": "Date", "scenario": "Scenario", "score": "Score"}[k]
		_sort_buttons[k].text = base + ((" v" if _sort_desc else " ^") if k == _sort_key else "")

	# Chart + summary use the chronological order
	var chrono := items.duplicate()
	chrono.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	var scores: Array[float] = []
	for m in chrono:
		scores.append(float(m.overall))
	_chart.set_scores(scores)
	_summary.text = _summary_text(scores)

	for c in _list.get_children():
		c.queue_free()
	if items.is_empty():
		var empty := _label("No recorded session yet. Finish a run to see it here.")
		empty.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(empty)
		return
	for m in _sorted(items):
		_list.add_child(_row(m))


func _summary_text(scores: Array[float]) -> String:
	if scores.is_empty():
		return "0 sessions"
	var sum := 0.0
	var best := 0.0
	for s in scores:
		sum += s
		best = maxf(best, s)
	var text := "%d sessions     average %.0f     best %.0f" % [scores.size(), sum / scores.size(), best]
	if scores.size() >= 6:
		var n := mini(5, scores.size() / 2)
		var last := 0.0
		var prev := 0.0
		for i in n:
			last += scores[scores.size() - 1 - i]
			prev += scores[scores.size() - 1 - n - i]
		var diff := (last - prev) / n
		text += "     last %d vs previous %d: %+.0f" % [n, n, diff]
	return text


func _row(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_cell(str(m.date), 160))
	row.add_child(_cell(str(m.title).trim_prefix("TRAINING - ") if m.group != ALL and str(m.title).begins_with("TRAINING") else str(m.title), 330))
	var score := _cell("%d  [%s]" % [m.overall, m.grade], 110)
	score.modulate = _score_color(float(m.overall))
	row.add_child(score)
	row.add_child(_cell("%.0f / %.0f / %.0f" % [m.framing, m.fluidity, m.tracking], 250))
	row.add_child(_cell("%.0f s" % m.run_time, 60))

	var replay := Button.new()
	replay.text = "Replay"
	var id: String = m.id
	replay.pressed.connect(func():
		if not SessionStore.start_replay(get_tree(), id):
			_message.text = SessionStore.last_error
	)
	row.add_child(replay)

	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func():
		if del.text == "Delete":
			del.text = "Sure?"
		else:
			SessionStore.delete(id)
			_all = SessionStore.index()
			_fill_filter()
			_refresh()
	)
	row.add_child(del)
	return row


func _cell(text: String, width: float) -> Label:
	var l := _label(text)
	l.custom_minimum_size.x = width
	l.clip_text = true
	return l


func _score_color(s: float) -> Color:
	if s >= 80.0:
		return Color(0.5, 1.0, 0.55)
	if s >= 50.0:
		return Color(1.0, 0.85, 0.4)
	return Color(1.0, 0.5, 0.45)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file(MENU_SCENE)
