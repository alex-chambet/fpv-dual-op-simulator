extends SceneTree
## Scratch: la profondeur de champ est-elle la vraie ? Ecrit rien dans user://.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var lf = load("res://scenarios/graphics/lens_focus.gd")
	print("=== zone de nettete, f/%.1f, cercle de confusion %.3f mm ===" % [lf.F_NUMBER, lf.COC])
	print("  focale   hyperfocale      a 8 m            a 15 m           a 40 m")
	for mm in [24.0, 35.0, 50.0, 85.0]:
		var h: float = (mm * mm) / (float(lf.F_NUMBER) * float(lf.COC)) * 0.001 + mm * 0.001
		var row := "  %5.0f mm  %6.1f m   " % [mm, h]
		for s in [8.0, 15.0, 40.0]:
			var d = lf.depth_of_field(s, mm)
			row += "%5.1f-%-7s " % [d[0], "inf" if is_inf(d[1]) else "%.1f m" % d[1]]
		print(row)

	print("\n=== les proprietes existent-elles ? ===")
	var a := CameraAttributesPractical.new()
	for p in ["dof_blur_far_enabled", "dof_blur_far_distance", "dof_blur_far_transition",
			"dof_blur_near_enabled", "dof_blur_near_distance", "dof_blur_near_transition",
			"dof_blur_amount", "auto_exposure_enabled", "auto_exposure_speed", "auto_exposure_scale"]:
		var ok: bool = false
		for d in a.get_property_list():
			if d.name == p:
				ok = true
		if not ok:
			print("  MANQUE : %s" % p)
	print("  verifiees")

	print("\n=== dans une vraie session ===")
	var sm = load("res://scenarios/scenario_matrix.gd")
	var amb = load("res://scenarios/graphics/ambience.gd")
	amb.choice = "noon"
	for mm in [24, 85]:
		var r := RandomNumberGenerator.new()
		r.seed = 4242
		var cfg = sm.generate("ski_alpin", "lateral", 3, r, {}, mm, false)
		cfg.ambience = "noon"
		sm.current = cfg
		var scene = load("res://scenarios/scenario.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		scene.set_process(false)          # jamais laisser tourner : cela enregistrerait un score
		scene.flight.set_process(false)
		await process_frame
		var cam = scene.flight.rig.camera
		var at = cam.attributes
		print("\n  %d mm : fov %.1f deg, attributes %s" % [mm, cam.fov,
			"absent" if at == null else at.get_class()])
		var sub = scene.subject
		var flight = scene.flight
		scene.state = 1
		var dt := 1.0 / 60.0
		var f := 0
		while not sub.finished and f < 2400:
			f += 1
			sub.advance(dt)
			flight.external_ratio = scene._drone_ratio(dt)
			flight._process(dt)
			scene._update_framing_state()
			if f % 600 == 0:
				var d: float = cam.global_position.distance_to(sub.torso_position())
				print("    %4.1fs  sujet a %5.1f m -> net de %s a %s, flou %.2f" % [f * dt, d,
					("%.1f m" % at.dof_blur_near_distance) if at.dof_blur_near_enabled else "la camera",
					("%.0f m" % at.dof_blur_far_distance) if at.dof_blur_far_enabled else "l'infini",
					at.dof_blur_amount])
		scene.queue_free()
		await process_frame
	quit()
