extends Control
class_name PauseModal

@onready var backdrop: ColorRect = $Backdrop
@onready var card: Panel = $Card
@onready var close_btn: Button = $Card/CloseBtn
@onready var title_label: Label = $Card/TitleLabel
@onready var resume_btn: Button = $Card/BtnBox/ResumeBtn
@onready var restart_btn: Button = $Card/BtnBox/RestartBtn
@onready var settings_btn: Button = get_node_or_null("Card/BtnBox/SettingsBtn")
@onready var levels_btn: Button = get_node_or_null("Card/BtnBox/LevelsBtn")
@onready var home_btn: Button = $Card/BtnBox/HomeBtn
@onready var settings_modal: Control = get_node_or_null("SettingsModal")

var restart_session_count: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	LocaleManager.language_changed.connect(_on_language_changed)
	
	if card:
		card.draw.connect(_on_card_draw)
	
	_setup_icons()
	_update_texts()
	
	if close_btn: close_btn.pressed.connect(_on_resume_pressed)
	if resume_btn: resume_btn.pressed.connect(_on_resume_pressed)
	if restart_btn: restart_btn.pressed.connect(_on_restart_pressed)
	if settings_btn: settings_btn.pressed.connect(_on_settings_pressed)
	if levels_btn: levels_btn.pressed.connect(_on_levels_pressed)
	if home_btn: home_btn.pressed.connect(_on_home_pressed)
	if backdrop:
		backdrop.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if settings_modal and settings_modal.visible:
					return
				_on_resume_pressed()
		)

func _setup_icons() -> void:
	if close_btn:
		close_btn.icon = IconFactory.get_icon("circle_btn_close", 1.0)
		close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		close_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if resume_btn: resume_btn.icon = IconFactory.get_icon("play_dark", 0.85)
	if restart_btn: restart_btn.icon = IconFactory.get_icon("restart", 0.8)
	if settings_btn: settings_btn.icon = IconFactory.get_icon("gear", 0.8)
	if levels_btn: levels_btn.icon = IconFactory.get_icon("levels_white", 0.8)
	if home_btn: home_btn.icon = IconFactory.get_icon("home", 0.8)

func _on_language_changed(_lang: String) -> void:
	_update_texts()

func _update_texts() -> void:
	if title_label:
		title_label.text = "P A U S E D"
	if resume_btn: resume_btn.text = "  " + LocaleManager.t("btn_resume")
	if restart_btn:
		# Restart tugmasiga doim oddiy tekstni yozib turamiz
		restart_btn.text = "  " + LocaleManager.t("btn_restart")

		# Har 4-chi urinish uchun reklama ikonkasini va sariq rangni qo'shamiz
		if (restart_session_count + 1) % 4 == 0:
			restart_btn.icon = IconFactory.get_icon("video_ad", 0.8) # Agar sizda shunday icon bo'lsa
			restart_btn.add_theme_color_override("font_color", Color(0.98, 0.85, 0.40)) # Oltin-sariq rang
			restart_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
		else:
			restart_btn.icon = IconFactory.get_icon("restart", 0.8)
			restart_btn.remove_theme_color_override("font_color")
			restart_btn.remove_theme_color_override("font_hover_color")

	if settings_btn: settings_btn.text = "  " + LocaleManager.t("settings_title")
	if levels_btn: levels_btn.text = "  " + LocaleManager.t("btn_level_select")
	if home_btn: home_btn.text = "  " + LocaleManager.t("btn_home")

func _on_card_draw() -> void:
	if not card: return
	var s := card.size
	var arm := 12.0
	var c := Color(0.85, 0.90, 1.0, 0.55)
	var w := 1.5
	var m := 6.0
	
	card.draw_line(Vector2(m, m + arm), Vector2(m, m), c, w)
	card.draw_line(Vector2(m, m), Vector2(m + arm, m), c, w)
	
	card.draw_line(Vector2(s.x - m - arm, m), Vector2(s.x - m, m), c, w)
	card.draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + arm), c, w)
	
	card.draw_line(Vector2(m, s.y - m - arm), Vector2(m, s.y - m), c, w)
	card.draw_line(Vector2(m, s.y - m), Vector2(m + arm, s.y - m), c, w)
	
	card.draw_line(Vector2(s.x - m - arm, s.y - m), Vector2(s.x - m, s.y - m), c, w)
	card.draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - arm), c, w)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if settings_modal and settings_modal.visible:
				return
			if visible:
				_on_resume_pressed()
			elif GameManager.is_level_running:
				open_pause()

func open_pause() -> void:
	# Pause ochilganda Reset tugmasidagi iconni yangilash uchun update chaqiriladi
	_update_texts()

	visible = true
	get_tree().paused = true
	var poki = get_node_or_null("/root/PokiService")
	if poki and poki.has_method("gameplay_stop"):
		poki.gameplay_stop()
	if card:
		card.queue_redraw()
	SoundManager.play("click")
	SoundManager.set_music_volume_pause(true)

func _on_resume_pressed() -> void:
	SoundManager.play("click")
	SoundManager.set_music_volume_pause(false)
	visible = false
	get_tree().paused = false
	var poki = get_node_or_null("/root/PokiService")
	if poki and poki.has_method("gameplay_start"):
		poki.gameplay_start()

func _on_restart_pressed() -> void:
	SoundManager.play("click")

	# Har bir daraja boshlanganda bu 0 ga tushiriladi (GameManager.restart_current_level ichida bo'lishi mumkin)
	restart_session_count += 1

	# Har 4-chi urinish "Mukofotli" reklama orqali ishlaydi (Rewarded Ad)
	if restart_session_count > 0 and restart_session_count % 4 == 0:
		var adm = get_node_or_null("/root/AdManager")
		if adm and adm.has_method("show_rewarded_ad"):
			adm.show_rewarded_ad(func():
				SoundManager.set_music_volume_pause(false)
				visible = false
				get_tree().paused = false
				GameManager.restart_current_level()
			)
			return

	# Qolgan hollarda tekin qayta boshlanadi
	SoundManager.set_music_volume_pause(false)
	visible = false
	get_tree().paused = false
	GameManager.restart_current_level()

func _on_settings_pressed() -> void:
	SoundManager.play("click")
	if settings_modal:
		settings_modal.open()

func _on_levels_pressed() -> void:
	SoundManager.play("click")
	SoundManager.set_music_volume_pause(false)
	visible = false
	get_tree().paused = false
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		sm.navigation_source = "game_pause"
		sm.return_level_num = GameManager.current_level_id
	get_tree().change_scene_to_file("res://scenes/main/level_select.tscn")

func _on_home_pressed() -> void:
	SoundManager.play("click")
	SoundManager.set_music_volume_pause(false)
	visible = false
	get_tree().paused = false
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		sm.navigation_source = "home_menu"
		sm.should_restore_result_modal = false
	GameManager.go_to_main_menu()
