extends Control

# Wrong Way - Game HUD Controller
# Atmospheric Minimalist HUD with Circular Glass Controls & Diamond Header

@onready var pause_btn: Button = get_node_or_null("TopHUD/PauseBtn")
@onready var level_label: Label = get_node_or_null("TopHUD/CenterHeader/HBox/LevelLabel")
@onready var time_icon: TextureRect = get_node_or_null("TopHUD/RightBox/TimeChip/HBox/TimeIcon")
@onready var time_label: Label = get_node_or_null("TopHUD/RightBox/TimeChip/HBox/TimeLabel")
@onready var skull_icon: TextureRect = get_node_or_null("TopHUD/RightBox/DeathsChip/HBox/SkullIcon")
@onready var deaths_label: Label = get_node_or_null("TopHUD/RightBox/DeathsChip/HBox/DeathsLabel")

@onready var left_btn: Button = get_node_or_null("TouchControls/LeftBtn")
@onready var right_btn: Button = get_node_or_null("TouchControls/RightBtn")
@onready var dash_btn: Button = get_node_or_null("TouchControls/DashBtn")
@onready var jump_btn: Button = get_node_or_null("TouchControls/JumpBtn")
@onready var touch_controls: Control = get_node_or_null("TouchControls")

@onready var countdown_box: CenterContainer = get_node_or_null("CountdownBox")
@onready var countdown_label: Label = get_node_or_null("CountdownBox/CountdownLabel")

var current_deaths: int = 0

func _ready() -> void:
	LocaleManager.language_changed.connect(_on_language_changed)
	GameManager.player_died.connect(_on_player_died)
	GameManager.level_started.connect(_on_level_started)
	SaveManager.touch_layout_changed.connect(_apply_custom_touch_layout)
	get_viewport().size_changed.connect(_apply_custom_touch_layout)
	
	_apply_custom_touch_layout()
	_setup_icons()
	_update_texts()
	
	if left_btn: _setup_touch_btn(left_btn, "move_left")
	if right_btn: _setup_touch_btn(right_btn, "move_right")
	if dash_btn: _setup_touch_btn(dash_btn, "dash")
	if jump_btn: _setup_touch_btn(jump_btn, "jump")
	_update_touch_visibility()

func _update_touch_visibility() -> void:
	# Touch boshqaruv tugmalari faqat sensorli qurilmalarda ko'rsatiladi.
	var is_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	if touch_controls:
		touch_controls.visible = is_touch

func _apply_custom_touch_layout() -> void:
	var def_positions := UIResponsive.get_default_touch_positions(self)
	var insets := UIResponsive.get_safe_insets(self)
	
	if pause_btn:
		pause_btn.position = Vector2(20.0 + insets["left"], 16.0 + insets["top"])
		
	var right_box: Control = get_node_or_null("TopHUD/RightBox")
	if right_box:
		var vp := UIResponsive.get_viewport_size(self)
		right_box.position = Vector2(vp.x - right_box.size.x - 20.0 - insets["right"], 16.0 + insets["top"])
	
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		if left_btn: left_btn.position = sm.get_touch_pos("left", def_positions["left"])
		if right_btn: right_btn.position = sm.get_touch_pos("right", def_positions["right"])
		if dash_btn: dash_btn.position = sm.get_touch_pos("dash", def_positions["dash"])
		if jump_btn: jump_btn.position = sm.get_touch_pos("jump", def_positions["jump"])
	else:
		if left_btn: left_btn.position = def_positions["left"]
		if right_btn: right_btn.position = def_positions["right"]
		if dash_btn: dash_btn.position = def_positions["dash"]
		if jump_btn: jump_btn.position = def_positions["jump"]

func _process(_delta: float) -> void:
	if time_label:
		if GameManager.is_level_running:
			var elapsed_sec: float = (float(Time.get_ticks_msec()) - GameManager.level_start_time) / 1000.0
			time_label.text = "%ds" % int(maxf(elapsed_sec, 0.0))
		elif GameManager.level_timer_ms > 0:
			time_label.text = "%ds" % int(GameManager.level_timer_ms / 1000.0)

func _setup_icons() -> void:
	if pause_btn:
		pause_btn.icon = IconFactory.get_icon("circle_btn_pause", 1.0)
		pause_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pause_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if time_icon:
		time_icon.texture = IconFactory.get_icon("timer_white", 0.8)
	if skull_icon:
		skull_icon.texture = IconFactory.get_icon("skull_white", 0.8)
	if left_btn:
		left_btn.icon = IconFactory.get_icon("circle_btn_left", 1.0)
		left_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if right_btn:
		right_btn.icon = IconFactory.get_icon("circle_btn_right", 1.0)
		right_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if dash_btn:
		dash_btn.icon = IconFactory.get_icon("circle_btn_dash", 1.0)
		dash_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if jump_btn:
		jump_btn.icon = IconFactory.get_icon("circle_btn_jump", 1.0)
		jump_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		jump_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

	# TouchControls faqat mobil qurilmalar uchun ko'rsatiladi
	var touch_controls = get_node_or_null("TouchControls")
	if touch_controls:
		if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
			touch_controls.visible = true
		else:
			touch_controls.visible = false

func _on_language_changed(_lang: String) -> void:
	_update_texts()

func _on_level_started(_level_id: int) -> void:
	current_deaths = GameManager.level_deaths
	_update_texts()
	_update_deaths_display()

func _update_texts() -> void:
	if level_label:
		level_label.text = LocaleManager.t("level_header", [GameManager.current_level_id])
	_update_deaths_display()

func _on_player_died(deaths_count: int) -> void:
	current_deaths = deaths_count
	_update_deaths_display()

func _update_deaths_display() -> void:
	if deaths_label:
		deaths_label.text = "%d" % current_deaths

func _setup_touch_btn(btn: Button, action: String) -> void:
	btn.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				Input.action_press(action)
			else:
				Input.action_release(action)
	)
	btn.button_down.connect(func(): Input.action_press(action))
	btn.button_up.connect(func(): Input.action_release(action))
	btn.mouse_exited.connect(func():
		if Input.is_action_pressed(action):
			Input.action_release(action)
	)

func _on_pause_btn_pressed() -> void:
	SoundManager.play("click")
	var parent_canvas = get_parent()
	if parent_canvas:
		var pause_modal = parent_canvas.get_node_or_null("PauseModal")
		if pause_modal and pause_modal.has_method("open_pause"):
			pause_modal.open_pause()
			return
	var pause_node = get_tree().current_scene.find_child("PauseModal", true, false)
	if pause_node and pause_node.has_method("open_pause"):
		pause_node.open_pause()
