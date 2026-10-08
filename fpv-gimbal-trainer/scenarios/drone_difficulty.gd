class_name DroneDifficulty
extends RefCounted
## What makes a training session hard for the gimbal operator. The drone ALWAYS flies smoothly
## (bounded acceleration, no sudden change of direction): the difficulty comes only from
##   1. the drone movement  (an orbit is harder than a lateral follow),
##   2. the axes the operator has to handle (pan only / tilt only at the low levels, then pan AND tilt
##      together),
##   3. the proximity to the subject (the closer the drone, the faster the subject crosses the frame).
## The session level (1..6) sets points 2 and 3 and how fast the movement is flown; the subject itself
## (speed, turns) is never changed by the level. Level 6 ("Expert") also brings the expert movements
## (EXPERT_MOVEMENTS): figures flown by a fast cinema FPV drone (entries from afar into an orbit, dives
## onto the subject, head-on crossings, spirals), still with bounded acceleration.

## Version of the drone flight model. A training session recorded with an older model cannot be replayed
## (the drone flew differently); the guided courses keep the same geometry and still replay.
const FLIGHT_VERSION := 2

## Highest level (Expert).
const MAX_LEVEL := 6
const EXPERT_LEVEL := 6
## Movements made of chained figures (MovementPlanner._build_figures): only drawn at random at the Expert level.
const EXPERT_MOVEMENTS := ["approach_orbit", "dive", "choreo"]

## Rank of each drone movement, 1 (easy) to 6 (expert): used to draw a movement that suits the level.
const MOVEMENT_TIER := {"pursuit": 1, "lateral": 1, "frontal": 2, "reveal": 3, "orbit": 4, "flyby": 5,
		"approach_orbit": 6, "dive": 6, "choreo": 6}

## Distance of the drone, relative to the level 3 distance (bigger = farther = easier).
const PROXIMITY := [1.45, 1.22, 1.0, 0.82, 0.68, 0.56]
## Sway of the drone around its base position, as an angle seen from the subject: it makes the
## camera pan (azimuth) and tilt (elevation). Single axis at levels 1-2, both axes from level 3.
const PAN_AMP_DEG := [12.0, 17.0, 14.0, 19.0, 25.0, 30.0]
const PAN_PERIOD := [16.0, 13.0, 14.0, 12.0, 10.0, 8.5]
const TILT_AMP_DEG := [7.0, 11.0, 7.0, 11.0, 15.0, 18.0]
const TILT_PERIOD := [14.0, 12.0, 12.0, 11.0, 9.5, 8.0]
## Seconds for one turn of an orbit, and shortest time of the sweep of a reveal / a flyby (shorter =
## faster). A sweep over a long distance takes longer: it never exceeds ACCEL_CAP (see MovementPlanner).
const ORBIT_PERIOD := [30.0, 24.0, 19.0, 15.0, 12.0, 8.0]
const SWEEP_TIME := [9.0, 8.0, 7.0, 6.0, 5.0, 4.0]
## Safety limits of the flight plan: 95th percentile of the pan / tilt speed of the subject in the
## image (deg/s), 99th percentile of the drone acceleration (m/s²). The planner moves the drone away
## and smooths its path until they are respected.
const PAN_CAP := [16.0, 24.0, 34.0, 46.0, 60.0, 78.0]
const TILT_CAP := [10.0, 14.0, 20.0, 28.0, 38.0, 50.0]
const ACCEL_CAP := [3.5, 4.0, 4.5, 5.2, 6.0, 9.0]
## Figures (expert movements): speed of the drone relative to the subject on the long legs (m/s), and
## time multiplier of the figures (bigger = slower). A figure flown below the Expert level is calmer.
const FIGURE_SPEED := [6.0, 7.5, 9.0, 10.5, 12.0, 17.0]
const FIGURE_TEMPO := [1.8, 1.55, 1.35, 1.2, 1.1, 1.0]
## Obstacles hiding the subject (scenery): the same at every level, the level is about the drone only.
const OCCLUSION := [0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
## Time constant (s) of the drone following the subject's progress: the drone does not copy the
## accelerations and braking of the subject (stop and go, corners, jumps); the subject drifts a little
## ahead of / behind its place in the shot instead.
const FOLLOW_TAU := 2.0
## Smaller time constants tried by the planner when the limits cannot be met with the default one.
const FOLLOW_TAU_CANDIDATES := [2.0, 1.2, 0.6]
## Time constant (s) of the slow pull of the drone's progress towards the subject's (the lag never accumulates).
const FOLLOW_PULL := 6.0


## Value of a per-level table at a (possibly fractional) level.
static func at(table: Array, level: float) -> float:
	var x := clampf(level, 1.0, float(table.size())) - 1.0
	var i := mini(int(x), table.size() - 2)
	return lerpf(float(table[i]), float(table[i + 1]), x - i)


## Everything the planner needs for a level.
static func params(level: float) -> Dictionary:
	return {
		"level": level,
		"proximity": at(PROXIMITY, level),
		"pan_amp": deg_to_rad(at(PAN_AMP_DEG, level)),
		"pan_period": at(PAN_PERIOD, level),
		"tilt_amp": deg_to_rad(at(TILT_AMP_DEG, level)),
		"tilt_period": at(TILT_PERIOD, level),
		"both_axes": level >= 2.5,
		"orbit_period": at(ORBIT_PERIOD, level),
		"sweep_time": at(SWEEP_TIME, level),
		"pan_cap": at(PAN_CAP, level),
		"tilt_cap": at(TILT_CAP, level),
		"accel_cap": at(ACCEL_CAP, level),
		"figure_speed": at(FIGURE_SPEED, level),
		"figure_tempo": at(FIGURE_TEMPO, level),
	}


## Session parameters stored in a SessionConfig (see ScenarioMatrix.level_params).
static func session_params(level: int) -> Dictionary:
	return {
		"level": level,
		"speed_scale": 1.0, "turn_scale": 1.0,   # the subject is never changed by the level
		"occlusion": at(OCCLUSION, level),
		"aggression": clampf((level - 1) / 4.0, 0.0, 1.0),
	}


## A drone movement among `allowed`, more likely to be one whose rank is close to the level. The expert
## figures are only drawn at the Expert level, and the Expert level only draws the hardest movements.
static func pick_movement(allowed: Array, level: int, rng: RandomNumberGenerator) -> String:
	var kept := allowed.filter(func(m): return (movement_tier(m) >= 4) if level >= EXPERT_LEVEL else not (m in EXPERT_MOVEMENTS))
	if not kept.is_empty():
		allowed = kept
	var weights: Array[float] = []
	var total := 0.0
	for m in allowed:
		var d := float(int(MOVEMENT_TIER.get(m, 3)) - level)
		var w := exp(-d * d / 3.0) + 0.02
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in allowed.size():
		r -= weights[i]
		if r <= 0.0:
			return str(allowed[i])
	return str(allowed[allowed.size() - 1])


## One-line description of a level, in French (menu).
static func describe(level: int) -> String:
	match clampi(level, 1, MAX_LEVEL):
		1: return "Drone loin du sujet ; un seul axe à gérer (pan ou tilt), mouvements lents."
		2: return "Drone assez loin ; un seul axe à la fois (pan ou tilt), un peu plus ample."
		3: return "Distance moyenne ; pan et tilt combinés, mouvements modérés."
		4: return "Drone proche ; pan et tilt combinés, mouvements plus amples et plus rapides."
		5: return "Drone très proche ; pan et tilt combinés, mouvements amples et rapides."
		_: return "EXPERT : drone de course rapide qui enchaîne les figures (entrées de loin en orbite, plongeons sur le sujet, croisements face à face, spirales). Le sujet passe de minuscule à plein cadre, pan et tilt à fond."


## Rating of a movement, 1..5 (menu).
static func movement_tier(movement: String) -> int:
	return int(MOVEMENT_TIER.get(movement, 3))
