extends Node2D

# Wrong Way - Visual Autopilot Bot (1 to 60 Levels)
# Powered by Physics Trajectory Lookahead AI Engine.

var current_level_id: int = 1
const MAX_LEVELS: int = 60

var current_level_instance: Node2D = null
var current_player: PlayerController = null
var current_door: ExitDoor = null
var current_traps: Node2D = null
var current_platforms: Node2D = null

# Geometry map
var solid_zones: Array[Dictionary] = []
var hazard_zones: Array[Dictionary] = []
var spring_nodes: Array[Node2D] = []

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
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--start="):
			current_level_id = clampi(int(arg.trim_prefix("--start=")), 1, MAX_LEVELS)

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

	_scan_level_geometry()
	print("[AUTOPILOT] solid_zones: %d, hazards: %d" % [solid_zones.size(), hazard_zones.size()])
	for s in solid_zones:
		print("  Solid: [%.0f, %.0f] @ y=%.0f" % [s.x1, s.x2, s.y])

	if current_player:
		current_player.died.connect(_on_player_died)
		prev_pos_x = current_player.global_position.x

	GameManager.current_level_id = lvl_id
	GameManager.is_level_running = true
	GameManager.is_countdown_active = false

	bot_status_text = "Daraja boshlandi"
	print("[AUTOPILOT] Daraja boshlandi: %d" % lvl_id)
	_update_hud()

func _scan_level_geometry() -> void:
	solid_zones.clear()
	hazard_zones.clear()
	spring_nodes.clear()

	if current_platforms:
		for p: Node in current_platforms.get_children():
			if p is StaticBody2D and "platform_size" in p:
				var p_name := p.name.to_lower()
				if p_name.contains("ceiling") or p_name.contains("wall"):
					continue
				if p.global_position.y <= 90.0 and p.platform_size.x >= 300.0:
					continue
				var x1: float = p.global_position.x
				var x2: float = x1 + p.platform_size.x
				var y: float = p.global_position.y
				solid_zones.append({"x1": x1, "x2": x2, "y": y, "node": p})

	if current_traps:
		for t: Node in current_traps.get_children():
			var t_name := t.name.to_lower()
			if "spring_size" in t or t_name.contains("spring"):
				if t is Node2D:
					spring_nodes.append(t as Node2D)
			elif t_name.contains("trapfloor") or t_name.contains("crumbling"):
				var t2d := t as Node2D
				var sz_x: float = 40.0
				if "platform_size" in t:
					sz_x = t.platform_size.x
				var x1: float = t2d.global_position.x
				var x2: float = x1 + sz_x
				hazard_zones.append({
					"x1": x1, "x2": x2, "y": t2d.global_position.y,
					"type": "trap_floor"
				})
			elif t_name.contains("spike"):
				var t2d := t as Node2D
				var w: float = 48.0
				if "spike_size" in t:
					w = t.spike_size.x
				elif "spike_width" in t:
					w = t.spike_width
				var x1: float = t2d.global_position.x
				var x2: float = x1 + w
				hazard_zones.append({
					"x1": x1, "x2": x2, "y": t2d.global_position.y,
					"type": "spike"
				})
			elif t_name.contains("saw"):
				var t2d := t as Node2D
				var x1: float = t2d.global_position.x - 28.0
				var x2: float = t2d.global_position.x + 28.0
				hazard_zones.append({
					"x1": x1, "x2": x2, "y": t2d.global_position.y,
					"type": "saw", "node": t2d
				})

func is_safe_floor(x: float, y: float) -> bool:
	var on_solid: bool = false
	for s in solid_zones:
		# Require at least 18px clearance from platform edge to avoid corner clipping
		if x >= (s.x1 + 18.0) and x <= (s.x2 - 18.0) and absf(y - s.y) <= 32.0:
			on_solid = true
			break
	if not on_solid:
		return false

	for h in hazard_zones:
		if h.type == "saw" and "node" in h and is_instance_valid(h.node):
			var sx: float = (h.node as Node2D).global_position.x
			var sy: float = (h.node as Node2D).global_position.y
			if absf(x - sx) < 45.0 and absf(y - sy) < 40.0:
				return false
		else:
			if x >= (h.x1 - 12.0) and x <= (h.x2 + 12.0) and absf(y - h.y) <= 32.0:
				return false

	return true

func _predict_landing_x(p_pos: Vector2, vel: Vector2, floor_y: float) -> float:
	var delta_y: float = floor_y - p_pos.y
	if delta_y <= 2.0:
		return p_pos.x
	var g: float = 1200.0
	var disc: float = vel.y * vel.y + 2.0 * g * delta_y
	if disc < 0.0:
		return p_pos.x
	var t: float = (-vel.y + sqrt(disc)) / g
	return p_pos.x + vel.x * t

func _find_nearest_floor_y(curr_y: float) -> float:
	var best_y: float = 380.0
	var min_diff: float = 9999.0
	for s in solid_zones:
		if s.y >= (curr_y - 10.0):
			var diff: float = s.y - curr_y
			if diff < min_diff:
				min_diff = diff
				best_y = s.y
	return best_y

func _on_player_died() -> void:
	level_deaths += 1
	total_deaths += 1
	launched_by_spring = false
	stuck_counter = 0
	_release_inputs()
	var p_pos_val := Vector2.ZERO
	if is_instance_valid(current_player):
		p_pos_val = current_player.global_position
	print("[AUTOPILOT] O'lim: %d (pos: %s)" % [level_deaths, str(p_pos_val)])
	bot_status_text = "Qayta urinish (%d-o'lim)..." % level_deaths
	_update_hud()

func _physics_process(delta: float) -> void:
	if is_bot_paused or is_transitioning:
		return

	if not is_instance_valid(current_player) or not is_instance_valid(current_door):
		return

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

	# Track spring airborne state (spring launches at -700 or faster; normal jump is -440)
	if current_player.velocity.y < -620.0:
		launched_by_spring = true
	elif current_player.is_on_floor():
		launched_by_spring = false

	# Target selection
	var target_x: float = d_pos.x
	var need_spring: bool = (d_pos.y < p_pos.y - 35.0)

	if need_spring and not launched_by_spring and not spring_nodes.is_empty():
		var spring := _find_best_spring(p_pos, d_pos)
		if spring:
			target_x = spring.global_position.x + 16.0
			bot_status_text = "Purjinaga yo'nalmoqda"

	var dx: float = target_x - p_pos.x
	var move_dir: float = signf(dx) if absf(dx) > 2.0 else 0.0

	# Check hazards ahead: Lasers
	var laser_threat := _get_active_laser_ahead(p_pos, move_dir)
	if laser_threat:
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

	# Physics Trajectory Decision
	if current_player.is_on_floor():
		var should_jump: bool = false

		# Stuck on obstacle / wall
		if absf(p_pos.x - prev_pos_x) < 0.6 and move_dir != 0.0:
			stuck_counter += 1
		else:
			stuck_counter = 0
		prev_pos_x = p_pos.x

		if stuck_counter > 5 or current_player.is_on_wall():
			should_jump = true

		# Boulder threat
		var boulder := _get_boulder_threat(p_pos)
		if boulder:
			should_jump = true

		# Pit or Hazard ahead on floor
		var check_ahead_x: float = p_pos.x + move_dir * 32.0
		var is_ahead_safe: bool = is_safe_floor(check_ahead_x, p_pos.y)
		if not is_ahead_safe:
			var near_spring: bool = (need_spring and _is_near_any_spring(p_pos))
			if not near_spring:
				should_jump = true

		if should_jump and jump_cooldown <= 0.0:
			Input.action_press("jump")
			jump_cooldown = 0.28
			bot_status_text = "Sakramoqda!"
			print("[AUTOPILOT] JUMP at x=%.1f, y=%.1f" % [p_pos.x, p_pos.y])
		elif jump_cooldown <= 0.10 or not should_jump:
			Input.action_release("jump")
	else:
		# AIRBORNE: Predict landing position!
		var current_floor_y: float = _find_nearest_floor_y(p_pos.y)
		var land_x: float = _predict_landing_x(
			p_pos, current_player.velocity, current_floor_y
		)
		var is_land_safe: bool = is_safe_floor(land_x, current_floor_y)
		var is_under_safe: bool = is_safe_floor(p_pos.x, current_floor_y)

		# If landing unsafe or flying over gap: DASH if dash clears to safety!
		var over_gap: bool = (not is_under_safe and current_player.velocity.y > -250.0)
		var needs_dash: bool = (not is_land_safe or over_gap)
		var dash_land_x: float = land_x + move_dir * 125.0
		var can_clear_by_dash: bool = is_safe_floor(dash_land_x, current_floor_y)

		if needs_dash and can_clear_by_dash and dash_cooldown <= 0.0:
			if not launched_by_spring:
				Input.action_press("dash")
				dash_cooldown = 0.45
				bot_status_text = "Havoda Dash (sakrash uzaytirildi)!"
				print("[AUTOPILOT] DASH at x=%.1f, land_x=%.1f" % [p_pos.x, land_x])

	_update_hud()

func _get_active_laser_ahead(at_pos: Vector2, dir: float) -> Node2D:
	if not current_traps:
		return null
	for t: Node in current_traps.get_children():
		if t is LaserBeamTrap:
			var lb := t as LaserBeamTrap
			var dx: float = (lb.global_position.x - at_pos.x) * dir
			if dx > 4.0 and dx < 65.0:
				if lb.is_active:
					return lb
	return null

func _get_dropping_crusher_ahead(at_pos: Vector2, dir: float) -> Node2D:
	if not current_traps:
		return null
	for t: Node in current_traps.get_children():
		if t is Crusher:
			var cr := t as Crusher
			var dx: float = (
				cr.global_position.x + cr.crusher_size.x / 2.0 - at_pos.x
			) * dir
			if dx > 0.0 and dx < (cr.crusher_size.x / 2.0 + 36.0):
				if cr.global_position.y > 60.0:
					return cr
	return null

func _get_boulder_threat(at_pos: Vector2) -> Node2D:
	if not current_traps:
		return null
	for t: Node in current_traps.get_children():
		if t is RollingBoulder:
			var b := t as RollingBoulder
			var dist: float = b.global_position.x - at_pos.x
			var dy: float = absf(b.global_position.y - at_pos.y)
			if absf(dist) < 85.0 and dy < 35.0:
				return b
	return null

func _is_near_any_spring(at_pos: Vector2) -> bool:
	for s in spring_nodes:
		if is_instance_valid(s) and at_pos.distance_to(s.global_position) < 55.0:
			return true
	return false

func _find_best_spring(at_pos: Vector2, d_pos: Vector2) -> Node2D:
	var best_s: Node2D = null
	var min_d := 99999.0
	var fallback_s: Node2D = null
	var min_fallback_d := 99999.0
	for s in spring_nodes:
		if is_instance_valid(s):
			var dist: float = at_pos.distance_to(s.global_position)
			if dist < min_fallback_d:
				min_fallback_d = dist
				fallback_s = s
			if s.global_position.y >= at_pos.y - 30.0:
				var cond_r: bool = (
					d_pos.x >= at_pos.x and
					s.global_position.x >= at_pos.x - 30.0
				)
				var cond_l: bool = (
					d_pos.x < at_pos.x and
					s.global_position.x <= at_pos.x + 30.0
				)
				var is_towards: bool = cond_r or cond_l
				if is_towards and dist < min_d:
					min_d = dist
					best_s = s
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
