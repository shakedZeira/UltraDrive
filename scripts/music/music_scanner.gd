# scripts/music/music_scanner.gd
class_name MusicScanner
extends RefCounted

## Threaded recursive scan of the music folder.
##
## Pass 1 (cheap): iterative DirAccess walk -> path, size, mtime. Pass 2: per file,
## consult the index cache (key = relative path + size + mtime); a hit reads no
## file, a miss reads ONLY the header (TagReader). The worker never touches the
## scene tree: it queues messages under a mutex and the main thread drains them
## with poll(). A rescan / folder change bumps `generation`; workers drop stale
## work and poll() drops stale messages.
##
## Messages from poll(): {type:"meta", meta}, {type:"progress", done, total},
## {type:"tracks", tracks:[...]}, {type:"done", stats}.

const BATCH_SIZE := 40
const INDEX_VERSION := 1
const MAX_DEPTH := 8
const MAX_FILES := 20000
const DEFAULT_INDEX := "user://music_index.json"

var generation: int = 0
## Tag reads that missed the cache / hit it (for tests and diagnostics).
var parse_count: int = 0
var cache_hits: int = 0

var _mutex := Mutex.new()
var _messages: Array = []
var _task: int = -1
var _running: bool = false
var _root: String = ""
var _index_path: String = DEFAULT_INDEX
var _min_age: float = 0.0

func is_running() -> bool:
	return _running

## Starts a background scan; returns the generation it runs under.
func start(folder: String, index_path: String = DEFAULT_INDEX, min_age_s: float = 0.0) -> int:
	cancel()
	_prepare(folder, index_path, min_age_s)
	var gen := generation
	_running = true
	_task = WorkerThreadPool.add_task(_run.bind(gen), false, "music_scan")
	return gen

## Same work on the calling thread (tests, tiny libraries). Results are still
## delivered through poll().
func run_sync(folder: String, index_path: String = DEFAULT_INDEX, min_age_s: float = 0.0) -> int:
	cancel()
	_prepare(folder, index_path, min_age_s)
	var gen := generation
	_running = true
	_run(gen)
	return gen

func cancel() -> void:
	generation += 1
	_mutex.lock()
	_messages.clear()
	_mutex.unlock()
	if _task >= 0:
		# Make sure a stale worker has finished touching our members before reuse.
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_running = false

## Drain queued messages of the CURRENT generation.
func poll() -> Array:
	_mutex.lock()
	var out := _messages
	_messages = []
	_mutex.unlock()
	var live: Array = []
	for m in out:
		if int(m["gen"]) == generation:
			live.append(m)
		if String(m["type"]) == "done" and int(m["gen"]) == generation:
			_running = false
	return live

func _prepare(folder: String, index_path: String, min_age_s: float) -> void:
	generation += 1
	_root = folder
	_index_path = index_path
	_min_age = min_age_s
	parse_count = 0
	cache_hits = 0

func _push(gen: int, message: Dictionary) -> void:
	message["gen"] = gen
	_mutex.lock()
	_messages.append(message)
	_mutex.unlock()

func _run(gen: int) -> void:
	var walked := walk(_root, _min_age)
	if gen != generation:
		return
	var files: Array = walked["files"]
	var sidecar := SidecarLoader.load_root(_root)
	_push(gen, {"type": "meta", "meta": walked["folder_meta"], "sidecar": sidecar})
	_push(gen, {"type": "progress", "done": 0, "total": files.size()})
	var index := load_index(_index_path, _root)
	var new_index := {}
	var batch: Array = []
	var done := 0
	var local_parse := 0
	var local_hits := 0
	for f in files:
		if gen != generation:
			return
		var rel: String = f["rel"]
		var raw: Dictionary
		var cached: Dictionary = index.get(rel, {})
		if not cached.is_empty() and int(cached.get("size", -1)) == int(f["size"]) \
				and int(cached.get("mtime", -1)) == int(f["mtime"]) and cached.get("tag") is Dictionary:
			raw = cached["tag"]
			local_hits += 1
		else:
			local_parse += 1
			if bool(f["native"]) or String(f["ext"]) == "flac":
				raw = TagReader.read_raw(String(f["path"]))
			else:
				raw = TagReader.read_raw("") # blank
		new_index[rel] = {"size": int(f["size"]), "mtime": int(f["mtime"]), "tag": raw}
		batch.append(_make_track(f, raw, sidecar, _root))
		done += 1
		if batch.size() >= BATCH_SIZE:
			_push(gen, {"type": "tracks", "tracks": batch})
			_push(gen, {"type": "progress", "done": done, "total": files.size()})
			batch = []
	if gen != generation:
		return
	if not batch.is_empty():
		_push(gen, {"type": "tracks", "tracks": batch})
	save_index(_index_path, _root, new_index)
	_mutex.lock()
	parse_count = local_parse
	cache_hits = local_hits
	_mutex.unlock()
	_push(gen, {"type": "progress", "done": done, "total": files.size()})
	_push(gen, {"type": "done", "stats": {"files": files.size(), "parsed": local_parse, "cached": local_hits}})

static func _make_track(f: Dictionary, raw: Dictionary, sidecar: Dictionary = {}, root: String = "") -> Dictionary:
	var rel: String = f["rel"]
	var side := MusicLibrary.sidecar_track(sidecar, rel)
	if not side.is_empty():
		# The sidecar only fills fields the embedded tags left empty (raw stays
		# tag-only in the index cache, so editing the sidecar needs no re-parse).
		raw = raw.duplicate()
		for key in ["title", "artist", "album"]:
			if String(raw.get(key, "")).is_empty():
				raw[key] = String(side.get(key, ""))
		if float(raw.get("duration_s", 0.0)) <= 0.0:
			raw["duration_s"] = float(side.get("duration_s", 0.0))
	var t := TagReader.resolve(raw, rel)
	t["id"] = rel
	t["rel"] = rel
	t["path"] = f["path"]
	t["station_folder"] = f["station_folder"]
	t["ext"] = f["ext"]
	t["native"] = f["native"]
	t["cover_file"] = f.get("cover_file", "")
	t["cover_path"] = f.get("cover_path", "")
	var side_cover := String(side.get("cover", ""))
	if String(t["cover_file"]).is_empty() and not side_cover.is_empty() and not root.is_empty():
		var base := root.replace("\\", "/").rstrip("/")
		if FileAccess.file_exists(base + "/" + side_cover):
			t["cover_file"] = side_cover
			t["cover_path"] = base + "/" + side_cover
	return t

# ---------------------------------------------------------------------------
# Folder walk (pure of scene state; safe on a worker thread).
# ---------------------------------------------------------------------------

## -> { files: [{rel, path, size, mtime, ext, native, station_folder, cover_file}],
##      folder_meta: {folder: station.json dict} }. Files are sorted by relative
## path; "." entries, in-flight downloads (*.part.*) and empty files are skipped.
static func walk(root: String, min_age_s: float = 0.0) -> Dictionary:
	var files: Array = []
	var images: Dictionary = {}
	var folder_meta: Dictionary = {}
	var base := root.replace("\\", "/")
	while base.length() > 1 and base.ends_with("/") and not base.ends_with(":/"):
		base = base.substr(0, base.length() - 1)
	if base.is_empty() or not DirAccess.dir_exists_absolute(base):
		return {"files": files, "folder_meta": folder_meta}
	var now := Time.get_unix_time_from_system()
	var stack: Array = [["", 0]]
	while not stack.is_empty() and files.size() < MAX_FILES:
		var item: Array = stack.pop_back()
		var rel_dir: String = item[0]
		var depth: int = item[1]
		var dir := DirAccess.open(base if rel_dir.is_empty() else base + "/" + rel_dir)
		if dir == null:
			continue
		var top := rel_dir.get_slice("/", 0)
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var rel := name if rel_dir.is_empty() else rel_dir + "/" + name
			if dir.current_is_dir():
				if depth < MAX_DEPTH:
					stack.append([rel, depth + 1])
			elif not MusicFormats.is_partial(name):
				var ext := name.get_extension().to_lower()
				var kind := MusicFormats.kind_for(ext)
				if kind != MusicFormats.Kind.NONE:
					var abs_path := base + "/" + rel
					var size := _file_size(abs_path)
					var mtime := int(FileAccess.get_modified_time(abs_path))
					var stable := min_age_s <= 0.0 or (now - float(mtime)) >= min_age_s
					if size > 0 and stable:
						files.append({
							"rel": rel, "path": abs_path, "size": size, "mtime": mtime, "ext": ext,
							"native": kind == MusicFormats.Kind.NATIVE, "station_folder": top,
						})
				elif MusicFormats.is_image(ext):
					images[rel.to_lower()] = rel
				elif name.to_lower() == "station.json" and not rel_dir.is_empty() and not rel_dir.contains("/"):
					var meta := _read_station_json(base + "/" + rel)
					if not meta.is_empty():
						folder_meta[rel_dir] = meta
			name = dir.get_next()
		dir.list_dir_end()
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["rel"]).to_lower() < String(b["rel"]).to_lower())
	for f in files:
		var cover := cover_file_for(String(f["rel"]), images)
		f["cover_file"] = cover
		f["cover_path"] = "" if cover.is_empty() else base + "/" + cover
	return {"files": files, "folder_meta": folder_meta}

## Sidecar cover for a track: "<stem>.jpg|jpeg|png|webp" next to it, else
## cover|folder|front|album.<img> in the same folder, else "".
static func cover_file_for(rel: String, images: Dictionary) -> String:
	var dir := rel.get_base_dir()
	var prefix := "" if dir.is_empty() else dir + "/"
	var stem := rel.get_file().get_basename()
	for e in MusicFormats.IMAGE_EXT:
		var key := (prefix + stem + "." + e).to_lower()
		if images.has(key):
			return String(images[key])
	for s in MusicFormats.FOLDER_COVER_STEMS:
		for e in MusicFormats.IMAGE_EXT:
			var key2 := (prefix + s + "." + e).to_lower()
			if images.has(key2):
				return String(images[key2])
	return ""

static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n

static func _read_station_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# ---------------------------------------------------------------------------
# Index cache (user://music_index.json): versioned, any parse error rebuilds.
# ---------------------------------------------------------------------------

static func load_index(path: String, root: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	if int(d.get("version", -1)) != INDEX_VERSION or String(d.get("root", "")) != root:
		return {}
	var entries: Variant = d.get("entries", {})
	return entries if entries is Dictionary else {}

static func save_index(path: String, root: String, entries: Dictionary) -> bool:
	var json := JSON.stringify({"version": INDEX_VERSION, "root": root, "entries": entries})
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(json)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK
