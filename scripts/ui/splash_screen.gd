extends Control

# Wrong Way - High-End Commercial Splash & Loading Screen (Poki Web Edition)
# - Atmospheric Ken Burns background camera drift
# - Volumetric vignette & glow-pulsing logo
# - Animated loading progress bar with cycling hints
# - On 100% load: signals PokiService.game_loading_finished() and transitions straight to Main Menu

@onready var bg_texture: TextureRect = $Background
@onready var vignette: ColorRect = $Vignette
@onready var logo_container: VBoxContainer = $CenterBox
@onready var bottom_box: VBoxContainer = $BottomBox
@onready var progress_bar: ProgressBar = $BottomBox/ProgressBar
@onready var status_label: Label = $BottomBox/StatusLabel
@onready var version_label: Label = $BottomBox/VersionLabel
@onready var curtain: ColorRect = $Curtain

var load_progress: float = 0.0
var target_progress: float = 0.0
var is_transitioning: bool = false

const HINTS := [
	"O'yin sozlamalari tekshirilmoqda...",
	"Tuzoqlarning barcha mexanizmlari yashirilmoqda...",
	"Hech qachon pol va eshiklarga ko'r-ko'rona ishonmang...",
	"Hamma narsa tayyor. Qorong'u olamga xush kelibsiz!"
]

func _ready() -> void:
	if curtain:
		curtain.modulate.a = 1.0
		var fade_in := create_tween()
		fade_in.tween_property(curtain, "modulate:a", 0.0, 0.35)

	if progress_bar:
		progress_bar.value = 0.0

	_update_hint(0)
	_start_background_drift()
	_apply_safe_insets()
	get_viewport().size_changed.connect(_apply_safe_insets)
	_run_loading_flow()

func _apply_safe_insets() -> void:
	var insets := UIResponsive.get_safe_insets(self)
	var b_margin: float = float(insets.get("bottom", 0.0))
	if bottom_box:
		bottom_box.offset_bottom = -30.0 - b_margin

func _start_background_drift() -> void:
	if not bg_texture:
		return
	bg_texture.pivot_offset = Vector2(480, 270)
	var tween := create_tween().set_loops()
	tween.tween_property(bg_texture, "scale", Vector2(1.04, 1.04), 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(bg_texture, "scale", Vector2(1.0, 1.0), 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _update_hint(idx: int) -> void:
	if status_label and idx < HINTS.size():
		var tween := create_tween()
		tween.tween_property(status_label, "modulate:a", 0.0, 0.12)
		tween.tween_callback(func():
			status_label.text = HINTS[idx]
		)
		tween.tween_property(status_label, "modulate:a", 1.0, 0.18)

func _run_loading_flow() -> void:
	target_progress = 35.0
	await get_tree().create_timer(0.25).timeout
	_update_hint(1)

	target_progress = 75.0
	await get_tree().create_timer(0.35).timeout
	_update_hint(2)

	target_progress = 100.0
	await get_tree().create_timer(0.30).timeout
	_update_hint(3)
	await get_tree().create_timer(0.20).timeout

	_finish_and_open_main_menu()

func _process(delta: float) -> void:
	if load_progress < target_progress:
		load_progress = move_toward(load_progress, target_progress, delta * 140.0)
		if progress_bar:
			progress_bar.value = load_progress

func _finish_and_open_main_menu() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	# Poki ga o'yin yuklanishi yakunlanganini bildiramiz
	var poki = get_node_or_null("/root/PokiService")
	if poki and poki.has_method("game_loading_finished"):
		poki.game_loading_finished()

	if curtain:
		var fade_out := create_tween()
		fade_out.tween_property(curtain, "modulate:a", 1.0, 0.35)
		fade_out.tween_callback(func():
			get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
		)
	else:
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
