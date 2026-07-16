extends Control
class_name ControlMeterInteraction

signal result_selected(request_id: int, result: int, timed_out: bool, marker_value: float)

const EDGE_MARGIN := 0.06
const FEEDBACK_SECONDS := 0.10
const DEFAULT_GOLD_ZONE_SCALE := 0.25
const MIN_GOLD_ZONE_SCALE := 0.10
const RAW_ZONE_MIN := 6.0
const RAW_ZONE_MAX := 30.0
const NEAR_MISS_DISTANCE := 0.10

const GRADE_CLEAN := &"clean"
const GRADE_NEAR_MISS := &"near_miss"
const GRADE_MISS := &"miss"
const GRADE_TIMEOUT := &"timeout"

var last_grade: StringName = GRADE_MISS
var last_miss_distance: float = 1.0

var _request_id: int = 0
var _success_window: float = 22.0 * DEFAULT_GOLD_ZONE_SCALE
var _marker_speed: float = 1.25
var _time_limit: float = 1.6
var _zone_center: float = 0.5
var _marker_value: float = 0.0
var _edge_forgiveness: float = 0.0
var _edge_forgiveness_pixels: float = 0.0
var _zone_height_scale: float = 1.0
var _zone_opacity: float = 1.0
var _binary_only: bool = false
var _one_way: bool = false
var _direction: float = 1.0
var _next_one_way_direction: float = 1.0
var _elapsed: float = 0.0
var _active: bool = false
var _resolved: bool = false
var _completion_emitted: bool = false
var _generation: int = 0
var _last_touch_msec: int = -1000
var _rng := RandomNumberGenerator.new()

@onready var _title: Label = %InteractionTitle
@onready var _prompt: Label = %InteractionPrompt
@onready var _timer: Label = %InteractionTimer
@onready var _track: Control = %ControlTrack
@onready var _gold_zone: Control = %GoldZone
@onready var _marker: Control = %ControlMarker
@onready var _tap_button: Button = %TapButton


func _ready() -> void:
	_track.resized.connect(_layout_meter)
	_tap_button.button_down.connect(_resolve_press)
	_rng.randomize()
	visible = false
	set_process(false)


func open_interaction(request: Dictionary) -> void:
	_generation += 1
	_request_id = int(request.get("request_id", 0))
	var raw_zone_min := float(request.get("raw_zone_min", RAW_ZONE_MIN))
	var raw_zone_max := maxf(raw_zone_min, float(request.get("raw_zone_max", RAW_ZONE_MAX)))
	var raw_success_window := clampf(
		float(request.get("success_window", 22.0)),
		raw_zone_min,
		raw_zone_max,
	)
	var gold_zone_scale := clampf(
		float(request.get("gold_zone_scale", DEFAULT_GOLD_ZONE_SCALE)),
		MIN_GOLD_ZONE_SCALE,
		1.0,
	)
	_success_window = raw_success_window * gold_zone_scale
	_marker_speed = clampf(float(request.get("marker_speed", 1.25)), 0.35, 4.0)
	_time_limit = maxf(0.3, float(request.get("time_limit", 1.6)))
	_edge_forgiveness = maxf(0.0, float(request.get("edge_forgiveness", 0.0)))
	_edge_forgiveness_pixels = maxf(0.0, float(request.get("edge_forgiveness_pixels", 0.0)))
	if (
		DisplayServer.is_touchscreen_available()
		or ResponsiveUI.current_layout_mode != ResponsiveUI.LayoutMode.DESKTOP
	):
		_edge_forgiveness = maxf(
			_edge_forgiveness,
			maxf(0.0, float(request.get("touch_edge_forgiveness", _edge_forgiveness))),
		)
		_edge_forgiveness_pixels = maxf(
			_edge_forgiveness_pixels,
			maxf(0.0, float(request.get("touch_edge_forgiveness_pixels", _edge_forgiveness_pixels))),
		)
	_zone_height_scale = clampf(float(request.get("zone_height_scale", 1.0)), 0.2, 1.0)
	_zone_opacity = clampf(float(request.get("zone_opacity", 1.0)), 0.25, 1.0)
	_binary_only = bool(request.get("binary_only", false))
	_one_way = bool(request.get("one_way", false))
	if request.has("rng_seed"):
		_rng.seed = int(request.get("rng_seed", 0))
	else:
		_rng.randomize()
	var half_window := _success_window / 200.0
	var minimum_center := EDGE_MARGIN + half_window
	var maximum_center := 1.0 - EDGE_MARGIN - half_window
	if request.has("zone_center"):
		_zone_center = clampf(float(request.get("zone_center", 0.5)), minimum_center, maximum_center)
	else:
		_zone_center = _rng.randf_range(minimum_center, maximum_center)
	_title.text = str(request.get("title", "CONTROL"))
	_prompt.text = str(request.get("prompt", "Stop the marker inside the gold zone."))
	_tap_button.text = str(request.get("button_text", "TAKE CONTROL"))
	if _one_way:
		_direction = _next_one_way_direction
		_marker_value = 0.0 if _direction > 0.0 else 1.0
		_next_one_way_direction *= -1.0
	else:
		_marker_value = 0.0
		_direction = 1.0
	_elapsed = 0.0
	_active = true
	_resolved = false
	_completion_emitted = false
	last_grade = GRADE_MISS
	last_miss_distance = 1.0
	visible = true
	self_modulate = Color.WHITE
	set_process(true)
	_layout_meter()
	_tap_button.grab_focus()


func close_interaction() -> void:
	_generation += 1
	var should_cancel := not _completion_emitted and (_active or _resolved)
	_active = false
	_resolved = true
	visible = false
	set_process(false)
	if should_cancel:
		_completion_emitted = true
		last_grade = GRADE_TIMEOUT
		last_miss_distance = 1.0
		result_selected.emit(_request_id, MatchInteractionModel.InputResult.FAIL, true, _marker_value)


func _process(delta: float) -> void:
	if not _active or _resolved:
		return
	_elapsed += delta
	# One-way prompts must cross the complete track once before expiring. A speed
	# below 1.0 must not make the marker disappear before it reaches the far edge.
	var one_way_speed_scale := maxf(1.0, _marker_speed)
	var travel_speed := one_way_speed_scale / _time_limit if _one_way else _marker_speed
	_marker_value += _direction * travel_speed * delta
	if _one_way and (_marker_value >= 1.0 or _marker_value <= 0.0):
		_marker_value = 1.0 if _direction > 0.0 else 0.0
		_layout_meter()
		_finish(MatchInteractionModel.InputResult.FAIL, true)
		return
	while not _one_way and (_marker_value > 1.0 or _marker_value < 0.0):
		if _marker_value > 1.0:
			_marker_value = 2.0 - _marker_value
			_direction = -1.0
		elif _marker_value < 0.0:
			_marker_value = -_marker_value
			_direction = 1.0
	_timer.text = "%.1fs" % maxf(0.0, _time_limit - _elapsed)
	_layout_meter()
	if _elapsed >= _time_limit:
		_finish(MatchInteractionModel.InputResult.FAIL, true)


func _input(event: InputEvent) -> void:
	if not _active or _resolved:
		return
	if event is InputEventKey and event.is_action_pressed("ui_accept"):
		_resolve_press()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		_last_touch_msec = Time.get_ticks_msec()
		_resolve_press()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec() - _last_touch_msec > 250:
			_resolve_press()
			get_viewport().set_input_as_handled()


func _resolve_press() -> void:
	if not _active or _resolved:
		return
	# Refresh and test the exact rectangles the player sees. Control coordinates
	# are logical pixels, so this remains aligned across DPI and touch scaling.
	_layout_meter()
	var track_width := maxf(1.0, _track.size.x)
	var marker_centre := _marker.position.x + _marker.size.x * 0.5
	var zone_left := _gold_zone.position.x
	var zone_right := zone_left + _gold_zone.size.x
	var forgiveness := _edge_forgiveness_pixels + _edge_forgiveness * track_width
	var distance_from_edge_pixels := 0.0
	if marker_centre < zone_left:
		distance_from_edge_pixels = zone_left - marker_centre
	elif marker_centre > zone_right:
		distance_from_edge_pixels = marker_centre - zone_right
	last_miss_distance = distance_from_edge_pixels / track_width
	if distance_from_edge_pixels <= forgiveness:
		last_grade = GRADE_CLEAN
		_finish(MatchInteractionModel.InputResult.SUCCESS, false)
	elif last_miss_distance <= NEAR_MISS_DISTANCE:
		if _binary_only:
			last_grade = GRADE_MISS
			_finish(MatchInteractionModel.InputResult.FAIL, false)
		else:
			last_grade = GRADE_NEAR_MISS
			_finish(MatchInteractionModel.InputResult.NEAR_MISS, false)
	else:
		last_grade = GRADE_MISS
		_finish(MatchInteractionModel.InputResult.FAIL, false)


func _finish(result: int, timed_out: bool) -> void:
	if not _active or _resolved:
		return
	_resolved = true
	_active = false
	set_process(false)
	if timed_out:
		last_grade = GRADE_TIMEOUT
		last_miss_distance = 1.0
	var generation := _generation
	if result == MatchInteractionModel.InputResult.SUCCESS:
		self_modulate = Color(1.18, 1.1, 0.68, 1.0)
	elif result == MatchInteractionModel.InputResult.NEAR_MISS:
		self_modulate = Color(1.05, 0.82, 0.48, 1.0)
	else:
		self_modulate = Color(1.0, 0.55, 0.58, 1.0)
	await get_tree().create_timer(FEEDBACK_SECONDS).timeout
	if generation != _generation or _completion_emitted:
		return
	_completion_emitted = true
	result_selected.emit(_request_id, result, timed_out, _marker_value)


func _layout_meter() -> void:
	if not is_instance_valid(_track):
		return
	var width := _track.size.x
	var height := _track.size.y
	var half_window := _success_window / 200.0
	var zone_height := height * _zone_height_scale
	_gold_zone.position = Vector2(
		width * (_zone_center - half_window),
		(height - zone_height) * 0.5,
	)
	_gold_zone.size = Vector2(width * half_window * 2.0, zone_height)
	_gold_zone.self_modulate = Color(1.0, 1.0, 1.0, _zone_opacity)
	var marker_width := maxf(14.0, _marker.size.x)
	_marker.position = Vector2((width - marker_width) * _marker_value, 0.0)
	_marker.size = Vector2(marker_width, height)


func _rendered_marker_center_normalized() -> float:
	if not is_instance_valid(_track) or not is_instance_valid(_marker):
		return _marker_value
	var width := _track.size.x
	if width <= 0.0:
		return _marker_value
	var marker_width := maxf(14.0, _marker.size.x)
	var left := (width - marker_width) * _marker_value
	return clampf((left + marker_width * 0.5) / width, 0.0, 1.0)
