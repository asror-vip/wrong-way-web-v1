extends Node2D

@onready var level_holder: Node2D = $LevelHolder
@onready var camera: Camera2D = $Camera2D

var shake_intensity: float = 0.0
var arena_extensions: Node2D = null
var solid_platform_scene = preload("res://scenes/objects/solid_platform.tscn")

func _ready() -> void:
	arena_extensions = Node2D.new()
	arena_extensions.name = "ArenaExtensions"
	add_child(arena_extensions)
	move_child(arena_extensions, 0)
	get_viewport().size_changed.connect(_adapt_arena_boundaries)

	var adm = get_node_or_null("/root/AdManager")
	if adm and adm.has_method("hide_banner"):
		adm.hide_banner()
	GameManager.request_screen_shake.connect(_on_screen_shake)
	GameManager.level_started.connect(_load_level)
	GameManager.player_died.connect(func(_d):
		var poki = get_node_or_null("/root/PokiService")
		if poki and poki.has_method("gameplay_stop"):
			poki.gameplay_stop()
	)
	GameManager.player_respawned.connect(func():
		var poki = get_node_or_null("/root/PokiService")
		if poki and poki.has_method("gameplay_start"):
			poki.gameplay_start()
	)
	GameManager.level_completed.connect(func(_lvl, _t, _d, _s):
		var poki = get_node_or_null("/root/PokiService")
		if poki and poki.has_method("gameplay_stop"):
			poki.gameplay_stop()
	)
	_load_level(GameManager.current_level_id)
	_adapt_arena_boundaries()
	
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.should_restore_result_modal and not sm.pending_result_data.is_empty():
		sm.should_restore_result_modal = false
		GameManager.is_level_running = false
		var win_overlay = get_node_or_null("CanvasLayer/WinOverlay")
		if win_overlay and win_overlay.has_method("restore_result"):
			win_overlay.restore_result(sm.pending_result_data)
		if level_holder:
			level_holder.process_mode = Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	if shake_intensity > 0.0:
		shake_intensity = maxf(0.0, shake_intensity - delta * 25.0)
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_intensity
	else:
		camera.offset = Vector2.ZERO

func _on_screen_shake(intensity: float) -> void:
	shake_intensity = intensity

var level_arena_scene = preload("res://scenes/levels/level_arena.tscn")
static var _level_cache: Dictionary = {}

func reload_to_level(lvl: int) -> void:
	get_tree().paused = false
	var win_overlay = get_node_or_null("CanvasLayer/WinOverlay")
	if win_overlay:
		win_overlay.visible = false
	var pause_modal = get_node_or_null("CanvasLayer/PauseModal")
	if pause_modal:
		pause_modal.visible = false
		
	GameManager.current_level_id = lvl
	GameManager.level_deaths = 0
	GameManager.level_timer_ms = 0.0
	GameManager.level_start_time = Time.get_ticks_msec()
	GameManager.is_level_running = true
	
	_load_level(lvl)
	GameManager.level_started.emit(lvl)

func _load_level(lvl: int) -> void:
	var poki = get_node_or_null("/root/PokiService")
	if poki and poki.has_method("gameplay_start"):
		poki.gameplay_start()
	if level_holder:
		level_holder.process_mode = Node.PROCESS_MODE_INHERIT
		for child in level_holder.get_children():
			level_holder.remove_child(child)
			child.queue_free()
		
	# 1. Asosiy va eng aniq sozlangan sahna (.tscn) kesh orqali tezkor yuklanadi
	var path := "res://scenes/levels/level_%02d.tscn" % lvl
	var lvl_res: PackedScene = null
	if _level_cache.has(path):
		lvl_res = _level_cache[path]
	elif ResourceLoader.exists(path):
		lvl_res = load(path)
		if lvl_res:
			_level_cache[path] = lvl_res

	if lvl_res:
		var inst: Node2D = lvl_res.instantiate()
		level_holder.add_child(inst)
		_adapt_arena_boundaries()
		return

	# 2. Agar sahna fayli topilmasa, LevelDatabase dan dinamik arena yuklanadi
	var ldb = get_node_or_null("/root/LevelDatabase")
	if ldb and ldb.has_method("has_level") and ldb.has_level(lvl):
		var arena = level_arena_scene.instantiate()
		level_holder.add_child(arena)
		arena.load_level_from_data(ldb.get_level(lvl))
		_adapt_arena_boundaries()

func _adapt_arena_boundaries() -> void:
	if not arena_extensions or not is_inside_tree():
		return
	for c in arena_extensions.get_children():
		c.queue_free()
		
	var vp := get_viewport_rect().size
	var world_tl := Vector2(480.0, 270.0) - vp * 0.5
	var world_br := Vector2(480.0, 270.0) + vp * 0.5
	
	# Horizontal qanotlar (Keng ekranlar: 18:9, 19.5:9, 20:9, 21:9, ultra-wide)
	if world_tl.x < 0.0:
		var left_w := -world_tl.x + 36.0
		var h := (world_br.y - world_tl.y) + 128.0
		_create_extension_block(Vector2(world_tl.x - 32.0, world_tl.y - 64.0), Vector2(left_w, h))
		# Yer qanoti (chap tomon polining uzluksiz davomi)
		_create_extension_block(Vector2(world_tl.x - 32.0, 380.0), Vector2(left_w, (world_br.y - 380.0) + 128.0))
		
	if world_br.x > 960.0:
		var right_w := (world_br.x - 928.0) + 64.0
		var h := (world_br.y - world_tl.y) + 128.0
		_create_extension_block(Vector2(928.0, world_tl.y - 64.0), Vector2(right_w, h))
		# Yer qanoti (o'ng tomon polining uzluksiz davomi)
		_create_extension_block(Vector2(928.0, 380.0), Vector2(right_w, (world_br.y - 380.0) + 128.0))
		
	# Vertikal qanotlar (16:10, 4:3, planshet va baland ekranlar)
	if world_br.y > 540.0:
		var bot_h := (world_br.y - 540.0) + 64.0
		var total_w := (world_br.x - world_tl.x) + 128.0
		_create_extension_block(Vector2(world_tl.x - 64.0, 540.0), Vector2(total_w, bot_h))
		
	if world_tl.y < 0.0:
		var top_h := -world_tl.y + 64.0
		var total_w := (world_br.x - world_tl.x) + 128.0
		_create_extension_block(Vector2(world_tl.x - 64.0, world_tl.y - 64.0), Vector2(total_w, top_h))

func _create_extension_block(pos: Vector2, sz: Vector2) -> void:
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var p = solid_platform_scene.instantiate()
	p.position = pos
	p.platform_size = sz
	arena_extensions.add_child(p)



