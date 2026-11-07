class_name MenuSettings
extends RefCounted
## All options. Every comfort and accessibility setting applies immediately.

var m
var confirm_reset := false
var _slide := {}

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
	c.button("reset", Rect2(x, y, w, 84), "TAP AGAIN TO ERASE EVERYTHING" if confirm_reset else "RESET PROGRESS", UI.RED, {"size": 23, "warning": true})
	y += 100.0
	c.scroll_max = maxf(0.0, y + c.scroll - float(m.H) + float(m.bottom))
	m.header(c, "SETTINGS", UI.CYAN)

func _title(c: UILayer, x: float, y: float, text: String) -> float:
	# A short accent bar, the section name, and a rule that fades out to the right.
	c.draw_rect(Rect2(x + 2.0, y + 14.0, 4.0, 22.0), Color(UI.CYAN, 0.9))
	UI.outlined(c, text, Vector2(x + 18.0, y + 32.0), 21, UI.CYAN, true)
	UI.rule(c, Vector2(x + 30.0 + UI.width_of(text, 21, true), y + 24.0), Vector2(x + 680.0, y + 24.0), UI.CYAN, 0.45)
	return y + 46.0

## One option row: its name, and a glass segmented control whose lit segment slides to the choice.
func _steps(c: UILayer, x: float, y: float, w: float, label: String, key: String, options: Array) -> float:
	var r := Rect2(x, y, w, 112)
	if y > -130.0 and y < float(m.H):
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(UI.CYAN, 0.22), 12, 2)
		UI.text(c, label, r.position + Vector2(20, 34), 22, UI.WHITE, true)
		var track := Rect2(x + 16.0, y + 46.0, w - 32.0, 54.0)
		c.draw_style_box(UI.box(Color(0.01, 0.02, 0.05, 0.85), Color(UI.CYAN, 0.28), 12, 1, 0), track)
		var count := options.size()
		var seg := track.size.x / float(count)
		var active := 0
		for i in range(count):
			var value: Variant = options[i][1]
			var on: bool = str(Save.opt[key]) == str(value)
			if value is float and Save.opt[key] is float:
				on = absf(float(Save.opt[key]) - float(value)) < 0.01
			if on:
				active = i
		var slide: float = float(_slide.get(key, float(active)))
		slide = move_toward(slide, float(active), c.get_process_delta_time() * 14.0) if UI.motion_ok() else float(active)
		_slide[key] = slide
		var lit := Rect2(track.position.x + 3.0 + slide * seg, track.position.y + 3.0, seg - 6.0, track.size.y - 6.0)
		UI.glass(c, lit, UI.Kind.SELECTED, UI.MINT, {"chamfer": 10})
		for i in range(count):
			var value: Variant = options[i][1]
			var id := "set_%s:%s" % [key, str(value)]
			var cell := Rect2(track.position.x + float(i) * seg, track.position.y, seg, track.size.y)
			c.hit_area(id, cell)
			var near := clampf(1.0 - absf(slide - float(i)), 0.0, 1.0)
			if i > 0 and absf(slide - float(i)) > 1.0 and absf(slide - float(i - 1)) > 1.0:
				c.draw_line(Vector2(cell.position.x, cell.position.y + 14.0), Vector2(cell.position.x, cell.end.y - 14.0), Color(UI.CYAN, 0.14), 1.0)
			var press := c.press_amount(id)
			if press > 0.0:
				c.draw_rect(cell.grow(-3.0), Color(1, 1, 1, 0.12 * press))
			UI.fit_text(c, str(options[i][0]), Vector2(cell.get_center().x - UI.width_of(str(options[i][0]), 19, true) * 0.5, cell.get_center().y + 7.0), 19, 13, seg - 12.0, UI.WHITE if near > 0.5 else UI.TEXT_DIM, true)
	return y + 120.0
