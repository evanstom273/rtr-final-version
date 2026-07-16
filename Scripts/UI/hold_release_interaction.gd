extends Control
class_name HoldReleaseInteraction

signal result_selected(request_id: int, result: int, timed_out: bool, release_value: float)

var _request_id: int = 0
var _success_window: float = 26.0
var _fill_duration: float = 1.4
var _time_limit: float = 1.8
var _elapsed: float = 0.0
var _value: float = 0.0
var _holding: bool = false
var _active: bool = false
var _resolved: bool = false
var _touch_active: bool = false
var _last_touch_msec: int = -1000

@onready var _title: Label = %InteractionTitle
@onready var _prompt: Label = %InteractionPrompt
@onready var _timer: Label = %InteractionTimer
@onready var _track: Control = %PowerTrack
@onready var _sweet_spot: ColorRect = %SweetSpot
@onready var _fill: ColorRect = %PowerFill
@onready var _hold_button: Button = %HoldButton


func _ready() -> void:
	_track.resized.connect(_layout_meter)
	_hold_button.button_down.connect(_begin_hold)
	_hold_button.button_up.connect(_release_hold)
	visible = false
	set_process(false)


func open_interaction(request: Dictionary) -> void:
	_request_id = int(request.get("request_id", 0))
	_success_window = clampf(float(request.get("success_window", 26.0)), 5.0, 45.0)
	_fill_duration = maxf(0.3, float(request.get("fill_duration", 1.4)))
	_time_limit = maxf(_fill_duration, float(request.get("time_limit", 1.8)))
	_title.text = str(request.get("title", "POWER"))
	_prompt.text = str(request.get("prompt", "Hold, then release in the sweet spot."))
	_hold_button.text = str(request.get("button_text", "HOLD / RELEASE"))
	_elapsed = 0.0
	_value = 0.0
	_holding = false
	_touch_active = false
	_active = true
	_resolved = false
	visible = true
	set_process(true)
	_layout_meter()
	_hold_button.grab_focus()


func close_interaction() -> void:
	var should_cancel := _active and not _resolved
	_active = false
	_holding = false
	visible = false
	set_process(false)
	if should_cancel:
		_resolved = true
		result_selected.emit(_request_id, MatchInteractionModel.InputResult.FAIL, true, _value)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _holding:
		_value = clampf(_value + delta / _fill_duration, 0.0, 1.0)
		if _value >= 1.0:
			_finish(MatchInteractionModel.InputResult.FAIL, false, _value)
			return
	_timer.text = "%.1fs" % maxf(0.0, _time_limit - _elapsed)
	_layout_meter()
	if _elapsed >= _time_limit:
		_finish(MatchInteractionModel.InputResult.FAIL, true, _value)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.is_action("ui_accept"):
		if event.pressed and not event.echo:
			_begin_hold()
		elif not event.pressed:
			_release_hold()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_last_touch_msec = Time.get_ticks_msec()
		_touch_active = event.pressed
		if event.pressed:
			_begin_hold()
		else:
			_release_hold()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec > 250:
			if event.pressed:
				_begin_hold()
			else:
				_release_hold()
			get_viewport().set_input_as_handled()


func _begin_hold() -> void:
	if not _active or _resolved or _holding:
		return
	_holding = true


func _release_hold() -> void:
	if not _active or _resolved or not _holding:
		return
	_holding = false
	var center := 0.65
	var half_window := _success_window / 200.0
	var success := absf(_value - center) <= half_window
	_finish(
		MatchInteractionModel.InputResult.SUCCESS if success else MatchInteractionModel.InputResult.FAIL,
		false,
		_value,
	)


func _finish(result: int, timed_out: bool, release_value: float) -> void:
	if not _active or _resolved:
		return
	_resolved = true
	_active = false
	_holding = false
	set_process(false)
	result_selected.emit(_request_id, result, timed_out, release_value)


func _layout_meter() -> void:
	if not is_instance_valid(_track):
		return
	var width := _track.size.x
	var height := _track.size.y
	var center := 0.65
	var half_window := _success_window / 200.0
	_sweet_spot.position = Vector2(width * (center - half_window), 0.0)
	_sweet_spot.size = Vector2(width * half_window * 2.0, height)
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(width * _value, height)
