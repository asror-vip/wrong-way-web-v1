extends StaticBody2D
class_name InvisibleBlock

@export var block_size: Vector2 = Vector2(32, 32)
@export var persist_revealed: bool = true

var is_revealed: bool = false
var tw: Tween
var original_pos: Vector2

@onready var col_shape: CollisionShape2D = $CollisionShape2D
@onready var trigger_area: Area2D = $TriggerArea

func _ready() -> void:
	add_to_group("traps")
	original_pos = position
	
	if col_shape:
		var rect := RectangleShape2D.new()
		rect.size = block_size
		col_shape.shape = rect
		col_shape.position = block_size / 2.0
		
	if trigger_area:
		var trig_shape = trigger_area.get_node_or_null("CollisionShape2D")
		if trig_shape:
			var t_rect := RectangleShape2D.new()
			# O'yinchi tagidan yoki yonidan sakraganda sezish uchun biroz kengaytirilgan
			t_rect.size = Vector2(block_size.x + 4.0, block_size.y + 12.0)
			trig_shape.shape = t_rect
			trig_shape.position = Vector2(block_size.x / 2.0, block_size.y / 2.0 + 4.0)
		trigger_area.body_entered.connect(_on_trigger_entered)

func _on_trigger_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if not is_revealed:
			reveal(body)

func reveal(player: Node2D = null) -> void:
	is_revealed = true
	SoundManager.play("trap")
	
	if player and "velocity" in player:
		# Qahramon yuqoriga sakrayotgan bo'lsa darhol pastga urib tushirish
		if player.velocity.y < 0:
			player.velocity.y = 140.0
			
	# Blok tepaga 6px sakrab joyiga qaytish animatsiyasi
	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween()
	tw.tween_property(self, "position:y", original_pos.y - 8.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", original_pos.y, 0.08).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	queue_redraw()

func reset_trap() -> void:
	if tw and tw.is_valid():
		tw.kill()
	is_revealed = false
	position = original_pos
	queue_redraw()

func _draw() -> void:
	if not is_revealed:
		return
		
	var rect := Rect2(0, 0, block_size.x, block_size.y)
	# To'q obsidian tosh tana
	draw_rect(rect, Color(0.06, 0.08, 0.12, 0.95), true)
	# Nozik tosh hoshiyasi
	draw_rect(rect, Color(0.25, 0.32, 0.45, 0.8), false, 1.2)
	
	# Tosh yoriqlari (Cracked stone texture)
	var cx := block_size.x * 0.5
	var cy := block_size.y * 0.5
	draw_line(Vector2(cx - 6, cy - 8), Vector2(cx + 2, cy), Color(0.18, 0.22, 0.32), 1.0)
	draw_line(Vector2(cx + 2, cy), Vector2(cx - 3, cy + 8), Color(0.18, 0.22, 0.32), 1.0)

