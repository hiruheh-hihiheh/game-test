class_name MenuHangar
extends RefCounted
## Ships, gear, tech and Nova modes.

var m
var tab := "ships"
var gear: MenuGear

func _init(hub) -> void:
	m = hub
	gear = MenuGear.new(hub)

## Opening the Hangar with new loot goes straight to the Gear tab.
func on_enter() -> void:
	if Save.new_gear_count() > 0:
		tab = "gear"
		gear.on_open()

func on_ui(id: String) -> void:
	if id.begins_with("g_"):
		gear.on_ui(id)
		return
	if id.begins_with("tab_"):
		tab = id.substr(4)
		m.ui.reset_scroll()
		if tab == "gear":
			gear.on_open()
	elif id.begins_with("buy_"):
		if Save.buy_upgrade(id.substr(4)):
			Audio.play("ui_buy")
			Save.haptic(30)
		else:
			Audio.play("ui_deny")
	elif id.begins_with("ship_"):
		var ship_id := id.substr(5)
		if ship_id in Save.owned_ships:
			Save.ship = ship_id
			Save.save_data()
			Audio.play("ui_click")
		elif Save.buy_ship(ship_id):
			Audio.play("unlock")
			Meta.sync_collection_stats()
		else:
			Audio.play("ui_deny")
	elif id.begins_with("paint_"):
		Save.paints[Save.ship] = id.substr(6)
		Save.save_data()
		Audio.play("ui_click")
	elif id.begins_with("nova_"):
		var mode_id := id.substr(5)
		if Save.has_blueprint(str(Ships.NOVA_MODES[mode_id].blueprint)):
			Save.nova_mode = mode_id
			Save.save_data()
			Audio.play("ui_click")
		else:
			Audio.play("ui_deny")

func paint(c: UILayer) -> void:
	var W: float = m.W
	var top: float = float(m.top) + 262.0
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var y := top - c.scroll
	match tab:
		"ships":
			y = _paint_ships(c, x, y, w)
		"gear":
			y = gear.paint(c, x, y, w)
		"lab":
			y = _paint_items(c, x, y, w, "gear")
			y = _lab_header(c, x, y, w)
			y = _paint_items(c, x, y, w, "lab")
		"tech":
			y = _paint_items(c, x, y, w, "tech")
		"nova":
			y = _paint_nova(c, x, y, w)
	c.scroll_max = maxf(0.0, y + c.scroll - float(m.H) + float(m.bottom) + 30.0)
	m.header(c, "HANGAR", UI.CYAN)
	var tabs := [["ships", "SHIPS"], ["gear", "GEAR"], ["lab", "LAB"], ["tech", "TECH"], ["nova", "NOVA"]]
	var tw := (w - 24.0) / 5.0
	c.draw_rect(Rect2(0, float(m.top) + 178.0, W, 76.0), Color(0.01, 0.01, 0.05, 0.86))
	for i in range(tabs.size()):
		var on: bool = tab == tabs[i][0]
		c.button("tab_" + str(tabs[i][0]), Rect2(x + float(i) * (tw + 6.0), float(m.top) + 186.0, tw, 62), str(tabs[i][1]), UI.MINT if on else UI.CYAN, {"primary": on, "size": 19})

func _paint_ships(c: UILayer, x: float, y: float, w: float) -> float:
	for id in Ships.ORDER:
		var ship: Dictionary = Ships.LIST[id]
		var h := 176.0
		var r := Rect2(x, y, w, h)
		var on: bool = Save.ship == id
		var owned: bool = id in Save.owned_ships
		var available := Save.ship_available(id)
		var color: Color = UI.MINT if on else UI.CYAN
		c.hit_area("ship_" + id, r, {"sound": ""})
		UI.panel(c, r, Color(color.darkened(0.8), 0.95), Color(color, 0.95 if on else 0.4), 16, 3 if on else 2)
		var at := r.position + Vector2(88, h * 0.5)
		UI.glow(c, at, 90.0, Color(color, 0.25))
		var tint := Color.WHITE if owned else (Color(0.6, 0.6, 0.7) if available else Color(0.1, 0.1, 0.16))
		UI.icon(c, Ships.ART[id], at, 138.0, tint)
		var tx := r.position.x + 172.0
		UI.text(c, str(ship.name), Vector2(tx, r.position.y + 38.0), 27, UI.WHITE, true)
		UI.text(c, str(ship.role), Vector2(r.end.x - 20.0, r.position.y + 36.0), 17, color, true, UI.RIGHT)
		UI.text(c, str(ship.weapon_desc), Vector2(tx, r.position.y + 68.0), 20, UI.TEXT_DIM)
		var lines := UI.wrap_lines(str(ship.trait) + ": " + str(ship.trait_desc), 18, w - 192.0)
		for l in range(mini(lines.size(), 2)):
			UI.text(c, lines[l], Vector2(tx, r.position.y + 96.0 + float(l) * 24.0), 18, UI.GOLD if l == 0 else UI.GOLD)
		var foot := r.position.y + h - 16.0
		if owned:
			var lvl := Save.ship_mastery(id)
			UI.text(c, "MASTERY %d" % lvl, Vector2(tx, foot), 17, UI.MINT, true)
			if lvl < Ships.MAX_MASTERY:
				var prev: int = Ships.xp_for(lvl - 1) if lvl > 1 else 0
				var ratio := float(Save.ship_xp(id) - prev) / float(Ships.xp_for(lvl) - prev)
				UI.bar(c, Rect2(tx + 136.0, foot - 13.0, w - 330.0, 13.0), ratio, UI.MINT)
		elif available:
			UI.text(c, "UNLOCK: %d SALVAGE" % int(ship.cost), Vector2(tx, foot), 18, UI.GOLD if Save.salvage >= int(ship.cost) else UI.TEXT_DIM, true)
		else:
			UI.text(c, "BLUEPRINT NEEDED: BEAT A BOSS", Vector2(tx, foot), 17, UI.TEXT_DIM, true)
		y += h + 12.0
	return _paint_paints(c, x, y, w)

func _paint_paints(c: UILayer, x: float, y: float, w: float) -> float:
	var lvl := Save.ship_mastery(Save.ship)
	UI.text(c, "PAINT FOR " + str(Ships.LIST[Save.ship].name), Vector2(x + 4.0, y + 20.0), 20, UI.TEXT_DIM, true)
	y += 32.0
	var keys: Array = Ships.PAINTS.keys()
	var cell := (w - 50.0) / 6.0
	for i in range(keys.size()):
		var id: String = keys[i]
		var open: bool = id == "stock" or Save.has_blueprint(str(Ships.PAINTS[id].get("blueprint", "locked")))
		for lv in Ships.MASTERY:
			if str(Ships.MASTERY[lv].get("paint", "")) == id and lvl >= int(lv):
				open = true
		var r := Rect2(x + float(i) * (cell + 10.0), y, cell, 66)
		var on := Save.paint_of(Save.ship) == id
		if open:
			c.button("paint_" + id, r, str(Ships.PAINTS[id].name), UI.MINT if on else UI.CYAN, {"size": 14, "primary": on})
		else:
			UI.panel(c, r, Color(0.02, 0.03, 0.07, 0.7), Color(0.4, 0.44, 0.54, 0.3), 12, 2)
			UI.text(c, "LOCKED", r.get_center() + Vector2(0, 6), 14, Color(0.5, 0.54, 0.62), true, UI.CENTER)
	return y + 80.0

func _paint_items(c: UILayer, x: float, y: float, w: float, kind: String) -> float:
	for item in Hangar.LIST:
		if str(item.kind) != kind:
			continue
		var id: String = item.id
		var lvl := Save.upgrade_level(id)
		var maxed: bool = lvl >= int(item.max)
		var need := Hangar.stars_needed(id)
		var gated := Save.total_stars() < need
		var lab_locked: bool = str(item.kind) == "lab" and not Hangar.lab_open()
		var h := 112.0
		var r := Rect2(x, y, w, h - 10.0)
		UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.92), Color(UI.CYAN, 0.28), 14, 2)
		UI.icon(c, Cards.ICONS[item.icon], r.position + Vector2(54, r.size.y * 0.5), 76.0)
		UI.text(c, str(item.name), r.position + Vector2(108, 34), 24, UI.WHITE, true)
		var lines := UI.wrap_lines(str(item.desc), 17, w - 300.0)
		UI.text(c, lines[0], r.position + Vector2(108, 60), 17, UI.TEXT_DIM)
		if int(item.max) <= 12:
			UI.pips(c, r.position + Vector2(108, r.size.y - 22.0), int(item.max), lvl, UI.MINT, Vector2(26, 8), 5.0)
		else:
			UI.text(c, "LEVEL %d" % lvl, r.position + Vector2(108, r.size.y - 14.0), 18, UI.MINT, true)
		var br := Rect2(r.end.x - 168, r.position.y + 12.0, 156, r.size.y - 24.0)
		if maxed:
			c.button("maxed_" + id, br, "MAX", UI.MINT, {"size": 24, "disabled": true})
		elif lab_locked:
			c.button("lab_" + id, br, "LOCKED", Color(0.5, 0.54, 0.64), {"size": 20, "disabled": true})
		elif gated:
			c.button("gated_" + id, br, "%d STARS" % need, Color(0.5, 0.54, 0.64), {"size": 20, "disabled": true})
		else:
			var cost := Hangar.cost(id, lvl)
			c.button("buy_" + id, br, str(cost), UI.GOLD if Save.salvage >= cost else Color(0.5, 0.54, 0.64), {"icon": m.SALVAGE_ART, "size": 23, "sound": ""})
		y += h
	return y

func _lab_header(c: UILayer, x: float, y: float, w: float) -> float:
	y += 10.0
	UI.outlined(c, "OVERCLOCK LAB", Vector2(x + 4.0, y + 24.0), 24, UI.GOLD, true)
	var text := "Endless upgrades. Never maxes out." if Hangar.lab_open() else "Unlocks when every upgrade above is maxed."
	UI.text(c, text, Vector2(x + 4.0, y + 54.0), 18, UI.TEXT_DIM)
	return y + 74.0

func _paint_nova(c: UILayer, x: float, y: float, w: float) -> float:
	for id in Ships.NOVA_MODES:
		var def: Dictionary = Ships.NOVA_MODES[id]
		var open := Save.has_blueprint(str(def.blueprint))
		var on: bool = Save.nova_mode == id
		var h := 128.0
		var r := Rect2(x, y, w, h)
		var color: Color = UI.MINT if on else UI.CYAN
		c.hit_area("nova_" + id, r, {"sound": ""})
		UI.panel(c, r, Color(color.darkened(0.8), 0.94 if open else 0.5), Color(color, 0.95 if on else 0.4), 14, 3 if on else 2)
		UI.text(c, str(def.name) if open else "??????", r.position + Vector2(24, 44), 26, UI.WHITE, true)
		var lines := UI.wrap_lines(str(def.desc) if open else "Blueprint not found. Defeat more bosses.", 19, w - 48.0)
		for l in range(mini(lines.size(), 2)):
			UI.text(c, lines[l], r.position + Vector2(24, 76.0 + float(l) * 26.0), 19, UI.TEXT_DIM)
		if on:
			UI.text(c, "EQUIPPED", r.position + Vector2(w - 24.0, 42), 18, UI.MINT, true, UI.RIGHT)
		y += h + 12.0
	return y
