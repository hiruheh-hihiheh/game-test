extends "res://tools/test_game.gd"
## Stress test: fills the screen with the worst case and reports the script cost per frame.
## Run: godot --headless --path . --script tools/bench.gd -- --test

func _run() -> void:
	save = root.get_node("Save")
	save.blueprints = ["bp_seeker", "bp_burn", "bp_arc", "bp_cryo", "bp_spike"]
	save.tutorial = {"move": true, "card": true, "nova": true, "crystal": true}
	save.session = {"mode": "campaign", "level": 58, "mutators": []}
	var game = await _new_game(save.session)
	_step(game, 2.0)
	game.held = {"spread": 4, "pierce": 3, "drone": 3, "seeker": 3, "overclock": 4, "burn": 1, "arc": 3}
	game._recompute()
	game.invuln = 9999.0
	var ms_total := 0.0
	var ms_peak := 0.0
	var frames := 600
	for f in range(frames):
		game.hull = game.max_hull
		game.invuln = 9999.0
		# Keep the screen at the bullet cap, far above anything a real level produces.
		while game.field.count < 620:
			game.ebullet(Vector2(randf_range(0.0, game.W), randf_range(0.0, 500.0)), randf_range(0.2, 2.9), 140.0, randi() % 5)
		while game.enemies.size() < 40:
			game.spawn_enemy({"kind": ["fighter", "weaver", "raider", "gunship"][randi() % 4], "pos": Vector2(randf_range(40.0, game.W - 40.0), randf_range(50.0, 500.0)), "move": "straight", "vel": Vector2(0, 10)})
		var before := Time.get_ticks_usec()
		game._process(1.0 / 60.0)
		var ms := float(Time.get_ticks_usec() - before) / 1000.0
		ms_total += ms
		ms_peak = maxf(ms_peak, ms)
		if f % 120 == 0:
			await process_frame
	print("BENCH bullets=%d enemies=%d shots=%d sparks=%d" % [game.field.count, game.enemies.size(), game.shots.size(), game.fx.spark_count])
	print("BENCH avg %.2f ms, peak %.2f ms per frame (16.6 ms budget at 60 fps)" % [ms_total / float(frames), ms_peak])
	game.queue_free()
	quit()
