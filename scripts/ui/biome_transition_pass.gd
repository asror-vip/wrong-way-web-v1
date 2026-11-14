extends Control
class_name BiomeTransitionPass

# Wrong Way - Biome Transition Mist Pass
# Atmospheric boundary between distinct chapters (Forest -> Winter Snow -> Green Forest)
# Focused on a slender, ethereal mist curtain with atmospheric motes and a lock gate badge.
# No artificial drawn roads or bridges.

@export var pass_index: int = 1 # 1: Forest -> Snow, 2: Snow -> Green Forest

var mist_back: ColorRect
var mist_front: ColorRect
var particles: CPUParticles2D
var lock_card: PanelContainer

var is_unlocked: bool = false
var is_card_active: bool = false

const PASS_WIDTH: float = 80.0
const PASS_HEIGHT: float = 540.0

func _ready() -> void:
	custom_minimum_size = Vector2(PASS_WIDTH, PASS_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_setup_mist_layers()
	_setup_particles()
	_setup_lock_card()
	update_state()

func _setup_mist_layers() -> void:
	var shader = preload("res://shaders/fog_transition.gdshader")
	
	# Layer 1: Background mist veil
	mist_back = ColorRect.new()
	mist_back.name = "MistBack"
	mist_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist_back.position = Vector2(-35.0, 0.0)
	mist_back.size = Vector2(PASS_WIDTH + 70.0, PASS_HEIGHT)
	
	var mat_back = ShaderMaterial.new()
	mat_back.shader = shader
	_apply_mist_colors(mat_back, 1.10, 0.045, 0.70)
	mist_back.material = mat_back
	add_child(mist_back)
	
	# Layer 2: Foreground soft drifting wisps
	mist_front = ColorRect.new()
	mist_front.name = "MistFront"
	mist_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist_front.position = Vector2(-25.0, 0.0)
	mist_front.size = Vector2(PASS_WIDTH + 50.0, PASS_HEIGHT)
	
	var mat_front = ShaderMaterial.new()
	mat_front.shader = shader
	_apply_mist_colors(mat_front, 0.70, 0.070, 0.80)
	mist_front.material = mat_front
	add_child(mist_front)

func _apply_mist_colors(mat: ShaderMaterial, density_val: float, speed_val: float, edge_exp: float) -> void:
	mat.set_shader_parameter("density", density_val)
	mat.set_shader_parameter("speed", speed_val)
	mat.set_shader_parameter("edge_fade_exp", edge_exp)
	if pass_index == 1:
		mat.set_shader_parameter("fog_color_left", Color(0.68, 0.76, 0.88, 0.75))
		mat.set_shader_parameter("fog_color_right", Color(0.88, 0.94, 1.00, 0.85))
		mat.set_shader_parameter("glow_color", Color(0.55, 0.82, 1.00, 0.45))
	else:
		mat.set_shader_parameter("fog_color_left", Color(0.85, 0.92, 1.00, 0.75))
		mat.set_shader_parameter("fog_color_right", Color(0.62, 0.88, 0.70, 0.80))
		mat.set_shader_parameter("glow_color", Color(0.48, 0.95, 0.65, 0.40))

func _setup_particles() -> void:
	particles = CPUParticles2D.new()
	particles.name = "AtmosphericMotes"
	particles.position = Vector2(PASS_WIDTH * 0.5, 0)
	particles.amount = 22
	particles.lifetime = 4.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(PASS_WIDTH * 0.45, 8.0)
	
	if pass_index == 1:
		# Snowflakes drifting gently from cold snow peaks into forest
		particles.direction = Vector2(-0.40, 1.0)
		particles.spread = 22.0
		particles.gravity = Vector2(0, 14)
		particles.initial_velocity_min = 22.0
		particles.initial_velocity_max = 42.0
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 3.5
		particles.color = Color(0.92, 0.96, 1.0, 0.78)
	else:
		# Floating emerald spores & summer embers rising
		particles.position = Vector2(PASS_WIDTH * 0.5, PASS_HEIGHT)
		particles.direction = Vector2(-0.20, -1.0)
		particles.spread = 28.0
		particles.gravity = Vector2(0, -8)
		particles.initial_velocity_min = 16.0
		particles.initial_velocity_max = 34.0
		particles.scale_amount_min = 1.8
		particles.scale_amount_max = 3.0
		particles.color = Color(0.65, 1.0, 0.75, 0.70)
		
	add_child(particles)

func _setup_lock_card() -> void:
	# Foydalanuvchi talabiga ko'ra chegaradagi (border pass) qulflangan yozuvi butunlay olib tashlandi
	lock_card = null

func set_card_active(active: bool) -> void:
	is_card_active = active
	if lock_card:
		lock_card.visible = (!is_unlocked and is_card_active)

func update_state() -> void:
	if pass_index == 1:
		is_unlocked = SaveManager.is_chapter_unlocked(2)
	else:
		is_unlocked = SaveManager.is_chapter_unlocked(3)
		
	if lock_card:
		lock_card.visible = (!is_unlocked and is_card_active)
		var lbl_title: Label = lock_card.get_node_or_null("VBox/HBox/Title")
		var lbl_sub: Label = lock_card.get_node_or_null("VBox/Sub")
		if pass_index == 1:
			if lbl_title: lbl_title.text = LocaleManager.t("chapter_2_locked")
			if lbl_sub: lbl_sub.text = LocaleManager.t("chapter_2_unlock_req")
		else:
			if lbl_title: lbl_title.text = LocaleManager.t("chapter_3_locked")
			if lbl_sub: lbl_sub.text = LocaleManager.t("chapter_3_unlock_req")
