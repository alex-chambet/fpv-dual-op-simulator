class_name SandboxFauna
extends Node3D
## A small herd of wild (riderless) horses roaming the fields of the sandbox, away from the roads and the village.
## Each one wanders at its own pace towards a randomly picked point, turning smoothly, with a 4-leg walk cycle
## (same gait as the horse sport subject). Horses are solid for the drone (push), like the traffic.

const COUNT := 7
const HORSE_COLORS := [Color(0.42, 0.27, 0.16), Color(0.16, 0.11, 0.08), Color(0.58, 0.37, 0.19),
		Color(0.74, 0.7, 0.64), Color(0.3, 0.2, 0.12)]
const WALK_SPEED := Vector2(1.6, 2.4)   ## m/s, picked per horse
const TURN_RATE := deg_to_rad(50.0)
const RETARGET_TIME := Vector2(7.0, 15.0)
const RANGE_R := Vector2(35.0, 90.0)     ## how far a new target may be from the current spot
const HALF_LEN := 1.1
const HALF_WIDTH := 0.5
const HEIGHT := 1.75

class Horse:
	var node: Node3D
	var legs: Array = []
	var pos := Vector3.ZERO
	var heading := 0.0
	var speed := 2.0
	var target := Vector3.ZERO
	var retarget_left := 0.0
	var phase := 0.0

var world: SandboxWorld
var _rng := RandomNumberGenerator.new()
var _horses: Array[Horse] = []


func setup(w: SandboxWorld) -> void:
	world = w
	_rng.seed = SandboxWorld.SEED + 53
	for _i in COUNT:
		var h := Horse.new()
		h.pos = _pick_spot(Vector3.ZERO, RANGE_R.y + VILLAGE_MARGIN)
		h.heading = _rng.randf_range(0.0, TAU)
		h.speed = _rng.randf_range(WALK_SPEED.x, WALK_SPEED.y)
		h.target = h.pos
		h.retarget_left = _rng.randf_range(0.0, 2.0)
		h.phase = _rng.randf_range(0.0, TAU)
		var col: Color = HORSE_COLORS[_rng.randi() % HORSE_COLORS.size()]
		var root := Node3D.new()
		h.legs = _build_horse(root, col, col.darkened(0.55))
		root.position = h.pos
		add_child(root)
		h.node = root
		_horses.append(h)
	set_process(true)


const VILLAGE_MARGIN := 80.0


## A spot in the open fields: far enough from the roads and the village, inside the playable map.
func _pick_spot(near: Vector3, radius: float) -> Vector3:
	for _try in 40:
		var a := _rng.randf_range(0.0, TAU)
		var d := _rng.randf_range(0.0, radius)
		var p := near + Vector3(cos(a), 0.0, sin(a)) * d if near != Vector3.ZERO else Vector3(
				_rng.randf_range(-SandboxWorld.HALF + 50.0, SandboxWorld.HALF - 50.0), 0.0,
				_rng.randf_range(-SandboxWorld.HALF + 50.0, SandboxWorld.HALF - 50.0))
		p.x = clampf(p.x, -SandboxWorld.HALF + 40.0, SandboxWorld.HALF - 40.0)
		p.z = clampf(p.z, -SandboxWorld.HALF + 40.0, SandboxWorld.HALF - 40.0)
		if Vector2(p.x, p.z).length() < SandboxWorld.VILLAGE_R + VILLAGE_MARGIN:
			continue
		if world.near_road(p.x, p.z, 22.0):
			continue
		p.y = world.ground(p.x, p.z)
		return p
	return Vector3(near.x, world.ground(near.x, near.z), near.z)


func _process(delta: float) -> void:
	for h in _horses:
		h.retarget_left -= delta
		if h.retarget_left <= 0.0 or Vector2(h.pos.x - h.target.x, h.pos.z - h.target.z).length() < 3.0:
			h.target = _pick_spot(h.pos, _rng.randf_range(RANGE_R.x, RANGE_R.y))
			h.retarget_left = _rng.randf_range(RETARGET_TIME.x, RETARGET_TIME.y)
		var to_target := Vector2(h.target.x - h.pos.x, h.target.z - h.pos.z)
		if to_target.length() > 0.01:
			var want := atan2(-to_target.x, -to_target.y)
			h.heading = h.heading + clampf(angle_difference(h.heading, want), -TURN_RATE * delta, TURN_RATE * delta)
		var fwd := Vector3(-sin(h.heading), 0.0, -cos(h.heading))
		h.pos += fwd * h.speed * delta
		h.pos.y = world.ground(h.pos.x, h.pos.z)
		var push := world.push(h.pos, 0.5)
		if push.length() > 0.0:
			h.pos += push
		h.node.position = h.pos
		h.node.rotation.y = h.heading
		h.phase += TAU * 0.55 * (h.speed / 2.0) * delta
		var swing := sin(h.phase)
		if h.legs.size() == 4:
			h.legs[0].rotation.x = swing * 0.8
			h.legs[1].rotation.x = sin(h.phase + 0.5) * 0.8
			h.legs[2].rotation.x = -swing * 0.8
			h.legs[3].rotation.x = -sin(h.phase + 0.5) * 0.8


## The horse body (brown/black/chestnut/grey), reusing the primitives of the sport horse model but without a rider.
static func _build_horse(parent: Node3D, col: Color, dark: Color) -> Array:
	var brown := PlaceholderModel._mat(col)
	var dmat := PlaceholderModel._mat(dark)
	var body := PlaceholderModel._mesh(parent, PlaceholderModel._capsule(0.3, 1.6), brown, Vector3(0, 1.0, 0))
	body.rotation.x = PI * 0.5
	var neck := PlaceholderModel._mesh(parent, PlaceholderModel._capsule(0.13, 0.75), brown, Vector3(0, 1.4, -0.85))
	neck.rotation.x = -0.7
	var head := PlaceholderModel._mesh(parent, PlaceholderModel._capsule(0.1, 0.5), brown, Vector3(0, 1.6, -1.2))
	head.rotation.x = -1.15
	var tail := PlaceholderModel._mesh(parent, PlaceholderModel._capsule(0.05, 0.6), dmat, Vector3(0, 1.05, 0.95))
	tail.rotation.x = 0.7
	var legs := []
	for z in [-0.6, 0.6]:
		for side in [-1.0, 1.0]:
			legs.append(PlaceholderModel._limb(parent, Vector3(side * 0.16, 0.95, z), 0.06, 0.9, dmat))
	return legs


## Horizontal push getting a sphere of radius r out of the horses, like the vehicles.
func push(pos: Vector3, r: float) -> Vector3:
	var best := Vector3.ZERO
	for h in _horses:
		if Vector2(h.pos.x - pos.x, h.pos.z - pos.z).length() > HALF_LEN + 3.0:
			continue
		var p := SandboxWorld.box_push(pos, r, h.pos, h.heading, HALF_WIDTH, HALF_LEN, HEIGHT)
		if p.length() > best.length():
			best = p
	return best


func count() -> int:
	return _horses.size()
