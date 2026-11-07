class_name DangerPicker
extends RefCounted
## The Danger Contracts section, shared by the briefing, the Expedition and the Ops screens:
## one illustrated card per contract, with its effect, its payout and why it is unavailable if it is.
## The picker holds the choice. The screen that owns it passes the current rules (ctx) every frame.

const CARD_H := 108.0

var chosen: Array = []
var note := ""
var context := "campaign"

func reset(for_context: String) -> void:
	chosen = []
	note = ""
	context = for_context

## Handles the picker's own button ids. Returns true if the id was one of them.
func on_ui(id: String, ctx: Dictionary) -> bool:
	if id == "danger_repeat":
		chosen = Danger.sanitize(Danger.recall(context), ctx)
		note = ""
		Audio.play("ui_click")
		return true
	if not id.begins_with("danger_"):
		return false
	var key := id.substr(7)
	if not Danger.has(key):
		return false
	if key in chosen:
		chosen.erase(key)
		note = ""
		Audio.play("ui_click")
		return true
	var why := Danger.blocked_reason(chosen, key, ctx)
	if not why.is_empty():
		note = why
		Audio.play("ui_deny")
		return true
	chosen.append(key)
	note = ""
	Audio.play("ui_buy", -4.0)
	return true

## Draws the section and returns the y below it.
func paint(c: UILayer, x: float, y: float, w: float, ctx: Dictionary) -> float:
	UI.text(c, "DANGER CONTRACTS", Vector2(x + 4.0, y + 20.0), 21, UI.MAGENTA, true)
	if not Danger.unlocked():
		UI.text(c, "Beat the first boss to unlock optional contracts", Vector2(x + 4.0, y + 52.0), 18, UI.TEXT_DIM)
		return y + 70.0
	UI.text(c, "Optional. Pays more. A loss costs nothing extra.", Vector2(x + 4.0, y + 50.0), 17, UI.TEXT_DIM)
	var last := Danger.recall(context)
	if chosen.is_empty() and not last.is_empty() and not Danger.sanitize(last, ctx).is_empty():
		c.button("danger_repeat", Rect2(x + w - 188.0, y + 2.0, 188, 48), "REPEAT LAST", UI.MAGENTA, {"size": 16})
	y += 66.0
	for id in Danger.ORDER:
		y = _card(c, id, x, y, w, ctx)
	if not chosen.is_empty():
		y = _summary(c, x, y, w)
	if not note.is_empty():
		UI.fit_text(c, note, Vector2(x + 4.0, y + 20.0), 18, 14, w - 8.0, UI.ORANGE)
		y += 30.0
	return y + 8.0

func _card(c: UILayer, id: String, x: float, y: float, w: float, ctx: Dictionary) -> float:
	var def: Dictionary = Danger.LIST[id]
	var r := Rect2(x, y, w, CARD_H - 8.0)
	var on := id in chosen
	var why := "" if on else Danger.blocked_reason(chosen, id, ctx)
	var locked := not why.is_empty()
	c.hit_area("danger_" + id, r)
	var edge := UI.MAGENTA
	UI.panel(c, r, Color(edge.darkened(0.7), 0.96) if on else Color(0.03, 0.05, 0.12, 0.9 if not locked else 0.6), Color(edge, 0.95 if on else (0.22 if locked else 0.4)), 12, 3 if on else 2, 8 if on else 0)
	UIArt.draw(c, str(def.art), r.position + Vector2(48, r.size.y * 0.5), 68.0, {"animate": on, "tint": Color.WHITE if not locked else Color(0.6, 0.66, 0.8, 0.45)})
	var tx := r.position.x + 98.0
	var right := r.end.x - 14.0
	# Heat: how much risk the contract adds, as bars.
	var heat_w := 3.0 * 12.0 + 2.0 * 3.0
	UI.pips(c, Vector2(right - heat_w, r.position.y + 14.0), 3, int(def.heat), UI.ORANGE if not locked else Color(0.5, 0.54, 0.64), Vector2(12, 6), 3.0)
	var name_w := right - heat_w - 12.0 - tx
	UI.fit_text(c, str(def.name), Vector2(tx, r.position.y + 30.0), 21, 15, name_w, UI.WHITE if not locked else UI.TEXT_DIM, true)
	UI.fit_text(c, str(def.desc), Vector2(tx, r.position.y + 54.0), 17, 13, right - tx, UI.TEXT_DIM)
	if locked:
		UI.fit_text(c, why, Vector2(tx, r.position.y + 82.0), 16, 12, right - tx, UI.ORANGE)
	else:
		UI.fit_text(c, " · ".join(Danger.reward_lines(id)), Vector2(tx, r.position.y + 82.0), 17, 12, right - tx - (92.0 if on else 0.0), UI.GOLD, true)
		if on:
			UI.text(c, "SELECTED", Vector2(right, r.position.y + 82.0), 15, UI.MAGENTA, true, UI.RIGHT)
	return y + CARD_H

func _summary(c: UILayer, x: float, y: float, w: float) -> float:
	var r := Rect2(x, y, w, 70.0)
	UI.panel(c, r, Color(0.2, 0.04, 0.12, 0.92), Color(UI.MAGENTA, 0.8), 12, 2)
	UI.fit_text(c, "ON A WIN: " + ", ".join(Danger.summary_lines(chosen)), r.position + Vector2(16, 30), 18, 12, w - 32.0, UI.GOLD, true)
	var pairs := " and " if chosen.size() > 1 else ""
	UI.fit_text(c, Danger.names(chosen) + (" pay 15% more together" if not pairs.is_empty() else ""), r.position + Vector2(16, 56), 15, 11, w - 32.0, UI.TEXT_DIM)
	return y + 80.0
