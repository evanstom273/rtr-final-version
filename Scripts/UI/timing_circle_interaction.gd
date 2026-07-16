extends Control
class_name TimingCircleInteraction

signal result_selected(request_id: int, result: int, timed_out: bool, accuracy: float)

const NEAR_MISS_DISTANCE := 0.09
const GRADE_CLEAN := &"clean"
const GRADE_NEAR_MISS := &"near_miss"
const GRADE_MISS := &"miss"
const GRADE_TIMEOUT := &"timeout"

var last_grade: StringName = GRADE_MISS
var last_miss_distance: float = 1.0

var _request_id: int = 0
var _success_window: float = 28.0
var _time_limit: float = 1.6
var _speed_multiplier: float = 1.0
var _elapsed: float = 0.0
var _progress: float = 1.0
var _active: bool = false
var _resolved: bool = false
var _last_touch_msec: int = -1000

@onready var _title: Label = %InteractionTitle
@onready var _prompt: Label = %InteractionPrompt
@onready var _timer: Label = %InteractionTimer
@onready var _canvas: Control = %CircleCanvas
@onready var _tap_button: Button = %TapButton


func _ready() -> void:
	_canvas.draw.connect(_draw_circle)
	_canvas.gui_input.connect(_on_gui_input)
	_tap_button.button_down.connect(_resolve_press)
	visible = false
	set_process(false)


func open_interaction(request: Dictionary) -> void:
	_request_id = int(request.get("request_id", 0))
	_success_window = clampf(float(request.get("success_window", 28.0)), 3.0, 80.0)
	_time_limit = maxf(0.2, float(request.get("time_limit", 1.6)))
	_speed_multiplier = clampf(float(request.get("speed_multiplier", 1.0)), 0.5, 2.5)
	_title.text = str(request.get("title", "TIMING"))
	_prompt.text = str(request.get("prompt", "Tap when the rings meet."))
	_tap_button.text = str(request.get("button_text", "TAP"))
	_elapsed = 0.0
	_progress = 1.0
	_active = true
	_resolved = false
	last_grade = GRADE_MISS
	last_miss_distance = 1.0
	visible = true
	set_process(true)
	_canvas.queue_redraw()
	_tap_button.grab_focus()


func close_interaction() -> void:
	var should_cancel := _active and not _resolved
	_active = false
	visible = false
	set_process(false)
	if should_cancel:
		_resolved = true
		last_grade = GRADE_TIMEOUT
		last_miss_distance = 1.0
		result_selected.emit(_request_id, MatchInteractionModel.InputResult.FAIL, true, 0.0)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_progress = maxf(0.0, 1.0 - (_elapsed / _time_limit) * _speed_multiplier)
	_timer.text = "%.1fs" % maxf(0.0, _time_limit - _elapsed)
	_canvas.queue_redraw()
	if _elapsed >= _time_limit or _progress <= 0.0:
		_finish(MatchInteractionModel.InputResult.FAIL, true, 0.0)


func _input(event: InputEvent) -> void:
	if not _active:
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


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_last_touch_msec = Time.get_ticks_msec()
		_resolve_press()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec() - _last_touch_msec > 250:
			_resolve_press()
			accept_event()


func _resolve_press() -> void:
	if not _active or _resolved:
		return
	var target_progress := 0.28
	var half_window := _success_window / 200.0
	var distance := absf(_progress - target_progress)
	var distance_from_edge := maxf(0.0, distance - half_window)
	last_miss_distance = distance_from_edge
	var accuracy := clampf(1.0 - distance / maxf(0.001, half_window), 0.0, 1.0)
	if distance <= half_window:
		last_grade = GRADE_CLEAN
		_finish(MatchInteractionModel.InputResult.SUCCESS, false, accuracy)
	elif distance_from_edge <= NEAR_MISS_DISTANCE:
		last_grade = GRADE_NEAR_MISS
		_finish(MatchInteractionModel.InputResult.NEAR_MISS, false, 0.0)
	else:
		last_grade = GRADE_MISS
		_finish(MatchInteractionModel.InputResult.FAIL, false, 0.0)


func _finish(result: int, timed_out: bool, accuracy: float) -> void:
	if not _active or _resolved:
		return
	_resolved = true
	_active = false
	set_process(false)
	if timed_out:
		last_grade = GRADE_TIMEOUT
		last_miss_distance = 1.0
	result_selected.emit(_request_id, result, timed_out, accuracy)


func _draw_circle() -> void:
	if not is_instance_valid(_canvas):
		return
	var center := _canvas.size * 0.5
	var max_radius := maxf(24.0, minf(_canvas.size.x, _canvas.size.y) * 0.43)
	var target_radius := max_radius * 0.28
	var half_window_radius := max_radius * (_success_window / 200.0)
	_canvas.draw_circle(center, max_radius, Color(0.025, 0.04, 0.07, 0.98))
	_canvas.draw_arc(center, maxf(2.0, target_radius - half_window_radius), 0.0, TAU, 96, Color(0.24, 0.45, 0.70, 0.55), 3.0)
	_canvas.draw_arc(center, target_radius + half_window_radius, 0.0, TAU, 96, Color(0.86, 0.70, 0.24, 0.9), 4.0)
	_canvas.draw_arc(center, maxf(2.0, max_radius * _progress), 0.0, TAU, 96, Color(0.92, 0.95, 1.0, 1.0), 7.0)
	_canvas.draw_circle(center, 8.0, Color(0.75, 0.14, 0.18, 1.0))
