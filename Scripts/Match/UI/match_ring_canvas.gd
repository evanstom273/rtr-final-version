extends Control
class_name MatchRingCanvas

var cue_from := Vector2.ZERO
var cue_to := Vector2.ZERO
var cue_color := Color.TRANSPARENT
var cue_visible := false
var special_mode: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func set_action_cue(from: Vector2, to: Vector2, color: Color) -> void:
	cue_from = from
	cue_to = to
	cue_color = color
	cue_visible = true
	queue_redraw()


func clear_action_cue() -> void:
	cue_visible = false
	queue_redraw()


func set_special_mode(value: StringName) -> void:
	special_mode = value
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var floor_rect := Rect2(Vector2.ZERO, size)
	draw_rect(floor_rect, Color(0.025, 0.035, 0.052, 1.0), true)
	var apron_rect := RingVisualPlacementResolver.apron_rect_for_canvas(size)
	var mat_rect := RingVisualPlacementResolver.mat_rect_for_canvas(size)
	_draw_ramp(apron_rect)
	draw_style_box(_flat_box(Color(0.075, 0.09, 0.125, 1.0), Color(0.23, 0.29, 0.39, 1.0), 2), apron_rect)
	draw_style_box(_flat_box(Color(0.13, 0.155, 0.19, 1.0), Color(0.48, 0.57, 0.68, 1.0), 2), mat_rect)
	_draw_mat_markings(mat_rect)
	_draw_ropes(mat_rect)
	_draw_posts(mat_rect)
	if cue_visible:
		_draw_action_cue()
	if special_mode == &"pin":
		draw_arc(mat_rect.get_center(), minf(mat_rect.size.x, mat_rect.size.y) * 0.16, 0.0, TAU, 48, Color(0.95, 0.78, 0.22, 0.42), 5.0, true)
	elif special_mode == &"submission":
		draw_arc(mat_rect.get_center(), minf(mat_rect.size.x, mat_rect.size.y) * 0.18, 0.0, TAU, 48, Color(0.83, 0.28, 0.28, 0.42), 5.0, true)


func _draw_ramp(apron_rect: Rect2) -> void:
	var join_x := apron_rect.position.x + 2.0
	var centre_y := apron_rect.get_center().y
	var near_half_height := apron_rect.size.y * 0.15
	var far_half_height := apron_rect.size.y * 0.24
	var ramp := PackedVector2Array([
		Vector2(join_x, centre_y - near_half_height),
		Vector2(0.0, centre_y - far_half_height),
		Vector2(0.0, centre_y + far_half_height),
		Vector2(join_x, centre_y + near_half_height),
	])
	draw_colored_polygon(ramp, Color(0.055, 0.065, 0.085, 1.0))
	for step in range(1, 5):
		var progress := float(step) / 5.0
		var x := lerpf(join_x, size.x * 0.02, progress)
		var half_height := lerpf(near_half_height, far_half_height, progress)
		draw_line(Vector2(x, centre_y - half_height), Vector2(x, centre_y + half_height), Color(0.15, 0.18, 0.23, 0.75), 1.0)


func _draw_mat_markings(mat_rect: Rect2) -> void:
	var centre := mat_rect.get_center()
	draw_line(Vector2(centre.x, mat_rect.position.y), Vector2(centre.x, mat_rect.end.y), Color(0.22, 0.25, 0.3, 0.35), 1.0)
	draw_line(Vector2(mat_rect.position.x, centre.y), Vector2(mat_rect.end.x, centre.y), Color(0.22, 0.25, 0.3, 0.35), 1.0)
	draw_circle(centre, minf(mat_rect.size.x, mat_rect.size.y) * 0.045, Color(0.78, 0.64, 0.2, 0.12))


func _draw_ropes(mat_rect: Rect2) -> void:
	var rope_colors := [
		Color(0.62, 0.69, 0.78, 0.9),
		Color(0.4, 0.48, 0.58, 0.9),
		Color(0.27, 0.34, 0.43, 0.9),
	]
	for index in range(3):
		var inset := float(index) * 5.0
		var rope_rect := mat_rect.grow(-inset)
		draw_line(rope_rect.position, Vector2(rope_rect.end.x, rope_rect.position.y), rope_colors[index], 2.0)
		draw_line(Vector2(rope_rect.end.x, rope_rect.position.y), rope_rect.end, rope_colors[index], 2.0)
		draw_line(rope_rect.end, Vector2(rope_rect.position.x, rope_rect.end.y), rope_colors[index], 2.0)
		draw_line(Vector2(rope_rect.position.x, rope_rect.end.y), rope_rect.position, rope_colors[index], 2.0)


func _draw_posts(mat_rect: Rect2) -> void:
	for point in [mat_rect.position, Vector2(mat_rect.end.x, mat_rect.position.y), mat_rect.end, Vector2(mat_rect.position.x, mat_rect.end.y)]:
		draw_circle(point, 7.0, Color(0.07, 0.08, 0.105, 1.0))
		draw_circle(point, 7.0, Color(0.84, 0.68, 0.2, 0.9), false, 2.0)


func _draw_action_cue() -> void:
	var direction := cue_to - cue_from
	if direction.length_squared() < 4.0:
		return
	draw_dashed_line(cue_from, cue_to, cue_color, 3.0, 8.0, true)
	var normal := direction.normalized()
	var tip := cue_to
	var left := tip - normal * 13.0 + normal.orthogonal() * 7.0
	var right := tip - normal * 13.0 - normal.orthogonal() * 7.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), cue_color)


func _flat_box(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	return style
