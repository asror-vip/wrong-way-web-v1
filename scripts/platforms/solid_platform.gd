extends StaticBody2D
class_name SolidPlatform

@export var platform_size: Vector2 = Vector2(350, 160)
@export var has_ceiling_teeth: bool = false
@export var is_extension_or_wall: bool = false

var _crusher_ranges: Array[Vector2] = []
var _falling_spike_xs: Array[float] = []

func _is_ceiling_platform() -> bool:
	if name.to_lower().contains("ceiling"):
		return true
	if name.to_lower().contains("wall"):
		return false
	return global_position.y <= 30.0 and platform_size.x >= 200.0

func _is_wall_or_extension() -> bool:
	if is_extension_or_wall:
		return true
	var n := name.to_lower()
	return n.contains("wall") or n.contains("extension") or n.contains("ceiling")

func _ready() -> void:
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.shape = RectangleShape2D.new()
		col.shape.size = platform_size
		col.position = platform_size / 2.0
	
	# Shift platformasi bo'lsa, har doim tikanli bo'lishi va ezuvchidan oldi qatlamda (z_index=10) turishi kerak
	var is_ceiling := _is_ceiling_platform()
	if is_ceiling:
		has_ceiling_teeth = true
		z_index = 10
		add_to_group("ceiling_platforms")
		call_deferred("_check_ceiling_traps")
	queue_redraw()

func _check_ceiling_traps() -> void:
	if not is_inside_tree():
		return
	var traps := get_tree().get_nodes_in_group("traps")
	var bot_y := global_position.y + platform_size.y
	_crusher_ranges.clear()
	_falling_spike_xs.clear()
	
	for t in traps:
		if t is Crusher:
			var cy: float = t.global_position.y
			if absf(cy + t.crusher_size.y - bot_y) <= 24.0 or absf(cy - bot_y) <= 24.0:
				var rel_x: float = t.global_position.x - global_position.x
				_crusher_ranges.append(Vector2(rel_x, rel_x + t.crusher_size.x))
		elif t is FallingSpikeTrap:
			var sy: float = t.global_position.y
			if absf(sy - bot_y) <= 24.0:
				var rel_x: float = t.global_position.x - global_position.x
				_falling_spike_xs.append(rel_x)
	
	var is_ceiling := _is_ceiling_platform()
	if is_ceiling:
		has_ceiling_teeth = true
		add_to_group("ceiling_platforms")
	queue_redraw()

func _draw() -> void:
	var is_ceiling_plat := _is_ceiling_platform()
	if not has_ceiling_teeth and is_ceiling_plat:
		_check_ceiling_traps()

	var ch: int = 1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_current_chapter"):
		ch = gm.get_current_chapter()

	# Asosiy tosh rangini boblarga (chapter) qarab belgilaymiz:
	var base_col := Color("#1c1a22") # Default / Limbo
	if ch == 2:
		base_col = Color("#0d131f") # Winter (To'q ko'k-kulrang)
	elif ch == 3:
		base_col = Color("#062319") # Emerald Woods (To'q yashil)
	elif ch == 4:
		base_col = Color("#291c14") # Golden Canyon (To'q jigarrang)
	elif ch == 5:
		base_col = Color("#1a0505") # Inferno Abyss (To'q qizil-qora)

	# Shift platformasida crusher bo'lsa, o'sha kichik ochiq joy uchun kichik shiftcha chizish (tepa tarafi butun shift bilan bir tekis)
	if has_ceiling_teeth and not _crusher_ranges.is_empty():
		var ranges := _crusher_ranges.duplicate()
		ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cur_x := 0.0
		for r in ranges:
			var rx1 := clampf(r.x, 0.0, platform_size.x)
			var rx2 := clampf(r.y, 0.0, platform_size.x)
			if rx1 > cur_x:
				_draw_segment(cur_x, rx1 - cur_x, base_col, ch)
			_draw_top_ceiling_cap(rx1, rx2 - rx1, base_col, ch)
			cur_x = maxf(cur_x, rx2)
		if cur_x < platform_size.x:
			_draw_segment(cur_x, platform_size.x - cur_x, base_col, ch)
	else:
		_draw_segment(0.0, platform_size.x, base_col, ch)

	# Shiftning uzluksiz tikanlari va aldovchi (soxta) stalaktitlari (aniq bitta standart!)
	if has_ceiling_teeth and platform_size.x > 64.0:
		var teeth_col := base_col
		if ch == 2: teeth_col = Color(0.22, 0.74, 0.97, 0.92) # Muz
		elif ch == 3: teeth_col = Color("#166534") # Zaharli tikan
		elif ch == 4: teeth_col = Color("#b45309") # Qumli qoya tikan
		elif ch == 5: teeth_col = Color("#7f1d1d") # Qizigan obsidian
		var bot_y := platform_size.y
		var start_x := 32.0
		var end_x := platform_size.x - 32.0
		var spike_w := 32.0
		var slot_w := 96.0
		var cycle_w := spike_w + slot_w # 128.0

		# 1. Katta tikanlar uchun yagona standart setka (Grid anchor)
		var anchor_x := start_x + 96.0
		if not _crusher_ranges.is_empty():
			var cr: Vector2 = _crusher_ranges[0]
			var cr_center := (cr.x + cr.y) / 2.0
			var ideal_spike_x := cr_center - (slot_w / 2.0 + spike_w)
			anchor_x = ideal_spike_x
			while anchor_x > (start_x + cycle_w):
				anchor_x -= cycle_w
			while anchor_x < start_x:
				anchor_x += cycle_w

		# 2. Standart setka bo'yicha katta tikanlar joylashuvini hisoblash
		var big_spikes: Array[float] = []
		var bx := anchor_x
		while bx <= (end_x - spike_w):
			big_spikes.append(bx)
			bx += cycle_w
		bx = anchor_x - cycle_w
		while bx >= start_x:
			big_spikes.push_front(bx)
			bx -= cycle_w

		# Ezuvchi bilan to'qnashuvchi katta tikanlarni filtrlash
		var valid_big_spikes: Array[float] = []
		for sp_x in big_spikes:
			var collides := false
			for cr in _crusher_ranges:
				if (sp_x + spike_w) > (cr.x - 8.0) and sp_x < (cr.y + 8.0):
					collides = true
					break
			if not collides:
				valid_big_spikes.append(sp_x)

		# Katta tikanlarni chizish (borderlarsiz, toza poligon)
		for sp_x in valid_big_spikes:
			var pts := PackedVector2Array([
				Vector2(sp_x, bot_y),
				Vector2(sp_x + 16.0, bot_y + 32.0),
				Vector2(sp_x + 32.0, bot_y)
			])
			draw_colored_polygon(pts, teeth_col)

		# 3. Katta tikanlar va ezuvchilar orasidagi zonalarni 16px tishlar bilan to'ldirish
		var cur_x := start_x
		while cur_x < end_x:
			# Katta tikan zonasida bo'lsa, uni o'tkazib yuborish
			var in_big := false
			for sp_x in valid_big_spikes:
				if cur_x >= (sp_x - 1.0) and cur_x < (sp_x + spike_w - 1.0):
					cur_x = sp_x + spike_w
					in_big = true
					break
			if in_big:
				continue

			# Ezuvchi zonasida bo'lsa, o'tkazib yuborish (Crusher o'z tishlarini chizadi)
			var in_crusher := false
			for cr in _crusher_ranges:
				if cur_x >= (cr.x - 1.0) and cur_x < (cr.y - 1.0):
					cur_x = cr.y
					in_crusher = true
					break
			if in_crusher:
				continue

			# Haqiqiy tushuvchi tikan zonasini tekshirish
			var in_falling := false
			for sx in _falling_spike_xs:
				if cur_x >= (sx - 17.0) and cur_x < (sx + 15.0):
					cur_x = sx + 16.0
					in_falling = true
					break
			if in_falling:
				continue

			# Navbatdagi to'siqqacha bo'lgan masofa
			var next_bound := end_x
			for sp_x in valid_big_spikes:
				if sp_x > cur_x and sp_x < next_bound:
					next_bound = sp_x
			for cr in _crusher_ranges:
				if cr.x > cur_x and cr.x < next_bound:
					next_bound = cr.x
			for sx in _falling_spike_xs:
				var z_left := sx - 16.0
				if z_left > cur_x and z_left < next_bound:
					next_bound = z_left

			var rem := next_bound - cur_x
			if rem <= 0.0:
				cur_x = next_bound
				continue

			var tw := minf(16.0, rem)
			if tw >= 6.0:
				var tooth_pts := PackedVector2Array([
					Vector2(cur_x, bot_y),
					Vector2(cur_x + tw * 0.5, bot_y + 13.0),
					Vector2(cur_x + tw, bot_y)
				])
				draw_colored_polygon(tooth_pts, teeth_col)
			cur_x += tw

func _draw_segment(sx: float, sw: float, base_col: Color, ch: int) -> void:
	if sw <= 0.0:
		return
	draw_rect(Rect2(sx, 0.0, sw, platform_size.y), base_col, true)
	if _is_wall_or_extension():
		return

	# Boblarga mos pol qoplamalari (Top layers)
	if ch == 2: # Winter
		var snow_h := 5.5
		if platform_size.x > 36.0:
			draw_rect(Rect2(sx, 0.0, sw, snow_h), Color("#f1f5f9"), true)
			draw_rect(Rect2(sx, 0.0, sw, 2.0), Color("#ffffff"), true)
			draw_rect(Rect2(sx, snow_h - 1.5, sw, 1.5), Color("#94a3b8"), true)
		else:
			var frost_rect := Rect2(sx, 0.0, minf(sw, 2.5), platform_size.y)
			draw_rect(frost_rect, Color(0.49, 0.86, 0.99, 0.6), true)
	elif ch == 3: # Emerald Woods (To'q yashil mox / Moss)
		draw_rect(Rect2(sx, 0.0, sw, 4.0), Color("#14532d"), true)
		draw_rect(Rect2(sx, 4.0, sw, 2.0), Color("#064e3b"), true)
	elif ch == 4: # Golden Canyon (Sahro / Qum)
		var sand_h := 6.0
		draw_rect(Rect2(sx, 0.0, sw, sand_h), Color("#fcd34d"), true)
		draw_rect(Rect2(sx, sand_h - 2.0, sw, 2.0), Color("#d97706"), true)
	elif ch == 5: # Inferno Abyss (Lava / Obsidian)
		draw_rect(Rect2(sx, 0.0, sw, 3.0), Color("#450a0a"), true)
		draw_rect(Rect2(sx, 0.0, sw, 1.0), Color("#f97316"), true) # Lava qizishi
	else: # Chapter 1 (Default / Limbo)
		draw_rect(Rect2(sx, 0.0, sw, 3.0), Color("#342f3a"), true)

func _draw_top_ceiling_cap(sx: float, sw: float, base_col: Color, ch: int) -> void:
	if sw <= 0.0:
		return
	# Ezuvchi ustidagi kichik ochiq joy uchun kichik shiftcha (tepa tarafi butun shift bilan 100% bir tekis)
	var cap_h := 16.0
	draw_rect(Rect2(sx, 0.0, sw, cap_h), base_col, true)

	if ch == 2:
		var snow_h := 5.5
		draw_rect(Rect2(sx, 0.0, sw, snow_h), Color("#f1f5f9"), true)
		draw_rect(Rect2(sx, 0.0, sw, 2.0), Color("#ffffff"), true)
		draw_rect(Rect2(sx, snow_h - 1.5, sw, 1.5), Color("#94a3b8"), true)
	elif ch == 3:
		draw_rect(Rect2(sx, 0.0, sw, 4.0), Color("#14532d"), true)
		draw_rect(Rect2(sx, 4.0, sw, 2.0), Color("#064e3b"), true)
	elif ch == 4:
		draw_rect(Rect2(sx, 0.0, sw, 6.0), Color("#fcd34d"), true)
		draw_rect(Rect2(sx, 4.0, sw, 2.0), Color("#d97706"), true)
	elif ch == 5:
		draw_rect(Rect2(sx, 0.0, sw, 3.0), Color("#450a0a"), true)
		draw_rect(Rect2(sx, 0.0, sw, 1.0), Color("#f97316"), true)
	else:
		draw_rect(Rect2(sx, 0.0, sw, 3.0), Color("#342f3a"), true)
