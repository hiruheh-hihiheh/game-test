extends Node
## Local balance log and crash breadcrumbs. Autoloaded as "Telemetry".
## Nothing leaves the device. To add a real analytics or crash service later, set
## `provider` to an object with send(event: String, data: Dictionary); no game code changes.
## Anything sent to a provider must be gated on the player's opt-in (Save.opt.telemetry).

const LOG_PATH := "user://telemetry.log"
const LOCK_PATH := "user://session.lock"
const CRUMB_PATH := "user://breadcrumbs.log"
const MAX_LOG_BYTES := 256000
const CRUMBS := 40

var provider = null
var previous_session_crashed := false
var _crumbs: PackedStringArray = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Save.path == Save.TEST_PATH:
		return
	# The lock is removed on clean exit, so finding one means the last session died.
	previous_session_crashed = FileAccess.file_exists(LOCK_PATH)
	var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))

func breadcrumb(text: String) -> void:
	_crumbs.append("%d %s" % [Time.get_ticks_msec(), text])
	if _crumbs.size() > CRUMBS:
		_crumbs.remove_at(0)

func log_event(event: String, data: Dictionary = {}) -> void:
	breadcrumb(event)
	if Save.path == Save.TEST_PATH:
		return
	if not bool(Save.opt.telemetry):
		return
	if provider != null:
		provider.send(event, data)
	_append(event, data)

func _append(event: String, data: Dictionary) -> void:
	if FileAccess.file_exists(LOG_PATH):
		var size_check := FileAccess.open(LOG_PATH, FileAccess.READ)
		if size_check and size_check.get_length() > MAX_LOG_BYTES:
			size_check.close()
			DirAccess.remove_absolute(LOG_PATH)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify({"e": event, "t": int(Time.get_unix_time_from_system()), "d": data}))

func _flush_crumbs() -> void:
	var f := FileAccess.open(CRUMB_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_crumbs))

func _notification(what: int) -> void:
	if Save.path == Save.TEST_PATH:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_crumbs()
		DirAccess.remove_absolute(LOCK_PATH)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(Time.get_unix_time_from_system()))
