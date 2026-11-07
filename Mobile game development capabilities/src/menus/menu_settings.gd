class_name MenuSettings
extends RefCounted
## All options. Every comfort and accessibility setting applies immediately.

var m
var confirm_reset := false

func _init(hub) -> void:
	m = hub

func on_ui(id: String) -> void:
	if id.begins_with("set_"):
		var parts := id.substr(4).split(":")
		_apply(parts[0], parts[1])
		return
	if id == "reset":
		if confirm_reset:
			confirm_reset = false
			_reset()
		else:
			confirm_reset = true

func _apply(key: String, value: String) -> void:
	var old: Variant = Save.opt[key]
	if old is bool:
		Save.opt[key] = value == "true"
	elif old is String:
		Save.opt[key] = value
	elif old is int:
		Save.opt[key] = int(value)
	else:
		Save.opt[key] = float(value)
	Audio.apply_volumes()
	Save.apply_display()
	Save.save_data()
	if key == "haptics":
		Save.haptic(40)

func _reset() -> void:
	var opt: Dictionary = Save.opt
	var p: String = Save.path
	for f in [p, p + ".bak"]:
		DirAccess.remove_absolute(f)
	Save.reset_progress()
	Save.reset_view()
	Save.opt = opt
	Meta.refresh_contracts()
	Save.save_data()
	Audio.play("ui_deny")

func paint(c: UILayer) -> void:
	var W: float = m.W
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var y: float = float(m.top) + 190.0 - c.scroll
	y = _title(c, x, y, "AUDIO")
	y = _steps(c, x, y, w, "Music", "music_volume", [["OFF", 0.0], ["LOW", 0.4], ["MID", 0.7], ["HIGH", 1.0]])
	y = _steps(c, x, y, w, "Sound effects", "sfx_volume", [["OFF", 0.0], ["LOW", 0.4], ["MID", 0.7], ["HIGH", 1.0]])
	y = _title(c, x, y, "CONTROLS")
	y = _steps(c, x, y, w, "Drag speed", "sensitivity", [["SLOW", 1.0], ["NORMAL", 1.3], ["FAST", 1.7]])
	y = _steps(c, x, y, w, "Nova button side", "nova_side", [["LEFT", "left"], ["RIGHT", "right"]])
	y = _steps(c, x, y, w, "Double-tap for Nova", "nova_double_tap", [["OFF", false], ["ON", true]])
	y = _steps(c, x, y, w, "Vibration", "haptics", [["OFF", 0.0], ["LOW", 0.5], ["FULL", 1.0]])
	y = _title(c, x, y, "COMFORT AND ACCESS")
	y = _steps(c, x, y, w, "Interface size", "ui_scale", [["NORMAL", 1.0], ["LARGE", 1.12]])
	y = _steps(c, x, y, w, "Screen shake", "shake", [["OFF", 0.0], ["LOW", 0.5], ["FULL", 1.0]])
	y = _steps(c, x, y, w, "Reduce flashes", "reduced_flash", [["OFF", false], ["ON", true]])
	y = _steps(c, x, y, w, "Reduce motion", "reduced_motion", [["OFF", false], ["ON", true]])
	y = _steps(c, x, y, w, "Colour-blind palette", "colorblind", [["OFF", false], ["ON", true]])
	y = _steps(c, x, y, w, "Enemy shot outlines", "bullet_outline", [["OFF", false], ["ON", true]])
	y = _steps(c, x, y, w, "Enemy shot size", "bullet_size", [["NORMAL", 1.0], ["LARGE", 1.25]])
	y = _steps(c, x, y, w, "Show your hitbox", "show_hitbox", [["OFF", false], ["ON", true]])
	y = _title(c, x, y, "PERFORMANCE")
	y = _steps(c, x, y, w, "Effects", "particles", [["LOW", 0], ["MID", 1], ["HIGH", 2]])
	y = _steps(c, x, y, w, "Frame rate (30 saves battery)", "fps", [["30", 30], ["60", 60]])
	y = _title(c, x, y, "DATA")
	y = _steps(c, x, y, w, "Save balance log on device", "telemetry", [["OFF", false], ["ON", true]])
	y += 10.0
	c.button("reset", Rect2(x, y, w, 84), "TAP AGAIN TO ERASE EVERYTHING" if confirm_reset else "RESET PROGRESS", UI.RED, {"size": 23})
	y += 100.0
	c.scroll_max = maxf(0.0, y + c.scroll - float(m.H) + float(m.bottom))
	m.header(c, "SETTINGS", UI.CYAN)

func _title(c: UILayer, x: float, y: float, text: String) -> float:
	UI.outlined(c, text, Vector2(x + 4.0, y + 32.0), 21, UI.CYAN, true)
	return y + 46.0

func _steps(c: UILayer, x: float, y: float, w: float, label: String, key: String, options: Array) -> float:
	var r := Rect2(x, y, w, 118)
	if y > -130.0 and y < float(m.H):
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(UI.CYAN, 0.22), 12, 2)
		UI.text(c, label, r.position + Vector2(20, 36), 22, UI.WHITE, true)
		var gap := 8.0
		var bw := (w - 40.0 - gap * float(options.size() - 1)) / float(options.size())
		for i in range(options.size()):
			var value: Variant = options[i][1]
			var on: bool = str(Save.opt[key]) == str(value)
			if value is float and Save.opt[key] is float:
				on = absf(float(Save.opt[key]) - float(value)) < 0.01
			c.button("set_%s:%s" % [key, str(value)], Rect2(x + 20.0 + float(i) * (bw + gap), y + 50.0, bw, 56), str(options[i][0]), UI.MINT if on else UI.CYAN, {"primary": on, "size": 19})
	return y + 128.0
