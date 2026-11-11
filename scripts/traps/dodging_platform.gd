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
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var base_col := Color("#0d131f") if is_winter else Color("#1c1a22")
	var rect := Rect2(0, 0, platform_size.x, platform_size.y)
	draw_rect(rect, base_col, true)
