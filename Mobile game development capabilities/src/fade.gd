extends CanvasLayer
## Smooth screen transitions. Autoloaded as "Fade".

var _rect: ColorRect
var _busy := false
var _toasts: Array = []
var _toast_layer: DrawLayer

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.008, 0.006, 0.02, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_toast_layer = DrawLayer.new()
	_toast_layer.painter = _paint_toasts
	add_child(_toast_layer)
	Meta.unlocked_goal.connect(toast)

func toast(title: String, detail: String) -> void:
	_toasts.append({"title": title, "detail": detail, "t": 2.8})

func _process(delta: float) -> void:
	if _toasts.is_empty():
		return
	_toasts[0].t -= delta
	if float(_toasts[0].t) <= 0.0:
		_toasts.remove_at(0)
	_toast_layer.queue_redraw()

func _paint_toasts(c: DrawLayer) -> void:
	if _toasts.is_empty():
		return
	var e: Dictionary = _toasts[0]
	var v := c.get_viewport_rect().size
	var a := clampf(float(e.t) * 3.0, 0.0, 1.0) * clampf((2.8 - float(e.t)) * 6.0, 0.0, 1.0)
	var w := minf(v.x - 48.0, 620.0)
	var r := Rect2((v.x - w) * 0.5, v.y * 0.2 - (1.0 - a) * 40.0, w, 84)
	UI.panel(c, r, Color(0.09, 0.07, 0.02, 0.96 * a), Color(UI.GOLD, a), 14, 3, 12)
	UI.text(c, str(e.title), r.position + Vector2(w * 0.5, 34), 25, Color(UI.GOLD, a), true, UI.CENTER)
	UI.text(c, str(e.detail), r.position + Vector2(w * 0.5, 64), 21, Color(UI.WHITE, a), false, UI.CENTER)

func go(scene: String) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var out := create_tween()
	out.tween_property(_rect, "color:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	await out.finished
	get_tree().change_scene_to_file(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_rect, "color:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	await back.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
