extends SceneTree
## Run by the test suite, twice at once, as two real processes sharing one save path. Each reserves generations and
## writes a pair of recovery files per generation as fast as it can, then records what it believes it owns.
## Not meant to be run by hand. Arguments: --path=<save path> --tag=<A or B> --count=<n> --start=<unix seconds>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var shared := ""
	var tag := "X"
	var count := 20
	var start := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			shared = arg.substr(7)
		elif arg.begins_with("--tag="):
			tag = arg.substr(6)
		elif arg.begins_with("--count="):
			count = int(arg.substr(8))
		elif arg.begins_with("--start="):
			start = float(arg.substr(8))
	var save = root.get_node("Save")
	var own_path: String = save.path
	save.path = shared
	save.test_mode = false  # the shared recovery folder must outlive this process; the parent removes it
	var cloud = load("res://src/meta/cloud_sync.gd").new()
	cloud.autostart = false
	root.add_child(cloud)
	while Time.get_unix_time_from_system() < start:
		pass
	var lines: Array = []
	for i in range(count):
		var rec: Dictionary = cloud._recovery_reserve()
		if rec.is_empty():
			lines.append("none")
			continue
		var payload := ("%s-%d-" % [tag, i]).repeat(300).to_utf8_buffer()
		var a: bool = cloud._recovery_put(rec, "cloud_save", "blob", payload)
		var b: bool = cloud._recovery_put(rec, "local_progress", "blob", payload)
		cloud._recovery_finish(rec)
		lines.append("%d %s %s %s-%d" % [int(rec.gen), a, b, tag, i])
	var f := FileAccess.open(shared + ".result_" + tag, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	save.remove_files(own_path)
	quit()
