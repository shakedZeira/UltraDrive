# autoload/save_manager.gd
extends Node

## Persists game data to user:// (mapped to AppData on Windows).
## Save robustness (match_fh6_gt7 P2-2): every write goes to a temp file that is
## renamed over the target so a crash never leaves a half-written slot; a slot
## that fails to parse is surfaced as corrupt (slot_state / load_game_full)
## instead of reading back as a fresh one; and a slot-wide size cap makes an
## oversized write fail cleanly instead of truncating.

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 3

## Serialized payload cap: a slot JSON larger than this is refused so oversized
## content (e.g. a bloated discovery dict) never writes a partial or truncated
## target file.
const MAX_SAVE_BYTES := 4 * 1024 * 1024

## Reserved top-level key holding the slot profile metadata (name, created_at).
## Additive: saves written before this feature simply lack the key and still
## load unchanged.
const PROFILE_KEY := "profile"

const DISCOVERY_KEY := "discovery"
const CAREER_MONEY_KEY := "career_money"
const CAREER_PROFILE_KEY := "career_profile"
const RIVAL_PERSONAS_KEY := "rival_personas"

## Slot readiness: MISSING (no file), VALID (parses to a Dictionary) or CORRUPT
## (present but unreadable). has_save() stays file-based so a corrupt slot reads
## as "present but corrupt" for a UI/diagnostic path that still wants to offer a
## recovery action.
enum SlotState { MISSING, VALID, CORRUPT }

## Last write/validation failure: one of "", "invalid_slot", "invalid_name",
## "slot_occupied", "save_too_large", "write_failed". Reset to "" on every call.
var last_error: String = ""

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

## Atomic-ish write: serialize to a .tmp sibling, then rename over the target.
## Refuses oversized payloads up front (no partial file, no truncation).
func save_game(slot: int, data: Dictionary) -> bool:
	last_error = ""
	if not _valid_slot(slot):
		last_error = "invalid_slot"
		return false
	var json := JSON.stringify(data, "\t")
	if json.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		last_error = "save_too_large"
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var tmp_path := _slot_tmp_path(slot)
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		last_error = "write_failed"
		return false
	file.store_string(json)
	file.close()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		DirAccess.remove_absolute(tmp_path)
		last_error = "write_failed"
		return false
	if dir.rename_absolute(tmp_path, _slot_path(slot)) == OK:
		return true
	DirAccess.remove_absolute(tmp_path)
	last_error = "write_failed"
	return false

## Compatibility surface: the slot Dictionary, or {} for a missing OR corrupt
## slot (callers that predate robustness keep working identically). Prefer
## load_game_full()/slot_state() when a corrupt slot must not look like a fresh
## one.
func load_game(slot: int) -> Dictionary:
	if not _valid_slot(slot):
		return {}
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json: Variant = _parse_json(file.get_as_text())
	file.close()
	return json if json is Dictionary else {}

## Robust read: { ok: bool, state: SlotState, data: Dictionary }. ok is false
## with state MISSING for an absent slot and state CORRUPT for a present-but-
## unparseable slot, so a corrupt save can never masquerade as a fresh slot.
func load_game_full(slot: int) -> Dictionary:
	if not _valid_slot(slot):
		return {"ok": false, "state": SlotState.MISSING, "data": {}}
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "state": SlotState.MISSING, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "state": SlotState.CORRUPT, "data": {}}
	var json: Variant = _parse_json(file.get_as_text())
	file.close()
	if json is Dictionary:
		return {"ok": true, "state": SlotState.VALID, "data": json}
	return {"ok": false, "state": SlotState.CORRUPT, "data": {}}

## SlotState for a polled slot (MISSING/VALID/CORRUPT).
func slot_state(slot: int) -> int:
	return int(load_game_full(slot)["state"])

## File-existence probe: a corrupt slot still reports present (use slot_state
## for corrupt-vs-missing disambiguation).
func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

## Initializes a named slot profile (name + created_at) inside the slot's own
## file. Refuses to overwrite an existing profile so a picker can never clobber
## a save by mis-clicking; a corrupt or absent slot is a valid create target.
func create_slot(slot: int, name: String) -> bool:
	last_error = ""
	var trimmed := name.strip_edges()
	if not _valid_slot(slot):
		last_error = "invalid_slot"
		return false
	if trimmed.is_empty():
		last_error = "invalid_name"
		return false
	var existing := load_game_full(slot)
	if existing["ok"]:
		var old: Dictionary = existing["data"]
		if old.has(PROFILE_KEY):
			last_error = "slot_occupied"
			return false
	var data := load_game(slot)
	data[PROFILE_KEY] = {"name": trimmed, "created_at": int(Time.get_unix_time_from_system())}
	return save_game(slot, data)

func slot_name(slot: int) -> String:
	var data := load_game(slot)
	var p: Variant = data.get(PROFILE_KEY, {})
	if p is Dictionary:
		var n: Variant = p.get("name", "")
		if n is String:
			return n
	return ""

func slot_created_at(slot: int) -> int:
	var data := load_game(slot)
	var p: Variant = data.get(PROFILE_KEY, {})
	if p is Dictionary:
		return int(p.get("created_at", 0))
	return 0

## 0-based indices of every slot with a file on disk (corrupt ones included,
## which the profile picker may still want to surface for re-creation).
func slots_in_use() -> Array[int]:
	var out: Array[int] = []
	for slot in MAX_SLOTS:
		if FileAccess.file_exists(_slot_path(slot)):
			out.append(slot)
	return out

## Read-only accessor for the "discovery" sub-dict inside a save slot.
## Used by WorldDiscovery.load_from_slot() so the save contract stays
## additive to the existing slot schema.
func load_discovery(slot: int) -> Dictionary:
	var data := load_game(slot)
	var d: Variant = data.get(DISCOVERY_KEY, {})
	return d if d is Dictionary else {}

## Merge-write the discovery sub-dict into an existing save slot
## (read-modify-write: preserves other slot fields like owned_cars,
## active_car, quality_preset, season, etc).
func save_discovery(slot: int, discovery: Dictionary) -> bool:
	var data := load_game(slot)
	data[DISCOVERY_KEY] = discovery
	return save_game(slot, data)

## Read-only accessor for the "career_money" sub-dict inside a save slot.
## Used by Money.load_from_slot() so the wallet stays additive to the
## existing slot schema.
func load_career_money(slot: int) -> Dictionary:
	var data := load_game(slot)
	var m: Variant = data.get(CAREER_MONEY_KEY, {})
	return m if m is Dictionary else {}

## Merge-write the wallet sub-dict into an existing save slot.
func save_career_money(slot: int, money: Dictionary) -> bool:
	var data := load_game(slot)
	data[CAREER_MONEY_KEY] = money
	return save_game(slot, data)

## Read-only accessor for the "career_profile" sub-dict inside a save slot.
## Used by CareerProfile.load_from_slot() (additive to the slot schema).
func load_career_profile(slot: int) -> Dictionary:
	var data := load_game(slot)
	var p: Variant = data.get(CAREER_PROFILE_KEY, {})
	return p if p is Dictionary else {}

## Merge-write the career profile sub-dict into an existing save slot.
func save_career_profile(slot: int, profile: Dictionary) -> bool:
	var data := load_game(slot)
	data[CAREER_PROFILE_KEY] = profile
	return save_game(slot, data)

## Read-only accessor for the "rival_personas" sub-dict inside a save slot.
## Used by RivalPersona.contract_for_slot() (additive to the slot schema).
func load_rival_personas(slot: int) -> Dictionary:
	var data := load_game(slot)
	var p: Variant = data.get(RIVAL_PERSONAS_KEY, {})
	return p if p is Dictionary else {}

## Merge-write the rival persona roster sub-dict into an existing save slot.
func save_rival_personas(slot: int, personas: Dictionary) -> bool:
	var data := load_game(slot)
	data[RIVAL_PERSONAS_KEY] = personas
	return save_game(slot, data)

static func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < MAX_SLOTS

static func _slot_path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json" % (slot + 1))

static func _slot_tmp_path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json.tmp" % (slot + 1))

static func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data