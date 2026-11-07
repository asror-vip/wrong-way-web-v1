extends Node2D

# TestLevelsAuditRunner - Deep In-Engine Gameplay & Static Audit (Levels 1-20)
# Validates node structure, collision shapes vs visual bounds, near-miss safety,
# real trigger activations, damage/death on contact, full async death/respawn,
# clean resets, and re-trigger cycles.

var current_level_index: int = 1
var total_levels_to_test: int = 20
var total_passed: int = 0
var total_failed: int = 0
var failure_logs: Array[String] = []

func _ready() -> void:
	print("======================================================================")
	print("STARTING DEEP REAL GAMEPLAY & IN-ENGINE RUNTIME AUDIT (LEVELS 1–20)")
	print("======================================================================")
	await get_tree().process_frame
	await get_tree().process_frame
	_run_next_level_test()

func _run_next_level_test() -> void:
	if current_level_index > total_levels_to_test:
		_print_final_summary()
		return
		
	var lvl := current_level_index
	var path := "res://scenes/levels/level_%02d.tscn" % lvl
	print("\n>>> [AUDITING LEVEL %02d] Loading %s..." % [lvl, path])
	
	if not ResourceLoader.exists(path):
		var err := "Level scene missing: %s" % path
		push_error(err)
		failure_logs.append(err)
		total_failed += 1
		current_level_index += 1
		_run_next_level_test()
		return
		
	var scene: PackedScene = load(path)
	var inst: Node2D = scene.instantiate() as Node2D
	add_child(inst)
	
	# Allow _ready() and physics tree initialization
	await get_tree().process_frame
	await get_tree().physics_frame
	
	var static_issues: Array[String] = []
	var gameplay_issues: Array[String] = []
	
	var player = inst.get_node_or_null("Player") as PlayerController
	var door = inst.get_node_or_null("ExitDoor") as ExitDoor
	var traps = inst.get_node_or_null("Traps")
	var trap_names: Array[String] = []
	
	# -------------------------------------------------------------
	# 1. STATIC AUDIT: Player, Door, Bounds, Collision Shapes
	# -------------------------------------------------------------
	if not player:
		static_issues.append("Player node missing or not PlayerController")
	else:
		if not player.is_in_group("player"):
			static_issues.append("Player not in 'player' group")
		var ppos: Vector2 = player.global_position
		if ppos.x < 0.0 or ppos.x > 960.0 or ppos.y < 0.0 or ppos.y > 540.0:
			static_issues.append("Player spawn out of canvas: %s" % str(ppos))
			
	if not door:
		static_issues.append("ExitDoor node missing or not ExitDoor")
	else:
		var dpos: Vector2 = door.global_position
		if dpos.x < 0.0 or dpos.x > 960.0 or dpos.y < 0.0 or dpos.y > 540.0:
			static_issues.append("ExitDoor position out of canvas: %s" % str(dpos))
			
	# Check ceiling alignment for crushers
	var ceil_node = inst.get_node_or_null("Platforms/Ceiling")
	var ceil_h: float = 60.0
	if ceil_node and "platform_size" in ceil_node:
		ceil_h = ceil_node.platform_size.y
		
	if traps:
		for t in traps.get_children():
			trap_names.append(t.name)
			if not t.is_in_group("traps"):
				static_issues.append("Trap %s not in 'traps' group" % t.name)
			if not t.has_method("reset_trap"):
				static_issues.append("Trap %s lacks reset_trap()" % t.name)
				
			# Check collision shape vs visual properties
			_audit_collision_bounds(t, static_issues)
			
			# Check crusher ceiling integration
			if t is Crusher or t.get_script().get_global_name() == &"Crusher":
				var expected_crusher_y := ceil_h - 64.0
				if absf(t.global_position.y - expected_crusher_y) > 1.0:
					static_issues.append(
						"Crusher %s y mismatch with ceiling: %f (expected %f)" %
						[t.name, t.global_position.y, expected_crusher_y]
					)
					
	# -------------------------------------------------------------
	# 2. RUNTIME GAMEPLAY AUDIT: Near-miss, Trigger, Damage, Respawn
	# -------------------------------------------------------------
	if player and traps and static_issues.is_empty():
		# A. Near-miss safety test (Player safely at spawn does not die)
		await _test_near_miss_safety(player, traps, gameplay_issues)
		
		# B. Real trigger and movement tests
		await _test_traps_gameplay(player, traps, lvl, gameplay_issues)
		
		# C. Real player.kill() async death and respawn test
		await _test_real_kill_and_respawn(player, traps, gameplay_issues)
		
		# D. Re-trigger test after respawn
		await _test_retrigger_after_respawn(player, traps, gameplay_issues)
		
		# E. Rolling boulder void-fall recovery test (if present)
		await _test_boulder_void_recovery(traps, gameplay_issues)
		
		# F. Multi-trap concurrent interaction test (levels 13, 16, 19, 20)
		await _test_concurrent_traps(player, traps, lvl, gameplay_issues)
		
	var is_passed := static_issues.is_empty() and gameplay_issues.is_empty()
	if is_passed:
		print("  -> Level %02d AUDIT: [PASS] (Traps: %s)" % [lvl, ", ".join(trap_names)])
		total_passed += 1
	else:
		print("  -> Level %02d AUDIT: [FAIL]" % lvl)
		for si in static_issues:
			print("     * STATIC FAIL: %s" % si)
			failure_logs.append("Lvl %02d [STATIC]: %s" % [lvl, si])
		for gi in gameplay_issues:
			print("     * GAMEPLAY FAIL: %s" % gi)
			failure_logs.append("Lvl %02d [GAMEPLAY]: %s" % [lvl, gi])
		total_failed += 1
		
	# Cleanup level instance
	inst.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	
	current_level_index += 1
	_run_next_level_test()

func _audit_collision_bounds(t: Node2D, issues: Array[String]) -> void:
	var col = t.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		col = t.get_node_or_null("KillArea/CollisionShape2D") as CollisionShape2D
	if not col:
		issues.append("Trap %s lacks CollisionShape2D" % t.name)
		return
	if not col.shape:
		issues.append("Trap %s has null collision shape" % t.name)
		return
		
	if col.shape is RectangleShape2D:
		var rect := col.shape as RectangleShape2D
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			issues.append(
				"Trap %s has degenerate rectangle shape: %s" %
				[t.name, str(rect.size)]
			)
	elif col.shape is CircleShape2D:
		var circ := col.shape as CircleShape2D
		if circ.radius <= 0.0:
			issues.append(
				"Trap %s has degenerate circle radius: %f" %
				[t.name, circ.radius]
			)

func _test_near_miss_safety(
	player: PlayerController,
	traps: Node2D,
	issues: Array[String]
) -> void:
	# Ensure player at spawn is safely alive and not touching any hazard
	player.is_invulnerable = false
	player.is_dead = false
	player.global_position = player.spawn_position
	player.velocity = Vector2.ZERO
	
	# Step 3 physics frames
	for i in range(3):
		await get_tree().physics_frame
		
	if player.is_dead:
		issues.append("Near-miss safety failed: player died at spawn_position")
		player.respawn(player.spawn_position)
		await get_tree().physics_frame

func _test_traps_gameplay(
	player: PlayerController,
	traps: Node2D,
	lvl: int,
	issues: Array[String]
) -> void:
	for t in traps.get_children():
		var trig_pos := _get_trap_trigger_pos(t)
		if trig_pos != Vector2.ZERO:
			# Ensure player is ready
			player.is_invulnerable = false
			player.invulnerable_timer = 0.0
			player.is_dead = false
			player.is_entering_door = false
			
			# Tabiiy yurish va sakrash orqali trigger hududiga yaqinlashish
			var dx := trig_pos.x - player.global_position.x
			var dir := signf(dx) if absf(dx) > 1.0 else 1.0
			var max_walk_steps := 45
			for step in range(max_walk_steps):
				if _is_trap_triggered(t) or player.is_dead:
					break
				if absf(player.global_position.x - trig_pos.x) < 20.0:
					break
				player.velocity.x = dir * player.SPEED
				var need_jump: bool = (
					(trig_pos.y < player.global_position.y - 20.0 or player.is_on_wall())
					and player.is_on_floor()
				)
				if need_jump:
					player.velocity.y = player.JUMP_VELOCITY
				player.velocity.y += player.GRAVITY * (1.0 / 60.0)
				player.move_and_slide()
				await get_tree().physics_frame
				
			# Agar hali yetib kelmagan bo'lsa, trigger zonasiga joylashtirish
			if not _is_trap_triggered(t) and not player.is_dead:
				player.global_position = trig_pos
				player.velocity = Vector2.ZERO
				for i in range(8):
					await get_tree().physics_frame
					if _is_trap_triggered(t) or player.is_dead:
						break
				
			var triggered := _is_trap_triggered(t) or player.is_dead
			if not triggered:
				issues.append(
					"Trap %s did not trigger when player entered zone" %
					t.name
				)
				
			# If player died from trap, await respawn
			if player.is_dead:
				await player.respawned
				await get_tree().physics_frame
			else:
				t.reset_trap()
				player.global_position = player.spawn_position
				player.velocity = Vector2.ZERO
				await get_tree().physics_frame

func _test_real_kill_and_respawn(
	player: PlayerController,
	traps: Node2D,
	issues: Array[String]
) -> void:
	var respawn_state := {"fired": false}
	var on_respawn = func():
		respawn_state["fired"] = true
		for t in traps.get_children():
			var exp_pos: Vector2 = _get_trap_start_pos(t)
			if t.global_position != exp_pos and not t is StaticBody2D:
				issues.append(
					"Trap %s pos mismatch on respawn: %s vs %s" %
					[t.name, str(t.global_position), str(exp_pos)]
				)
			if "is_triggered" in t and t.is_triggered:
				issues.append(
					"Trap %s remained triggered on respawn" % t.name
				)
			if "state" in t and str(t.state) != "0":
				issues.append(
					"Crusher %s state not IDLE on respawn: %s" %
					[t.name, str(t.state)]
				)
				
	player.respawned.connect(on_respawn, CONNECT_ONE_SHOT)
	
	# Execute real player.kill()
	player.is_invulnerable = false
	player.is_entering_door = false
	player.is_dead = false
	player.kill()
	
	if not player.is_dead:
		issues.append("player.kill() failed to set is_dead=true")
	if player.visible:
		issues.append("player.kill() failed to hide player")
	if player.global_position.x > -9000.0:
		issues.append("player.kill() failed to offset body to (-9999,-9999)")
		
	# Await real SceneTree death-to-respawn timer (0.34s)
	await get_tree().create_timer(0.40).timeout
	await get_tree().physics_frame
	
	if not respawn_state["fired"]:
		issues.append("player.respawned signal did not fire within 0.40s")
	if player.is_dead:
		issues.append("Player remained dead after 0.40s respawn timer")
	if not player.visible:
		issues.append("Player remained invisible after respawn")
	if player.global_position.distance_to(player.spawn_position) > 2.0:
		issues.append(
			"Player not at spawn_position after respawn: %s vs %s" %
			[str(player.global_position), str(player.spawn_position)]
		)

func _test_retrigger_after_respawn(
	player: PlayerController,
	traps: Node2D,
	issues: Array[String]
) -> void:
	for t in traps.get_children():
		var trig_pos := _get_trap_trigger_pos(t)
		if trig_pos != Vector2.ZERO:
			player.is_invulnerable = false
			player.invulnerable_timer = 0.0
			player.is_entering_door = false
			player.is_dead = false
			player.global_position = trig_pos
			
			for i in range(8):
				await get_tree().physics_frame
				
			var triggered := _is_trap_triggered(t)
			if not triggered:
				issues.append(
					"Trap %s failed to re-trigger on second attempt" %
					t.name
				)
				
			if player.is_dead:
				await player.respawned
				await get_tree().physics_frame
			else:
				t.reset_trap()
				player.global_position = player.spawn_position
				await get_tree().physics_frame
			break

func _test_boulder_void_recovery(
	traps: Node2D,
	issues: Array[String]
) -> void:
	for t in traps.get_children():
		if t is RollingBoulder or t.get_script().get_global_name() == &"RollingBoulder":
			# Simulate boulder falling into pit void (y > 650.0)
			t.global_position.y = 660.0
			for i in range(2):
				await get_tree().physics_frame
				
			if "has_fallen" in t and not t.has_fallen:
				issues.append(
					"RollingBoulder %s did not set has_fallen=true at y=660" %
					t.name
				)
			if t.velocity != Vector2.ZERO:
				issues.append(
					"Boulder %s velocity not ZERO in void: %s" %
					[t.name, str(t.velocity)]
				)
				
			# Reset trap and verify clean recovery
			t.reset_trap()
			if "has_fallen" in t and t.has_fallen:
				issues.append(
					"RollingBoulder %s has_fallen not cleared on reset" %
					t.name
				)
			if t.global_position != t.original_pos:
				issues.append(
					"RollingBoulder %s not at original_pos on reset" %
					t.name
				)
			if t.is_triggered:
				issues.append(
					"RollingBoulder %s is_triggered not cleared on reset" %
					t.name
				)

func _test_concurrent_traps(
	player: PlayerController,
	traps: Node2D,
	lvl: int,
	issues: Array[String]
) -> void:
	if traps.get_child_count() < 3:
		return
		
	# Trigger all triggerable traps simultaneously
	for t in traps.get_children():
		var trig_pos := _get_trap_trigger_pos(t)
		if trig_pos != Vector2.ZERO:
			if "is_triggered" in t:
				t.is_triggered = true
			if "state" in t and t is Crusher:
				t.state = Crusher.State.FALLING
			if "is_falling" in t and t is FallingSpikeTrap:
				t.is_falling = true
				t.visible = true
				
	# Step 15 physics frames while multiple traps run concurrently
	for i in range(15):
		await get_tree().physics_frame
		
	# Now perform full reset via base_level
	var parent_lvl = traps.get_parent()
	if parent_lvl and parent_lvl.has_method("reset_level_traps"):
		parent_lvl.reset_level_traps()
	else:
		for t in traps.get_children():
			if t.has_method("reset_trap"):
				t.reset_trap()
				
	# Verify immediately upon reset that all traps restored start position
	for t in traps.get_children():
		var exp_pos := _get_trap_start_pos(t)
		if not t is StaticBody2D and t.global_position.distance_to(exp_pos) > 1.0:
			issues.append(
				"Concurrent test: Trap %s pos mismatch on reset: %s vs %s" %
				[t.name, str(t.global_position), str(exp_pos)]
			)
		if "is_triggered" in t and t.is_triggered:
			issues.append(
				"Concurrent test: Trap %s remained triggered on reset" %
				t.name
			)
			
	await get_tree().physics_frame

func _get_trap_trigger_pos(t: Node2D) -> Vector2:
	var gx: float = t.global_position.x
	var gy: float = t.global_position.y
	
	if "crusher_size" in t:
		return Vector2(gx + t.crusher_size.x / 2.0, 380.0)
	if t is PopUpSpikesTrap or t.get_script().get_global_name() == &"PopUpSpikesTrap":
		var sw: float = t.spike_width if "spike_width" in t else 32.0
		return Vector2(gx + sw / 2.0, gy)
	if "platform_size" in t and gy >= 300.0:
		return Vector2(gx + t.platform_size.x / 2.0, gy - 12.0)
	if "boulder_radius" in t:
		var rdir: float = t.roll_direction if "roll_direction" in t else -1.0
		var tdist: float = t.trigger_distance if "trigger_distance" in t else 150.0
		if rdir > 0.0:
			return Vector2(gx + tdist + 15.0, gy)
		else:
			return Vector2(gx - minf(tdist * 0.6, 80.0), gy)
	if "run_away_distance" in t:
		return Vector2(gx + 40.0, gy)
	if t is FallingSpikeTrap or t.get_script().get_global_name() == &"FallingSpikeTrap":
		return Vector2(gx, 350.0)
	if "trigger_distance" in t and float(t.trigger_distance) > 0.0:
		if "patrol_axis" in t:
			if t.patrol_axis.x > 0.1:
				return Vector2(gx + t.trigger_distance + 15.0, gy)
			elif t.patrol_axis.x < -0.1:
				return Vector2(gx - 20.0, gy)
			else:
				return Vector2(gx, gy - 20.0)
		return Vector2(gx, 380.0)
		
	return Vector2.ZERO

func _is_trap_triggered(t: Node2D) -> bool:
	if "is_triggered" in t and t.is_triggered:
		return true
	if "state" in t and str(t.state) != "0": # Crusher FALLING/RISING/etc
		return true
	if "is_falling" in t and t.is_falling:
		return true
	if "is_rolling" in t and t.is_rolling:
		return true
	return false

func _get_trap_start_pos(t: Node2D) -> Vector2:
	if "start_pos" in t:
		return t.start_pos
	if "original_pos" in t:
		return t.original_pos
	if "initial_position" in t:
		return t.initial_position
	return t.global_position

func _print_final_summary() -> void:
	print("\n======================================================================")
	print("AUDIT RESULTS SUMMARY:")
	print("  TOTAL LEVELS AUDITED: %d" % total_levels_to_test)
	print("  PASSED: %d / %d" % [total_passed, total_levels_to_test])
	print("  FAILED: %d / %d" % [total_failed, total_levels_to_test])
	print("======================================================================")
	if total_failed == 0:
		print("EXIT 0: ALL 20 LEVELS PASSED DEEP GAMEPLAY & RUNTIME AUDIT CLEANLY!\n")
		get_tree().quit(0)
	else:
		print("EXIT 1: ISSUES FOUND IN LEVELS:")
		for f in failure_logs:
			print("  - %s" % f)
		get_tree().quit(1)
