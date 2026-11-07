class_name UILayer
extends Node2D
## Screen-space UI. Buttons are declared each frame by a painter callback, while
## this node tracks their touch, hover and press animation between frames.

signal pressed(id: String)

var painter: Callable
var input_enabled := true
var _buttons: Array = []
var _press := {}
var _hover_amt := {}   # id -> 0..1, eased hover for the mouse
var _sel_amt := {}     # id -> 0..1, eased "selected" for tabs and option buttons
var _down_id := ""
var _down_finger := -1
var _hover_id := ""
var scroll := 0.0
var scroll_max := 0.0
var _touch_moved := 0.0
var _scroll_finger := -1

func reset_scroll() -> void:
	scroll = 0.0
	scroll_max = 0.0

func _process(delta: float) -> void:
	scroll = clampf(scroll, 0.0, scroll_max)
	for id in _press.keys():
		var target := 1.0 if id == _down_id else 0.0
		_press[id] = move_toward(float(_press[id]), target, delta * 11.0)
		if float(_press[id]) <= 0.0 and id != _down_id:
			_press.erase(id)
	for id in _hover_amt.keys():
		var goal := 1.0 if id == _hover_id else 0.0
		_hover_amt[id] = move_toward(float(_hover_amt[id]), goal, delta * 9.0)
		if float(_hover_amt[id]) <= 0.0 and goal == 0.0:
			_hover_amt.erase(id)
	if _hover_id != "" and not _hover_amt.has(_hover_id):
		_hover_amt[_hover_id] = 0.0
	queue_redraw()

func _draw() -> void:
	_buttons.clear()
	if painter.is_valid():
		painter.call(self)

## Options: icon, primary, disabled, instant, sub, size, sound.
func button(id: String, rect: Rect2, label: String, color: Color = UI.CYAN, opts: Dictionary = {}) -> void:
	_buttons.append({"id": id, "rect": rect, "instant": opts.get("instant", false), "disabled": opts.get("disabled", false), "sound": opts.get("sound", "ui_click")})
	var press := float(_press.get(id, 0.0))
	var disabled: bool = opts.get("disabled", false)
	var primary: bool = opts.get("primary", false)
	var hover := id == _hover_id and not disabled
	var scale_by := 1.0 - press * 0.05
	var center := rect.get_center()
	draw_set_transform(center, 0.0, Vector2(scale_by, scale_by))
	var local := Rect2(-rect.size * 0.5, rect.size)
	var tint := color if not disabled else Color(0.42, 0.46, 0.56)
	var selected: bool = bool(opts.get("selected", false)) and not disabled
	# "Selected" eases in and out, so tabs and option buttons slide between states instead of snapping.
	var sel_amt := 0.0
	if selected or _sel_amt.has(id):
		var goal := 1.0 if selected else 0.0
		sel_amt = goal if not UI.motion_ok() else move_toward(float(_sel_amt.get(id, 0.0)), goal, get_process_delta_time() * 8.0)
		if sel_amt <= 0.0 and goal == 0.0:
			_sel_amt.erase(id)
		else:
			_sel_amt[id] = sel_amt
		if _sel_amt.size() > 160:
			_sel_amt.clear()
	var hover_amt := float(_hover_amt.get(id, 0.0)) if not disabled else 0.0
	var kind: int = UI.Kind.CARD
	if disabled:
		kind = UI.Kind.DISABLED
	elif bool(opts.get("warning", false)):
		kind = UI.Kind.WARNING
	elif primary:
		kind = UI.Kind.PRIMARY
	elif selected:
		kind = UI.Kind.SELECTED
	var pulse := UI.breathe(2.6) if primary and not disabled else 1.0
	var glow_steps := 6 + int(round(pulse * 3.0)) * 2 if primary and not disabled else 0
	UI.glass(self, local, kind, tint, {"chamfer": 14, "lift": hover_amt * 0.05 + press * 0.2, "glow": glow_steps if primary else (6 if selected else 0), "pulse": pulse})
	# A slim light under the selected tab that grows out from the middle.
	if sel_amt > 0.02 and not primary:
		var span := (local.size.x - 40.0) * (0.35 + 0.45 * sel_amt)
		draw_rect(Rect2(-span * 0.5, local.end.y - 8.0, span, 2.5), Color(tint.lightened(0.3), 0.9 * sel_amt))
	var icon_tex: Texture2D = opts.get("icon")
	var fs: int = opts.get("size", 30)
	var text_color := UI.WHITE if not disabled else Color(0.6, 0.64, 0.72)
	var sub: String = opts.get("sub", "")
	var has_label := not label.is_empty()
	var art_key: String = opts.get("art", "")
	if not art_key.is_empty():
		# A destination card: illustration on the left, text beside it. The art follows the press scale.
		var asz: float = opts.get("art_size", 56.0)
		var pad := 14.0
		var live := not disabled
		var ambient := Transform2D(0.0, Vector2(scale_by, scale_by), 0.0, center)
		UIArt.draw(self, art_key, Vector2(-rect.size.x * 0.5 + pad + asz * 0.5, 0.0), asz, {"parent": ambient, "animate": live, "tint": Color.WHITE if live else Color(0.55, 0.6, 0.7, 0.5)})
		var tx := -rect.size.x * 0.5 + pad + asz + 12.0
		var ty := fs * 0.36 - (10.0 if not sub.is_empty() else 0.0)
		UI.text(self, label, Vector2(tx, ty), fs, text_color, true)
		if not sub.is_empty():
			UI.text(self, sub, Vector2(tx, ty + 28.0), 18, Color(tint, 0.95))
	elif icon_tex and not has_label:
		UI.icon(self, icon_tex, Vector2.ZERO, minf(rect.size.x, rect.size.y) * 0.78, Color.WHITE if not disabled else Color(1, 1, 1, 0.4))
	elif icon_tex:
		var isize := rect.size.y * 0.62
		var total := isize + 14.0 + UI.width_of(label, fs, true)
		var x := -total * 0.5
		UI.icon(self, icon_tex, Vector2(x + isize * 0.5, 0), isize, Color.WHITE if not disabled else Color(1, 1, 1, 0.4))
		UI.text(self, label, Vector2(x + isize + 14.0, fs * 0.36), fs, text_color, true)
	else:
		var y := fs * 0.36 - (10.0 if not sub.is_empty() else 0.0)
		if primary and not disabled:
			UI.text(self, label, Vector2(0, y + 2.0), fs, Color(0, 0, 0, 0.35), true, UI.CENTER)
		UI.text(self, label, Vector2(0, y), fs, text_color, true, UI.CENTER)
		if not sub.is_empty():
			UI.text(self, sub, Vector2(0, y + 28.0), 18, Color(tint, 0.95), false, UI.CENTER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## An invisible press target over custom-drawn content, such as a card or level node.
func hit_area(id: String, rect: Rect2, opts: Dictionary = {}) -> void:
	_buttons.append({"id": id, "rect": rect, "instant": opts.get("instant", false), "disabled": opts.get("disabled", false), "sound": opts.get("sound", "ui_click")})

## Where a button is on screen. Tests use this so they press what a player would press.
func rect_of(id: String) -> Rect2:
	for b in _buttons:
		if b.id == id:
			return b.rect
	return Rect2()

func press_amount(id: String) -> float:
	return float(_press.get(id, 0.0))

func _find(pos: Vector2) -> Dictionary:
	for i in range(_buttons.size() - 1, -1, -1):
		var b: Dictionary = _buttons[i]
		var r: Rect2 = b.rect
		if r.grow(6.0).has_point(pos):
			return b
	return {}

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		var hit := _find(event.position)
		_hover_id = hit.get("id", "")
		return
	if event is InputEventScreenDrag and scroll_max > 0.0 and event.index == _scroll_finger:
		scroll = clampf(scroll - event.relative.y, 0.0, scroll_max)
		_touch_moved += absf(event.relative.y)
		# A real scroll cancels the button that the finger started on.
		if _touch_moved > 14.0 and not _down_id.is_empty():
			_down_id = ""
			_down_finger = -1
		return
	if not event is InputEventScreenTouch:
		return
	if event.pressed:
		_scroll_finger = event.index
		_touch_moved = 0.0
		var hit := _find(event.position)
		if hit.is_empty():
			return
		get_viewport().set_input_as_handled()
		if hit.disabled:
			Audio.play("ui_deny")
			return
		_down_id = hit.id
		_down_finger = event.index
		_press[hit.id] = 0.15
		if hit.instant:
			_fire(hit)
			_down_id = ""
	elif event.index == _down_finger:
		var was := _down_id
		_down_id = ""
		_down_finger = -1
		if was.is_empty():
			return
		get_viewport().set_input_as_handled()
		var hit := _find(event.position)
		if hit.get("id", "") == was:
			_fire(hit)

func _fire(hit: Dictionary) -> void:
	var sound: String = hit.sound
	if not sound.is_empty():
		Audio.play(sound)
	Save.haptic(12)
	pressed.emit(hit.id)
