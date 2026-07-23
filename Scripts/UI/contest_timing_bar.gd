extends Control
class_name ContestTimingBar

signal result_selected(result: StringName)

const RED_RESULT := &"RED"
const YELLOW_RESULT := &"YELLOW"
const GREEN_RESULT := &"GREEN"
const BASE_TRAVEL_SPEED := 0.8
const DEFAULT_TIME_LIMIT := 2.0

var last_result_was_timeout: bool = false

var _probabilities: Dictionary = {"red": 55.0, "yellow": 30.0, "green": 15.0}
var _indicator_progress: float = 0.0
var _direction: float = 1.0
var _speed: float = BASE_TRAVEL_SPEED
var _elapsed: float = 0.0
var _time_limit: float = DEFAULT_TIME_LIMIT
var _active: bool = false

@onready var _title: Label = %ContestTitle
@onready var _prompt: Label = %ContestPrompt
@onready var _odds: Label = %ContestOdds
@onready var _timer_label: Label = %TimerLabel
@onready var _countdown: ProgressBar = %CountdownBar
@onready var _track: Control = %ContestTrack
@onready var _red_left: ColorRect = %RedLeftZone
@onready var _yellow_left: ColorRect = %YellowLeftZone
@onready var _green_zone: ColorRect = %GreenZone
@onready var _yellow_right: ColorRect = %YellowRightZone
@onready var _red_right: ColorRect = %RedRightZone
@onready var _indicator: ColorRect = %TimingIndicator
@onready var _stop_button: Button = %StopButton


func _ready() -> void:
	_track.gui_input.connect(_on_track_gui_input)
	_track.resized.connect(_layout_zones)
	_stop_button.pressed.connect(_stop_indicator)
	visible = false
	set_process(false)


static func normalize_probabilities(probabilities: Dictionary) -> Dictionary:
	var green := clampf(float(probabilities.get("green", 15.0)), 3.0, 24.0)
	var yellow := clampf(float(probabilities.get("yellow", 30.0)), 10.0, 38.0)
	var red := 100.0 - green - yellow
	return {"red": red, "yellow": yellow, "green": green}


func open_contest(
	probabilities: Dictionary,
	title: String,
	prompt: String,
	time_limit_seconds: float = DEFAULT_TIME_LIMIT,
	band_labels: PackedStringArray = PackedStringArray(),
) -> void:
	_probabilities = normalize_probabilities(probabilities)
	_title.text = title
	_prompt.text = prompt
	var labels := band_labels
	if labels.size() < 3:
		labels = PackedStringArray(["FAIL", "PARTIAL", "REVERSE"])
	_odds.text = "%s %d%%   %s %d%%   %s %d%%" % [
		labels[0],
		roundi(float(_probabilities.get("red", 0.0))),
		labels[1],
		roundi(float(_probabilities.get("yellow", 0.0))),
		labels[2],
		roundi(float(_probabilities.get("green", 0.0))),
	]
	_indicator_progress = 0.0
	_direction = 1.0
	_elapsed = 0.0
	_time_limit = maxf(0.1, time_limit_seconds)
	_speed = BASE_TRAVEL_SPEED * _difficulty_speed_multiplier(float(_probabilities.get("red", 55.0)))
	last_result_was_timeout = false
	_active = true
	visible = true
	_countdown.max_value = _time_limit
	_countdown.value = _time_limit
	_update_timer_display()
	set_process(true)
	_layout_zones()
	_stop_button.grab_focus()


func close_contest() -> void:
	_active = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_indicator_progress += delta * _speed * _direction
	if _indicator_progress >= 1.0:
		_indicator_progress = 2.0 - _indicator_progress
		_direction = -1.0
	elif _indicator_progress <= 0.0:
		_indicator_progress = -_indicator_progress
		_direction = 1.0
	_layout_indicator()
	_update_timer_display()
	if _elapsed >= _time_limit:
		_finish(RED_RESULT, true)


func _layout_zones() -> void:
	if not is_node_ready():
		return
	var width := _track.size.x
	var height := _track.size.y
	var red_half := width * float(_probabilities.get("red", 55.0)) / 200.0
	var yellow_half := width * float(_probabilities.get("yellow", 30.0)) / 200.0
	var green_width := width * float(_probabilities.get("green", 15.0)) / 100.0
	_set_zone_rect(_red_left, 0.0, red_half, height)
	_set_zone_rect(_yellow_left, red_half, yellow_half, height)
	_set_zone_rect(_green_zone, red_half + yellow_half, green_width, height)
	_set_zone_rect(_yellow_right, red_half + yellow_half + green_width, yellow_half, height)
	_set_zone_rect(_red_right, red_half + yellow_half * 2.0 + green_width, red_half, height)
	_layout_indicator()


func _set_zone_rect(zone: ColorRect, left: float, width: float, height: float) -> void:
	zone.position = Vector2(left, 0.0)
	zone.size = Vector2(maxf(0.0, width), height)


func _layout_indicator() -> void:
	var travel := maxf(0.0, _track.size.x - _indicator.size.x)
	_indicator.position = Vector2(travel * _indicator_progress, 0.0)
	_indicator.size.y = _track.size.y


func _update_timer_display() -> void:
	var remaining := maxf(0.0, _time_limit - _elapsed)
	_countdown.value = remaining
	_timer_label.text = "%.1fs" % remaining
	_timer_label.modulate = AppThemePalette.ERROR if remaining <= 0.5 else Color.WHITE


func _on_track_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_stop_indicator()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		_stop_indicator()
		accept_event()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var should_stop := false
	if event is InputEventKey and event.is_action_pressed("ui_accept"):
		should_stop = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		should_stop = true
	elif event is InputEventScreenTouch and event.pressed:
		should_stop = true
	if should_stop:
		_stop_indicator()
		get_viewport().set_input_as_handled()


func _stop_indicator() -> void:
	if not _active:
		return
	var red_half := float(_probabilities.get("red", 55.0)) / 200.0
	var yellow_half := float(_probabilities.get("yellow", 30.0)) / 200.0
	var green_width := float(_probabilities.get("green", 15.0)) / 100.0
	var yellow_left_end := red_half + yellow_half
	var green_end := yellow_left_end + green_width
	var yellow_right_end := green_end + yellow_half
	if _indicator_progress < red_half or _indicator_progress >= yellow_right_end:
		_finish(RED_RESULT)
	elif _indicator_progress < yellow_left_end or _indicator_progress >= green_end:
		_finish(YELLOW_RESULT)
	else:
		_finish(GREEN_RESULT)


func _finish(result: StringName, timed_out: bool = false) -> void:
	if not _active:
		return
	last_result_was_timeout = timed_out
	close_contest()
	result_selected.emit(result)


func _difficulty_speed_multiplier(red_probability: float) -> float:
	if red_probability < 35.0:
		return 1.0
	if red_probability <= 50.0:
		return 1.35
	if red_probability <= 65.0:
		return 1.75
	return 2.1
