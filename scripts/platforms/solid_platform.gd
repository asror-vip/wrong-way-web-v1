extends StaticBody2D
class_name SolidPlatform

@export var platform_size: Vector2 = Vector2(350, 160)
@export var has_ceiling_teeth: bool = false
@export var is_extension_or_wall: bool = false

var _crusher_ranges: Array[Vector2] = []
var _falling_spike_xs: Array[float] = []

func _is_ceiling_platform() -> bool:
	if is_extension_or_wall:
		return false
	var p_node := get_parent()
	if p_node and p_node.name.to_lower().contains("extension"):
		return false
	var n := name.to_lower()
	if n.contains("extension") or n.contains("wall"):
		return false
	if n.contains("ceiling"):
		return true
	return global_position.y <= 30.0 and platform_size.x >= 200.0

func _is_wall_or_extension() -> bool:
	if is_extension_or_wall:
		return true
	var n := name.to_lower()
	if n.contains("wall") or n.contains("extension") or n.contains("ceiling"):
		return true
	var p_node := get_parent()
	if p_node and p_node.name.to_lower().contains("extension"):
		return true
	return false

func _ready() -> void:
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.shape = RectangleShape2D.new()
		col.shape.size = platform_size
		col.position = platform_size / 2.0
	
	# Shift platformasi har doim tikanli bo'lishi va ezuvchidan oldi qatlamda
	# (z_index=10) turishi kerak
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

	# Shift platformasida crusher bo'lsa, o'sha ochiq joy uchun kichik shiftcha chizish
	# (tepa tarafi butun shift bilan bir tekis qoplanadi)
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

	# Shiftning uzluksiz tikanlari va aldovchi (soxta) stalaktitlari
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
		var cycle_w := 128.0

		# 1. Soxta katta tikanlarni real tushuvchi tikanlar va ezuvchilardan xoli joyga qo'yish
		var valid_big_spikes: Array[float] = []
		var bx := start_x + 64.0
		while bx <= (end_x - spike_w):
			var collides := false
			for cr in _crusher_ranges:
				if (bx + spike_w) > (cr.x - 16.0) and bx < (cr.y + 16.0):
					collides = true
					break
			if not collides:
				for sx in _falling_spike_xs:
					if absf((bx + 16.0) - sx) < 48.0:
						collides = true
						break
			if not collides:
				valid_big_spikes.append(bx)
			bx += cycle_w

		# Soxta katta tikanlarni chizish (32px kenglik, 32px chuqurlik)
		for sp_x in valid_big_spikes:
			var pts := PackedVector2Array([
				Vector2(sp_x, bot_y),
				Vector2(sp_x + 16.0, bot_y + 32.0),
				Vector2(sp_x + 32.0, bot_y)
			])
			draw_colored_polygon(pts, teeth_col)

		# 2. Band bo'lgan zonalarni birlashtirish (Ezuvchilar, real stalaktitlar, soxta stalaktitlar)
		var occupied_zones: Array[Vector2] = []
		for cr in _crusher_ranges:
			occupied_zones.append(Vector2(cr.x, cr.y))
		for sx in _falling_spike_xs:
			occupied_zones.append(Vector2(sx - 16.0, sx + 16.0))
		for sp_x in valid_big_spikes:
			occupied_zones.append(Vector2(sp_x, sp_x + 32.0))

		occupied_zones.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

		# Ustma-ust tushgan zonalarni bitta oraliqqa birlashtirish (Merge intervals)
		var merged_zones: Array[Vector2] = []
		for z in occupied_zones:
			if merged_zones.is_empty():
				merged_zones.append(z)
			else:
				var last := merged_zones[-1]
				if z.x <= last.y:
					merged_zones[-1] = Vector2(last.x, maxf(last.y, z.y))
				else:
					merged_zones.append(z)

		# 3. Zonalarning orasidagi bo'sh oraliqlarni bir tekis (uniform) tishlar bilan to'ldirish
		var cur_pos := start_x
		for z in merged_zones:
			var gap_start := cur_pos
			var gap_end := minf(z.x, end_x)
			if gap_end > gap_start:
				_draw_uniform_teeth(gap_start, gap_end, bot_y, teeth_col)
			cur_pos = maxf(cur_pos, z.y)

		if cur_pos < end_x:
			_draw_uniform_teeth(cur_pos, end_x, bot_y, teeth_col)

func _draw_uniform_teeth(x1: float, x2: float, bot_y: float, teeth_col: Color) -> void:
	var span := x2 - x1
	if span < 8.0:
		return
	var count := maxi(1, int(round(span / 16.0)))
	var tw := span / float(count)
	for i in range(count):
		var tx := x1 + float(i) * tw
		var tooth_pts := PackedVector2Array([
			Vector2(tx, bot_y),
			Vector2(tx + tw * 0.5, bot_y + 13.0),
			Vector2(tx + tw, bot_y)
		])
		draw_colored_polygon(tooth_pts, teeth_col)

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

func _draw_top_ceiling_cap(sx: float, sw: float, base_col: Color, _ch: int) -> void:
	if sw <= 0.0:
		return
	# Ezuvchi ustidagi uya butun shift kabi to'q tosh rangi bilan bir xil bo'ladi.
	# Hech qanday oq chiziq yoki qor chizilmaydi, toki ezuvchi joyi sezilib qolmasin!
	var cap_h := 16.0
	draw_rect(Rect2(sx, 0.0, sw, cap_h), base_col, true)
