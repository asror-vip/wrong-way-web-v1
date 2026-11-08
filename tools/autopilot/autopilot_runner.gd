extends Node2D

# Wrong Way - Visual Autopilot Bot (1 to 60 Levels)
# Plays levels visibly on screen with full UI, trap avoidance & auto-progression.

var current_level_id: int = 1
const MAX_LEVELS: int = 60

var current_level_instance: Node2D = null
var current_player: PlayerController = null
var current_door: ExitDoor = null
var current_traps: Node2D = null
var current_platforms: Node2D = null

var level_deaths: int = 0
var total_deaths: int = 0
var completed_levels: int = 0

var is_transitioning: bool = false
var is_bot_paused: bool = false
var bot_speed_multiplier: float = 1.0

var stuck_counter: int = 0
var prev_pos_x: float = 0.0
var jump_cooldown: float = 0.0
var dash_cooldown: float = 0.0
var launched_by_spring: bool = false
var bot_status_text: String = "Tayyorlanmoqda..."

@onready var level_container: Node2D = $LevelContainer
@onready var hud_layer: CanvasLayer = $CanvasLayer
@onready var lbl_level: Label = $CanvasLayer/Panel/HBox/LblLevel
@onready var lbl_status: Label = $CanvasLayer/Panel/HBox/LblStatus
@onready var lbl_stats: Label = $CanvasLayer/Panel/HBox/LblStats
@onready var btn_pause: Button = $CanvasLayer/Panel/HBox/BtnPause
@onready var btn_speed: Button = $CanvasLayer/Panel/HBox/BtnSpeed
@onready var win_banner: PanelContainer = $CanvasLayer/WinBanner
@onready var lbl_banner: Label = $CanvasLayer/WinBanner/LblBanner

func _ready() -> void:
	# Parse command line args if specified (e.g. --start=21)
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--start="):
			current_level_id = clampi(int(arg.trim_prefix("--start=")), 1, MAX_LEVELS)

	# Setup buttons
	$CanvasLayer/Panel/HBox/BtnPrev.pressed.connect(_on_prev_pressed)
	$CanvasLayer/Panel/HBox/BtnNext.pressed.connect(_on_next_pressed)
	btn_pause.pressed.connect(_on_pause_toggle)
	btn_speed.pressed.connect(_on_speed_toggle)

	win_banner.visible = false
	_load_level(current_level_id)

func _on_prev_pressed() -> void:
	if current_level_id > 1:
		_load_level(current_level_id - 1)

func _on_next_pressed() -> void:
	if current_level_id < MAX_LEVELS:
		_load_level(current_level_id + 1)

func _on_pause_toggle() -> void:
	is_bot_paused = !is_bot_paused
	btn_pause.text = "Davom" if is_bot_paused else "Pauza"
	if is_bot_paused:
		_release_inputs()

func _on_speed_toggle() -> void:
	if bot_speed_multiplier == 1.0:
		bot_speed_multiplier = 2.0
		Engine.time_scale = 2.0
		btn_speed.text = "2x"
	else:
		bot_speed_multiplier = 1.0
		Engine.time_scale = 1.0
		btn_speed.text = "1x"

func _load_level(lvl_id: int) -> void:
	_release_inputs()
	current_level_id = lvl_id
	level_deaths = 0
	is_transitioning = false
	launched_by_spring = false
	stuck_counter = 0

	# Unload previous level
	for child in level_container.get_children():
		level_container.remove_child(child)
		child.queue_free()

	win_banner.visible = false
	var path := "res://scenes/levels/level_%02d.tscn" % lvl_id
	if not ResourceLoader.exists(path):
		bot_status_text = "Fayl topilmadi: " + path
		_update_hud()
		return

	var scn: PackedScene = load(path)
	current_level_instance = scn.instantiate() as Node2D
	level_container.add_child(current_level_instance)

	current_player = current_level_instance.get_node_or_null("Player") as PlayerController
	current_door = current_level_instance.get_node_or_null("ExitDoor") as ExitDoor
	current_traps = current_level_instance.get_node_or_null("Traps")
	current_platforms = current_level_instance.get_node_or_null("Platforms")

	if current_player:
		current_player.died.connect(_on_player_died)
		prev_pos_x = current_player.global_position.x

	# Update GameManager current level
	GameManager.current_level_id = lvl_id
	GameManager.is_level_running = true
	GameManager.is_countdown_active = false

	bot_status_text = "Daraja boshlandi"
	print("[AUTOPILOT] Daraja boshlandi: %d" % lvl_id)
	_update_hud()

func _on_player_died() -> void:
	level_deaths += 1
	total_deaths += 1
	launched_by_spring = false
	stuck_counter = 0
	_release_inputs()
	bot_status_text = "Qayta urinish (%d-o'lim)..." % level_deaths
	_update_hud()

func _physics_process(delta: float) -> void:
	if is_bot_paused or is_transitioning:
		return

	if not is_instance_valid(current_player) or not is_instance_valid(current_door):
		return

	# Level complete check
	if current_door.is_sinking or current_player.is_entering_door:
		_handle_level_won()
		return

	var p_pos := current_player.global_position
	var d_pos := current_door.global_position

	if p_pos.distance_to(d_pos) < 32.0:
		_handle_level_won()
		return

	if current_player.is_dead:
		_release_inputs()
		return

	if jump_cooldown > 0.0:
		jump_cooldown -= delta
	if dash_cooldown > 0.0:
		dash_cooldown -= delta
		Input.action_release("dash")

	# Track spring airborne state
	if current_player.velocity.y < -300.0:
		launched_by_spring = true
	elif current_player.is_on_floor():
		launched_by_spring = false

	# Target selection
	var target_x: float = d_pos.x
	var need_spring: bool = (d_pos.y < p_pos.y - 35.0)

	if need_spring and not launched_by_spring and current_traps:
		var spring := _find_best_spring(p_pos, d_pos)
		if spring:
			target_x = spring.global_position.x + 16.0
			bot_status_text = "Purjinaga yo'nalmoqda"

	var dx := target_x - p_pos.x
	var move_dir := signf(dx) if absf(dx) > 2.0 else 0.0

	# Check hazards ahead: Lasers
	var laser_threat := _get_active_laser_ahead(p_pos, move_dir)
	if laser_threat:
		# Pause and wait for laser to pulse off
		_release_inputs()
		bot_status_text = "Lazer o'chishi kutilmoqda..."
		_update_hud()
		return

	# Check hazards ahead: Crushers
	var crusher_threat := _get_dropping_crusher_ahead(p_pos, move_dir)
	if crusher_threat:
		_release_inputs()
		bot_status_text = "Ezuvchi qaytishi kutilmoqda..."
		_update_hud()
		return

	# Handle inverted controls
	var final_move_dir := move_dir
	if current_player.controls_inverted:
		final_move_dir = -final_move_dir

	# Drive horizontal movement
	if final_move_dir > 0:
		Input.action_press("move_right")
		Input.action_release("move_left")
		bot_status_text = "O'ngga yugurmoqda"
	elif final_move_dir < 0:
		Input.action_press("move_left")
		Input.action_release("move_right")
		bot_status_text = "Chapga yugurmoqda"
	else:
		Input.action_release("move_right")
		Input.action_release("move_left")

	# Check stuck condition (running into wall or obstacle)
	if absf(p_pos.x - prev_pos_x) < 0.6 and move_dir != 0.0 and current_player.is_on_floor():
		stuck_counter += 1
	else:
		stuck_counter = 0
	prev_pos_x = p_pos.x

	var should_jump := false

	# 1. Stuck on wall / ledge
	if stuck_counter > 5 or current_player.is_on_wall():
		should_jump = true

	# 2. Pit ahead check
	if current_player.is_on_floor() and move_dir != 0.0:
		var is_near_spring := _is_near_any_spring(p_pos)
		if not is_near_spring and not _has_floor_ahead(p_pos, move_dir):
			should_jump = true
			# Wide pit: dash forward in mid-air
			if dash_cooldown <= 0.0:
				Input.action_press("dash")
				dash_cooldown = 0.5

	# 3. Rolling boulder threat
	var boulder := _get_boulder_threat(p_pos)
	if boulder and current_player.is_on_floor():
		should_jump = true

	# 4. Spikes or Saws on floor ahead
	if _has_spikes_ahead(p_pos, move_dir) and current_player.is_on_floor():
		should_jump = true

	# Execute jump
	if should_jump and current_player.is_on_floor() and jump_cooldown <= 0.0:
		Input.action_press("jump")
		jump_cooldown = 0.28
		bot_status_text = "Sakramoqda!"
	elif jump_cooldown <= 0.10 or not should_jump:
		Input.action_release("jump")

	_update_hud()

func _has_floor_ahead(at_pos: Vector2, dir: float) -> bool:
	var check_x := at_pos.x + dir * 28.0
	var check_y := at_pos.y
	if current_platforms:
		for p in current_platforms.get_children():
			if p is StaticBody2D and "platform_size" in p:
				var px1: float = p.global_position.x
				var px2: float = px1 + p.platform_size.x
				var py: float = p.global_position.y
				if check_x >= px1 and check_x <= px2 and absf(py - check_y) <= 24.0:
					return true
	if current_traps:
		for t in current_traps.get_children():
			if "platform_size" in t:
				var tx1: float = t.global_position.x
				var tx2: float = tx1 + t.platform_size.x
				var ty: float = t.global_position.y
				if check_x >= tx1 and check_x <= tx2 and absf(ty - check_y) <= 24.0:
					return true
	return false

func _has_spikes_ahead(at_pos: Vector2, dir: float) -> bool:
	if not current_traps:
		return false
	var check_x := at_pos.x + dir * 35.0
	for t in current_traps.get_children():
		var t_name := t.name.to_lower()
		if t_name.contains("spike") or t_name.contains("saw"):
			var sx: float = t.global_position.x
			var sy: float = t.global_position.y
			if absf(sx - check_x) < 32.0 and absf(sy - at_pos.y) < 35.0:
				return true
	return false

func _get_active_laser_ahead(at_pos: Vector2, dir: float) -> Node2D:
	if not current_traps:
		return null
	for t in current_traps.get_children():
		if t is LaserBeamTrap:
			var lb := t as LaserBeamTrap
			var dx := (lb.global_position.x - at_pos.x) * dir
			# Laser is directly in path within 65px
			if dx > 4.0 and dx < 65.0:
				if lb.is_active:
					return lb
	return null

func _get_dropping_crusher_ahead(at_pos: Vector2, dir: float) -> Node2D:
	if not current_traps:
		return null
	for t in current_traps.get_children():
		if t is Crusher:
			var cr := t as Crusher
			var dx := (cr.global_position.x + cr.crusher_size.x / 2.0 - at_pos.x) * dir
			if dx > 0.0 and dx < (cr.crusher_size.x / 2.0 + 36.0):
				# Dropping or at bottom
				if cr.global_position.y > 60.0:
					return cr
	return null

func _get_boulder_threat(at_pos: Vector2) -> Node2D:
	if not current_traps:
		return null
	for t in current_traps.get_children():
		if t is RollingBoulder:
			var b := t as RollingBoulder
			var dist := b.global_position.x - at_pos.x
			var dy := absf(b.global_position.y - at_pos.y)
			if absf(dist) < 85.0 and dy < 35.0:
				return b
	return null

func _is_near_any_spring(at_pos: Vector2) -> bool:
	if not current_traps:
		return false
	for t in current_traps.get_children():
		if "spring_size" in t or t.name.to_lower().contains("spring"):
			if at_pos.distance_to(t.global_position) < 55.0:
				return true
	return false

func _find_best_spring(at_pos: Vector2, d_pos: Vector2) -> Node2D:
	var best_s: Node2D = null
	var min_d := 99999.0
	var fallback_s: Node2D = null
	var min_fallback_d := 99999.0
	for t: Node2D in current_traps.get_children():
		if "spring_size" in t or t.name.to_lower().contains("spring"):
			var dist: float = at_pos.distance_to(t.global_position)
			if dist < min_fallback_d:
				min_fallback_d = dist
				fallback_s = t
			if t.global_position.y >= at_pos.y - 30.0:
				var cond_r: bool = (
					d_pos.x >= at_pos.x and
					t.global_position.x >= at_pos.x - 30.0
				)
				var cond_l: bool = (
					d_pos.x < at_pos.x and
					t.global_position.x <= at_pos.x + 30.0
				)
				var is_towards: bool = cond_r or cond_l
				if is_towards and dist < min_d:
					min_d = dist
					best_s = t
	return best_s if best_s else fallback_s

func _handle_level_won() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_release_inputs()
	completed_levels += 1

	bot_status_text = "G'alaba! Eshikka kirdi 🎉"
	print("[AUTOPILOT] G'alaba: %d-daraja yakunlandi!" % current_level_id)
	lbl_banner.text = "DARAJA %d MUVAFFAQIYATLI YAKUNLANDI!" % current_level_id
	win_banner.visible = true
	_update_hud()

	await get_tree().create_timer(0.45).timeout

	if current_level_id >= MAX_LEVELS:
		lbl_banner.text = "BARCHA 60 TA DARAJA BOT TOMONIDAN YUTIB CHIQILDI! 🏆"
		bot_status_text = "Barcha 60 ta daraja yakunlandi!"
		_update_hud()
	else:
		_load_level(current_level_id + 1)

func _release_inputs() -> void:
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("jump")
	Input.action_release("dash")

func _update_hud() -> void:
	if lbl_level:
		lbl_level.text = "DARAJA %02d / %02d" % [current_level_id, MAX_LEVELS]
	if lbl_status:
		lbl_status.text = "Holat: " + bot_status_text
	if lbl_stats:
		lbl_stats.text = "O'tildi: %d | O'limlar: %d" % [completed_levels, total_deaths]
