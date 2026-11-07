extends Node

# PokiService - Official Poki SDK v2 Integration for Wrong Way (Godot 4 HTML5)
# Handles lifecycle, commercial breaks, rewarded breaks, audio muting, and tab blur.

signal commercial_break_completed
signal rewarded_break_completed(success: bool)
signal sdk_ready
signal sdk_init_failed

enum SdkState {
	UNINITIALIZED,
	INITIALIZING,
	READY,
	FAILED
}

enum AdType {
	NONE,
	COMMERCIAL,
	REWARDED
}

var sdk_state: SdkState = SdkState.UNINITIALIZED
var is_poki_available: bool = false # SdkState.READY bo'lgandagina true bo'ladi
var is_gameplay_running: bool = false

var _is_ad_playing: bool = false
var _current_ad_type: AdType = AdType.NONE
var _is_init_in_progress: bool = false
var _init_token: int = 0
var _ad_token: int = 0
var ad_timeout_seconds: float = 12.0

# Lifecycle race condition himoyasi
var _gameplay_desired: bool = false
var _gameplay_notified_to_poki: bool = false
var _lifecycle_seq: int = 0

var _js_commercial_callback = null
var _js_rewarded_callback = null
var _js_init_success_callback = null
var _js_init_failed_callback = null

var _active_commercial_callbacks: Array[Callable] = []
var _queued_commercial_requests: Array[Callable] = []
var _active_rewarded_callbacks: Array[Callable] = []

# Unit testlar va offline simulyatsiya uchun mock provider
var _sdk_mock_provider: Object = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_poki()
	if OS.has_feature("web") and sdk_state == SdkState.UNINITIALIZED:
		_poll_sdk_availability()

func _notification(what: int) -> void:
	# Brauzer tabidan boshqa oynaga o'tganda (blur) ovozni to'xtatish (Poki qat'iy talabi)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if not _is_ad_playing:
			_restore_audio()

func _restore_audio() -> void:
	# Foydalanuvchining shaxsiy sozlamalarini hurmat qilgan holda ovozni tiklash
	var sm = get_node_or_null("/root/SaveManager")
	var is_user_muted := false
	if sm:
		is_user_muted = (not sm.music_enabled) and (not sm.sfx_enabled)
	AudioServer.set_bus_mute(0, is_user_muted)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("update_music_volume"):
		snd.update_music_volume(false)

# ------------------------------------------------------------------------------
# Mock & Test Hook
# ------------------------------------------------------------------------------
func set_mock_provider(provider: Object) -> void:
	_sdk_mock_provider = provider

func get_mock_provider() -> Object:
	return _sdk_mock_provider

func is_ad_playing() -> bool:
	return _is_ad_playing

func get_current_ad_type() -> AdType:
	return _current_ad_type

func try_init_sdk() -> bool:
	return _try_init_sdk()

func get_ad_token() -> int:
	return _ad_token

func is_gameplay_desired() -> bool:
	return _gameplay_desired

func is_gameplay_notified_to_poki() -> bool:
	return _gameplay_notified_to_poki

func simulate_commercial_break_finished_for_test() -> void:
	_on_commercial_break_finished([])

func simulate_rewarded_break_finished_for_test(success: bool) -> void:
	_on_rewarded_break_finished([success])

func reset_state_for_testing() -> void:
	_init_token += 1
	_lifecycle_seq += 1
	_ad_token += 1
	ad_timeout_seconds = 12.0
	sdk_state = SdkState.UNINITIALIZED
	is_poki_available = false
	is_gameplay_running = false
	_gameplay_desired = false
	_gameplay_notified_to_poki = false
	_is_ad_playing = false
	_current_ad_type = AdType.NONE
	_is_init_in_progress = false
	_active_commercial_callbacks.clear()
	_queued_commercial_requests.clear()
	_active_rewarded_callbacks.clear()
	_sdk_mock_provider = null
	AudioServer.set_bus_mute(0, false)

# ------------------------------------------------------------------------------
# Poki SDK Initialization & Late-Loading
# ------------------------------------------------------------------------------
func _init_poki() -> void:
	if _sdk_mock_provider != null:
		_try_init_sdk()
		return
	if OS.has_feature("web"):
		_try_init_sdk()
		if sdk_state == SdkState.UNINITIALIZED:
			print("PokiService: PokiSDK hali yuklanmadi, kechikib yuklanish monitoringi boshlandi.")
	else:
		sdk_state = SdkState.FAILED
		is_poki_available = false
		print("PokiService: Desktop muhiti — PokiSDK simulyatsiya rejimida ishlaydi.")

func _try_init_sdk() -> bool:
	if sdk_state == SdkState.READY:
		return true
	if sdk_state == SdkState.INITIALIZING or _is_init_in_progress:
		# Bir vaqtning o'zida bir nechta init chaqirilishini bloklash
		return false
	if sdk_state == SdkState.FAILED:
		return false

	_init_token += 1
	var current_token := _init_token

	# Mock provider orqali tekshirish (testlar uchun)
	if _sdk_mock_provider != null:
		var has_sdk: bool = _sdk_mock_provider.has_method("has_poki_sdk") \
			and _sdk_mock_provider.has_poki_sdk()
		if not has_sdk:
			return false
		_is_init_in_progress = true
		sdk_state = SdkState.INITIALIZING
		print("PokiService: Mock SDK orqali init boshlandi (token: %d)..." % current_token)
		_sdk_mock_provider.init_sdk(
			func(): _on_poki_init_success(current_token, []),
			func(): _on_poki_init_failed(current_token, [])
		)
		return true

	if not OS.has_feature("web"):
		sdk_state = SdkState.FAILED
		is_poki_available = false
		return false

	var js_poki = JavaScriptBridge.get_interface("PokiSDK")
	if not js_poki:
		return false

	_is_init_in_progress = true
	sdk_state = SdkState.INITIALIZING
	print("PokiService: PokiSDK topildi. init() boshlanmoqda (token: %d)..." % current_token)

	_js_init_success_callback = JavaScriptBridge.create_callback(func(args = []):
		_on_poki_init_success(current_token, args)
	)
	_js_init_failed_callback = JavaScriptBridge.create_callback(func(args = []):
		_on_poki_init_failed(current_token, args)
	)

	var window = JavaScriptBridge.get_interface("window")
	window._poki_init_success = _js_init_success_callback
	window._poki_init_failed = _js_init_failed_callback

	JavaScriptBridge.eval("""
		if (window.PokiSDK && !window._poki_init_called) {
			window._poki_init_called = true;
			window.PokiSDK.init().then(function() {
				console.log('PokiSDK init success');
				if (window._poki_init_success) {
					window._poki_init_success();
				}
			}).catch(function(err) {
				console.warn('PokiSDK init failed:', err);
				if (window._poki_init_failed) {
					window._poki_init_failed();
				}
			});
		} else if (!window.PokiSDK) {
			if (window._poki_init_failed) {
				window._poki_init_failed();
			}
		}
	""")
	return true

func _on_poki_init_success(token: int, _args: Array = []) -> void:
	if token != _init_token:
		print("PokiService: Eskirgan init_success (token: %d) e'tiborsiz qoldirildi." % token)
		return
	if sdk_state != SdkState.INITIALIZING:
		print("PokiService: Kutilmagan init_success (state: %d) e'tiborsiz qoldirildi." % sdk_state)
		return
	print("PokiService: PokiSDK.init() muvaffaqiyatli (token: %d) -> READY" % token)
	_is_init_in_progress = false
	sdk_state = SdkState.READY
	is_poki_available = true
	sdk_ready.emit()

func _on_poki_init_failed(token: int, _args: Array = []) -> void:
	if token != _init_token:
		print("PokiService: Eskirgan init_failed (token: %d) e'tiborsiz qoldirildi." % token)
		return
	if sdk_state != SdkState.INITIALIZING:
		return
	print("PokiService: PokiSDK.init() rad etildi (token: %d) -> SdkState.FAILED" % token)
	_is_init_in_progress = false
	sdk_state = SdkState.FAILED
	is_poki_available = false
	sdk_init_failed.emit()

func _poll_sdk_availability() -> void:
	for _attempt in range(16): # 16 x 0.25s = 4.0s
		if sdk_state == SdkState.READY or sdk_state == SdkState.FAILED:
			break
		if sdk_state == SdkState.UNINITIALIZED:
			_try_init_sdk()
		await get_tree().create_timer(0.25).timeout
	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		print("PokiService: SDK monitoring vaqti tugadi -> FAILED (token: %d)" % _init_token)
		_init_token += 1
		_is_init_in_progress = false
		sdk_state = SdkState.FAILED
		is_poki_available = false

func ensure_sdk_initialized(max_wait: float = 2.5) -> int:
	if sdk_state == SdkState.READY or sdk_state == SdkState.FAILED:
		return sdk_state
	if not OS.has_feature("web") and _sdk_mock_provider == null:
		sdk_state = SdkState.FAILED
		is_poki_available = false
		return sdk_state

	if sdk_state == SdkState.UNINITIALIZED:
		_try_init_sdk()

	var elapsed := 0.0
	while (sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING) \
			and elapsed < max_wait:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
		if sdk_state == SdkState.UNINITIALIZED:
			_try_init_sdk()

	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		print("PokiService: SDK init timeout -> SdkState.FAILED (token: %d bekor)" % _init_token)
		_init_token += 1
		_is_init_in_progress = false
		sdk_state = SdkState.FAILED
		is_poki_available = false

	return sdk_state

# ------------------------------------------------------------------------------
# Lifecycle (Race-Protected)
# ------------------------------------------------------------------------------
func game_loading_finished() -> void:
	print("PokiService: gameLoadingFinished()")
	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		await ensure_sdk_initialized(2.0)
	if _sdk_mock_provider != null:
		if _sdk_mock_provider.has_method("game_loading_finished"):
			_sdk_mock_provider.game_loading_finished()
		return
	if sdk_state == SdkState.READY:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameLoadingFinished(); }")

func gameplay_start() -> void:
	_lifecycle_seq += 1
	var seq := _lifecycle_seq
	_gameplay_desired = true
	is_gameplay_running = true
	print("PokiService: gameplay_start() so'rovi (seq: %d)" % seq)

	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		await ensure_sdk_initialized(2.0)

	if seq != _lifecycle_seq:
		print("PokiService: Eski gameplay_start (seq: %d) e'tiborsiz qoldirildi." % seq)
		return
	if not _gameplay_desired:
		return
	if _is_ad_playing:
		print("PokiService: Reklama davomida gameplay_start kutish rejimiga o'tdi.")
		return

	_notify_gameplay_start_if_ready()

func _notify_gameplay_start_if_ready() -> void:
	if sdk_state == SdkState.READY and _gameplay_desired and not _is_ad_playing:
		if not _gameplay_notified_to_poki:
			_gameplay_notified_to_poki = true
			print("PokiService: PokiSDK.gameplayStart() yuborildi.")
			if _sdk_mock_provider != null and _sdk_mock_provider.has_method("gameplay_start"):
				_sdk_mock_provider.gameplay_start()
			elif OS.has_feature("web"):
				JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameplayStart(); }")

func gameplay_stop() -> void:
	_lifecycle_seq += 1
	var seq := _lifecycle_seq
	_gameplay_desired = false
	is_gameplay_running = false
	print("PokiService: gameplay_stop() so'rovi (seq: %d)" % seq)

	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		await ensure_sdk_initialized(2.0)

	if seq != _lifecycle_seq or _gameplay_desired:
		return

	if sdk_state == SdkState.READY and _gameplay_notified_to_poki:
		_gameplay_notified_to_poki = false
		print("PokiService: PokiSDK.gameplayStop() yuborildi.")
		if _sdk_mock_provider != null and _sdk_mock_provider.has_method("gameplay_stop"):
			_sdk_mock_provider.gameplay_stop()
		elif OS.has_feature("web"):
			JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameplayStop(); }")

# ------------------------------------------------------------------------------
# Commercial Break (Interstitial Ad)
# ------------------------------------------------------------------------------
func commercial_break(on_completed: Callable = Callable()) -> void:
	# Agar allaqachon reklama ko'rsatilayotgan bo'lsa:
	if _is_ad_playing:
		if _current_ad_type == AdType.COMMERCIAL:
			# Davom etayotgan commercial break ga ulanadi
			if on_completed.is_valid() and not _active_commercial_callbacks.has(on_completed):
				_active_commercial_callbacks.append(on_completed)
			print("PokiService: Commercial break davom etmoqda. So'rov qo'shildi.")
			return
		elif _current_ad_type == AdType.REWARDED:
			# Rewarded break vaqtida kelgan commercial so'rov navbatga olinadi
			if on_completed.is_valid() and not _queued_commercial_requests.has(on_completed):
				_queued_commercial_requests.append(on_completed)
			print("PokiService: Rewarded break ketmoqda. Commercial so'rov navbatga olindi.")
			return

	_start_commercial_break(on_completed)

func _start_commercial_break(on_completed: Callable = Callable()) -> void:
	if on_completed.is_valid() and not _active_commercial_callbacks.has(on_completed):
		_active_commercial_callbacks.append(on_completed)

	_is_ad_playing = true
	_current_ad_type = AdType.COMMERCIAL
	_ad_token += 1
	var token := _ad_token
	_start_ad_safety_timer(token, AdType.COMMERCIAL, ad_timeout_seconds)

	print("PokiService: commercialBreak boshlanmoqda...")
	gameplay_stop()
	AudioServer.set_bus_mute(0, true)

	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		await ensure_sdk_initialized(2.0)

	if _sdk_mock_provider != null:
		_sdk_mock_provider.request_commercial_break(func():
			_on_commercial_break_finished([])
		)
		return

	if sdk_state == SdkState.READY:
		_js_commercial_callback = JavaScriptBridge.create_callback(_on_commercial_break_finished)
		var window = JavaScriptBridge.get_interface("window")
		window._poki_commercial_callback = _js_commercial_callback
		JavaScriptBridge.eval("""
			if (window.PokiSDK) {
				PokiSDK.commercialBreak().then(function() {
					if (window._poki_commercial_callback) {
						window._poki_commercial_callback();
					}
				}).catch(function(err) {
					console.warn('PokiSDK commercialBreak rejected:', err);
					if (window._poki_commercial_callback) {
						window._poki_commercial_callback();
					}
				});
			} else if (window._poki_commercial_callback) {
				window._poki_commercial_callback();
			}
		""")
	else:
		# Desktop yoki offline muhitda 0.05s simulyatsiya
		await get_tree().create_timer(0.05).timeout
		_on_commercial_break_finished([])

func _on_commercial_break_finished(_args: Array = []) -> void:
	# Duplicate callback guard: reklama tugagan bo'lsa, takroriy callback o'tkazilmaydi
	if not _is_ad_playing or _current_ad_type != AdType.COMMERCIAL:
		print("PokiService: Takroriy yoki eskirgan commercialBreak callback e'tiborsiz.")
		return

	print("PokiService: commercialBreak yakunlandi.")
	_is_ad_playing = false
	_current_ad_type = AdType.NONE
	_restore_audio()

	var callbacks := _active_commercial_callbacks.duplicate()
	_active_commercial_callbacks.clear()
	for cb in callbacks:
		if cb.is_valid():
			cb.call()

	commercial_break_completed.emit()

	# Agar reklama vaqtida gameplay_start chaqirilgan bo'lsa (start kutayotgan holat)
	if _gameplay_desired and not _gameplay_notified_to_poki:
		_notify_gameplay_start_if_ready()

	# Agar navbatda turgan boshqa so'rovlar bo'lsa tekshiramiz
	_check_queued_ad_requests()

# ------------------------------------------------------------------------------
# Rewarded Break (Rewarded Ad for Level Unlock)
# ------------------------------------------------------------------------------
func rewarded_break(on_reward_result: Callable = Callable()) -> void:
	# Agar hozir boshqa reklama ko'rsatilayotgan bo'lsa:
	# Bir vaqtning o'zida ikkita reklama ko'rsatilishi mumkin emas.
	# Davom etayotgan reklamani buzmasdan ushbu so'rov xavfsiz rad etiladi.
	if _is_ad_playing:
		print("PokiService: Reklama ketmoqda, rewarded so'rovi rad etildi (success=false).")
		if on_reward_result.is_valid():
			on_reward_result.call(false)
		return

	_start_rewarded_break(on_reward_result)

func _start_rewarded_break(on_reward_result: Callable = Callable()) -> void:
	if on_reward_result.is_valid() and not _active_rewarded_callbacks.has(on_reward_result):
		_active_rewarded_callbacks.append(on_reward_result)

	_is_ad_playing = true
	_current_ad_type = AdType.REWARDED
	_ad_token += 1
	var token := _ad_token
	_start_ad_safety_timer(token, AdType.REWARDED, ad_timeout_seconds)

	print("PokiService: rewardedBreak boshlanmoqda...")
	gameplay_stop()
	AudioServer.set_bus_mute(0, true)

	if sdk_state == SdkState.UNINITIALIZED or sdk_state == SdkState.INITIALIZING:
		await ensure_sdk_initialized(2.0)

	if _sdk_mock_provider != null:
		_sdk_mock_provider.request_rewarded_break(func(success: bool):
			_on_rewarded_break_finished([success])
		)
		return

	if sdk_state == SdkState.READY:
		_js_rewarded_callback = JavaScriptBridge.create_callback(_on_rewarded_break_finished)
		var window = JavaScriptBridge.get_interface("window")
		window._poki_rewarded_callback = _js_rewarded_callback
		JavaScriptBridge.eval("""
			if (window.PokiSDK) {
				PokiSDK.rewardedBreak().then(function(success) {
					if (window._poki_rewarded_callback) {
						window._poki_rewarded_callback(Boolean(success));
					}
				}).catch(function(err) {
					console.warn('PokiSDK rewardedBreak rejected:', err);
					if (window._poki_rewarded_callback) {
						window._poki_rewarded_callback(false);
					}
				});
			} else if (window._poki_rewarded_callback) {
				window._poki_rewarded_callback(false);
			}
		""")
	else:
		await get_tree().create_timer(0.05).timeout
		_on_rewarded_break_finished([false])

func _on_rewarded_break_finished(args: Array = []) -> void:
	# Duplicate callback guard: reklama tugagan bo'lsa, takroriy callback o'tkazilmaydi
	if not _is_ad_playing or _current_ad_type != AdType.REWARDED:
		print("PokiService: Takroriy yoki eskirgan rewardedBreak callback e'tiborsiz.")
		return

	var success: bool = false
	if args.size() > 0:
		success = bool(args[0])
	print("PokiService: rewardedBreak yakunlandi. Natija: ", success)
	_is_ad_playing = false
	_current_ad_type = AdType.NONE
	_restore_audio()

	# 1. Faqat rewarded callback chaqiriladi!
	var rewarded_cbs := _active_rewarded_callbacks.duplicate()
	_active_rewarded_callbacks.clear()
	for cb in rewarded_cbs:
		if cb.is_valid():
			cb.call(success)

	rewarded_break_completed.emit(success)

	# Agar navbatda boshqa commercial bo'lmasa va start kutayotgan bo'lsa
	var queue_empty: bool = _queued_commercial_requests.is_empty()
	if _gameplay_desired and not _gameplay_notified_to_poki and queue_empty:
		_notify_gameplay_start_if_ready()

	# 2. Commercial va rewarded navbatlari ARALASHMAYDI!
	_check_queued_ad_requests()

func _check_queued_ad_requests() -> void:
	if _queued_commercial_requests.is_empty():
		return

	print("PokiService: Navbatdagi commercial so'rov(lar) ishga tushirilmoqda...")
	var next_callbacks := _queued_commercial_requests.duplicate()
	_queued_commercial_requests.clear()

	for cb in next_callbacks:
		if cb.is_valid() and not _active_commercial_callbacks.has(cb):
			_active_commercial_callbacks.append(cb)

	_start_commercial_break()

func _start_ad_safety_timer(token: int, type: AdType, max_wait: float) -> void:
	var tree := get_tree()
	if not tree or max_wait <= 0.0:
		return
	await tree.create_timer(max_wait).timeout
	if _is_ad_playing and _current_ad_type == type and _ad_token == token:
		print("PokiService: Reklama callback timeout (%.1fs). Tiklanmoqda." % max_wait)
		if type == AdType.COMMERCIAL:
			_on_commercial_break_finished([])
		elif type == AdType.REWARDED:
			_on_rewarded_break_finished([false])
