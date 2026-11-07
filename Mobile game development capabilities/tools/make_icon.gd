extends SceneTree
## Builds res://icon.png: the Nova ship on a glowing panel.
## Run: godot --headless --path . --script tools/make_icon.gd

func _initialize() -> void:
	var size := 512
	var ship := Image.new()
	ship.load("res://assets/starfall/ships/player_nova_01.png")
	ship.convert(Image.FORMAT_RGBA8)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(center) / (size * 0.72)
			var glow := pow(clampf(1.0 - d, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(0.02, 0.03, 0.10).lerp(Color(0.10, 0.50, 0.78), glow))
	ship.resize(430, 430, Image.INTERPOLATE_LANCZOS)
	img.blend_rect(ship, Rect2i(0, 0, 430, 430), Vector2i(41, 41))
	img.save_png("res://icon.png")
	quit()
