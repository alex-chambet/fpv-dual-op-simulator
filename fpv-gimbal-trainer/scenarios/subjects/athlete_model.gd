class_name AthleteModel
extends Node3D
## The subject as an animated human: the rigged mannequin of the Quaternius "Universal Animation Library" (CC0,
## res://assets/characters/) in the sport's colours, with its gear:
##  - "run": the jog / sprint / walk animations of the library, played at the pace of the subject;
##  - "ski": skis, boots, poles and helmet; a stance built by code (hips lowered and pitched forward, IK legs with
##    the feet on the skis, IK arms holding the poles), from an athletic stance to a full downhill tuck (`tuck`);
##  - "bike": a mountain bike (wheels, frame, suspension fork, wide bar); the rider seated, feet on the pedals and
##    hands on the grips (IK), pedalling at moderate speed and freewheeling with level pedals when fast.
## Character space (the mannequin's): +Y up, the athlete faces +Z, the feet stand on y = 0.

const SCENE := "res://assets/characters/mannequin.glb"
const HEIGHT := 1.83          # m, the mannequin standing

var kind := "run"
## Skier: 0 = athletic stance, 1 = downhill tuck (set by the archetype every frame).
var tuck := 0.0
## Mountain bike: pedals turn below this speed (m/s), freewheel above.
const PEDAL_UNTIL := 8.5

var sk: Skeleton3D
var ap: AnimationPlayer
var ik: TwoBoneIK3D
var _char: Node3D            ## the mannequin (character space)
var _t := {}                 ## IK targets and poles: name -> Node3D
var _hips := -1
var _spine: Array[int] = []
var _neck := -1
var _head := -1
var _hips_rest: Transform3D  ## skeleton space
var _poles: Array[MeshInstance3D] = []
var _crank := 0.0
var _pedalling := 1.0
var _anim := ""
var wheels: Array[Node3D] = []


## True if the sheet's subject can be this animated athlete (a person on foot, on skis or on a bike).
static func supports(def: SubjectDefinition) -> bool:
	if def.placeholder_shape != "person" or def.environment == "falaise":
		return false
	return def.placeholder_gear in ["skis", "none", "bike"] and ResourceLoader.exists(SCENE)


## The model root of the subject (same contract as PlaceholderModel.build: fills `parts`).
static func build(def: SubjectDefinition, parts: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var a := AthleteModel.new()
	a.name = "Athlete"
	a.kind = {"skis": "ski", "bike": "bike"}.get(def.placeholder_gear, "run")
	body.add_child(a)
	a._setup(def)
	parts["body"] = body
	parts["legs"] = []
	parts["arms"] = []
	parts["horse_legs"] = []
	parts["wheels"] = a.wheels
	parts["wheel_radius"] = 0.36
	parts["athlete"] = a
	var k := def.effective_size() / (1.9 if a.kind == "bike" else HEIGHT)
	root.scale = Vector3.ONE * k
	parts["aim_y"] = {"ski": 0.95, "bike": 1.2, "run": 1.2}[a.kind] * k
	return root


func _setup(def: SubjectDefinition) -> void:
	_char = (load(SCENE) as PackedScene).instantiate()
	_char.name = "Mannequin"
	add_child(_char)
	# the library's characters face +Z; the subjects of the game face -Z
	rotation.y = PI
	sk = _char.find_child("Skeleton3D", true, false)
	ap = _char.find_child("AnimationPlayer", true, false)
	var mesh: MeshInstance3D = _char.find_child("Mannequin", true, false)
	var suit := def.placeholder_color
	var trim := def.placeholder_accent if kind == "ski" else suit.darkened(0.55)
	mesh.set_surface_override_material(0, _mat(suit, 0.55))
	mesh.set_surface_override_material(1, _mat(trim, 0.6))
	_hips = sk.find_bone("DEF-hips")
	for n in ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]:
		_spine.append(sk.find_bone(n))
	_neck = sk.find_bone("DEF-neck")
	_head = sk.find_bone("DEF-head")
	_hips_rest = sk.get_bone_global_rest(_hips)
	match kind:
		"ski":
			_ski_gear(def)
			_make_ik()
		"bike":
			_bike_gear(def)
			_make_ik()
		_:
			_run_gear(def)
			ap.play("Jog_Fwd")


# --- Animation ---------------------------------------------------------------------------------------

## Called every frame by the archetype (ArchetypeSubject._on_advanced).
func update(s: PathSubject, delta: float) -> void:
	match kind:
		"run":
			_run(s.speed_now)
		"ski":
			_pose_ski(delta)
		"bike":
			_pose_bike(s.speed_now, delta)


func _run(v: float) -> void:
	var want := "Walk" if v < 1.6 else ("Jog_Fwd" if v < 4.6 else "Sprint")
	if want != _anim:
		_anim = want
		ap.play(want, 0.35)
	var natural: float = {"Walk": 1.45, "Jog_Fwd": 3.3, "Sprint": 6.3}[want]
	ap.speed_scale = clampf(v / float(natural), 0.55, 1.7)


## Hips pitched forward (`pitch` rad) at `pos` (skeleton space), the spine bent by `bend` more, the head up.
func _body_pose(pos: Vector3, pitch: float, bend: float) -> void:
	sk.reset_bone_poses()
	var g := Transform3D(Basis(Vector3.RIGHT, pitch) * _hips_rest.basis, pos)
	_set_global(_hips, g)
	for b in _spine:
		_bend(b, bend / _spine.size())
	_bend(_neck, -(pitch + bend) * 0.45)
	_bend(_head, -(pitch + bend) * 0.4)


func _pose_ski(_delta: float) -> void:
	var t := smoothstep(0.0, 1.0, tuck)
	_body_pose(Vector3(0.0, lerpf(0.76, 0.6, t), lerpf(-0.14, -0.2, t)), lerpf(0.62, 0.95, t), lerpf(0.2, 0.35, t))
	for side in [-1.0, 1.0]:
		var sd := "L" if side > 0.0 else "R"
		_t["foot" + sd].position = Vector3(side * 0.11, 0.1, 0.02)
		_t["knee" + sd].position = Vector3(side * 0.16, 0.6, 1.6)
		_t["hand" + sd].position = Vector3(side * lerpf(0.3, 0.16, t), lerpf(0.8, 0.72, t), lerpf(0.4, 0.42, t))
		_t["elbow" + sd].position = Vector3(side * lerpf(0.8, 0.45, t), lerpf(0.75, 0.35, t), lerpf(-0.2, 0.2, t))
	# poles: from the grip, down and back to the snow (tucked under the arms in a tuck)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var grip: Vector3 = _t["hand" + ("L" if side > 0.0 else "R")].position
		var tip := Vector3(side * lerpf(0.42, 0.3, t), lerpf(0.04, 0.55, t), lerpf(-0.35, -0.85, t))
		_place_rod(_poles[i], grip + Vector3(0, 0.05, 0), tip)


## Bike geometry (character space).
const WHEEL_R := 0.36
const AXLE_Z := 0.58
const BB := Vector3(0.0, 0.34, -0.02)
const CRANK := 0.17
const SADDLE := Vector3(0.0, 0.98, -0.24)
const BAR := Vector3(0.0, 1.08, 0.5)


func _pose_bike(v: float, delta: float) -> void:
	var pedal := 1.0 if v < PEDAL_UNTIL else 0.0
	_pedalling = lerpf(_pedalling, pedal, 1.0 - exp(-delta / 0.6))
	# cadence: about 1.4 turns of the cranks per second at 4 m/s (low gear in the woods)
	if _pedalling > 0.05:
		_crank = fmod(_crank + delta * TAU * clampf(v / 2.9, 0.4, 2.2) * _pedalling, TAU)
	else:
		_crank = lerp_angle(_crank, 0.0, 1.0 - exp(-delta / 0.4))  # level pedals
	var stand := 1.0 - _pedalling  # freewheeling downhill: up off the saddle, weight back
	_body_pose(SADDLE + Vector3(0.0, 0.06 + 0.1 * stand, 0.02 - 0.08 * stand), lerpf(0.75, 0.65, stand), 0.3)
	for side in [-1.0, 1.0]:
		var sd := "L" if side > 0.0 else "R"
		var a := _crank + (0.0 if side > 0.0 else PI)
		var pedal_pos := BB + Vector3(side * 0.15, sin(a) * CRANK, cos(a) * CRANK)
		_t["foot" + sd].position = pedal_pos + Vector3(0, 0.07, -0.02)
		_t["knee" + sd].position = Vector3(side * 0.22, 1.1, 1.4)
		_t["hand" + sd].position = BAR + Vector3(side * 0.33, 0.02, 0.0)
		_t["elbow" + sd].position = Vector3(side * 0.75, 1.05, 0.1)
	_crank_node.rotation.x = -_crank


# --- Skeleton helpers ----------------------------------------------------------------------------------

func _set_global(bone: int, g: Transform3D) -> void:
	var p := sk.get_bone_parent(bone)
	var local := g if p < 0 else sk.get_bone_global_pose(p).affine_inverse() * g
	sk.set_bone_pose_position(bone, local.origin)
	sk.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())


## Rotates a bone (and what hangs from it) forward about the skeleton's X axis, around its own head.
func _bend(bone: int, angle: float) -> void:
	if bone < 0:
		return
	var g := sk.get_bone_global_pose(bone)
	_set_global(bone, Transform3D(Basis(Vector3.RIGHT, angle) * g.basis, g.origin))


func _make_ik() -> void:
	for n in ["footL", "footR", "kneeL", "kneeR", "handL", "handR", "elbowL", "elbowR"]:
		var t := Node3D.new()
		t.name = "IK_" + n
		_char.add_child(t)
		_t[n] = t
	ik = TwoBoneIK3D.new()
	ik.name = "IK"
	sk.add_child(ik)
	ik.set_setting_count(4)
	var chains := [["DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "footL", "kneeL"],
			["DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", "footR", "kneeR"],
			["DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L", "handL", "elbowL"],
			["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R", "handR", "elbowR"]]
	for i in chains.size():
		var c: Array = chains[i]
		ik.set_root_bone_name(i, c[0])
		ik.set_middle_bone_name(i, c[1])
		ik.set_end_bone_name(i, c[2])
		ik.set_target_node(i, ik.get_path_to(_t[c[3]]))
		ik.set_pole_node(i, ik.get_path_to(_t[c[4]]))


func _place_rod(rod: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	rod.transform = Transform3D(Basis(side, up, side.cross(up)).scaled(Vector3(1.0, d.length(), 1.0)), (a + b) * 0.5)


# --- Gear ------------------------------------------------------------------------------------------

func _ski_gear(def: SubjectDefinition) -> void:
	var ski_mat := _mat(def.placeholder_accent.darkened(0.1), 0.35)
	var dark := _mat(Color(0.07, 0.07, 0.08), 0.4)
	for side in [-1.0, 1.0]:
		var ski := Node3D.new()
		ski.position = Vector3(side * 0.11, 0.02, 0.1)
		_char.add_child(ski)
		_box(ski, Vector3(0.075, 0.022, 1.72), Vector3.ZERO, ski_mat)
		var tip := _box(ski, Vector3(0.075, 0.02, 0.2), Vector3(0, 0.035, 0.92), ski_mat)
		tip.rotation.x = -0.45
		_box(ski, Vector3(0.09, 0.05, 0.3), Vector3(0, 0.03, -0.1), dark)  # binding
	# boots, on the feet
	for sd in ["L", "R"]:
		var att := BoneAttachment3D.new()
		sk.add_child(att)
		att.bone_name = "DEF-foot." + sd
		_box(att, Vector3(0.13, 0.22, 0.17), Vector3(0, 0.06, 0.0), dark)
	# poles (placed every frame)
	var pole_mat := _mat(Color(0.75, 0.76, 0.8), 0.3)
	pole_mat.metallic = 0.7
	for i in 2:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.009
		cyl.bottom_radius = 0.007
		cyl.height = 1.0
		cyl.radial_segments = 6
		var rod := MeshInstance3D.new()
		rod.mesh = cyl
		rod.material_override = pole_mat
		_char.add_child(rod)
		_poles.append(rod)
	_helmet(def.placeholder_accent, true)


var _crank_node: Node3D


func _bike_gear(def: SubjectDefinition) -> void:
	var frame := _mat(def.placeholder_accent, 0.3)
	frame.metallic = 0.4
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.6)
	var steel := _mat(Color(0.7, 0.71, 0.74), 0.3)
	steel.metallic = 0.8
	var bike := Node3D.new()
	bike.name = "Bike"
	_char.add_child(bike)
	var rear := Vector3(0.0, WHEEL_R, -AXLE_Z)
	var front := Vector3(0.0, WHEEL_R, AXLE_Z)
	for c in [rear, front]:
		var w := Node3D.new()
		w.position = c
		w.rotation = Vector3(0.0, 0.0, PI * 0.5)
		bike.add_child(w)
		var tyre := TorusMesh.new()
		tyre.inner_radius = WHEEL_R - 0.06
		tyre.outer_radius = WHEEL_R
		tyre.rings = 24
		tyre.ring_segments = 8
		var tm := MeshInstance3D.new()
		tm.mesh = tyre
		tm.material_override = dark
		w.add_child(tm)
		var rim := TorusMesh.new()
		rim.inner_radius = WHEEL_R - 0.075
		rim.outer_radius = WHEEL_R - 0.055
		rim.rings = 24
		rim.ring_segments = 4
		var rm := MeshInstance3D.new()
		rm.mesh = rim
		rm.material_override = steel
		w.add_child(rm)
		for k in 8:  # spokes (seen as a blur when the wheel spins)
			var a := TAU * k / 8.0
			_tube(w, Vector3.ZERO, Vector3(cos(a), 0.0, sin(a)) * (WHEEL_R - 0.07), 0.004, steel)
		wheels.append(w)
	# frame: rear triangle, seat tube, top / down tube, head tube, suspension fork
	var head_top := BAR + Vector3(0.0, -0.22, -0.1)
	var head_bot := head_top + Vector3(0.0, -0.17, 0.06)
	var seat_top := SADDLE + Vector3(0.0, -0.1, 0.03)
	_tube(bike, BB, seat_top, 0.022, frame)
	_tube(bike, BB, head_bot, 0.028, frame)
	_tube(bike, seat_top + Vector3(0, -0.06, 0.02), head_top, 0.024, frame)
	_tube(bike, head_bot, head_top, 0.03, frame)
	for side in [-1.0, 1.0]:
		var o := Vector3(side * 0.06, 0.0, 0.0)
		_tube(bike, BB + o * 0.6, rear + o, 0.012, frame)
		_tube(bike, seat_top + o * 0.4 + Vector3(0, -0.05, 0), rear + o, 0.011, frame)
		_tube(bike, head_bot + o * 0.9, front + o, 0.022, steel)  # fork legs
	_tube(bike, SADDLE + Vector3(0, -0.12, 0.0), seat_top, 0.014, steel)
	_box(bike, Vector3(0.13, 0.04, 0.26), SADDLE + Vector3(0, -0.02, 0.0), dark)
	_tube(bike, head_top, BAR, 0.017, dark)
	_tube(bike, BAR + Vector3(-0.38, 0, 0), BAR + Vector3(0.38, 0, 0), 0.014, dark)
	_crank_node = Node3D.new()
	_crank_node.position = BB
	bike.add_child(_crank_node)
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.rotation.x = 0.0 if side > 0.0 else PI
		_crank_node.add_child(arm)
		_tube(arm, Vector3(side * 0.08, 0, 0), Vector3(side * 0.08, 0.0, CRANK), 0.012, steel)
		_box(arm, Vector3(0.1, 0.02, 0.07), Vector3(side * 0.14, 0.0, CRANK), dark)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.09
	ring.bottom_radius = 0.09
	ring.height = 0.01
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.material_override = steel
	rmi.rotation.z = PI * 0.5
	rmi.position = Vector3(0.05, 0, 0)
	_crank_node.add_child(rmi)
	_helmet(def.placeholder_accent.lightened(0.2), false)


## Runner: a cap with its peak, and a race bib on the chest.
func _run_gear(def: SubjectDefinition) -> void:
	var head := BoneAttachment3D.new()
	sk.add_child(head)
	head.bone_name = "DEF-head"
	var sph := SphereMesh.new()
	sph.radius = 0.118
	sph.height = 0.1
	sph.is_hemisphere = true
	sph.radial_segments = 16
	sph.rings = 4
	var cap := MeshInstance3D.new()
	cap.mesh = sph
	cap.material_override = _mat(def.placeholder_accent, 0.7)
	cap.position = Vector3(0.0, 0.13, -0.005)
	cap.scale = Vector3(1.0, 1.0, 1.1)
	head.add_child(cap)
	var peak := _box(head, Vector3(0.17, 0.012, 0.1), Vector3(0.0, 0.135, 0.15), _mat(def.placeholder_accent.darkened(0.25), 0.7))
	peak.rotation.x = -0.18
	var chest := BoneAttachment3D.new()
	sk.add_child(chest)
	chest.bone_name = "DEF-spine.003"
	_box(chest, Vector3(0.2, 0.15, 0.008), Vector3(0.0, 0.04, 0.125), _mat(Color(0.96, 0.96, 0.94), 0.8))
	_box(chest, Vector3(0.12, 0.05, 0.003), Vector3(0.0, 0.035, 0.13), _mat(Color(0.05, 0.05, 0.06), 0.8))


func _helmet(col: Color, goggles: bool) -> void:
	var att := BoneAttachment3D.new()
	sk.add_child(att)
	att.bone_name = "DEF-head"
	var sph := SphereMesh.new()
	sph.radius = 0.135
	sph.height = 0.2
	sph.is_hemisphere = true
	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.material_override = _mat(col, 0.25)
	mi.position = Vector3(0.0, 0.12, -0.01)
	mi.scale = Vector3(1.0, 1.0, 1.15)
	att.add_child(mi)
	if goggles:
		_box(att, Vector3(0.21, 0.06, 0.05), Vector3(0.0, 0.11, 0.11), _mat(Color(0.95, 0.55, 0.1), 0.05))
	else:
		_box(att, Vector3(0.2, 0.025, 0.08), Vector3(0.0, 0.2, 0.13), _mat(col.darkened(0.3), 0.4))  # visor


static func _mat(c: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _tube(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = maxf(a.distance_to(b), 0.001)
	cyl.radial_segments = 6
	cyl.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	parent.add_child(mi)
	return mi
