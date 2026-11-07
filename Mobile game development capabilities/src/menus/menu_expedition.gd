class_name MenuExpedition
extends RefCounted
## Expedition: choose a sector, walk a branching route, handle depots and signals.

var m
var overlay := ""
var signal_event := {}
var message := ""
var picker := DangerPicker.new()

func _init(hub) -> void:
	m = hub

func on_ui(id: String) -> void:
	if id.begins_with("start"):
		Expedition.start(int(id.substr(5)))
		Audio.play("wave_start", -4.0)
		return
	if id.begins_with("node"):
		_enter(int(id.substr(4)))
		return
	if overlay == "danger":
		if picker.on_ui(id, _danger_ctx()):
			return
		if id == "danger_go":
			var chosen := Danger.sanitize(picker.chosen, _danger_ctx())
			if not chosen.is_empty():
				Danger.remember(chosen, "expedition")
			overlay = ""
			m.launch({"mode": "expedition", "level": 1, "mutators": [], "danger": chosen})
		elif id == "danger_cancel":
			overlay = ""
			Save.expedition.current = {}
		return
	match id:
		"abandon":
			Expedition.abandon()
		"choice_a":
			_choose("a")
		"choice_b":
			_choose("b")
		"repair":
			if Expedition.depot_repair():
				Audio.play("repair")
			else:
				Audio.play("ui_deny")
		"module":
			var card := Expedition.depot_module()
			if card.is_empty():
				Audio.play("ui_deny")
			else:
				Audio.play("ui_buy")
				message = "Installed " + str(Cards.LIST[card].name)
		"leave":
			overlay = ""
			message = ""
			Expedition.advance()

func _enter(index: int) -> void:
	if not Expedition.reachable(index):
		Audio.play("ui_deny")
		return
	var type := Expedition.enter_node(index)
	match type:
		"depot":
			overlay = "depot"
			message = ""
		"signal":
			overlay = "signal"
			signal_event = Expedition.pick_signal(int(Save.expedition.current.seed))
			message = ""
		"elite", "boss":
			# The hard fights offer optional contracts. Ordinary battles stay as they are.
			if Danger.unlocked():
				overlay = "danger"
				picker.reset("expedition")
			else:
				m.launch({"mode": "expedition", "level": 1, "mutators": []})
		_:
			m.launch({"mode": "expedition", "level": 1, "mutators": []})

func _danger_ctx() -> Dictionary:
	return {"mode": "expedition", "dials": [], "picks": -1}

func _choose(side: String) -> void:
	if not message.is_empty():
		return
	message = Expedition.apply_choice(signal_event[side])
	Audio.play("ui_buy")
	Save.save_data()

func paint(c: UILayer) -> void:
	if not Expedition.active():
		_paint_sectors(c)
	elif overlay == "depot":
		_paint_depot(c)
	elif overlay == "signal":
		_paint_signal(c)
	elif overlay == "danger":
		_paint_danger(c)
	else:
		_paint_route(c)

func _paint_sectors(c: UILayer) -> void:
	var y: float = m.header(c, "EXPEDITION", UI.MAGENTA)
	var w: float = minf(float(m.W) - 40.0, 680.0)
	var x: float = (float(m.W) - w) * 0.5
	var lines := UI.wrap_lines("Choose a route through a sector. Your hull and modules carry from fight to fight. Die and half your haul makes it home.", 20, w - 8.0)
	for l in lines:
		UI.text(c, l, Vector2(x + 4.0, y + 24.0), 20, UI.TEXT_DIM)
		y += 28.0
	y += 18.0
	var open := mini(Levels.sector_of(Save.unlocked), Levels.SECTOR_COUNT)
	for i in range(Levels.SECTOR_COUNT):
		var info: Dictionary = Levels.SECTORS[i]
		var seen: Array = Save.stats.get("seen_expedition_unique", [])
		var label := str(info.name)
		c.button("start%d" % (i + 1), Rect2(x, y, w, 88), label, info.color, {"size": 26, "disabled": i + 1 > open, "sub": "Cleared" if (i + 1) in seen else ""})
		y += 100.0

func _node_pos(layer: int, index: int, count: int) -> Vector2:
	var y: float = float(m.H) - float(m.bottom) - 120.0 - float(layer) * ((float(m.H) - 500.0) / float(Expedition.LAYERS - 1))
	var w: float = float(m.W) - 200.0
	var x: float = float(m.W) * 0.5 if count <= 1 else 100.0 + w * float(index) / float(count - 1)
	return Vector2(x, y)

func _paint_route(c: UILayer) -> void:
	var run: Dictionary = Save.expedition
	var layers: Array = run.layers
	var current: int = run.layer
	var y: float = m.header(c, str(Levels.SECTORS[int(run.sector) - 1].name), Levels.SECTORS[int(run.sector) - 1].color)
	var hull: int = int(run.hull)
	UI.text(c, "HULL %s" % ("FULL" if hull < 0 else str(hull)), Vector2(40, y + 26.0), 22, UI.WHITE, true)
	UI.text(c, "RUN SALVAGE %d" % int(run.salvage), Vector2(float(m.W) - 40.0, y + 26.0), 22, UI.MINT, true, UI.RIGHT)
	for l in range(layers.size() - 1):
		var row: Array = layers[l]
		var next: Array = layers[l + 1]
		for i in range(row.size()):
			for k in range(next.size()):
				var from := float(i) / maxf(1.0, float(row.size() - 1))
				var to := float(k) / maxf(1.0, float(next.size() - 1))
				if absf(from - to) <= 0.55 or row.size() == 1 or next.size() == 1:
					c.draw_line(_node_pos(l, i, row.size()), _node_pos(l + 1, k, next.size()), Color(1, 1, 1, 0.12), 2.0)
	for l in range(layers.size()):
		var row: Array = layers[l]
		for i in range(row.size()):
			_paint_route_node(c, l, i, row, current)
	c.button("abandon", Rect2(float(m.W) * 0.5 - 130.0, float(m.H) - float(m.bottom) - 56.0, 260, 56), "ABANDON RUN", UI.RED, {"size": 18})

func _paint_route_node(c: UILayer, l: int, i: int, row: Array, current: int) -> void:
	var node: Dictionary = row[i]
	var info: Dictionary = Expedition.NODE_INFO[node.type]
	var pos := _node_pos(l, i, row.size())
	var r := 52.0
	var col: Color = info.color
	var is_now := l == current and Expedition.reachable(i)
	if is_now:
		c.hit_area("node%d" % i, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0))
		UI.glow(c, pos, r * 1.9 * (1.0 + sin(float(m.t) * 4.0) * 0.1), Color(col, 0.5))
	var dim := 1.0 if is_now else (0.55 if l > current else 0.3)
	UI.panel(c, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), Color(col.darkened(0.7), 0.96 * dim), Color(col, dim), 18, 3)
	UI.text(c, str(info.name), pos + Vector2(0, 7), 17, Color(UI.WHITE, dim), true, UI.CENTER)

func _paint_danger(c: UILayer) -> void:
	var node_type := str((Save.expedition.get("current", {}) as Dictionary).get("type", "elite"))
	var y: float = m.header(c, "CONTRACTS", UI.MAGENTA) - c.scroll
	var w: float = minf(float(m.W) - 40.0, 680.0)
	var x: float = (float(m.W) - w) * 0.5
	UI.text(c, "%s NODE" % node_type.to_upper(), Vector2(float(m.W) * 0.5, y + 12.0), 22, UI.TEXT_DIM, true, UI.CENTER)
	y += 30.0
	y = picker.paint(c, x, y, w, _danger_ctx())
	var by: float = float(m.H) - float(m.bottom) - 108.0
	c.scroll_max = maxf(0.0, y + c.scroll - by + 12.0)
	c.draw_rect(Rect2(0, by - 10.0, float(m.W), float(m.H)), Color(0.01, 0.01, 0.05, 0.9))
	c.button("danger_cancel", Rect2(x, by, 190, 100), "BACK", Color(0.6, 0.64, 0.74), {"size": 24})
	var label := "FIGHT" if picker.chosen.is_empty() else "FIGHT WITH DANGER"
	c.button("danger_go", Rect2(x + 204.0, by, w - 204.0, 100), label, UI.MINT, {"primary": true, "size": 28})

func _paint_depot(c: UILayer) -> void:
	var y: float = m.header(c, "DEPOT", UI.MINT)
	var run: Dictionary = Save.expedition
	var w: float = minf(float(m.W) - 60.0, 640.0)
	var x: float = (float(m.W) - w) * 0.5
	UI.text(c, "RUN SALVAGE %d" % int(run.salvage), Vector2(float(m.W) * 0.5, y + 40.0), 26, UI.MINT, true, UI.CENTER)
	y += 80.0
	c.button("repair", Rect2(x, y, w, 100), "REPAIR 1 HULL", UI.MINT, {"size": 26, "sub": "%d salvage" % Expedition.DEPOT_REPAIR})
	y += 116.0
	c.button("module", Rect2(x, y, w, 100), "BUY A MODULE", UI.GOLD, {"size": 26, "sub": "%d salvage" % Expedition.DEPOT_MODULE})
	y += 124.0
	if not message.is_empty():
		UI.text(c, message, Vector2(float(m.W) * 0.5, y + 24.0), 23, UI.WHITE, false, UI.CENTER)
		y += 50.0
	c.button("leave", Rect2(x, y, w, 90), "MOVE ON", UI.CYAN, {"size": 26, "primary": true})

func _paint_signal(c: UILayer) -> void:
	var y: float = m.header(c, "SIGNAL", UI.GOLD)
	var w: float = minf(float(m.W) - 60.0, 640.0)
	var x: float = (float(m.W) - w) * 0.5
	UI.text(c, str(signal_event.title), Vector2(float(m.W) * 0.5, y + 44.0), 30, UI.GOLD, true, UI.CENTER)
	y += 70.0
	for l in UI.wrap_lines(str(signal_event.text), 23, w):
		UI.text(c, l, Vector2(float(m.W) * 0.5, y + 28.0), 23, UI.WHITE, false, UI.CENTER)
		y += 34.0
	y += 34.0
	if message.is_empty():
		for side in ["a", "b"]:
			var lines := UI.wrap_lines(str(signal_event[side].label), 21, w - 40.0)
			var label: String = lines[0]
			var sub: String = lines[1] if lines.size() > 1 else ""
			c.button("choice_" + side, Rect2(x, y, w, 104), label, UI.GOLD if side == "a" else UI.CYAN, {"size": 21, "sub": sub})
			y += 120.0
	else:
		UI.text(c, message, Vector2(float(m.W) * 0.5, y + 24.0), 25, UI.MINT, true, UI.CENTER)
		y += 70.0
		c.button("leave", Rect2(x, y, w, 90), "MOVE ON", UI.CYAN, {"size": 26, "primary": true})
