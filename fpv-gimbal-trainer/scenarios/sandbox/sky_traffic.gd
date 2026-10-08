class_name SkyTraffic
extends Node3D
## Air traffic of the sandbox: a light plane that circles high over the countryside (wide banked turns, spinning
## propeller) and a helicopter that patrols around the village, slowing down to hover over two spots. Both fly smooth
## closed paths (bounded bank and pitch), well above the drone's auto flight (45 m at most) and out of its way.

const GRAVITY := 9.81

## Aircraft: the model (nose towards -Z), its path and its attitude filters.
class Craft:
	var node: Node3D
	var rotors: Array = []       ## [{node, axis: Vector3, rate: rad/s}]
	var u := 0.0                 ## parameter along the closed path
	var speed := 50.0            ## m/s along the path
	var heli := false
	var heading := 0.0           ## rad, 0 = towards -Z
	var yaw_rate := 0.0
	var bank := 0.0
	var pitch := 0.0
	var pos := Vector3.ZERO
	var started := false

var _plane: Craft
var _heli: Craft
var _world: SandboxWorld
static var _mats := {}


func setup(w: SandboxWorld) -> void:
	_world = w
	_plane = Craft.new()
	_plane.node = _build_plane()
	_plane.u = 0.7
	_plane.speed = 40.0
	_heli = Craft.new()
	_heli.node = _build_helicopter()
	_heli.heli = true
	_heli.u = 2.2
	_heli.speed = 24.0
	for c in [_plane, _heli]:
		c.node.name = "Helicopter" if c.heli else "Plane"
		c.rotors = c.node.get_meta("rotors")
		add_child(c.node)
		_step(c, 0.0)
	set_process(true)


# --- Paths ------------------------------------------------------------------------------------

## Point of the path of the plane: a wide loop around the map with a gentle altitude change.
static func plane_path(u: float, ground_ref: float) -> Vector3:
	var a := 1000.0
	var b := 620.0
	return Vector3(a * cos(u) + 120.0, ground_ref + 190.0 + 25.0 * sin(2.0 * u + 0.5), b * sin(u) - 60.0)


## Point of the helicopter's path: a loop around the village (the height is set from the ground).
static func heli_path(u: float) -> Vector3:
	return Vector3(430.0 * cos(u) + 40.0, 0.0, 330.0 * sin(u) - 30.0)


## Share of the cruise speed of the helicopter at u: it slows down almost to a hover over two spots.
static func heli_speed_factor(u: float) -> float:
	var f := 1.0
	for h in [0.9, 4.1]:
		var d := angle_difference(u, h)
		f -= 0.92 * exp(-d * d / 0.06)
	return f


func _path(c: Craft, u: float) -> Vector3:
	if c.heli:
		var p := heli_path(u)
		p.y = _world.ground(p.x, p.z) + 95.0 + 14.0 * sin(2.0 * u)
		return p
	return plane_path(u, _world.ground(0.0, 0.0))


# --- Motion -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if delta <= 0.0:
		return
	_step(_plane, delta)
	_step(_heli, delta)


func _step(c: Craft, delta: float) -> void:
	var du := 0.002
	var p := _path(c, c.u)
	var tangent := _path(c, c.u + du) - _path(c, c.u - du)
	var length := tangent.length() / (2.0 * du)  # metres per unit of u
	var cruise := c.speed * (heli_speed_factor(c.u) if c.heli else 1.0)
	c.u = fposmod(c.u + cruise / maxf(length, 1.0) * delta, TAU)
	var flat := Vector2(tangent.x, tangent.z)
	var target_heading := atan2(-flat.x, -flat.y)
	var first := not c.started
	c.started = true
	if first:
		c.heading = target_heading
		c.pos = p
	elif delta > 0.0:
		# a helicopter turns slowly (it swings round while it hovers), a plane follows its path
		var k := 1.0 - exp(-delta / 1.3) if c.heli else 1.0
		var new_heading: float = c.heading + angle_difference(c.heading, target_heading) * k
		c.yaw_rate += (angle_difference(c.heading, new_heading) / delta - c.yaw_rate) * (1.0 - exp(-delta / 0.6))
		c.heading = new_heading
		var prev_y: float = c.pos.y
		c.pos = p
		if c.heli:
			c.pos.y = lerpf(prev_y, p.y, 1.0 - exp(-delta / 1.5))
	# attitude: banked into the turn (left turn = positive roll: the right wing goes up), nose along the climb
	var horizontal := flat.length()
	var climb := atan2(tangent.y, maxf(horizontal, 0.001))
	var bank_target := atan2(cruise * c.yaw_rate, GRAVITY)
	var pitch_target := climb
	if c.heli:
		bank_target *= 0.5
		pitch_target = -deg_to_rad(minf(cruise * 0.45, 9.0))
	bank_target = clampf(bank_target, -deg_to_rad(36.0), deg_to_rad(36.0))
	var kb := 1.0 - exp(-delta / 0.5) if delta > 0.0 else 1.0
	c.bank += (bank_target - c.bank) * kb
	c.pitch += (pitch_target - c.pitch) * kb
	c.node.position = c.pos
	c.node.basis = Basis(Vector3.UP, c.heading) * Basis(Vector3.RIGHT, c.pitch) * Basis(Vector3(0, 0, 1), c.bank)
	for r in c.rotors:
		r.node.rotate_object_local(r.axis, r.rate * delta)


# --- Models -----------------------------------------------------------------------------------

func _mat(col: Color, rough := 0.45, metal := 0.15) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [col.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


func _glass_mat() -> StandardMaterial3D:
	return _mat(Color(0.04, 0.07, 0.1), 0.08, 0.6)


func _disc_mat() -> StandardMaterial3D:
	var key := "disc"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.12, 0.12, 0.1)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r_top: float, r_bottom: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = 2.0 * r
	s.radial_segments = 20
	s.rings = 10
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	return c


## Light high-wing plane with a propeller (about 12 m long, 16 m of wingspan: a little more than a real light plane so
## that it can be seen from far away).
func _build_plane() -> Node3D:
	var root := Node3D.new()
	var s := Node3D.new()
	s.scale = Vector3.ONE * 1.5
	root.add_child(s)
	var white := _mat(Color(0.93, 0.94, 0.96))
	var red := _mat(Color(0.75, 0.1, 0.08))
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.7, 0.0)
	var rx := Vector3(PI * 0.5, 0.0, 0.0)
	_add(s, _capsule(0.95, 8.6), white, Vector3.ZERO, rx)                       # fuselage
	_add(s, _cyl(0.2, 0.8, 4.2), white, Vector3(0.0, 0.1, 6.0), rx)             # tail cone
	_add(s, _box(Vector3(1.72, 0.5, 1.5)), _glass_mat(), Vector3(0.0, 0.5, -1.3))  # windows
	_add(s, _box(Vector3(11.0, 0.16, 1.7)), white, Vector3(0.0, 0.95, -0.7))    # wing
	_add(s, _box(Vector3(1.0, 0.18, 1.72)), red, Vector3(5.7, 0.95, -0.7))      # wing tips
	_add(s, _box(Vector3(1.0, 0.18, 1.72)), red, Vector3(-5.7, 0.95, -0.7))
	_add(s, _box(Vector3(4.0, 0.12, 1.0)), white, Vector3(0.0, 0.35, 7.6))      # tailplane
	_add(s, _box(Vector3(0.12, 1.9, 1.3)), red, Vector3(0.0, 1.4, 7.3), Vector3(deg_to_rad(-12.0), 0.0, 0.0))  # fin
	for side in [-1.0, 1.0]:
		_add(s, _box(Vector3(0.1, 1.5, 0.12)), dark, Vector3(side * 1.9, 0.1, -0.6), Vector3(0.0, 0.0, side * deg_to_rad(-38.0)))  # wing struts
		_add(s, _box(Vector3(0.1, 0.9, 0.12)), dark, Vector3(side * 1.0, -1.0, -1.2))     # undercarriage legs
		_add(s, _cyl(0.3, 0.3, 0.16, 14), dark, Vector3(side * 1.0, -1.5, -1.2), Vector3(0.0, 0.0, PI * 0.5))
	_add(s, _box(Vector3(0.1, 0.8, 0.12)), dark, Vector3(0.0, -1.0, -3.3))
	_add(s, _cyl(0.22, 0.22, 0.14, 12), dark, Vector3(0.0, -1.45, -3.3), Vector3(0.0, 0.0, PI * 0.5))
	# propeller: the pivot spins about the Z axis
	var prop := Node3D.new()
	prop.position = Vector3(0.0, 0.0, -4.95)
	s.add_child(prop)
	_add(prop, _sphere(0.3), red, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 1.3))
	_add(prop, _box(Vector3(0.16, 3.0, 0.05)), dark, Vector3.ZERO)
	_add(prop, _cyl(1.5, 1.5, 0.01, 24), _disc_mat(), Vector3(0.0, 0.0, -0.05), rx)
	var craft_rotor := {"node": prop, "axis": Vector3(0, 0, 1), "rate": 45.0}
	root.set_meta("rotors", [craft_rotor])
	return root


## Helicopter: red and white fuselage, glass nose, tail boom with a tail rotor, four-blade main rotor, skids.
func _build_helicopter() -> Node3D:
	var root := Node3D.new()
	var s := Node3D.new()
	s.scale = Vector3.ONE * 1.4
	root.add_child(s)
	var red := _mat(Color(0.8, 0.09, 0.07))
	var white := _mat(Color(0.94, 0.94, 0.95))
	var dark := _mat(Color(0.1, 0.1, 0.11), 0.7, 0.0)
	var rx := Vector3(PI * 0.5, 0.0, 0.0)
	_add(s, _sphere(1.0), red, Vector3(0.0, 0.0, 0.2), Vector3.ZERO, Vector3(1.15, 1.2, 2.1))     # cabin
	_add(s, _sphere(1.0), _glass_mat(), Vector3(0.0, 0.15, -1.35), Vector3.ZERO, Vector3(1.0, 0.85, 1.1))  # canopy
	_add(s, _sphere(1.0), white, Vector3(0.0, 0.75, 0.9), Vector3.ZERO, Vector3(0.95, 0.5, 1.6))   # engine cowling
	_add(s, _cyl(0.12, 0.45, 5.0), white, Vector3(0.0, 0.45, 4.4), rx)                           # tail boom
	_add(s, _box(Vector3(0.1, 1.3, 0.9)), red, Vector3(0.0, 1.0, 6.6), Vector3(deg_to_rad(-15.0), 0.0, 0.0))  # fin
	_add(s, _box(Vector3(1.6, 0.08, 0.5)), white, Vector3(0.0, 0.5, 6.1))                        # tailplane
	_add(s, _cyl(0.14, 0.2, 0.7), dark, Vector3(0.0, 1.45, 0.4))                                 # mast
	for side in [-1.0, 1.0]:
		_add(s, _cyl(0.06, 0.06, 3.6, 8), dark, Vector3(side * 1.05, -1.35, 0.1), rx)            # skids
		for z in [-0.7, 0.9]:
			_add(s, _box(Vector3(0.08, 0.55, 0.08)), dark, Vector3(side * 0.95, -1.05, z), Vector3(0.0, 0.0, side * deg_to_rad(12.0)))
	var main := Node3D.new()
	main.position = Vector3(0.0, 1.85, 0.4)
	s.add_child(main)
	_add(main, _cyl(0.22, 0.22, 0.18, 12), dark, Vector3.ZERO)
	_add(main, _box(Vector3(9.4, 0.04, 0.34)), dark, Vector3.ZERO)
	_add(main, _box(Vector3(0.34, 0.04, 9.4)), dark, Vector3.ZERO)
	_add(main, _cyl(4.7, 4.7, 0.01, 32), _disc_mat(), Vector3.ZERO)
	var tail := Node3D.new()
	tail.position = Vector3(0.22, 1.0, 6.75)
	s.add_child(tail)
	_add(tail, _box(Vector3(0.04, 1.5, 0.1)), dark, Vector3.ZERO)
	_add(tail, _cyl(0.75, 0.75, 0.01, 16), _disc_mat(), Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5))
	root.set_meta("rotors", [{"node": main, "axis": Vector3.UP, "rate": 26.0}, {"node": tail, "axis": Vector3.RIGHT, "rate": 55.0}])
	return root
