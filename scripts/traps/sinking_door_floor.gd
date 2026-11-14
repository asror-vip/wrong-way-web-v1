extends StaticBody2D
class_name SinkingDoorFloor

# Level Devil Trap: Sinking Door Floor (Eshik oldidagi yerning cho'kib ketishi)
# The classic Level Devil troll: Right when the player is 1 step from the exit door,
# the floor drops straight into the abyss!

@export var platform_size: Vector2 = Vector2(100, 160)
@export var trigger_distance: float = 80.0
@export var fall_speed_accel: float = 3800.0

var original_pos: Vector2
var is_triggered: bool = false
var is_falling: bool = false
var fall_velocity: float = 0.0

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = platform_size
		col_shape.shape = rect
		col_shape.position = platform_size / 2.0

func _physics_process(delta: float) -> void:
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			if "is_invulnerable" in player and player.is_invulnerable:
				return
			var center_x: float = global_position.x + platform_size.x / 2.0
			var dist_x: float = abs(player.global_position.x - center_x)
			if dist_x < trigger_distance and abs(player.global_position.y - global_position.y) < 60.0:
				trigger_sink()
	elif is_falling:
		fall_velocity += fall_speed_accel * delta
		position.y += fall_velocity * delta
		if position.y > original_pos.y + 600.0:
			set_physics_process(false)
			if col_shape:
				col_shape.set_deferred("disabled", true)

func trigger_sink() -> void:
	if is_triggered:
		return
	is_triggered = true
	SoundManager.play("trap")
	GameManager.request_screen_shake.emit(6.0)
	is_falling = true

func reset_trap() -> void:
	is_triggered = false
	is_falling = false
	fall_velocity = 0.0
	position = original_pos
	set_physics_process(true)
	if col_shape:
		col_shape.set_deferred("disabled", false)
	queue_redraw()

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
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, snow_h)), Color("#f1f5f9"), true)
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 2.0)), Color("#ffffff"), true)
			draw_rect(Rect2(Vector2(0, snow_h - 1.5), Vector2(platform_size.x, 1.5)), Color("#94a3b8"), true)
		else:
			draw_rect(Rect2(Vector2.ZERO, Vector2(2.5, platform_size.y)), Color(0.49, 0.86, 0.99, 0.6), true)
	elif ch == 3:
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 4.0)), Color("#14532d"), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 2.0)), Color("#064e3b"), true)
	elif ch == 4:
		var sand_h := 6.0
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, sand_h)), Color("#fcd34d"), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 2.0)), Color("#d97706"), true)
	elif ch == 5:
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 3.0)), Color("#450a0a"), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 1.0)), Color("#f97316"), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 3.0)), Color("#342f3a"), true)
