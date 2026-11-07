extends Node

# LevelDatabase - Data-driven Level System
# Loads the 60 canonical levels directly from res://data/levels.json (100% offline & instant).

signal levels_loaded(count: int)

var _levels_cache: Dictionary = {}
var is_loaded: bool = false

func _ready() -> void:
	load_local_levels()

func load_local_levels() -> void:
	_levels_cache.clear()
	var file_path := "res://data/levels.json"
	if FileAccess.file_exists(file_path):
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file:
			var json_text := file.get_as_text()
			file.close()
			var parsed = JSON.parse_string(json_text)
			if parsed is Array:
				_populate_cache(parsed)
				
	is_loaded = true
	print("LevelDatabase: %d ta daraja muvaffaqiyatli yuklandi!" % _levels_cache.size())
	levels_loaded.emit(_levels_cache.size())
	if OS.has_feature("web"):
		_register_web_interface()

func _register_web_interface() -> void:
	var win = JavaScriptBridge.get_interface("window")
	if win:
		win.godot_level_count = _levels_cache.size()

func _populate_cache(items: Array) -> void:
	for item in items:
		if item is Dictionary and item.has("id"):
			var lvl_id: int = int(item["id"])
			_levels_cache[lvl_id] = item

func get_level(level_id: int) -> Dictionary:
	if not is_loaded:
		load_local_levels()
	return _levels_cache.get(level_id, {})

func has_level(level_id: int) -> bool:
	if not is_loaded:
		load_local_levels()
	return _levels_cache.has(level_id)

func get_all_levels() -> Array:
	if not is_loaded:
		load_local_levels()
	return _levels_cache.values()
