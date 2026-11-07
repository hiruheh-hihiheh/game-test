class_name UIArt
extends RefCounted
## Companion illustrations for menus.
##
## Memory: nothing is loaded at boot. A page asks for the groups it shows with `focus()`,
## the textures stream in on a background thread, and groups no page needs any more are
## released. Painting never loads or allocates anything: `draw()` only looks in the cache,
## and skips an illustration that has not arrived yet (it fades in when it does).
## With "Reduce motion" on, everything is drawn still.

const DIR := "res://assets/starfall/ui_illustrations/"

# key -> file. A path starting with res:// is used as it is.
const FILES := {
	# Title screen destinations
	"hangar": "home/hangar_dock.png",
	"ops": "home/ops_radar.png",
	"expedition": "home/expedition_rift.png",
	"rift": "home/endless_vortex.png",
	# Loot slots and the pilot badge
	"weapon": "loot/weapon.png",
	"reactor": "loot/reactor.png",
	"plating": "loot/plating.png",
	"rank": "pilot/rank_badge.png",
	# Hangar upgrades
	"cannon": "gear/cannon.png",
	"rapid": "gear/rapid.png",
	"shield": "gear/shield.png",
	"hull": "gear/hull.png",
	"magnet": "gear/magnet.png",
	"core": "gear/core.png",
	# Hangar tech
	"slot": "tech/slot.png",
	"reroll": "tech/reroll.png",
	"lucky": "tech/lucky.png",
	"extra_card": "tech/extra_card.png",
	"emergency": "tech/emergency.png",
	"salvor": "tech/salvor.png",
	# Nova modes. "locked" stands in for a mode the player has not found yet.
	"pulse": "nova/pulse.png",
	"singularity": "nova/singularity.png",
	"overdrive": "nova/overdrive.png",
	"aegis": "nova/aegis.png",
	"locked": "shared/locked_blueprint.png",
	# Existing boss art, drawn very faintly behind Legendary gear (boss_<sector>).
	"boss_1": "res://assets/starfall/gen/boss_warden_core.png",
	"boss_2": "res://assets/starfall/gen/boss_tyrant_hull.png",
	"boss_3": "res://assets/starfall/gen/boss_hydra_core.png",
	"boss_4": "res://assets/starfall/gen/boss_regent.png",
	"boss_5": "res://assets/starfall/gen/boss_admiral.png",
	"boss_6": "res://assets/starfall/gen/boss_core_eye.png",
}

# What each page needs. A group is loaded together and released together.
const GROUPS := {
	"home": ["hangar", "ops", "expedition", "rift"],
	"pilot": ["rank"],
	"loot": ["weapon", "reactor", "plating"],
	"upgrades": ["cannon", "rapid", "shield", "hull", "magnet", "core"],
	"tech": ["slot", "reroll", "lucky", "extra_card", "emergency", "salvor"],
	"nova": ["pulse", "singularity", "overdrive", "aegis", "locked"],
	"bosses": ["boss_1", "boss_2", "boss_3", "boss_4", "boss_5", "boss_6"],
	# Danger Contract cards (the title art in CORE covers "ops").
	"danger": ["hull", "rapid", "salvor", "core", "shield", "slot"],
}
# Small and used on the title screen every visit, so they stay in memory once loaded.
const CORE := ["home", "pilot"]
const FADE_IN := 0.22

# Motion per illustration. Cycles are 2.5 to 6 seconds and nothing is random.
# bob = px, rot = degrees, pulse = fraction of size, halo = a soft outline that breathes.
const STYLE := {
	"hangar": {"bob": 2.5, "bob_p": 4.4, "pulse": 0.015, "pulse_p": 3.6},
	"ops": {"rot": 4.0, "rot_p": 6.0, "pulse": 0.02, "pulse_p": 3.0, "ph": 0.3},
	"expedition": {"bob": 2.0, "bob_p": 3.8, "pulse": 0.025, "pulse_p": 3.4, "ph": 0.55},
	"rift": {"rot": 6.0, "rot_p": 6.0, "pulse": 0.02, "pulse_p": 3.2, "ph": 0.15},
	"weapon": {"fit": 1.15, "bob": 1.5, "bob_p": 4.0, "halo": Color(0.25, 0.9, 1.0), "halo_a": 0.34, "halo_p": 3.0},
	"reactor": {"rot": 3.0, "rot_p": 5.5, "pulse": 0.02, "pulse_p": 4.0, "ph": 0.4},
	"plating": {"bob": 1.2, "bob_p": 4.8, "halo": Color(1.0, 0.86, 0.5), "halo_a": 0.26, "halo_p": 5.5, "ph": 0.2},
	"rank": {"pulse": 0.02, "pulse_p": 2.6},
	"pulse": {"pulse": 0.03, "pulse_p": 3.2},
	"singularity": {"rot": 4.0, "rot_p": 5.5, "pulse": 0.02, "pulse_p": 4.2, "ph": 0.25},
	"overdrive": {"bob": 1.5, "bob_p": 3.0, "after": 0.2},
	"aegis": {"pulse": 0.025, "pulse_p": 4.0, "halo": Color(0.5, 0.95, 1.0), "halo_a": 0.2, "halo_p": 4.0},
}

# Looks for a locked or empty slot: a dim, cool tint instead of a recoloured copy of the image.
const GHOST := Color(0.62, 0.7, 0.84, 0.36)
const LOCKED := Color(0.6, 0.66, 0.8, 0.5)

static var _cache := {}    # key -> Texture2D
static var _pending := {}  # key -> time it was requested
static var _born := {}     # key -> time it arrived, for the fade-in
static var _want := {}     # key -> true while the current page needs it

# ---------- Accessibility ----------

## "Reduce motion": every illustration is drawn still.
static func calm() -> bool:
	return bool(Save.opt.get("reduced_motion", false))

## Extra light (halos, afterimages) is also off when flashes are reduced.
static func quiet() -> bool:
	return calm() or bool(Save.opt.get("reduced_flash", false))

static func now() -> float:
	return float(Time.get_ticks_msec()) * 0.001

# ---------- Loading ----------

static func has(key: String) -> bool:
	return FILES.has(key)

static func path_of(key: String) -> String:
	var f: String = FILES[key]
	return f if f.begins_with("res://") else DIR + f

static func keys_of(groups: Array) -> Array:
	var out: Array = []
	for g in groups:
		out.append_array(GROUPS.get(g, []))
	return out

## Tells the cache what the current page shows. `active` groups start streaming now, `warm` groups
## stream after them in case the player goes there next, and everything else (except the small
## title art) is released.
static func focus(active: Array, warm: Array = []) -> void:
	_want.clear()
	for k in keys_of(CORE + active + warm):
		_want[k] = true
	for k in _cache.keys():
		if not _want.has(k):
			_cache.erase(k)
			_born.erase(k)
	# Requests still in flight finish on their own; pump() drops them if nobody wants them any more.
	for k in keys_of(CORE + active):
		_request(k)
	for k in keys_of(warm):
		_request(k)

static func _request(key: String) -> void:
	if _cache.has(key) or _pending.has(key):
		return
	if ResourceLoader.load_threaded_request(path_of(key), "Texture2D") == OK:
		_pending[key] = now()

## The texture if it has arrived. Never blocks.
static func tex_of(key: String) -> Texture2D:
	var t: Texture2D = _cache.get(key)
	if t != null:
		return t
	if not _pending.has(key):
		if FILES.has(key):
			_want[key] = true
			_request(key)
		return null
	return _collect(key)

## Takes a finished request out of the loader. Anything the page no longer wants is let go.
static func _collect(key: String) -> Texture2D:
	var p := path_of(key)
	var status := ResourceLoader.load_threaded_get_status(p)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return null
	var t: Texture2D = null
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		t = ResourceLoader.load_threaded_get(p) as Texture2D
	var asked := float(_pending.get(key, 0.0))
	_pending.erase(key)
	if t == null or not _want.has(key):
		return null
	_cache[key] = t
	# An illustration that shows up while its page is already on screen fades in.
	if now() - asked < 0.6:
		_born[key] = now()
	return t

## Collects finished requests. Cheap; the menu calls it every frame.
static func pump() -> void:
	for k in _pending.keys():
		_collect(k)

## Loads groups right away. For tests and screenshot tools, never for a menu.
static func load_now(groups: Array) -> void:
	for k in keys_of(groups):
		if not _cache.has(k):
			_want[k] = true
			_cache[k] = load(path_of(k)) as Texture2D
			_pending.erase(k)

static func is_ready(groups: Array) -> bool:
	for k in keys_of(groups):
		if tex_of(k) == null:
			return false
	return true

static func loaded_keys() -> Array:
	return _cache.keys()

## Rough video memory of what is loaded, counting mipmaps.
static func memory_bytes() -> int:
	var total := 0
	for k in _cache:
		var t: Texture2D = _cache[k]
		total += int(float(t.get_width() * t.get_height() * 4) * 1.34)
	return total

static func clear() -> void:
	_cache.clear()
	_pending.clear()
	_born.clear()
	_want.clear()

# ---------- Drawing ----------

static func _phase(key: String, st: Dictionary) -> float:
	return float(st.get("ph", float(absi(key.hash()) % 100) / 100.0))

## Where an illustration sits at time t: a small offset, tilt and scale. Still when animate is false.
static func pose_of(key: String, t: float, animate: bool) -> Dictionary:
	var out := {"off": Vector2.ZERO, "rot": 0.0, "scale": 1.0}
	if not animate:
		return out
	var st: Dictionary = STYLE.get(key, {"bob": 1.5, "bob_p": 4.2})
	var ph := _phase(key, st)
	if st.has("bob"):
		out.off = Vector2(0.0, sin((t / float(st.bob_p) + ph) * TAU) * float(st.bob))
	if st.has("rot"):
		out.rot = deg_to_rad(sin((t / float(st.rot_p) + ph) * TAU) * float(st.rot))
	if st.has("pulse"):
		out.scale = 1.0 + sin((t / float(st.pulse_p) + ph) * TAU) * float(st.pulse)
	return out

## Draws illustration `key` inside a size x size box, keeping its proportions.
## Options: tint, animate (false draws it still), parent (the transform the caller is drawing
## under, such as a pressed button). Does nothing until the texture has arrived.
static func draw(ci: CanvasItem, key: String, center: Vector2, size: float, opts := {}) -> void:
	var tex := tex_of(key)
	if tex == null:
		return
	var parent: Transform2D = opts.get("parent", Transform2D.IDENTITY)
	var tint: Color = opts.get("tint", Color.WHITE)
	var t := now()
	if _born.has(key):
		var fade := clampf((t - float(_born[key])) / FADE_IN, 0.0, 1.0)
		if fade >= 1.0:
			_born.erase(key)
		else:
			tint.a *= fade
	var st: Dictionary = STYLE.get(key, {"bob": 1.5, "bob_p": 4.2})
	var animate: bool = bool(opts.get("animate", true)) and not calm()
	var ph := _phase(key, st)
	var pose := pose_of(key, t, animate)
	var off: Vector2 = pose.off
	var rot: float = pose.rot
	var sc: float = pose.scale
	var ts := tex.get_size()
	var k := size * float(st.get("fit", 1.0)) / maxf(ts.x, ts.y)
	var half := ts * k * 0.5
	var rect := Rect2(-half, half * 2.0)
	if animate and not quiet():
		if st.has("halo"):
			var glow: Color = st.halo
			var a := float(st.halo_a) * (0.5 + 0.5 * sin((t / float(st.halo_p) + ph) * TAU)) * tint.a
			ci.draw_set_transform_matrix(parent * Transform2D(rot, Vector2(sc * 1.07, sc * 1.07), 0.0, center + off))
			ci.draw_texture_rect(tex, rect, false, Color(glow, a))
		if st.has("after"):
			var flicker := 0.55 + 0.45 * sin(t * 5.2)
			ci.draw_set_transform_matrix(parent * Transform2D(rot, Vector2(sc, sc), 0.0, center + off + Vector2(-size * 0.09, 0.0)))
			ci.draw_texture_rect(tex, rect, false, Color(0.55, 0.85, 1.0, float(st.after) * flicker * tint.a))
	ci.draw_set_transform_matrix(parent * Transform2D(rot, Vector2(sc, sc), 0.0, center + off))
	ci.draw_texture_rect(tex, rect, false, tint)
	ci.draw_set_transform_matrix(parent)

## The boss of `sector` as a faint watermark inside `rect`.
static func boss_mark(ci: CanvasItem, sector: int, rect: Rect2, alpha: float) -> void:
	if sector < 1 or sector > 6:
		return
	var key := "boss_%d" % sector
	var tex := tex_of(key)
	if tex == null:
		return
	var a := alpha
	if _born.has(key):
		a *= clampf((now() - float(_born[key])) / FADE_IN, 0.0, 1.0)
	var ts := tex.get_size()
	var k := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var sz := ts * k
	ci.draw_texture_rect(tex, Rect2(rect.get_center() - sz * 0.5, sz), false, Color(0.9, 0.95, 1.0, a))
