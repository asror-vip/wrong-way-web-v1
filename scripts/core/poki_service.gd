extends Node

# PokiService - Official Poki SDK v2 Integration for Wrong Way (Godot 4 HTML5)
# Handles lifecycle, commercial breaks (interstitial), rewarded breaks, and audio muting.

signal commercial_break_completed
signal rewarded_break_completed(success: bool)

var is_poki_available: bool = false
var is_gameplay_running: bool = false
var _cached_music_volume: float = 1.0
var _cached_sfx_volume: float = 1.0
var _js_commercial_callback = null
var _js_rewarded_callback = null
var _pending_commercial_callable: Callable = Callable()
var _pending_rewarded_callable: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_poki()

func _init_poki() -> void:
	if OS.has_feature("web"):
		var js_poki = JavaScriptBridge.get_interface("PokiSDK")
		if js_poki:
			is_poki_available = true
			print("PokiService: PokiSDK brauzerda muvaffaqiyatli aniqlandi.")
		else:
			print("PokiService: PokiSDK topilmadi (offline yoki lokal web test).")
	else:
		print("PokiService: Desktop muhiti — PokiSDK simulyatsiya rejimida ishlaydi.")

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func game_loading_finished() -> void:
	print("PokiService: gameLoadingFinished()")
	if is_poki_available:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameLoadingFinished(); }")

func gameplay_start() -> void:
	if is_gameplay_running:
		return
	is_gameplay_running = true
	print("PokiService: gameplayStart()")
	if is_poki_available:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameplayStart(); }")

func gameplay_stop() -> void:
	if not is_gameplay_running:
		return
	is_gameplay_running = false
	print("PokiService: gameplayStop()")
	if is_poki_available:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameplayStop(); }")

# ------------------------------------------------------------------------------
# Commercial Break (Interstitial Ad)
# ------------------------------------------------------------------------------
func commercial_break(on_completed: Callable = Callable()) -> void:
	print("PokiService: commercialBreak chaqirilmoqda...")
	_pending_commercial_callable = on_completed
	gameplay_stop()
	_mute_audio(true)
	
	if is_poki_available:
		_js_commercial_callback = JavaScriptBridge.create_callback(_on_commercial_break_finished)
		var window = JavaScriptBridge.get_interface("window")
		window._poki_commercial_callback = _js_commercial_callback
		JavaScriptBridge.eval("""
			if (window.PokiSDK) {
				PokiSDK.commercialBreak().then(function() {
					if (window._poki_commercial_callback) {
						window._poki_commercial_callback();
					}
				}).catch(function() {
					if (window._poki_commercial_callback) {
						window._poki_commercial_callback();
					}
				});
			} else if (window._poki_commercial_callback) {
				window._poki_commercial_callback();
			}
		""")
	else:
		# Desktop muhitida 0.1s dan keyin yakunlanadi
		await get_tree().create_timer(0.1).timeout
		_on_commercial_break_finished([])

func _on_commercial_break_finished(_args: Array) -> void:
	print("PokiService: commercialBreak yakunlandi.")
	_mute_audio(false)
	if _pending_commercial_callable.is_valid():
		var cb := _pending_commercial_callable
		_pending_commercial_callable = Callable()
		cb.call()
	commercial_break_completed.emit()

# ------------------------------------------------------------------------------
# Rewarded Break (Rewarded Ad for Level Unlock)
# ------------------------------------------------------------------------------
func rewarded_break(on_reward_result: Callable = Callable()) -> void:
	print("PokiService: rewardedBreak chaqirilmoqda...")
	_pending_rewarded_callable = on_reward_result
	gameplay_stop()
	_mute_audio(true)
	
	if is_poki_available:
		_js_rewarded_callback = JavaScriptBridge.create_callback(_on_rewarded_break_finished)
		var window = JavaScriptBridge.get_interface("window")
		window._poki_rewarded_callback = _js_rewarded_callback
		JavaScriptBridge.eval("""
			if (window.PokiSDK) {
				PokiSDK.rewardedBreak().then(function(success) {
					if (window._poki_rewarded_callback) {
						window._poki_rewarded_callback(Boolean(success));
					}
				}).catch(function() {
					if (window._poki_rewarded_callback) {
						window._poki_rewarded_callback(false);
					}
				});
			} else if (window._poki_rewarded_callback) {
				window._poki_rewarded_callback(true);
			}
		""")
	else:
		# Desktop muhitida sinov uchun mukofot beriladi
		await get_tree().create_timer(0.1).timeout
		_on_rewarded_break_finished([true])

func _on_rewarded_break_finished(args: Array) -> void:
	var success: bool = true
	if args.size() > 0:
		success = bool(args[0])
	print("PokiService: rewardedBreak yakunlandi. Natija: ", success)
	_mute_audio(false)
	if _pending_rewarded_callable.is_valid():
		var cb := _pending_rewarded_callable
		_pending_rewarded_callable = Callable()
		cb.call(success)
	rewarded_break_completed.emit(success)

# ------------------------------------------------------------------------------
# Audio helper
# ------------------------------------------------------------------------------
func _mute_audio(mute: bool) -> void:
	var sm = get_node_or_null("/root/SoundManager")
	if not sm:
		return
	if mute:
		_cached_music_volume = sm.music_volume if "music_volume" in sm else 1.0
		_cached_sfx_volume = sm.sfx_volume if "sfx_volume" in sm else 1.0
		if sm.has_method("set_music_volume"):
			sm.set_music_volume(0.0)
		if sm.has_method("set_sfx_volume"):
			sm.set_sfx_volume(0.0)
	else:
		if sm.has_method("set_music_volume"):
			sm.set_music_volume(_cached_music_volume)
		if sm.has_method("set_sfx_volume"):
			sm.set_sfx_volume(_cached_sfx_volume)
