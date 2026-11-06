extends Control

# Wrong Way - Main Menu Controller
# Reimagined with Dark Atmospheric Silhouette Art Style & Glowing White Glass UI (Poki Web Edition)

@onready var game_title_lbl: Label = get_node_or_null("Header/GameLogo")
@onready var best_chip_lbl: Label = get_node_or_null("TopBar/BestBadge/HBox/BestLabel")
@onready var best_crown_icon: TextureRect = get_node_or_null("TopBar/BestBadge/HBox/CrownIcon")
@onready var menu_character: Control = get_node_or_null("MenuCharacter")
@onready var settings_top_btn: Button = get_node_or_null("TopBar/SettingsTopBtn")
@onready var quit_top_btn: Button = get_node_or_null("TopBar/QuitTopBtn")

@onready var play_btn: Button = get_node_or_null("MenuStack/PlayBtn")
@onready var play_btn_label: Label = get_node_or_null("MenuStack/PlayBtn/HBox/PlayLabel")
@onready var play_btn_icon: TextureRect = get_node_or_null("MenuStack/PlayBtn/HBox/PlayIcon")
@onready var play_btn_chevron: TextureRect = get_node_or_null("MenuStack/PlayBtn/HBox/ChevronIcon")
@onready var level_select_btn: Button = get_node_or_null("MenuStack/LevelSelectBtn")

@onready var settings_modal: Control = get_node_or_null("SettingsModal")
@onready var info_modal: Control = get_node_or_null("InfoModal")
@onready var info_title_icon: TextureRect = get_node_or_null("InfoModal/Card/TitleRow/TitleIcon")
@onready var info_title_label: Label = get_node_or_null("InfoModal/Card/TitleRow/TitleLabel")
@onready var info_desc_label: Label = get_node_or_null("InfoModal/Card/Content/DescLabel")
@onready var info_close_btn: Button = get_node_or_null("InfoModal/Card/CloseBtn")
@onready var info_backdrop: ColorRect = get_node_or_null("InfoModal/Backdrop")

func _ready() -> void:
	LocaleManager.language_changed.connect(_on_language_changed)
	
	if info_backdrop:
		info_backdrop.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_info_close_pressed()
		)
	
	_setup_icons()
	_update_all_texts()
	_update_record()
	
	if quit_top_btn and menu_character:
		quit_top_btn.mouse_entered.connect(func():
			if menu_character.has_method("set_sad_emotion"):
				menu_character.set_sad_emotion(true)
		)
		quit_top_btn.mouse_exited.connect(func():
			if menu_character.has_method("set_sad_emotion"):
				menu_character.set_sad_emotion(false)
		)
		
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
		
	SoundManager.set_gameplay_mode(false)
	SoundManager.play_music()

func _apply_responsive_layout() -> void:
	var insets := UIResponsive.get_safe_insets(self)
	var vp := UIResponsive.get_viewport_size(self)
	
	if settings_top_btn:
		settings_top_btn.position.x = 24.0 + insets["left"]
		settings_top_btn.position.y = 20.0 + insets["top"]
	if quit_top_btn:
		quit_top_btn.position.x = 24.0 + insets["left"]
		quit_top_btn.position.y = 74.0 + insets["top"]
		
	var best_badge = get_node_or_null("TopBar/BestBadge")
	if best_badge:
		best_badge.position.x = vp.x - 140.0 - insets["right"]
		best_badge.position.y = 17.0 + insets["top"]
		
	var header = get_node_or_null("Header")
	if header:
		header.position.x = 72.0 + insets["left"]
	if menu_character:
		menu_character.position.x = 78.0 + insets["left"]
		
	var menu_stack = get_node_or_null("MenuStack")
	if menu_stack:
		# Kichik ekranlar (4:3 tabletlar) uchun tugmalarning chapdagi cliff bilan to'qnashmasligi
		var target_x: float = vp.x - 380.0 - float(insets["right"])
		if target_x < 390.0:
			target_x = maxf(280.0, vp.x - 320.0 - float(insets["right"]))
		menu_stack.position.x = target_x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if settings_modal and settings_modal.visible:
				settings_modal.close()
				get_viewport().set_input_as_handled()
				return
			if info_modal and info_modal.visible:
				_on_info_close_pressed()
				get_viewport().set_input_as_handled()
				return

func _setup_icons() -> void:
	if best_crown_icon:
		best_crown_icon.texture = IconFactory.get_icon("crown_gold", 0.85)
	if settings_top_btn:
		settings_top_btn.icon = IconFactory.get_icon("circle_btn_gear", 1.0)
		settings_top_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		settings_top_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if quit_top_btn:
		quit_top_btn.icon = IconFactory.get_icon("circle_btn_quit", 1.0)
		quit_top_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quit_top_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if play_btn_icon:
		play_btn_icon.texture = IconFactory.get_icon("play_dark", 0.9)
	if play_btn_chevron:
		play_btn_chevron.texture = IconFactory.get_icon("chevron_right", 0.8)
	if level_select_btn:
		level_select_btn.icon = IconFactory.get_icon("level_select", 0.85)
	if info_close_btn:
		info_close_btn.icon = IconFactory.get_icon("circle_btn_close", 1.0)
		info_close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_close_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

func _on_language_changed(_lang: String) -> void:
	_update_all_texts()

func _update_all_texts() -> void:
	if game_title_lbl:
		game_title_lbl.text = "WRONG\nWAY"
	if play_btn_label:
		var has_progress := SaveManager.get_highest_unlocked_level() > 1
		play_btn_label.text = LocaleManager.t("btn_continue") if has_progress else LocaleManager.t("btn_play")
	if level_select_btn:
		level_select_btn.text = "   " + LocaleManager.t("btn_levels")
	_update_record()

func _update_record() -> void:
	if best_chip_lbl:
		var stars: int = SaveManager.get_total_stars()
		if stars > 0:
			best_chip_lbl.text = "Best: %d" % stars
		else:
			best_chip_lbl.text = "Best: 0"

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

func _on_quit_pressed() -> void:
	SoundManager.play("click")
	if OS.has_feature("web"):
		# Brauzerda ilovani yopib bo'lmaydi, o'yin ma'lumotini ochamiz
		if info_modal:
			if info_title_label: info_title_label.text = "WRONG WAY"
			if info_desc_label: info_desc_label.text = "Wrong Way — Competitive 2D Trap-Platformer.\n\nPoki Web Edition.\nBarcha 60 ta darajadan muvaffaqiyatli o'tib, yulduzlarni to'plang!"
			info_modal.visible = true
	else:
		get_tree().quit()

func _on_info_close_pressed() -> void:
	SoundManager.play("click")
	if info_modal:
		info_modal.visible = false
