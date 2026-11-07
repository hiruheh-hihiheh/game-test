class_name CloudSave
extends RefCounted
## Cloud save: what is stored, how it is checked, and the interface a storage backend must offer.
##
## This file is pure data handling. It never touches the network. The game keeps a complete local save and
## treats the cloud as a backup it can restore from, so everything here is built to refuse bad data:
##   encode()    the whole progress dictionary (every key of Save.PROGRESS_KEYS) in a versioned, checksummed envelope
##   decode()    envelope, checksum, format and version checks, then validate_progress() on the content
##   validate_progress()  types, bounds and gear structure, so a damaged or hostile blob can never replace a save
## Settings (volume, interface size, accessibility) are device choices and are NOT part of the cloud save.
## Merging is deliberately absent: a lower balance may be a real purchase, so a restore replaces progress whole
## and a disagreement is put to the player (see Cloud).

const SNAPSHOT_NAME := "starfall_salvage_main"
const GAME_ID := "starfall_salvage"
const FORMAT := 1
## Play Games snapshots hold up to 3 MB. The game's save is a few tens of KB; this is a safety stop.
const MAX_BYTES := 2500000

## Where Google Play Games sign-in stands.
enum Auth { UNAVAILABLE, CHECKING, SIGNED_IN, SIGNED_OUT, ERROR }

## What the Account section of the Pilot Profile shows.
enum Status { GUEST, CONNECTING, CONNECTED, SYNCING, SYNCED, PENDING, OFFLINE, ERROR, CONFLICT, ACCOUNT }

## A place to keep the snapshot. Every call is asynchronous and answers through `done`, exactly once.
##
## check_account result:  {ok, account_id, kind, detail}   account_id is the signed-in player's stable id. An empty id
##   means the identity could not be established, and Cloud then does not sync.
## load_snapshot result:  {ok, found, bytes, kind, detail}
##   ok=false carries kind: "offline", "timeout", "auth", "unavailable", "conflict" or "error".
##   found=false with ok=true means the cloud holds nothing yet (a verified empty answer).
## save_snapshot result:  {ok, kind, detail}
## A "conflict" failure (either call) also carries {origin: "SAVE"|"LOAD", candidates: [{role, bytes}]}: the versions
## the service reported, so Cloud can keep them on the device. No backend here resolves a conflict itself.
class Backend:
	signal auth_changed
	var auth := CloudSave.Auth.UNAVAILABLE
	## Why the state is what it is, in plain words, when that helps the player ("" otherwise).
	var auth_detail := ""
	## The last player id this backend confirmed. Cloud never stores it, only a one-way hash.
	var account_id := ""

	func label() -> String:
		return "No cloud service"

	## True when this build can talk to a cloud service at all.
	func available() -> bool:
		return false

	## Starts the asynchronous sign-in check. `host` is a node the backend may add children to (they stay for the session).
	func start(_host: Node) -> void:
		pass

	## Asks again after a failure or a refusal.
	func retry_auth() -> void:
		pass

	## Called when a request ran out of time, or the account changed. Pending callbacks are dropped and a late answer
	## from the service must be ignored from here on.
	func abort() -> void:
		pass

	## Confirms which player is signed in right now.
	func check_account(done: Callable) -> void:
		done.call_deferred({"ok": account_id != "", "account_id": account_id, "kind": "identity", "detail": "no account"})

	func load_snapshot(_snapshot_name: String, done: Callable) -> void:
		done.call_deferred({"ok": false, "found": false, "kind": "unavailable", "detail": "no cloud service in this build"})

	func save_snapshot(_snapshot_name: String, _description: String, _bytes: PackedByteArray, _progress: int, done: Callable) -> void:
		done.call_deferred({"ok": false, "kind": "unavailable", "detail": "no cloud service in this build"})

	func set_auth(state: int, detail := "") -> void:
		auth_detail = detail
		if state != auth:
			auth = state
			auth_changed.emit()

## The backend for this build: Google Play Games on Android when the plugin is installed, otherwise none.
## A desktop build, or an Android build without the plugin, plays as a local guest.
static func make_backend() -> Backend:
	if OS.get_name() == "Android":
		# Loaded by path so the game also runs when the plugin, or this adapter, is absent.
		var script = load("res://src/meta/cloud_play_games.gd")
		if script != null:
			var candidate = script.new()
			if candidate is Backend and candidate.available():
				return candidate
	return Backend.new()

# ---------- Encoding ----------

static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

## The whole progress dictionary as one blob: a small JSON envelope (so it is readable as plain text and a damaged
## copy never reaches the engine's binary decoder) around the progress in variant encoding, which keeps integer
## keys, nested dictionaries and every number type exactly, as JSON would not. The checksum covers the payload.
static func encode(progress: Dictionary) -> PackedByteArray:
	var payload := var_to_bytes(progress)
	return JSON.stringify({
		"format": FORMAT, "game": GAME_ID, "save_version": int(progress.get("version", Save.VERSION)),
		"saved_at": int(Time.get_unix_time_from_system()), "checksum": _sha256(payload), "payload": Marshalls.raw_to_base64(payload),
	}).to_utf8_buffer()

## Opens a blob and checks it. Result: {ok, code, error, data, saved_at, errors}.
## code is "empty", "too_large", "malformed", "game", "newer", "checksum" or "invalid" when ok is false.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var fail := func(code: String, text: String, errors := []) -> Dictionary:
		return {"ok": false, "code": code, "error": text, "data": {}, "saved_at": 0, "errors": errors}
	if bytes.is_empty():
		return fail.call("empty", "The cloud save is empty")
	if bytes.size() > MAX_BYTES:
		return fail.call("too_large", "The cloud save is too large")
	# The envelope is plain ASCII, so anything else is damage. Checking first keeps the engine from logging errors.
	for b in bytes:
		if b > 127:
			return fail.call("malformed", "The cloud save could not be read")
	var json := JSON.new()
	if json.parse(bytes.get_string_from_ascii()) != OK or not json.data is Dictionary:
		return fail.call("malformed", "The cloud save could not be read")
	var env: Dictionary = json.data
	if not env.get("format") is float or not env.get("payload") is String or not env.get("checksum") is String:
		return fail.call("malformed", "The cloud save is damaged")
	if int(env.format) > FORMAT:
		return fail.call("newer", "The cloud save was written by a newer version of the game")
	if int(env.format) < 1:
		return fail.call("malformed", "The cloud save is damaged")
	if str(env.get("game", "")) != GAME_ID:
		return fail.call("game", "The cloud save belongs to a different game")
	var payload := Marshalls.base64_to_raw(str(env.payload))
	if payload.is_empty() or _sha256(payload) != str(env.checksum):
		return fail.call("checksum", "The cloud save failed its integrity check")
	# Only a payload whose checksum matches is read. No objects are ever decoded.
	var data = bytes_to_var(payload)
	if not data is Dictionary:
		return fail.call("malformed", "The cloud save content is damaged")
	if int((data as Dictionary).get("version", 0)) > Save.VERSION:
		return fail.call("newer", "The cloud save was written by a newer version of the game")
	var migrated := migrate(data)
	var errors := validate_progress(migrated)
	if not errors.is_empty():
		return fail.call("invalid", "The cloud save has invalid content", errors)
	return {"ok": true, "code": "", "error": "", "data": migrated, "saved_at": int(env.get("saved_at", 0)), "errors": []}

## Brings an older payload up to the current shape. Keys it lacks are filled with a new player's values when it is
## restored (Save.restore_progress resets first), so nothing needs inventing here. Add a step per version bump.
static func migrate(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var version := int(out.get("version", 1))
	# Version 1 -> 2 needed no changes to the progress dictionary.
	out["version"] = maxi(version, 1)
	return out

# ---------- Validation ----------

static func _is_int(v) -> bool:
	return v is int

static func _is_number(v) -> bool:
	return v is int or v is float

## Everything wrong with a progress dictionary, in plain words. Empty means it is safe to restore.
static func validate_progress(d: Dictionary) -> Array:
	var errors: Array = []
	var version = d.get("version", null)
	if not version is int or int(version) < 1 or int(version) > Save.VERSION:
		errors.append("unsupported save version")
	for key in ["unlocked", "salvage", "star_mask", "upgrades", "ship", "owned_ships"]:
		if not d.has(key):
			errors.append("missing " + key)
	if not errors.is_empty():
		return errors
	var defaults: Dictionary = Save._defaults
	for key in Save.PROGRESS_KEYS:
		if not d.has(key) or not defaults.has(key):
			continue
		var want: int = typeof(defaults[key])
		var got: int = typeof(d[key])
		var ok := got == want or (want == TYPE_FLOAT and got == TYPE_INT)
		if not ok:
			errors.append("%s has the wrong type" % key)
	if not errors.is_empty():
		return errors
	var bounded := {"salvage": 2000000000, "parts": 2000000000, "best_score": 2000000000, "endless_best_wave": 100000, "reroll_tokens": 1000000, "expedition_wins": 1000000}
	for key in bounded:
		if d.has(key) and (int(d[key]) < 0 or int(d[key]) > int(bounded[key])):
			errors.append("%s is out of range" % key)
	if int(d.unlocked) < 1 or int(d.unlocked) > Levels.LEVEL_COUNT:
		errors.append("unlocked is out of range")
	if int(d.get("pilot_xp", 0)) < 0 or int(d.get("pilot_xp", 0)) > 1000000000000:
		errors.append("pilot_xp is out of range")
	if int(d.get("tier_unlocked", 0)) < 0 or int(d.get("tier_unlocked", 0)) > Tiers.MAX_TIER:
		errors.append("tier_unlocked is out of range")
	if not str(d.ship) in Ships.LIST:
		errors.append("unknown ship")
	for id in d.owned_ships:
		if not id is String or not str(id) in Ships.LIST:
			errors.append("unknown owned ship")
			break
	if not (d.owned_ships as Array).is_empty() and not str(d.ship) in d.owned_ships:
		errors.append("current ship is not owned")
	if d.has("nova_mode") and not str(d.nova_mode) in Ships.NOVA_MODES:
		errors.append("unknown Nova mode")
	for key in ["star_mask"]:
		for k in d[key]:
			if not k is int or int(k) < 1 or int(k) > 1000 or not d[key][k] is int or int(d[key][k]) < 0 or int(d[key][k]) > 7:
				errors.append("bad star data")
				break
	for key in ["upgrades", "mastery"]:
		if not d.has(key):
			continue
		for k in d[key]:
			if not k is String or not d[key][k] is int or int(d[key][k]) < 0 or int(d[key][k]) > 1000000000:
				errors.append("bad " + key)
				break
	for key in ["blueprints", "loadout", "side_cleared", "bosses_beaten", "seen_unlocks", "rift_claimed", "owned_ships"]:
		if d.has(key) and (d[key] as Array).size() > 500:
			errors.append(key + " is too long")
	errors.append_array(_validate_gear(d))
	return errors

static func _validate_gear(d: Dictionary) -> Array:
	var errors: Array = []
	var gear = d.get("gear", [])
	if (gear as Array).size() > Gear.MAX_ITEMS * 2:
		errors.append("too many gear items")
		return errors
	var uids := {}
	for item in gear:
		if not item is Dictionary:
			errors.append("a gear item is not a dictionary")
			break
		var it: Dictionary = item
		if not it.get("uid") is int or int(it.uid) < 1 or uids.has(int(it.uid)):
			errors.append("a gear item has a bad or repeated id")
			break
		uids[int(it.uid)] = true
		if not str(it.get("slot", "")) in Gear.SLOTS:
			errors.append("a gear item has an unknown slot")
			break
		if not it.get("rarity") is int or int(it.rarity) < 0 or int(it.rarity) > Gear.LEGENDARY:
			errors.append("a gear item has a bad rarity")
			break
		if not it.get("lvl", 0) is int or int(it.get("lvl", 0)) < 0 or int(it.get("lvl", 0)) > int(Gear.LEVEL_CAP[int(it.rarity)]):
			errors.append("a gear item has a bad level")
			break
		if not it.get("power", 1) is int or int(it.get("power", 1)) < 1 or int(it.get("power", 1)) > 100000:
			errors.append("a gear item has a bad power")
			break
		if not it.get("aff", []) is Array or (it.get("aff", []) as Array).size() > 8:
			errors.append("a gear item has bad stats")
			break
		var bad_stat := false
		for a in it.get("aff", []):
			if not a is Dictionary or not Gear.AFFIXES.has(str(a.get("k", ""))) or not _is_number(a.get("r", 0.0)) or float(a.get("r", 0.0)) < 0.0 or float(a.get("r", 0.0)) > 1.0:
				bad_stat = true
		if bad_stat:
			errors.append("a gear item has an unknown stat")
			break
		var perk := str(it.get("perk", ""))
		if not perk.is_empty() and not Gear.PERKS.has(perk):
			errors.append("a gear item has an unknown perk")
			break
	var equipped = d.get("equipped", {})
	for ship_id in equipped:
		if not equipped[ship_id] is Dictionary:
			errors.append("equipment is damaged")
			break
		for slot in equipped[ship_id]:
			if not str(slot) in Gear.SLOTS or not equipped[ship_id][slot] is int:
				errors.append("equipment is damaged")
				break
	return errors

# ---------- Reading a save ----------

## Keys of Save.PROGRESS_KEYS that are generated by the game rather than earned. Everything else counts.
##   gear_uid   a counter that follows the gear list
## and two keys that count only once the player has touched them:
##   contracts  today's three daily contracts are generated at every launch; they count once one has progress or is claimed
##   stats      the title screen mirrors a few other values into stats on every launch (see DERIVED_STATS); those never count
const GENERATED_KEYS := ["gear_uid"]
const DERIVED_STATS := ["ships_owned", "best_mastery", "pilot_level", "stars", "side", "tier_unlocked"]

## True when a progress dictionary holds anything a player would mind losing. A brand new install, even one that
## has generated its first daily contracts and the title screen's derived statistics, does not. A new key in
## Save.PROGRESS_KEYS must be added here or to GENERATED_KEYS: the test suite fails until it is.
static func has_progress(d: Dictionary) -> bool:
	for key in ["salvage", "parts", "pilot_xp", "best_score", "endless_best_wave", "expedition_wins", "tier_unlocked", "reroll_tokens"]:
		if int(d.get(key, 0)) > 0:
			return true
	if int(d.get("unlocked", 1)) > 1 or str(d.get("ship", "nova")) != "nova" or str(d.get("nova_mode", "pulse")) != "pulse":
		return true
	for key in ["star_mask", "level_best", "upgrades", "mastery", "paints", "tutorial", "achievements", "codex", "expedition", "weekly_best", "daily_best", "equipped", "tier_data"]:
		if not (d.get(key, {}) as Dictionary).is_empty():
			return true
	for key in ["gear", "blueprints", "loadout", "side_cleared", "bosses_beaten", "seen_unlocks", "rift_claimed"]:
		if not (d.get(key, []) as Array).is_empty():
			return true
	if (d.get("owned_ships", ["nova"]) as Array).size() > 1:
		return true
	var stats: Dictionary = d.get("stats", {})
	for k in stats:
		if str(k) in DERIVED_STATS:
			continue
		var v = stats[k]
		if (v is int or v is float) and float(v) > 0.0:
			return true
		if v is Array and not (v as Array).is_empty():
			return true
	for c in (d.get("contracts", {}) as Dictionary).get("list", []):
		if c is Dictionary and (int(c.get("progress", 0)) > 0 or bool(c.get("done", false)) or bool(c.get("claimed", false))):
			return true
	var danger: Dictionary = d.get("danger", {})
	return not (danger.get("done", {}) as Dictionary).is_empty() or not (danger.get("last", {}) as Dictionary).is_empty()

## A one-way fingerprint of a Google Play Games player id. Only this is ever stored, never the id.
static func account_hash(player_id: String) -> String:
	if player_id.is_empty():
		return ""
	return ("starfall_salvage_pgs_account_v1:" + player_id).sha256_text()

## A fingerprint of the saved progress that ignores the time it was written, so two saves with the same
## content have the same fingerprint.
static func progress_hash(d: Dictionary) -> String:
	var copy: Dictionary = d.duplicate(true)
	copy.erase("saved_at")
	# A new player's danger record is {} until it is first repaired. Both spellings mean the same thing.
	copy["danger"] = Danger.repair(copy.get("danger", {}))
	return JSON.stringify(copy, "", true).sha256_text()

## What the conflict screen shows about a save.
static func summarize(d: Dictionary) -> Dictionary:
	var stars := 0
	for k in (d.get("star_mask", {}) as Dictionary):
		var m := int(d.star_mask[k])
		stars += (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1)
	return {
		"level": int(Pilot.level_of(int(d.get("pilot_xp", 0))).level), "pilot_xp": int(d.get("pilot_xp", 0)),
		"salvage": int(d.get("salvage", 0)), "parts": int(d.get("parts", 0)), "stars": stars,
		"unlocked": int(d.get("unlocked", 1)), "gear": (d.get("gear", []) as Array).size(),
		"ships": (d.get("owned_ships", []) as Array).size(), "saved_at": int(d.get("saved_at", 0)),
	}
