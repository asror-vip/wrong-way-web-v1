extends AnimatableBody2D
class_name DodgingPlatform

# Level Devil Trap: Dodging Platform (Qochuvchi Platforma)
# Looks like a safe stepping stone over a deadly gap.
# As soon as the player jumps towards it, it slides away rapidly!

@export var platform_size: Vector2 = Vector2(90, 36)
@export var dodge_offset: Vector2 = Vector2(130.0, 0.0) # O'ngga yoki pastga qochish
@export var trigger_distance: float = 85.0
@export var dodge_duration: float = 0.22

var original_pos: Vector2
var is_triggered: bool = false
var tween: Tween

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = platform_size
		col_shape.shape = rect
		col_shape.position = platform_size / 2.0

func _physics_process(_delta: float) -> void:
	if not is_triggered:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and is_instance_valid(player):
			if "is_dead" in player and player.is_dead:
				return
			if "is_invulnerable" in player and player.is_invulnerable:
				return
			var center: Vector2 = global_position + platform_size / 2.0
			var dist: float = player.global_position.distance_to(center)
			if dist < trigger_distance:
				trigger_dodge()

func trigger_dodge() -> void:
	if is_triggered:
		return
	is_triggered = true
	SoundManager.play("trap")
	GameManager.request_screen_shake.emit(4.0)
	
	tween = create_tween()
	var target := original_pos + dodge_offset
	tween.tween_property(self, "position", target, dodge_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func reset_trap() -> void:
	if tween and tween.is_valid():
		tween.kill()
	is_triggered = false
	position = original_pos
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(0, 0, platform_size.x, platform_size.y)
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var base_col := Color("#1c1a22")
	if ch == 2: base_col = Color("#0d131f")
	elif ch == 3: base_col = Color("#062319")
	elif ch == 4: base_col = Color("#291c14")
	elif ch == 5: base_col = Color("#1a0505")

	draw_rect(rect, base_col, true)

	# Boblarga mos pol qoplamalari (Top layers)
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
