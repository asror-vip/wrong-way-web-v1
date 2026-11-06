extends StaticBody2D
class_name CrumblingPlatform

# Wrong Way - Unexpected Event: Crumbling Platform / Collapsing Floor
# Looks identical to a solid platform, but when stepped on:
# Trembles and cracks for 0.25s, then collapses into the abyss!

@export var platform_size: Vector2 = Vector2(140, 28)
@export var collapse_delay: float = 0.28 # Kutilmagan qulash kechikishi
@export var fall_speed: float = 900.0

var is_triggered: bool = false
var is_falling: bool = false
var original_pos: Vector2
var fall_velocity: float = 0.0
var crack_progress: float = 0.0
var shake_tw: Tween
var crack_tw: Tween

@onready var col_shape: CollisionShape2D = $CollisionShape2D
@onready var step_area: Area2D = $StepArea

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	collapse_delay = minf(collapse_delay, 0.18)
	_update_shapes()
	
	if step_area:
		step_area.body_entered.connect(_on_step_entered)

func _update_shapes() -> void:
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = platform_size
		col_shape.shape = rect
		col_shape.position = platform_size / 2.0
		
	if step_area:
		var s_shape = step_area.get_node_or_null("CollisionShape2D")
		if s_shape:
			var s_rect := RectangleShape2D.new()
			# Tepasiga tushganda sezish
			s_rect.size = Vector2(platform_size.x - 4.0, 10.0)
			s_shape.shape = s_rect
			s_shape.position = Vector2(platform_size.x / 2.0, -4.0)

func _physics_process(delta: float) -> void:
	if not is_triggered:
		if step_area:
			for b in step_area.get_overlapping_bodies():
				_on_step_entered(b)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null and is_instance_valid(p):
			if not ("is_dead" in p and p.is_dead) and not ("is_invulnerable" in p and p.is_invulnerable):
				var px: float = p.global_position.x
				var py: float = p.global_position.y
				if px >= (global_position.x - 2.0) and px <= (global_position.x + platform_size.x + 2.0):
					if py >= (global_position.y - 20.0) and py <= (global_position.y + 8.0):
						_on_step_entered(p)

	if is_falling:
		fall_velocity += 1600.0 * delta
		position.y += fall_velocity * delta
		queue_redraw()
		if position.y > original_pos.y + 600.0:
			set_physics_process(false)
			if col_shape:
				col_shape.set_deferred("disabled", true)

func _on_step_entered(body: Node2D) -> void:
	if is_triggered:
		return
	if body is PlayerController or body.is_in_group("player"):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		trigger_crumble()

func trigger_crumble() -> void:
	is_triggered = true
	SoundManager.play("trap")
	GameManager.request_screen_shake.emit(4.0)
	
	# Platforma qaltiraydi va yoriladi
	if shake_tw and shake_tw.is_valid(): shake_tw.kill()
	shake_tw = create_tween().set_loops()
	for i in range(4):
		shake_tw.tween_property(self, "position:x", original_pos.x + 3.0, collapse_delay / 8.0)
		shake_tw.tween_property(self, "position:x", original_pos.x - 3.0, collapse_delay / 8.0)
		shake_tw.tween_property(self, "position:x", original_pos.x, collapse_delay / 8.0)
	
	# Yoriqlar chuqurlashadi
	if crack_tw and crack_tw.is_valid(): crack_tw.kill()
	crack_tw = create_tween()
	crack_tw.tween_property(self, "crack_progress", 1.0, collapse_delay)
	
	crack_tw.finished.connect(func():
		if is_instance_valid(self) and is_triggered:
			is_falling = true
			if shake_tw and shake_tw.is_valid(): shake_tw.kill()
			position = original_pos
			GameManager.request_screen_shake.emit(6.0)
	)

func reset_trap() -> void:
	if shake_tw and shake_tw.is_valid(): shake_tw.kill()
	if crack_tw and crack_tw.is_valid(): crack_tw.kill()
	is_triggered = false
	is_falling = false
	fall_velocity = 0.0
	crack_progress = 0.0
	position = original_pos
	set_physics_process(true)
	if col_shape:
		col_shape.set_deferred("disabled", false)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(0, 0, platform_size.x, platform_size.y)
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var base_col := Color("#0d131f") if is_winter else Color("#1c1a22")
	draw_rect(rect, base_col, true)

	if is_winter:
		var snow_h := 5.5
		if platform_size.x > 36.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, snow_h)), Color("#f1f5f9"), true)
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 2.0)), Color("#ffffff"), true)
			draw_rect(Rect2(Vector2(0, snow_h - 1.5), Vector2(platform_size.x, 1.5)), Color("#94a3b8"), true)
			var icicle_step := 32.0
			var num_icicles := int((platform_size.x - 20.0) / icicle_step)
			for i in range(num_icicles):
				var ix := 14.0 + float(i) * icicle_step
				var ilen := 4.0 if (i % 2 == 0) else 6.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(ix - 2.0, snow_h),
					Vector2(ix + 2.0, snow_h),
					Vector2(ix, snow_h + ilen)
				]), Color("#bae6fd"))
		else:
			draw_rect(Rect2(Vector2.ZERO, Vector2(2.5, platform_size.y)), Color(0.49, 0.86, 0.99, 0.6), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 3.0)), Color("#342f3a"), true)
	
	# Kutilmagan yoriqlar (bosilganda tez tarqaladi)
	if crack_progress > 0.05:
		var cx := platform_size.x * 0.5
		var alpha := clampf(crack_progress, 0.0, 1.0)
		var crack_col := Color(0.85, 0.92, 1.0, alpha * 0.9)
		
		# Asosiy yoriq
		draw_line(Vector2(cx, 0), Vector2(cx - 10 * crack_progress, platform_size.y * 0.5), crack_col, 1.8)
		draw_line(Vector2(cx - 10 * crack_progress, platform_size.y * 0.5), Vector2(cx + 8 * crack_progress, platform_size.y), crack_col, 1.6)
		# Qo'shimcha yoriqlar
		draw_line(Vector2(cx - 10 * crack_progress, platform_size.y * 0.5), Vector2(cx - 24 * crack_progress, platform_size.y * 0.8), crack_col, 1.2)
		draw_line(Vector2(cx + 4, platform_size.y * 0.3), Vector2(cx + 20 * crack_progress, platform_size.y * 0.6), crack_col, 1.2)

