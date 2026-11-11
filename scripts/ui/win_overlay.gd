extends Control
class_name WinOverlay

@onready var crown_icon: TextureRect = $CrownIcon
@onready var spotlight_fx: Control = $SpotlightFX
@onready var line_accent: Control = $LineAccent
@onready var win_title: Label = $WinTitle
@onready var subtitle: Label = $Subtitle
@onready var star_box: HBoxContainer = $StarBox
@onready var stats_label: Label = $StatsLabel
@onready var next_btn: Button = $BtnRow/NextBtn
@onready var replay_btn: Button = $BtnRow/ReplayBtn
@onready var map_btn: Button = $MapBtn
@onready var home_btn: Button = $HomeBtn

var last_lvl: int = 1
var last_time_ms: float = 0.0
var last_deaths: int = 0
var last_stars: int = 1
var anim_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GameManager.level_completed.connect(_on_level_completed)
	GameManager.level_started.connect(func(_lvl): visible = false)
	LocaleManager.language_changed.connect(_on_language_changed)
	
	if spotlight_fx:
		spotlight_fx.draw.connect(_on_spotlight_draw)
	if line_accent:
		line_accent.draw.connect(_on_line_accent_draw)
		
	_setup_icons()
	
	if next_btn: next_btn.pressed.connect(_on_next_pressed)
	if replay_btn: replay_btn.pressed.connect(_on_replay_pressed)
	if map_btn: map_btn.pressed.connect(_on_map_pressed)
	if home_btn: home_btn.pressed.connect(_on_home_pressed)

func _process(delta: float) -> void:
	if visible and crown_icon:
		anim_time += delta * 2.0
		# Crown yumshoq yuqoriga-pastga tebranishi
		crown_icon.position.y = 85.0 + sin(anim_time) * 3.5

func _setup_icons() -> void:
	if crown_icon:
		crown_icon.texture = IconFactory.get_icon("crown", 1.8)
	if next_btn:
		next_btn.icon = IconFactory.get_icon("play_dark", 0.85)
	if replay_btn:
		replay_btn.icon = IconFactory.get_icon("restart", 0.8)
	if map_btn:
		map_btn.icon = IconFactory.get_icon("circle_btn_back", 1.0)
		map_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if home_btn:
		home_btn.icon = IconFactory.get_icon("circle_btn_home", 1.0)
		home_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		home_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

func _on_spotlight_draw() -> void:
	if not spotlight_fx: return
	var center_x := spotlight_fx.size.x * 0.5
	
	# Yumshoq spotlight nuri (tepadan pastga kengayuvchi)
	var top_w := 60.0
	var bot_w := 240.0
	var beam_h := 380.0
	
	var outer_poly := PackedVector2Array([
		Vector2(center_x - top_w, 0.0),
		Vector2(center_x + top_w, 0.0),
		Vector2(center_x + bot_w, beam_h),
		Vector2(center_x - bot_w, beam_h)
	])
	spotlight_fx.draw_colored_polygon(outer_poly, Color(0.9, 0.95, 1.0, 0.04))
	
	var inner_poly := PackedVector2Array([
		Vector2(center_x - 30.0, 0.0),
		Vector2(center_x + 30.0, 0.0),
		Vector2(center_x + 140.0, beam_h - 40.0),
		Vector2(center_x - 140.0, beam_h - 40.0)
	])
	spotlight_fx.draw_colored_polygon(inner_poly, Color(0.95, 0.98, 1.0, 0.03))
	
	# Yulduzlar atrofidagi olmos uchqunlari (reference rasmdagidek)
	var diamonds := [
		Vector2(center_x - 150.0, 160.0), Vector2(center_x + 150.0, 150.0),
		Vector2(center_x - 180.0, 240.0), Vector2(center_x + 180.0, 245.0),
		Vector2(center_x - 130.0, 280.0), Vector2(center_x + 130.0, 285.0)
	]
	for pt in diamonds:
		_draw_diamond(spotlight_fx, pt, 3.5, Color(1, 1, 1, 0.35))

func _draw_diamond(canvas: Control, center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(center.x, center.y - r),
		Vector2(center.x + r, center.y),
		Vector2(center.x, center.y + r),
		Vector2(center.x - r, center.y)
	])
	canvas.draw_colored_polygon(pts, col)

func _on_line_accent_draw() -> void:
	if not line_accent: return
	var w := line_accent.size.x
	var cy := line_accent.size.y / 2.0
	var cx := w / 2.0
	
	# Markazida uzilish bo'lgan nafis chiziq
	var col_edge := Color(1, 1, 1, 0.05)
	var col_mid := Color(1, 1, 1, 0.45)
	line_accent.draw_line(Vector2(20, cy), Vector2(cx - 30, cy), col_mid, 1.0)
	line_accent.draw_line(Vector2(cx + 30, cy), Vector2(w - 20, cy), col_mid, 1.0)
	# Markaziy olmos
	_draw_diamond(line_accent, Vector2(cx, cy), 3.0, Color(1, 1, 1, 0.6))

func _on_language_changed(_lang: String) -> void:
	if visible:
		_render_win_data()

func restore_result(data: Dictionary) -> void:
	if data.is_empty():
		return
	_on_level_completed(
		data.get("lvl", GameManager.current_level_id),
		data.get("time_ms", 0.0),
		data.get("deaths", 0),
		data.get("stars", 1)
	)

func _on_level_completed(lvl: int, time_ms: float, deaths: int, stars: int) -> void:
	last_lvl = lvl
	last_time_ms = time_ms
	last_deaths = deaths
	last_stars = stars

	_render_win_data()
	visible = true
	if spotlight_fx: spotlight_fx.queue_redraw()
	if line_accent: line_accent.queue_redraw()

func _render_win_data() -> void:
	if win_title:
		win_title.text = "LEVEL COMPLETE"
	
	if subtitle:
		if last_lvl == 60:
			subtitle.text = "BARCHA 60 TA DARAJA YAKUNLANDI! 🎉\n4-BOB VA 5-BOB TEZ KUNDA (COMING SOON)"
		else:
			subtitle.text = LocaleManager.t("great_job")
		
	# 3 ta katta yulduz (glowing oq yulduzlar)
	if star_box:
		for child in star_box.get_children():
			child.queue_free()
		for s in range(3):
			var is_earned := (s < last_stars)
			var icon_key := "star_white" if is_earned else "star_dim"
			var star_icon := IconFactory.create_texture_rect(icon_key, Vector2(44, 44), 1.7)
			star_box.add_child(star_icon)
			
	if stats_label:
		var time_sec: int = maxi(1, int(round(last_time_ms / 1000.0)))
		stats_label.text = "Vaqt: %ds   •   O'limlar: %d" % [time_sec, last_deaths]
		
	if next_btn:
		next_btn.text = "  " + LocaleManager.t("btn_next_lvl")
		# 2+ yulduz olingan bo'lsa va 60-darajadan kichik bo'lsa keyingi daraja faol
		next_btn.visible = (last_stars >= 2 and last_lvl < 60)
		
	if replay_btn:
		replay_btn.text = "  " + LocaleManager.t("btn_restart")

func _on_next_pressed() -> void:
	SoundManager.play("click")
	visible = false
	GameManager.start_game(last_lvl + 1)

func _on_replay_pressed() -> void:
	SoundManager.play("click")
	visible = false
	GameManager.start_game(last_lvl)

func _on_map_pressed() -> void:
	SoundManager.play("click")
	visible = false
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		sm.navigation_source = "result_modal"
		sm.return_level_num = last_lvl
		sm.should_restore_result_modal = true
		sm.pending_result_data = {
			"lvl": last_lvl,
			"time_ms": last_time_ms,
			"deaths": last_deaths,
			"stars": last_stars
		}
	GameManager.go_to_level_select()

func _on_home_pressed() -> void:
	SoundManager.play("click")
	visible = false
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		sm.navigation_source = "home_menu"
		sm.should_restore_result_modal = false
	GameManager.go_to_main_menu()
