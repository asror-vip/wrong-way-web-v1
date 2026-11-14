extends Control

# Wrong Way - Level Select (Campaign Map)
# Advanced Multi-Chapter System using Custom Artwork from assets/images/maps-images:
# - Chapter 1 (1-20): "1.jpg" (Limbo dark forest winding mountain road)
# - Chapter 2 (21-40): "2.jpg" (Winter snow / ice peaks winding road)
# - Circular level buttons (38x38) positioned directly on the painted road centerline
# - Path is visually native to the artwork (no procedural black lines over the art)
# - Clouds appear when next chapter is locked, and vanish when unlocked!
# - Smooth sliding animation between chapters (60fps cubic tween + swipe)
# - TopBar: Chapter 1 shows X / 60, Chapter 2 shows 0 / 55

const UNIFIED_ROAD_POS: Array[Vector2] = [
	Vector2(38, 192),   # 1: Yo'l boshlanishi
	Vector2(117, 218),  # 2: Birinchi pastlik nishabi
	Vector2(163, 330),  # 3: Tik pastga tushish
	Vector2(241, 417),  # 4: Pastki halqa markazi
	Vector2(290, 321),  # 5: Tik ko'tarilish
	Vector2(306, 201),  # 6: Tog' sari burilish
	Vector2(399, 126),  # 7: Cho'qqi nishabi
	Vector2(512, 128),  # 8: Asosiy cho'qqi
	Vector2(496, 224),  # 9: S-yo'lak kirishi
	Vector2(434, 296),  # 10: O'rta halqa chap qulog'i
	Vector2(536, 325),  # 11: O'rta halqadan chiqish
	Vector2(600, 222),  # 12: Tosh ko'prik boshlanishi
	Vector2(691, 141),  # 13: Tosh ko'prik yakuni
	Vector2(806, 128),  # 14: O'ng qoya cho'qqisi
	Vector2(804, 224),  # 15: O'ng nishab
	Vector2(694, 267),  # 16: O'ng ichki qayrilish
	Vector2(673, 376),  # 17: Quyi ichki halqa
	Vector2(765, 396),  # 18: Pastki to'g'ri trassa
	Vector2(848, 318),  # 19: Chiqish nishabi
	Vector2(934, 230),  # 20: 1-bob marrasi / 2-bobga ulanish
]

const CHAPTER_1_POS: Array[Vector2] = UNIFIED_ROAD_POS
const CHAPTER_2_POS: Array[Vector2] = UNIFIED_ROAD_POS
const CHAPTER_3_POS: Array[Vector2] = UNIFIED_ROAD_POS

@onready var chapter_slider: Control = $ChapterSlider
@onready var ch1_view: Control = $ChapterSlider/Chapter1View
@onready var backdrop_ch1: TextureRect = $ChapterSlider/Chapter1View/BackdropCh1
@onready var map_draw1: Control = $ChapterSlider/Chapter1View/MapDraw1
@onready var node_layer1: Control = $ChapterSlider/Chapter1View/NodeLayer1

@onready var pass1: Control = get_node_or_null("ChapterSlider/MountainPass1")

@onready var ch2_view: Control = $ChapterSlider/Chapter2View
@onready var backdrop_ch2: TextureRect = $ChapterSlider/Chapter2View/BackdropCh2
@onready var map_draw2: Control = $ChapterSlider/Chapter2View/MapDraw2
@onready var node_layer2: Control = $ChapterSlider/Chapter2View/NodeLayer2

@onready var pass2: Control = get_node_or_null("ChapterSlider/MountainPass2")
@onready var ch3_view: Control = get_node_or_null("ChapterSlider/Chapter3View")
@onready var backdrop_ch3: TextureRect = get_node_or_null("ChapterSlider/Chapter3View/BackdropCh3")
@onready var map_draw3: Control = get_node_or_null("ChapterSlider/Chapter3View/MapDraw3")
@onready var node_layer3: Control = get_node_or_null("ChapterSlider/Chapter3View/NodeLayer3")

@onready var back_btn: Button = $TopBar/BackButton
@onready var title_label: Label = $TopBar/TitleLabel
@onready var total_stars_chip: Label = $TopBar/TotalStarsChip

@onready var side_nav_right: Button = $SideNavRight
@onready var side_nav_left: Button = $SideNavLeft
@onready var btn_ch1: Button = $BottomBar/HBox/BtnCh1
@onready var btn_ch2: Button = $BottomBar/HBox/BtnCh2
@onready var btn_ch3: Button = get_node_or_null("BottomBar/HBox/BtnCh3")

var style_white = preload("res://resources/themes/btn_capsule_white.tres")
var style_white_hov = preload("res://resources/themes/btn_capsule_white_hover.tres")
var style_white_press = preload("res://resources/themes/btn_capsule_white_pressed.tres")
var style_glass = preload("res://resources/themes/btn_capsule_glass.tres")
var style_glass_hov = preload("res://resources/themes/btn_capsule_glass_hover.tres")
var style_glass_press = preload("res://resources/themes/btn_capsule_glass_pressed.tres")
var empty_focus = preload("res://resources/themes/btn_focus_empty.tres")

var current_chapter: int = 1
var is_animating: bool = false
var star_chip_icon: TextureRect

var ch4_view: Control = null
var ch5_view: Control = null
var backdrop_ch4: TextureRect = null
var backdrop_ch5: TextureRect = null
var lock_card_ch4: Control = null
var lock_card_ch5: Control = null

# Jonli interaktiv surish (Continuous Drag & Halfway Snap)
var is_dragging: bool = false
var has_dragged: bool = false
var drag_start_x: float = 0.0
var slider_start_x: float = 0.0
var drag_accum_dist: float = 0.0

func _ready() -> void:
	var adm = get_node_or_null("/root/AdManager")
	if adm and adm.has_method("show_banner"):
		adm.show_banner()
	
	LocaleManager.language_changed.connect(_on_language_changed)
	SoundManager.set_gameplay_mode(false)
	SoundManager.play_music()
	
	_setup_coming_soon_views()
	_setup_top_bar()
	_setup_nav_connections()
	_setup_seamless_backdrop_materials()
	_setup_widescreen_layout()
	get_viewport().size_changed.connect(_setup_widescreen_layout)
		
	# Boshlang'ich holatda 1, 2 va 3-bob doiralarini yaratish
	_create_nodes_for_chapter(1)
	_create_nodes_for_chapter(2)
	_create_nodes_for_chapter(3)
	
	_update_chapter_locks()
	
	# Boshlang'ich bobni animatsiyasiz ko'rsatish
	switch_to_chapter(1, false)

func _setup_coming_soon_views() -> void:
	if not chapter_slider:
		return

	var blur_shader = preload("res://shaders/bokeh_blur.gdshader")

	# 4-BOB (Sahro / Oltin Kanyon)
	ch4_view = chapter_slider.get_node_or_null("Chapter4View")
	if not ch4_view:
		ch4_view = Control.new()
		ch4_view.name = "Chapter4View"
		ch4_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chapter_slider.add_child(ch4_view)

		backdrop_ch4 = TextureRect.new()
		backdrop_ch4.name = "BackdropCh4"
		backdrop_ch4.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop_ch4.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var tex4 = load("res://assets/images/maps-images/4.jpg")
		if tex4:
			backdrop_ch4.texture = tex4

		var m4 := ShaderMaterial.new()
		m4.shader = blur_shader
		m4.set_shader_parameter("blur_amount", 0.0)
		backdrop_ch4.material = m4
		ch4_view.add_child(backdrop_ch4)

		lock_card_ch4 = _create_coming_soon_card(
			4,
			LocaleManager.t("chapter_4_title"),
			LocaleManager.t("chapter_4_desc")
		)
		ch4_view.add_child(lock_card_ch4)

	# 5-BOB (Lava / Olovli Abiss)
	ch5_view = chapter_slider.get_node_or_null("Chapter5View")
	if not ch5_view:
		ch5_view = Control.new()
		ch5_view.name = "Chapter5View"
		ch5_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		chapter_slider.add_child(ch5_view)

		backdrop_ch5 = TextureRect.new()
		backdrop_ch5.name = "BackdropCh5"
		backdrop_ch5.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop_ch5.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var tex5 = load("res://assets/images/maps-images/5.jpg")
		if not tex5:
			tex5 = load("res://assets/images/maps-images/5.png")
		if tex5:
			backdrop_ch5.texture = tex5

		var m5 := ShaderMaterial.new()
		m5.shader = blur_shader
		m5.set_shader_parameter("blur_amount", 0.0)
		backdrop_ch5.material = m5
		ch5_view.add_child(backdrop_ch5)

		lock_card_ch5 = _create_coming_soon_card(
			5,
			LocaleManager.t("chapter_5_title"),
			LocaleManager.t("chapter_5_desc")
		)
		ch5_view.add_child(lock_card_ch5)

func _create_coming_soon_card(chapter: int, title_str: String, desc_str: String) -> Control:
	var card_w: float = 380.0
	var card_h: float = 90.0

	var card := PanelContainer.new()
	card.name = "ComingSoonCard%d" % chapter
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size = Vector2(card_w, card_h)
	card.position = Vector2(
		(get_viewport_rect().size.x - card_w) * 0.5,
		(get_viewport_rect().size.y - card_h) * 0.5
	)
	card.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.94)
	style.border_color = Color("#f59e0b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.75)
	style.shadow_size = 16
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var lock_icon := IconFactory.create_texture_rect("lock", Vector2(22, 22), 0.9)
	hbox.add_child(lock_icon)

	var lbl_title := Label.new()
	lbl_title.name = "Title"
	lbl_title.text = title_str.to_upper()
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.add_theme_color_override("font_color", Color(0.98, 0.90, 0.55))
	hbox.add_child(lbl_title)

	var lbl_sub := Label.new()
	lbl_sub.name = "Sub"
	var coming_soon_tag := "✦  " + LocaleManager.t("coming_soon_caps") + "  ✦\n"
	lbl_sub.text = coming_soon_tag + desc_str
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 12)
	lbl_sub.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))
	vbox.add_child(lbl_sub)

	return card

func _refresh_coming_soon_cards() -> void:
	if lock_card_ch4:
		var t4: Label = lock_card_ch4.get_node_or_null("VBox/HBox/Title")
		var s4: Label = lock_card_ch4.get_node_or_null("VBox/Sub")
		if t4: t4.text = LocaleManager.t("chapter_4_title").to_upper()
		if s4:
			var p4 := "✦  " + LocaleManager.t("coming_soon_caps") + "  ✦\n"
			s4.text = p4 + LocaleManager.t("chapter_4_desc")
	if lock_card_ch5:
		var t5: Label = lock_card_ch5.get_node_or_null("VBox/HBox/Title")
		var s5: Label = lock_card_ch5.get_node_or_null("VBox/Sub")
		if t5: t5.text = LocaleManager.t("chapter_5_title").to_upper()
		if s5:
			var p5 := "✦  " + LocaleManager.t("coming_soon_caps") + "  ✦\n"
			s5.text = p5 + LocaleManager.t("chapter_5_desc")

func _get_step_width() -> float:
	return get_viewport_rect().size.x

func _get_map_transform() -> Dictionary:
	var vp := get_viewport_rect().size
	var s: float = maxf(vp.x / 960.0, vp.y / 540.0)
	var ox: float = (vp.x - 960.0 * s) * 0.5
	var oy: float = (vp.y - 540.0 * s) * 0.5
	return {"scale": s, "offset": Vector2(ox, oy)}

func _get_map_offset() -> Vector2:
	return _get_map_transform()["offset"]

func _setup_widescreen_layout() -> void:
	var step_w := _get_step_width()
	if ch1_view:
		ch1_view.offset_left = 0.0
		ch1_view.offset_right = 0.0
	if ch2_view:
		ch2_view.offset_left = step_w
		ch2_view.offset_right = step_w
	if ch3_view:
		ch3_view.offset_left = step_w * 2.0
		ch3_view.offset_right = step_w * 2.0
	if ch4_view:
		ch4_view.offset_left = step_w * 3.0
		ch4_view.offset_right = step_w * 3.0
		if lock_card_ch4:
			lock_card_ch4.position = Vector2((step_w - lock_card_ch4.size.x) * 0.5, (get_viewport_rect().size.y - lock_card_ch4.size.y) * 0.5)
	if ch5_view:
		ch5_view.offset_left = step_w * 4.0
		ch5_view.offset_right = step_w * 4.0
		if lock_card_ch5:
			lock_card_ch5.position = Vector2((step_w - lock_card_ch5.size.x) * 0.5, (get_viewport_rect().size.y - lock_card_ch5.size.y) * 0.5)

	var insets := UIResponsive.get_safe_insets(self)
	if back_btn:
		back_btn.position.x = 20.0 + insets["left"]
	if total_stars_chip:
		total_stars_chip.position.x = step_w - total_stars_chip.size.x - 20.0 - insets["right"]
	if side_nav_right:
		side_nav_right.position.x = step_w - side_nav_right.size.x - 16.0 - insets["right"]
	if side_nav_left:
		side_nav_left.position.x = 16.0 + insets["left"]
		
	if toast_panel and toast_panel.visible:
		toast_panel.position.x = (step_w - toast_panel.size.x) * 0.5
		
	_reposition_all_chapter_nodes()

func _reposition_all_chapter_nodes() -> void:
	_position_nodes(1, node_layer1)
	_position_nodes(2, node_layer2)
	_position_nodes(3, node_layer3)

func _position_nodes(chapter: int, container: Control) -> void:
	if not container or not is_inside_tree():
		return
	var positions := CHAPTER_1_POS
	if chapter == 2:
		positions = CHAPTER_2_POS
	elif chapter == 3:
		positions = CHAPTER_3_POS
	var t := _get_map_transform()
	var s: float = t["scale"]
	var offset: Vector2 = t["offset"]
	var children := container.get_children()
	for i in range(mini(children.size(), positions.size())):
		var btn = children[i] as Control
		if btn:
			btn.position = positions[i] * s + offset - Vector2(19.0 * s, 19.0 * s)
			btn.scale = Vector2(s, s)

func _setup_seamless_backdrop_materials() -> void:
	var blur_shader = preload("res://shaders/bokeh_blur.gdshader")
	
	if backdrop_ch1:
		var m1 := ShaderMaterial.new()
		m1.shader = blur_shader
		m1.set_shader_parameter("blur_amount", 0.0)
		m1.set_shader_parameter("fade_left", 0.0)
		m1.set_shader_parameter("fade_right", 0.0)
		backdrop_ch1.material = m1
		backdrop_ch1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
	if backdrop_ch2:
		var m2 := ShaderMaterial.new()
		m2.shader = blur_shader
		m2.set_shader_parameter("blur_amount", 0.0)
		m2.set_shader_parameter("fade_left", 0.0)
		m2.set_shader_parameter("fade_right", 0.0)
		backdrop_ch2.material = m2
		backdrop_ch2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
	if backdrop_ch3:
		var m3 := ShaderMaterial.new()
		m3.shader = blur_shader
		m3.set_shader_parameter("blur_amount", 0.0)
		m3.set_shader_parameter("fade_left", 0.0)
		m3.set_shader_parameter("fade_right", 0.0)
		backdrop_ch3.material = m3
		backdrop_ch3.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _setup_top_bar() -> void:
	if back_btn:
		back_btn.icon = IconFactory.get_icon("circle_btn_back", 1.0)
		back_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		back_btn.text = ""
		var empty_sb := StyleBoxEmpty.new()
		back_btn.add_theme_stylebox_override("normal", empty_sb)
		back_btn.add_theme_stylebox_override("hover", empty_sb)
		back_btn.add_theme_stylebox_override("pressed", empty_sb)
		back_btn.add_theme_stylebox_override("focus", empty_sb)
		if not back_btn.pressed.is_connected(_on_back_pressed):
			back_btn.pressed.connect(_on_back_pressed)
	
	if total_stars_chip and star_chip_icon == null:
		star_chip_icon = IconFactory.create_texture_rect("crown_gold", Vector2(16, 16), 0.75)
		star_chip_icon.position = Vector2(8, (total_stars_chip.size.y - 16) / 2.0)
		total_stars_chip.add_child(star_chip_icon)

func _setup_nav_connections() -> void:
	var solid_box := StyleBoxFlat.new()
	solid_box.set_corner_radius_all(22)
	solid_box.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	solid_box.border_color = Color(0.35, 0.45, 0.65, 0.90)
	solid_box.set_border_width_all(1.5)
	solid_box.shadow_color = Color(0, 0, 0, 0.6)
	solid_box.shadow_size = 6
	
	if side_nav_right:
		side_nav_right.add_theme_stylebox_override("normal", solid_box)
		side_nav_right.add_theme_stylebox_override("hover", solid_box)
		side_nav_right.add_theme_stylebox_override("pressed", solid_box)
		side_nav_right.pressed.connect(_on_side_nav_right_pressed)
	if side_nav_left:
		side_nav_left.add_theme_stylebox_override("normal", solid_box)
		side_nav_left.add_theme_stylebox_override("hover", solid_box)
		side_nav_left.add_theme_stylebox_override("pressed", solid_box)
		side_nav_left.pressed.connect(func():
			if current_chapter > 1:
				switch_to_chapter(current_chapter - 1, true)
		)
	if btn_ch1:
		btn_ch1.pressed.connect(func(): switch_to_chapter(1, true))
	if btn_ch2:
		btn_ch2.pressed.connect(func(): switch_to_chapter(2, true))
	if btn_ch3:
		btn_ch3.pressed.connect(func(): switch_to_chapter(3, true))

var toast_panel: PanelContainer = null
var toast_title_lbl: Label = null
var toast_msg_lbl: Label = null
var toast_tween: Tween = null

func _setup_toast_ui() -> void:
	if toast_panel:
		return
	toast_panel = PanelContainer.new()
	toast_panel.name = "FloatingToast"
	toast_panel.custom_minimum_size = Vector2(380, 56)
	toast_panel.size = Vector2(380, 56)
	toast_panel.position = Vector2((get_viewport_rect().size.x - 380.0) * 0.5, 75.0)
	toast_panel.z_index = 100
	toast_panel.visible = false
	toast_panel.modulate.a = 0.0
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.96)
	style.border_color = Color("#f59e0b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 14
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	toast_panel.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	toast_panel.add_child(hbox)
	
	var lock_icon := IconFactory.create_texture_rect("lock", Vector2(20, 20), 0.9)
	hbox.add_child(lock_icon)
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	
	toast_title_lbl = Label.new()
	toast_title_lbl.add_theme_font_size_override("font_size", 13)
	toast_title_lbl.add_theme_color_override("font_color", Color(0.98, 0.90, 0.55))
	vbox.add_child(toast_title_lbl)
	
	toast_msg_lbl = Label.new()
	toast_msg_lbl.add_theme_font_size_override("font_size", 11)
	toast_msg_lbl.add_theme_color_override("font_color", Color(0.80, 0.86, 0.96))
	vbox.add_child(toast_msg_lbl)
	
	add_child(toast_panel)

func _show_notice(title_text: String, message_text: String) -> void:
	if not toast_panel:
		_setup_toast_ui()
		
	if toast_title_lbl:
		toast_title_lbl.text = title_text
	if toast_msg_lbl:
		toast_msg_lbl.text = message_text
		
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
		
	toast_panel.visible = true
	toast_panel.position.y = 55.0
	toast_panel.modulate.a = 0.0
	
	toast_tween = create_tween()
	toast_tween.set_parallel(true)
	toast_tween.tween_property(toast_panel, "position:y", 75.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.25)
	
	toast_tween.chain().tween_interval(2.5)
	
	var fade_out = toast_tween.chain().set_parallel(true)
	fade_out.tween_property(toast_panel, "position:y", 60.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fade_out.tween_property(toast_panel, "modulate:a", 0.0, 0.25)
	toast_tween.chain().tween_callback(func(): toast_panel.visible = false)

func _on_side_nav_right_pressed() -> void:
	if current_chapter < 5:
		switch_to_chapter(current_chapter + 1, true)

func _input(event: InputEvent) -> void:
	if is_animating:
		return
		
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				is_dragging = true
				has_dragged = false
				drag_start_x = mb.position.x
				slider_start_x = chapter_slider.position.x
				drag_accum_dist = 0.0
			else:
				if is_dragging:
					is_dragging = false
					if has_dragged:
						_finish_drag()
						get_viewport().set_input_as_handled()
						
	elif event is InputEventMouseMotion and is_dragging:
		var mm := event as InputEventMouseMotion
		var dx: float = mm.position.x - drag_start_x
		drag_accum_dist += absf(mm.relative.x)
		if drag_accum_dist > 8.0:
			has_dragged = true
			
		if has_dragged:
			var step_w := _get_step_width()
			var target_x: float = slider_start_x + dx
			target_x = clampf(target_x, -step_w * 4.0 - 50.0, 50.0)
			chapter_slider.position.x = target_x
			_update_realtime_drag_feedback(target_x)
			get_viewport().set_input_as_handled()
			
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			is_dragging = true
			has_dragged = false
			drag_start_x = st.position.x
			slider_start_x = chapter_slider.position.x
			drag_accum_dist = 0.0
		else:
			if is_dragging:
				is_dragging = false
				if has_dragged:
					_finish_drag()
					get_viewport().set_input_as_handled()
					
	elif event is InputEventScreenDrag and is_dragging:
		var sd := event as InputEventScreenDrag
		var dx: float = sd.position.x - drag_start_x
		drag_accum_dist += absf(sd.relative.x)
		if drag_accum_dist > 8.0:
			has_dragged = true
			
		if has_dragged:
			var step_w := _get_step_width()
			var target_x: float = slider_start_x + dx
			target_x = clampf(target_x, -step_w * 4.0 - 50.0, 50.0)
			chapter_slider.position.x = target_x
			_update_realtime_drag_feedback(target_x)
			get_viewport().set_input_as_handled()

func _update_realtime_drag_feedback(slider_x: float) -> void:
	var step_w := _get_step_width()
	var target_ch: int = 1
	if slider_x <= -step_w * 3.5:
		target_ch = 5
	elif slider_x <= -step_w * 2.5:
		target_ch = 4
	elif slider_x <= -step_w * 1.5:
		target_ch = 3
	elif slider_x <= -step_w * 0.5:
		target_ch = 2
	else:
		target_ch = 1
	if btn_ch1 and btn_ch2:
		_set_btn_active(btn_ch1, target_ch == 1)
		_set_btn_active(btn_ch2, target_ch == 2)
		if btn_ch3: _set_btn_active(btn_ch3, target_ch == 3)
	if title_label:
		var title_key := "chapter_%d_title" % target_ch
		var title_str := LocaleManager.t(title_key)
		title_label.text = "< ◇ ── " + title_str.to_upper() + " ── ◇ >"

	if lock_card_ch2:
		lock_card_ch2.visible = (!SaveManager.is_chapter_unlocked(2) and slider_x <= -step_w * 0.75 and slider_x >= -step_w * 1.25)
	if lock_card_ch3:
		lock_card_ch3.visible = (!SaveManager.is_chapter_unlocked(3) and slider_x <= -step_w * 1.75)
	if pass1 and pass1.has_method("set_card_active"):
		pass1.set_card_active(slider_x < -150.0 and slider_x > -step_w + 150.0)
	if pass2 and pass2.has_method("set_card_active"):
		pass2.set_card_active(slider_x < -step_w - 150.0 and slider_x > -step_w * 2.0 + 150.0)

func _finish_drag() -> void:
	var step_w := _get_step_width()
	var slider_x := chapter_slider.position.x
	if slider_x <= -step_w * 3.5:
		switch_to_chapter(5, true)
	elif slider_x <= -step_w * 2.5:
		switch_to_chapter(4, true)
	elif slider_x <= -step_w * 1.5:
		switch_to_chapter(3, true)
	elif slider_x <= -step_w * 0.5:
		switch_to_chapter(2, true)
	else:
		switch_to_chapter(1, true)

func switch_to_chapter(target_chapter: int, animated: bool = true) -> void:
	current_chapter = target_chapter
	var step_w := _get_step_width()
	var target_x: float = -step_w * (current_chapter - 1)
	
	if pass1 and pass1.has_method("set_card_active"):
		pass1.set_card_active(false)
	if pass2 and pass2.has_method("set_card_active"):
		pass2.set_card_active(false)
	
	_update_top_bar_data()
	_update_nav_buttons()
	_update_chapter_locks()
	
	if not animated:
		chapter_slider.position.x = target_x
		return
		
	# Silliq kinematik animatsiya: 60fps cubic tween
	is_animating = true
	SoundManager.play("click")
	
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(chapter_slider, "position:x", target_x, 0.38)
	tw.finished.connect(func():
		is_animating = false
	)

func _update_top_bar_data() -> void:
	if title_label:
		var title_key := "chapter_%d_title" % current_chapter
		var title_str := LocaleManager.t(title_key)
		title_label.text = "< ◇ ── " + title_str.to_upper() + " ── ◇ >"
		
	if total_stars_chip:
		if current_chapter <= 3:
			var ch_stars := SaveManager.get_chapter_stars(current_chapter)
			total_stars_chip.text = "     %d / 60" % ch_stars
		else:
			total_stars_chip.text = "     " + LocaleManager.t("coming_soon_caps")

func _update_nav_buttons() -> void:
	if side_nav_right:
		side_nav_right.visible = (current_chapter < 5)
		if current_chapter < 5:
			var next_txt := LocaleManager.t("chapter_nav_btn", [current_chapter + 1])
			side_nav_right.text = next_txt + " ▶"
	if side_nav_left:
		side_nav_left.visible = (current_chapter > 1)
		if current_chapter > 1:
			var prev_txt := LocaleManager.t("chapter_nav_btn", [current_chapter - 1])
			side_nav_left.text = "◀ " + prev_txt

	if btn_ch1:
		btn_ch1.text = LocaleManager.t("btn_chapter_1")
		_set_btn_active(btn_ch1, current_chapter == 1)
	if btn_ch2:
		btn_ch2.text = LocaleManager.t("btn_chapter_2")
		_set_btn_active(btn_ch2, current_chapter == 2)
	if btn_ch3:
		btn_ch3.text = LocaleManager.t("btn_chapter_3")
		_set_btn_active(btn_ch3, current_chapter == 3)

func _set_btn_active(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_stylebox_override("normal", style_white)
		btn.add_theme_stylebox_override("hover", style_white_hov)
		btn.add_theme_stylebox_override("pressed", style_white_press)
		btn.add_theme_stylebox_override("focus", empty_focus)
		var dark_c := Color(0.08, 0.08, 0.12)
		btn.add_theme_color_override("font_color", dark_c)
		btn.add_theme_color_override("font_hover_color", dark_c)
		btn.add_theme_color_override("font_pressed_color", dark_c)
		btn.add_theme_color_override("font_focus_color", dark_c)
	else:
		btn.add_theme_stylebox_override("normal", style_glass)
		btn.add_theme_stylebox_override("hover", style_glass_hov)
		btn.add_theme_stylebox_override("pressed", style_glass_press)
		btn.add_theme_stylebox_override("focus", empty_focus)
		btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(0.85, 0.88, 0.94))

func _on_language_changed(_lang: String) -> void:
	_update_top_bar_data()
	_update_nav_buttons()
	_update_chapter_locks()
	_refresh_coming_soon_cards()
	_create_nodes_for_chapter(1)
	_create_nodes_for_chapter(2)
	_create_nodes_for_chapter(3)

func _create_nodes_for_chapter(chapter: int) -> void:
	var container: Control = null
	if chapter == 1:
		container = node_layer1
	elif chapter == 2:
		container = node_layer2
	elif chapter == 3:
		container = node_layer3
		
	if not container:
		return
		
	for child in container.get_children():
		child.queue_free()

	var positions := CHAPTER_1_POS
	if chapter == 2:
		positions = CHAPTER_2_POS
	elif chapter == 3:
		positions = CHAPTER_3_POS

	var start_lvl := 1
	if chapter == 2:
		start_lvl = 21
	elif chapter == 3:
		start_lvl = 41

	var max_unlocked: int = 1
	var completed := SaveManager.get_highest_completed_level()
	if completed > 0:
		max_unlocked = mini(60, completed + 1)
	else:
		max_unlocked = 1

	for i in range(20):
		var lvl := start_lvl + i
		var pos: Vector2 = positions[i]
		var unlocked := SaveManager.is_level_unlocked(lvl)
		var stars: int = SaveManager.level_stars.get(str(lvl), 0)
		var is_active_target := (lvl == max_unlocked)
		
		var map_tf := _get_map_transform()
		var map_scale: float = map_tf["scale"]
		var offset: Vector2 = map_tf["offset"]
		
		# Dumaloq tugma (36x36 diametrli doira, radius 18)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.size = Vector2(36, 36)
		btn.position = pos * map_scale + offset - Vector2(18.0 * map_scale, 18.0 * map_scale)
		btn.scale = Vector2(map_scale, map_scale)
		btn.focus_mode = Control.FOCUS_NONE
		
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(18)
		
		if unlocked:
			if is_active_target:
				style.bg_color = Color(0.10, 0.22, 0.38, 0.96)
				style.border_color = Color("#38bdf8")
				style.set_border_width_all(2)
				style.shadow_color = Color(0.22, 0.74, 0.97, 0.50)
				style.shadow_size = 8
			else:
				style.bg_color = Color(0.06, 0.10, 0.18, 0.92)
				style.border_color = Color(0.35, 0.45, 0.62, 0.85)
				style.set_border_width_all(1.5)
				style.shadow_color = Color(0, 0, 0, 0.50)
				style.shadow_size = 4
				
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_stylebox_override("pressed", style)
			
			btn.text = str(lvl)
			btn.add_theme_font_size_override("font_size", 15)
			btn.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
			
			# Dumaloq doira TEPASIDA kattaroq 3 ta yulduzcha
			var star_box := HBoxContainer.new()
			star_box.alignment = BoxContainer.ALIGNMENT_CENTER
			star_box.custom_minimum_size = Vector2(36, 12)
			star_box.size = Vector2(36, 12)
			star_box.position = Vector2(0, -14) # Doira tepasida
			star_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			star_box.add_theme_constant_override("separation", 2)
			
			for s in range(3):
				var star_key := "star_gold" if s < stars else "star_dim"
				var star_icon := IconFactory.create_texture_rect(star_key, Vector2(10, 10), 0.52)
				star_box.add_child(star_icon)
			btn.add_child(star_box)
			
			btn.pressed.connect(func(): _on_level_btn_pressed(lvl))
		else:
			# Qulflangan daraja uchun qoida: Undan oldingi daraja ochilgan bo'lishi SHART!
			var is_prev_unlocked: bool = true
			if lvl > 1:
				is_prev_unlocked = SaveManager.is_level_unlocked(lvl - 1)

			# Qoida: Darajani reklama orqali ochish faqat har 3 darajada bir marta ishlaydi
			var can_ad_unlock := SaveManager.is_level_ad_unlockable(lvl) and is_prev_unlocked and (lvl % 3 == 0)

			if can_ad_unlock:
				style.bg_color = Color(0.12, 0.10, 0.16, 0.90)
				style.border_color = Color("#eab308")
				style.set_border_width_all(1.5)
				style.shadow_color = Color(0.92, 0.70, 0.03, 0.25)
				style.shadow_size = 5
				
				btn.add_theme_stylebox_override("normal", style)
				btn.add_theme_stylebox_override("hover", style)
				btn.add_theme_stylebox_override("pressed", style)
				
				btn.text = str(lvl)
				btn.add_theme_font_size_override("font_size", 14)
				btn.add_theme_color_override("font_color", Color(0.98, 0.85, 0.40))
				
				var ad_badge := IconFactory.create_texture_rect("video_ad", Vector2(14, 14), 0.60)
				ad_badge.position = Vector2(20, -5)
				ad_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(ad_badge)
				
				btn.pressed.connect(func():
					SoundManager.play("click")
					var adm = get_node_or_null("/root/AdManager")
					if adm and adm.has_method("show_rewarded_ad"):
						adm.show_rewarded_ad(func():
							SaveManager.unlock_level_via_ad(lvl)
							_create_nodes_for_chapter(current_chapter)
						)
					else:
						SaveManager.unlock_level_via_ad(lvl)
						_create_nodes_for_chapter(current_chapter)
				)
			else:
				style.bg_color = Color(0.04, 0.05, 0.08, 0.82)
				style.border_color = Color(0.20, 0.25, 0.35, 0.50)
				style.set_border_width_all(1)
				
				btn.add_theme_stylebox_override("normal", style)
				btn.add_theme_stylebox_override("hover", style)
				btn.add_theme_stylebox_override("pressed", style)
				
				btn.text = str(lvl)
				btn.add_theme_font_size_override("font_size", 14)
				btn.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60))
				
				var lock_badge := IconFactory.create_texture_rect("lock", Vector2(13, 13), 0.55)
				lock_badge.position = Vector2(21, -5)
				lock_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(lock_badge)
				
				btn.pressed.connect(func():
					SoundManager.play("click")
					var info: Dictionary = SaveManager.get_lock_reason_dialog(lvl)
					var t: String = info.get("title", LocaleManager.t("lvl_locked"))
					var m: String = info.get("text", LocaleManager.t("lock_must_open_earlier"))
					_show_notice(t, m)
				)
				
		container.add_child(btn)

func _on_level_btn_pressed(lvl: int) -> void:
	SoundManager.play("click")
	SaveManager.should_restore_result_modal = false
	SaveManager.navigation_source = "home_menu"
	
	var level_scene_path := "res://scenes/levels/level_%02d.tscn" % lvl
	if lvl > 60 and not ResourceLoader.exists(level_scene_path):
		_show_notice(
			LocaleManager.t("level_header", [lvl]),
			LocaleManager.t("more_levels_soon")
		)
		return
		
	var already_beaten := SaveManager.is_level_completed(lvl)
	if already_beaten and not SaveManager.debug_unlock_all:
		var adm = get_node_or_null("/root/AdManager")
		if adm and adm.has_method("show_interstitial_ad"):
			adm.show_interstitial_ad(func():
				GameManager.start_game(lvl)
			)
		else:
			GameManager.start_game(lvl)
	else:
		GameManager.start_game(lvl)

# -------------------------------------------------------------
# Boblar Bulutlari (Ochilmaganda ko'rinadi, ochilganda yo'qoladi)
# -------------------------------------------------------------
# Boblar Qulflari va Holatlari (Clean Chapter Locks & Badges)
# -------------------------------------------------------------
var lock_card_ch2: Control = null
var lock_card_ch3: Control = null

func _update_chapter_locks() -> void:
	var ch2_unlocked: bool = SaveManager.is_chapter_unlocked(2)
	var ch3_unlocked: bool = SaveManager.is_chapter_unlocked(3)
	
	if backdrop_ch2:
		backdrop_ch2.modulate = Color(1.0, 1.0, 1.0, 1.0) if ch2_unlocked else Color(0.55, 0.58, 0.68, 1.0)
	if backdrop_ch3:
		backdrop_ch3.modulate = Color(1.0, 1.0, 1.0, 1.0) if ch3_unlocked else Color(0.55, 0.58, 0.68, 1.0)
		
	if pass1 and pass1.has_method("update_state"):
		pass1.update_state()
	if pass2 and pass2.has_method("update_state"):
		pass2.update_state()
		
	if not ch2_unlocked:
		if not lock_card_ch2 and ch2_view:
			lock_card_ch2 = _create_chapter_lock_card(2)
			ch2_view.add_child(lock_card_ch2)
		if lock_card_ch2:
			lock_card_ch2.visible = (current_chapter == 2)
			_refresh_lock_card_texts(lock_card_ch2, 2)
	else:
		if lock_card_ch2:
			lock_card_ch2.visible = false
			
	if not ch3_unlocked:
		if not lock_card_ch3 and ch3_view:
			lock_card_ch3 = _create_chapter_lock_card(3)
			ch3_view.add_child(lock_card_ch3)
		if lock_card_ch3:
			lock_card_ch3.visible = (current_chapter == 3)
			_refresh_lock_card_texts(lock_card_ch3, 3)
	else:
		if lock_card_ch3:
			lock_card_ch3.visible = false

func _create_chapter_lock_card(chapter: int) -> Control:
	var card_w: float = 340.0
	var card_h: float = 56.0
	
	var card := PanelContainer.new()
	card.name = "ChapterLockCard%d" % chapter
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size = Vector2(card_w, card_h)
	# Yo'l va daraja doirachalariga xalaqit bermasligi uchun tepada (top-bar ostida)
	card.position = Vector2((get_viewport_rect().size.x - card_w) * 0.5, 68.0)
	card.z_as_relative = false
	card.z_index = 100
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.13, 0.94)
	style.border_color = Color(0.35, 0.45, 0.65, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 12
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)
	
	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hbox)
	
	var lock_icon := IconFactory.create_texture_rect("lock", Vector2(18, 18), 0.85)
	lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lock_icon)
	
	var lbl_title := Label.new()
	lbl_title.name = "Title"
	lbl_title.add_theme_font_size_override("font_size", 15)
	lbl_title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl_title)
	
	var lbl_sub := Label.new()
	lbl_sub.name = "Sub"
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 12)
	lbl_sub.add_theme_color_override("font_color", Color(0.68, 0.75, 0.88))
	lbl_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl_sub)
	
	_refresh_lock_card_texts(card, chapter)
	return card

func _refresh_lock_card_texts(card: Control, chapter: int) -> void:
	if not card: return
	var lbl_title: Label = card.get_node_or_null("VBox/HBox/Title")
	var lbl_sub: Label = card.get_node_or_null("VBox/Sub")
	var t_key := "chapter_2_locked" if chapter == 2 else "chapter_3_locked"
	var r_key := "chapter_2_unlock_req" if chapter == 2 else "chapter_3_unlock_req"
	if lbl_title:
		lbl_title.text = LocaleManager.t(t_key)
	if lbl_sub:
		lbl_sub.text = LocaleManager.t(r_key)

func _on_back_pressed() -> void:
	SoundManager.play("click")
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
