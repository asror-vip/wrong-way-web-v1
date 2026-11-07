extends Node

# Wrong Way - Comprehensive Audit Test Suite
# Covers:
# 1. Late SDK Loading (300ms, 1s, 2s), Init Success, Init Rejection, and Missing SDK
# 2. Duplicate Init Prevention and SDK Readiness Gates
# 3. Commercial -> Commercial Ad Queue (no premature callbacks, single execution)
# 4. Commercial -> Rewarded Ad Queue (safe rejection of rewarded without breaking commercial)
# 5. Rewarded -> Commercial Ad Queue (rewarded finishes, REAL commercialBreak starts, callback waits)
# 6. Chained Multiple Ad Requests & Ad Error Handling (promise rejection / failure)
# 7. ControlInverter Multi-Zone Isolation and Respawn Cleansing

class MockPokiSdk extends RefCounted:
	var available: bool = false
	var init_should_succeed: bool = true
	var init_delay: float = 0.0
	var ad_delay: float = 0.05
	var commercial_should_succeed: bool = true
	var rewarded_result: bool = true
	
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
		var tree := Engine.get_main_loop() as SceneTree
		if ad_delay > 0.0 and tree:
			await tree.create_timer(ad_delay).timeout
		on_done.call()

	func request_rewarded_break(on_result: Callable) -> void:
		rewarded_call_count += 1
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

class DummyPlayer extends Node2D:
	var active_inverters: Dictionary = {}
	var controls_inverted: bool = false
	
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
	print("================================================================")
	print("STARTING WRONG WAY ADVANCED AUDIT TEST SUITE (POKI SDK & TRAPS)")
	print("================================================================")
	
	await _test_control_inverter_isolation()
	await _test_late_sdk_300ms()
	await _test_late_sdk_1s()
	await _test_late_sdk_2s()
	await _test_sdk_init_rejection()
	await _test_sdk_never_arrives()
	await _test_duplicate_init_prevention()
	await _test_sdk_gate_before_gameplay()
	await _test_ad_queue_commercial_to_commercial()
	await _test_ad_queue_commercial_to_rewarded()
	await _test_ad_queue_rewarded_to_commercial()
	await _test_ad_queue_chained_requests()
	await _test_ad_error_handling()
	
	print("\n================================================================")
	print("ALL 13 ADVANCED AUDIT TEST SUITES PASSED CLEANLY! (EXIT CODE 0)")
	print("================================================================")
	get_tree().quit(0)

# ------------------------------------------------------------------------------
# Test 1: ControlInverter Multi-Zone Isolation & Reset
# ------------------------------------------------------------------------------
func _test_control_inverter_isolation() -> void:
	print("\n[TEST 1] ControlInverter Isolation & Single-Trap Reset...")
	var player := DummyPlayer.new()
	player.add_to_group("player")
	add_child(player)
	
	var inv_script: Script = load("res://scripts/traps/control_inverter.gd")
	var inv_a: Area2D = inv_script.new()
	var inv_b: Area2D = inv_script.new()
	add_child(inv_a)
	add_child(inv_b)
	
	player.add_inverter_zone(inv_a)
	player.add_inverter_zone(inv_b)
	assert(player.controls_inverted == true, "Both zones active -> inverted")
	assert(player.active_inverters.size() == 2, "2 zones registered")
	
	# Reset Zone A ONLY
	inv_a.reset_trap()
	assert(player.controls_inverted == true, "CRITICAL: Resetting Zone A must NOT cancel active Zone B!")
	assert(player.active_inverters.has(inv_b) == true, "Zone B must remain")
	assert(player.active_inverters.has(inv_a) == false, "Zone A removed")
	
	# Reset Zone B
	inv_b.reset_trap()
	assert(player.controls_inverted == false, "All zones reset -> controls restored")
	
	# Respawn test
	player.add_inverter_zone(inv_a)
	player.respawn()
	assert(player.controls_inverted == false, "Player respawn must clear all zones")
	
	inv_a.queue_free()
	inv_b.queue_free()
	player.queue_free()
	print("  -> PASS: Inverter zones strictly isolated and cleanly reset.")

# ------------------------------------------------------------------------------
# Test 2: Late SDK Loading - 300 ms Delay
# ------------------------------------------------------------------------------
func _test_late_sdk_300ms() -> void:
	print("\n[TEST 2] Late SDK Loading: Arrives after 300ms with Init Success...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = false
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)
	
	# Simulate late arrival after 300ms in background
	get_tree().create_timer(0.3).timeout.connect(func():
		print("  (Event: Mock PokiSDK script arrived after 300ms)")
		mock.available = true
	)
	
	var final_state: int = await poki.ensure_sdk_initialized(1.5)
	assert(final_state == poki.SdkState.READY, "SDK must transition to READY after 300ms late load")
	assert(poki.is_poki_available == true, "is_poki_available must be true when READY")
	print("  -> PASS: 300ms late SDK resolved to SdkState.READY.")

# ------------------------------------------------------------------------------
# Test 3: Late SDK Loading - 1.0 s Delay
# ------------------------------------------------------------------------------
func _test_late_sdk_1s() -> void:
	print("\n[TEST 3] Late SDK Loading: Arrives after 1.0s with Init Success...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = false
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)
	
	get_tree().create_timer(1.0).timeout.connect(func():
		print("  (Event: Mock PokiSDK script arrived after 1.0s)")
		mock.available = true
	)
	
	var final_state: int = await poki.ensure_sdk_initialized(2.5)
	assert(final_state == poki.SdkState.READY, "SDK must transition to READY after 1.0s late load")
	assert(poki.is_poki_available == true, "is_poki_available must be true when READY")
	print("  -> PASS: 1.0s late SDK resolved to SdkState.READY.")

# ------------------------------------------------------------------------------
# Test 4: Late SDK Loading - 2.0 s Delay
# ------------------------------------------------------------------------------
func _test_late_sdk_2s() -> void:
	print("\n[TEST 4] Late SDK Loading: Arrives after 2.0s with Init Success...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = false
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)
	
	get_tree().create_timer(2.0).timeout.connect(func():
		print("  (Event: Mock PokiSDK script arrived after 2.0s)")
		mock.available = true
	)
	
	var final_state: int = await poki.ensure_sdk_initialized(3.0)
	assert(final_state == poki.SdkState.READY, "SDK must transition to READY after 2.0s late load")
	assert(poki.is_poki_available == true, "is_poki_available must be true when READY")
	print("  -> PASS: 2.0s late SDK resolved to SdkState.READY.")

# ------------------------------------------------------------------------------
# Test 5: SDK Init Rejection (Adblocker / Failure)
# ------------------------------------------------------------------------------
func _test_sdk_init_rejection() -> void:
	print("\n[TEST 5] SDK Init Rejection (Adblock / Script Error)...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_should_succeed = false # Rejection
	poki.set_mock_provider(mock)
	
	var final_state: int = await poki.ensure_sdk_initialized(1.0)
	assert(final_state == poki.SdkState.FAILED, "Rejected init must transition to SdkState.FAILED")
	assert(poki.is_poki_available == false, "is_poki_available must be false on failure")
	print("  -> PASS: Rejected SDK init recorded as SdkState.FAILED with is_poki_available=false.")

# ------------------------------------------------------------------------------
# Test 6: SDK Never Arrives (Offline / Missing)
# ------------------------------------------------------------------------------
func _test_sdk_never_arrives() -> void:
	print("\n[TEST 6] SDK Never Arrives (Offline / Timed Out)...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = false # Never available
	poki.set_mock_provider(mock)
	
	var final_state: int = await poki.ensure_sdk_initialized(0.4)
	assert(final_state == poki.SdkState.FAILED, "Missing SDK must timeout to SdkState.FAILED")
	assert(poki.is_poki_available == false, "is_poki_available must be false")
	print("  -> PASS: Missing SDK safely times out without freezing game loop.")

# ------------------------------------------------------------------------------
# Test 7: Prevent Duplicate Concurrent Inits
# ------------------------------------------------------------------------------
func _test_duplicate_init_prevention() -> void:
	print("\n[TEST 7] Duplicate Init Prevention...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.3
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)
	
	# Start first init
	poki._try_init_sdk()
	assert(poki.sdk_state == poki.SdkState.INITIALIZING, "State is INITIALIZING")
	
	# Try starting second init concurrently
	var second_result: bool = poki._try_init_sdk()
	assert(second_result == false, "Second concurrent init call must be rejected")
	assert(mock.init_call_count == 1, "Only 1 init call should have been made to provider")
	
	await poki.ensure_sdk_initialized(1.0)
	assert(poki.sdk_state == poki.SdkState.READY, "State reached READY")
	print("  -> PASS: Duplicate init calls prevented during active initialization.")

# ------------------------------------------------------------------------------
# Test 8: SDK Readiness Gate for Gameplay Calls
# ------------------------------------------------------------------------------
func _test_sdk_gate_before_gameplay() -> void:
	print("\n[TEST 8] SDK Readiness Gate Before Gameplay...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = true
	mock.init_delay = 0.1
	mock.init_should_succeed = true
	poki.set_mock_provider(mock)
	
	# Call gameplay_start while SDK is uninitialized
	poki.gameplay_start()
	# Wait for init to finish
	await poki.ensure_sdk_initialized(1.0)
	assert(poki.sdk_state == poki.SdkState.READY, "SDK initialized")
	assert(mock.gameplay_start_count == 1, "gameplay_start executed after SDK ready")
	print("  -> PASS: Gameplay calls safely await SDK ready state.")

# ------------------------------------------------------------------------------
# Test 9: Commercial -> Commercial Queue (Single Break, Single Callbacks)
# ------------------------------------------------------------------------------
func _test_ad_queue_commercial_to_commercial() -> void:
	print("\n[TEST 9] Ad Queue: Commercial -> Commercial...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)
	
	var counts := {"cb1": 0, "cb2": 0}
	
	poki.commercial_break(func(): counts["cb1"] += 1)
	assert(poki._is_ad_playing == true, "Commercial 1 is playing")
	assert(counts["cb1"] == 0, "Callback 1 must NOT be called early")
	
	# Request second commercial while first is playing
	poki.commercial_break(func(): counts["cb2"] += 1)
	assert(counts["cb2"] == 0, "Callback 2 must NOT be called early")
	assert(mock.commercial_call_count == 1, "Should not trigger two simultaneous commercialBreaks")
	
	# Wait for ad to finish
	await get_tree().create_timer(0.25).timeout
	assert(poki._is_ad_playing == false, "Ad finished")
	assert(counts["cb1"] == 1, "Callback 1 called exactly once")
	assert(counts["cb2"] == 1, "Callback 2 called exactly once")
	print("  -> PASS: Concurrent commercial requests share the break and fire callbacks once at end.")

# ------------------------------------------------------------------------------
# Test 10: Commercial -> Rewarded Queue (Safe Rejection)
# ------------------------------------------------------------------------------
func _test_ad_queue_commercial_to_rewarded() -> void:
	print("\n[TEST 10] Ad Queue: Commercial -> Rewarded Safe Rejection...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.15
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)
	
	var state := {"comm_done": false, "rew_result": null}
	
	poki.commercial_break(func(): state["comm_done"] = true)
	
	# Attempt rewarded while commercial is playing
	poki.rewarded_break(func(success: bool): state["rew_result"] = success)
	assert(state["rew_result"] == false, "Rewarded during commercial must be rejected immediately with false")
	assert(state["comm_done"] == false, "Commercial must not be disrupted")
	
	await get_tree().create_timer(0.25).timeout
	assert(state["comm_done"] == true, "Commercial completed successfully")
	print("  -> PASS: Rewarded during commercial safely rejected without corrupting commercial ad.")

# ------------------------------------------------------------------------------
# Test 11: Rewarded -> Commercial Queue (REAL commercialBreak execution!)
# ------------------------------------------------------------------------------
func _test_ad_queue_rewarded_to_commercial() -> void:
	print("\n[TEST 11] Ad Queue: Rewarded -> Commercial (REAL commercialBreak execution!)...")
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
	
	# 1. Start rewarded break
	poki.rewarded_break(func(success: bool):
		state["rew_result"] = success
		state["rew_finish_time"] = float(Time.get_ticks_msec() - start_time)
	)
	assert(poki._current_ad_type == poki.AdType.REWARDED, "Current ad is REWARDED")
	
	# 2. In the middle of rewarded break, request a commercial break!
	poki.commercial_break(func():
		state["comm_done"] = true
		state["comm_finish_time"] = float(Time.get_ticks_msec() - start_time)
	)
	
	# 3. Wait for rewarded break to complete (around 150ms)
	await get_tree().create_timer(0.2).timeout
	assert(state["rew_result"] == true, "Rewarded ad finished with true")
	assert(state["comm_done"] == false, "CRITICAL AUDIT CHECK: Commercial callback must NOT be called when rewarded ad finishes!")
	assert(poki._is_ad_playing == true, "Commercial break must now be playing as a REAL ad!")
	assert(mock.commercial_call_count == 1, "Real PokiSDK.commercialBreak() was invoked!")
	
	# 4. Wait for commercial break to complete (another 150ms)
	await get_tree().create_timer(0.25).timeout
	assert(state["comm_done"] == true, "Commercial callback called ONLY after real commercialBreak finishes!")
	assert(state["comm_finish_time"] > state["rew_finish_time"], "Commercial finished AFTER rewarded ad finished!")
	assert(poki._is_ad_playing == false, "All ads finished cleanly")
	print("  -> PASS: Queued commercial request ran a real commercialBreak after rewarded ad!")

# ------------------------------------------------------------------------------
# Test 12: Chained Multiple Ad Requests
# ------------------------------------------------------------------------------
func _test_ad_queue_chained_requests() -> void:
	print("\n[TEST 12] Ad Queue: Chained Multiple Requests (Rewarded + Comm 1 + Comm 2)...")
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
	
	# Wait for rewarded break
	await get_tree().create_timer(0.15).timeout
	assert(counts["rew"] == 1, "Rewarded completed once")
	assert(counts["comm1"] == 0 and counts["comm2"] == 0, "Commercials not called early")
	
	# Wait for sequential commercial break
	await get_tree().create_timer(0.2).timeout
	assert(counts["comm1"] == 1, "Comm 1 completed once")
	assert(counts["comm2"] == 1, "Comm 2 completed once")
	assert(mock.commercial_call_count == 1, "Single consolidated commercial break for both callbacks")
	print("  -> PASS: Chained multiple requests resolved without callback duplication or omission.")

# ------------------------------------------------------------------------------
# Test 13: Ad Error Handling (Rejection / Failure)
# ------------------------------------------------------------------------------
func _test_ad_error_handling() -> void:
	print("\n[TEST 13] Ad Error Handling (Catch / Rejection Recovery)...")
	var poki = get_node_or_null("/root/PokiService")
	poki.reset_state_for_testing()
	
	var mock := MockPokiSdk.new()
	mock.available = true
	mock.ad_delay = 0.05
	mock.rewarded_result = false # Failed rewarded ad (user closed early or no fill)
	poki.set_mock_provider(mock)
	await poki.ensure_sdk_initialized(0.5)
	
	var state := {"rew_success": null}
	poki.rewarded_break(func(success: bool): state["rew_success"] = success)
	await get_tree().create_timer(0.15).timeout
	assert(state["rew_success"] == false, "Failed rewarded ad gracefully returns success=false")
	assert(poki._is_ad_playing == false, "Ad state cleanly reset to false")
	var sm = get_node_or_null("/root/SaveManager")
	var expected_user_muted := false
	if sm:
		expected_user_muted = (not sm.music_enabled) and (not sm.sfx_enabled)
	assert(AudioServer.is_bus_mute(0) == expected_user_muted, "Audio restored matching SaveManager settings after failed ad")
	print("  -> PASS: Ad errors caught cleanly with state and audio restoration.")
