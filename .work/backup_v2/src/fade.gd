extends CanvasLayer
## Smooth screen transitions. Autoloaded as "Fade".

var _rect: ColorRect
var _busy := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.008, 0.006, 0.02, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

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
