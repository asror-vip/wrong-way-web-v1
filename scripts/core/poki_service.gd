extends Node

# PokiService - Official Poki SDK v2 Integration for Wrong Way (Godot 4 HTML5)
# Handles lifecycle, commercial breaks (interstitial), rewarded breaks, audio muting, and tab blur.

signal commercial_break_completed
signal rewarded_break_completed(success: bool)

enum AdType { NONE, COMMERCIAL, REWARDED }

var is_poki_available: bool = false
var is_gameplay_running: bool = false
var _is_ad_playing: bool = false
var _current_ad_type: AdType = AdType.NONE
var _js_commercial_callback = null
var _js_rewarded_callback = null
var _pending_commercial_callbacks: Array[Callable] = []
var _pending_rewarded_callbacks: Array[Callable] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_poki()
	if OS.has_feature("web") and not is_poki_available:
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

func _init_poki() -> void:
	if OS.has_feature("web"):
		_ensure_poki_sdk()
		if not is_poki_available:
			print("PokiService: PokiSDK hali yuklanmadi, kechikib yuklanish monitoringi boshlandi.")
	else:
		print("PokiService: Desktop muhiti — PokiSDK simulyatsiya rejimida ishlaydi.")

func _ensure_poki_sdk() -> bool:
	if is_poki_available:
		return true
	if OS.has_feature("web"):
		var js_poki = JavaScriptBridge.get_interface("PokiSDK")
		if js_poki:
			is_poki_available = true
			print("PokiService: PokiSDK brauzerda muvaffaqiyatli aniqlandi.")
			JavaScriptBridge.eval("""
				if (window.PokiSDK && !window._poki_initialized) {
					window._poki_initialized = true;
					PokiSDK.init().then(function() {
						console.log('PokiService: PokiSDK.init() muvaffaqiyatli.');
					}).catch(function() {
						console.log('PokiService: PokiSDK.init() xato yoki adblocker.');
					});
				}
			""")
			return true
	return false

func _poll_sdk_availability() -> void:
	if not OS.has_feature("web"):
		return
	for _attempt in range(12):
		if _ensure_poki_sdk():
			break
		await get_tree().create_timer(0.25).timeout

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func game_loading_finished() -> void:
	print("PokiService: gameLoadingFinished()")
	_ensure_poki_sdk()
	if is_poki_available:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameLoadingFinished(); }")

func gameplay_start() -> void:
	if is_gameplay_running:
		return
	is_gameplay_running = true
	print("PokiService: gameplayStart()")
	_ensure_poki_sdk()
	if is_poki_available:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameplayStart(); }")

func gameplay_stop() -> void:
	if not is_gameplay_running:
		return
	is_gameplay_running = false
	print("PokiService: gameplayStop()")
	_ensure_poki_sdk()
	if is_poki_available:
		JavaScriptBridge.eval("if (window.PokiSDK) { PokiSDK.gameplayStop(); }")

# ------------------------------------------------------------------------------
# Commercial Break (Interstitial Ad)
# ------------------------------------------------------------------------------
func commercial_break(on_completed: Callable = Callable()) -> void:
	if on_completed.is_valid() and not _pending_commercial_callbacks.has(on_completed):
		_pending_commercial_callbacks.append(on_completed)

	# Agar hozir allaqachon reklama (commercial yoki rewarded) ko'rsatilayotgan bo'lsa:
	# Callback DARHOL chaqirilmaydi! Reklama tugamasdan o'yin davom etib ketmasligi uchun
	# so'rov navbatga qo'yildi va reklama tugashi bilan birgalikda chaqiriladi.
	if _is_ad_playing:
		print("PokiService: Reklama allaqachon ko'rsatilmoqda. Yangi commercial so'rovi navbatga qo'yildi (o'yin reklama tugamasdan davom etmaydi).")
		return

	print("PokiService: commercialBreak chaqirilmoqda...")
	_is_ad_playing = true
	_current_ad_type = AdType.COMMERCIAL
	gameplay_stop()
	AudioServer.set_bus_mute(0, true)
	
	_ensure_poki_sdk()
	
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
		# Desktop yoki offline muhitda 0.1s dan keyin yakunlanadi
		await get_tree().create_timer(0.1).timeout
		_on_commercial_break_finished([])

func _on_commercial_break_finished(_args: Array = []) -> void:
	print("PokiService: commercialBreak yakunlandi.")
	_is_ad_playing = false
	_current_ad_type = AdType.NONE
	_restore_audio()
	
	var callbacks := _pending_commercial_callbacks.duplicate()
	_pending_commercial_callbacks.clear()
	for cb in callbacks:
		if cb.is_valid():
			cb.call()
			
	commercial_break_completed.emit()

# ------------------------------------------------------------------------------
# Rewarded Break (Rewarded Ad for Level Unlock)
# ------------------------------------------------------------------------------
func rewarded_break(on_reward_result: Callable = Callable()) -> void:
	# Agar hozir boshqa reklama ko'rsatilayotgan bo'lsa:
	# Bir vaqtning o'zida ikkita reklama ko'rsatilishi mumkin emas.
	# Davom etayotgan reklamani buzmasdan ushbu so'rov xavfsiz rad etiladi.
	if _is_ad_playing:
		print("PokiService: Reklama allaqachon ko'rsatilmoqda, yangi rewarded so'rovi xavfsiz rad etildi.")
		if on_reward_result.is_valid():
			on_reward_result.call(false)
		return

	print("PokiService: rewardedBreak chaqirilmoqda...")
	if on_reward_result.is_valid() and not _pending_rewarded_callbacks.has(on_reward_result):
		_pending_rewarded_callbacks.append(on_reward_result)
		
	_is_ad_playing = true
	_current_ad_type = AdType.REWARDED
	gameplay_stop()
	AudioServer.set_bus_mute(0, true)
	
	_ensure_poki_sdk()
	
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
				// Agar PokiSDK bo'lmasa mukofot berilmasin (false)
				window._poki_rewarded_callback(false);
			}
		""")
	else:
		# SDK mavjud bo'lmaganda mukofot berilmaydi (false)
		await get_tree().create_timer(0.1).timeout
		_on_rewarded_break_finished([false])

func _on_rewarded_break_finished(args: Array = []) -> void:
	var success: bool = false
	if args.size() > 0:
		success = bool(args[0])
	print("PokiService: rewardedBreak yakunlandi. Natija: ", success)
	_is_ad_playing = false
	_current_ad_type = AdType.NONE
	_restore_audio()
	
	var rewarded_cbs := _pending_rewarded_callbacks.duplicate()
	_pending_rewarded_callbacks.clear()
	for cb in rewarded_cbs:
		if cb.is_valid():
			cb.call(success)
			
	# Rewarded break vaqtida navbatga tushgan commercial so'rovlar bo'lsa ularni ham chiqaramiz
	var commercial_cbs := _pending_commercial_callbacks.duplicate()
	_pending_commercial_callbacks.clear()
	for cb in commercial_cbs:
		if cb.is_valid():
			cb.call()
			
	rewarded_break_completed.emit(success)
