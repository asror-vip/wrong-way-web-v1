extends Node

# Wrong Way — AdManager (Poki Web Ad Adapter)
# Bridges game reward & interstitial requests directly to PokiService (PokiSDK v2).

signal banner_visibility_changed(is_visible: bool)
signal rewarded_ad_started
signal rewarded_ad_completed(reward_granted: bool)
signal interstitial_ad_completed

var is_banner_active: bool = false
var banner_enabled: bool = false
var consent_granted: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# -------------------------------------------------------------
# Banner Ads (Poki handles display ads around the canvas)
# -------------------------------------------------------------
func show_banner() -> void:
	is_banner_active = false
	banner_visibility_changed.emit(false)

func hide_banner() -> void:
	is_banner_active = false
	banner_visibility_changed.emit(false)

# -------------------------------------------------------------
# Interstitial / Commercial Break
# -------------------------------------------------------------
func show_interstitial_replay(on_completed: Callable = Callable()) -> void:
	show_interstitial(on_completed)

func show_interstitial(on_completed: Callable = Callable()) -> void:
	var poki = get_node_or_null("/root/PokiService")
	if poki and poki.has_method("commercial_break"):
		poki.commercial_break(func():
			if on_completed.is_valid():
				on_completed.call()
			interstitial_ad_completed.emit()
		)
	else:
		if on_completed.is_valid():
			on_completed.call()
		interstitial_ad_completed.emit()

# -------------------------------------------------------------
# Rewarded Video Break (PokiSDK.rewardedBreak)
# -------------------------------------------------------------
func show_rewarded_ad(on_reward_callback: Callable = Callable()) -> void:
	rewarded_ad_started.emit()
	var poki = get_node_or_null("/root/PokiService")
	if poki and poki.has_method("rewarded_break"):
		poki.rewarded_break(func(success: bool):
			if success and on_reward_callback.is_valid():
				on_reward_callback.call()
			rewarded_ad_completed.emit(success)
		)
	else:
		# Fallback
		if on_reward_callback.is_valid():
			on_reward_callback.call()
		rewarded_ad_completed.emit(true)

func is_rewarded_ready() -> bool:
	return true

func set_consent(_granted: bool) -> void:
	consent_granted = true
