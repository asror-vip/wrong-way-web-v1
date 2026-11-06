extends Control

# Wrong Way - Main Menu Controller (Clean Web Edition)
# Focused, high-performance main menu for Poki Web release.

@onready var game_title_lbl: Label = get_node_or_null("Header/GameLogo")
@onready var best_chip_lbl: Label = get_node_or_null("TopBar/BestBadge/HBox/BestLabel")
@onready var best_crown_icon: TextureRect = get_node_or_null("TopBar/BestBadge/HBox/CrownIcon")
@onready var settings_top_btn: Button = get_node_or_null("TopBar/SettingsTopBtn")
@onready var menu_character: Control = get_node_or_null("MenuCharacter")

@onready var play_btn: Button = get_node_or_null("MenuStack/PlayBtn")
@onready var play_btn_label: Label = get_node_or_null("MenuStack/PlayBtn/HBox/PlayLabel")
@onready var play_btn_icon: TextureRect = get_node_or_null("MenuStack/PlayBtn/HBox/PlayIcon")
@onready var play_btn_chevron: TextureRect = get_node_or_null("MenuStack/PlayBtn/HBox/ChevronIcon")

@onready var level_select_btn: Button = get_node_or_null("MenuStack/LevelSelectBtn")
@onready var levels_label: Label = get_node_or_null("MenuStack/LevelSelectBtn/HBox/LevelsLabel")
@onready var grid_icon: TextureRect = get_node_or_null("MenuStack/LevelSelectBtn/HBox/GridIcon")
@onready var count_label: Label = get_node_or_null("MenuStack/LevelSelectBtn/HBox/CountLabel")

@onready var settings_modal: Control = get_node_or_null("SettingsModal")

func _ready() -> void:
	LocaleManager.language_changed.connect(_on_language_changed)
	
	_setup_icons()
	_update_all_texts()
	_update_record()
	_play_intro_animation()

func _setup_icons() -> void:
	if best_crown_icon:
		best_crown_icon.texture = IconFactory.get_icon("crown_gold", 0.85)
	if settings_top_btn:
		settings_top_btn.icon = IconFactory.get_icon("circle_btn_gear", 1.0)
		settings_top_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		settings_top_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if play_btn_icon:
		play_btn_icon.texture = IconFactory.get_icon("play_dark", 0.85)
	if play_btn_chevron:
		play_btn_chevron.texture = IconFactory.get_icon("chevron_right", 0.75)
	if grid_icon:
		grid_icon.texture = IconFactory.get_icon("levels_white", 0.85)

func _update_all_texts() -> void:
	if play_btn_label:
		var has_progress := SaveManager.get_highest_unlocked_level() > 1
		play_btn_label.text = LocaleManager.t("btn_continue") if has_progress else LocaleManager.t("btn_play")
	if levels_label:
		levels_label.text = LocaleManager.t("btn_levels")
	if count_label:
		var unlocked := SaveManager.unlocked_levels.size()
		count_label.text = "%d / 60" % mini(60, unlocked)

func _update_record() -> void:
	if best_chip_lbl:
		var stars: int = SaveManager.get_total_stars()
		if stars > 0:
			best_chip_lbl.text = "Best: %d" % stars
		else:
			best_chip_lbl.text = "Best: 0"

func _play_intro_animation() -> void:
	var stack = get_node_or_null("MenuStack")
	if stack:
		stack.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(stack, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_language_changed(_new_lang: String) -> void:
	_update_all_texts()

func _on_play_pressed() -> void:
	SoundManager.play("click")
	var target_lvl := SaveManager.get_highest_unlocked_level()
	GameManager.start_game(target_lvl)

func _on_level_select_pressed() -> void:
	SoundManager.play("click")
	GameManager.go_to_level_select()

func _on_settings_pressed() -> void:
	SoundManager.play("click")
	if settings_modal and settings_modal.has_method("open"):
		settings_modal.open()
