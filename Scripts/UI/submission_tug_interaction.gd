extends Control
class_name SubmissionTugInteraction

signal result_selected(request_id: int, outcome: int, timed_out: bool, marker: float, elapsed: float)
signal damage_tick(request_id: int, marker: float)
signal struggle_state_changed(request_id: int, state: StringName)

const MAX_TAPS_PER_SECOND := 8
const MIN_TAP_IMPULSE := 0.65
const MAX_TAP_IMPULSE := 1.15
const AI_PULSE_SECONDS := 0.2
const DAMAGE_TICK_SECONDS := 1.0
const DEFAULT_STALL_FAILSAFE_SECONDS := 30.0
const STALL_WINDOW_SECONDS := 10.0
const STALL_MOVEMENT_THRESHOLD := 3.0
const STATE_SAMPLE_SECONDS := 1.0
const STATE_EVENT_COOLDOWN_SECONDS := 2.5

const STATE_ATTACKER_GAINING := &"attacker_gaining"
const STATE_DEFENDER_GAINING := &"defender_gaining"
const STATE_NEAR_ESCAPE := &"near_escape"
const STATE_NEAR_TAP := &"near_tap"

@export_range(1.0, 3.0, 0.05) var submission_resolution_speed_multiplier: float = 1.5

var _request_id: int = 0
var _marker: float = 50.0
var _tap_out_threshold: float = 90.0
var _escape_threshold: float = 10.0
var _elapsed: float = 0.0
var _player_direction: float = 1.0
var _player_score: float = 50.0
var _ai_score: float = 50.0
var _ai_elapsed: float = 0.0
var _damage_elapsed: float = 0.0
var _stall_failsafe_seconds: float = DEFAULT_STALL_FAILSAFE_SECONDS
var _stall_window_elapsed: float = 0.0
var _stall_min_marker: float = 50.0
var _stall_max_marker: float = 50.0
var _last_effective_input_elapsed: float = -1000.0
var _state_sample_elapsed: float = 0.0
var _state_sample_marker: float = 50.0
var _last_state: StringName = &""
var _last_state_elapsed: float = -1000.0
var _near_escape_armed: bool = true
var _near_tap_armed: bool = true
var _active: bool = false
var _resolved: bool = false
var _tap_times: Array[int] = []
var _last_touch_msec: int = -1000
var _pulse_tween: Tween
var _active_resolution_speed_multiplier: float = 1.5

@onready var _title: Label = %InteractionTitle
@onready var _move_name: Label = %SubmissionMoveName
@onready var _role: Label = %PlayerRole
@onready var _prompt: Label = %InteractionPrompt
@onready var _track: Control = %TugTrack
@onready var _marker_node: Control = %TugMarker
@onready var _escape_zone: Control = %EscapeZone
@onready var _tap_zone: Control = %TapZone
@onready var _tap_button: Button = %TapButton


func _ready() -> void:
	_track.resized.connect(_layout_marker)
	visible = false
	set_process(false)


func open_interaction(request: Dictionary) -> void:
	_request_id = int(request.get("request_id", 0))
	_marker = clampf(float(request.get("start_marker", 50.0)), 0.0, 100.0)
	_tap_out_threshold = clampf(float(request.get("tap_out_threshold", 90.0)), 70.0, 98.0)
	_escape_threshold = clampf(float(request.get("escape_threshold", 10.0)), 2.0, 30.0)
	_player_direction = 1.0 if float(request.get("player_direction", 1.0)) >= 0.0 else -1.0
	_player_score = clampf(float(request.get("player_score", 50.0)), 0.0, 100.0)
	_ai_score = clampf(float(request.get("ai_score", 50.0)), 0.0, 100.0)
	_active_resolution_speed_multiplier = clampf(
		float(request.get("resolution_speed_multiplier", submission_resolution_speed_multiplier)),
		1.0,
		3.0,
	)
	_stall_failsafe_seconds = maxf(
		DEFAULT_STALL_FAILSAFE_SECONDS,
		float(request.get("stall_failsafe_seconds", DEFAULT_STALL_FAILSAFE_SECONDS)),
	)
	_title.text = str(request.get("title", "SUBMISSION STRUGGLE"))
	_move_name.text = str(request.get("move_name", "Submission Hold"))
	_role.text = "YOU ARE ATTACKING — PUSH RIGHT" if _player_direction > 0.0 else "YOU ARE DEFENDING — PUSH LEFT"
	_prompt.text = str(
		request.get(
			"prompt",
			"Tap repeatedly to drive the marker toward %s." % ("TAP OUT" if _player_direction > 0.0 else "ESCAPE"),
		)
	)
	_tap_button.text = str(request.get("button_text", "TAP TO APPLY PRESSURE" if _player_direction > 0.0 else "TAP TO ESCAPE"))
	_elapsed = 0.0
	_ai_elapsed = 0.0
	_damage_elapsed = 0.0
	_stall_window_elapsed = 0.0
	_stall_min_marker = _marker
	_stall_max_marker = _marker
	_last_effective_input_elapsed = -1000.0
	_state_sample_elapsed = 0.0
	_state_sample_marker = _marker
	_last_state = &""
	_last_state_elapsed = -1000.0
	_near_escape_armed = true
	_near_tap_armed = true
	_tap_times.clear()
	_active = true
	_resolved = false
	visible = true
	set_process(true)
	_layout_marker()
	_tap_button.grab_focus()


func close_interaction() -> void:
	var should_cancel := _active and not _resolved
	_active = false
	visible = false
	set_process(false)
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	if should_cancel:
		_resolved = true
		result_selected.emit(
			_request_id,
			MatchInteractionModel.CombinedOutcome.BOTCH_OR_SCRAMBLE,
			true,
			_marker,
			_elapsed,
		)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_ai_elapsed += delta
	_damage_elapsed += delta
	_stall_window_elapsed += delta
	_state_sample_elapsed += delta
	while _ai_elapsed >= AI_PULSE_SECONDS:
		_ai_elapsed -= AI_PULSE_SECONDS
		_apply_ai_drift()
	while _damage_elapsed >= DAMAGE_TICK_SECONDS:
		_damage_elapsed -= DAMAGE_TICK_SECONDS
		damage_tick.emit(_request_id, _marker)
	_marker = clampf(_marker, 0.0, 100.0)
	_stall_min_marker = minf(_stall_min_marker, _marker)
	_stall_max_marker = maxf(_stall_max_marker, _marker)
	_layout_marker()
	_update_struggle_state()
	if _marker >= _tap_out_threshold:
		_finish(MatchInteractionModel.CombinedOutcome.TAP_OUT, false)
	elif _marker <= _escape_threshold:
		_finish(MatchInteractionModel.CombinedOutcome.SUBMISSION_ESCAPE, false)
	elif _stall_window_elapsed >= STALL_WINDOW_SECONDS:
		var marker_range := _stall_max_marker - _stall_min_marker
		var no_recent_input := _elapsed - _last_effective_input_elapsed >= STALL_WINDOW_SECONDS
		if _elapsed >= _stall_failsafe_seconds and marker_range < STALL_MOVEMENT_THRESHOLD and no_recent_input:
			_finish(MatchInteractionModel.CombinedOutcome.BOTCH_OR_SCRAMBLE, true)
		else:
			_stall_window_elapsed = 0.0
			_stall_min_marker = _marker
			_stall_max_marker = _marker


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if _is_submission_tap_key(event):
		_register_tap()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		_last_touch_msec = Time.get_ticks_msec()
		_register_tap()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec() - _last_touch_msec > 250:
			_register_tap()
			get_viewport().set_input_as_handled()


func _is_submission_tap_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	return (
		key_event.keycode == KEY_SPACE
		or key_event.physical_keycode == KEY_SPACE
		or key_event.is_action_pressed("ui_accept")
	)


func _register_tap() -> void:
	if not _active or _resolved:
		return
	var now := Time.get_ticks_msec()
	while not _tap_times.is_empty() and now - _tap_times.front() >= 1000:
		_tap_times.pop_front()
	if _tap_times.size() >= MAX_TAPS_PER_SECOND:
		return
	_tap_times.append(now)
	_last_effective_input_elapsed = _elapsed
	var impulse := (
		lerpf(MIN_TAP_IMPULSE, MAX_TAP_IMPULSE, _player_score / 100.0)
		* _active_resolution_speed_multiplier
	)
	_marker = clampf(_marker + _player_direction * impulse, 0.0, 100.0)
	_pulse_player_side()
	_layout_marker()


func _apply_ai_drift() -> void:
	var ai_objective_direction := -_player_direction
	var score_advantage := _ai_score - _player_score
	# At equal scores, one AI pulse now has the same force as one player press.
	# The AI pulses five times per second while the player may reach eight presses,
	# so active input can win an even struggle without each press overpowering AI.
	var impulse := lerpf(MIN_TAP_IMPULSE, MAX_TAP_IMPULSE, _ai_score / 100.0)
	if score_advantage > 5.0:
		impulse = clampf(
			impulse + score_advantage * 0.012,
			MIN_TAP_IMPULSE,
			1.8,
		)
	elif score_advantage < -5.0:
		# Superior player condition reduces the AI's opposing force, but never
		# creates free movement toward the player's objective. A player must press
		# at least once—and keep fighting—to earn either a tap-out or an escape.
		impulse = clampf(impulse - absf(score_advantage) * 0.012, 0.15, 1.2)
	_marker += ai_objective_direction * impulse * _active_resolution_speed_multiplier


func _update_struggle_state() -> void:
	if _marker <= _escape_threshold + 12.0 and _near_escape_armed:
		_emit_state(STATE_NEAR_ESCAPE)
		_near_escape_armed = false
	elif _marker >= _escape_threshold + 18.0:
		_near_escape_armed = true
	if _marker >= _tap_out_threshold - 12.0 and _near_tap_armed:
		_emit_state(STATE_NEAR_TAP)
		_near_tap_armed = false
	elif _marker <= _tap_out_threshold - 18.0:
		_near_tap_armed = true
	if _state_sample_elapsed < STATE_SAMPLE_SECONDS:
		return
	var movement := _marker - _state_sample_marker
	_state_sample_elapsed = 0.0
	_state_sample_marker = _marker
	if absf(movement) < 2.0:
		return
	_emit_state(STATE_ATTACKER_GAINING if movement > 0.0 else STATE_DEFENDER_GAINING)


func _emit_state(state: StringName) -> void:
	if state == _last_state and _elapsed - _last_state_elapsed < STATE_EVENT_COOLDOWN_SECONDS:
		return
	if _elapsed - _last_state_elapsed < STATE_EVENT_COOLDOWN_SECONDS:
		return
	_last_state = state
	_last_state_elapsed = _elapsed
	struggle_state_changed.emit(_request_id, state)


func _pulse_player_side() -> void:
	var side: Control = _tap_zone if _player_direction > 0.0 else _escape_zone
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	side.self_modulate = Color(1.45, 1.45, 1.45, 1.0)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(side, "self_modulate", Color.WHITE, 0.18)


func _finish(outcome: int, timed_out: bool) -> void:
	if not _active or _resolved:
		return
	_resolved = true
	_active = false
	set_process(false)
	result_selected.emit(_request_id, outcome, timed_out, _marker, _elapsed)


func _layout_marker() -> void:
	if not is_instance_valid(_track):
		return
	var travel := maxf(0.0, _track.size.x - _marker_node.size.x)
	_marker_node.position = Vector2(travel * (_marker / 100.0), 0.0)
	_marker_node.size.y = _track.size.y
	_escape_zone.position = Vector2.ZERO
	_escape_zone.size = Vector2(_track.size.x * (_escape_threshold / 100.0), _track.size.y)
	_tap_zone.position = Vector2(_track.size.x * (_tap_out_threshold / 100.0), 0.0)
	_tap_zone.size = Vector2(_track.size.x * ((100.0 - _tap_out_threshold) / 100.0), _track.size.y)
