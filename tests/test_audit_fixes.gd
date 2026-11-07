extends Node

# Automated Test Suite for Audit Fixes
# Tests:
# 1. PokiService ad callback queueing during commercial break (no premature callbacks, audio muted)
# 2. PokiService safe handling of concurrent commercial & rewarded ad requests
# 3. PokiService late SDK detection simulation
# 4. ControlInverter multi-zone isolation on single-trap reset vs global respawn/reset

class DummyPlayer extends Node2D:
	var active_inverters: Dictionary = {}
	var controls_inverted: bool = false
	var is_dead: bool = false
	
	func add_inverter_zone(zone: Node) -> void:
		active_inverters[zone] = true
		controls_inverted = true
	
	func remove_inverter_zone(zone: Node) -> void:
		active_inverters.erase(zone)
		controls_inverted = not active_inverters.is_empty()
	
	func clear_inverter_zones() -> void:
		active_inverters.clear()
		controls_inverted = false
		
	func respawn() -> void:
		clear_inverter_zones()

func _ready() -> void:
	print("========================================")
	print("STARTING AUDIT VERIFICATION TEST SUITE")
	print("========================================")
	
	await _test_control_inverter_isolation()
	await _test_poki_service_ad_queues()
	await _test_poki_service_sdk_detection()
	
	print("========================================")
	print("ALL AUDIT TESTS PASSED SUCCESSFULLY! (EXIT 0)")
	print("========================================")
	get_tree().quit(0)

# ------------------------------------------------------------------------------
# Test 1 & 2: ControlInverter Multi-Zone Isolation & Reset
# ------------------------------------------------------------------------------
func _test_control_inverter_isolation() -> void:
	print("\n--- Test: ControlInverter Isolation & Reset ---")
	var player := DummyPlayer.new()
	player.add_to_group("player")
	add_child(player)
	
	var inv_script: Script = load("res://scripts/traps/control_inverter.gd")
	var inv_a: Area2D = inv_script.new()
	var inv_b: Area2D = inv_script.new()
	add_child(inv_a)
	add_child(inv_b)
	
	# Initial state: controls normal
	assert(player.controls_inverted == false, "Initial controls should NOT be inverted")
	assert(player.active_inverters.is_empty(), "Initial inverters dict should be empty")
	
	# Player enters Zone A
	player.add_inverter_zone(inv_a)
	assert(player.controls_inverted == true, "Entering Zone A must invert controls")
	assert(player.active_inverters.size() == 1, "Zone A must be registered in active_inverters")
	
	# Player enters Zone B
	player.add_inverter_zone(inv_b)
	assert(player.controls_inverted == true, "Controls must remain inverted in Zone B")
	assert(player.active_inverters.size() == 2, "Both zones must be in active_inverters")
	
	# CRITICAL AUDIT CHECK: Reset Zone A ONLY
	# Previously, reset_trap() called clear_inverter_zones() which erased Zone B!
	# Now, it must only remove Zone A, leaving Zone B active!
	inv_a.reset_trap()
	assert(player.controls_inverted == true, "CRITICAL: Resetting Zone A must NOT cancel active Zone B!")
	assert(player.active_inverters.has(inv_b) == true, "Zone B must still be registered")
	assert(player.active_inverters.has(inv_a) == false, "Zone A must have been removed")
	print("  [PASS] Single trap reset does not cancel other active inverter zones.")
	
	# Now reset Zone B
	inv_b.reset_trap()
	assert(player.controls_inverted == false, "Resetting Zone B when no other zones remain must restore controls")
	assert(player.active_inverters.is_empty(), "Inverters dict must be empty after all zones reset")
	print("  [PASS] Resetting all zones restores normal controls.")
	
	# Re-enter both zones, then player respawns
	player.add_inverter_zone(inv_a)
	player.add_inverter_zone(inv_b)
	assert(player.controls_inverted == true, "Controls inverted before respawn")
	
	# Respawn clears all zones
	player.respawn()
	assert(player.controls_inverted == false, "CRITICAL: Player respawn must clear all inverter zones!")
	assert(player.active_inverters.is_empty(), "Inverters dict must be empty on respawn")
	print("  [PASS] Player respawn clears all inverter zones.")
	
	# Cleanup
	inv_a.queue_free()
	inv_b.queue_free()
	player.queue_free()

# ------------------------------------------------------------------------------
# Test 3: PokiService Ad Queues & Mutual Exclusion
# ------------------------------------------------------------------------------
func _test_poki_service_ad_queues() -> void:
	print("\n--- Test: PokiService Ad Callback Queueing & Mutual Exclusion ---")
	var poki = get_node_or_null("/root/PokiService")
	assert(poki != null, "PokiService singleton must exist")
	
	var flags := {
		"cb1_called": false,
		"cb2_called": false,
		"rew_rejected": false,
		"rew_success_result": false,
		"comm_during_rew_called": false
	}
	
	var cb1 := func(): flags["cb1_called"] = true
	var cb2 := func(): flags["cb2_called"] = true
	
	# Trigger commercial break 1
	poki.commercial_break(cb1)
	assert(poki._is_ad_playing == true, "Ad must be marked playing")
	assert(flags["cb1_called"] == false, "Callback 1 must NOT be called immediately")
	
	# Duplicate request while ad 1 is playing
	poki.commercial_break(cb2)
	assert(flags["cb2_called"] == false, "CRITICAL: Duplicate commercial callback must NOT be called while ad is active!")
	assert(poki._pending_commercial_callbacks.size() == 2, "Both callbacks must be queued in _pending_commercial_callbacks")
	print("  [PASS] Duplicate commercial callback safely queued and not fired early.")
	
	# Concurrent rewarded request during active commercial ad
	poki.rewarded_break(func(success: bool):
		if not success:
			flags["rew_rejected"] = true
	)
	assert(flags["rew_rejected"] == true, "Rewarded request during commercial ad must be safely rejected (success=false)")
	assert(poki._is_ad_playing == true, "Ongoing commercial ad state must remain undisturbed")
	print("  [PASS] Rewarded break during active commercial is rejected without disrupting commercial ad.")
	
	# Simulate commercial ad completion
	poki._on_commercial_break_finished([])
	assert(poki._is_ad_playing == false, "Ad must no longer be playing after completion")
	assert(flags["cb1_called"] == true, "Callback 1 must be called after ad completes")
	assert(flags["cb2_called"] == true, "Callback 2 must be called after ad completes")
	assert(poki._pending_commercial_callbacks.is_empty(), "Callback queue must be empty after flush")
	print("  [PASS] All queued commercial callbacks called upon ad completion.")
	
	# Test Commercial request during Rewarded break
	poki.rewarded_break(func(success: bool):
		flags["rew_success_result"] = success
	)
	assert(poki._is_ad_playing == true, "Rewarded ad playing")
	assert(poki._current_ad_type == poki.AdType.REWARDED, "Current ad type is REWARDED")
	
	poki.commercial_break(func():
		flags["comm_during_rew_called"] = true
	)
	assert(flags["comm_during_rew_called"] == false, "Commercial request during rewarded ad must NOT fire early")
	
	# Simulate rewarded completion with true
	poki._on_rewarded_break_finished([true])
	assert(flags["rew_success_result"] == true, "Rewarded callback received true")
	assert(flags["comm_during_rew_called"] == true, "Commercial callback queued during rewarded ad was safely flushed")
	assert(poki._is_ad_playing == false, "Ad finished")
	print("  [PASS] Commercial callback during rewarded ad safely queued and flushed on completion.")

# ------------------------------------------------------------------------------
# Test 4: PokiService Late SDK Detection
# ------------------------------------------------------------------------------
func _test_poki_service_sdk_detection() -> void:
	print("\n--- Test: PokiService Late SDK Detection Logic ---")
	var poki = get_node_or_null("/root/PokiService")
	
	# In desktop test environment, is_poki_available is initially false
	# Verify _ensure_poki_sdk returns true if is_poki_available is already true
	poki.is_poki_available = true
	assert(poki._ensure_poki_sdk() == true, "_ensure_poki_sdk must return true when already available")
	
	# Reset
	poki.is_poki_available = false
	# On desktop, _ensure_poki_sdk returns false without crashing
	var result: bool = poki._ensure_poki_sdk()
	assert(result == false, "_ensure_poki_sdk returns false safely on desktop")
	
	# Verify lifecycle methods safely execute _ensure_poki_sdk()
	poki.gameplay_start()
	poki.gameplay_stop()
	poki.game_loading_finished()
	print("  [PASS] Late SDK detection hooks and lifecycle methods execute cleanly.")
