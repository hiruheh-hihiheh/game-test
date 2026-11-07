class_name MenuGear
extends RefCounted
## The Gear tab of the Hangar: equip, upgrade and scrap loot.

const CARD_H := 164.0

var m
var filter := ""
var fresh: Array = []
var confirm_uid := 0

func _init(hub) -> void:
	m = hub

## Remembers which items are new this visit, then clears their flag.
func on_open() -> void:
	fresh = []
	for it in Save.gear:
		if bool(it.get("new", false)):
			fresh.append(int(it.uid))
			it["new"] = false
	confirm_uid = 0
	Save.mark_dirty()

func on_ui(id: String) -> void:
	if id.begins_with("g_equip_"):
		if Save.equip(Save.ship, int(id.substr(8))):
			Audio.play("ui_buy")
			Save.save_data()
		confirm_uid = 0
	elif id.begins_with("g_unequip_"):
		Save.unequip(Save.ship, id.substr(10))
		Audio.play("ui_back")
		Save.save_data()
	elif id.begins_with("g_up_"):
		if Save.upgrade_gear(int(id.substr(5))):
			Audio.play("evolve", -4.0)
			Save.haptic(25)
			Meta.count("gear_upgrade")
			Save.save_data()
	elif id.begins_with("g_scrap_"):
		_scrap(id.substr(8))
	elif id.begins_with("g_filter_"):
		filter = "" if id.substr(9) == "all" else id.substr(9)
		m.ui.reset_scroll()

func _scrap(arg: String) -> void:
	if arg == "low":
		var gained := 0
		for it in Save.gear.duplicate():
			if int(it.rarity) <= Gear.UNCOMMON and Save.equipped_on(int(it.uid)).is_empty():
				gained += maxi(0, Save.scrap_gear(int(it.uid)))
		if gained > 0:
			Audio.play("ui_buy")
			Save.save_data()
		return
	var uid := int(arg)
	var item := Save.gear_by_uid(uid)
	if item.is_empty():
		return
	if int(item.rarity) >= Gear.RARE and confirm_uid != uid:
		confirm_uid = uid
		return
	if Save.scrap_gear(uid) >= 0:
		Audio.play("ui_back")
		Save.save_data()
	confirm_uid = 0

## Draws the tab and returns the y just below it.
func paint(c: UILayer, x: float, y: float, w: float) -> float:
	var ship: String = Save.ship
	UI.outlined(c, "EQUIPPED ON %s" % str(Ships.LIST[ship].name), Vector2(x + 4.0, y + 22.0), 21, UI.CYAN, true)
	y += 36.0
	for slot in Gear.SLOTS:
		var item: Dictionary = Save.equipped_item(ship, slot)
		if item.is_empty():
			y = _empty_slot(c, x, y, w, slot)
		else:
			y = _card(c, item, x, y, w, true)
	y += 8.0
	var chip := Rect2(x, y, 230, 62)
	UI.panel(c, chip, Color(0.02, 0.04, 0.1, 0.9), Color(UI.GOLD, 0.6), 12, 2)
	UI.text(c, "PARTS", chip.position + Vector2(18, 38), 19, UI.TEXT_DIM, true)
	UI.text(c, str(Save.parts), chip.position + Vector2(212, 41), 28, UI.WHITE, true, UI.RIGHT)
	c.button("g_scrap_low", Rect2(x + 246.0, y, w - 246.0, 62), "SCRAP COMMON + UNCOMMON", UI.ORANGE, {"size": 17})
	y += 78.0
	UI.outlined(c, "BAG  %d / %d" % [Save.gear.size(), Gear.MAX_ITEMS], Vector2(x + 4.0, y + 22.0), 21, UI.CYAN, true)
	y += 36.0
	var chips := [["all", "ALL"], ["weapon", "WEAPON"], ["reactor", "REACTOR"], ["plating", "PLATING"]]
	var cw := (w - 18.0) / 4.0
	for i in range(chips.size()):
		var on: bool = (filter == "" and chips[i][0] == "all") or filter == chips[i][0]
		c.button("g_filter_" + str(chips[i][0]), Rect2(x + float(i) * (cw + 6.0), y, cw, 54), str(chips[i][1]), UI.MINT if on else UI.CYAN, {"primary": on, "size": 16})
	y += 68.0
	var bag: Array = []
	for it in Save.gear:
		if not filter.is_empty() and str(it.slot) != filter:
			continue
		if Save.equipped_on(int(it.uid)) == ship:
			continue
		bag.append(it)
	bag.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.rarity) != int(b.rarity):
			return int(a.rarity) > int(b.rarity)
		return Gear.rating(a) > Gear.rating(b))
	if bag.is_empty():
		UI.text(c, "Nothing here yet. Fly levels to find gear.", Vector2(x + w * 0.5, y + 40.0), 20, UI.TEXT_DIM, false, UI.CENTER)
		y += 80.0
	for it in bag:
		y = _card(c, it, x, y, w, false)
	return y + 10.0

func _empty_slot(c: UILayer, x: float, y: float, w: float, slot: String) -> float:
	var h := 92.0
	var r := Rect2(x, y, w, h)
	if y + h < -10.0 or y > float(m.H):
		return y + h + 10.0
	UI.panel(c, r, Color(0.03, 0.05, 0.12, 0.7), Color(UI.CYAN, 0.2), 14, 2)
	# The empty slot shows its illustration as a colourless outline of what could go here.
	UIArt.draw(c, slot, r.position + Vector2(52, h * 0.5), 66.0, {"animate": false, "tint": UIArt.GHOST})
	UI.text(c, "EMPTY " + str(Gear.SLOT_INFO[slot].name), r.position + Vector2(104, 40), 22, UI.TEXT_DIM, true)
	UI.text(c, "Equip gear from your bag below", r.position + Vector2(104, 68), 18, UI.TEXT_DIM)
	return y + h + 10.0

func _card(c: UILayer, item: Dictionary, x: float, y: float, w: float, equipped: bool) -> float:
	var h := CARD_H
	if y + h < -10.0 or y > float(m.H):
		return y + h + 10.0
	var uid := int(item.uid)
	var rarity: int = item.rarity
	var color: Color = Gear.RARITY_COLORS[rarity]
	var r := Rect2(x, y, w, h)
	UI.panel(c, r, Color(color.darkened(0.82), 0.96), Color(color, 0.95 if rarity >= Gear.EPIC else 0.55), 14, 3 if rarity >= Gear.EPIC else 2, 12 if rarity == Gear.LEGENDARY else 0)
	# Legendary gear carries a faint watermark of the boss it comes from, tucked behind the text.
	if rarity == Gear.LEGENDARY:
		var perk: String = str(item.get("perk", ""))
		if Gear.PERKS.has(perk):
			UIArt.boss_mark(c, int(Gear.PERKS[perk].boss), Rect2(r.end.x - 330.0, r.position.y + 12.0, 150.0, h - 24.0), 0.11)
	var icon_at := r.position + Vector2(52, 60)
	# Rarity is the glow: none for Common and Uncommon, rising for Rare and Epic, a slow gold pulse for Legendary.
	var glow_a: float = [0.0, 0.0, 0.24, 0.36, 0.4][rarity]
	if rarity == Gear.LEGENDARY and not UIArt.calm():
		glow_a += 0.1 * sin(UIArt.now() * TAU / 3.6)
	if glow_a > 0.0:
		UI.glow(c, icon_at, 62.0 + float(rarity) * 3.0, Color(color, glow_a))
	var shade: float = [0.8, 0.9, 1.0, 1.0, 1.0][rarity]
	UIArt.draw(c, str(item.slot), icon_at, 80.0, {"tint": Color(shade, shade, shade)})
	# Everything on the right of the art has to fit between it and the buttons, whatever the name or stats.
	var bx := r.end.x - 166.0
	var current: Dictionary = {} if equipped else Save.equipped_item(Save.ship, str(item.slot))
	var rarity_label := str(Gear.RARITY_NAMES[rarity])
	UI.fit_text(c, rarity_label, r.position + Vector2(52.0 - UI.width_of(rarity_label, UI.fit_size(rarity_label, 14, 11, 84.0, true), true) * 0.5, 126), 14, 11, 84.0, color, true)
	var tx := r.position.x + 104.0
	var limit := bx - 12.0 - tx
	var name_text := str(item.name)
	var tag_w := (UI.width_of("NEW", 16, true) + 12.0) if uid in fresh else 0.0
	var name_w := limit - tag_w - (92.0 if not current.is_empty() else 0.0)
	var used := UI.fit_text(c, name_text, Vector2(tx, r.position.y + 34.0), 22, 17, name_w, UI.WHITE, true)
	if uid in fresh:
		UI.text(c, "NEW", Vector2(tx + used + 12.0, r.position.y + 33.0), 16, UI.GOLD, true)
	var cap := Gear.level_cap(item)
	UI.fit_text(c, "LV %d/%d   RATING %d" % [int(item.lvl), cap, Gear.rating(item)], Vector2(tx, r.position.y + 58.0), 16, 13, limit, UI.TEXT_DIM)
	var ly := r.position.y + 84.0
	for line in Gear.lines(item):
		UI.fit_text(c, str(line), Vector2(tx, ly), 18, 14, limit, UI.MINT)
		ly += 21.0
	var perk := Gear.perk_text(item)
	if not perk.is_empty():
		UI.fit_text(c, "* " + perk, Vector2(tx, ly), 18, 13, limit, UI.GOLD, true)
	if equipped:
		var cost := Gear.upgrade_cost(item)
		if cost < 0:
			c.button("g_max_%d" % uid, Rect2(bx, r.position.y + 14.0, 150, 62), "MAX", UI.MINT, {"size": 21, "disabled": true})
		else:
			c.button("g_up_%d" % uid, Rect2(bx, r.position.y + 14.0, 150, 62), "UPGRADE", UI.GOLD, {"size": 19, "sub": "%d parts" % cost, "disabled": Save.parts < cost, "sound": ""})
		c.button("g_unequip_" + str(item.slot), Rect2(bx, r.position.y + 86.0, 150, 62), "UNEQUIP", UI.CYAN, {"size": 19})
	else:
		if not current.is_empty():
			_delta_arrow(c, Vector2(bx - 14.0, r.position.y + 30.0), Gear.rating(item) - Gear.rating(current))
		c.button("g_equip_%d" % uid, Rect2(bx, r.position.y + 14.0, 150, 62), "EQUIP", UI.MINT, {"size": 21, "primary": true, "sound": ""})
		var other := Save.equipped_on(uid)
		if not other.is_empty():
			c.button("g_used_%d" % uid, Rect2(bx, r.position.y + 86.0, 150, 62), "ON " + str(Ships.LIST[other].name), Color(0.5, 0.54, 0.64), {"size": 15, "disabled": true})
		else:
			var sure := confirm_uid == uid
			c.button("g_scrap_%d" % uid, Rect2(bx, r.position.y + 86.0, 150, 62), "SURE?" if sure else "SCRAP", UI.RED if sure else UI.ORANGE, {"size": 19, "sub": "+%d parts" % Gear.scrap_value(item), "sound": ""})
	return y + h + 10.0

## A small triangle and number showing whether this beats what you wear.
func _delta_arrow(c: UILayer, at: Vector2, diff: int) -> void:
	var up := diff >= 0
	var col: Color = UI.MINT if up else UI.RED
	var tip := at + Vector2(-70, -6 if up else 6)
	var pts := PackedVector2Array([tip + Vector2(0, -10 if up else 10), tip + Vector2(-9, 7 if up else -7), tip + Vector2(9, 7 if up else -7)])
	c.draw_colored_polygon(pts, col)
	UI.text(c, "%+d" % diff, at + Vector2(0, 2), 19, col, true, UI.RIGHT)
