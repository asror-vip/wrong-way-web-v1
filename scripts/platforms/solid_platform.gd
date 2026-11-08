extends StaticBody2D
class_name SolidPlatform

@export var platform_size: Vector2 = Vector2(350, 160)
@export var has_ceiling_teeth: bool = false

var _crusher_ranges: Array[Vector2] = []
var _crushers: Array[Crusher] = []
var _falling_spike_xs: Array[float] = []

func _ready() -> void:
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.shape = RectangleShape2D.new()
		col.shape.size = platform_size
		col.position = platform_size / 2.0
	
	# Shift platformasi bo'lsa, tuzoqlar mavjudligini avtomatik aniqlash
	if not has_ceiling_teeth and (name.to_lower().contains("ceiling") or global_position.y <= 10.0):
		call_deferred("_check_ceiling_traps")
	queue_redraw()

func _check_ceiling_traps() -> void:
	if not is_inside_tree():
		return
	var traps := get_tree().get_nodes_in_group("traps")
	var bot_y := global_position.y + platform_size.y
	var found_trap := false
	_crusher_ranges.clear()
	_crushers.clear()
	_falling_spike_xs.clear()
	
	for t in traps:
		if t is Crusher:
			var cy: float = t.global_position.y
			if absf(cy + t.crusher_size.y - bot_y) <= 24.0 or absf(cy - bot_y) <= 24.0:
				var rel_x: float = t.global_position.x - global_position.x
				_crusher_ranges.append(Vector2(rel_x, rel_x + t.crusher_size.x))
				_crushers.append(t)
				found_trap = true
		elif t is FallingSpikeTrap:
			var sy: float = t.global_position.y
			if absf(sy - bot_y) <= 24.0:
				var rel_x: float = t.global_position.x - global_position.x
				_falling_spike_xs.append(rel_x)
				found_trap = true
	
	if found_trap:
		has_ceiling_teeth = true
		add_to_group("ceiling_platforms")
		queue_redraw()

func _draw() -> void:
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var base_col := Color("#0d131f") if is_winter else Color("#1c1a22")
	draw_rect(Rect2(Vector2.ZERO, platform_size), base_col, true)

	# Ezuvchi (Crusher) pastga tushganda, uning shift ichidagi joyi bo'sh (o'yiq) qolishi
	for c in _crushers:
		if c != null and is_instance_valid(c):
			if c.global_position.y > c.initial_position.y + 2.0:
				var rel_x: float = c.global_position.x - global_position.x
				var cw: float = c.crusher_size.x
				var bot_y := platform_size.y
				var socket_top := 8.0
				var cavity_col := Color(0.04, 0.05, 0.08, 1.0)
				if is_winter:
					cavity_col = Color(0.03, 0.05, 0.09, 1.0)
				# Bo'sh qolgan ichki chuqurlik
				draw_rect(
					Rect2(rel_x, socket_top, cw, bot_y - socket_top),
					cavity_col,
					true
				)
				# Uyaning ichki yon va ustki qirralari
				draw_line(
					Vector2(rel_x, socket_top),
					Vector2(rel_x, bot_y),
					Color("#141722"),
					1.5
				)
				draw_line(
					Vector2(rel_x + cw, socket_top),
					Vector2(rel_x + cw, bot_y),
					Color("#141722"),
					1.5
				)
				draw_line(
					Vector2(rel_x, socket_top),
					Vector2(rel_x + cw, socket_top),
					Color("#141722"),
					1.5
				)

	if is_winter:
		# Yerda qor qatlami (Snow layer on ground/platforms)
		var snow_h := 5.5
		if platform_size.x > 36.0:
			# Asosiy toza qor qoplami
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, snow_h)), Color("#f1f5f9"), true)
			# Qorning yaltiroq ustki qatlami
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 2.0)), Color("#ffffff"), true)
			# Qor ostidagi sovuq soya
			draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 1.5)), Color("#94a3b8"), true)
			
			# Qirralardan osilib turgan kichik muz donalari (Icicles)
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
			# Tik devor uchun muz qirovi
			draw_rect(Rect2(Vector2.ZERO, Vector2(2.5, platform_size.y)), Color(0.49, 0.86, 0.99, 0.6), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(platform_size.x, 3.0)), Color("#342f3a"), true)

	# Shiftning uzluksiz tikanlari va aldovchi (soxta) stalaktitlari (borderlarsiz!)
	if has_ceiling_teeth and platform_size.x > 64.0:
		var teeth_col := Color(0.22, 0.74, 0.97, 0.92) if is_winter else base_col
		var bot_y := platform_size.y
		var start_x := 32.0
		var end_x := platform_size.x - 32.0
		var cur_x := start_x

		while cur_x < end_x:
			# Crusher joylashgan oraliqni tekshirish (Crusher o'z tishlarini o'zi chizadi)
			var in_crusher := false
			for cr in _crusher_ranges:
				if cur_x >= (cr.x - 2.0) and cur_x < (cr.y - 2.0):
					in_crusher = true
					break
			if in_crusher:
				cur_x += 16.0
				continue

			# Haqiqiy tushuvchi tikan joylashgan nuqtani tekshirish
			var at_real_spike := false
			for sx in _falling_spike_xs:
				if absf(cur_x + 16.0 - sx) < 12.0:
					at_real_spike = true
					break
			if at_real_spike:
				cur_x += 32.0
				continue

			# Aldovchi (soxta) 32px li uzun tikan (tushuvchi tikan bilan bir xil o'lchamda!)
			if fposmod(cur_x, 96.0) < 16.0 and (cur_x + 32.0) <= end_x:
				var decoy_pts := PackedVector2Array([
					Vector2(cur_x, bot_y),
					Vector2(cur_x + 16.0, bot_y + 32.0),
					Vector2(cur_x + 32.0, bot_y)
				])
				draw_colored_polygon(decoy_pts, teeth_col)
				cur_x += 32.0
			else:
				# Standart 16px li kichik tish (Crusher tishlari bilan bir xil o'lchamda)
				var tooth_pts := PackedVector2Array([
					Vector2(cur_x, bot_y),
					Vector2(cur_x + 8.0, bot_y + 13.0),
					Vector2(cur_x + 16.0, bot_y)
				])
				draw_colored_polygon(tooth_pts, teeth_col)
				cur_x += 16.0
