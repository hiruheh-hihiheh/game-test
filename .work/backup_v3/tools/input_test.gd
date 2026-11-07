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

func _press(ui, id: String) -> void:
	var r: Rect2 = ui.rect_of(id)
	check(r.size != Vector2.ZERO, "button %s is on screen" % id)
	await _click(r.get_center())

func _run() -> void:
	var save = root.get_node("Save")
	save.unlocked = 11
	save.tutorial = {"move": true, "card": true, "nova": true}
	save.salvage = 500
	change_scene_to_file("res://title_screen.tscn")
	await _wait(10)
	var menu = current_scene
	check(menu != null and menu.has_method("launch"), "game boots to the title screen")
	var v: Vector2 = root.get_visible_rect().size
	await _wait(40)
	await _press(menu.ui, "play")
	await _wait(6)
	check(menu.screen == "map", "tapping PLAY opens the map")
	await _wait(10)
	await _press(menu.ui, "back")
	await _wait(50)
	check(menu.screen == "title", "home button returns to title")
	await _press(menu.ui, "hangar")
	await _wait(10)
	check(menu.screen == "hangar", "hangar button opens the hangar")
	await _press(menu.ui, "tab_gear")
	await _wait(10)
	var bank: int = save.salvage
	await _press(menu.ui, "buy_cannon")
	await _wait(4)
	check(save.salvage < bank and save.upgrade_level("cannon") == 1, "tapping a price buys the upgrade once")
	await _press(menu.ui, "back")
	await _wait(50)
	await _press(menu.ui, "ops")
	await _wait(10)
	check(menu.screen == "ops", "ops opens")
	await _press(menu.ui, "tab_awards")
	await _wait(10)
	await _drag(Vector2(v.x * 0.5, v.y * 0.7), Vector2(v.x * 0.5, v.y * 0.4))
	await _wait(6)
	check(menu.screen == "ops" and menu.ui.scroll > 100.0, "lists scroll by dragging")
	await _press(menu.ui, "back")
	await _wait(50)
	await _press(menu.ui, "play")
	await _wait(10)
	save.map_sector = 2
	await _wait(6)
	await _press(menu.ui, "level11")
	await _wait(10)
	check(menu.screen == "preflight", "tapping a level opens the briefing")
	await _press(menu.ui, "launch")
	await _wait(70)
	var game = current_scene
	check(game != null and game.has_method("try_nova"), "launch starts the level")
	check(int(save.session.level) == 11, "the tapped level is the one that loads")
	await _wait(130)
	var P = game.Phase
	check(game.phase == P.PLAYING, "level intro finishes")
	check(game.shots.size() > 0, "ship fires by itself")
	var start_x: float = game.player_pos.x
	await _drag(Vector2(v.x * 0.5, v.y * 0.6), Vector2(v.x * 0.5 - 170.0, v.y * 0.6))
	await _wait(8)
	check(game.player_pos.x < start_x - 120.0, "dragging moves the ship (moved %d px)" % int(start_x - game.player_pos.x))
	await _press(game.ui, "pause")
	await _wait(4)
	check(game.phase == P.PAUSED, "pause button opens pause (single toggle)")
	var count: int = game.enemies.size()
	await _wait(20)
	check(game.enemies.size() == count, "game is frozen while paused")
	await _press(game.ui, "resume")
	await _wait(70)
	check(game.phase == P.PLAYING, "RESUME button works after the countdown")
	game.energy = 100.0
	await _wait(3)
	await _press(game.ui, "burst")
	await _wait(3)
	check(game.energy < 50.0, "Nova button fires the burst")
	game.hull = 1
	game.shield = 0.0
	game.invuln = 0.0
	game.hurt_player(10.0)
	await _wait(100)
	check(game.phase == P.DEFEAT, "losing all hull ends the run")
	await _wait(60)
	await _press(game.ui, "retry")
	await _wait(70)
	check(current_scene != game and current_scene.has_method("try_nova"), "TRY AGAIN restarts the level")
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)
