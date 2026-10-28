class_name SessionConfig
extends RefCounted
## One session: a sport (SubjectDefinition) x a drone movement x a difficulty level - either a
## generated training session or a fixed scenario of the menu (scripted drone).

var subject: SubjectDefinition
## Drone movement id (pursuit, lateral, frontal, orbit, reveal, flyby) or "legacy" (fixed scenario).
var movement := "lateral"
var level := 3
## speed_scale, turn_scale, occlusion (0..1), aggression (0..1) - derived from the level.
var params := {}
var seed := 0
## Focal length (mm, full-frame) of the lens, see SENSOR_HEIGHT_MM.
var lens := 24
## 2-player session: a pilot flies the drone (FPV, acro) with a second controller, the gimbal operator films.
var two_player := false
## +1 / -1: which side of the subject the drone favours.
var side := 1.0
## Time of day / weather (Ambience id): noon, morning, golden, overcast, snowfall.
var ambience := "noon"
## Which choices the player fixed (the others are re-rolled for the next session).
var lock_subject := false
var lock_movement := false
var lock_level := false
## The level is the base difficulty of the sport.
var level_auto := false
## Menu filters used to pick the sport of the next sessions.
var filter := {}
## Fixed scenario of the menu: scripted drone, fixed layout, scores stored under fixed_id.
var fixed := false
var fixed_id := ""
var fixed_title := ""
## Movement drill ("Mouvements" menu): which speed step of ScenarioMatrix.DRILL_STEPS the subject
## moves at. -1 = not a drill.
var drill_step := -1


func is_drill() -> bool:
	return drill_step >= 0


const LENSES := [24, 35, 50, 85]
## Height (mm) of the recorded image on a full-frame sensor filming 16:9 (36 x 20.25 mm, e.g. Sony FX3 / FX6,
## A7S III): the reference the focal lengths are quoted against. A 16:9 window then shows exactly what that
## camera records (24 mm: 73.7 deg wide, 45.8 deg high). The game used to give 60 deg high at 24 mm, i.e. a
## 27.7 mm-high sensor that does not exist: every lens looked ~1.4x wider than the real one.
const SENSOR_HEIGHT_MM := 20.25
## Vertical field of view (degrees) of a lens (Camera3D keeps the height: KEEP_HEIGHT).
static func fov_for(mm: int) -> float:
	return rad_to_deg(2.0 * atan(SENSOR_HEIGHT_MM * 0.5 / float(mm)))


func movement_name() -> String:
	return str(ScenarioMatrix.movement_info(movement).get("name", "Scripted"))


func title() -> String:
	if fixed:
		return fixed_title
	if is_drill():
		return "MOUVEMENT - %s / %s / level %d%s" % [movement_name(),
				ScenarioMatrix.DRILL_STEPS[drill_step].name, level, "" if lens == 24 else " / %d mm" % lens]
	if two_player:
		return "2 PLAYERS - %s%s" % [subject.display_name, "" if lens == 24 else " / %d mm" % lens]
	return "TRAINING - %s / %s / level %d%s" % [subject.display_name, movement_name(), level, "" if lens == 24 else " / %d mm" % lens]


func scenario_id() -> String:
	if fixed:
		return fixed_id
	if is_drill():  # one score board per figure, speed step and level
		return "drill_%s_v%d_L%d%s" % [movement, drill_step, level, "" if lens == 24 else "_%dmm" % lens]
	if two_player:
		return "duo_%s%s" % [subject.id, "" if lens == 24 else "_%dmm" % lens]
	return "matrix_%s_%s_L%d%s" % [subject.id, movement, level, "" if lens == 24 else "_%dmm" % lens]


## Plain data, saved with the recorded session (the sport sheet is embedded: a replay never
## depends on later edits of the catalogue).
func to_dict() -> Dictionary:
	return {
		"definition": subject.to_dict(), "subject": subject.id, "movement": movement, "level": level,
		"seed": seed, "side": side, "lens": lens, "two_player": two_player, "fixed": fixed, "fixed_id": fixed_id, "fixed_title": fixed_title,
		"ambience": ambience, "drill_step": drill_step,
	}
