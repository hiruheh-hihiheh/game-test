class_name MenuProfile
extends RefCounted
## The Pilot Profile: a service record. Level and XP, what the next level pays, the permanent bonuses,
## the road ahead, career statistics and the ship you fly.
##
## Nothing here is calculated a second time. Levels and XP come from Pilot.level_of, rewards and bonus
## gains from Pilot.reward_for and Pilot.bonus_gain (the same functions Pilot.grant pays from), the
## bonuses from Pilot.dmg_bonus and Pilot.shield_bonus (the same ones combat applies), mastery from
## Save and Ships, and the career figures from Meta.stat and Save. Opening the page pays nothing.

const CARD_GAP := 14.0
const SLOT_ART := ["weapon", "reactor", "plating"]

var m
## Tests switch this on to read back every string the page painted.
var capture_text := false
var shown: Array = []
var _veil := 0

func _init(hub) -> void:
	m = hub

func on_ui(id: String) -> void:
	if id == "profile_hangar":
		m.go("hangar")

# ---------- What the page knows ----------

## Everything the page displays, from the real save.
func summary() -> Dictionary:
	var info: Dictionary = Pilot.level_of(Save.pilot_xp)
	var lv := int(info.level)
	var into := int(info.into)
	var need := int(info.need)
	var next := lv + 1
	var ship_id: String = Save.ship
	var mastery := Save.ship_mastery(ship_id)
	var mastery_xp := Save.ship_xp(ship_id)
	var from_xp: int = Ships.xp_for(mastery - 1) if mastery > 1 else 0
	var to_xp: int = Ships.xp_for(mastery)
	var ratio := float(into) / float(need)
	var cap := Pilot.BONUS_CAP
	return {
		"level": lv, "into": into, "need": need, "remaining": need - into, "ratio": ratio,
		"percent": int(ratio * 100.0), "total_xp": Save.pilot_xp,
		"next_level": next, "reward": Pilot.reward_for(next), "gain": Pilot.bonus_gain(next),
		"dmg_pct": (Pilot.dmg_bonus() - 1.0) * 100.0, "dmg_cap_pct": (Pilot.dmg_bonus_at(cap) - 1.0) * 100.0,
		"shield": Pilot.shield_bonus(), "shield_cap": Pilot.shield_bonus_at(cap),
		"bonus_ratio": float(mini(lv, cap)) / float(cap), "bonuses_maxed": lv >= cap,
		"ship_id": ship_id, "ship": Ships.LIST[ship_id], "mastery": mastery, "mastery_xp": mastery_xp,
		"mastery_ratio": 1.0 if mastery >= Ships.MAX_MASTERY else float(mastery_xp - from_xp) / float(to_xp - from_xp),
		"mastery_next": str(Ships.MASTERY[mastery + 1].text) if mastery < Ships.MAX_MASTERY else "",
		"milestones": milestones(lv),
		"stats": stats(),
	}

## Upcoming milestones relative to `lv`: the next level, the next three gear drops after it, and level 100.
## Anything already reached is not offered as upcoming.
func milestones(lv: int) -> Array:
	var out: Array = []
	var next := lv + 1
	var pay: Dictionary = Pilot.reward_for(next)
	var gain: Dictionary = Pilot.bonus_gain(next)
	out.append({"kind": "next", "level": next, "away": 1, "rarity": int(pay.gear), "salvage": int(pay.salvage), "parts": int(pay.parts), "maxed": bool(gain.maxed), "caps": next == Pilot.BONUS_CAP})
	var cursor := next
	for i in range(3):
		var g: Dictionary = Pilot.next_gear_level(cursor)
		cursor = int(g.level)
		out.append({"kind": "gear", "level": cursor, "away": cursor - lv, "rarity": int(g.rarity), "caps": cursor == Pilot.BONUS_CAP})
	# The cap is its own milestone only while it is more than one level away and no gear drop already sits on it.
	var cap_listed := next >= Pilot.BONUS_CAP
	for item in out:
		if int(item.level) == Pilot.BONUS_CAP:
			cap_listed = true
	if not cap_listed:
		out.append({"kind": "cap", "level": Pilot.BONUS_CAP, "away": Pilot.BONUS_CAP - lv})
	return out

## Career figures that really are saved, grouped for the page.
func stats() -> Array:
	return [
		{"name": "COMBAT RECORD", "items": [
			["ENEMIES DEFEATED", UI.num(Meta.stat("kill"))], ["BOSSES DEFEATED", UI.num(Meta.stat("boss"))], ["HIGHEST COMBO", UI.num(Meta.stat("best_combo"))]]},
		{"name": "CAMPAIGN PROGRESS", "items": [
			["LEVEL CLEARS", UI.num(Meta.stat("clear"))], ["STARS", "%d / %d" % [Save.total_stars(), Levels.LEVEL_COUNT * 3]], ["BEST RIFT FLOOR", UI.num(Save.endless_best_wave)]]},
		{"name": "COLLECTION", "items": [
			["GEAR FOUND", UI.num(Meta.stat("gear_found"))], ["LEGENDARIES", UI.num(Meta.stat("legendary"))], ["SHIPS OWNED", "%d / %d" % [Save.owned_ships.size(), Ships.ORDER.size()]]]},
	]

func achievements() -> Array:
	return [Save.achievements.size(), Goals.ACHIEVEMENTS.size()]

# ---------- Painting ----------

func _t(c: UILayer, value: String, pos: Vector2, size: int, color: Color, bold := false, align := UI.LEFT) -> void:
	if capture_text:
		shown.append(value)
	UI.text(c, value, pos, size, color, bold, align)

func _ft(c: UILayer, value: String, pos: Vector2, size: int, min_size: int, max_w: float, color: Color, bold := false) -> void:
	if capture_text:
		shown.append(value)
	UI.fit_text(c, value, pos, size, min_size, max_w, color, bold)

func _veiled(c: UILayer, r: Rect2) -> void:
	UI.enter_veil(c, r, float(m.screen_t), mini(_veil, 9))
	_veil += 1

func paint(c: UILayer) -> void:
	if capture_text:
		shown.clear()
	_veil = 0
	var d := summary()
	var W: float = m.W
	var w := minf(W - 40.0, 680.0)
	var x := (W - w) * 0.5
	var y: float = float(m.top) + 190.0 - c.scroll
	y = _hero(c, d, x, y, w)
	y = _xp(c, d, x, y, w)
	y = _rewards(c, d, x, y, w)
	y = _roadmap(c, d, x, y, w)
	y = _attributes(c, d, x, y, w)
	y = _career(c, d, x, y, w)
	y = _ship_card(c, d, x, y, w)
	c.scroll_max = maxf(0.0, y + c.scroll - float(m.H) + float(m.bottom) + 24.0)
	m.header(c, "PILOT PROFILE", UI.CYAN)

func _section(c: UILayer, x: float, y: float, w: float, text: String, accent: Color = UI.CYAN) -> float:
	c.draw_rect(Rect2(x + 2.0, y + 14.0, 4.0, 22.0), Color(accent, 0.9))
	if capture_text:
		shown.append(text)
	UI.outlined(c, text, Vector2(x + 18.0, y + 32.0), 21, accent, true)
	UI.rule(c, Vector2(x + 30.0 + UI.width_of(text, 21, true), y + 24.0), Vector2(x + w, y + 24.0), accent, 0.45)
	return y + 50.0

func _octagon(r: float, cut: float) -> PackedVector2Array:
	var k := r * cut
	return PackedVector2Array([Vector2(-r + k, -r), Vector2(r - k, -r), Vector2(r, -r + k), Vector2(r, r - k), Vector2(r - k, r), Vector2(-r + k, r), Vector2(-r, r - k), Vector2(-r, -r + k)])

## The big level emblem: a glass octagon with slow orbiting arcs, the rank wings on top, the level as the focus.
func _emblem(c: UILayer, center: Vector2, r: float, level: int) -> void:
	UI.glow(c, center, r * 2.0, Color(UI.CYAN, 0.28))
	c.draw_set_transform(center, 0.0, Vector2.ONE)
	var spin := fmod(UI.clock() * 0.25, 1.0) * TAU if UI.motion_ok() else 0.6
	for k in range(3):
		var a := spin + float(k) * TAU / 3.0
		c.draw_arc(Vector2.ZERO, r + 14.0, a, a + 1.25, 20, Color(UI.CYAN, 0.55), 2.5, true)
		c.draw_arc(Vector2.ZERO, r + 24.0, -a, -a + 0.7, 14, Color(UI.MINT, 0.35), 2.0, true)
	var shape := _octagon(r, 0.34)
	var top_c := UI.CYAN.darkened(0.45)
	var bottom_c := UI.CYAN.darkened(0.8)
	var fills := PackedColorArray()
	for p in shape:
		fills.append(top_c.lerp(bottom_c, clampf((p.y + r) / (r * 2.0), 0.0, 1.0)))
	c.draw_polygon(shape, fills)
	var rim := shape.duplicate()
	rim.append(shape[0])
	c.draw_polyline(rim, Color(UI.CYAN, 0.95), 2.5, true)
	var inner := _octagon(r - 9.0, 0.34)
	inner.append(inner[0])
	c.draw_polyline(inner, Color(UI.CYAN, 0.3), 1.0, true)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	UIArt.draw(c, "rank", center + Vector2(0, -r - 10.0), 74.0, {"animate": false})
	var digits := str(level).length()
	var size := 84 if digits <= 2 else (66 if digits == 3 else 50)
	if capture_text:
		shown.append(str(level))
	UI.glow_text(c, str(level), center + Vector2(0, float(size) * 0.34 + 4.0), size, UI.WHITE, UI.CYAN)
	_t(c, "LEVEL", center + Vector2(0, -r * 0.42), 16, UI.TEXT_DIM, true, UI.CENTER)

func _hero(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	var h := 286.0
	var r := Rect2(x, y, w, h)
	UI.glass(c, r, UI.Kind.SELECTED, UI.CYAN, {"chamfer": 20})
	var center := r.position + Vector2(118.0, 164.0)
	_emblem(c, center, 74.0, int(d.level))
	var tx := r.position.x + 238.0
	var room := w - 238.0 - 22.0
	_t(c, "SERVICE RECORD", Vector2(tx, r.position.y + 40.0), 17, UI.TEXT_DIM, true)
	_t(c, "TOTAL PILOT XP", Vector2(tx, r.position.y + 76.0), 17, UI.CYAN, true)
	_ft(c, UI.num(int(d.total_xp)), Vector2(tx, r.position.y + 118.0), 44, 24, room, UI.WHITE, true)
	UI.rule(c, Vector2(tx, r.position.y + 140.0), Vector2(r.end.x - 22.0, r.position.y + 140.0), UI.CYAN, 0.6)
	# The ship being flown.
	var ship: Dictionary = d.ship
	var art_at := Vector2(tx + 46.0, r.position.y + 206.0)
	UI.glow(c, art_at, 56.0, Color(UI.MINT, 0.22))
	UI.icon(c, Ships.ART[d.ship_id], art_at, 92.0)
	var nx := tx + 108.0
	_ft(c, str(ship.name), Vector2(nx, r.position.y + 190.0), 28, 18, room - 108.0, UI.WHITE, true)
	_ft(c, str(ship.role), Vector2(nx, r.position.y + 218.0), 18, 12, room - 108.0, UI.GOLD, true)
	_t(c, "MASTERY %d" % int(d.mastery), Vector2(nx, r.position.y + 246.0), 18, UI.MINT, true)
	_veiled(c, r)
	return y + h + CARD_GAP

func _xp(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, w, "XP PROGRESSION")
	var h := 236.0
	var r := Rect2(x, y, w, h)
	UI.glass(c, r, UI.Kind.CARD, UI.CYAN, {"chamfer": 18})
	_t(c, "PILOT LEVEL %d" % int(d.level), r.position + Vector2(24.0, 44.0), 30, UI.WHITE, true)
	_t(c, "%s / %s XP" % [UI.num(int(d.into)), UI.num(int(d.need))], r.position + Vector2(24.0, 82.0), 24, UI.MINT, true)
	# The bar fills up when the page opens, and a soft glint travels along it.
	var grow := 1.0
	if UI.motion_ok():
		grow = UI.ease_out(clampf((float(m.screen_t) - 0.12) / 0.9, 0.0, 1.0))
	var bar := Rect2(r.position + Vector2(24.0, 104.0), Vector2(w - 48.0, 36.0))
	UI.bar(c, bar, float(d.ratio) * grow, UI.CYAN)
	if UI.flash_ok() and float(d.ratio) > 0.02:
		var lit := Rect2(bar.position, Vector2(bar.size.x * float(d.ratio) * grow, bar.size.y))
		UI.shine(c, lit, fmod(UI.clock() * 0.4, 2.2), Color(1, 1, 1))
	_t(c, "%d%%" % int(d.percent), bar.get_center() + Vector2(0, 8.0), 21, UI.WHITE, true, UI.CENTER)
	_t(c, "%s XP TO NEXT LEVEL" % UI.num(int(d.remaining)), r.position + Vector2(24.0, 178.0), 24, UI.GOLD, true)
	_t(c, "LIFETIME XP: %s" % UI.num(int(d.total_xp)), r.position + Vector2(24.0, 210.0), 18, UI.TEXT_DIM, false)
	_t(c, "NO LEVEL CAP", r.end - Vector2(24.0, 24.0), 16, UI.TEXT_DIM, true, UI.RIGHT)
	_veiled(c, r)
	return y + h + CARD_GAP

## One small reward tile: an icon, a big number and a short description.
func _tile(c: UILayer, r: Rect2, icon, value: String, label: String, accent: Color, maxed := false) -> void:
	UI.glass(c, r, UI.Kind.CARD, accent if not maxed else UI.MINT, {"chamfer": 14})
	if icon != null:
		UI.icon(c, icon, r.position + Vector2(46.0, r.size.y * 0.5), 56.0)
	var tx := r.position.x + 92.0
	_ft(c, value, Vector2(tx, r.position.y + 46.0), 32, 20, r.size.x - 92.0 - 14.0, UI.MINT if maxed else UI.WHITE, true)
	_ft(c, label, Vector2(tx, r.position.y + 76.0), 16, 11, r.size.x - 92.0 - 14.0, UI.TEXT_DIM, true)

func _rewards(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, w, "NEXT LEVEL REWARDS", UI.GOLD)
	var pay: Dictionary = d.reward
	var gain: Dictionary = d.gain
	var next := int(d.next_level)
	var gear := int(pay.gear)
	var tile_w := (w - CARD_GAP) * 0.5
	var tile_h := 100.0
	var head := Rect2(x, y, w, 50.0)
	UI.glass(c, head, UI.Kind.REWARD, UI.GOLD, {"chamfer": 14})
	_t(c, "NEXT LEVEL — LEVEL %d" % next, head.get_center() + Vector2(0, 9.0), 24, UI.GOLD, true, UI.CENTER)
	_veiled(c, head)
	y += head.size.y + 10.0
	var tiles: Array = [
		[m.SALVAGE_ART, "+%s" % UI.num(int(pay.salvage)), "SALVAGE, added to your balance", UI.GOLD, false],
		[Cards.ICONS["modules"], "+%s" % UI.num(int(pay.parts)), "PARTS, for upgrading gear", UI.CYAN, false],
	]
	if bool(gain.maxed):
		tiles.append([Cards.ICONS["beam"], "MAXED", "DAMAGE BONUS AT CAP", UI.MINT, true])
		tiles.append([Cards.ICONS["orb"], "MAXED", "SHIELD BONUS AT CAP", UI.MINT, true])
	else:
		tiles.append([Cards.ICONS["beam"], "+%.1f%%" % (float(gain.dmg) * 100.0), "DAMAGE BONUS, permanent", UI.ORANGE, false])
		tiles.append([Cards.ICONS["orb"], "+%.1f" % float(gain.shield), "SHIELD BONUS, permanent", UI.CYAN, false])
	for i in range(tiles.size()):
		var t: Array = tiles[i]
		var r := Rect2(x + float(i % 2) * (tile_w + CARD_GAP), y + float(i / 2) * (tile_h + 10.0), tile_w, tile_h)
		_tile(c, r, t[0], str(t[1]), str(t[2]), t[3], bool(t[4]))
		_veiled(c, r)
	y += 2.0 * tile_h + 10.0 + 10.0
	if gear >= 0:
		var rarity_name := str(Gear.RARITY_NAMES[gear]).to_upper()
		var color: Color = Gear.RARITY_COLORS[gear]
		var r2 := Rect2(x, y, w, 128.0)
		UI.glass(c, r2, UI.Kind.REWARD, color.lerp(UI.GOLD, 0.35), {"chamfer": 18, "alpha": 1.0})
		for k in range(3):
			UIArt.draw(c, SLOT_ART[k], r2.position + Vector2(52.0 + float(k) * 58.0, 64.0), 60.0)
		var gx := r2.position.x + 232.0
		_ft(c, "%s GEAR DROP" % rarity_name, Vector2(gx, r2.position.y + 54.0), 30, 18, r2.size.x - 232.0 - 16.0, color.lightened(0.25), true)
		_ft(c, "Guaranteed on level %d." % next, Vector2(gx, r2.position.y + 86.0), 20, 13, r2.size.x - 232.0 - 16.0, UI.WHITE)
		_ft(c, "Weapon, reactor or plating", Vector2(gx, r2.position.y + 110.0), 15, 11, r2.size.x - 232.0 - 16.0, UI.TEXT_DIM)
		UI.shine(c, r2, fmod(UI.clock() * 0.35, 2.4), UI.GOLD.lightened(0.4))
		_veiled(c, r2)
		y += r2.size.y + CARD_GAP
	return y

func _roadmap(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, w, "PILOT PROGRESSION ROADMAP")
	var list: Array = d.milestones
	var card_h := 92.0
	var gap := 10.0
	var rail_x := x + 22.0
	var top := y
	for i in range(list.size()):
		var ms: Dictionary = list[i]
		var r := Rect2(x + 52.0, y, w - 52.0, card_h)
		var title := ""
		var detail := ""
		var accent: Color = UI.CYAN
		match str(ms.kind):
			"next":
				title = "LEVEL %d  ·  NEXT LEVEL" % int(ms.level)
				var bits := ["+%s salvage" % UI.num(int(ms.salvage)), "+%s parts" % UI.num(int(ms.parts))]
				if bool(ms.maxed):
					bits.append("bonuses maxed")
				elif bool(ms.caps):
					bits.append("bonuses reach their cap")
				else:
					bits.append("bonuses grow")
				if int(ms.rarity) >= 0:
					bits.append("%s gear" % str(Gear.RARITY_NAMES[int(ms.rarity)]).to_lower())
				detail = ", ".join(bits)
				accent = UI.MINT
			"gear":
				var rarity := int(ms.rarity)
				title = "LEVEL %d  ·  %s GEAR" % [int(ms.level), str(Gear.RARITY_NAMES[rarity]).to_upper()]
				detail = "A guaranteed %s or better gear drop" % str(Gear.RARITY_NAMES[rarity]).to_lower()
				if bool(ms.get("caps", false)):
					detail += ". Bonuses reach their cap."
				accent = Gear.RARITY_COLORS[rarity]
			"cap":
				title = "LEVEL %d  ·  BONUSES MAXED" % int(ms.level)
				detail = "Damage +%.0f%% and shield +%.0f stop growing. XP never stops." % [float(d.dmg_cap_pct), float(d.shield_cap)]
				accent = UI.GOLD
		UI.glass(c, r, UI.Kind.CARD if i > 0 else UI.Kind.SELECTED, accent, {"chamfer": 14})
		# The rail: a node for each milestone, lit for the next one.
		var node := Vector2(rail_x, y + card_h * 0.5)
		c.draw_circle(node, 11.0, Color(accent.darkened(0.6), 0.95))
		c.draw_arc(node, 11.0, 0.0, TAU, 20, Color(accent, 0.95 if i == 0 else 0.6), 2.0, true)
		if i == 0 and UI.flash_ok():
			c.draw_arc(node, 14.0 + 5.0 * UI.breathe(2.0), 0.0, TAU, 24, Color(accent, 0.4), 1.5, true)
		_ft(c, title, r.position + Vector2(18.0, 34.0), 21, 14, r.size.x - 36.0 - 150.0, UI.WHITE, true)
		_ft(c, detail, r.position + Vector2(18.0, 62.0), 17, 11, r.size.x - 36.0, UI.TEXT_DIM)
		var state := "NEXT" if i == 0 else ("%d LEVELS AWAY" % int(ms.away))
		_t(c, state, Vector2(r.end.x - 16.0, r.position.y + 32.0), 15, accent if i == 0 else UI.TEXT_DIM, true, UI.RIGHT)
		_veiled(c, r)
		y += card_h + gap
	c.draw_line(Vector2(rail_x, top + card_h * 0.5), Vector2(rail_x, y - gap - card_h * 0.5), Color(UI.CYAN, 0.3), 2.0)
	if int(d.level) >= Pilot.BONUS_CAP:
		var done := Rect2(x + 52.0, y, w - 52.0, 72.0)
		UI.glass(c, done, UI.Kind.REWARD, UI.GOLD, {"chamfer": 14})
		c.draw_circle(Vector2(rail_x, y + 36.0), 11.0, Color(UI.GOLD, 0.95))
		_t(c, "LEVEL %d  ·  BONUSES MAXED  ·  COMPLETE" % Pilot.BONUS_CAP, done.position + Vector2(18.0, 32.0), 19, UI.GOLD, true)
		_ft(c, "Your damage and shield bonuses are at their cap. XP and rewards keep coming.", done.position + Vector2(18.0, 58.0), 16, 11, done.size.x - 36.0, UI.TEXT_DIM)
		_veiled(c, done)
		y += 72.0 + gap
	_ft(c, "XP has no level cap. Only the damage and shield bonuses stop growing at level %d." % Pilot.BONUS_CAP, Vector2(x + 4.0, y + 22.0), 16, 11, w - 8.0, UI.TEXT_DIM)
	return y + 40.0

func _attribute(c: UILayer, r: Rect2, label: String, icon, value: String, cap_text: String, ratio: float, accent: Color, maxed: bool, progress_text: String) -> void:
	UI.glass(c, r, UI.Kind.CARD, accent, {"chamfer": 16})
	UI.icon(c, icon, r.position + Vector2(40.0, 44.0), 50.0)
	_ft(c, label, r.position + Vector2(76.0, 36.0), 16, 11, r.size.x - 92.0, UI.TEXT_DIM, true)
	_ft(c, value, r.position + Vector2(76.0, 80.0), 40, 22, r.size.x - 92.0, accent.lightened(0.25), true)
	UI.bar(c, Rect2(r.position + Vector2(18.0, 100.0), Vector2(r.size.x - 36.0, 18.0)), ratio, accent)
	_ft(c, progress_text, r.position + Vector2(18.0, 144.0), 16, 11, r.size.x - 36.0 - (80.0 if maxed else 0.0), UI.WHITE, true)
	_ft(c, cap_text, r.position + Vector2(18.0, 168.0), 15, 11, r.size.x - 36.0, UI.TEXT_DIM)
	if maxed:
		UI.chip(c, Vector2(r.end.x - 18.0, r.position.y + 142.0), "MAXED", 14, UI.MINT, UI.RIGHT)

func _attributes(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, w, "COMBAT ATTRIBUTES", UI.ORANGE)
	var cw := (w - CARD_GAP) * 0.5
	var lv := int(d.level)
	var cap := Pilot.BONUS_CAP
	var progress := "LEVEL %d / %d" % [mini(lv, cap), cap]
	var r1 := Rect2(x, y, cw, 188.0)
	var r2 := Rect2(x + cw + CARD_GAP, y, cw, 188.0)
	_attribute(c, r1, "DAMAGE ENHANCEMENT", Cards.ICONS["beam"], "+%.1f%%" % float(d.dmg_pct), "CAP +%.1f%% AT LEVEL %d" % [float(d.dmg_cap_pct), cap], float(d.bonus_ratio), UI.ORANGE, bool(d.bonuses_maxed), progress)
	_attribute(c, r2, "SHIELD ENHANCEMENT", Cards.ICONS["orb"], "+%.1f" % float(d.shield), "CAP +%.1f AT LEVEL %d" % [float(d.shield_cap), cap], float(d.bonus_ratio), UI.CYAN, bool(d.bonuses_maxed), progress)
	_veiled(c, r1)
	_veiled(c, r2)
	y += 188.0 + 10.0
	_ft(c, "Pilot bonuses are separate from ship stats and Hangar upgrades, and apply in every flight.", Vector2(x + 4.0, y + 18.0), 15, 11, w - 8.0, UI.TEXT_DIM)
	return y + 40.0

func _career(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, w, "CAREER STATISTICS", UI.MINT)
	var cols := 3
	var tw := (w - CARD_GAP * 2.0) / 3.0
	for group in d.stats:
		_t(c, str(group.name), Vector2(x + 4.0, y + 18.0), 16, UI.TEXT_DIM, true)
		y += 28.0
		for i in range(cols):
			var item: Array = group.items[i]
			var r := Rect2(x + float(i) * (tw + CARD_GAP), y, tw, 86.0)
			UI.glass(c, r, UI.Kind.CARD, UI.MINT, {"chamfer": 12})
			_ft(c, str(item[1]), r.position + Vector2(14.0, 44.0), 30, 16, tw - 28.0, UI.WHITE, true)
			_ft(c, str(item[0]), r.position + Vector2(14.0, 70.0), 14, 10, tw - 28.0, UI.TEXT_DIM, true)
			_veiled(c, r)
		y += 86.0 + 14.0
	var ach := achievements()
	_t(c, "ACHIEVEMENTS", Vector2(x + 4.0, y + 18.0), 16, UI.TEXT_DIM, true)
	y += 28.0
	var ra := Rect2(x, y, w, 96.0)
	UI.glass(c, ra, UI.Kind.CARD, UI.GOLD, {"chamfer": 14})
	UI.star(c, ra.position + Vector2(38.0, 34.0), 18.0, UI.GOLD)
	_t(c, "%d / %d" % [int(ach[0]), int(ach[1])], ra.position + Vector2(70.0, 44.0), 30, UI.WHITE, true)
	_t(c, "UNLOCKED", ra.end - Vector2(18.0, 54.0), 16, UI.TEXT_DIM, true, UI.RIGHT)
	UI.bar(c, Rect2(ra.position + Vector2(18.0, 62.0), Vector2(w - 36.0, 18.0)), float(ach[0]) / maxf(1.0, float(ach[1])), UI.GOLD)
	_veiled(c, ra)
	return y + 96.0 + 20.0

func _ship_card(c: UILayer, d: Dictionary, x: float, y: float, w: float) -> float:
	y = _section(c, x, y, w, "CURRENT SHIP", UI.MINT)
	var h := 196.0
	var r := Rect2(x, y, w, h)
	var ship: Dictionary = d.ship
	UI.glass(c, r, UI.Kind.SELECTED, UI.MINT, {"chamfer": 18})
	var art_at := r.position + Vector2(78.0, 92.0)
	UI.glow(c, art_at, 80.0, Color(UI.MINT, 0.25))
	UI.icon(c, Ships.ART[d.ship_id], art_at, 124.0)
	var tx := r.position.x + 164.0
	var room := w - 164.0 - 20.0
	_ft(c, str(ship.name), Vector2(tx, r.position.y + 42.0), 30, 18, room, UI.WHITE, true)
	_ft(c, str(ship.role), Vector2(tx, r.position.y + 68.0), 18, 12, room, UI.GOLD, true)
	var mastery := int(d.mastery)
	_t(c, "MASTERY %d / %d" % [mastery, Ships.MAX_MASTERY], Vector2(tx, r.position.y + 100.0), 20, UI.MINT, true)
	UI.bar(c, Rect2(tx, r.position.y + 110.0, minf(room, 300.0), 14.0), float(d.mastery_ratio), UI.MINT)
	var line := "MAX MASTERY  ·  %s ship XP" % UI.num(int(d.mastery_xp)) if mastery >= Ships.MAX_MASTERY else "%s ship XP  ·  NEXT: %s" % [UI.num(int(d.mastery_xp)), str(d.mastery_next)]
	_ft(c, line, Vector2(tx, r.position.y + 146.0), 16, 11, room - 214.0, UI.TEXT_DIM)
	c.button("profile_hangar", Rect2(r.end.x - 206.0, r.end.y - 62.0, 190.0, 50.0), "OPEN HANGAR", UI.MINT, {"size": 17})
	_veiled(c, r)
	return y + h + 20.0
