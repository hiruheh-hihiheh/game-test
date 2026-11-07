class_name Expedition
extends RefCounted
## Roguelite mode. Pick a sector, then choose a path through a branching map.
## Hull and modules carry between nodes, so every choice shapes the rest of the run.

const LAYERS := 7

const NODE_INFO := {
	"battle": {"name": "BATTLE", "desc": "A standard fight. Earn a module.", "color": Color(0.25, 0.90, 1.0)},
	"elite": {"name": "ELITE", "desc": "A dangerous champion. Epic rewards.", "color": Color(1.0, 0.27, 0.66)},
	"depot": {"name": "DEPOT", "desc": "Spend run salvage on repairs and modules.", "color": Color(0.32, 1.0, 0.72)},
	"signal": {"name": "SIGNAL", "desc": "Something is out there. Risk or reward.", "color": Color(1.0, 0.82, 0.32)},
	"boss": {"name": "BOSS", "desc": "The sector's master.", "color": Color(1.0, 0.27, 0.30)},
}

const SIGNALS := [
	{"title": "DERELICT BEACON", "text": "A dead ship is still calling for help. Its reactor is unstable.",
		"a": {"label": "Strip it (lose 1 hull, gain a rare module)", "hull": -1, "card_rarity": 1},
		"b": {"label": "Leave it (gain 30 salvage)", "salvage": 30}},
	{"title": "SMUGGLER CACHE", "text": "A locked crate drifts past. The lock looks rigged.",
		"a": {"label": "Force it (70% for 120 salvage, or lose 1 hull)", "gamble": 0.7, "salvage": 120, "hull": -1},
		"b": {"label": "Tag it for later (gain 40 salvage)", "salvage": 40}},
	{"title": "FIELD MEDIC", "text": "A hauler offers repairs in exchange for what you are carrying.",
		"a": {"label": "Trade 60 salvage for 2 hull", "cost": 60, "hull": 2},
		"b": {"label": "Decline politely (gain a common module)", "card_rarity": 0}},
	{"title": "STRANGE SIGNAL", "text": "The transmission is a blueprint for something that shouldn't exist.",
		"a": {"label": "Install it (gain an epic module, lose 1 hull)", "card_rarity": 2, "hull": -1},
		"b": {"label": "Erase it (repair 1 hull)", "hull": 1}},
]

static func start(sector: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var run_seed := rng.randi()
	var layers: Array = []
	for layer in range(LAYERS):
		var row: Array = []
		var width := 1 if layer == 0 or layer == LAYERS - 1 else (2 if layer % 2 == 1 else 3)
		for i in range(width):
			row.append(_node(rng, layer, run_seed + layer * 31 + i * 7))
		layers.append(row)
	Save.expedition = {
		"active": true, "sector": sector, "layers": layers, "layer": 0, "from": 0, "salvage": 40,
		"hull": -1, "cards": {}, "score": 0, "current": {}, "seed": run_seed, "pending_card": false,
	}
	Save.save_data()

static func _node(rng: RandomNumberGenerator, layer: int, node_seed: int) -> Dictionary:
	var type := "battle"
	if layer == LAYERS - 1:
		type = "boss"
	elif layer > 0:
		var roll := rng.randf()
		if roll < 0.2:
			type = "elite"
		elif roll < 0.38:
			type = "depot"
		elif roll < 0.6:
			type = "signal"
	return {"type": type, "tier": layer + 1, "seed": node_seed}

static func active() -> bool:
	return bool(Save.expedition.get("active", false))

static func reachable(index: int) -> bool:
	var run: Dictionary = Save.expedition
	var row: Array = run.layers[int(run.layer)]
	if int(run.layer) == 0:
		return true
	var prev: Array = run.layers[int(run.layer) - 1]
	# Nodes connect to their nearest neighbours in the next layer.
	var from := float(run.from) / maxf(1.0, float(prev.size() - 1))
	var to := float(index) / maxf(1.0, float(row.size() - 1))
	return absf(from - to) <= 0.55 or prev.size() == 1 or row.size() == 1

static func enter_node(index: int) -> String:
	var run: Dictionary = Save.expedition
	var node: Dictionary = run.layers[int(run.layer)][index]
	run.current = node
	run.from = index
	Save.save_data()
	return str(node.type)

## Moves past a non-combat node.
static func advance() -> void:
	var run: Dictionary = Save.expedition
	run.layer = int(run.layer) + 1
	run.current = {}
	Save.save_data()

static func on_node_cleared(g) -> void:
	var run: Dictionary = Save.expedition
	run.hull = g.hull
	run.cards = g.held.duplicate()
	run.score = int(run.score) + int(g.score)
	run.salvage = int(run.salvage) + int(g.run_salvage) + int(g.level.reward)
	if str(run.current.get("type", "")) == "boss":
		_won(g)
		return
	run.layer = int(run.layer) + 1
	run.pending_card = true
	run.current = {}
	Save.save_data()

static func _won(g) -> void:
	var run: Dictionary = Save.expedition
	var sector: int = run.sector
	Meta.count("expedition_win")
	Meta.unique("expedition_unique", sector)
	Save.expedition_wins += 1
	var pay := 300 + sector * 120
	Save.salvage += pay
	g.rewards.append({"title": "EXPEDITION COMPLETE", "detail": "+%d salvage" % pay})
	Save.expedition = {}
	Save.save_data()

static func on_run_lost() -> void:
	var run: Dictionary = Save.expedition
	# Half of what the run was carrying makes it home.
	Save.salvage += int(run.get("salvage", 0)) / 2
	Save.expedition = {}
	Save.save_data()

static func abandon() -> void:
	on_run_lost()

static func pick_signal(run_seed: int) -> Dictionary:
	return SIGNALS[absi(run_seed) % SIGNALS.size()]

static func grant_card(rarity: int) -> String:
	var run: Dictionary = Save.expedition
	var pool: Array = []
	for id in Cards.LIST:
		var c: Dictionary = Cards.LIST[id]
		if int(c.rarity) == rarity and Cards.unlocked(id, Save.blueprints) and int(run.cards.get(id, 0)) < int(c.max) and id != "repair":
			pool.append(id)
	if pool.is_empty():
		return ""
	var id: String = pool[randi() % pool.size()]
	run.cards[id] = int(run.cards.get(id, 0)) + 1
	return id

static func apply_choice(choice: Dictionary) -> String:
	var run: Dictionary = Save.expedition
	var hull: int = int(run.hull)
	var max_hull: int = int(Ships.LIST[Save.ship].hull) + Save.upgrade_level("hull")
	if hull < 0:
		hull = max_hull
	var msg := ""
	if choice.has("gamble"):
		if randf() < float(choice.gamble):
			run.salvage = int(run.salvage) + int(choice.salvage)
			msg = "It paid off: +%d salvage" % int(choice.salvage)
		else:
			hull -= 1
			msg = "It was rigged: -1 hull"
	else:
		if choice.has("cost"):
			if int(run.salvage) < int(choice.cost):
				return "Not enough run salvage"
			run.salvage = int(run.salvage) - int(choice.cost)
		if choice.has("salvage"):
			run.salvage = int(run.salvage) + int(choice.salvage)
			msg = "+%d salvage" % int(choice.salvage)
		if choice.has("hull"):
			hull += int(choice.hull)
			msg = "%+d hull" % int(choice.hull)
		if choice.has("card_rarity"):
			var id := grant_card(int(choice.card_rarity))
			if not id.is_empty():
				msg += ("  " if not msg.is_empty() else "") + "Gained " + str(Cards.LIST[id].name)
	run.hull = clampi(hull, 1, max_hull)
	return msg

const DEPOT_REPAIR := 50
const DEPOT_MODULE := 90

static func depot_repair() -> bool:
	var run: Dictionary = Save.expedition
	var max_hull: int = int(Ships.LIST[Save.ship].hull) + Save.upgrade_level("hull")
	var hull: int = max_hull if int(run.hull) < 0 else int(run.hull)
	if int(run.salvage) < DEPOT_REPAIR or hull >= max_hull:
		return false
	run.salvage = int(run.salvage) - DEPOT_REPAIR
	run.hull = hull + 1
	Save.save_data()
	return true

static func depot_module() -> String:
	var run: Dictionary = Save.expedition
	if int(run.salvage) < DEPOT_MODULE:
		return ""
	var id := grant_card(1 if randf() < 0.7 else 2)
	if id.is_empty():
		return ""
	run.salvage = int(run.salvage) - DEPOT_MODULE
	Save.save_data()
	return id
