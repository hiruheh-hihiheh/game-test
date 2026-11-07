extends Node
## Stands in for the plugin's GodotPlayGameServices autoload. Like the real one, initialize() creates the native
## plugin reference once, and a second call reports PLUGIN_NOT_FOUND.

var android_plugin: Object
## False plays a build where the native Android plugin was not exported.
var native_present := true
var initialize_calls := 0

func initialize() -> int:
	initialize_calls += 1
	if not android_plugin:
		if native_present:
			android_plugin = load("res://tools/fake_pgs/fake_android_plugin.gd").new()
			android_plugin.initialize()
			return 0
	return 1
