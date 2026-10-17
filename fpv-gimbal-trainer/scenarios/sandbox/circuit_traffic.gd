class_name CircuitTraffic
extends Node3D
## The cars of the circuit sandbox: a field of racing cars of different classes lapping the
## Nürburgring Grand-Prix-Strecke, each at its own pace.
##
## Every car drives the racing line of the circuit at the speed its own class allows, computed by
## the same lap simulation as the training level (RaceCarPhysics): a GT3 laps in about 1 min 25,
## a GT4 in 1 min 30, a touring car in 1 min 35, a historic car in 1 min 42, a road GT in 1 min 56
## and the safety car in 2 min 20. They therefore catch each other up: a car that comes up behind a
## slower one closes in, pulls out of the line and goes past on the straight, then tucks back in.
## Nothing is scripted - the overtaking comes out of the speed difference.

## The field: class, colour, how much of the width the driver uses, and how hard they try.
const FIELD := [
	{"car": "gt3", "colour": Color(0.86, 0.12, 0.08), "accent": Color(0.95, 0.95, 0.95), "swing": 1.0, "pace": 1.0},
	{"car": "gt3", "colour": Color(0.05, 0.08, 0.12), "accent": Color(0.95, 0.72, 0.05), "swing": 0.97, "pace": 0.97},
	{"car": "gt4", "colour": Color(0.08, 0.32, 0.78), "accent": Color(0.95, 0.78, 0.05), "swing": 0.97, "pace": 1.0},
	{"car": "gt4", "colour": Color(0.95, 0.95, 0.93), "accent": Color(0.8, 0.1, 0.35), "swing": 0.93, "pace": 0.96},
	{"car": "tcr", "colour": Color(0.1, 0.55, 0.3), "accent": Color(0.95, 0.95, 0.95), "swing": 0.93, "pace": 1.0},
	{"car": "tcr", "colour": Color(0.95, 0.5, 0.05), "accent": Color(0.1, 0.1, 0.12), "swing": 0.9, "pace": 0.95},
	{"car": "historique", "colour": Color(0.92, 0.72, 0.1), "accent": Color(0.15, 0.15, 0.18), "swing": 0.88, "pace": 1.0},
	{"car": "gt_route", "colour": Color(0.12, 0.12, 0.14), "accent": Color(0.7, 0.7, 0.72), "swing": 0.7, "pace": 1.0},
	{"car": "safety", "colour": Color(0.93, 0.93, 0.95), "accent": Color(0.85, 0.5, 0.05), "swing": 0.5, "pace": 1.0},
]

const SAFE_GAP := 13.0      ## how close a car lets itself get to the one ahead, m
const LOOK_AHEAD := 70.0    ## how far ahead it looks, m
const PULL_OUT := 3.4       ## how far it moves off line to pass, m
const CAR_HALF_W := 1.15    ## half width of a car, m
const CAR_HALF_L := 2.35    ## half length of a car, m
const LANE_RATE := 1.7      ## how fast it crosses to that line, m/s

var layout: CircuitLayout
var cars: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _offsets := PackedFloat32Array()


func setup(world) -> void:
	layout = world.layout
	_rng.seed = 1234
	_offsets = CircuitTrack.line_offsets(layout.centre, maxf(layout.half_width - 1.5, 0.2))
	var n := FIELD.size()
	for i in n:
		var spec: Dictionary = FIELD[i]
		var car := RaceCarPhysics.car(str(spec.car))
		car["pace"] = float(car.get("pace", 1.0)) * float(spec.pace)
		var swing := float(spec.swing)
		var line := _line(swing)
		var speeds := RaceCarPhysics.solve_closed(line, car)
		var root := Node3D.new()
		root.name = "Car%d" % i
		var wheels: Array = []
		var lights: Array = []
		if str(spec.car) in ["gt3", "gt4", "tcr", "historique"]:
			var built := CarModel.race(root, spec.colour, spec.accent)
			wheels = built["wheels"]
			lights = built["brake_lights"]
		else:
			wheels = CarModel.build(root, spec.colour, 1 if str(spec.car) == "gt_route" else 0)
			if str(spec.car) == "safety":
				_light_bar(root, spec.accent)
		add_child(root)
		# spread the field round the lap, the slowest ones first so they get caught
		var s := layout.lap_length * (1.0 - float(i) / n) - 40.0
		cars.append({
			"spec": spec, "car": car, "node": root, "wheels": wheels, "lights": lights,
			"speeds": speeds, "swing": swing, "s": fposmod(s, layout.lap_length),
			"v": speeds[layout.index_at(s)], "lateral": 0.0, "pass_side": 0.0, "blocked": 0.0,
			"spin": 0.0, "accel": 0.0, "lat_now": 0.0, "pass_idx": -1,
		})


## The line this driver takes: the racing line, used more or less fully.
func _line(swing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in layout.centre.size():
		var off := layout.safe_offset(i, _offsets[i] * swing)
		var p := layout.centre[i] + layout.normals[i] * off
		out.append(Vector3(p.x, layout.surface[i], p.y))
	return out


func _light_bar(root: Node3D, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.1, 0.16, 0.42)
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.position = Vector3(0, 1.52, -0.4)
	root.add_child(mi)


func count() -> int:
	return cars.size()


func _process(delta: float) -> void:
	if layout == null or delta <= 0.0:
		return
	var lap := layout.lap_length
	# where each car sits across the track right now (its own line plus any move to overtake)
	for c in cars:
		c["lat_now"] = _offsets[layout.index_at(float(c.s))] * float(c.swing) + float(c.lateral)
	for ci in cars.size():
		var c: Dictionary = cars[ci]
		var i := layout.index_at(float(c.s))
		var speeds: PackedFloat32Array = c.speeds
		var free: float = speeds[i]
		var car: Dictionary = c.car

		# The nearest car ahead that is really in the way: one whose place across the track, where it
		# is now, is within a car's width of where this one will be when it gets there (their lines
		# cross, so the test has to be made at the OTHER car's point of the lap, not at this one's).
		var gap := LOOK_AHEAD
		var ahead_v := free
		var ahead_lat: float = float(c.lat_now)
		var ahead_idx := -1
		for oi in cars.size():
			if oi == ci:
				continue
			var o: Dictionary = cars[oi]
			var d := fposmod(float(o.s) - float(c.s), lap)
			if d > LOOK_AHEAD:
				continue
			var mine: float = _offsets[layout.index_at(float(o.s))] * float(c.swing) + float(c.lateral)
			if absf(float(o.lat_now) - mine) > 2.9:
				continue      # it goes past on the other side of the track
			if d < gap:
				gap = d
				ahead_v = float(o.v)
				ahead_lat = float(o.lat_now)
				ahead_idx = oi

		# Overtaking, as a state: a car held up long enough pulls out and stays out until the car it
		# is passing is well behind (otherwise it would tuck back in on top of it).
		var passing: int = int(c.pass_idx)
		if passing >= 0:
			var t: Dictionary = cars[passing]
			var rel := fposmod(float(t.s) - float(c.s), lap)
			if (rel > lap * 0.5 and rel < lap - 16.0) or (rel < lap * 0.5 and rel > 55.0):
				passing = -1
				c.pass_side = 0.0
		elif ahead_idx >= 0:
			var held: bool = gap < SAFE_GAP * 2.4 and free > ahead_v * 1.03
			c.blocked = clampf(float(c.blocked) + (delta if held else -delta * 1.6), 0.0, 3.0)
			if float(c.blocked) > 0.45:
				passing = ahead_idx
				c.pass_side = -signf(ahead_lat) if absf(ahead_lat) > 0.4 else (1.0 if _rng.randf() < 0.5 else -1.0)
		else:
			c.blocked = maxf(float(c.blocked) - delta * 1.6, 0.0)
		c.pass_idx = passing
		c.lateral = move_toward(float(c.lateral), float(c.pass_side) * PULL_OUT, LANE_RATE * delta)

		# car following: close in, but never faster than it can shed again
		var want := minf(free, ahead_v + (gap - SAFE_GAP) * 0.55) if gap < LOOK_AHEAD else free
		# once really alongside, it may use its own pace again
		if passing >= 0 and absf(float(c.lat_now) - float(cars[passing].lat_now)) > 2.9:
			want = free
		# last resort: never drive into the back of the car in front
		if gap < 7.5:
			want = minf(want, ahead_v - 2.0)
		want = maxf(want, 3.0)

		# realistic change of speed: the engine and the brakes of its own class
		var grip := float(car.grip) * float(car.get("pace", 1.0))
		var a_up: float = minf(float(car.power) * 1000.0 * float(car.get("pace", 1.0))
				/ (float(car.mass) * maxf(float(c.v), 4.0)), grip * 9.81 * float(car.get("drive", 0.5)))
		var a_down := grip * 9.81 * 1.1
		var before: float = c.v
		c.v = move_toward(float(c.v), want, (a_up if want > float(c.v) else a_down) * delta)
		c.accel = lerpf(float(c.accel), (float(c.v) - before) / maxf(delta, 0.0001), 1.0 - exp(-delta / 0.15))
		c.s = fposmod(float(c.s) + float(c.v) * delta, lap)
		_place(c, delta)


func _place(c: Dictionary, delta: float) -> void:
	var s := float(c.s)
	var i := layout.index_at(s)
	var base: float = _offsets[i] * float(c.swing) + float(c.lateral)
	var off := layout.safe_offset(i, base)
	var centre := layout.point_at(s)
	var nrm := layout.normal_at(s)
	var pos := Vector3(centre.x + nrm.x * off, 0.0, centre.z + nrm.y * off)
	pos.y = layout.ground(pos.x, pos.z) + 0.05
	var node: Node3D = c.node
	node.position = pos
	var dir := layout.dir_at(s)
	# the model looks along -Z
	var yaw := atan2(-dir.x, -dir.y)
	var slope := (layout.point_at(s + 6.0).y - layout.point_at(s - 6.0).y) / 12.0
	var accel := float(c.accel)
	var basis := Basis(Vector3.UP, yaw)
	basis = basis * Basis(Vector3.RIGHT, atan2(-slope, 1.0) + clampf(-accel * 0.0025, -0.045, 0.045))
	var lean := clampf(atan2(float(c.v) * _yaw_rate(s), 9.81) * 0.12, -0.06, 0.06)
	basis = basis * Basis(Vector3.BACK, lean)
	node.basis = basis
	# wheels and brake lights
	var wheels: Array = c.wheels
	if not wheels.is_empty():
		c.spin = float(c.spin) + float(c.v) * delta / 0.34
		for w in wheels:
			(w as MeshInstance3D).rotation = Vector3(float(c.spin), 0.0, PI * 0.5)
	var braking := clampf(-accel / 6.0, 0.0, 1.0)
	for light in c.lights:
		var mat := (light as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = lerpf(0.25, 4.0, braking)


## Yaw rate of the track at a lap distance (rad per metre x speed = rad/s), for the body roll.
func _yaw_rate(s: float) -> float:
	var i := layout.index_at(s)
	return layout.curvature[i]


## Horizontal push getting a drone sphere out of the cars.
func push(pos: Vector3, radius: float) -> Vector3:
	var best := Vector3.ZERO
	for c in cars:
		var node: Node3D = c.node
		var p: Vector3 = node.position
		if pos.y > p.y + 1.5 + radius or pos.y < p.y - radius:
			continue
		var local := (pos - p)
		local.y = 0.0
		local = local.rotated(Vector3.UP, -node.rotation.y)
		var hx := 1.1 + radius
		var hz := 2.4 + radius
		if absf(local.x) > hx or absf(local.z) > hz:
			continue
		var dx := hx - absf(local.x)
		var dz := hz - absf(local.z)
		var push_local := Vector3(signf(local.x) * dx, 0.0, 0.0) if dx < dz else Vector3(0.0, 0.0, signf(local.z) * dz)
		var out := push_local.rotated(Vector3.UP, node.rotation.y)
		if out.length() > best.length():
			best = out
	return best
