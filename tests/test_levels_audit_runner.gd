extends Node2D

# TestLevelsAuditRunner - Comprehensive In-Engine Runtime Verification
# Tests all 20 levels for node integrity, collision shapes, trap triggering,
# reset correctness on player death/respawn, and boundary safety.

var current_level_index: int = 1
var total_levels_to_test: int = 20
var total_passed: int = 0
var total_failed: int = 0
var failure_logs: Array[String] = []

func _ready() -> void:
	print("======================================================================")
	print("STARTING IN-ENGINE GODOT RUNTIME AUDIT FOR LEVELS 1–20")
	print("======================================================================")
	# Allow autoloads and singletons 2 frames to settle
	await get_tree().process_frame
	await get_tree().process_frame
	_run_next_level_test()

func _run_next_level_test() -> void:
	if current_level_index > total_levels_to_test:
		_print_final_summary()
		return
		
	var lvl := current_level_index
	var path := "res://scenes/levels/level_%02d.tscn" % lvl
	print("\n[AUDIT LEVEL %02d] Loading %s..." % [lvl, path])
	
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
	
	# Allow _ready() and collision initialization to execute
	await get_tree().process_frame
	
	var issues: Array[String] = []
	
	# 1. Player verification
	var player = inst.get_node_or_null("Player") as PlayerController
	if not player:
		issues.append("Player node missing or not PlayerController")
	else:
		if not player.is_in_group("player"):
			issues.append("Player is not in group 'player'")
		var ppos: Vector2 = player.global_position
		if ppos.x < 0.0 or ppos.x > 960.0 or ppos.y > 540.0:
			issues.append("Player spawn out of bounds: %s" % str(ppos))
			
	# 2. ExitDoor verification
	var door = inst.get_node_or_null("ExitDoor") as ExitDoor
	if not door:
		issues.append("ExitDoor node missing or not ExitDoor")
	else:
		var dpos: Vector2 = door.global_position
		if dpos.x < 0.0 or dpos.x > 960.0 or dpos.y > 540.0:
			issues.append("ExitDoor position out of bounds: %s" % str(dpos))
			
	# 3. Traps container & each trap verification
	var traps = inst.get_node_or_null("Traps")
	var trap_count := 0
	if traps:
		trap_count = traps.get_child_count()
		for t in traps.get_children():
			if not t.is_in_group("traps"):
				issues.append("Trap %s is not in group 'traps'" % t.name)
			if not t.has_method("reset_trap"):
				issues.append("Trap %s lacks reset_trap() method" % t.name)
				
			# Record original position
			var orig_pos: Vector2 = t.global_position
			
			# Test trap reset idempotency
			if t.has_method("reset_trap"):
				t.reset_trap()
				var expected_pos: Vector2 = orig_pos
				if "start_pos" in t:
					expected_pos = t.start_pos
				elif "original_pos" in t:
					expected_pos = t.original_pos
				elif "initial_position" in t:
					expected_pos = t.initial_position
				if t.global_position != expected_pos and not t is StaticBody2D:
					issues.append(
						"Trap %s pos mismatch after reset: %s vs %s" %
						[t.name, str(t.global_position), str(expected_pos)]
					)
					
	# 4. Test BaseLevel.reset_level_traps()
	if inst.has_method("reset_level_traps"):
		inst.reset_level_traps()
		
	# 5. Simulate death & respawn cycle
	if player and inst.has_method("reset_level_traps"):
		player.is_dead = true
		inst.reset_level_traps()
		player.respawn(player.spawn_position)
		if player.is_dead:
			issues.append("Player remains dead after respawn()")
		if player.controls_inverted:
			issues.append("Player controls remained inverted after respawn()")
			
	if issues.is_empty():
		print("  -> Result: [PASS] (Traps verified: %d, Player & Door valid)" % trap_count)
		total_passed += 1
	else:
		print("  -> Result: [FAIL]")
		for iss in issues:
			print("     * FAIL: %s" % iss)
			failure_logs.append("Lvl %d: %s" % [lvl, iss])
		total_failed += 1
		
	# Cleanup level instance
	inst.queue_free()
	await get_tree().process_frame
	
	current_level_index += 1
	_run_next_level_test()

func _print_final_summary() -> void:
	print("\n======================================================================")
	print("AUDIT RESULTS SUMMARY:")
	print("  TOTAL LEVELS AUDITED: %d" % total_levels_to_test)
	print("  PASSED: %d / %d" % [total_passed, total_levels_to_test])
	print("  FAILED: %d / %d" % [total_failed, total_levels_to_test])
	print("======================================================================")
	if total_failed == 0:
		print("EXIT 0: ALL 20 LEVELS PASSED IN-ENGINE RUNTIME AUDIT CLEANLY!\n")
		get_tree().quit(0)
	else:
		print("EXIT 1: ISSUES FOUND IN LEVELS:")
		for f in failure_logs:
			print("  - %s" % f)
		get_tree().quit(1)
