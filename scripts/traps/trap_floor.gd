extends StaticBody2D
class_name TrapFloor

@export var platform_size: Vector2 = Vector2(140, 160)
@export var shake_duration: float = 0.18

var initial_position: Vector2
var is_triggered: bool = false
var is_falling: bool = false
var fall_speed: float = 0.0
var shake_timer: float = 0.0

@onready var visual: Node2D = $Visual
@onready var trigger_area: Area2D = $TriggerArea
@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	initial_position = global_position
	shake_duration = minf(shake_duration, 0.12)
	# Pastdagi tuzoq polini ham ekranning eng pastigacha uzaytiramiz
	if position.y >= 360.0 and (position.y + platform_size.y) < 540.0:
		platform_size.y = 540.0 - position.y
	if col_shape:
		col_shape.shape = RectangleShape2D.new()
		col_shape.shape.size = platform_size
		col_shape.position = platform_size / 2.0
	if trigger_area:
		trigger_area.body_entered.connect(_on_trigger_body_entered)
		var trig_col := trigger_area.get_node_or_null("TriggerShape") as CollisionShape2D
		if trig_col:
			var trig_rect := RectangleShape2D.new()
			# Trigger zona pol ustida turgan o'yinchini aniq sezishi uchun
			trig_rect.size = Vector2(platform_size.x + 10.0, 40.0)
			trig_col.shape = trig_rect
			trig_col.position = Vector2(platform_size.x / 2.0, -10.0)
	elif has_node("AreaTrigger"):
		$AreaTrigger.body_entered.connect(_on_trigger_body_entered)
	if visual:
		visual.queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_triggered:
		if trigger_area:
			for b in trigger_area.get_overlapping_bodies():
				_on_trigger_body_entered(b)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null and is_instance_valid(p):
			if not ("is_dead" in p and p.is_dead) and not ("is_invulnerable" in p and p.is_invulnerable):
				var px: float = p.global_position.x
				var py: float = p.global_position.y
				if px >= (global_position.x - 4.0) and px <= (global_position.x + platform_size.x + 4.0):
					if py >= (global_position.y - 32.0) and py <= (global_position.y + 12.0):
						_on_trigger_body_entered(p)

	if is_triggered and not is_falling:
		shake_timer -= delta
		if visual:
			visual.position.x = randf_range(-2.0, 2.0)
		if shake_timer <= 0.0:
			if visual:
				visual.position.x = 0.0
			is_falling = true

	if is_falling:
		fall_speed += 3200.0 * delta
		global_position.y += fall_speed * delta

func _on_trigger_body_entered(body: Node2D) -> void:
	if (body is PlayerController or body.is_in_group("player")) and not is_triggered:
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		is_triggered = true
		shake_timer = shake_duration
		var sm = get_node_or_null("/root/SoundManager")
		if sm and sm.has_method("play"):
			sm.play("trap")

func reset_trap() -> void:
	is_triggered = false
	is_falling = false
	fall_speed = 0.0
	shake_timer = 0.0
	global_position = initial_position
	if visual:
		visual.position = Vector2.ZERO

func _draw() -> void:
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var base_col := Color("#1c1a22")
	if ch == 2: base_col = Color("#0d131f")
	elif ch == 3: base_col = Color("#062319")
	elif ch == 4: base_col = Color("#291c14")
	elif ch == 5: base_col = Color("#1a0505")

	var rect := Rect2(0, 0, platform_size.x, platform_size.y)
	draw_rect(rect, base_col, true)

	if ch == 2:
		var snow_h := 5.5
		if platform_size.x > 36.0:
			draw_rect(Rect2(0.0, 0.0, platform_size.x, snow_h), Color("#f1f5f9"), true)
			draw_rect(Rect2(0.0, 0.0, platform_size.x, 2.0), Color("#ffffff"), true)
			draw_rect(Rect2(0.0, snow_h - 1.5, platform_size.x, 1.5), Color("#94a3b8"), true)
		else:
			draw_rect(Rect2(0.0, 0.0, minf(platform_size.x, 2.5), platform_size.y), Color(0.49, 0.86, 0.99, 0.6), true)
	elif ch == 3:
		draw_rect(Rect2(0.0, 0.0, platform_size.x, 4.0), Color("#14532d"), true)
		draw_rect(Rect2(0.0, 4.0, platform_size.x, 2.0), Color("#064e3b"), true)
	elif ch == 4:
		var sand_h := 6.0
		draw_rect(Rect2(0.0, 0.0, platform_size.x, sand_h), Color("#fcd34d"), true)
		draw_rect(Rect2(0.0, sand_h - 2.0, platform_size.x, 2.0), Color("#d97706"), true)
	elif ch == 5:
		draw_rect(Rect2(0.0, 0.0, platform_size.x, 3.0), Color("#450a0a"), true)
		draw_rect(Rect2(0.0, 0.0, platform_size.x, 1.0), Color("#f97316"), true)
	else:
		draw_rect(Rect2(0.0, 0.0, platform_size.x, 3.0), Color("#342f3a"), true)
