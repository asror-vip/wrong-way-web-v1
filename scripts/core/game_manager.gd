extends Node

signal level_started(level_id: int)
signal level_completed(level_id: int, time_ms: float, deaths: int, stars: int)
signal player_died(deaths_count: int)
signal player_respawned
signal request_screen_shake(intensity: float)
signal custom_level_completed
signal custom_player_died

var current_level_id: int = 1
var level_deaths: int = 0
var level_start_time: float = 0.0
var level_timer_ms: float = 0.0
var is_level_running: bool = false
var is_custom_editor_mode: bool = false
var is_duel_mode: bool = false
var is_countdown_active: bool = false
var duel_random_seed: int = 0

func get_current_chapter() -> int:
	if current_level_id <= 20:
		return 1
	elif current_level_id <= 40:
		return 2
	elif current_level_id <= 60:
		return 3
	elif current_level_id <= 80:
		return 4
	return 5

func is_winter_theme() -> bool:
	return get_current_chapter() == 2

func _enter_tree() -> void:
	if get_tree() and get_tree().root:
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		get_tree().root.content_scale_size = Vector2i(960, 540)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile") or OS.has_feature("android"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	elif not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and is_level_running and not get_tree().paused:
			restart_current_level()
		elif event.keycode == KEY_F11:
			toggle_fullscreen()
		elif event.keycode == KEY_F10 and OS.has_feature("editor"):
			var sm = get_node_or_null("/root/SaveManager")
			if sm:
				var new_val: bool = not bool(sm.get("debug_unlock_all"))
				sm.set("debug_unlock_all", new_val)
				if sm.has_method("save_data"):
					sm.save_data()
				print("SaveManager: debug_unlock_all = ", new_val)


func start_game(level_id: int) -> void:
	is_duel_mode = false
	is_countdown_active = false
	get_tree().paused = false
	current_level_id = level_id
	level_deaths = 0
	level_timer_ms = 0.0
	level_start_time = Time.get_ticks_msec()
	is_level_running = true

	var cur_scene = get_tree().current_scene
	if cur_scene and cur_scene.name == "Gameplay" and cur_scene.has_method("reload_to_level"):
		cur_scene.reload_to_level(level_id)
		return

	get_tree().change_scene_to_file("res://scenes/game/gameplay.tscn")
	# change_scene_to_file is deferred, so we shouldn't emit level_started here.
	# The gameplay.gd's _ready will call _load_level directly.

func start_duel_game(level_id: int, random_seed_num: int = 0) -> void:
	is_duel_mode = true
	is_countdown_active = true
	duel_random_seed = random_seed_num
	seed(random_seed_num)
	get_tree().paused = false
	current_level_id = level_id
	level_deaths = 0
	level_timer_ms = 0.0
	level_start_time = Time.get_ticks_msec()
	is_level_running = false
	get_tree().change_scene_to_file("res://scenes/game/gameplay.tscn")
	# Deferred change, gameplay.gd will handle it.

func record_death() -> void:
	if is_custom_editor_mode:
		custom_player_died.emit()
		return
	level_deaths += 1
	player_died.emit(level_deaths)
	var sm = get_node_or_null("/root/SaveManager")
	if sm == null or sm.shake_enabled:
		request_screen_shake.emit(10.0)

func complete_level() -> void:
	if is_custom_editor_mode:
		custom_level_completed.emit()
		return
	is_level_running = false
	level_timer_ms = Time.get_ticks_msec() - level_start_time
	var stars: int = 1
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("record_result"):
		stars = sm.record_result(current_level_id, level_timer_ms, level_deaths)
		sm.pending_result_data = {
			"lvl": current_level_id,
			"time_ms": level_timer_ms,
			"deaths": level_deaths,
			"stars": stars
		}
	level_completed.emit(current_level_id, level_timer_ms, level_deaths, stars)

func restart_current_level() -> void:
	get_tree().paused = false
	level_deaths = 0
	level_timer_ms = 0.0
	level_start_time = Time.get_ticks_msec()
	is_level_running = true
	level_started.emit(current_level_id)

func go_to_level_select() -> void:
	get_tree().paused = false
	is_level_running = false
	SoundManager.set_gameplay_mode(false)
	get_tree().change_scene_to_file("res://scenes/main/level_select.tscn")

func go_to_main_menu() -> void:
	get_tree().paused = false
	is_level_running = false
	SoundManager.set_gameplay_mode(false)
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
