class_name SoundPanel
extends SettingsRows
## The volumes (SoundSettings), shared by Paramètres and the pause menu (Échap > Son). Each change
## goes straight onto its audio bus, so it can be set by ear while a session is running.


func _init() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size.x = 600

	_heading("Son")
	_slider("Volume général", 0.0, 1.0, 0.05, SoundSettings.master, _pct, func(v):
		SoundSettings.master = v
		_changed())
	_slider("Sujet (moteur, carres)", 0.0, 1.0, 0.05, SoundSettings.subject, _pct, func(v):
		SoundSettings.subject = v
		_changed())
	_slider("Drone (hélices, vent)", 0.0, 1.0, 0.05, SoundSettings.drone, _pct, func(v):
		SoundSettings.drone = v
		_changed())
	_note("Le son du sujet vient d'où le sujet est : il change de côté quand le drone tourne autour, "
			+ "et sa hauteur tombe au moment où il passe (effet Doppler) — c'est le signal pour lancer "
			+ "le panoramique. Le drone, lui, est sous toi : ses hélices montent quand il accélère ou "
			+ "monte, et le vent suit sa vitesse.")


func _pct(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func _changed() -> void:
	SoundSettings.apply()
	SoundSettings.save()
