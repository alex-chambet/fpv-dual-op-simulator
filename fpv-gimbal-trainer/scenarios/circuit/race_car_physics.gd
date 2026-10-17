class_name RaceCarPhysics
extends RefCounted
## How fast a real racing car can go round a given line: a quasi-steady-state lap simulation, the
## same model lap-time simulators use.
##
## At every point of the line the car is limited by
##   - the tyres: the grip circle a_max = mu * g * (1 + downforce / weight), the downforce growing
##     with the square of the speed, so a fast corner holds far more g than a slow one;
##   - the engine: the traction it can put down (a_max * the share of the weight on the driven axle)
##     at low speed, then power / (mass * v), so the acceleration fades as the speed rises;
##   - aerodynamic drag (and rolling resistance), which also helps under braking;
##   - the slope of the track, which costs or gives acceleration.
## Cornering and accelerating / braking share the same grip (friction ellipse): what is left for the
## engine or the brakes is sqrt(a_max^2 - a_lateral^2), which is why a car cannot accelerate hard
## while still turning.
##
## A forward pass (how fast the car can get) and a backward pass (how late it can brake) are run a
## few times around the closed lap until they agree. The result is a speed for every point of the
## line: the car brakes before every corner, holds the limit through it and pulls away on the exit.

const G := 9.81

## Ready-made cars. mass kg, grip = tyre friction coefficient, power kW, drag = 0.5 * rho * Cd * A
## (kg/m), downforce = downforce / weight at `ref_speed` m/s, drive = share of the weight on the
## driven axle, rolling = rolling resistance, pace = how close to the limit the driver is.
const CARS := {
	"gt3": {
		"name": "GT3", "mass": 1300.0, "grip": 1.50, "power": 410.0, "drag": 0.766,
		"downforce": 0.35, "ref_speed": 50.0, "drive": 0.55, "rolling": 0.015, "pace": 1.0,
		"length": 4.6, "colour": Color(0.86, 0.12, 0.08), "accent": Color(0.95, 0.95, 0.95),
	},
	"gt4": {
		"name": "GT4", "mass": 1350.0, "grip": 1.38, "power": 320.0, "drag": 0.86,
		"downforce": 0.16, "ref_speed": 50.0, "drive": 0.52, "rolling": 0.015, "pace": 1.0,
		"length": 4.6, "colour": Color(0.08, 0.32, 0.78), "accent": Color(0.95, 0.78, 0.05),
	},
	"tcr": {
		"name": "Tourisme TCR", "mass": 1250.0, "grip": 1.30, "power": 260.0, "drag": 0.90,
		"downforce": 0.10, "ref_speed": 50.0, "drive": 0.45, "rolling": 0.016, "pace": 0.98,
		"length": 4.4, "colour": Color(0.95, 0.95, 0.95), "accent": Color(0.1, 0.55, 0.3),
	},
	"historique": {
		"name": "Historique", "mass": 1100.0, "grip": 1.15, "power": 220.0, "drag": 0.95,
		"downforce": 0.05, "ref_speed": 50.0, "drive": 0.52, "rolling": 0.018, "pace": 0.96,
		"length": 4.3, "colour": Color(0.92, 0.72, 0.1), "accent": Color(0.15, 0.15, 0.18),
	},
	"gt_route": {
		"name": "GT de route", "mass": 1550.0, "grip": 1.05, "power": 300.0, "drag": 1.00,
		"downforce": 0.04, "ref_speed": 50.0, "drive": 0.52, "rolling": 0.018, "pace": 0.80,
		"length": 4.5, "colour": Color(0.12, 0.12, 0.14), "accent": Color(0.7, 0.7, 0.72),
	},
	"safety": {
		"name": "Safety car", "mass": 1700.0, "grip": 1.00, "power": 240.0, "drag": 1.05,
		"downforce": 0.02, "ref_speed": 50.0, "drive": 0.5, "rolling": 0.02, "pace": 0.58,
		"length": 4.8, "colour": Color(0.93, 0.93, 0.95), "accent": Color(0.85, 0.5, 0.05),
	},
}


static func car(id: String) -> Dictionary:
	var c: Dictionary = CARS.get(id, CARS["gt4"])
	return c.duplicate()


## Signed curvature (1/m) in the xz plane at each point of a closed 3D polyline, smoothed.
static func curvature_closed(pts: PackedVector3Array, window := 2, smooth_passes := 2) -> PackedFloat32Array:
	var n := pts.size()
	var k := PackedFloat32Array()
	k.resize(n)
	for i in n:
		var a := pts[(i - window + n) % n]
		var b := pts[(i + window) % n]
		var t0 := Vector2(pts[i].x - a.x, pts[i].z - a.z)
		var t1 := Vector2(b.x - pts[i].x, b.z - pts[i].z)
		if t0.length() < 0.0001 or t1.length() < 0.0001:
			continue
		k[i] = t0.angle_to(t1) / maxf((t0.length() + t1.length()) * 0.5, 0.001)
	for _p in smooth_passes:
		var s := k.duplicate()
		for i in n:
			s[i] = (k[(i - 1 + n) % n] + 2.0 * k[i] + k[(i + 1) % n]) * 0.25
		k = s
	return k


## Speed (m/s) at every point of a closed lap line, for the given car.
static func solve_closed(pts: PackedVector3Array, c: Dictionary) -> PackedFloat32Array:
	var n := pts.size()
	var pace := clampf(float(c.get("pace", 1.0)), 0.3, 1.0)
	var mass := float(c.mass)
	var mu := float(c.grip) * pace
	var power := float(c.power) * 1000.0 * pace
	var drag := float(c.drag)
	var df_ref := float(c.downforce)
	var v_ref := float(c.get("ref_speed", 50.0))
	var drive := float(c.get("drive", 0.52))
	var rolling := float(c.get("rolling", 0.015))

	var k := curvature_closed(pts)
	var ds := PackedFloat32Array()
	var grade := PackedFloat32Array()
	var radius := PackedFloat32Array()
	ds.resize(n)
	grade.resize(n)
	radius.resize(n)
	for i in n:
		var j := (i + 1) % n
		var flat := Vector2(pts[j].x - pts[i].x, pts[j].z - pts[i].z).length()
		ds[i] = maxf(flat, 0.01)
		grade[i] = (pts[j].y - pts[i].y) / ds[i]
		radius[i] = 1.0 / maxf(absf(k[i]), 0.000001)

	# the speed a corner allows, solving v^2 = mu * g * (1 + downforce(v)) * r
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var r := radius[i]
		var denom := 1.0 - mu * G * df_ref * r / (v_ref * v_ref)
		v[i] = 200.0 if denom <= 0.02 else sqrt(mu * G * r / denom)

	for _pass in 3:
		# forward: how fast the car can get out of each point
		for i in n:
			var j := (i + 1) % n
			var vi := v[i]
			var df := df_ref * vi * vi / (v_ref * v_ref)
			var a_cap := mu * G * (1.0 + df)
			var a_lat := vi * vi / radius[i]
			var a_free := sqrt(maxf(a_cap * a_cap - a_lat * a_lat, 0.0))
			var a_engine := minf(power / (mass * maxf(vi, 3.0)), a_cap * drive)
			var a := minf(a_engine, a_free) - drag * vi * vi / mass - rolling * G - G * grade[i]
			var nv := sqrt(maxf(vi * vi + 2.0 * a * ds[i], 4.0))
			if nv < v[j]:
				v[j] = nv
		# backward: how late the car can brake into each point
		for c2 in n:
			var i := (n - 1 - c2 + n) % n
			var j := (i + 1) % n
			var vj := v[j]
			var df := df_ref * vj * vj / (v_ref * v_ref)
			var a_cap := mu * G * (1.0 + df)
			var a_lat := vj * vj / radius[j]
			var a_free := sqrt(maxf(a_cap * a_cap - a_lat * a_lat, 0.0))
			var a_brake := a_free + drag * vj * vj / mass + rolling * G + G * grade[i]
			var nv := sqrt(maxf(vj * vj + 2.0 * a_brake * ds[i], 4.0))
			if nv < v[i]:
				v[i] = nv
	return v


## Time (s) of a closed lap flown at `speeds`.
static func lap_time(pts: PackedVector3Array, speeds: PackedFloat32Array) -> float:
	var n := pts.size()
	var t := 0.0
	for i in n:
		var j := (i + 1) % n
		var d := Vector2(pts[j].x - pts[i].x, pts[j].z - pts[i].z).length()
		t += d / maxf((speeds[i] + speeds[j]) * 0.5, 1.0)
	return t


## Minimum and maximum of a speed profile, m/s.
static func speed_range(speeds: PackedFloat32Array) -> Vector2:
	var lo := INF
	var hi := 0.0
	for s in speeds:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return Vector2(lo, hi)
