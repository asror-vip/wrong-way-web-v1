extends StaticBody2D
class_name SolidPlatform

@export var platform_size: Vector2 = Vector2(350, 160)
@export var has_ceiling_teeth: bool = false

var _crusher_ranges: Array[Vector2] = []
var _falling_spike_xs: Array[float] = []

func _ready() -> void:
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.shape = RectangleShape2D.new()
		col.shape.size = platform_size
		col.position = platform_size / 2.0
	
	# Shift platformasi bo'lsa, tuzoqlar mavjudligini avtomatik aniqlash
	var is_ceiling := name.to_lower().contains("ceiling") or global_position.y <= 10.0
	if not has_ceiling_teeth and is_ceiling:
		call_deferred("_check_ceiling_traps")
	queue_redraw()

func _check_ceiling_traps() -> void:
	if not is_inside_tree():
		return
	var traps := get_tree().get_nodes_in_group("traps")
	var bot_y := global_position.y + platform_size.y
	var found_trap := false
	_crusher_ranges.clear()
	_falling_spike_xs.clear()
	
	for t in traps:
		if t is Crusher:
			var cy: float = t.global_position.y
			if absf(cy + t.crusher_size.y - bot_y) <= 24.0 or absf(cy - bot_y) <= 24.0:
				var rel_x: float = t.global_position.x - global_position.x
				_crusher_ranges.append(Vector2(rel_x, rel_x + t.crusher_size.x))
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
	var is_ceiling_plat := name.to_lower().contains("ceiling") or global_position.y <= 10.0
	if not has_ceiling_teeth and is_ceiling_plat:
		_check_ceiling_traps()
	var is_winter := false
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("is_winter_theme"):
		is_winter = gm.is_winter_theme()

	var base_col := Color("#0d131f") if is_winter else Color("#1c1a22")

	# Shift platformasida crusher bo'lsa, uzilish (gap) bilan segmentlarga bo'lib chizish
	if has_ceiling_teeth and not _crusher_ranges.is_empty():
		var ranges := _crusher_ranges.duplicate()
		ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cur_x := 0.0
		for r in ranges:
			var rx1 := clampf(r.x, 0.0, platform_size.x)
			var rx2 := clampf(r.y, 0.0, platform_size.x)
			if rx1 > cur_x:
				_draw_segment(cur_x, rx1 - cur_x, base_col, is_winter)
			cur_x = maxf(cur_x, rx2)
		if cur_x < platform_size.x:
			_draw_segment(cur_x, platform_size.x - cur_x, base_col, is_winter)
	else:
		_draw_segment(0.0, platform_size.x, base_col, is_winter)

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

func _draw_segment(sx: float, sw: float, base_col: Color, is_winter: bool) -> void:
	if sw <= 0.0:
		return
	draw_rect(Rect2(sx, 0.0, sw, platform_size.y), base_col, true)
	if is_winter:
		var snow_h := 5.5
		if platform_size.x > 36.0:
			draw_rect(Rect2(sx, 0.0, sw, snow_h), Color("#f1f5f9"), true)
			draw_rect(Rect2(sx, 0.0, sw, 2.0), Color("#ffffff"), true)
			draw_rect(Rect2(sx, 0.0, sw, 1.5), Color("#94a3b8"), true)
		else:
			var frost_rect := Rect2(sx, 0.0, minf(sw, 2.5), platform_size.y)
			draw_rect(frost_rect, Color(0.49, 0.86, 0.99, 0.6), true)
	else:
		draw_rect(Rect2(sx, 0.0, sw, 3.0), Color("#342f3a"), true)
