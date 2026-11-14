extends Area2D
class_name CircularSawTrap

@export var orbit_radius: float = 64.0 # 2x katak radiusi
@export var orbit_speed: float = 2.4
@export var saw_radius: float = 16.0 # 32px diametr
@export var clockwise: bool = true
@export var start_angle_deg: float = 0.0

var current_angle: float = 0.0
var spin_angle: float = 0.0
var blade_offset: Vector2 = Vector2.ZERO

@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("traps")
	current_angle = deg_to_rad(start_angle_deg)
	_update_blade_position()
	if col_shape:
		var circle := CircleShape2D.new()
		circle.radius = saw_radius - 1.0
		col_shape.shape = circle
		col_shape.position = blade_offset
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var dir := 1.0 if clockwise else -1.0
	current_angle += orbit_speed * dir * delta
	spin_angle += 16.0 * dir * delta
	
	_update_blade_position()
	if col_shape:
		col_shape.position = blade_offset
	queue_redraw()

func _update_blade_position() -> void:
	if orbit_radius > 0.0:
		blade_offset = Vector2(cos(current_angle), sin(current_angle)) * orbit_radius
	else:
		blade_offset = Vector2.ZERO

func _draw() -> void:
	if orbit_radius > 0.0:
		# 1. Markaziy o'q (32px to'r markazi)
		draw_circle(Vector2.ZERO, 6.0, Color("#1e1b29"))
		draw_circle(Vector2.ZERO, 3.5, Color("#475569"))
		draw_circle(Vector2.ZERO, 1.5, Color("#cbd5e1"))
		
		# 2. Bog'lovchi metall zanjir
		var chain_links := maxi(2, int(orbit_radius / 16.0))
		for i in range(1, chain_links):
			var t := float(i) / float(chain_links)
			var link_pos := blade_offset * t
			draw_circle(link_pos, 3.5, Color("#334155"))
			draw_circle(link_pos, 1.5, Color("#64748b"))
		draw_line(Vector2.ZERO, blade_offset, Color("#1e293b"), 2.5)
	
	# 3. 32px diametrli arra diski
	_draw_saw_blade(blade_offset, saw_radius, spin_angle)

func _draw_saw_blade(pos: Vector2, r: float, spin: float) -> void:
	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	var teeth_count := 8
	var inner_r := r * 0.70
	var pts := PackedVector2Array()
	var step := (PI * 2.0) / float(teeth_count)
	
	for i in range(teeth_count):
		var a0 := spin + float(i) * step
		var a1 := a0 + step * 0.45
		var a2 := a0 + step * 0.80
		
		pts.append(pos + Vector2(cos(a0), sin(a0)) * inner_r)
		pts.append(pos + Vector2(cos(a1), sin(a1)) * r)
		pts.append(pos + Vector2(cos(a2), sin(a2)) * inner_r)
		
	if ch == 2:
		# Muzli arra tishlari (Winter)
		draw_colored_polygon(pts, Color(0.22, 0.74, 0.97, 0.95))
		draw_polyline(pts, Color("#ffffff"), 1.2)
		draw_circle(pos, inner_r * 0.85, Color("#0f172a"))
		draw_circle(pos, inner_r * 0.65, Color("#0284c7"))
		draw_circle(pos, 4.0, Color("#1e293b"))
		draw_circle(pos, 2.0, Color("#e0f2fe"))
	elif ch == 3:
		# Zaharli o'rmon arrasi (Neon Green, Zanglagan ichi)
		draw_colored_polygon(pts, Color("#22c55e")) # Zaharli yashil qirralar
		draw_polyline(pts, Color("#86efac"), 1.2)
		draw_circle(pos, inner_r * 0.85, Color("#1c1917"))
		draw_circle(pos, inner_r * 0.65, Color("#166534")) # To'q yashil markaz
		draw_circle(pos, 4.0, Color("#451a03")) # Zanglagan o'q
		draw_circle(pos, 2.0, Color("#fef08a"))
	elif ch == 4:
		# Sahro ibodatxonasi mis arrasi (Copper, Aztek)
		teeth_count = 6 # Sahroda tishlar qalinroq va burchakli
		pts.clear()
		step = (PI * 2.0) / float(teeth_count)
		inner_r = r * 0.75
		for i in range(teeth_count):
			var a0 := spin + float(i) * step
			var a1 := a0 + step * 0.50
			var a2 := a0 + step * 1.0
			pts.append(pos + Vector2(cos(a0), sin(a0)) * inner_r)
			pts.append(pos + Vector2(cos(a1), sin(a1)) * r)
			pts.append(pos + Vector2(cos(a2), sin(a2)) * inner_r)
		draw_colored_polygon(pts, Color("#d97706")) # To'q mis
		draw_polyline(pts, Color("#fcd34d"), 1.5) # Yaltiroq tillarang
		draw_circle(pos, inner_r * 0.80, Color("#451a03"))
		draw_circle(pos, inner_r * 0.55, Color("#b45309"))
		draw_circle(pos, 5.0, Color("#78350f"))
		draw_rect(Rect2(pos.x - 2, pos.y - 2, 4, 4), Color("#fef3c7"), true) # Kvadrat qoziq
	elif ch == 5:
		# Olovli Abiss arrasi (Obsidian va Lava markazi)
		draw_colored_polygon(pts, Color("#ef4444")) # Qizigan qirralar
		draw_polyline(pts, Color("#f97316"), 1.5) # Lovullagan olov hoshiya
		draw_circle(pos, inner_r * 0.90, Color("#1a0505")) # To'q obsidian
		draw_circle(pos, inner_r * 0.70, Color("#991b1b"))
		draw_circle(pos, inner_r * 0.45, Color("#ea580c")) # Lava markazi
		draw_circle(pos, 3.0, Color("#fef08a")) # Oq-sariq issiqlik markazi
	else:
		# Default / Limbo
		draw_colored_polygon(pts, Color("#94a3b8"))
		draw_polyline(pts, Color("#f1f5f9"), 1.0)
		draw_circle(pos, inner_r * 0.85, Color("#475569"))
		draw_circle(pos, inner_r * 0.65, Color("#dc2626"))
		draw_circle(pos, 4.0, Color("#0f172a"))
		draw_circle(pos, 2.0, Color("#e2e8f0"))

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController or body.is_in_group("player"):
		if "is_dead" in body and body.is_dead:
			return
		if "is_invulnerable" in body and body.is_invulnerable:
			return
		if body.has_method("kill"):
			body.kill()

func reset_trap() -> void:
	current_angle = deg_to_rad(start_angle_deg)
	_update_blade_position()
	if col_shape:
		col_shape.position = blade_offset
