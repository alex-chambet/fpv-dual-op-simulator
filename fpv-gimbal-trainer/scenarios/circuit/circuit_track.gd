class_name CircuitTrack
extends RefCounted
## The Nürburgring Grand-Prix-Strecke (5.148 km, 15 turns, layout since 2002) as data.
##
## POINTS is the centre line of the track at FULL scale, in metres, one point every STEP metres,
## point 0 on the start / finish line, increasing index = the racing direction. It was traced from
## the circuit map of the Wikipedia article (Nürburgring - Grand-Prix-Strecke.svg): the drawing was
## flattened to a polyline, scaled so that its length is the official 5.148 km, then re-driven with
## a bounded curvature so that no corner is drawn tighter than 30 m of radius (a schematic map draws
## the slow corners much sharper than they are; 30 m is close to the real radius of Turn 1).
##
## HEIGHT_S / HEIGHT_M are the elevation profile along the lap (full scale, metres above the lowest
## point of the Mercedes Arena): down from the start / finish into the Arena, back up through the
## Ford-Kurve to the high point around the Kumho-Kurve, then down the back straight to the Veedol
## chicane and up again through the Coca-Cola-Kurve.
##
## Everything here is full scale. The game plays the circuit at CircuitLayout.scale (0.5), which
## halves the lengths AND the heights, so the gradients are the real ones.

## Official length of the lap, m.
const LAP_LENGTH := 5148.0
## Spacing of POINTS, m.
const STEP := 6.0
## Width of the asphalt (the real track is 10 to 15 m wide; it is NOT scaled down with the rest, so
## that a 4.6 m car still has room for a racing line and for overtaking).
const HALF_WIDTH := 5.6
## Width of the red and white kerbs, m.
const KERB_WIDTH := 1.1

## Elevation profile: lap distance (m) and height (m), interpolated smoothly.
static var HEIGHT_S := PackedFloat32Array([0.0, 400.0, 774.0, 960.0, 1227.0, 1325.0, 1560.0, 1827.0,
		1966.0, 2300.0, 2574.0, 2966.0, 3111.0, 3350.0, 3557.0, 3747.0, 4188.0, 4621.0, 4710.0,
		4948.0, 5148.0])
static var HEIGHT_M := PackedFloat32Array([30.0, 29.0, 20.0, 11.0, 4.0, 2.0, 8.0, 13.0,
		17.0, 25.0, 23.0, 33.0, 36.0, 40.0, 42.0, 40.0, 32.0, 22.0, 21.0,
		24.0, 30.0])

## The corners, by lap distance (m, full scale): [s, number, name].
const CORNERS := [
	[774.0, "1", "Castrol-S"],
	[960.0, "2", "Mercedes-Arena"],
	[1227.0, "3", "Mercedes-Arena"],
	[1325.0, "4", "Mercedes-Arena"],
	[1827.0, "5", "Valvoline-Kurve"],
	[1966.0, "6", "Ford-Kurve"],
	[2574.0, "7", "Dunlop-Kehre"],
	[2966.0, "8", "Michael-Schumacher-S"],
	[3111.0, "9", "Michael-Schumacher-S"],
	[3557.0, "10", "Kumho-Kurve"],
	[3747.0, "11", "Bit-Kurve"],
	[4188.0, "12", "NGK-Schikane"],
	[4621.0, "13", "Veedol-Schikane"],
	[4710.0, "14", "Veedol-Schikane"],
	[4948.0, "15", "Coca-Cola-Kurve"],
]

## Landmarks of the circuit, by lap distance (m, full scale). Used by the scenery.
## [s, kind]: "pits" (the pit building and the main grandstand along the straight), "gantry"
## (the start / finish gantry), "bridge" (the Dunlop bridge over the track), "stand" (a grandstand
## on the outside of the corner), "arena" (the big banked grandstand of the Mercedes-Arena).
const LANDMARKS := [
	[0.0, "gantry"],
	[5000.0, "pits"],
	[1100.0, "arena"],
	[2574.0, "bridge"],
	[2450.0, "stand"],
	[3557.0, "stand"],
	[4650.0, "stand"],
	[4948.0, "stand"],
]


## The centre line at `scale`, resampled every `step` metres (closed loop, no duplicated last point).
static func centre_line(scale: float, step: float) -> PackedVector2Array:
	var src := PackedVector2Array()
	for p in POINTS:
		src.append(p * scale)
	return resample_closed(src, step)


## Height of the track surface at a lap distance (m), at `scale`.
static func height_at(lap_s: float, scale: float) -> float:
	var lap := LAP_LENGTH
	var s := fposmod(lap_s / scale, lap)
	var n := HEIGHT_S.size()
	for i in range(n - 1):
		if s >= HEIGHT_S[i] and s <= HEIGHT_S[i + 1]:
			var t := (s - HEIGHT_S[i]) / maxf(HEIGHT_S[i + 1] - HEIGHT_S[i], 0.001)
			return lerpf(HEIGHT_M[i], HEIGHT_M[i + 1], smoothstep(0.0, 1.0, t)) * scale
	return HEIGHT_M[0] * scale


# --- Closed-loop geometry ----------------------------------------------------------------------

## Points every `step` metres along a closed polyline.
static func resample_closed(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3 or step <= 0.0:
		return poly
	var total := 0.0
	for i in n:
		total += poly[i].distance_to(poly[(i + 1) % n])
	var count := maxi(8, roundi(total / step))
	var exact := total / count       # so the loop closes exactly
	var out := PackedVector2Array()
	var i_seg := 0
	var carry := 0.0
	var pos := poly[0]
	out.append(pos)
	for _k in count - 1:
		var left := exact
		while left > 0.0 and i_seg < n:
			var b := poly[(i_seg + 1) % n]
			var d := pos.distance_to(b)
			if d > left + 0.0001:
				pos = pos + (b - pos) / d * left
				left = 0.0
			else:
				pos = b
				left -= d
				i_seg += 1
		out.append(pos)
	return out


## Signed curvature (1/m, positive = turning left) at each point of a closed polyline, smoothed.
static func signed_curvature(poly: PackedVector2Array, smooth_passes := 2, window := 2) -> PackedFloat32Array:
	var n := poly.size()
	var k := PackedFloat32Array()
	k.resize(n)
	for i in n:
		var a := poly[(i - window + n) % n]
		var b := poly[(i + window) % n]
		var t0 := poly[i] - a
		var t1 := b - poly[i]
		var l0 := t0.length()
		var l1 := t1.length()
		if l0 < 0.0001 or l1 < 0.0001:
			k[i] = 0.0
			continue
		k[i] = t0.angle_to(t1) / maxf((l0 + l1) * 0.5, 0.001)
	for _p in smooth_passes:
		var s := k.duplicate()
		for i in n:
			s[i] = (k[(i - 1 + n) % n] + 2.0 * k[i] + k[(i + 1) % n]) * 0.25
		k = s
	return k


## Unit normal to the right of the direction of travel, at each point of a closed polyline.
static func right_normals(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	for i in n:
		var t := poly[(i + 1) % n] - poly[(i - 1 + n) % n]
		out.append(Vector2(t.y, -t.x).normalized())
	return out


# --- Racing line -------------------------------------------------------------------------------

## The line a driver takes: wide on the way in, on the inside at the apex, wide again on the way out,
## never further than `max_offset` metres from the centre line. Returns the lateral offset of the
## line at each point (positive = to the right of the direction of travel).
##
## The anchors (wide / apex / wide) are joined by smoothstep ramps, so the offset - and with it the
## curvature the line adds to the one of the track - stays smooth: between two corners the car
## crosses the track progressively, as a driver does, and in a chicane the two anchors meet in the
## middle and cancel out.
static func line_offsets(poly: PackedVector2Array, max_offset: float) -> PackedFloat32Array:
	var n := poly.size()
	var k := signed_curvature(poly)
	var total := 0.0
	for i in n:
		total += poly[i].distance_to(poly[(i + 1) % n])
	var step := total / n
	var k_thresh := 1.0 / maxf(0.043 * total, 20.0)   # a bend tighter than this counts as a corner

	# corner spans (closed loop), merged when they almost touch
	var corner := []
	var i0 := -1
	for c in n * 2:
		var i: int = c % n
		var strong: bool = absf(k[i]) > k_thresh
		if strong and i0 < 0:
			i0 = c
		elif not strong and i0 >= 0:
			if c - i0 >= maxi(3, roundi(12.0 / step)):
				corner.append([i0, c - 1])
			i0 = -1
			if c >= n:
				break
	if corner.is_empty():
		var zero := PackedFloat32Array()
		zero.resize(n)
		return zero
	# merge spans separated by less than 18 m and of the same sign
	var merged := []
	for span in corner:
		if not merged.is_empty():
			var last: Array = merged[merged.size() - 1]
			var gap: int = int(span[0]) - int(last[1])
			var same := signf(k[int(last[1]) % n]) == signf(k[int(span[0]) % n])
			if gap * step < 18.0 and same:
				last[1] = span[1]
				continue
		merged.append([span[0], span[1]])

	# anchors around the loop: wide before, inside at the apex, wide after
	var anchors := []   # [index (may exceed n), offset]
	for span in merged:
		var a: int = int(span[0])
		var b: int = int(span[1])
		var apex := a
		var best := 0.0
		var dir := 0.0
		for c in range(a, b + 1):
			var kk: float = k[c % n]
			dir += kk
			if absf(kk) > best:
				best = absf(kk)
				apex = c
		var side := signf(dir)
		if side == 0.0:
			side = 1.0
		var arc := (b - a) * step
		# How far before the corner the car is already on the outside. Crossing the track adds
		# curvature where it turns in (which opens the apex) but being on the inside also tightens
		# the line by about k^2 * offset: on a hairpin the driver must therefore turn in late and
		# quickly, on a fast sweep they can drift across over a long distance. Keeping the
		# transition shorter than about 3 radii is what makes the apex wider than the centre line.
		var r_apex := 1.0 / maxf(absf(k[apex % n]), 0.000001)
		var lead := clampf(3.0 * r_apex - arc * 0.5, 8.0, 60.0) / step
		anchors.append([a - lead, side * max_offset])
		anchors.append([apex, -side * max_offset])
		anchors.append([b + lead, side * max_offset])

	# keep the anchors in order: where an exit anchor overtakes the next entry anchor (a chicane),
	# both move to the middle and their offsets average out - the car goes straight through
	for i in range(1, anchors.size()):
		var prev: Array = anchors[i - 1]
		var cur: Array = anchors[i]
		if float(cur[0]) <= float(prev[0]) + 1.0:
			var mid: float = (float(cur[0]) + float(prev[0])) * 0.5
			var val: float = (float(cur[1]) + float(prev[1])) * 0.5
			prev[0] = mid - 0.5
			cur[0] = mid + 0.5
			prev[1] = val
			cur[1] = val

	var off := PackedFloat32Array()
	off.resize(n)
	for i in n:
		off[i] = 0.0
	for i in range(anchors.size()):
		var a: Array = anchors[i]
		var b: Array = anchors[(i + 1) % anchors.size()]
		var ia := float(a[0])
		var ib := float(b[0])
		if ib <= ia:
			ib += n
		var span := maxf(ib - ia, 0.001)
		var c := int(floor(ia))
		while c <= int(ceil(ib)):
			var t := clampf((c - ia) / span, 0.0, 1.0)
			off[(c % n + n) % n] = lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, t))
			c += 1
	for _p in 3:
		var s := off.duplicate()
		for i in n:
			s[i] = (off[(i - 1 + n) % n] + 2.0 * off[i] + off[(i + 1) % n]) * 0.25
		off = s
	for i in n:
		off[i] = clampf(off[i], -max_offset, max_offset)
	return off


## The centre line moved sideways by `off` (positive = to the right of the direction of travel).
static func offset_line(poly: PackedVector2Array, off: PackedFloat32Array) -> PackedVector2Array:
	var nrm := right_normals(poly)
	var out := PackedVector2Array()
	for i in poly.size():
		out.append(poly[i] + nrm[i] * off[i])
	return out


## Lap distance (m) of each point of a closed polyline.
static func arc_lengths(poly: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var s := 0.0
	for i in poly.size():
		out.append(s)
		s += poly[i].distance_to(poly[(i + 1) % poly.size()])
	return out


## Centre line of the circuit, full scale, metres. Point 0 is on the start / finish line.
## (a static var, not a const: a packed array literal is not a constant expression in GDScript)
static var POINTS := PackedVector2Array([
	Vector2(556.1, -437.8), Vector2(551.2, -434.3), Vector2(546.3, -430.8), Vector2(541.5, -427.3), Vector2(536.6, -423.8), Vector2(531.7, -420.3), 
	Vector2(526.8, -416.8), Vector2(521.9, -413.4), Vector2(517.1, -409.9), Vector2(512.2, -406.4), Vector2(507.3, -402.9), Vector2(502.4, -399.4), 
	Vector2(497.5, -395.9), Vector2(492.7, -392.4), Vector2(487.8, -388.9), Vector2(482.9, -385.4), Vector2(478.0, -381.9), Vector2(473.1, -378.5), 
	Vector2(468.2, -375.0), Vector2(463.4, -371.5), Vector2(458.5, -368.0), Vector2(453.6, -364.5), Vector2(448.7, -361.0), Vector2(443.8, -357.6), 
	Vector2(438.8, -354.2), Vector2(433.9, -350.9), Vector2(428.9, -347.5), Vector2(423.9, -344.2), Vector2(418.9, -340.8), Vector2(414.0, -337.4), 
	Vector2(409.0, -334.1), Vector2(404.0, -330.7), Vector2(399.1, -327.3), Vector2(394.1, -324.0), Vector2(389.1, -320.6), Vector2(384.1, -317.3), 
	Vector2(379.2, -313.9), Vector2(374.2, -310.5), Vector2(369.2, -307.2), Vector2(364.3, -303.8), Vector2(359.3, -300.5), Vector2(354.3, -297.1), 
	Vector2(349.4, -293.7), Vector2(344.4, -290.4), Vector2(339.4, -287.0), Vector2(334.4, -283.7), Vector2(329.5, -280.3), Vector2(324.5, -276.9), 
	Vector2(319.5, -273.6), Vector2(314.6, -270.2), Vector2(309.6, -266.9), Vector2(304.6, -263.5), Vector2(299.6, -260.1), Vector2(294.7, -256.8), 
	Vector2(289.7, -253.4), Vector2(284.7, -250.1), Vector2(279.8, -246.7), Vector2(274.8, -243.3), Vector2(269.8, -240.0), Vector2(264.9, -236.6), 
	Vector2(259.9, -233.3), Vector2(254.9, -229.9), Vector2(249.9, -226.5), Vector2(245.0, -223.2), Vector2(240.0, -219.8), Vector2(235.0, -216.5), 
	Vector2(230.1, -213.1), Vector2(225.1, -209.7), Vector2(220.1, -206.4), Vector2(215.1, -203.0), Vector2(210.2, -199.7), Vector2(205.2, -196.3), 
	Vector2(200.2, -192.9), Vector2(195.3, -189.6), Vector2(190.3, -186.2), Vector2(185.3, -182.9), Vector2(180.3, -179.5), Vector2(175.4, -176.1), 
	Vector2(170.4, -172.8), Vector2(165.4, -169.4), Vector2(160.5, -166.0), Vector2(155.5, -162.7), Vector2(150.7, -159.1), Vector2(145.9, -155.5), 
	Vector2(141.3, -151.6), Vector2(136.8, -147.6), Vector2(132.4, -143.6), Vector2(128.1, -139.4), Vector2(123.9, -135.1), Vector2(119.6, -130.9), 
	Vector2(115.4, -126.6), Vector2(111.2, -122.3), Vector2(107.0, -118.1), Vector2(102.8, -113.8), Vector2(98.6, -109.5), Vector2(94.4, -105.3), 
	Vector2(90.1, -101.0), Vector2(85.9, -96.7), Vector2(81.7, -92.4), Vector2(77.5, -88.2), Vector2(73.3, -83.9), Vector2(69.1, -79.6), 
	Vector2(64.9, -75.3), Vector2(60.7, -71.0), Vector2(56.5, -66.8), Vector2(52.3, -62.4), Vector2(48.1, -58.1), Vector2(44.0, -53.8), 
	Vector2(39.8, -49.5), Vector2(35.7, -45.1), Vector2(31.8, -40.5), Vector2(28.6, -35.5), Vector2(26.3, -30.0), Vector2(25.2, -24.1), 
	Vector2(25.4, -18.1), Vector2(26.7, -12.3), Vector2(29.1, -6.8), Vector2(32.7, -1.9), Vector2(37.1, 2.1), Vector2(42.2, 5.2), 
	Vector2(47.9, 7.2), Vector2(53.8, 8.0), Vector2(59.8, 7.5), Vector2(65.5, 6.0), Vector2(70.9, 3.2), Vector2(75.6, -0.5), 
	Vector2(79.7, -4.9), Vector2(83.4, -9.5), Vector2(87.3, -14.1), Vector2(91.5, -18.4), Vector2(96.1, -22.2), Vector2(101.2, -25.4), 
	Vector2(106.5, -28.1), Vector2(112.1, -30.5), Vector2(117.7, -32.6), Vector2(123.3, -34.7), Vector2(129.0, -36.7), Vector2(134.6, -38.6), 
	Vector2(140.3, -40.6), Vector2(146.0, -42.5), Vector2(151.7, -44.3), Vector2(157.4, -46.1), Vector2(163.2, -47.7), Vector2(169.1, -48.9), 
	Vector2(175.0, -49.8), Vector2(181.0, -50.2), Vector2(187.0, -50.1), Vector2(193.0, -49.4), Vector2(198.8, -48.1), Vector2(204.5, -46.3), 
	Vector2(210.0, -43.9), Vector2(215.2, -40.8), Vector2(219.9, -37.2), Vector2(224.2, -33.0), Vector2(228.0, -28.3), Vector2(231.2, -23.2), 
	Vector2(233.8, -17.9), Vector2(235.9, -12.2), Vector2(237.3, -6.4), Vector2(238.0, -0.4), Vector2(238.3, 5.5), Vector2(238.1, 11.5), 
	Vector2(237.5, 17.5), Vector2(236.5, 23.4), Vector2(235.2, 29.3), Vector2(233.7, 35.1), Vector2(232.0, 40.9), Vector2(230.1, 46.5), 
	Vector2(228.1, 52.2), Vector2(225.8, 57.8), Vector2(223.5, 63.3), Vector2(221.1, 68.8), Vector2(218.7, 74.3), Vector2(216.1, 79.7), 
	Vector2(213.6, 85.1), Vector2(211.0, 90.5), Vector2(208.3, 95.9), Vector2(205.6, 101.3), Vector2(202.9, 106.6), Vector2(200.1, 112.0), 
	Vector2(197.4, 117.3), Vector2(194.5, 122.5), Vector2(191.4, 127.7), Vector2(187.9, 132.6), Vector2(183.9, 137.0), Vector2(179.4, 140.9), 
	Vector2(174.3, 144.2), Vector2(168.9, 146.7), Vector2(163.2, 148.6), Vector2(157.3, 149.8), Vector2(151.4, 150.3), Vector2(145.4, 150.1), 
	Vector2(139.5, 149.2), Vector2(133.7, 147.4), Vector2(128.4, 144.7), Vector2(123.7, 140.9), Vector2(119.9, 136.4), Vector2(117.0, 131.1), 
	Vector2(115.2, 125.4), Vector2(114.3, 119.5), Vector2(114.1, 113.5), Vector2(114.4, 107.5), Vector2(114.9, 101.5), Vector2(115.6, 95.6), 
	Vector2(116.4, 89.6), Vector2(117.2, 83.7), Vector2(117.7, 77.7), Vector2(117.6, 71.7), Vector2(116.6, 65.8), Vector2(114.4, 60.3), 
	Vector2(111.1, 55.3), Vector2(106.8, 51.0), Vector2(101.8, 47.7), Vector2(96.3, 45.5), Vector2(90.4, 44.4), Vector2(84.4, 44.6), 
	Vector2(78.5, 45.8), Vector2(72.8, 47.6), Vector2(67.1, 49.4), Vector2(61.3, 50.9), Vector2(55.3, 51.8), Vector2(49.4, 52.3), 
	Vector2(43.4, 52.5), Vector2(37.4, 52.6), Vector2(31.4, 52.7), Vector2(25.4, 52.7), Vector2(19.4, 52.8), Vector2(13.4, 52.9), 
	Vector2(7.4, 53.0), Vector2(1.4, 53.1), Vector2(-4.6, 53.2), Vector2(-10.6, 53.4), Vector2(-16.6, 53.5), Vector2(-22.6, 53.6), 
	Vector2(-28.6, 53.8), Vector2(-34.6, 53.9), Vector2(-40.6, 54.1), Vector2(-46.6, 54.2), Vector2(-52.6, 54.3), Vector2(-58.6, 54.5), 
	Vector2(-64.6, 54.6), Vector2(-70.6, 54.8), Vector2(-76.6, 54.9), Vector2(-82.6, 55.0), Vector2(-88.6, 55.2), Vector2(-94.6, 55.3), 
	Vector2(-100.6, 55.4), Vector2(-106.6, 55.5), Vector2(-112.6, 55.7), Vector2(-118.6, 56.0), Vector2(-124.6, 56.3), Vector2(-130.5, 56.9), 
	Vector2(-136.5, 57.6), Vector2(-142.4, 58.5), Vector2(-148.4, 59.4), Vector2(-154.3, 60.5), Vector2(-160.2, 61.5), Vector2(-166.1, 62.6), 
	Vector2(-172.0, 63.6), Vector2(-177.9, 64.7), Vector2(-183.8, 65.7), Vector2(-189.7, 66.7), Vector2(-195.6, 67.7), Vector2(-201.6, 68.8), 
	Vector2(-207.5, 69.8), Vector2(-213.4, 70.8), Vector2(-219.3, 71.8), Vector2(-225.2, 72.8), Vector2(-231.1, 73.8), Vector2(-237.0, 74.8), 
	Vector2(-242.9, 75.9), Vector2(-248.9, 76.9), Vector2(-254.8, 77.9), Vector2(-260.7, 78.9), Vector2(-266.6, 79.9), Vector2(-272.5, 80.9), 
	Vector2(-278.4, 82.0), Vector2(-284.3, 83.0), Vector2(-290.3, 84.0), Vector2(-296.2, 85.0), Vector2(-302.1, 86.0), Vector2(-308.0, 87.0), 
	Vector2(-313.9, 88.1), Vector2(-319.8, 89.1), Vector2(-325.7, 90.1), Vector2(-331.7, 91.0), Vector2(-337.6, 91.8), Vector2(-343.6, 92.1), 
	Vector2(-349.6, 92.2), Vector2(-355.6, 91.9), Vector2(-361.6, 91.3), Vector2(-367.5, 90.2), Vector2(-373.2, 88.6), Vector2(-378.8, 86.4), 
	Vector2(-384.2, 83.6), Vector2(-389.2, 80.4), Vector2(-393.8, 76.5), Vector2(-397.8, 72.1), Vector2(-401.4, 67.3), Vector2(-404.5, 62.2), 
	Vector2(-407.2, 56.8), Vector2(-409.6, 51.3), Vector2(-411.8, 45.7), Vector2(-413.9, 40.1), Vector2(-415.9, 34.4), Vector2(-418.0, 28.8), 
	Vector2(-420.1, 23.2), Vector2(-422.2, 17.6), Vector2(-424.3, 11.9), Vector2(-426.4, 6.3), Vector2(-428.5, 0.7), Vector2(-430.7, -4.9), 
	Vector2(-432.8, -10.5), Vector2(-435.0, -16.1), Vector2(-437.3, -21.6), Vector2(-439.7, -27.1), Vector2(-442.6, -32.4), Vector2(-445.9, -37.4), 
	Vector2(-450.0, -41.8), Vector2(-454.7, -45.5), Vector2(-460.0, -48.3), Vector2(-465.6, -50.3), Vector2(-471.5, -51.3), Vector2(-477.5, -51.5), 
	Vector2(-483.4, -50.6), Vector2(-489.2, -48.9), Vector2(-494.6, -46.3), Vector2(-499.6, -43.0), Vector2(-504.2, -39.2), Vector2(-508.5, -35.0), 
	Vector2(-512.5, -30.6), Vector2(-516.3, -25.9), Vector2(-520.0, -21.2), Vector2(-523.6, -16.4), Vector2(-527.2, -11.6), Vector2(-530.8, -6.8), 
	Vector2(-534.4, -2.0), Vector2(-538.0, 2.8), Vector2(-541.7, 7.5), Vector2(-545.3, 12.3), Vector2(-549.0, 17.1), Vector2(-552.6, 21.8), 
	Vector2(-556.3, 26.6), Vector2(-560.0, 31.3), Vector2(-563.6, 36.1), Vector2(-567.3, 40.9), Vector2(-570.9, 45.6), Vector2(-574.6, 50.4), 
	Vector2(-578.3, 55.0), Vector2(-582.2, 59.6), Vector2(-586.2, 64.1), Vector2(-590.3, 68.5), Vector2(-594.4, 72.8), Vector2(-598.6, 77.1), 
	Vector2(-602.9, 81.4), Vector2(-607.1, 85.6), Vector2(-611.4, 89.9), Vector2(-615.6, 94.1), Vector2(-619.9, 98.3), Vector2(-624.2, 102.5), 
	Vector2(-628.5, 106.6), Vector2(-632.9, 110.7), Vector2(-637.3, 114.8), Vector2(-641.7, 118.9), Vector2(-646.2, 122.9), Vector2(-650.7, 126.9), 
	Vector2(-655.2, 130.8), Vector2(-659.7, 134.7), Vector2(-664.3, 138.6), Vector2(-668.9, 142.4), Vector2(-673.6, 146.2), Vector2(-678.3, 150.0), 
	Vector2(-683.0, 153.6), Vector2(-687.8, 157.3), Vector2(-692.6, 160.8), Vector2(-697.5, 164.3), Vector2(-702.5, 167.7), Vector2(-707.5, 171.0), 
	Vector2(-712.5, 174.3), Vector2(-717.5, 177.5), Vector2(-722.6, 180.7), Vector2(-727.8, 183.8), Vector2(-732.9, 186.9), Vector2(-738.1, 189.9), 
	Vector2(-743.3, 192.9), Vector2(-748.5, 195.9), Vector2(-753.7, 198.8), Vector2(-759.0, 201.7), Vector2(-764.3, 204.6), Vector2(-769.6, 207.4), 
	Vector2(-774.9, 210.1), Vector2(-780.3, 212.8), Vector2(-785.7, 215.4), Vector2(-791.1, 218.0), Vector2(-796.5, 220.6), Vector2(-802.0, 223.1), 
	Vector2(-807.4, 225.6), Vector2(-812.9, 228.0), Vector2(-818.4, 230.4), Vector2(-823.9, 232.8), Vector2(-829.4, 235.1), Vector2(-835.0, 237.4), 
	Vector2(-840.5, 239.7), Vector2(-846.1, 241.8), Vector2(-851.8, 243.9), Vector2(-857.4, 246.0), Vector2(-863.0, 248.0), Vector2(-868.7, 250.1), 
	Vector2(-874.3, 252.1), Vector2(-879.9, 254.2), Vector2(-885.5, 256.5), Vector2(-891.0, 258.9), Vector2(-896.3, 261.6), Vector2(-901.5, 264.7), 
	Vector2(-906.4, 268.2), Vector2(-910.8, 272.2), Vector2(-914.7, 276.8), Vector2(-917.7, 281.9), Vector2(-919.9, 287.5), Vector2(-921.1, 293.4), 
	Vector2(-921.1, 299.4), Vector2(-920.0, 305.3), Vector2(-917.9, 310.9), Vector2(-914.9, 316.1), Vector2(-911.1, 320.7), Vector2(-906.5, 324.6), 
	Vector2(-901.4, 327.8), Vector2(-896.0, 330.3), Vector2(-890.3, 332.2), Vector2(-884.4, 333.2), Vector2(-878.4, 333.5), Vector2(-872.4, 333.1), 
	Vector2(-866.5, 331.9), Vector2(-860.8, 330.2), Vector2(-855.3, 327.9), Vector2(-850.0, 325.1), Vector2(-844.9, 321.8), Vector2(-840.1, 318.3), 
	Vector2(-835.4, 314.5), Vector2(-830.9, 310.6), Vector2(-826.4, 306.7), Vector2(-821.8, 302.7), Vector2(-817.2, 298.9), Vector2(-812.6, 295.1), 
	Vector2(-807.8, 291.5), Vector2(-803.0, 287.9), Vector2(-798.1, 284.4), Vector2(-793.2, 281.0), Vector2(-788.3, 277.5), Vector2(-783.3, 274.1), 
	Vector2(-778.4, 270.7), Vector2(-773.4, 267.3), Vector2(-768.5, 263.9), Vector2(-763.6, 260.5), Vector2(-758.6, 257.1), Vector2(-753.7, 253.7), 
	Vector2(-748.7, 250.3), Vector2(-743.8, 246.9), Vector2(-738.9, 243.5), Vector2(-733.9, 240.1), Vector2(-729.0, 236.7), Vector2(-724.0, 233.3), 
	Vector2(-719.1, 229.9), Vector2(-714.1, 226.5), Vector2(-709.2, 223.1), Vector2(-704.2, 219.7), Vector2(-699.3, 216.3), Vector2(-694.3, 212.9), 
	Vector2(-689.4, 209.5), Vector2(-684.4, 206.1), Vector2(-679.5, 202.7), Vector2(-674.5, 199.3), Vector2(-669.6, 195.9), Vector2(-664.6, 192.6), 
	Vector2(-659.7, 189.2), Vector2(-654.7, 185.8), Vector2(-649.8, 182.4), Vector2(-644.8, 179.0), Vector2(-639.9, 175.6), Vector2(-634.9, 172.2), 
	Vector2(-629.9, 168.9), Vector2(-624.9, 165.7), Vector2(-619.8, 162.5), Vector2(-614.5, 159.6), Vector2(-609.1, 157.0), Vector2(-603.6, 154.8), 
	Vector2(-597.8, 153.0), Vector2(-592.0, 151.8), Vector2(-586.0, 151.0), Vector2(-580.0, 150.5), Vector2(-574.0, 150.4), Vector2(-568.0, 150.6), 
	Vector2(-562.1, 151.2), Vector2(-556.1, 152.2), Vector2(-550.3, 153.4), Vector2(-544.5, 155.0), Vector2(-538.8, 156.9), Vector2(-533.2, 158.9), 
	Vector2(-527.6, 161.1), Vector2(-522.0, 163.3), Vector2(-516.4, 165.5), Vector2(-510.8, 167.7), Vector2(-505.2, 169.9), Vector2(-499.6, 172.1), 
	Vector2(-494.1, 174.3), Vector2(-488.4, 176.4), Vector2(-482.8, 178.5), Vector2(-477.1, 180.3), Vector2(-471.3, 182.0), Vector2(-465.5, 183.3), 
	Vector2(-459.5, 184.1), Vector2(-453.6, 184.6), Vector2(-447.6, 184.7), Vector2(-441.6, 184.5), Vector2(-435.6, 184.1), Vector2(-429.6, 183.5), 
	Vector2(-423.6, 182.8), Vector2(-417.7, 182.0), Vector2(-411.8, 181.1), Vector2(-405.8, 180.2), Vector2(-399.9, 179.1), Vector2(-394.0, 178.1), 
	Vector2(-388.1, 177.1), Vector2(-382.2, 176.0), Vector2(-376.3, 175.0), Vector2(-370.4, 173.9), Vector2(-364.5, 172.9), Vector2(-358.6, 171.9), 
	Vector2(-352.7, 170.9), Vector2(-346.7, 169.8), Vector2(-340.8, 168.8), Vector2(-334.9, 167.8), Vector2(-329.0, 166.8), Vector2(-323.1, 165.8), 
	Vector2(-317.2, 164.7), Vector2(-311.3, 163.7), Vector2(-305.4, 162.7), Vector2(-299.4, 161.7), Vector2(-293.5, 160.6), Vector2(-287.6, 159.6), 
	Vector2(-281.7, 158.6), Vector2(-275.8, 157.6), Vector2(-269.9, 156.5), Vector2(-264.0, 155.5), Vector2(-258.1, 154.5), Vector2(-252.1, 153.5), 
	Vector2(-246.2, 152.5), Vector2(-240.3, 151.4), Vector2(-234.4, 150.4), Vector2(-228.5, 149.4), Vector2(-222.6, 148.4), Vector2(-216.7, 147.3), 
	Vector2(-210.8, 146.3), Vector2(-204.8, 145.3), Vector2(-198.9, 144.3), Vector2(-193.0, 143.2), Vector2(-187.1, 142.2), Vector2(-181.2, 141.2), 
	Vector2(-175.3, 140.2), Vector2(-169.4, 139.2), Vector2(-163.5, 138.1), Vector2(-157.6, 137.1), Vector2(-151.6, 136.1), Vector2(-145.7, 135.1), 
	Vector2(-139.8, 134.0), Vector2(-133.9, 133.0), Vector2(-128.0, 132.0), Vector2(-122.1, 131.0), Vector2(-116.2, 129.9), Vector2(-110.3, 128.9), 
	Vector2(-104.3, 127.9), Vector2(-98.4, 126.9), Vector2(-92.5, 125.8), Vector2(-86.6, 124.8), Vector2(-80.7, 123.8), Vector2(-74.8, 122.8), 
	Vector2(-68.9, 121.8), Vector2(-63.0, 120.8), Vector2(-57.0, 119.8), Vector2(-51.1, 119.0), Vector2(-45.1, 118.5), Vector2(-39.1, 118.5), 
	Vector2(-33.2, 119.3), Vector2(-27.4, 120.9), Vector2(-22.0, 123.5), Vector2(-17.2, 127.0), Vector2(-12.9, 131.3), Vector2(-9.4, 136.1), 
	Vector2(-6.5, 141.4), Vector2(-4.1, 146.9), Vector2(-2.1, 152.5), Vector2(-0.2, 158.2), Vector2(1.6, 163.9), Vector2(3.4, 169.7), 
	Vector2(5.2, 175.4), Vector2(7.0, 181.1), Vector2(8.9, 186.8), Vector2(10.9, 192.5), Vector2(12.8, 198.2), Vector2(14.7, 203.8), 
	Vector2(16.6, 209.5), Vector2(18.6, 215.2), Vector2(20.5, 220.9), Vector2(22.4, 226.5), Vector2(24.4, 232.2), Vector2(26.3, 237.9), 
	Vector2(28.2, 243.6), Vector2(30.2, 249.3), Vector2(32.2, 254.9), Vector2(34.5, 260.5), Vector2(37.1, 265.9), Vector2(40.0, 271.1), 
	Vector2(43.4, 276.1), Vector2(47.2, 280.7), Vector2(51.5, 284.9), Vector2(56.2, 288.6), Vector2(61.3, 291.7), Vector2(66.8, 294.2), 
	Vector2(72.5, 296.1), Vector2(78.3, 297.5), Vector2(84.2, 298.4), Vector2(90.2, 298.5), Vector2(96.2, 298.0), Vector2(102.1, 297.0), 
	Vector2(107.9, 295.4), Vector2(113.5, 293.3), Vector2(118.9, 290.7), Vector2(124.1, 287.7), Vector2(129.3, 284.7), Vector2(134.4, 281.5), 
	Vector2(139.5, 278.3), Vector2(144.6, 275.1), Vector2(149.7, 272.0), Vector2(154.8, 268.9), Vector2(159.9, 265.8), Vector2(165.1, 262.7), 
	Vector2(170.2, 259.6), Vector2(175.3, 256.5), Vector2(180.5, 253.4), Vector2(185.6, 250.3), Vector2(190.8, 247.2), Vector2(195.9, 244.1), 
	Vector2(201.1, 241.0), Vector2(206.2, 237.9), Vector2(211.3, 234.8), Vector2(216.5, 231.7), Vector2(221.6, 228.6), Vector2(226.8, 225.6), 
	Vector2(231.9, 222.5), Vector2(237.0, 219.4), Vector2(242.2, 216.3), Vector2(247.3, 213.2), Vector2(252.5, 210.1), Vector2(257.6, 207.0), 
	Vector2(262.8, 203.9), Vector2(267.9, 200.8), Vector2(273.0, 197.7), Vector2(278.2, 194.6), Vector2(283.3, 191.5), Vector2(288.5, 188.4), 
	Vector2(293.6, 185.3), Vector2(298.7, 182.2), Vector2(303.9, 179.2), Vector2(309.0, 176.1), Vector2(314.2, 173.0), Vector2(319.3, 169.9), 
	Vector2(324.4, 166.8), Vector2(329.6, 163.7), Vector2(334.7, 160.6), Vector2(339.9, 157.5), Vector2(345.0, 154.4), Vector2(350.2, 151.3), 
	Vector2(355.3, 148.2), Vector2(360.4, 145.1), Vector2(365.6, 142.0), Vector2(370.7, 138.9), Vector2(375.9, 135.8), Vector2(381.0, 132.8), 
	Vector2(386.1, 129.7), Vector2(391.3, 126.6), Vector2(396.4, 123.5), Vector2(401.6, 120.4), Vector2(406.7, 117.3), Vector2(411.8, 114.2), 
	Vector2(416.9, 111.0), Vector2(421.9, 107.6), Vector2(426.6, 103.9), Vector2(431.2, 100.1), Vector2(435.7, 96.0), Vector2(439.9, 91.8), 
	Vector2(443.8, 87.3), Vector2(447.6, 82.6), Vector2(451.2, 77.8), Vector2(454.6, 72.8), Vector2(457.7, 67.7), Vector2(460.6, 62.5), 
	Vector2(463.3, 57.1), Vector2(465.9, 51.7), Vector2(468.4, 46.3), Vector2(470.9, 40.8), Vector2(473.4, 35.3), Vector2(475.8, 29.9), 
	Vector2(478.3, 24.4), Vector2(480.8, 18.9), Vector2(483.3, 13.5), Vector2(485.8, 8.0), Vector2(488.3, 2.6), Vector2(490.8, -2.9), 
	Vector2(493.3, -8.3), Vector2(495.9, -13.8), Vector2(498.4, -19.2), Vector2(500.9, -24.7), Vector2(503.4, -30.1), Vector2(505.9, -35.6), 
	Vector2(508.4, -41.0), Vector2(510.9, -46.5), Vector2(513.4, -51.9), Vector2(515.9, -57.4), Vector2(518.4, -62.8), Vector2(521.0, -68.3), 
	Vector2(523.5, -73.7), Vector2(526.0, -79.2), Vector2(528.5, -84.6), Vector2(531.0, -90.1), Vector2(533.5, -95.5), Vector2(536.0, -101.0), 
	Vector2(538.5, -106.4), Vector2(541.0, -111.9), Vector2(543.5, -117.3), Vector2(546.1, -122.8), Vector2(548.6, -128.2), Vector2(551.1, -133.7), 
	Vector2(553.6, -139.1), Vector2(556.1, -144.6), Vector2(558.6, -150.0), Vector2(561.1, -155.5), Vector2(563.6, -160.9), Vector2(566.1, -166.4), 
	Vector2(568.6, -171.8), Vector2(571.2, -177.3), Vector2(573.7, -182.7), Vector2(576.2, -188.2), Vector2(578.7, -193.6), Vector2(581.2, -199.1), 
	Vector2(583.7, -204.5), Vector2(586.2, -210.0), Vector2(588.7, -215.4), Vector2(591.2, -220.9), Vector2(593.7, -226.3), Vector2(596.3, -231.8), 
	Vector2(598.8, -237.2), Vector2(601.3, -242.7), Vector2(603.8, -248.1), Vector2(606.3, -253.6), Vector2(608.8, -259.0), Vector2(611.3, -264.5), 
	Vector2(613.8, -269.9), Vector2(616.4, -275.3), Vector2(619.1, -280.7), Vector2(622.5, -285.6), Vector2(626.7, -289.9), Vector2(631.6, -293.3), 
	Vector2(637.1, -295.6), Vector2(643.0, -296.7), Vector2(649.0, -296.6), Vector2(654.9, -295.4), Vector2(660.4, -293.1), Vector2(665.7, -290.2), 
	Vector2(670.9, -287.3), Vector2(676.4, -284.8), Vector2(682.2, -283.2), Vector2(688.1, -282.8), Vector2(694.1, -283.6), Vector2(699.7, -285.5), 
	Vector2(704.9, -288.6), Vector2(709.3, -292.6), Vector2(712.8, -297.5), Vector2(715.3, -302.9), Vector2(716.7, -308.8), Vector2(716.8, -314.8), 
	Vector2(716.1, -320.7), Vector2(714.8, -326.6), Vector2(713.6, -332.4), Vector2(712.8, -338.4), Vector2(712.8, -344.4), Vector2(713.7, -350.3), 
	Vector2(715.4, -356.0), Vector2(717.6, -361.6), Vector2(720.2, -367.0), Vector2(723.0, -372.3), Vector2(725.8, -377.6), Vector2(728.6, -382.9), 
	Vector2(731.3, -388.3), Vector2(733.9, -393.7), Vector2(736.4, -399.2), Vector2(738.7, -404.7), Vector2(741.0, -410.2), Vector2(743.3, -415.8), 
	Vector2(745.5, -421.4), Vector2(747.8, -426.9), Vector2(750.0, -432.5), Vector2(752.3, -438.0), Vector2(754.5, -443.6), Vector2(756.8, -449.2), 
	Vector2(759.0, -454.7), Vector2(761.3, -460.3), Vector2(763.6, -465.8), Vector2(765.8, -471.4), Vector2(768.0, -477.0), Vector2(770.0, -482.6), 
	Vector2(771.7, -488.4), Vector2(772.9, -494.3), Vector2(773.5, -500.2), Vector2(773.4, -506.2), Vector2(772.5, -512.2), Vector2(770.6, -517.9), 
	Vector2(767.9, -523.2), Vector2(764.4, -528.0), Vector2(760.1, -532.3), Vector2(755.3, -535.9), Vector2(750.1, -538.8), Vector2(744.6, -541.2), 
	Vector2(738.8, -542.9), Vector2(732.9, -544.0), Vector2(727.0, -544.5), Vector2(721.0, -544.5), Vector2(715.0, -543.9), Vector2(709.1, -542.7), 
	Vector2(703.4, -540.9), Vector2(697.9, -538.5), Vector2(692.7, -535.6), Vector2(687.6, -532.4), Vector2(682.7, -528.9), Vector2(677.9, -525.4), 
	Vector2(673.0, -521.8), Vector2(668.2, -518.2), Vector2(663.4, -514.7), Vector2(658.6, -511.1), Vector2(653.7, -507.6), Vector2(648.8, -504.1), 
	Vector2(644.0, -500.6), Vector2(639.1, -497.1), Vector2(634.2, -493.6), Vector2(629.3, -490.1), Vector2(624.4, -486.6), Vector2(619.5, -483.2), 
	Vector2(614.7, -479.7), Vector2(609.8, -476.2), Vector2(604.9, -472.7), Vector2(600.0, -469.2), Vector2(595.1, -465.7), Vector2(590.3, -462.2), 
	Vector2(585.4, -458.7), Vector2(580.5, -455.2), Vector2(575.6, -451.7), Vector2(570.7, -448.3), Vector2(565.9, -444.8), Vector2(561.0, -441.3)])
