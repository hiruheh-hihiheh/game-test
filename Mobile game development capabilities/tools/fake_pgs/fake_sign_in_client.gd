extends Node
## Mirrors PlayGamesSignInClient (v3.4.0): connects to the native plugin in _ready(), and only if it already exists.

signal user_authenticated(is_authenticated: bool)
signal server_side_access_requested(token: String)

var wired := false

func _gps() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GodotPlayGameServices")

func _ready() -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		wired = true
		gps.android_plugin.userAuthenticated.connect(func(is_authenticated: bool):
			user_authenticated.emit(is_authenticated)
		)

func is_authenticated() -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		gps.android_plugin.isAuthenticated()

func sign_in() -> void:
	var gps := _gps()
	if gps and gps.android_plugin:
		gps.android_plugin.signIn()
