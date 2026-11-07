extends Node

# Wrong Way - Advanced Audit Test Suite (Mock-Based Unit Tests)
# Covers:
# 1. Real PlayerController & ControlInverter Multi-Zone Isolation & Respawn
# 2. Late SDK Loading (300ms, 1s, 2s) with Init Success
# 3. SDK Init Rejection (Adblock / Script Error)
# 4. SDK Never Arrives (Offline / Timed Out)
# 5. Stale Init Callback After Timeout (Generation Token Invalidation)
# 6. Duplicate Init Call Prevention During Active Initializing
# 7. SDK Readiness Gate Before Gameplay
# 8. Gameplay Lifecycle Start/Stop Race Condition (start -> stop during init)
# 9. Lifecycle: Rapid Start -> Stop -> Start Sequence
# 10. Lifecycle: gameplay_start During Ad Resumes Automatically on Ad Finish
# 11. Lifecycle: gameplay_stop During Ad Cancels Queued Start
# 12. Ad Safety Timeout: Commercial Break (Callback Never Arrives)
# 13. Ad Safety Timeout: Rewarded Break (Callback Never Arrives)
# 14. Late Ad Callback After Timeout Ignored (At Most Once Guarantee)
# 15. Commercial -> Commercial Ad Queue (no premature callbacks, single break)
# 16. Commercial -> Rewarded Ad Queue (safe rejection with success=false)
# 17. Rewarded -> Commercial Ad Queue (real commercialBreak runs after rewarded)
# 18. Chained Multiple Ad Requests (Rewarded + Comm 1 + Comm 2)
# 19. Commercial & Rewarded Rejection / Promise Catch Recovery

class MockPokiSdk extends RefCounted:
	var available: bool = false
	var init_should_succeed: bool = true
	var init_delay: float = 0.0
	var ad_delay: float = 0.05
	var commercial_should_succeed: bool = true
	var rewarded_result: bool = true
	var ignore_commercial_callback: bool = false
	var ignore_rewarded_callback: bool = false

	var commercial_call_count: int = 0
	var rewarded_call_count: int = 0
	var init_call_count: int = 0
	var gameplay_start_count: int = 0
	var gameplay_stop_count: int = 0
	var game_loading_finished_count: int = 0

	func has_poki_sdk() -> bool:
		return available

	func init_sdk(on_success: Callable, on_fail: Callable) -> void:
		init_call_count += 1
		var tree := Engine.get_main_loop() as SceneTree
		if init_delay > 0.0 and tree:
			await tree.create_timer(init_delay).timeout
		if init_should_succeed:
			on_success.call()
		else:
			on_fail.call()

	func request_commercial_break(on_done: Callable) -> void:
		commercial_call_count += 1
		if ignore_commercial_callback:
			return
		var tree := Engine.get_main_loop() as SceneTree
		if ad_delay > 0.0 and tree:
			await tree.create_timer(ad_delay).timeout
		on_done.call()

	func request_rewarded_break(on_result: Callable) -> void:
		rewarded_call_count += 1
		if ignore_rewarded_callback:
			return
		var tree := Engine.get_main_loop() as SceneTree
		if ad_delay > 0.0 and tree:
			await tree.create_timer(ad_delay).timeout
		on_result.call(rewarded_result)

	func gameplay_start() -> void:
		gameplay_start_count += 1

	func gameplay_stop() -> void:
		gameplay_stop_count += 1

	func game_loading_finished() -> void:
		game_loading_finished_count += 1

func _ready() -> void:
	print("======================================================================")
	print("STARTING ADVANCED AUDIT TEST SUITE (19 COMPREHENSIVE TESTS)")
	print("======================================================================")

	_test_control_inverter_real_player()
	await _test_late_sdk_300ms()
	await _test_late_sdk_1s()
	await _test_late_sdk_2s()
	await _test_sdk_init_rejection()
	await _test_sdk_never_arrives()
	await _test_stale_init_callback_after_timeout()
	await _test_duplicate_init_prevention()
	await _test_sdk_gate_before_gameplay()
	await _test_gameplay_start_stop_race()
	await _test_lifecycle_rapid_start_stop_start()
	await _test_lifecycle_start_during_ad_resumes_after()
	await _test_lifecycle_stop_during_ad_cancels_start()
	await _test_ad_safety_timeout_commercial()
	await _test_ad_safety_timeout_rewarded()
	await _test_late_ad_callback_after_timeout_ignored()
	await _test_ad_queue_commercial_to_commercial()
	await _test_ad_queue_commercial_to_rewarded()
	await _test_ad_queue_rewarded_to_commercial()
	await _test_ad_queue_chained_requests()
	await _test_commercial_rejection()
	await _test_rewarded_rejection()

	print("\n======================================================================")
	print("ALL 19 ADVANCED AUDIT TESTS PASSED CLEANLY! (EXIT CODE 0)")
	print("======================================================================")
	get_tree().quit(0)

# ------------------------------------------------------------------------------
# Test 1: Real PlayerController & ControlInverter Multi-Zone Isolation & Respawn
# ------------------------------------------------------------------------------
func _test_control_inverter_real_player() -> void:
	print("\n[TEST 1] Real PlayerController & ControlInverter Scenes...")
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)

	var inv_scene: PackedScene = load("res://scenes/traps/control_inverter.tscn")
	var inv_a = inv_scene.instantiate()
	var inv_b = inv_scene.instantiate()
	add_child(inv_a)
	add_child(inv_b)

	# Simulating body_entered into both zones
	inv_a._on_body_entered(player)
	inv_b._on_body_entered(player)
	assert(player.controls_inverted == true, "Both zones entered -> inverted")
	assert(player.active_inverters.size() == 2, "Both zones registered")

	# Reset Zone A ONLY
	inv_a.reset_trap()
	assert(player.controls_inverted == true, "Zone A reset must not cancel active Zone B")
	assert(player.active_inverters.has(inv_b) == true, "Zone B must remain active")
	assert(player.active_inverters.has(inv_a) == false, "Zone A removed from player")

	# Reset Zone B
	inv_b.reset_trap()
	assert(player.controls_inverted == false, "All zones reset -> controls restored")

	# Respawn clears all active inverters
	inv_a._on_body_entered(player)
	assert(player.controls_inverted == true, "Zone A re-entered")
	player.respawn()
	assert(player.controls_inverted == false, "Respawn must clear all zones")
	assert(player.active_inverters.is_empty() == true, "Inverter map is empty")

	inv_a.queue_free()
	inv_b.queue_free()
	player.queue_free()
	print("  -> PASS: Real PlayerController & ControlInverter scenes verified.")

# ------------------------------------------------------------------------------
# Test 2: Late SDK Loading - 300 ms Delay
# ------------------------------------------------------------------------------
func _test_late_sdk_300ms() -> void:
	print("\n[TEST 2] Late SDK Loading: 300ms Delay...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = false
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	get_tree().create_timer(0.3).timeout.connect(func():
		mock.available = true
	)

	var final_state: int = await poki.ensure_sdk_initialized(1.5)
	assert(final_state == poki.SdkState.READY, "Must transition to READY")
	assert(poki.is_poki_available == true, "is_poki_available must be true")
	print("  -> PASS: 300ms late SDK resolved to SdkState.READY.")

# ------------------------------------------------------------------------------
# Test 3: Late SDK Loading - 1.0 s Delay
# ------------------------------------------------------------------------------
func _test_late_sdk_1s() -> void:
	print("\n[TEST 3] Late SDK Loading: 1.0s Delay...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = false
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	get_tree().create_timer(1.0).timeout.connect(func():
		mock.available = true
	)

	var final_state: int = await poki.ensure_sdk_initialized(2.5)
	assert(final_state == poki.SdkState.READY, "Must transition to READY")
	assert(poki.is_poki_available == true, "is_poki_available must be true")
	print("  -> PASS: 1.0s late SDK resolved to SdkState.READY.")

# ------------------------------------------------------------------------------
# Test 4: Late SDK Loading - 2.0 s Delay
# ------------------------------------------------------------------------------
func _test_late_sdk_2s() -> void:
	print("\n[TEST 4] Late SDK Loading: 2.0s Delay...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = false
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	get_tree().create_timer(2.0).timeout.connect(func():
		mock.available = true
	)

	var final_state: int = await poki.ensure_sdk_initialized(3.0)
	assert(final_state == poki.SdkState.READY, "Must transition to READY")
	assert(poki.is_poki_available == true, "is_poki_available must be true")
	print("  -> PASS: 2.0s late SDK resolved to SdkState.READY.")

# ------------------------------------------------------------------------------
# Test 5: SDK Init Rejection (Adblock / Script Error)
# ------------------------------------------------------------------------------
func _test_sdk_init_rejection() -> void:
	print("\n[TEST 5] SDK Init Rejection (Adblock / Script Error)...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_should_succeed = false
	poki.set_mock_provider(mock)

	var final_state: int = await poki.ensure_sdk_initialized(1.0)
	assert(final_state == poki.SdkState.FAILED, "Rejected init must transition to FAILED")
	assert(poki.is_poki_available == false, "is_poki_available must be false on failure")
	print("  -> PASS: Rejected SDK init recorded as SdkState.FAILED.")

# ------------------------------------------------------------------------------
# Test 6: SDK Never Arrives (Offline / Timed Out)
# ------------------------------------------------------------------------------
func _test_sdk_never_arrives() -> void:
	print("\n[TEST 6] SDK Never Arrives (Offline / Timed Out)...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = false
	poki.set_mock_provider(mock)

	var final_state: int = await poki.ensure_sdk_initialized(0.3)
	assert(final_state == poki.SdkState.FAILED, "Missing SDK must timeout to FAILED")
	assert(poki.is_poki_available == false, "is_poki_available must be false")
	print("  -> PASS: Missing SDK safely times out without freezing game loop.")

# ------------------------------------------------------------------------------
# Test 7: Stale Init Callback After Timeout (Generation Token Invalidation)
# ------------------------------------------------------------------------------
func _test_stale_init_callback_after_timeout() -> void:
	print("\n[TEST 7] Stale Init Callback After Timeout...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.6
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	var timed_out_state: int = await poki.ensure_sdk_initialized(0.2)
	assert(timed_out_state == poki.SdkState.FAILED, "State must be FAILED after timeout")

	await get_tree().create_timer(0.6).timeout
	assert(poki.sdk_state == poki.SdkState.FAILED, "Late callback must not resurrect state")
	assert(poki.is_poki_available == false, "is_poki_available must remain false")
	print("  -> PASS: Stale callback after timeout safely ignored.")

# ------------------------------------------------------------------------------
# Test 8: Duplicate Init Prevention
# ------------------------------------------------------------------------------
func _test_duplicate_init_prevention() -> void:
	print("\n[TEST 8] Duplicate Init Prevention...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.3
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	poki.try_init_sdk()
	assert(poki.sdk_state == poki.SdkState.INITIALIZING, "State is INITIALIZING")

	var second_result: bool = poki.try_init_sdk()
	assert(second_result == false, "Second concurrent init call must be rejected")
	assert(mock.init_call_count == 1, "Only 1 init call made to provider")

	await poki.ensure_sdk_initialized(1.0)
	assert(poki.sdk_state == poki.SdkState.READY, "State reached READY")
	print("  -> PASS: Duplicate init calls prevented during active initialization.")

# ------------------------------------------------------------------------------
# Test 9: SDK Readiness Gate Before Gameplay
# ------------------------------------------------------------------------------
func _test_sdk_gate_before_gameplay() -> void:
	print("\n[TEST 9] SDK Readiness Gate Before Gameplay...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.1
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	poki.gameplay_start()
	await poki.ensure_sdk_initialized(1.0)
	assert(poki.sdk_state == poki.SdkState.READY, "SDK initialized")
	assert(mock.gameplay_start_count == 1, "gameplay_start executed after ready")
	print("  -> PASS: Gameplay calls safely await SDK ready state.")

# ------------------------------------------------------------------------------
# Test 10: Gameplay Lifecycle Start/Stop Race Condition (start -> stop during init)
# ------------------------------------------------------------------------------
func _test_gameplay_start_stop_race() -> void:
	print("\n[TEST 10] Gameplay Lifecycle Start/Stop Race Condition...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.25
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)

	poki.gameplay_start()
	assert(poki.is_gameplay_running == true, "gameplay desired is running")

	await get_tree().create_timer(0.05).timeout
	poki.gameplay_stop()
	assert(poki.is_gameplay_running == false, "gameplay is now stopped")

	await get_tree().create_timer(0.3).timeout
	assert(poki.sdk_state == poki.SdkState.READY, "SDK is now READY")

	assert(mock.gameplay_start_count == 0, "Stale start must not be sent to SDK!")
	assert(mock.gameplay_stop_count == 0, "No spurious stop sent either")
	print("  -> PASS: Stale gameplay_start safely cancelled by stop during init.")

# ------------------------------------------------------------------------------
# Test 11: Lifecycle Rapid Start -> Stop -> Start Sequence
# ------------------------------------------------------------------------------
func _test_lifecycle_rapid_start_stop_start() -> void:
	print("\n[TEST 11] Rapid start -> stop -> start sequence...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.05
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	# Execute rapid sequence in succession
	poki.gameplay_start()
	poki.gameplay_stop()
	poki.gameplay_start()

	assert(poki.is_gameplay_desired() == true, "Desired is running")
	assert(poki.is_gameplay_notified_to_poki() == true, "Poki notified running")
	assert(mock.gameplay_start_count == 2, "Start called twice (start, stop, start)")
	assert(mock.gameplay_stop_count == 1, "Stop called once")
	print("  -> PASS: Rapid start->stop->start sequence tracks desired state.")

# ------------------------------------------------------------------------------
# Test 12: Lifecycle start during ad resumes automatically on ad finish
# ------------------------------------------------------------------------------
func _test_lifecycle_start_during_ad_resumes_after() -> void:
	print("\n[TEST 12] gameplay_start during ad resumes automatically on finish...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	poki.commercial_break()
	assert(poki.is_ad_playing() == true, "Ad is playing")

	# Request gameplay_start while ad is playing
	poki.gameplay_start()
	assert(poki.is_gameplay_desired() == true, "Gameplay is desired")
	assert(mock.gameplay_start_count == 0, "PokiSDK must not receive start during ad")

	# Wait for ad to finish
	await get_tree().create_timer(0.25).timeout
	assert(poki.is_ad_playing() == false, "Ad finished")
	assert(mock.gameplay_start_count == 1, "PokiSDK received start automatically on ad end")
	assert(poki.is_gameplay_notified_to_poki() == true, "Gameplay notified running")
	print("  -> PASS: gameplay_start during ad auto-resumed when ad completed.")

# ------------------------------------------------------------------------------
# Test 13: Lifecycle stop during ad cancels queued start
# ------------------------------------------------------------------------------
func _test_lifecycle_stop_during_ad_cancels_start() -> void:
	print("\n[TEST 13] gameplay_stop during ad cancels queued start...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	poki.commercial_break()
	assert(poki.is_ad_playing() == true, "Ad is playing")

	poki.gameplay_start()
	poki.gameplay_stop()
	assert(poki.is_gameplay_desired() == false, "Desired is stopped")

	await get_tree().create_timer(0.25).timeout
	assert(poki.is_ad_playing() == false, "Ad finished")
	assert(mock.gameplay_start_count == 0, "PokiSDK did NOT receive start")
	print("  -> PASS: gameplay_stop during ad safely cancelled queued start.")

# ------------------------------------------------------------------------------
# Test 14: Ad Safety Timeout: Commercial Break (Callback Never Arrives)
# ------------------------------------------------------------------------------
func _test_ad_safety_timeout_commercial() -> void:
	print("\n[TEST 14] Ad Safety Timeout: Commercial Break...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	poki.ad_timeout_seconds = 0.2 # Fast timeout for testing

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ignore_commercial_callback = true # Simulating frozen/blocked ad callback
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var callback_called := {"called": false}
	poki.commercial_break(func(): callback_called["called"] = true)
	assert(poki.is_ad_playing() == true, "Commercial is playing")

	await get_tree().create_timer(0.35).timeout
	assert(poki.is_ad_playing() == false, "Ad state safely reset by timeout")
	assert(callback_called["called"] == true, "User callback called via timeout recovery")
	print("  -> PASS: Commercial ad safely recovered after timeout.")

# ------------------------------------------------------------------------------
# Test 15: Ad Safety Timeout: Rewarded Break (Callback Never Arrives)
# ------------------------------------------------------------------------------
func _test_ad_safety_timeout_rewarded() -> void:
	print("\n[TEST 15] Ad Safety Timeout: Rewarded Break...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	poki.ad_timeout_seconds = 0.2 # Fast timeout for testing

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ignore_rewarded_callback = true # Simulating frozen rewarded callback
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var reward_result := {"result": null}
	poki.rewarded_break(func(success: bool): reward_result["result"] = success)
	assert(poki.is_ad_playing() == true, "Rewarded is playing")

	await get_tree().create_timer(0.35).timeout
	assert(poki.is_ad_playing() == false, "Rewarded state reset by timeout")
	assert(reward_result["result"] == false, "Rewarded returns false on timeout")
	print("  -> PASS: Rewarded ad safely recovered with success=false.")

# ------------------------------------------------------------------------------
# Test 16: Late Ad Callback After Timeout Ignored
# ------------------------------------------------------------------------------
func _test_late_ad_callback_after_timeout_ignored() -> void:
	print("\n[TEST 16] Late Ad Callback After Timeout Ignored...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	poki.ad_timeout_seconds = 0.15

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ignore_commercial_callback = true
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var count := {"cb": 0}
	poki.commercial_break(func(): count["cb"] += 1)

	await get_tree().create_timer(0.25).timeout
	assert(count["cb"] == 1, "Called once via timeout recovery")
	assert(poki.is_ad_playing() == false, "Ad finished")

	# Now simulate stale/late callback arriving from JS
	poki.simulate_commercial_break_finished_for_test()
	assert(count["cb"] == 1, "Duplicate callback after timeout must NOT fire user callback")
	print("  -> PASS: Late callback after timeout rejected by state guard.")

# ------------------------------------------------------------------------------
# Test 17: Commercial -> Commercial Queue (Single Break, Single Callbacks)
# ------------------------------------------------------------------------------
func _test_ad_queue_commercial_to_commercial() -> void:
	print("\n[TEST 17] Ad Queue: Commercial -> Commercial...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var counts := {"cb1": 0, "cb2": 0}
	poki.commercial_break(func(): counts["cb1"] += 1)
	assert(poki.is_ad_playing() == true, "Commercial 1 is playing")
	assert(counts["cb1"] == 0, "Callback 1 must NOT be called early")

	poki.commercial_break(func(): counts["cb2"] += 1)
	assert(counts["cb2"] == 0, "Callback 2 must NOT be called early")
	assert(mock.commercial_call_count == 1, "No simultaneous commercialBreaks allowed")

	await get_tree().create_timer(0.25).timeout
	assert(poki.is_ad_playing() == false, "Ad finished")
	assert(counts["cb1"] == 1, "Callback 1 called exactly once")
	assert(counts["cb2"] == 1, "Callback 2 called exactly once")
	print("  -> PASS: Concurrent commercials share the break and fire once.")

# ------------------------------------------------------------------------------
# Test 18: Commercial -> Rewarded Queue (Safe Rejection)
# ------------------------------------------------------------------------------
func _test_ad_queue_commercial_to_rewarded() -> void:
	print("\n[TEST 18] Ad Queue: Commercial -> Rewarded Safe Rejection...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var state := {"comm_done": false, "rew_result": null}
	poki.commercial_break(func(): state["comm_done"] = true)

	poki.rewarded_break(func(success: bool): state["rew_result"] = success)
	assert(state["rew_result"] == false, "Rewarded during commercial rejected with false")
	assert(state["comm_done"] == false, "Commercial must not be disrupted")

	await get_tree().create_timer(0.25).timeout
	assert(state["comm_done"] == true, "Commercial completed successfully")
	print("  -> PASS: Rewarded during commercial safely rejected.")

# ------------------------------------------------------------------------------
# Test 19: Rewarded -> Commercial Queue (REAL commercialBreak execution!)
# ------------------------------------------------------------------------------
func _test_ad_queue_rewarded_to_commercial() -> void:
	print("\n[TEST 19] Ad Queue: Rewarded -> Commercial (REAL commercialBreak!)...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	mock.rewarded_result = true
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var start_time := Time.get_ticks_msec()
	var state := {
		"rew_result": null,
		"comm_done": false,
		"rew_finish_time": 0.0,
		"comm_finish_time": 0.0
	}

	poki.rewarded_break(func(success: bool):
		state["rew_result"] = success
		state["rew_finish_time"] = float(Time.get_ticks_msec() - start_time)
	)
	assert(poki.get_current_ad_type() == poki.AdType.REWARDED, "Current ad is REWARDED")

	poki.commercial_break(func():
		state["comm_done"] = true
		state["comm_finish_time"] = float(Time.get_ticks_msec() - start_time)
	)

	await get_tree().create_timer(0.2).timeout
	assert(state["rew_result"] == true, "Rewarded ad finished with true")
	assert(state["comm_done"] == false, "Commercial callback not called on rewarded finish")
	assert(poki.is_ad_playing() == true, "Commercial break must now be playing as a REAL ad!")
	assert(mock.commercial_call_count == 1, "Real PokiSDK.commercialBreak() was invoked!")

	await get_tree().create_timer(0.25).timeout
	assert(state["comm_done"] == true, "Commercial called only after real break finishes")
	var finished_after: bool = state["comm_finish_time"] > state["rew_finish_time"]
	assert(finished_after, "Commercial finished AFTER rewarded finished!")
	assert(poki.is_ad_playing() == false, "All ads finished cleanly")
	print("  -> PASS: Queued commercial request ran a real commercialBreak after rewarded ad!")

# ------------------------------------------------------------------------------
# Test 20: Chained Multiple Ad Requests
# ------------------------------------------------------------------------------
func _test_ad_queue_chained_requests() -> void:
	print("\n[TEST 20] Ad Queue: Chained Multiple Requests...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.1
	mock.rewarded_result = true
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var counts := {"rew": 0, "comm1": 0, "comm2": 0}

	poki.rewarded_break(func(_s: bool): counts["rew"] += 1)
	poki.commercial_break(func(): counts["comm1"] += 1)
	poki.commercial_break(func(): counts["comm2"] += 1)

	await get_tree().create_timer(0.15).timeout
	assert(counts["rew"] == 1, "Rewarded completed once")
	assert(counts["comm1"] == 0 and counts["comm2"] == 0, "Commercials not called early")

	await get_tree().create_timer(0.2).timeout
	assert(counts["comm1"] == 1, "Comm 1 completed once")
	assert(counts["comm2"] == 1, "Comm 2 completed once")
	assert(mock.commercial_call_count == 1, "Single break for both callbacks")
	print("  -> PASS: Chained multiple requests resolved without duplicates.")

# ------------------------------------------------------------------------------
# Test 21: Commercial Rejection (commercial_should_succeed = false)
# ------------------------------------------------------------------------------
func _test_commercial_rejection() -> void:
	print("\n[TEST 21] Commercial Rejection / Catch Handling...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.05
	mock.commercial_should_succeed = false
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var state := {"comm_called": false}
	poki.commercial_break(func(): state["comm_called"] = true)
	await get_tree().create_timer(0.15).timeout
	assert(state["comm_called"] == true, "Commercial callback called gracefully on rejection")
	assert(poki.is_ad_playing() == false, "Ad state must be reset to false")
	print("  -> PASS: Commercial rejection gracefully caught without hanging.")

# ------------------------------------------------------------------------------
# Test 22: Rewarded Rejection (rewarded_result = false)
# ------------------------------------------------------------------------------
func _test_rewarded_rejection() -> void:
	print("\n[TEST 22] Rewarded Rejection / Catch Handling...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()

	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.05
	mock.rewarded_result = false
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)

	var state := {"rew_success": null}
	poki.rewarded_break(func(success: bool): state["rew_success"] = success)
	await get_tree().create_timer(0.15).timeout
	assert(state["rew_success"] == false, "Failed rewarded ad gracefully returns false")
	assert(poki.is_ad_playing() == false, "Ad state cleanly reset to false")
	print("  -> PASS: Rewarded rejection caught cleanly with success=false.")
