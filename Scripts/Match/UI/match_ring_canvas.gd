extends Control
class_name MatchRingCanvas

var cue_from := Vector2.ZERO
var cue_to := Vector2.ZERO
var cue_color := Color.TRANSPARENT
var cue_visible := false
var special_mode: StringName = &""
var environment_objects: Array = []


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


func set_environment_objects(value: Array) -> void:
	environment_objects = value.duplicate(true)
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
	_draw_environment_objects(mat_rect, apron_rect)
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


func _draw_environment_objects(mat_rect: Rect2, apron_rect: Rect2) -> void:
	for raw in environment_objects:
		if not raw is Dictionary:
			continue
		var data := raw as Dictionary
		if int(data.get("lifecycle", -1)) == MatchWeaponInstance.Lifecycle.HELD:
			continue
		var id := int(data.get("instance_id", 0))
		var area := int(data.get("area", WrestlerResource.Area.OUTSIDE))
		var slot := Vector2(float((id * 37) % 5 - 2), float((id * 53) % 5 - 2)) * 12.0
		var centre := mat_rect.get_center() + slot
		if area == WrestlerResource.Area.OUTSIDE:
			centre = Vector2(apron_rect.position.x - 34.0, apron_rect.get_center().y) + slot
		elif area == WrestlerResource.Area.RAMP:
			centre = Vector2(apron_rect.position.x * 0.45, apron_rect.get_center().y) + slot
		var kind := int(data.get("weapon_kind", WeaponResource.WeaponKind.HANDHELD))
		var life := int(data.get("lifecycle", MatchWeaponInstance.Lifecycle.DROPPED))
		match kind:
			WeaponResource.WeaponKind.TABLE:
				var table_size := Vector2(42, 22) if life != MatchWeaponInstance.Lifecycle.SET_CORNER else Vector2(18, 46)
				draw_rect(Rect2(centre - table_size * 0.5, table_size), Color(0.37, 0.23, 0.12, 0.92), true)
				draw_rect(Rect2(centre - table_size * 0.5, table_size), Color(0.94, 0.7, 0.25, 0.85), false, 2.0)
				if life == MatchWeaponInstance.Lifecycle.SET_STACKED:
					draw_line(centre + Vector2(-20, -15), centre + Vector2(20, -15), Color(0.94, 0.7, 0.25), 3.0)
			WeaponResource.WeaponKind.LADDER:
				for x in [-9.0, 9.0]:
					draw_line(centre + Vector2(x, 22), centre + Vector2(x * 0.45, -22), Color(0.68, 0.74, 0.82), 3.0, true)
				for y in [-14.0, -4.0, 6.0, 16.0]:
					draw_line(centre + Vector2(-7, y), centre + Vector2(7, y), Color(0.68, 0.74, 0.82), 2.0, true)
			WeaponResource.WeaponKind.THUMBTACKS:
				for index in range(7):
					var angle := TAU * float(index) / 7.0
					draw_circle(centre + Vector2(cos(angle), sin(angle)) * 13.0, 2.2, Color(0.92, 0.75, 0.28))
			_:
				draw_line(centre + Vector2(-16, 8), centre + Vector2(16, -8), Color(0.78, 0.68, 0.5), 5.0, true)


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
