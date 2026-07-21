extends Control
class_name HoldReleaseInteraction

signal result_selected(request_id: int, result: int, timed_out: bool, release_value: float)
signal count_reached(request_id: int, count: int)

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
var _pin_count_mode: bool = false
var _reported_count: int = 0
var _zone_center: float = 0.65
var _edge_forgiveness_pixels: float = 0.0
var _touch_edge_forgiveness_pixels: float = 0.0
var _rng := RandomNumberGenerator.new()

var last_count_reached: int = 0
var last_release_missed: bool = false

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
	_rng.randomize()
	visible = false
	set_process(false)


func open_interaction(request: Dictionary) -> void:
	_request_id = int(request.get("request_id", 0))
	var raw_zone_min := float(request.get("raw_zone_min", 5.0))
	var raw_zone_max := maxf(raw_zone_min, float(request.get("raw_zone_max", 45.0)))
	_success_window = clampf(float(request.get("success_window", 26.0)), raw_zone_min, raw_zone_max)
	_fill_duration = maxf(0.3, float(request.get("fill_duration", 1.4)))
	_time_limit = maxf(_fill_duration, float(request.get("time_limit", 1.8)))
	_pin_count_mode = bool(request.get("pin_count_mode", false))
	_edge_forgiveness_pixels = maxf(0.0, float(request.get("edge_forgiveness_pixels", 2.0)))
	_touch_edge_forgiveness_pixels = maxf(
		_edge_forgiveness_pixels,
		float(request.get("touch_edge_forgiveness_pixels", 4.0)),
	)
	if request.has("rng_seed"):
		_rng.seed = int(request.get("rng_seed", 0))
	else:
		_rng.randomize()
	var half_window := _success_window / 200.0
	var minimum_center := 0.06 + half_window
	var maximum_center := 0.94 - half_window
	if request.has("zone_center"):
		_zone_center = clampf(float(request.get("zone_center", 0.65)), minimum_center, maximum_center)
	else:
		_zone_center = _rng.randf_range(minimum_center, maximum_center)
	_title.text = str(request.get("title", "POWER"))
	_prompt.text = str(request.get("prompt", "Hold, then release in the sweet spot."))
	_hold_button.text = str(request.get("button_text", "HOLD / RELEASE"))
	_hold_button.disabled = false
	_elapsed = 0.0
	_value = 0.0
	_holding = false
	_touch_active = false
	_reported_count = 0
	last_count_reached = 0
	last_release_missed = false
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
	_hold_button.disabled = false
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
			_mark_failed_release()
	if _pin_count_mode:
		_update_pin_count()
	else:
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
	var half_window := _success_window / 200.0
	var forgiveness := _edge_forgiveness_pixels / maxf(1.0, _track.size.x)
	if DisplayServer.is_touchscreen_available() or ResponsiveUI.current_layout_mode != ResponsiveUI.LayoutMode.DESKTOP:
		forgiveness = _touch_edge_forgiveness_pixels / maxf(1.0, _track.size.x)
	var success := absf(_value - _zone_center) <= half_window + forgiveness
	if success:
		_finish(MatchInteractionModel.InputResult.SUCCESS, false, _value)
	elif _pin_count_mode:
		_mark_failed_release()
	else:
		_finish(MatchInteractionModel.InputResult.FAIL, false, _value)


func _mark_failed_release() -> void:
	_holding = false
	last_release_missed = true
	_value = 0.0
	_hold_button.disabled = false
	_hold_button.text = "MISSED - HOLD TO TRY AGAIN"


func _update_pin_count() -> void:
	var reached := mini(3, floori(_elapsed))
	if reached > _reported_count:
		for count in range(_reported_count + 1, reached + 1):
			_reported_count = count
			last_count_reached = count
			count_reached.emit(_request_id, count)
	match _reported_count:
		0:
			_timer.text = "THE REFEREE IS IN POSITION"
		1:
			_timer.text = "ONE!"
		2:
			_timer.text = "TWO!"
		_:
			_timer.text = "THREE!"


func _finish(result: int, timed_out: bool, release_value: float) -> void:
	if not _active or _resolved:
		return
	_resolved = true
	_active = false
	_holding = false
	set_process(false)
	_hold_button.disabled = false
	result_selected.emit(_request_id, result, timed_out, release_value)


func _layout_meter() -> void:
	if not is_instance_valid(_track):
		return
	var width := _track.size.x
	var height := _track.size.y
	var half_window := _success_window / 200.0
	_sweet_spot.position = Vector2(width * (_zone_center - half_window), 0.0)
	_sweet_spot.size = Vector2(width * half_window * 2.0, height)
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(width * _value, height)
