class_name ArchetypeSubject
extends PathSubject
## The tracked subject of a sport: a PathSubject whose speed, lean and animation come from a
## SubjectArchetype configured by a SubjectDefinition (data). The same class serves every sport.

var def: SubjectDefinition
var arch: SubjectArchetype
var params: Dictionary
var plan: Dictionary
## Placeholder parts (body, legs, arms, wheels...), see PlaceholderModel.
var parts := {}
## Free per-subject state for the archetype (phase of the cadence, speed bursts...).
var state := {}
var seed_value := 0
## Jump events with their span as a ratio of the path: {r0, r1, ...}
var jump_events: Array[Dictionary] = []


func _init(d: SubjectDefinition, a: SubjectArchetype, p: Dictionary, pl: Dictionary, seed_v := 0) -> void:
	def = d
	arch = a
	params = p
	plan = pl
	seed_value = seed_v
	arch.configure_subject(self)


func _build_model() -> Node3D:
	var root := PlaceholderModel.build(def, parts)
	aim_height = float(parts["aim_y"])
	return root


func _on_ready_done() -> void:
	# Jump spans as ratios of the curve, from the positions of take-off and landing
	for ev in plan.events:
		if ev.get("type", "") != "jump" or curve == null or curve.get_baked_length() <= 0.0:
			continue
		var curve_len := curve.get_baked_length()
		var r0 := curve.get_closest_offset(ev.p0) / curve_len
		var r1 := curve.get_closest_offset(ev.p1) / curve_len
		var e: Dictionary = ev.duplicate()
		e["r0"] = r0
		e["r1"] = r1
		jump_events.append(e)
	arch.on_ready(self)


func _compute_speed(delta: float) -> float:
	return arch.compute_speed(self, delta)


func _on_advanced(delta: float) -> void:
	arch.animate(self, delta)


func _in_air() -> bool:
	return not current_jump().is_empty()


## The jump event the subject is in right now (empty dictionary if none).
func current_jump() -> Dictionary:
	for ev in jump_events:
		if progress_ratio >= float(ev.r0) - 0.0005 and progress_ratio <= float(ev.r1):
			return ev
	return {}
