extends Control
class_name MatchInteractionOverlay

signal submission_damage_tick(request_id: int, marker: float)
signal submission_state_changed(request_id: int, state: StringName)
signal pin_count_reached(request_id: int, count: int)

var _active_request_id: int = 0
var _interaction_active: bool = false

@onready var _safe_area: MarginContainer = %InteractionSafeArea
@onready var _panel: PanelContainer = %InteractionPanel
@onready var _timing_circle: TimingCircleInteraction = %TimingCircleInteraction
@onready var _control_meter = %ControlMeterInteraction
@onready var _hold_release: HoldReleaseInteraction = %HoldReleaseInteraction
@onready var _submission_tug: SubmissionTugInteraction = %SubmissionTugInteraction


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_submission_tug.damage_tick.connect(_on_submission_damage_tick)
	_submission_tug.struggle_state_changed.connect(_on_submission_state_changed)
	_hold_release.count_reached.connect(_on_pin_count_reached)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(_mode: int, _effective_size: Vector2) -> void:
	_panel.custom_minimum_size = Vector2(
		float(ResponsiveUI.choose(560, 680, 760)),
		float(ResponsiveUI.choose(400, 460, 500)),
	)


func is_interaction_active() -> bool:
	return _interaction_active


func get_active_request_id() -> int:
	return _active_request_id


func run_timing_circle(request: Dictionary) -> Dictionary:
	var prepared := _prepare_request(request)
	var request_id := int(prepared.request_id)
	_timing_circle.open_interaction(prepared)
	var response: Array = await _timing_circle.result_selected
	if response.is_empty() or int(response[0]) != request_id or request_id != _active_request_id:
		return {"result": MatchInteractionModel.InputResult.FAIL, "stale": true}
	_finish_active_interaction()
	return {
		"result": int(response[1]),
		"timed_out": bool(response[2]),
		"accuracy": float(response[3]),
		"grade": _timing_circle.last_grade,
		"miss_distance": _timing_circle.last_miss_distance,
		"request_id": request_id,
	}


func run_control_meter(request: Dictionary) -> Dictionary:
	var prepared := _prepare_request(request)
	var request_id := int(prepared.request_id)
	_control_meter.open_interaction(prepared)
	var response: Array = await _control_meter.result_selected
	if response.is_empty() or int(response[0]) != request_id or request_id != _active_request_id:
		return {"result": MatchInteractionModel.InputResult.FAIL, "stale": true}
	_finish_active_interaction()
	return {
		"result": int(response[1]),
		"timed_out": bool(response[2]),
		"marker_value": float(response[3]),
		"grade": _control_meter.last_grade,
		"miss_distance": _control_meter.last_miss_distance,
		"request_id": request_id,
	}


func run_hold_release(request: Dictionary) -> Dictionary:
	var prepared := _prepare_request(request)
	var request_id := int(prepared.request_id)
	_hold_release.open_interaction(prepared)
	var response: Array = await _hold_release.result_selected
	if response.is_empty() or int(response[0]) != request_id or request_id != _active_request_id:
		return {"result": MatchInteractionModel.InputResult.FAIL, "stale": true}
	var count_reached := _hold_release.last_count_reached
	var release_missed := _hold_release.last_release_missed
	_finish_active_interaction()
	return {
		"result": int(response[1]),
		"timed_out": bool(response[2]),
		"release_value": float(response[3]),
		"count_reached": count_reached,
		"release_missed": release_missed,
		"request_id": request_id,
	}


func run_submission_tug(request: Dictionary) -> Dictionary:
	var prepared := _prepare_request(request)
	var request_id := int(prepared.request_id)
	_submission_tug.open_interaction(prepared)
	var response: Array = await _submission_tug.result_selected
	if response.is_empty() or int(response[0]) != request_id or request_id != _active_request_id:
		return {"outcome": MatchInteractionModel.CombinedOutcome.BOTCH_OR_SCRAMBLE, "stale": true}
	_finish_active_interaction()
	return {
		"outcome": int(response[1]),
		"timed_out": bool(response[2]),
		"marker": float(response[3]),
		"elapsed": float(response[4]),
		"request_id": request_id,
	}


func close_interaction(_immediate: bool = true) -> void:
	_active_request_id += 1
	_interaction_active = false
	_timing_circle.close_interaction()
	_control_meter.close_interaction()
	_hold_release.close_interaction()
	_submission_tug.close_interaction()
	visible = false


func _prepare_request(request: Dictionary) -> Dictionary:
	close_interaction(true)
	_active_request_id += 1
	var prepared := request.duplicate(true)
	prepared["request_id"] = _active_request_id
	_interaction_active = true
	visible = true
	return prepared


func _finish_active_interaction() -> void:
	_interaction_active = false
	_timing_circle.close_interaction()
	_control_meter.close_interaction()
	_hold_release.close_interaction()
	_submission_tug.close_interaction()
	visible = false


func _on_submission_damage_tick(request_id: int, marker: float) -> void:
	if _interaction_active and request_id == _active_request_id:
		submission_damage_tick.emit(request_id, marker)


func _on_submission_state_changed(request_id: int, state: StringName) -> void:
	if _interaction_active and request_id == _active_request_id:
		submission_state_changed.emit(request_id, state)


func _on_pin_count_reached(request_id: int, count: int) -> void:
	if _interaction_active and request_id == _active_request_id:
		pin_count_reached.emit(request_id, count)
