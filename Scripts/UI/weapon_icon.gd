extends Control
class_name WeaponIcon

var icon_id: StringName = &"weapon"
var tint := Color(0.92, 0.76, 0.25, 1.0)


func set_icon(value: StringName, enabled: bool = true) -> void:
	icon_id = value
	tint = Color(0.92, 0.76, 0.25, 1.0) if enabled else Color(0.38, 0.42, 0.48, 0.75)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) * 0.34
	match icon_id:
		&"chair", &"steel_chair":
			draw_rect(Rect2(c.x - s * 0.55, c.y - s, s * 1.1, s * 0.75), tint, false, 3.0)
			draw_line(c + Vector2(-s * 0.48, -s * 0.22), c + Vector2(-s * 0.72, s), tint, 3.0, true)
			draw_line(c + Vector2(s * 0.48, -s * 0.22), c + Vector2(s * 0.72, s), tint, 3.0, true)
		&"kendo", &"kendo_stick", &"bat", &"baseball_bat", &"barbed_bat", &"barbed_wire_bat", &"janice", &"hockey", &"hockey_stick", &"shovel":
			draw_line(c + Vector2(-s * 0.78, s * 0.75), c + Vector2(s * 0.58, -s * 0.65), tint, 5.0, true)
			if icon_id in [&"hockey", &"hockey_stick"]:
				draw_line(c + Vector2(-s * 0.78, s * 0.75), c + Vector2(-s * 0.2, s * 0.82), tint, 5.0, true)
			elif icon_id == &"shovel":
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.42, -s * 0.52), c + Vector2(s * 0.78, -s), c + Vector2(s, -s * 0.55)]), tint)
			elif icon_id in [&"barbed_bat", &"barbed_wire_bat", &"janice"]:
				for i in range(4):
					var p := c + Vector2(-s * 0.45 + i * s * 0.28, s * 0.4 - i * s * 0.28)
					draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), tint, 2.0, true)
		&"tube", &"light_tube":
			for offset in [-5.0, 5.0]:
				draw_line(c + Vector2(-s * 0.8, s * 0.7 + offset), c + Vector2(s * 0.8, -s * 0.7 + offset), tint, 3.0, true)
		&"table":
			draw_rect(Rect2(c.x - s, c.y - s * 0.45, s * 2.0, s * 0.55), tint, false, 4.0)
			draw_line(c + Vector2(-s * 0.7, s * 0.1), c + Vector2(-s * 0.85, s), tint, 4.0, true)
			draw_line(c + Vector2(s * 0.7, s * 0.1), c + Vector2(s * 0.85, s), tint, 4.0, true)
		&"ladder":
			draw_line(c + Vector2(-s * 0.72, s), c + Vector2(-s * 0.35, -s), tint, 4.0, true)
			draw_line(c + Vector2(s * 0.72, s), c + Vector2(s * 0.35, -s), tint, 4.0, true)
			for i in range(4):
				var y := -s * 0.7 + i * s * 0.46
				draw_line(c + Vector2(-s * 0.48, y), c + Vector2(s * 0.48, y), tint, 3.0, true)
		&"tacks", &"thumbtacks":
			for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				var p := c + Vector2(cos(angle), sin(angle)) * s * 0.4
				draw_circle(p, 4.0, tint)
				draw_line(p, p + Vector2(cos(angle), sin(angle)) * s * 0.65, tint, 2.0, true)
		_:
			draw_circle(c, s * 0.65, tint, false, 3.0, true)
			draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), tint, 3.0, true)
