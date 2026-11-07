extends SceneTree
func _initialize():
	var paths := ["res://game.gd","res://title_screen.gd"]
	for dir in ["res://src","res://src/data","res://src/meta","res://src/combat","res://src/combat/bosses","res://src/menus"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				paths.append(dir + "/" + f)
	var bad := 0
	for p in paths:
		var s: GDScript = load(p)
		if s == null or not s.can_instantiate():
			print("BAD ", p); bad += 1
	print("checked ", paths.size(), " bad ", bad)
	quit()
