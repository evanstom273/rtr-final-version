extends Control
class_name WrestlerRingMarker

var participant_id := ""
var snapshot: Dictionary = {}
var reduced_motion := false
var _movement_tween: Tween
var _feedback_tween: Tween
var _facing_vector := Vector2.RIGHT

@onready var _name_label: Label = %NameLabel
@onready var _side_badge: Label = %SideBadge
@onready var _control_badge: Label = %ControlBadge
@onready var _state_badge: Label = %StateBadge
@onready var _debug_label: Label = %DebugLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	queue_redraw()


func apply_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	participant_id = str(snapshot.get("id", participant_id))
	visible = bool(snapshot.get("is_active", true)) and int(snapshot.get("position", WrestlerResource.Position.NONE)) != WrestlerResource.Position.NONE
	if not visible:
		return
	_name_label.text = _short_name(str(snapshot.get("display_name", "Wrestler")))
	_name_label.tooltip_text = str(snapshot.get("display_name", "Wrestler"))
	_side_badge.text = "P1" if bool(snapshot.get("is_player", false)) else str(snapshot.get("side_label", "AI"))
	_control_badge.visible = bool(snapshot.get("has_control", false))
	var weapon_name := str(snapshot.get("held_weapon_name", "")).strip_edges()
	var badges: Array[String] = [_state_abbreviation()]
	if not weapon_name.is_empty():
		badges.append(_weapon_abbreviation(weapon_name))
	var bleeding := str(snapshot.get("bleeding_label", "None"))
	if bleeding != "None":
		badges.append("BLEED %s" % bleeding.left(3).to_upper())
	_state_badge.text = " / ".join(badges)
	_debug_label.visible = bool(snapshot.get("debug_visible", false))
	_debug_label.text = str(snapshot.get("debug_text", ""))
	_facing_vector = snapshot.get("facing_vector", _facing_vector) as Vector2
	tooltip_text = str(snapshot.get("accessible_description", _accessible_description()))
	queue_redraw()


func move_to(target_position: Vector2, duration: float, immediate: bool = false) -> void:
	if position.distance_squared_to(target_position) < 0.25:
		return
	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()
	if immediate or reduced_motion or duration <= 0.0:
		position = target_position
		return
	_movement_tween = create_tween()
	_movement_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_movement_tween.tween_property(self, "position", target_position, duration)


func pulse(kind: StringName) -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	modulate = Color.WHITE
	scale = Vector2.ONE
	if reduced_motion:
		modulate = _feedback_color(kind)
		_feedback_tween = create_tween()
		_feedback_tween.tween_property(self, "modulate", Color.WHITE, 0.14)
		return
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(self, "scale", Vector2(1.09, 1.09), 0.09)
	_feedback_tween.parallel().tween_property(self, "modulate", _feedback_color(kind), 0.09)
	_feedback_tween.tween_property(self, "scale", Vector2.ONE, 0.13)
	_feedback_tween.parallel().tween_property(self, "modulate", Color.WHITE, 0.13)


func settle() -> void:
	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	scale = Vector2.ONE
	modulate = Color.WHITE


func _draw() -> void:
	if not visible:
		return
	var centre := Vector2(size.x * 0.5, 29.0)
	var position_state := int(snapshot.get("position", WrestlerResource.Position.STANDING))
	var accent := Color(0.25, 0.64, 1.0, 1.0) if bool(snapshot.get("is_player", false)) else Color(0.93, 0.3, 0.3, 1.0)
	var fill := Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45, 0.96)
	if bool(snapshot.get("has_control", false)):
		draw_circle(centre, 24.0, Color(0.95, 0.78, 0.22, 0.22))
		draw_arc(centre, 24.0, 0.0, TAU, 32, Color(0.95, 0.78, 0.22, 0.95), 3.0, true)
	if bool(snapshot.get("is_targeted", false)):
		draw_arc(centre, 28.0, 0.0, TAU, 32, Color(0.95, 0.78, 0.22, 0.72), 2.0, true)
	match position_state:
		WrestlerResource.Position.GROUNDED:
			draw_style_box(_marker_box(fill, accent, 9), Rect2(centre - Vector2(24.0, 9.0), Vector2(48.0, 18.0)))
		WrestlerResource.Position.SEATED:
			draw_style_box(_marker_box(fill, accent, 7), Rect2(centre - Vector2(17.0, 14.0), Vector2(34.0, 28.0)))
		WrestlerResource.Position.KNEELING:
			var diamond := PackedVector2Array([centre + Vector2(0, -18), centre + Vector2(17, 0), centre + Vector2(0, 18), centre + Vector2(-17, 0)])
			draw_colored_polygon(diamond, fill)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), accent, 2.5, true)
		WrestlerResource.Position.PERCHED:
			draw_circle(centre, 17.0, fill)
			draw_arc(centre, 20.0, -PI, 0.0, 18, Color(0.95, 0.78, 0.22, 1.0), 3.0, true)
			draw_line(centre + Vector2(-18, 19), centre + Vector2(18, 19), accent, 3.0)
		WrestlerResource.Position.CLIMBING:
			var climbing_shape := PackedVector2Array([centre + Vector2(0, -20), centre + Vector2(17, 16), centre + Vector2(-17, 16)])
			draw_colored_polygon(climbing_shape, fill)
			draw_polyline(PackedVector2Array([climbing_shape[0], climbing_shape[1], climbing_shape[2], climbing_shape[0]]), accent, 2.5, true)
			for y in [-10.0, 0.0, 10.0]:
				draw_line(centre + Vector2(-8, y), centre + Vector2(8, y), Color(0.95, 0.78, 0.22), 2.0, true)
		_:
			if bool(snapshot.get("is_player", false)):
				draw_circle(centre, 18.0, fill)
				draw_arc(centre, 18.0, 0.0, TAU, 28, accent, 2.5, true)
			else:
				var points := PackedVector2Array([centre + Vector2(0, -19), centre + Vector2(19, 0), centre + Vector2(0, 19), centre + Vector2(-19, 0)])
				draw_colored_polygon(points, fill)
				draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), accent, 2.5, true)
	_draw_orientation(centre, accent)
	_draw_motion(centre, accent)
	if int(snapshot.get("bleeding_severity", 0)) > 0:
		draw_colored_polygon(PackedVector2Array([centre + Vector2(25, -18), centre + Vector2(20, -7), centre + Vector2(30, -7)]), Color(0.86, 0.16, 0.18, 0.92))


func _draw_orientation(centre: Vector2, accent: Color) -> void:
	var orientation := int(snapshot.get("orientation", WrestlerResource.Orientation.FRONT))
	if orientation in [WrestlerResource.Orientation.FACE_UP, WrestlerResource.Orientation.FACE_DOWN]:
		var eye_y := centre.y - 2.0
		if orientation == WrestlerResource.Orientation.FACE_UP:
			draw_circle(Vector2(centre.x - 5, eye_y), 1.8, Color.WHITE)
			draw_circle(Vector2(centre.x + 5, eye_y), 1.8, Color.WHITE)
		else:
			draw_line(Vector2(centre.x - 7, eye_y), Vector2(centre.x + 7, eye_y), Color(0.9, 0.9, 0.92), 2.0)
		return
	var direction := _facing_vector.normalized()
	if direction.length_squared() < 0.1:
		direction = Vector2.RIGHT
	if orientation == WrestlerResource.Orientation.BACK:
		direction *= -1.0
	var tip := centre + direction * 23.0
	var wing := direction.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * 9.0 + wing, tip - direction * 9.0 - wing]), accent)


func _draw_motion(centre: Vector2, accent: Color) -> void:
	match int(snapshot.get("motion_state", WrestlerResource.MotionState.STATIONARY)):
		WrestlerResource.MotionState.RUNNING:
			for offset in [0.0, 6.0, 12.0]:
				draw_line(centre + Vector2(-30.0 - offset, -7.0), centre + Vector2(-20.0 - offset, -7.0), accent, 2.0)
		WrestlerResource.MotionState.ROPE_REBOUND:
			draw_arc(centre, 27.0, -0.8, 0.8, 12, Color(0.95, 0.78, 0.22), 2.5, true)
		WrestlerResource.MotionState.RISING:
			draw_line(centre + Vector2(-25, 11), centre + Vector2(-25, -11), Color(0.75, 0.84, 0.95), 2.0)
			draw_colored_polygon(PackedVector2Array([centre + Vector2(-25, -15), centre + Vector2(-30, -7), centre + Vector2(-20, -7)]), Color(0.75, 0.84, 0.95))
		WrestlerResource.MotionState.STAGGERING:
			draw_polyline(PackedVector2Array([centre + Vector2(-26, -10), centre + Vector2(-31, -4), centre + Vector2(-24, 2), centre + Vector2(-30, 9)]), Color(1.0, 0.62, 0.3), 2.0, true)


func _state_abbreviation() -> String:
	var motion := int(snapshot.get("motion_state", WrestlerResource.MotionState.STATIONARY))
	if motion != WrestlerResource.MotionState.STATIONARY:
		match motion:
			WrestlerResource.MotionState.RUNNING:
				return "RUN"
			WrestlerResource.MotionState.ROPE_REBOUND:
				return "REB"
			WrestlerResource.MotionState.RISING:
				return "RISE"
			WrestlerResource.MotionState.STAGGERING:
				return "STAG"
	match int(snapshot.get("position", WrestlerResource.Position.STANDING)):
		WrestlerResource.Position.GROUNDED:
			return "DOWN"
		WrestlerResource.Position.SEATED:
			return "SEAT"
		WrestlerResource.Position.KNEELING:
			return "KNEEL"
		WrestlerResource.Position.PERCHED:
			return "TOP"
		WrestlerResource.Position.CLIMBING:
			return "CLIMB"
	return "UP"


func _weapon_abbreviation(value: String) -> String:
	var words := value.to_upper().split(" ", false)
	if words.size() == 1:
		return str(words[0]).left(6)
	var result := ""
	for word in words:
		result += str(word).left(1)
	return result.left(5)


func _accessible_description() -> String:
	return "%s, %s controlled, %s, %s, %s, %s%s" % [
		str(snapshot.get("display_name", "Wrestler")),
		"player" if bool(snapshot.get("is_player", false)) else "AI",
		_enum_name(WrestlerResource.Position, int(snapshot.get("position", 0))),
		_enum_name(WrestlerResource.Orientation, int(snapshot.get("orientation", 0))),
		_enum_name(WrestlerResource.Area, int(snapshot.get("area", 0))),
		_enum_name(WrestlerResource.MotionState, int(snapshot.get("motion_state", 0))),
		", holding %s" % str(snapshot.get("held_weapon_name", "")) if not str(snapshot.get("held_weapon_name", "")).is_empty() else "",
	]


func _enum_name(values: Dictionary, value: int) -> String:
	for key in values:
		if int(values[key]) == value:
			return str(key).to_lower().replace("_", " ").capitalize()
	return "Unknown"


func _short_name(value: String) -> String:
	var clean := value.strip_edges()
	if clean.length() <= 18:
		return clean
	return clean.left(16) + "…"


func _marker_box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


func _feedback_color(kind: StringName) -> Color:
	if kind in [&"finisher", &"signature", &"pin"]:
		return Color(1.0, 0.88, 0.48, 1.0)
	if kind in [&"reversal", &"crash", &"impact"]:
		return Color(1.0, 0.58, 0.5, 1.0)
	return Color(0.72, 0.86, 1.0, 1.0)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()
