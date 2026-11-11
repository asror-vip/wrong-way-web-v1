extends Node2D

# Wrong Way - Fair-Play Autopilot AI Engine (1 to 60 Levels)
# 100% Halol (Girromlarsiz): Faqat fizika, provokatsiya (baiting) va to'liq traektoriya hisoblari orqali.

var current_level_id: int = 1
const MAX_LEVELS: int = 60

var current_level_instance: Node2D = null
var current_player: PlayerController = null
var current_door: ExitDoor = null
var current_traps: Node2D = null
var current_platforms: Node2D = null

# Geometriya va xaritalash
var solid_platforms: Array[Dictionary] = []
var floor_hazards: Array[Dictionary] = []
var spring_nodes: Array[Node2D] = []

# Maxsus tuzoqlar ro'yxati
var crushers: Array[Crusher] = []
var falling_ceilings: Array[FallingCeiling] = []
var crashing_pillars: Array[CrashingPillar] = []
var falling_spikes: Array[FallingSpikeTrap] = []
var jumping_spikes: Array[JumpingSpikes] = []
var fake_doors: Array[FakeDoorTrap] = []
var dodging_platforms: Array[DodgingPlatform] = []
var invisible_blocks: Array[InvisibleBlock] = []

# Harakat va reja holatlari
var active_jump_allow_dash: bool = false
var active_jump_land_x: float = 0.0
var active_jump_max_x: float = 99999.0
var is_in_planned_jump: bool = false
var is_pit_jump: bool = false
var active_evading_boulder: Node2D = null
var active_evading_saw: Node2D = null

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

var max_frames_to_run: int = -1

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
	var all_args := OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--start="):
			current_level_id = clampi(int(arg.trim_prefix("--start=")), 1, MAX_LEVELS)
		elif arg.begins_with("--quit-after="):
			max_frames_to_run = int(arg.trim_prefix("--quit-after="))

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
	is_in_planned_jump = false
	active_evading_boulder = null
	active_evading_saw = null
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

	if current_player:
		current_player.died.connect(_on_player_died)
		prev_pos_x = current_player.global_position.x

	GameManager.current_level_id = lvl_id
	GameManager.is_level_running = true
	GameManager.is_countdown_active = false

	bot_status_text = "Halol rejim ishga tushdi"
	_update_hud()

func _scan_level_geometry() -> void:
	solid_platforms.clear()
	floor_hazards.clear()
	spring_nodes.clear()
	crushers.clear()
	falling_ceilings.clear()
	crashing_pillars.clear()
	falling_spikes.clear()
	jumping_spikes.clear()
	fake_doors.clear()
	dodging_platforms.clear()
	invisible_blocks.clear()

	if current_platforms:
		for p: Node in current_platforms.get_children():
			if p is StaticBody2D and "platform_size" in p:
				var p_name := p.name.to_lower()
				if p_name.contains("ceiling") or p_name.contains("wall"):
					continue
				var sz: Vector2 = p.platform_size
				if sz.x <= 32.0 or sz.y >= 500.0:
					continue
				if p.global_position.y <= 90.0 and sz.x >= 300.0:
					continue

				var x1: float = p.global_position.x
				var x2: float = x1 + sz.x
				var y: float = p.global_position.y
				solid_platforms.append({
					"x1": x1, "x2": x2, "y": y, "width": sz.x, "node": p
				})

	solid_platforms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.x1 < b.x1
	)

	var merged_plats: Array[Dictionary] = []
	for p in solid_platforms:
		if merged_plats.is_empty():
			merged_plats.append(p)
		else:
			var prev: Dictionary = merged_plats[-1]
			if absf(prev.y - p.y) <= 8.0 and p.x1 <= (prev.x2 + 5.0):
				prev.x2 = maxf(prev.x2, p.x2)
				prev.width = prev.x2 - prev.x1
			else:
				merged_plats.append(p)
	solid_platforms = merged_plats

	if current_traps:
		for t: Node in current_traps.get_children():
			var t_name := t.name.to_lower()
			if t is SpringTrap or "spring_size" in t or t_name.contains("spring"):
				if t is Node2D:
					spring_nodes.append(t as Node2D)
			elif t is Crusher:
				crushers.append(t as Crusher)
			elif t is FallingCeiling:
				falling_ceilings.append(t as FallingCeiling)
			elif t is CrashingPillar:
				crashing_pillars.append(t as CrashingPillar)
			elif t is FallingSpikeTrap:
				falling_spikes.append(t as FallingSpikeTrap)
			elif t is JumpingSpikes:
				var js := t as JumpingSpikes
				jumping_spikes.append(js)
				floor_hazards.append({
					"x1": js.global_position.x,
					"x2": js.global_position.x + js.spike_width,
					"y": js.global_position.y,
					"y_top": js.global_position.y - js.spike_height,
					"y_bottom": js.global_position.y,
					"type": "jumping_spikes", "node": js
				})
			elif t is DodgingPlatform:
				dodging_platforms.append(t as DodgingPlatform)
			elif t is InvisibleBlock:
				invisible_blocks.append(t as InvisibleBlock)
			elif t is FakeDoorTrap:
				fake_doors.append(t as FakeDoorTrap)
			elif t is SinkingDoorFloor:
				var sf := t as SinkingDoorFloor
				floor_hazards.append({
					"x1": sf.global_position.x - 10.0,
					"x2": sf.global_position.x + sf.platform_size.x + 10.0,
					"y": sf.global_position.y,
					"type": "sinking_floor", "node": sf
				})
			elif t is TrapFloor or t is CrumblingPlatform or t_name.contains("trapfloor") or t_name.contains("crumbling"):
				var t2d := t as Node2D
				var sz_x: float = 40.0
				if "platform_size" in t:
					sz_x = t.platform_size.x
				var x1: float = t2d.global_position.x
				floor_hazards.append({
					"x1": x1, "x2": x1 + sz_x, "y": t2d.global_position.y,
					"type": "trap_floor", "node": t2d
				})
			elif t is SpikesTrap or t is PopUpSpikesTrap or t_name.contains("spike"):
				var t2d := t as Node2D
				var w: float = 48.0
				if "spike_size" in t:
					w = t.spike_size.x
				elif "spike_width" in t:
					w = t.spike_width
				var x1: float = t2d.global_position.x
				var h_type := "spike"
				var y_bottom: float = t2d.global_position.y
				var y_top: float = y_bottom - 32.0
				if t is PopUpSpikesTrap:
					h_type = "popup"
					var max_h: float = t.max_spike_height if "max_spike_height" in t else 32.0
					y_top = y_bottom - max_h
				floor_hazards.append({
					"x1": x1, "x2": x1 + w, "y": y_bottom,
					"y_top": y_top, "y_bottom": y_bottom,
					"type": h_type, "node": t2d
				})
			elif t is CircularSawTrap or t_name.contains("circular"):
				var cs := t as CircularSawTrap
				var total_r: float = cs.orbit_radius + cs.saw_radius
				if _has_solid_platform_under(cs.global_position.x, cs.global_position.y + 45.0):
					floor_hazards.append({
						"x1": cs.global_position.x - total_r,
						"x2": cs.global_position.x + total_r,
						"y": cs.global_position.y,
						"type": "circular_saw", "node": cs
					})
			elif t is MovingSawTrap or t_name.contains("saw"):
				var ms := t as MovingSawTrap
				floor_hazards.append({
					"x1": ms.global_position.x - ms.radius,
					"x2": ms.global_position.x + ms.radius,
					"y": ms.global_position.y,
					"type": "saw", "node": ms
				})
			elif t is RotatingSpikeBallTrap or t_name.contains("spikeball"):
				var rb := t as RotatingSpikeBallTrap
				var reach: float = rb.chain_length + rb.ball_radius
				floor_hazards.append({
					"x1": rb.global_position.x - reach,
					"x2": rb.global_position.x + reach,
					"y": rb.global_position.y + reach,
					"type": "spikeball", "node": rb
				})

	# Yonma-yon tikanlarni bitta yaxlit to'siqqa birlashtirish
	floor_hazards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.x1 < b.x1
	)
	var merged_hazards: Array[Dictionary] = []
	for h in floor_hazards:
		if merged_hazards.is_empty():
			merged_hazards.append(h)
		else:
			var prev: Dictionary = merged_hazards[-1]
			var can_merge: bool = (
				(prev.type == "spike" or prev.type == "popup" or prev.type == "compound" or prev.type == "jumping_spikes") and
				(h.type == "spike" or h.type == "popup" or h.type == "compound" or h.type == "jumping_spikes")
			)
			if can_merge and absf(prev.y - h.y) <= 35.0 and (h.x1 - prev.x2) < 25.0:
				prev.x2 = maxf(prev.x2, h.x2)
				prev.type = "compound"
			else:
				merged_hazards.append(h)
	floor_hazards = merged_hazards

func _set_move_input(world_dir: float) -> void:
	var is_inverted: bool = current_player != null and current_player.controls_inverted
	var effective_dir: float = -world_dir if is_inverted else world_dir
	if effective_dir > 0.1:
		Input.action_press("move_right")
		Input.action_release("move_left")
	elif effective_dir < -0.1:
		Input.action_press("move_left")
		Input.action_release("move_right")
	else:
		Input.action_release("move_right")
		Input.action_release("move_left")

func _has_safe_runway_behind(at_pos: Vector2, move_dir: float, runway: float) -> bool:
	var back_dir: float = -move_dir
	var check_step := 8.0
	var dist := 8.0
	while dist <= runway:
		var check_x := at_pos.x + back_dir * dist
		if not _is_safe_floor(check_x, at_pos.y):
			return false
		dist += check_step
	return true

func _try_step_back(move_dir: float, runway: float = 24.0) -> bool:
	if current_player == null or not is_instance_valid(current_player):
		return false
	if _has_safe_runway_behind(current_player.global_position, move_dir, runway):
		_set_move_input(-move_dir)
		return true
	else:
		_set_move_input(0.0)
		return false

func _get_platform_at(pos: Vector2) -> Dictionary:
	for p in solid_platforms:
		if pos.x >= (p.x1 - 15.0) and pos.x <= (p.x2 + 15.0):
			if absf(pos.y - p.y) <= 45.0:
				return p
	for p in solid_platforms:
		if pos.x >= (p.x1 - 25.0) and pos.x <= (p.x2 + 25.0):
			return p
	return {}

func _get_platform_ahead(pos: Vector2, dir: float) -> Dictionary:
	var best_p: Dictionary = {}
	var min_dist: float = 99999.0
	for p in solid_platforms:
		var d: float = (p.x1 - pos.x) * dir if dir > 0 else (pos.x - p.x2) * dir
		if d > 10.0 and d < min_dist:
			min_dist = d
			best_p = p
	return best_p

func _has_solid_platform_under(x: float, y: float) -> bool:
	for s in solid_platforms:
		if x >= (s.x1 + 6.0) and x <= (s.x2 - 6.0):
			if s.y >= (y - 20.0):
				return true
	return false

func _is_safe_floor(x: float, y: float) -> bool:
	var on_solid: bool = false
	for s in solid_platforms:
		if x >= (s.x1 + 6.0) and x <= (s.x2 - 6.0) and absf(y - s.y) <= 35.0:
			on_solid = true
			break
	if not on_solid:
		return false

	for h in floor_hazards:
		if h.type == "sinking_floor":
			if x >= h.x1 and x <= h.x2:
				return false
		elif h.type == "saw" or h.type == "circular_saw":
			if is_instance_valid(h.node):
				var node_pos: Vector2 = (h.node as Node2D).global_position
				if absf(x - node_pos.x) < 36.0:
					return false
		elif h.type == "trap_floor":
			if is_instance_valid(h.node) and "is_falling" in h.node and h.node.is_falling:
				if x >= (h.x1 - 10.0) and x <= (h.x2 + 10.0):
					return false
		else:
			if x >= (h.x1 - 8.0) and x <= (h.x2 + 8.0) and absf(y - h.y) <= 35.0:
				return false

	# Faqatgina hali polga (y - 35.0) yetmagan va havoda turgan tikan ostigina xavfli deb hisoblanadi
	for fs in falling_spikes:
		if is_instance_valid(fs):
			var is_down: bool = (
				fs.is_grounded
				or fs.global_position.y >= (y - 35.0)
				or (fs.global_position.y > (fs.original_pos.y + 80.0) and not fs.is_falling)
				or fs.global_position.y > 450.0
			)
			if not is_down and absf(x - fs.global_position.x) < 26.0:
				return false

	return true

# KEYINGI PLATFORMAGA ANIQ VA XAVFSIZ QO'NISH KOORDINATASI
func _get_safe_pit_landing_x(plat: Dictionary, dir: float) -> float:
	if plat.is_empty():
		return 0.0
	var edge_x: float = plat.x1 if dir > 0 else plat.x2
	var target_x: float = edge_x + dir * 18.0

	# Agar yangi platforma boshida tushuvchi tikan bo'lsa, sakrash uni to'liq bosib o'tishi shart!
	for fs in falling_spikes:
		if is_instance_valid(fs):
			var fx: float = fs.global_position.x
			var dist_to_edge: float = (fx - edge_x) * dir
			if dist_to_edge > 0.0 and dist_to_edge < 75.0:
				var past_fx: float = fx + dir * 42.0
				target_x = maxf(target_x, past_fx) if dir > 0 else minf(target_x, past_fx)

	for h in floor_hazards:
		var h_app: float = h.x1 if dir > 0 else h.x2
		var h_end: float = h.x2 if dir > 0 else h.x1
		var d_hz: float = (h_app - edge_x) * dir
		if d_hz > 0.0 and d_hz < 70.0:
			var past_h: float = h_end + dir * 20.0
			target_x = maxf(target_x, past_h) if dir > 0 else minf(target_x, past_h)

	target_x = clampf(target_x, plat.x1 + 12.0, plat.x2 - 12.0)
	return target_x

# CHUQURLIKDAGI ARRALARNI (VERTİKAL VA GORIZONTAL) KUTISH MANTIG'I
func _is_pit_blocked_by_saw(edge_x: float, land_x: float) -> bool:
	if not current_traps:
		return false
	var x_min: float = minf(edge_x, land_x) - 15.0
	var x_max: float = maxf(edge_x, land_x) + 15.0
	for t in current_traps.get_children():
		if t is MovingSawTrap:
			var ms := t as MovingSawTrap
			var sx: float = ms.global_position.x
			if sx >= x_min and sx <= x_max:
				if ms.global_position.y < 365.0:
					return true
				var is_moving_up: bool = (ms.patrol_axis.y < -0.1 and ms.moving_forward) or (ms.patrol_axis.y > 0.1 and not ms.moving_forward)
				if is_moving_up and ms.global_position.y < 420.0:
					return true
	return false

func _get_moving_saw_pos_at(ms: MovingSawTrap, dt_ahead: float) -> Vector2:
	if not is_instance_valid(ms):
		return Vector2.ZERO
	if ms.patrol_distance <= 0.0 or ms.patrol_speed <= 0.0:
		return ms.global_position
	var cycle_time: float = (2.0 * ms.patrol_distance) / ms.patrol_speed
	var current_t: float = ms.patrol_t * (ms.patrol_distance / ms.patrol_speed)
	if not ms.moving_forward:
		current_t = cycle_time - current_t
	var future_t: float = fmod(current_t + dt_ahead, cycle_time)
	var half_c: float = cycle_time * 0.5
	var norm_t: float = (future_t / half_c) if future_t <= half_c else (2.0 - future_t / half_c)
	var dir_vec: Vector2 = ms.patrol_axis.normalized()
	return ms.start_pos + dir_vec * (ms.patrol_distance * norm_t)

# TRAEKTORIYA SIMULYATSIYASI (PREDICTIVE SHIFT TIKANLARI VA SHIFT TO'QNAShUVI)
func _simulate_trajectory(start_pos: Vector2, dir: float, with_dash: bool, max_x_limit: float = 99999.0) -> Dictionary:
	var sim_pos := start_pos
	var vx: float = dir * 280.0
	var vy: float = -560.0
	var g: float = 1450.0
	var dt: float = 1.0 / 60.0
	var dashed: bool = false
	var dash_steps: int = 0

	for step in range(75):
		var t: float = float(step) * dt
		if with_dash and not dashed and vy > -220.0:
			dashed = true
			dash_steps = 10

		var past_limit: bool = (sim_pos.x >= max_x_limit) if dir > 0 else (sim_pos.x <= max_x_limit)
		if past_limit and max_x_limit < 90000.0:
			vx = 0.0
			dash_steps = 0
		elif dash_steps > 0:
			vx = dir * 660.0
			dash_steps -= 1
		else:
			vx = dir * 280.0

		sim_pos.x += vx * dt
		vy += g * dt
		sim_pos.y += vy * dt

		# 1. Shift tikanlari bilan to'qnashuv (Ceiling teeth)
		if sim_pos.y <= 95.0:
			return {"safe": false, "reason": "ceiling_spikes"}

		# 2. InvisibleBlock to'qnashuvi
		for ib in invisible_blocks:
			if is_instance_valid(ib):
				var ix1: float = ib.global_position.x
				var ix2: float = ix1 + ib.block_size.x
				var iy1: float = ib.global_position.y
				var iy2: float = iy1 + ib.block_size.y
				if sim_pos.x >= (ix1 - 10.0) and sim_pos.x <= (ix2 + 10.0):
					if (sim_pos.y - 32.0) <= iy2 and sim_pos.y >= iy1:
						return {"safe": false, "reason": "invisible_block"}

		# 3. Harakatlanuvchi va aylanma arralar
		if current_traps:
			for tr in current_traps.get_children():
				if tr is CircularSawTrap:
					var cs := tr as CircularSawTrap
					var c_dir: float = 1.0 if cs.clockwise else -1.0
					var ang: float = cs.current_angle + cs.orbit_speed * c_dir * t
					var b_pos: Vector2 = cs.global_position + Vector2(cos(ang), sin(ang)) * cs.orbit_radius
					if Vector2(sim_pos.x, sim_pos.y - 18.0).distance_to(b_pos) < (cs.saw_radius + 24.0):
						return {"safe": false, "reason": "circular_saw"}

				elif tr is MovingSawTrap:
					var ms := tr as MovingSawTrap
					var s_pos := _get_moving_saw_pos_at(ms, t)
					if Vector2(sim_pos.x, sim_pos.y - 16.0).distance_to(s_pos) < (ms.radius + 18.0):
						return {"safe": false, "reason": "moving_saw"}

				elif tr is LaserBeamTrap:
					var lb := tr as LaserBeamTrap
					var cycle: float = lb.active_time + lb.inactive_time
					var l_t: float = fmod(lb.timer + t, cycle)
					if l_t < lb.active_time:
						var lx: float = lb.global_position.x
						var ly: float = lb.global_position.y
						if lb.is_vertical:
							if absf(sim_pos.x - lx) < 14.0 and sim_pos.y >= (ly - 10.0) and sim_pos.y <= (ly + lb.beam_length + 10.0):
								return {"safe": false, "reason": "laser"}
						else:
							if absf(sim_pos.y - ly) < 14.0 and sim_pos.x >= (lx - 10.0) and sim_pos.x <= (lx + lb.beam_length + 10.0):
								return {"safe": false, "reason": "laser"}

		# 4. PREDICTIVE FALLING SPIKE (Faqat hali havoda bo'lgan tikan uchun)
		for fs in falling_spikes:
			if is_instance_valid(fs) and not fs.is_grounded and fs.global_position.y < (start_pos.y - 50.0):
				var fx: float = fs.global_position.x
				var dx_to_fs: float = absf(sim_pos.x - fx)
				if dx_to_fs < 45.0:
					var t_fall: float = maxf(0.0, t - 0.16)
					var spike_y: float = fs.global_position.y + 750.0 * t_fall + 1200.0 * t_fall * t_fall
					if absf(sim_pos.y - spike_y) < 36.0:
						return {"safe": false, "reason": "falling_spike"}

		# 5. Parvoz davomidagi yerdagi tikanlar
		for h in floor_hazards:
			if h.type == "spike" or h.type == "popup" or h.type == "jumping_spikes" or h.type == "compound":
				var h_top: float = h.get("y_top", h.y - 32.0)
				var h_bottom: float = h.get("y_bottom", h.y)
				if (sim_pos.x + 12.0) >= h.x1 and (sim_pos.x - 12.0) <= h.x2:
					if sim_pos.y >= (h_top - 6.0) and (sim_pos.y - 30.0) <= h_bottom:
						return {"safe": false, "reason": "spike_flight"}

		# 6. Qo'nish nuqtasi tekshiruvi
		if vy > 0.0:
			for s in solid_platforms:
				if sim_pos.x >= (s.x1 + 6.0) and sim_pos.x <= (s.x2 - 6.0):
					if sim_pos.y >= s.y and (sim_pos.y - vy * dt) <= (s.y + 18.0):
						# Shift tikani qo'nish nuqtasiga uriladimi (faqat tepada osilgan bo'lsa)
						for fs in falling_spikes:
							if is_instance_valid(fs) and not fs.is_grounded and fs.global_position.y < (s.y - 50.0):
								if absf(sim_pos.x - fs.global_position.x) < 28.0:
									return {"safe": false, "reason": "spike_landing"}
						if _is_safe_floor(sim_pos.x, s.y):
							return {"safe": true, "land_x": sim_pos.x}
						else:
							return {"safe": false, "reason": "bad_landing"}

	return {"safe": false, "reason": "timeout"}

func _on_player_died() -> void:
	level_deaths += 1
	total_deaths += 1
	launched_by_spring = false
	is_in_planned_jump = false
	active_evading_boulder = null
	active_evading_saw = null
	stuck_counter = 0
	jump_cooldown = 0.0
	dash_cooldown = 0.0
	_release_inputs()
	bot_status_text = "Qayta urinish (%d-o'lim)..." % level_deaths
	_update_hud()

func _physics_process(delta: float) -> void:
	if max_frames_to_run > 0 and Engine.get_physics_frames() >= max_frames_to_run:
		get_tree().quit(0)
		return

	if is_bot_paused or is_transitioning:
		return

	if not is_instance_valid(current_player) or not is_instance_valid(current_door):
		return

	if current_door.is_sinking or current_player.is_entering_door:
		_handle_level_won()
		return

	var p_pos := current_player.global_position
	var d_pos := current_door.global_position

	if p_pos.distance_to(d_pos) < 32.0 or (absf(p_pos.x - d_pos.x) < 20.0 and absf(p_pos.y - d_pos.y) < 32.0):
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

	if current_player.velocity.y < -580.0:
		launched_by_spring = true
	elif current_player.is_on_floor():
		launched_by_spring = false
		if jump_cooldown <= 0.0:
			is_in_planned_jump = false
			active_evading_boulder = null
			active_evading_saw = null

	var target_x: float = d_pos.x
	var need_spring: bool = (d_pos.y < p_pos.y - 45.0)
	var spring_ahead: Node2D = null

	if need_spring and not launched_by_spring and not spring_nodes.is_empty():
		var spring := _find_best_spring(p_pos, d_pos)
		if spring:
			spring_ahead = spring
			target_x = spring.global_position.x + 16.0

	var dx: float = target_x - p_pos.x
	var move_dir: float = signf(dx) if absf(dx) > 3.0 else 0.0

	# 1. Toshdan qochish
	var boulder := _get_boulder_threat(p_pos)
	if boulder != null and current_player.is_on_floor():
		if jump_cooldown <= 0.0:
			Input.action_press("jump")
			jump_cooldown = 0.36
			is_in_planned_jump = true
			active_evading_boulder = boulder
			active_jump_max_x = 99999.0
			active_jump_land_x = p_pos.x + move_dir * 280.0
			active_jump_allow_dash = true
			_set_move_input(move_dir)
			bot_status_text = "Tosh ustidan olg'a sakramoqda!"
			return

	# 2. Tuzoqlarni provokatsiya qilish
	if current_player.is_on_floor() and not is_in_planned_jump:
		var bait_handled := _handle_trap_baiting(p_pos, move_dir)
		if bait_handled:
			stuck_counter = 0
			_update_hud()
			return

	# 3. Dinamik to'siqlarni kutish
	if current_player.is_on_floor() and not is_in_planned_jump:
		if _handle_saw_waiting(p_pos, move_dir):
			stuck_counter = 0
			_update_hud()
			return
		if _check_laser_blocking(p_pos, move_dir):
			stuck_counter = 0
			_update_hud()
			return

	if current_player.is_on_floor():
		if absf(p_pos.x - prev_pos_x) < 0.4 and move_dir != 0.0:
			stuck_counter += 1
		else:
			stuck_counter = 0
		prev_pos_x = p_pos.x

	var should_jump: bool = false
	var execute_dash: bool = false
	var should_airbrake: bool = false

	# 4. PLATFORMA VA TUZOQLARDAN O'TISHNI REJALASHTIRISH
	var curr_plat := _get_platform_at(p_pos)
	if not curr_plat.is_empty():
		var plat_x1: float = curr_plat.x1
		var plat_x2: float = curr_plat.x2
		var plat_edge_x: float = plat_x2 if move_dir > 0 else plat_x1
		var dist_to_edge: float = (plat_edge_x - p_pos.x) * move_dir

		var next_hazard: Dictionary = {}
		var min_hz_dist: float = 9999.0
		for h in floor_hazards:
			var h_app: float = h.x1 if move_dir > 0 else h.x2
			var dist: float = (h_app - p_pos.x) * move_dir
			if dist > -10.0 and dist < min_hz_dist:
				if p_pos.x >= plat_x1 - 15.0 and p_pos.x <= plat_x2 + 15.0:
					min_hz_dist = dist
					next_hazard = h

		# SinkingDoorFloor: eshikka to'g'ridan-to'g'ri sakrash
		if not next_hazard.is_empty() and next_hazard.type == "sinking_floor":
			var d_dist := absf(d_pos.x - p_pos.x)
			if d_dist < 260.0 and current_player.is_on_floor() and jump_cooldown <= 0.0:
				should_jump = true
				is_in_planned_jump = true
				active_jump_allow_dash = (d_dist > 140.0)
				active_jump_land_x = d_pos.x
				bot_status_text = "Eshikka havodan to'g'ridan-to'g'ri sakrash!"

		# Yerdagi tikan/tuzoq ustidan sakrash
		elif not next_hazard.is_empty() and min_hz_dist < dist_to_edge:
			var hz_app: float = next_hazard.x1 if move_dir > 0 else next_hazard.x2
			var dist_to_hz: float = (hz_app - p_pos.x) * move_dir
			var takeoff_dist: float = 65.0

			if current_player.is_on_floor() and not is_in_planned_jump:
				if dist_to_hz < 30.0 and dist_to_hz > -5.0:
					if _try_step_back(move_dir, 35.0):
						bot_status_text = "Razgon uchun chekinmoqda..."
						return

			if current_player.is_on_floor() and jump_cooldown <= 0.0 and not is_in_planned_jump:
				if dist_to_hz <= takeoff_dist and dist_to_hz >= -5.0:
					var sim_norm := _simulate_trajectory(p_pos, move_dir, false)
					var sim_dash := _simulate_trajectory(p_pos, move_dir, true)

					if sim_norm.safe:
						should_jump = true
						is_in_planned_jump = true
						active_jump_allow_dash = false
						active_jump_land_x = sim_norm.land_x
					elif sim_dash.safe:
						should_jump = true
						is_in_planned_jump = true
						active_jump_allow_dash = true
						active_jump_land_x = sim_dash.land_x
					else:
						# Tikan bo'lsa kutmasdan orqaga razgonga chiqadi
						if _try_step_back(move_dir, 40.0):
							bot_status_text = "Razgon uchun orqaga chekinmoqda..."
							return
						else:
							should_jump = true
							is_in_planned_jump = true
							active_jump_allow_dash = true
							active_jump_land_x = hz_app + move_dir * 120.0
							bot_status_text = "Majburiy sakrash!"

		# Chuqurlik (Pit) ustidan sakrash
		elif dist_to_edge > 0.0 and dist_to_edge <= 28.0:
			var next_p := _get_platform_ahead(p_pos, move_dir)
			if not next_p.is_empty():
				var safe_target_x := _get_safe_pit_landing_x(next_p, move_dir)

				if _is_pit_blocked_by_saw(plat_edge_x, safe_target_x):
					_set_move_input(0.0)
					bot_status_text = "Chuqurdagi vertikal arra kutilmoqda..."
					_update_hud()
					return

				if current_player.is_on_floor() and jump_cooldown <= 0.0:
					var sim_norm := _simulate_trajectory(p_pos, move_dir, false)
					var sim_dash := _simulate_trajectory(p_pos, move_dir, true)

					var need_dash_for_spike := false
					for fs in falling_spikes:
						if is_instance_valid(fs) and not fs.is_grounded:
							if absf(safe_target_x - fs.global_position.x) < 40.0:
								need_dash_for_spike = true
								break

					if sim_dash.safe and (need_dash_for_spike or not sim_norm.safe):
						should_jump = true
						is_in_planned_jump = true
						is_pit_jump = true
						active_jump_allow_dash = true
						active_jump_land_x = sim_dash.land_x
						bot_status_text = "Chuqur va arra ustidan Dash sakrash!"
					elif sim_norm.safe:
						should_jump = true
						is_in_planned_jump = true
						is_pit_jump = true
						active_jump_allow_dash = false
						active_jump_land_x = sim_norm.land_x
						bot_status_text = "Arra aylanib o'tdi, sakramoqda!"
					else:
						# Arra aylanib yo'lni to'sib turgan paytda chetda to'xtab turadi (orqadagi tikanga chekinmaydi)
						_set_move_input(0.0)
						bot_status_text = "Arra o'tib xavfsiz oyna ochilishi kutilmoqda..."
						return

	# Havodagi boshqaruv (Dash & Airbrake)
	if not current_player.is_on_floor():
		if is_in_planned_jump:
			var at_apex: bool = current_player.velocity.y > -220.0
			if active_jump_allow_dash and at_apex and dash_cooldown <= 0.0:
				execute_dash = true
				active_jump_allow_dash = false
			elif not active_jump_allow_dash:
				var past_land: bool = (p_pos.x >= active_jump_land_x) if move_dir > 0 else (p_pos.x <= active_jump_land_x)
				if past_land:
					should_airbrake = true

	if stuck_counter > 8 and current_player.is_on_floor() and jump_cooldown <= 0.0:
		should_jump = true
		stuck_counter = 0

	if should_jump and jump_cooldown <= 0.0:
		Input.action_press("jump")
		jump_cooldown = 0.36
	elif not current_player.is_on_floor() and current_player.velocity.y >= 0.0:
		Input.action_release("jump")

	if execute_dash and dash_cooldown <= 0.0:
		Input.action_press("dash")
		dash_cooldown = 0.42

	if should_airbrake:
		_set_move_input(0.0)
	else:
		_set_move_input(move_dir)

	_update_hud()

# TUZOQLARNI PROVOKATSIYA QILISH (BAITING)
func _handle_trap_baiting(p_pos: Vector2, move_dir: float) -> bool:
	# A. CRUSHER
	for cr in crushers:
		if not is_instance_valid(cr):
			continue
		var cx1: float = cr.global_position.x
		var cx2: float = cx1 + cr.crusher_size.x
		var c_mid: float = (cx1 + cx2) * 0.5
		var dist_to_mid: float = (c_mid - p_pos.x) * move_dir
		if dist_to_mid > -10.0 and dist_to_mid < 120.0:
			var safe_wait_x: float = cx1 - 20.0 if move_dir > 0 else cx2 + 20.0
			var bait_trigger_x: float = cx1 - 8.0 if move_dir > 0 else cx2 + 8.0

			if cr.state == Crusher.State.IDLE:
				var at_bait: bool = (p_pos.x >= bait_trigger_x) if move_dir > 0 else (p_pos.x <= bait_trigger_x)
				if not at_bait:
					return false
				else:
					_try_step_back(move_dir, 20.0)
					bot_status_text = "Ezuvchi tuzog'i provokatsiya qilindi..."
					return true

			elif cr.state == Crusher.State.FALLING or cr.state == Crusher.State.WAITING_BOTTOM:
				var at_safe: bool = (p_pos.x <= safe_wait_x) if move_dir > 0 else (p_pos.x >= safe_wait_x)
				if at_safe:
					_set_move_input(0.0)
					bot_status_text = "Ezuvchi tushishi kutilmoqda..."
					return true
				else:
					_try_step_back(move_dir, 20.0)
					return true

			elif cr.state == Crusher.State.RISING:
				var cr_bottom: float = cr.global_position.y + cr.crusher_size.y
				if cr_bottom > 300.0:
					_set_move_input(0.0)
					bot_status_text = "Ezuvchi ko'tarilishi kutilmoqda..."
					return true
				else:
					bot_status_text = "Ezuvchi tagidan o'tmoqda!"
					return false

	# B. JUMPING SPIKES
	for js in jumping_spikes:
		if not is_instance_valid(js):
			continue
		if js.is_triggered:
			if js.global_position.y < (js.original_pos.y - 5.0):
				_set_move_input(0.0)
				bot_status_text = "Sakragan tikan yerga qaytishi kutilmoqda..."
				return true
			continue

		var js_mid: float = js.global_position.x + js.spike_width * 0.5
		var dist_to_js: float = (js_mid - p_pos.x) * move_dir
		if dist_to_js > 0.0 and dist_to_js < 75.0:
			if dist_to_js > 55.0:
				_set_move_input(move_dir)
				return true
			else:
				_set_move_input(0.0)
				if jump_cooldown <= 0.0 and current_player.is_on_floor():
					Input.action_press("jump")
					jump_cooldown = 0.5
					bot_status_text = "Sakrovchi tikan havoga chiqarildi (Bait)!"
				return true

	# C. CRASHING PILLAR & FALLING CEILING
	for cp in crashing_pillars:
		if not is_instance_valid(cp) or cp.is_grounded:
			continue
		var px: float = cp.global_position.x + cp.pillar_size.x * 0.5
		var dist_to_p: float = (px - p_pos.x) * move_dir
		if dist_to_p > 0.0 and dist_to_p < 170.0:
			if not cp.is_triggered:
				if dist_to_p > 155.0:
					return false
				else:
					_try_step_back(move_dir, 24.0)
					bot_status_text = "Qulovchi ustun ishga tushirildi..."
					return true
			else:
				_set_move_input(0.0)
				bot_status_text = "Ustun qulashi kutilmoqda..."
				return true

	for fc in falling_ceilings:
		if not is_instance_valid(fc):
			continue
		var cx: float = fc.global_position.x + fc.ceiling_size.x * 0.5
		var dist_to_c: float = (cx - p_pos.x) * move_dir
		if dist_to_c > 0.0 and dist_to_c < 110.0:
			if not fc.is_triggered:
				if dist_to_c > 85.0:
					return false
				else:
					_try_step_back(move_dir, 24.0)
					bot_status_text = "Shift qulashi ishga tushirildi..."
					return true
			else:
				_set_move_input(0.0)
				bot_status_text = "Shift urilishi kutilmoqda..."
				return true

	# D. FALLING SPIKE (Shift tikani)
	for fs in falling_spikes:
		if not is_instance_valid(fs):
			continue
		# Tikan pol sathiga (y - 35.0) yetgan yoki shiftdan 80px pastda to'xtagan bo'lsa, xavfsiz deb o'tib ketiladi
		var is_down_or_gone: bool = (
			fs.is_grounded
			or fs.global_position.y >= (p_pos.y - 35.0)
			or (fs.global_position.y > (fs.original_pos.y + 80.0) and not fs.is_falling)
			or fs.global_position.y > 450.0
			or not fs.visible
			or (fs.col_shape and fs.col_shape.disabled)
		)
		if is_down_or_gone:
			continue

		var sx: float = fs.global_position.x
		var dist_to_s: float = (sx - p_pos.x) * move_dir
		if dist_to_s > 0.0 and dist_to_s < 75.0:
			if not fs.is_triggered:
				if dist_to_s > 52.0:
					return false
				else:
					_try_step_back(move_dir, 20.0)
					bot_status_text = "Shift tikani tebratildi..."
					return true
			else:
				if dist_to_s < 38.0:
					_try_step_back(move_dir, 16.0)
				else:
					_set_move_input(0.0)
				bot_status_text = "Shift tikani tushishi kutilmoqda..."
				return true

	# E. FAKE DOOR
	for fd in fake_doors:
		if not is_instance_valid(fd):
			continue
		if not fd.visible or (fd.col_shape and fd.col_shape.disabled):
			continue
		var dist_to_fd: float = (fd.global_position.x - p_pos.x) * move_dir
		if dist_to_fd > 0.0 and dist_to_fd < 120.0:
			if not fd.is_triggered:
				if dist_to_fd > 70.0:
					_set_move_input(move_dir)
					bot_status_text = "Soxta eshikka yaqinlashmoqda..."
					return true
				else:
					_set_move_input(0.0)
					bot_status_text = "Soxta eshik qochishi kutilmoqda..."
					return true
			else:
				_set_move_input(0.0)
				bot_status_text = "Soxta eshik yo'qolishi kutilmoqda..."
				return true

	return false

func _check_laser_blocking(p_pos: Vector2, move_dir: float) -> bool:
	if not current_traps:
		return false
	for t in current_traps.get_children():
		if t is LaserBeamTrap:
			var lb := t as LaserBeamTrap
			var dx: float = (lb.global_position.x - p_pos.x) * move_dir
			if dx > 4.0 and dx < 60.0:
				var cycle: float = lb.active_time + lb.inactive_time
				var cur_t: float = fmod(lb.timer, cycle)
				var is_on: bool = cur_t < lb.active_time
				var time_left_safe: float = (cycle - cur_t) if not is_on else 0.0
				if is_on or time_left_safe < 0.45:
					_set_move_input(0.0)
					bot_status_text = "Lazer o'chishi kutilmoqda..."
					return true
	return false

func _handle_saw_waiting(p_pos: Vector2, move_dir: float) -> bool:
	if not current_traps:
		return false
	for t in current_traps.get_children():
		if t is MovingSawTrap:
			var ms := t as MovingSawTrap
			var s_pos: Vector2 = ms.global_position
			var dx: float = (s_pos.x - p_pos.x) * move_dir
			# Faqat pol ustida yurgan oddiy arra o'yinchiga qarab kelayotganda kutish
			if absf(s_pos.y - p_pos.y) < 35.0 and dx > 0.0 and dx < 75.0:
				var s_dir: float = ms.patrol_axis.x if ms.moving_forward else -ms.patrol_axis.x
				var moving_towards: bool = (s_dir * (p_pos.x - s_pos.x)) > 0.0
				if moving_towards or dx < 45.0:
					_set_move_input(0.0)
					bot_status_text = "Harakatlanuvchi arra kutilmoqda..."
					return true
	return false

func _get_boulder_threat(p_pos: Vector2) -> Node2D:
	if not current_traps:
		return null
	for t in current_traps.get_children():
		if t is RollingBoulder:
			var b := t as RollingBoulder
			if b.has_fallen or not (b.is_triggered or b.is_rolling):
				continue
			var dist: float = absf(b.global_position.x - p_pos.x)
			if dist < 160.0 and absf(b.global_position.y - p_pos.y) < 50.0:
				return b
	return null

func _find_best_spring(at_pos: Vector2, d_pos: Vector2) -> Node2D:
	var best_s: Node2D = null
	var min_d := 99999.0
	var move_to_door := signf(d_pos.x - at_pos.x)
	for s in spring_nodes:
		if is_instance_valid(s):
			var dist_x: float = (s.global_position.x - at_pos.x) * move_to_door
			if dist_x >= -25.0:
				var dist: float = at_pos.distance_to(s.global_position)
				if dist < min_d:
					min_d = dist
					best_s = s
	return best_s

func _handle_level_won() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_release_inputs()
	completed_levels += 1

	bot_status_text = "G'alaba! Eshikka halol kirdi 🎉"
	lbl_banner.text = "DARAJA %d MUVAFFAQIYATLI YAKUNLANDI!" % current_level_id
	win_banner.visible = true
	_update_hud()

	await get_tree().create_timer(0.45).timeout

	if current_level_id >= MAX_LEVELS:
		lbl_banner.text = "BARCHA 60 TA DARAJA HALOL YUTIB CHIQILDI! 🏆"
		bot_status_text = "Barcha darajalar yakunlandi!"
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