extends Control
class_name MoveCategoryIcon

@export var icon_id: StringName = &"generic":
	set(value):
		icon_id = value
		queue_redraw()
@export var icon_color: Color = Color(0.9, 0.91, 0.89, 1.0):
	set(value):
		icon_color = value
		queue_redraw()
@export var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var unit := minf(size.x, size.y) / 48.0
	var center := size * 0.5
	var width := maxf(1.6, 2.2 * unit)
	match icon_id:
		&"strike":
			_draw_impact(center, unit, width)
		&"grapple":
			_draw_standing_front(center, unit, width)
		&"throw":
			_draw_standing_behind(center, unit, width)
		&"slam":
			_draw_grounded(center, unit, width)
		&"submission":
			_draw_lock(center, unit)
		&"aerial":
			_draw_diving(center, unit, width, true)
		&"reversal":
			_draw_rope_rebound(center, unit, width)
		&"pinning":
			_draw_grounded(center, unit, width)
		&"weapon":
			_draw_impact(center, unit, width)
		&"environmental":
			_draw_corner(center, unit, width)
		&"standing_front":
			_draw_standing_front(center, unit, width)
		&"standing_behind":
			_draw_standing_behind(center, unit, width)
		&"running":
			_draw_running(center, unit, width)
		&"rope_rebound":
			_draw_rope_rebound(center, unit, width)
		&"grounded":
			_draw_grounded(center, unit, width)
		&"springboard":
			_draw_springboard(center, unit, width)
		&"corner":
			_draw_corner(center, unit, width)
		&"diving_standing":
			_draw_diving(center, unit, width, true)
		&"diving_grounded":
			_draw_diving(center, unit, width, false)
		_:
			_draw_impact(center, unit, width)
	if locked:
		_draw_lock(center + Vector2(12, 12) * unit, unit)


func _draw_standing_front(center: Vector2, unit: float, width: float) -> void:
	draw_circle(center + Vector2(-8, -8) * unit, 4.0 * unit, icon_color)
	draw_circle(center + Vector2(8, -8) * unit, 4.0 * unit, icon_color)
	draw_line(center + Vector2(-8, -3) * unit, center + Vector2(-8, 12) * unit, icon_color, width, true)
	draw_line(center + Vector2(8, -3) * unit, center + Vector2(8, 12) * unit, icon_color, width, true)
	draw_line(center + Vector2(-8, 2) * unit, center + Vector2(1, 6) * unit, icon_color, width, true)
	draw_line(center + Vector2(8, 2) * unit, center + Vector2(-1, 6) * unit, icon_color, width, true)


func _draw_standing_behind(center: Vector2, unit: float, width: float) -> void:
	draw_circle(center + Vector2(-4, -7) * unit, 4.0 * unit, icon_color)
	draw_circle(center + Vector2(7, -4) * unit, 3.2 * unit, icon_color.darkened(0.18))
	draw_line(center + Vector2(-4, -2) * unit, center + Vector2(-4, 13) * unit, icon_color, width, true)
	draw_line(center + Vector2(7, 0) * unit, center + Vector2(7, 12) * unit, icon_color.darkened(0.18), width, true)
	draw_arc(center, 16.0 * unit, -1.05, 1.2, 18, icon_color, width, true)
	_draw_arrow_head(center + Vector2(6, 15) * unit, Vector2(0.8, 0.6), unit, width)


func _draw_running(center: Vector2, unit: float, width: float) -> void:
	draw_circle(center + Vector2(3, -11) * unit, 4.0 * unit, icon_color)
	draw_line(center + Vector2(2, -6) * unit, center + Vector2(-2, 5) * unit, icon_color, width, true)
	draw_line(center + Vector2(-2, 5) * unit, center + Vector2(11, 12) * unit, icon_color, width, true)
	draw_line(center + Vector2(-1, 1) * unit, center + Vector2(-12, 12) * unit, icon_color, width, true)
	draw_line(center + Vector2(0, -3) * unit, center + Vector2(12, 2) * unit, icon_color, width, true)
	for offset in [-9.0, -3.0, 3.0]:
		draw_line(center + Vector2(-19, offset) * unit, center + Vector2(-9, offset) * unit, icon_color.darkened(0.25), width * 0.7, true)


func _draw_rope_rebound(center: Vector2, unit: float, width: float) -> void:
	for x in [-15.0, -10.0]:
		draw_line(center + Vector2(x, -17) * unit, center + Vector2(x, 17) * unit, icon_color, width * 0.75, true)
	for y in [-10.0, 0.0, 10.0]:
		draw_line(center + Vector2(-18, y) * unit, center + Vector2(-7, y) * unit, icon_color, width * 0.65, true)
	draw_arc(center + Vector2(1, 0) * unit, 13.0 * unit, -1.55, 1.55, 20, icon_color, width, true)
	_draw_arrow_head(center + Vector2(1, 13) * unit, Vector2(-1, 0), unit, width)


func _draw_grounded(center: Vector2, unit: float, width: float) -> void:
	draw_line(center + Vector2(-19, 13) * unit, center + Vector2(19, 13) * unit, icon_color.darkened(0.2), width, true)
	draw_circle(center + Vector2(-12, 5) * unit, 4.0 * unit, icon_color)
	draw_line(center + Vector2(-7, 6) * unit, center + Vector2(12, 8) * unit, icon_color, width, true)
	draw_line(center + Vector2(2, 7) * unit, center + Vector2(13, 1) * unit, icon_color, width, true)
	draw_line(center + Vector2(4, -14) * unit, center + Vector2(4, -3) * unit, icon_color, width, true)
	_draw_arrow_head(center + Vector2(4, 0) * unit, Vector2(0, 1), unit, width)


func _draw_springboard(center: Vector2, unit: float, width: float) -> void:
	draw_line(center + Vector2(-19, 11) * unit, center + Vector2(19, 11) * unit, icon_color, width, true)
	draw_line(center + Vector2(-19, 16) * unit, center + Vector2(19, 16) * unit, icon_color.darkened(0.25), width * 0.65, true)
	draw_arc(center + Vector2(0, 8) * unit, 15.0 * unit, 3.35, 5.95, 20, icon_color, width, true)
	_draw_arrow_head(center + Vector2(14, 3) * unit, Vector2(0.7, 0.7), unit, width)


func _draw_corner(center: Vector2, unit: float, width: float) -> void:
	draw_line(center + Vector2(-13, -17) * unit, center + Vector2(-13, 16) * unit, icon_color, width, true)
	draw_line(center + Vector2(-13, 13) * unit, center + Vector2(17, 13) * unit, icon_color, width, true)
	for y in [-10.0, 0.0, 10.0]:
		draw_circle(center + Vector2(-9, y) * unit, 2.5 * unit, icon_color)
	draw_line(center + Vector2(-6, -8) * unit, center + Vector2(12, 7) * unit, icon_color.darkened(0.12), width, true)
	_draw_arrow_head(center + Vector2(12, 7) * unit, Vector2(0.75, 0.65), unit, width)


func _draw_diving(center: Vector2, unit: float, width: float, standing_target: bool) -> void:
	draw_line(center + Vector2(-17, -12) * unit, center + Vector2(-17, 15) * unit, icon_color, width, true)
	draw_line(center + Vector2(-20, -8) * unit, center + Vector2(-10, -8) * unit, icon_color, width, true)
	draw_arc(center + Vector2(-2, 1) * unit, 16.0 * unit, 3.7, 6.05, 20, icon_color, width, true)
	_draw_arrow_head(center + Vector2(14, -3) * unit, Vector2(0.7, 0.7), unit, width)
	if standing_target:
		draw_circle(center + Vector2(14, 7) * unit, 3.0 * unit, icon_color.darkened(0.12))
		draw_line(center + Vector2(14, 10) * unit, center + Vector2(14, 18) * unit, icon_color.darkened(0.12), width, true)
	else:
		draw_circle(center + Vector2(6, 15) * unit, 2.8 * unit, icon_color.darkened(0.12))
		draw_line(center + Vector2(9, 15) * unit, center + Vector2(19, 16) * unit, icon_color.darkened(0.12), width, true)


func _draw_impact(center: Vector2, unit: float, width: float) -> void:
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var direction := Vector2.from_angle(angle)
		draw_line(center + direction * 7.0 * unit, center + direction * 17.0 * unit, icon_color, width, true)
	draw_circle(center, 5.0 * unit, icon_color)


func _draw_arrow_head(point: Vector2, direction: Vector2, unit: float, width: float) -> void:
	var forward := direction.normalized()
	var side := Vector2(-forward.y, forward.x)
	draw_line(point, point - forward * 6.0 * unit + side * 4.0 * unit, icon_color, width, true)
	draw_line(point, point - forward * 6.0 * unit - side * 4.0 * unit, icon_color, width, true)


func _draw_lock(center: Vector2, unit: float) -> void:
	var lock_color := Color(0.94, 0.76, 0.25, 1.0)
	draw_arc(center + Vector2(0, -3) * unit, 4.0 * unit, PI, TAU, 10, lock_color, maxf(1.4, 1.8 * unit), true)
	draw_rect(Rect2(center + Vector2(-5, -3) * unit, Vector2(10, 8) * unit), lock_color, false, maxf(1.4, 1.8 * unit), true)
