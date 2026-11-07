extends SceneTree
## Sends real mouse events through the window, the same path a player's clicks take.
## Run: godot --path . --script tools/input_test.gd -- --test

var failures := 0
var scale_to_window := 1.0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		failures += 1

# Waits in real time, at 60ths of a second, whatever the actual frame rate is.
func _wait(frames: int) -> void:
	await create_timer(float(frames) / 60.0).timeout

func _to_window(view_pos: Vector2) -> Vector2:
	return view_pos * float(root.size.x) / root.get_visible_rect().size.x

func _click(view_pos: Vector2) -> void:
	var at := _to_window(view_pos)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	await _wait(3)
	var up := down.duplicate()
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await _wait(4)

func _drag(from: Vector2, to: Vector2) -> void:
	var a := _to_window(from)
	var b := _to_window(to)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a
	down.global_position = a
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	await _wait(2)
	var steps := 10
	for i in range(1, steps + 1):
		var move := InputEventMouseMotion.new()
		var p := a.lerp(b, float(i) / float(steps))
		move.position = p
		move.global_position = p
		move.relative = (b - a) / float(steps)
		move.screen_relative = move.relative
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(move)
		await _wait(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	Input.parse_input_event(up)
	await _wait(3)

func _run() -> void:
	var save = root.get_node("Save")
	save.unlocked = 11
	save.tutorial_done = true
	save.salvage = 500
	change_scene_to_file("res://title_screen.tscn")
	await _wait(10)
	var menu = current_scene
	check(menu != null and menu.has_method("_go"), "game boots to the title screen")
	var v: Vector2 = root.get_visible_rect().size
	await _wait(30)
	var w := minf(v.x - 72.0, 620.0)
	var play_y: float = v.y - menu.bottom - 330.0 + 64.0
	await _click(Vector2(v.x * 0.5, play_y))
	await _wait(6)
	check(menu.screen == "map", "tapping PLAY opens the map")
	await _click(Vector2(60, menu.top + 42.0))
	await _wait(6)
	check(menu.screen == "title", "home button returns to title")
	await _wait(50)
	var half := (w - 20.0) * 0.5
	await _click(Vector2((v.x - w) * 0.5 + half * 0.5, play_y - 64.0 + 148.0 + 48.0))
	await _wait(6)
	check(menu.screen == "hangar", "hangar button opens the hangar")
	var bank: int = save.salvage
	# Fourth row of the hangar: its buy button sits at the right edge.
	var hw := minf(v.x - 40.0, 680.0)
	var hx := (v.x - hw) * 0.5
	var rows_top: float = menu.top + 170.0 + 214.0
	await _click(Vector2(hx + hw - 90.0, rows_top + 50.0))
	await _wait(4)
	check(save.salvage < bank and save.upgrade_level("cannon") == 1, "tapping a price buys the upgrade once")
	await _click(Vector2(60, menu.top + 42.0))
	await _wait(50)
	await _click(Vector2(v.x * 0.5, play_y))
	await _wait(6)
	var y_bottom: float = v.y - menu.bottom - 210.0
	var y_top: float = menu.top + 310.0
	save.map_sector = 2
	await _wait(3)
	await _click(menu._node_pos(0, y_bottom, y_top))
	await _wait(70)
	var game = current_scene
	check(game != null and game.has_method("_nova_burst"), "tapping a level starts it")
	check(save.play_level == 11, "the tapped level is the one that loads")
	await _wait(130)
	var P = game.Phase
	check(game.phase == P.PLAYING, "level intro finishes")
	check(game.bullets.size() > 0, "ship fires by itself")
	var start_x: float = game.player_pos.x
	await _drag(Vector2(v.x * 0.5, v.y * 0.6), Vector2(v.x * 0.5 - 170.0, v.y * 0.6))
	await _wait(8)
	check(game.player_pos.x < start_x - 120.0, "dragging moves the ship (moved %d px)" % int(start_x - game.player_pos.x))
	await _click(Vector2(v.x - 55.0, game.top + 35.0))
	await _wait(4)
	check(game.phase == P.PAUSED, "pause button opens pause (single toggle)")
	var count: int = game.enemies.size()
	await _wait(20)
	check(game.enemies.size() == count, "game is frozen while paused")
	var pw := minf(v.x - 100.0, 560.0)
	await _click(Vector2(v.x * 0.5, v.y * 0.5 - 330.0 + 90.0 + 52.0))
	await _wait(5)
	check(game.phase == P.PLAYING, "RESUME button works")
	game.energy = 100.0
	await _wait(3)
	await _click(Vector2(v.x - 92.0, v.y - 104.0 - game.inset.y))
	await _wait(3)
	check(game.energy < 50.0, "Nova button fires the burst")
	game.hull = 1
	game.shield = 0.0
	game.invuln = 0.0
	game._hurt_player(10.0)
	await _wait(70)
	check(game.phase == P.DEFEAT, "losing all hull ends the run")
	await _wait(60)
	var rw := minf(v.x - 56.0, 664.0)
	await _click(Vector2(v.x * 0.5, v.y * 0.5 - 250.0 + 330.0 + 34.0 + 50.0))
	await _wait(70)
	check(current_scene != game and current_scene.has_method("_nova_burst"), "TRY AGAIN restarts the level")
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)
