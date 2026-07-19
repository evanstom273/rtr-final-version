extends Control
class_name SimpleMatchUI

signal match_presentation_state_changed(snapshots: Array, context: Dictionary)
signal match_presentation_event(event: Dictionary)

enum Side { NONE, PLAYER, AI }
enum ControlState { PLAYER_CONTROL, AI_CONTROL, NEUTRAL, MATCH_ENDED }
enum ActionResult {
	NONE,
	CLEAN_SUCCESS,
	PARTIAL_DEFENCE,
	REVERSAL,
	HIGH_RISK_CRASH,
	SETUP_SUCCESS,
	KICKOUT,
	SUBMISSION_ESCAPE,
	TAP_OUT,
	CONTESTED_STRUGGLE,
	BOTCH_OR_SCRAMBLE,
	LABOURED_SUCCESS,
}
enum FinishType {
	NONE,
	PINFALL,
	SUBMISSION,
	COUNT_OUT,
	DISQUALIFICATION,
	DOUBLE_COUNT_OUT,
	DOUBLE_DISQUALIFICATION,
	DRAW,
	NO_CONTEST,
}

const ROSTER_DIRECTORY := "res://Wrestlers"
const AI_DELAY_SECONDS := 0.6
const MATCH_RESULT_REVEAL_DELAY_SECONDS := 0.65
const GROUNDED_ATTACKER_RECOVERY_CHANCE := 0.80
const TAUNT_COOLDOWN_SECONDS := 120
const INTERACTION_CANCELLED := -100
const COUNT_OUT_INTERVAL_SECONDS := 30
const STEEL_CHAIR = preload("res://Weapons/steel_chair.tres")

@export var player_wrestler: WrestlerResource
@export var ai_wrestler: WrestlerResource
@export_range(0.05, 2.0, 0.05) var live_refresh_interval: float = 0.2
@export_range(1.0, 3.0, 0.05) var submission_resolution_speed_multiplier: float = 1.5

var player_side_state := MatchSideState.new()
var ai_side_state := MatchSideState.new()
var _ai_decision_engine := MatchAIDecisionEngine.new()
var current_controller: int = ControlState.PLAYER_CONTROL
var current_attacker_side: int = Side.PLAYER
var current_defender_side: int = Side.AI
var match_ended: bool = false
var winner_side: int = Side.NONE
var loser_side: int = Side.NONE
var finish_type: int = FinishType.NONE
var finish_move: MoveResource
var finish_reason: String = ""
var finish_action: String = ""
var final_time: int = 0
var selected_move: MoveResource
var selected_move_target_resolution: Dictionary = {}
var last_move_used: MoveResource
var last_action_result: int = ActionResult.NONE
var match_log_entries: Array[String] = []
var is_resolving_action: bool = false
var contest_prompt_active: bool = false
var pin_sequence_active: bool = false
var submission_sequence_active: bool = false
var _contest_timing_bar: ContestTimingBar

var _roster: Array[WrestlerResource] = []
var _refresh_elapsed: float = 0.0
var _match_log_scroll_generation: int = 0
var _match_time_seconds: int = 0
var _turn_generation: int = 0
var _scheduled_ai_generation: int = -1
var _scheduled_neutral_generation: int = -1
var _match_initialized: bool = false
var _flow_recovery_active: bool = false
var _last_dead_end_signature: String = ""
var _dead_end_repetitions: int = 0
var _watchdog_recovery_pending: bool = false
var _latest_match_report: Dictionary = {}
var _match_setup_metadata: Dictionary = {}
var _match_rules := MatchRules.new()
var _dropped_weapon: WeaponResource
var _dropped_weapon_area: int = WrestlerResource.Area.OUTSIDE
var _dropped_weapon_uses_remaining: int = 0
var _referee_count_active: bool = false
var _referee_count_value: int = 0
var _referee_count_elapsed: int = 0
var _referee_count_pending_resolution: bool = false
var _referee_count_starts: int = 0
var _referee_count_highest: int = 0
var _referee_count_resets: int = 0
var _last_count_commentary_value: int = 0
var _count_outside_presence: Dictionary = {}
var _recent_matchups: Array[PackedStringArray] = []
var _player_setup_intent: StringName = &""
var _setup_action_cache: Dictionary = {}
var _active_pin_context: Dictionary = {}
var _recent_reversal_side: int = Side.NONE
var _active_submission_attacker_side: int = Side.NONE
var _active_submission_defender_side: int = Side.NONE
var _active_submission_move: MoveResource
var _active_submission_target_resolution: Dictionary = {}
var _neutral_recovery_favored_side: int = Side.NONE
var _interaction_player_position: int = WrestlerResource.Position.NONE
var _interaction_ai_position: int = WrestlerResource.Position.NONE
var _interaction_player_state_key: String = ""
var _interaction_ai_state_key: String = ""
var _interaction_controller: int = ControlState.NEUTRAL
var _interaction_player_wrestler: WrestlerResource
var _interaction_ai_wrestler: WrestlerResource
var _move_button_default_style: StyleBox
var _move_button_available_style: StyleBoxFlat
var _move_button_default_font_color: Color
var _chair_shot_move: MoveResource

@onready var _player_selector: OptionButton = %PlayerSelector
@onready var _ai_selector: OptionButton = %AISelector
@onready var _selection_status: Label = %SelectionStatus
@onready var _player_card: WrestlerMatchCard = %PlayerCard
@onready var _ai_card: WrestlerMatchCard = %AICard
@onready var _safe_area: MarginContainer = %SafeArea
@onready var _page_margin: MarginContainer = %PageMargin
@onready var _selector_row: BoxContainer = %SelectorRow
@onready var _cards_row: BoxContainer = %CardsRow
@onready var _center_stack: VBoxContainer = %VBoxContainer
@onready var _center_column: PanelContainer = %CenterColumn
@onready var _ring_view: MatchRingView = %RingView
@onready var _portrait_rotate_overlay: ColorRect = %PortraitRotateOverlay
@onready var _versus: Label = %Versus
@onready var _player_label: Label = %PlayerLabel
@onready var _ai_label: Label = %AILabel
@onready var _player_selected_name: Label = %PlayerSelectedName
@onready var _ai_selected_name: Label = %AISelectedName
@onready var _vs_banner: Label = %VSBanner
@onready var _attacker_indicator: Label = %AttackerIndicator
@onready var _match_clock: Label = %MatchClock
@onready var _referee_count_badge: Label = %RefereeCountBadge
@onready var _result_banner: Label = %ResultBanner
@onready var _view_report_button: Button = %ViewReportButton
@onready var _match_log_scroll: ScrollContainer = %MatchLogScroll
@onready var _match_log_list: VBoxContainer = %MatchLogList
@onready var _move_selector_button: Button = %MoveSelectorButton
@onready var _setup_actions_button: Button = %SetupActionsButton
@onready var _execute_button: Button = %ExecuteButton
@onready var _pin_button: Button = %PinButton
@onready var _new_match_button: Button = %NewMatchButton
@onready var _moves_radial_menu: MovesRadialMenu = %MovesRadialMenu
@onready var _setup_actions_menu: SetupActionsMenu = %SetupActionsMenu
@onready var _interaction_overlay: MatchInteractionOverlay = %MatchInteractionOverlay
@onready var _match_result_popup = %MatchResultPopup
@onready var _match_report_popup: MatchReportPopup = %MatchReportPopup
@onready var _match_setup_popup = %MatchSetupPopup


func _ready() -> void:
	_chair_shot_move = _create_runtime_chair_shot_move()
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	match_presentation_state_changed.connect(_ring_view.apply_state_snapshot)
	match_presentation_event.connect(_ring_view.present_event)
	var match_log_scroll_bar := _match_log_scroll.get_v_scroll_bar()
	match_log_scroll_bar.modulate.a = 0.0
	match_log_scroll_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_match_log_scrolling()
	_player_selector.item_selected.connect(_on_player_selected)
	_ai_selector.item_selected.connect(_on_ai_selected)
	_move_selector_button.pressed.connect(_on_move_selector_pressed)
	_setup_actions_button.pressed.connect(_on_setup_actions_pressed)
	_execute_button.pressed.connect(_on_execute_pressed)
	_pin_button.pressed.connect(_on_pin_pressed)
	_new_match_button.pressed.connect(_on_new_match_requested)
	_view_report_button.pressed.connect(_open_latest_match_report)
	_moves_radial_menu.move_selected.connect(_on_move_selected)
	_moves_radial_menu.target_focus_changed.connect(_on_player_target_focus_changed)
	_ai_card.target_focus_requested.connect(_on_player_target_focus_changed)
	_setup_actions_menu.action_selected.connect(_on_setup_action_selected)
	_interaction_overlay.submission_damage_tick.connect(_on_submission_damage_tick)
	_interaction_overlay.submission_state_changed.connect(_on_submission_state_changed)
	_match_result_popup.view_report_requested.connect(_on_result_view_report_requested)
	_match_result_popup.new_match_requested.connect(_on_new_match_requested)
	_match_result_popup.closed.connect(_on_result_popup_closed)
	_match_report_popup.return_requested.connect(_on_match_report_returned)
	_match_report_popup.new_match_requested.connect(_on_new_match_requested)
	_match_setup_popup.match_requested.connect(_on_match_setup_requested)
	_match_setup_popup.cancelled.connect(_on_match_setup_cancelled)
	_cache_move_button_styles()
	_load_roster()
	_resolve_initial_assignments()
	_populate_selectors()
	_open_initial_match_setup.call_deferred()


func _configure_match_log_scrolling() -> void:
	# Wait until the responsive containers have their constrained final height.
	# Enabling automatic scrolling before that layout pass lets the log claim its
	# full content height and leaves no actual scroll range.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_match_log_scroll):
		# Keep the scrollbar allocation constant from the first entry onward. An
		# AUTO scrollbar appearing later changes the log width, re-wraps every row,
		# and can visibly move all three match columns.
		_match_log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS


func _cache_move_button_styles() -> void:
	var normal_style := _move_selector_button.get_theme_stylebox("normal")
	if normal_style != null:
		_move_button_default_style = normal_style.duplicate() as StyleBox
		_move_button_available_style = normal_style.duplicate() as StyleBoxFlat
	if _move_button_available_style != null:
		_move_button_available_style.bg_color = Color(0.13, 0.12, 0.055, 1.0)
		_move_button_available_style.border_color = Color(0.95, 0.78, 0.22, 1.0)
		_move_button_available_style.border_width_left = 2
		_move_button_available_style.border_width_top = 2
		_move_button_available_style.border_width_right = 2
		_move_button_available_style.border_width_bottom = 2
	_move_button_default_font_color = _move_selector_button.get_theme_color("font_color")


func _exit_tree() -> void:
	_turn_generation += 1
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, _effective_size: Vector2) -> void:
	var portrait_phone := mode == ResponsiveUI.LayoutMode.PHONE and _effective_size.y > _effective_size.x
	_selector_row.vertical = portrait_phone
	_cards_row.vertical = portrait_phone
	_portrait_rotate_overlay.visible = portrait_phone
	_center_column.size_flags_stretch_ratio = float(ResponsiveUI.choose(2.35, 2.12, 1.85))
	_ring_view.size_flags_stretch_ratio = 1.0
	_center_stack.add_theme_constant_override("separation", int(ResponsiveUI.choose(7, 9, 10)))
	var page_margin := ResponsiveUI.get_page_margin()
	var vertical_margin := int(ResponsiveUI.choose(8, 12, 14))
	_page_margin.add_theme_constant_override("margin_left", page_margin)
	_page_margin.add_theme_constant_override("margin_top", vertical_margin)
	_page_margin.add_theme_constant_override("margin_right", page_margin)
	_page_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	_selector_row.add_theme_constant_override("separation", int(ResponsiveUI.choose(8, 12, 16)))
	_cards_row.add_theme_constant_override("separation", int(ResponsiveUI.choose(10, 12, 12)))
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait_phone else HORIZONTAL_ALIGNMENT_LEFT
	_ai_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait_phone else HORIZONTAL_ALIGNMENT_RIGHT
	_versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_versus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	if _interaction_overlay.is_interaction_active() and _interaction_context_changed():
		_interaction_overlay.close_interaction(true)
		contest_prompt_active = false
	_refresh_elapsed += delta
	if _refresh_elapsed < live_refresh_interval:
		return
	_refresh_elapsed = 0.0
	refresh_match_ui()
	if (
		_match_initialized
		and not match_ended
		and not is_resolving_action
		and not contest_prompt_active
		and not pin_sequence_active
		and not submission_sequence_active
		and (
			(current_controller == ControlState.AI_CONTROL and _scheduled_ai_generation != _turn_generation)
			or (current_controller == ControlState.NEUTRAL and _scheduled_neutral_generation != _turn_generation)
		)
	):
		ensure_match_can_continue("missing scheduled continuation")


func start_match() -> void:
	_turn_generation += 1
	_scheduled_ai_generation = -1
	_scheduled_neutral_generation = -1
	_match_initialized = false
	_last_dead_end_signature = ""
	_dead_end_repetitions = 0
	_watchdog_recovery_pending = false
	match_ended = false
	winner_side = Side.NONE
	loser_side = Side.NONE
	finish_type = FinishType.NONE
	finish_move = null
	finish_reason = ""
	finish_action = ""
	final_time = 0
	last_move_used = null
	last_action_result = ActionResult.NONE
	_match_time_seconds = 0
	_dropped_weapon = null
	_dropped_weapon_area = WrestlerResource.Area.OUTSIDE
	_dropped_weapon_uses_remaining = 0
	_reset_referee_count_runtime()
	is_resolving_action = false
	contest_prompt_active = false
	pin_sequence_active = false
	submission_sequence_active = false
	_latest_match_report.clear()
	match_log_entries.clear()
	player_side_state.initialize(player_wrestler)
	ai_side_state.initialize(ai_wrestler)
	_ai_decision_engine.reset()
	_player_setup_intent = &""
	_setup_action_cache.clear()
	_active_pin_context.clear()
	_recent_reversal_side = Side.NONE
	_active_submission_attacker_side = Side.NONE
	_active_submission_defender_side = Side.NONE
	_active_submission_move = null
	_active_submission_target_resolution.clear()
	_neutral_recovery_favored_side = Side.NONE
	_clear_selected_move()
	_moves_radial_menu.set_target_focus(MoveResource.MoveTargetParts.NONE)
	_clear_match_log()
	_moves_radial_menu.close()
	_setup_actions_menu.close()
	_interaction_overlay.close_interaction(true)
	_result_banner.visible = false
	_result_banner.text = ""
	_view_report_button.visible = false
	_new_match_button.visible = false
	_match_result_popup.close_result()
	_match_report_popup.close_report()
	_match_setup_popup.close_setup()
	_ring_view.reset_match()
	# Assign first, ring the bell, then arm the first continuation. This prevents
	# an AI deferred callback from resolving behind the mandatory setup popup.
	var opening_controller := (
		ControlState.PLAYER_CONTROL
		if randf() < 0.5
		else ControlState.AI_CONTROL
	)
	_set_controller(opening_controller, false)
	refresh_match_ui()
	if player_wrestler != null and ai_wrestler != null:
		add_match_log_entry(
			"The bell rings. %s and %s square up in the centre of the ring." % [
				_wrestler_name(player_wrestler),
				_wrestler_name(ai_wrestler),
			],
		)
		_emit_ring_state({"reason": "opening bell", "immediate": true})
		_emit_ring_event(&"match_started", current_attacker_side, current_defender_side)
		_match_initialized = true
		_schedule_current_turn()


func set_player_wrestler(value: WrestlerResource) -> void:
	if _same_wrestler(value, ai_wrestler):
		_selection_status.text = "Player and AI must be different wrestlers."
		return
	player_wrestler = value
	_sync_selector_to_resource(_player_selector, player_wrestler)
	_update_disabled_options()
	_selection_status.text = ""
	if is_node_ready():
		start_match()


func set_ai_wrestler(value: WrestlerResource) -> void:
	if _same_wrestler(value, player_wrestler):
		_selection_status.text = "Player and AI must be different wrestlers."
		return
	ai_wrestler = value
	_sync_selector_to_resource(_ai_selector, ai_wrestler)
	_update_disabled_options()
	_selection_status.text = ""
	if is_node_ready():
		start_match()


func refresh_cards() -> void:
	refresh_match_ui()


func refresh_match_ui() -> void:
	if not is_node_ready():
		return
	var repaired_position := _repair_invalid_positions()
	player_side_state.sync_to_resource()
	ai_side_state.sync_to_resource()
	_player_card.set_wrestler(player_wrestler)
	_ai_card.set_wrestler(ai_wrestler)
	_player_card.set_match_state(player_side_state.snapshot())
	_ai_card.set_match_state(ai_side_state.snapshot())
	_player_card.set_target_focus(ai_side_state.target_focus_body_part)
	_player_card.set_targeting_enabled(false)
	_ai_card.set_target_focus(player_side_state.target_focus_body_part)
	_ai_card.set_targeting_enabled(_player_targeting_allowed())
	_player_selected_name.text = _wrestler_name(player_wrestler)
	_ai_selected_name.text = _wrestler_name(ai_wrestler)
	_clear_selected_move_if_invalid()
	_update_match_header()
	_update_action_availability()
	_moves_radial_menu.refresh_match_state(
		player_wrestler,
		ai_wrestler,
		Callable(self, "_player_move_menu_filter"),
		Callable(self, "_player_move_unavailable_reason"),
		ai_side_state,
	)
	_emit_ring_state({"reason": "live refresh"})
	if repaired_position and _match_initialized:
		ensure_match_can_continue.call_deferred("invalid-position repair")


func _emit_ring_state(context: Dictionary = {}) -> void:
	if not is_node_ready() or player_wrestler == null or ai_wrestler == null:
		return
	var snapshots: Array = [
		_ring_snapshot_for_side(Side.PLAYER),
		_ring_snapshot_for_side(Side.AI),
	]
	match_presentation_state_changed.emit(snapshots, context.duplicate(true))


func _ring_snapshot_for_side(side: int) -> Dictionary:
	var state := _state_for_side(side)
	if state == null or state.wrestler == null:
		return {}
	var opponent_side := _opponent_side(side)
	return {
		"id": _ring_participant_id(side),
		"display_name": _wrestler_name(state.wrestler),
		"side_label": "P1" if side == Side.PLAYER else "AI",
		"is_player": side == Side.PLAYER,
		"is_active": not match_ended or side in [winner_side, loser_side],
		"has_control": current_attacker_side == side and not match_ended,
		"is_targeted": current_defender_side == side and is_resolving_action,
		"target_id": _ring_participant_id(opponent_side),
		"position": state.current_position,
		"orientation": state.current_orientation,
		"area": state.current_area,
		"motion_state": state.current_motion_state,
		"previous_position": state.last_position,
		"previous_orientation": state.last_orientation,
		"previous_area": state.last_area,
		"previous_motion_state": state.last_motion_state,
		"held_weapon_name": state.held_weapon.display_name if state.held_weapon != null else "",
		"held_weapon_uses_remaining": state.held_weapon_uses_remaining if state.held_weapon != null else 0,
	}


func _ring_participant_id(side: int) -> String:
	var state := _state_for_side(side)
	if state == null or state.wrestler == null:
		return ""
	if state.wrestler.wrestler_id != 0:
		return "wrestler_%d" % state.wrestler.wrestler_id
	if not state.wrestler.resource_path.is_empty():
		return state.wrestler.resource_path.get_file().get_basename()
	return _wrestler_name(state.wrestler).to_snake_case()


func _emit_ring_event(
	kind: StringName,
	actor_side: int = Side.NONE,
	target_side: int = Side.NONE,
	extra: Dictionary = {},
) -> void:
	if not is_node_ready():
		return
	var event := extra.duplicate(true)
	event["kind"] = kind
	event["actor_id"] = _ring_participant_id(actor_side)
	event["target_id"] = _ring_participant_id(target_side)
	match_presentation_event.emit(event)


func _ring_action_result_name(result: int) -> StringName:
	match result:
		ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS:
			return &"impact"
		ActionResult.REVERSAL:
			return &"reversal"
		ActionResult.HIGH_RISK_CRASH:
			return &"crash"
		ActionResult.BOTCH_OR_SCRAMBLE:
			return &"botch"
	return &"contest"


func set_current_attacker(value: WrestlerResource) -> void:
	if value == player_wrestler:
		_set_controller(ControlState.PLAYER_CONTROL)
	elif value == ai_wrestler:
		_set_controller(ControlState.AI_CONTROL)
	else:
		_set_controller(ControlState.NEUTRAL)


func advance_match_clock(increments: int = 1) -> void:
	var action_seconds := MatchRules.normalized_action_clock_seconds(_match_rules.action_clock_seconds)
	var elapsed_seconds := maxi(0, increments) * action_seconds
	_match_time_seconds += elapsed_seconds
	_accumulate_referee_count(elapsed_seconds)
	var escalation := MatchInteractionModel.build_late_match_profile(_match_time_seconds)
	var pressure := float(escalation.get("finish_pressure", 0.0))
	for state in [player_side_state, ai_side_state]:
		if state != null:
			state.late_escalation_total += pressure
			state.late_escalation_samples += 1
	_update_match_header()


func _reset_referee_count_runtime() -> void:
	_referee_count_active = false
	_referee_count_value = 0
	_referee_count_elapsed = 0
	_referee_count_pending_resolution = false
	_referee_count_starts = 0
	_referee_count_highest = 0
	_referee_count_resets = 0
	_last_count_commentary_value = 0
	_count_outside_presence = {Side.PLAYER: false, Side.AI: false}
	_update_referee_count_presentation()


func _accumulate_referee_count(elapsed_seconds: int) -> void:
	if match_ended or not _match_initialized or not _match_rules.count_outs_enabled:
		return
	var outside_sides := _outside_sides()
	if outside_sides.is_empty():
		return
	if not _referee_count_active:
		_start_referee_count()
	for side in outside_sides:
		var state := _state_for_side(side)
		if state != null:
			state.outside_seconds += elapsed_seconds
	_referee_count_elapsed += elapsed_seconds
	while _referee_count_elapsed >= COUNT_OUT_INTERVAL_SECONDS and _referee_count_value < _match_rules.count_out_limit:
		_referee_count_elapsed -= COUNT_OUT_INTERVAL_SECONDS
		_referee_count_value += 1
		_referee_count_highest = maxi(_referee_count_highest, _referee_count_value)
		_announce_referee_count(_referee_count_value)
	if _referee_count_value >= _match_rules.count_out_limit:
		_referee_count_pending_resolution = true
	_update_referee_count_presentation()


func _settle_referee_count(context: String = "") -> void:
	if match_ended:
		return
	if not _match_rules.count_outs_enabled:
		_clear_active_referee_count(false)
		return
	var outside_sides := _outside_sides()
	for side in [Side.PLAYER, Side.AI]:
		var was_outside := bool(_count_outside_presence.get(side, false))
		var is_outside: bool = side in outside_sides
		if was_outside and not is_outside and _referee_count_active:
			var state := _state_for_side(side)
			if _referee_count_value >= maxi(1, _match_rules.count_out_limit - 2):
				if state != null:
					state.late_count_returns += 1
				add_match_log_entry("%s dives back inside at %d!" % [_side_name(side), _referee_count_value], Color(0.95, 0.78, 0.22, 1.0))
			else:
				add_match_log_entry("%s gets back inside the ring." % _side_name(side))
		_count_outside_presence[side] = is_outside
	if outside_sides.is_empty():
		if _referee_count_active:
			_clear_active_referee_count(true)
		return
	if not _referee_count_active:
		_start_referee_count()
	if not _referee_count_pending_resolution:
		return
	_referee_count_pending_resolution = false
	if outside_sides.size() >= 2:
		add_match_log_entry("Neither wrestler made it back — the referee calls for the bell.", Color(0.95, 0.78, 0.22, 1.0))
		end_match(Side.NONE, Side.NONE, FinishType.DOUBLE_COUNT_OUT, null, "Both wrestlers failed to answer the count.", "Referee count %d" % _referee_count_value)
		return
	var counted_out_side: int = int(outside_sides[0])
	var winning_side := _opponent_side(counted_out_side)
	add_match_log_entry("That's %d! %s has been counted out." % [_match_rules.count_out_limit, _side_name(counted_out_side)], Color(0.95, 0.78, 0.22, 1.0))
	end_match(winning_side, counted_out_side, FinishType.COUNT_OUT, null, "%s failed to return before the referee's count." % _side_name(counted_out_side), "Referee count %d" % _referee_count_value)


func _start_referee_count() -> void:
	_referee_count_active = true
	_referee_count_value = 0
	_referee_count_elapsed = 0
	_referee_count_pending_resolution = false
	_referee_count_starts += 1
	_last_count_commentary_value = 0
	for side in [Side.PLAYER, Side.AI]:
		_count_outside_presence[side] = _side_is_outside(side)
	add_match_log_entry("The referee begins the count.", Color(0.95, 0.78, 0.22, 1.0))
	_emit_ring_event(&"count_started", Side.NONE, Side.NONE, {"count": 0, "limit": _match_rules.count_out_limit})
	_update_referee_count_presentation()


func _announce_referee_count(value: int) -> void:
	if value <= _last_count_commentary_value:
		return
	_last_count_commentary_value = value
	var words := ["", "ONE!", "TWO!", "THREE!", "FOUR!", "FIVE!", "SIX!", "SEVEN!", "EIGHT!", "NINE!", "TEN!"]
	var count_text: String = str(words[value]) if value < words.size() else "%d!" % value
	add_match_log_entry(count_text, Color(0.95, 0.78, 0.22, 1.0))
	if value == _match_rules.count_out_limit - 1:
		add_match_log_entry("They are one count away from losing the match on the floor.", Color(1.0, 0.58, 0.42, 1.0))
	_emit_ring_event(&"count_updated", Side.NONE, Side.NONE, {"count": value, "limit": _match_rules.count_out_limit})


func _clear_active_referee_count(record_reset: bool) -> void:
	var had_count := _referee_count_active
	if had_count and record_reset:
		_referee_count_resets += 1
		add_match_log_entry("The count is broken; both wrestlers are safely inside.")
	_referee_count_active = false
	_referee_count_value = 0
	_referee_count_elapsed = 0
	_referee_count_pending_resolution = false
	_last_count_commentary_value = 0
	for side in [Side.PLAYER, Side.AI]:
		_count_outside_presence[side] = _side_is_outside(side)
	if had_count:
		_emit_ring_event(&"count_reset")
	_update_referee_count_presentation()


func _outside_sides() -> Array[int]:
	var sides: Array[int] = []
	for side in [Side.PLAYER, Side.AI]:
		if _side_is_outside(side):
			sides.append(side)
	return sides


func _side_is_outside(side: int) -> bool:
	var state := _state_for_side(side)
	return state != null and _match_rules.is_outside_area(state.current_area)


func _update_referee_count_presentation() -> void:
	if not is_node_ready() or not is_instance_valid(_referee_count_badge):
		return
	_referee_count_badge.visible = _referee_count_active and not match_ended
	_referee_count_badge.text = "COUNT: %d / %d" % [_referee_count_value, _match_rules.count_out_limit]


func add_match_log_entry(
	message: String,
	color: Color = Color(0.84, 0.87, 0.92, 1.0),
) -> void:
	if not is_node_ready() or message.strip_edges().is_empty():
		return
	match_log_entries.append("%s — %s" % [_formatted_match_clock(), message])
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = 1.0
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 7)
	var timestamp := Label.new()
	timestamp.custom_minimum_size = Vector2(48, 0)
	timestamp.text = _formatted_match_clock()
	timestamp.add_theme_color_override("font_color", Color(0.95, 0.78, 0.22, 1.0))
	var divider := Label.new()
	divider.text = "—"
	divider.add_theme_color_override("font_color", Color(0.48, 0.52, 0.6, 1.0))
	var entry := Label.new()
	entry.custom_minimum_size.x = 1.0
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.text = _soft_wrap_log_text(message)
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_theme_color_override("font_color", color)
	row.add_child(timestamp)
	row.add_child(divider)
	row.add_child(entry)
	_match_log_list.add_child(row)
	_scroll_match_log_to_latest(row)


func _soft_wrap_log_text(message: String) -> String:
	# Long move names and compound words must never increase the centre column's
	# minimum width and squeeze the wrestler cards. Zero-width break points keep
	# the displayed wording unchanged while allowing stable wrapping.
	return message.replace("-", "-\u200b").replace("/", "/\u200b").replace("_", "_\u200b")


func _scroll_match_log_to_latest(latest_row: Control) -> void:
	_match_log_scroll_generation += 1
	var request_generation := _match_log_scroll_generation
	# Wrapped labels and VBox containers can need more than one layout pass before
	# the ScrollContainer knows its final range.
	await get_tree().process_frame
	await get_tree().process_frame
	if request_generation != _match_log_scroll_generation:
		return
	if not is_instance_valid(_match_log_scroll) or not is_instance_valid(latest_row):
		return
	_match_log_scroll.ensure_control_visible(latest_row)
	_match_log_scroll.scroll_vertical = ceili(_match_log_scroll.get_v_scroll_bar().max_value)
	# Re-apply after ensure_control_visible has completed its own deferred layout.
	await get_tree().process_frame
	if request_generation == _match_log_scroll_generation and is_instance_valid(_match_log_scroll):
		_match_log_scroll.scroll_vertical = ceili(_match_log_scroll.get_v_scroll_bar().max_value)


func get_valid_moves(side: int) -> Array[MoveResource]:
	var valid: Array[MoveResource] = []
	var state := _state_for_side(side)
	if state == null or state.wrestler == null:
		return valid
	for move in state.all_assigned_moves():
		if move != null and _move_is_valid(side, move):
			valid.append(move)
	if side == Side.PLAYER and _chair_shot_move != null and _move_is_valid(side, _chair_shot_move):
		valid.append(_chair_shot_move)
	return valid


func get_valid_setup_actions(side: int) -> Array[StringName]:
	var actor := _state_for_side(side)
	var target := _state_for_side(_opponent_side(side))
	if actor == null or target == null or actor.wrestler == null:
		return []
	var cache_key := "%d|%s|%s|%d|%d|%d|%d|%d|%s|%s|%d|%d" % [
		side,
		_match_state_cache_key(actor),
		_match_state_cache_key(target),
		_match_time_seconds,
		roundi(actor.momentum),
		actor.taunt_cooldown_until_seconds,
		1 if actor.signature_ready else 0,
		actor.finisher_stock,
		String(actor.held_weapon.weapon_id) if actor.held_weapon != null else "none",
		String(target.held_weapon.weapon_id) if target.held_weapon != null else "none",
		1 if _match_rules.disqualifications_enabled else 0,
		_referee_count_value,
	]
	if _setup_action_cache.has(cache_key):
		var cached: Array[StringName] = []
		for cached_action in _setup_action_cache[cache_key]:
			cached.append(StringName(cached_action))
		return cached
	var actions := MatchSetupStateRules.get_candidate_actions(actor, target)
	var paths := MatchSetupStateRules.find_followup_paths(
		actor.all_assigned_moves(),
		actor.snapshot(),
		target.snapshot(),
		2,
	)
	var first_path_actions: Array[StringName] = []
	for path_data in paths:
		var move := path_data.get("move") as MoveResource
		if move == null or not _move_is_unlocked_for_state(actor, move):
			continue
		var path: Array = path_data.get("actions", [])
		if not path.is_empty():
			var first_action := StringName(path[0])
			if first_action not in first_path_actions:
				first_path_actions.append(first_action)
	var usable_actions: Array[StringName] = []
	for action_id in actions:
		if action_id == SetupActionsMenu.TAUNT and _match_time_seconds < actor.taunt_cooldown_until_seconds:
			continue
		if (
			MatchSetupStateRules.is_recovery(action_id)
			or action_id == SetupActionsMenu.TAUNT
			or (side == Side.PLAYER and action_id == SetupActionsMenu.EXIT_RING)
			or action_id in first_path_actions
		):
			usable_actions.append(action_id)
	_append_rule_actions(side, actor, target, usable_actions)
	# A non-empty raw list can become empty after follow-up filtering. Ask the
	# setup component for its authored reset fallback at that point as well.
	if usable_actions.is_empty():
		usable_actions.append(SetupActionsMenu.RESET_STANCE)
	if _setup_action_cache.size() >= 64:
		_setup_action_cache.clear()
	_setup_action_cache[cache_key] = usable_actions.duplicate()
	return usable_actions


func _append_rule_actions(
	side: int,
	actor: MatchSideState,
	target: MatchSideState,
	actions: Array[StringName],
) -> void:
	if _match_rules.count_outs_enabled and not _side_is_outside(side) and _side_is_outside(_opponent_side(side)):
		if SetupActionsMenu.WAIT_FOR_COUNT not in actions:
			actions.append(SetupActionsMenu.WAIT_FOR_COUNT)
	if not _match_rules.weapons_enabled:
		return
	var ai_may_use_weapons := side != Side.AI or not _match_rules.disqualifications_enabled
	if (
		actor.held_weapon == null
		and not _chair_is_in_play()
		and actor.current_area == WrestlerResource.Area.OUTSIDE
		and actor.current_position == WrestlerResource.Position.STANDING
		and actor.current_motion_state == WrestlerResource.MotionState.STATIONARY
		and ai_may_use_weapons
	):
		actions.append(SetupActionsMenu.RETRIEVE_STEEL_CHAIR)
	if (
		actor.held_weapon == null
		and _dropped_weapon != null
		and actor.current_area == _dropped_weapon_area
		and actor.current_position == WrestlerResource.Position.STANDING
		and actor.current_motion_state == WrestlerResource.MotionState.STATIONARY
		and ai_may_use_weapons
	):
		actions.append(SetupActionsMenu.PICK_UP_WEAPON)
	if actor.held_weapon != null:
		actions.append(SetupActionsMenu.DROP_WEAPON)
		if side == Side.AI and _weapon_attack_is_mechanically_valid(actor, target) and ai_may_use_weapons:
			actions.append(SetupActionsMenu.CHAIR_SHOT)


func _weapon_attack_is_mechanically_valid(actor: MatchSideState, target: MatchSideState) -> bool:
	return (
		actor != null
		and target != null
		and actor.held_weapon != null
		and actor.current_position == WrestlerResource.Position.STANDING
		and actor.current_motion_state == WrestlerResource.MotionState.STATIONARY
		and actor.current_area == target.current_area
		and target.current_position != WrestlerResource.Position.NONE
	)


func _chair_is_in_play() -> bool:
	return (
		_dropped_weapon != null
		or player_side_state.held_weapon != null
		or ai_side_state.held_weapon != null
	)


func _create_runtime_chair_shot_move() -> MoveResource:
	var move := MoveResource.new()
	move.move_name = "Steel Chair Shot"
	move.move_type = MoveResource.MoveType.WEAPON
	move.move_target_parts.append(MoveResource.MoveTargetParts.BODY)
	move.targeting_mode = MoveResource.TargetingMode.FIXED_PARTS
	move.required_attacker_position = WrestlerResource.Position.NONE
	move.required_attacker_orientation = WrestlerResource.Orientation.NONE
	move.required_attacker_area_mode = MoveResource.AreaRequirementMode.ANY
	move.required_attacker_motion_state = WrestlerResource.MotionState.STATIONARY
	move.required_target_position = WrestlerResource.Position.NONE
	move.required_target_orientation = WrestlerResource.Orientation.NONE
	move.required_target_area_mode = MoveResource.AreaRequirementMode.SAME_AS_OTHER
	move.required_target_motion_state = WrestlerResource.MotionState.STATIONARY
	move.move_impact = STEEL_CHAIR.impact if STEEL_CHAIR != null else 8
	return move


func _match_state_cache_key(state: MatchSideState) -> String:
	if state == null:
		return "none"
	return "%d:%d:%d:%d" % [
		state.current_position,
		state.current_orientation,
		state.current_area,
		state.current_motion_state,
	]


func _setup_action_has_executable_followup(side: int, action_id: StringName) -> bool:
	if MatchSetupStateRules.is_recovery(action_id) or action_id == SetupActionsMenu.TAUNT:
		return true
	var actor := _state_for_side(side)
	var target := _state_for_side(_opponent_side(side))
	if actor == null or target == null or actor.wrestler == null:
		return false
	for path_data in MatchSetupStateRules.find_followup_paths(actor.all_assigned_moves(), actor.snapshot(), target.snapshot(), 2):
		var path: Array = path_data.get("actions", [])
		var move := path_data.get("move") as MoveResource
		if not path.is_empty() and StringName(path[0]) == action_id and _move_is_unlocked_for_state(actor, move):
			return true
	return false


func _move_is_unlocked_for_state(state: MatchSideState, move: MoveResource) -> bool:
	if state == null or move == null:
		return false
	return state.can_use_move(move)


func _setup_followup_move_types(action_id: StringName) -> Array[int]:
	match action_id:
		SetupActionsMenu.START_RUNNING:
			return [MoveResource.MoveType.RUNNING]
		SetupActionsMenu.CLIMB_TOP_ROPE:
			return [MoveResource.MoveType.AERIAL]
		SetupActionsMenu.PREPARE_SPRINGBOARD:
			return [MoveResource.MoveType.SPRINGBOARD]
		SetupActionsMenu.WAKE_OPPONENT:
			return [MoveResource.MoveType.AERIAL]
	return []


func select_move(side: int, move: MoveResource) -> bool:
	if side != Side.PLAYER or current_controller != ControlState.PLAYER_CONTROL:
		return false
	if is_resolving_action or match_ended or not _move_is_valid(side, move):
		return false
	selected_move = move
	selected_move_target_resolution = MoveTargetResolver.resolve(
		move,
		player_side_state.target_focus_body_part,
		ai_side_state,
	)
	_execute_button.text = "Execute: \"%s\" [%s]" % [
		_move_name(move),
		str(selected_move_target_resolution.get("full_tag", "BODY")),
	]
	_update_action_availability()
	return true


func execute_selected_move(side: int) -> void:
	if selected_move == null:
		return
	var move := selected_move
	var target_resolution := selected_move_target_resolution.duplicate(true)
	if move == _chair_shot_move:
		_clear_selected_move()
		await _execute_rule_action(side, SetupActionsMenu.CHAIR_SHOT, _state_for_side(side), _state_for_side(_opponent_side(side)))
		return
	execute_move(side, move, target_resolution)


func execute_move(
	attacker_side: int,
	move: MoveResource,
	target_resolution: Dictionary = {},
) -> void:
	if not _side_has_control(attacker_side) or match_ended or is_resolving_action:
		return
	if not _move_is_valid(attacker_side, move):
		if attacker_side == Side.PLAYER:
			add_match_log_entry(
				"That move is no longer available from the current positions.",
				Color(1.0, 0.66, 0.3, 1.0),
			)
		_clear_selected_move()
		refresh_match_ui()
		return

	var defender_side := _opponent_side(attacker_side)
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(
			move,
			_state_for_side(attacker_side).target_focus_body_part,
			_state_for_side(defender_side),
		)
	is_resolving_action = true
	last_move_used = move
	_clear_selected_move()
	var attacker_state := _state_for_side(attacker_side)
	var spent_finisher := false
	if attacker_state != null and attacker_state.is_finisher_move(move):
		spent_finisher = attacker_state.spend_finisher()
		if not spent_finisher:
			is_resolving_action = false
			refresh_match_ui()
			return
	advance_match_clock()
	_emit_ring_event(
		&"move_started",
		attacker_side,
		defender_side,
		{
			"label": _move_name(move),
			"is_finisher": move.is_finisher,
			"is_signature": attacker_state != null and move in attacker_state.wrestler.signature_moves,
		},
	)
	refresh_match_ui()
	var attacker := attacker_state
	if _is_high_risk(move):
		attacker.high_risk_attempts += 1
	var defender_input := await _run_defender_response(attacker_side, defender_side, move, target_resolution)
	if match_ended:
		return
	if defender_input == INTERACTION_CANCELLED:
		if spent_finisher:
			attacker_state.refund_finisher()
		is_resolving_action = false
		_resume_controller_after_cancel(attacker_side)
		ensure_match_can_continue("cancelled move response")
		return
	var reversed := defender_input == MatchInteractionModel.InputResult.SUCCESS
	var result := _action_result_from_combined_outcome(
		MatchInteractionModel.resolve_binary_outcome(reversed, _is_high_risk(move)),
	)
	apply_move_result(
		attacker_side,
		defender_side,
		move,
		result,
		reversed,
		target_resolution,
	)
	last_action_result = result
	_emit_ring_state({
		"reason": "move resolution",
		"actor_id": _ring_participant_id(attacker_side),
		"target_id": _ring_participant_id(defender_side),
		"shared_interaction": result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS],
	})
	_emit_ring_event(
		&"move_resolved",
		attacker_side,
		defender_side,
		{"result": _ring_action_result_name(result)},
	)

	if move.is_submission and result == ActionResult.CLEAN_SUCCESS:
		await start_submission_sequence(
			attacker_side,
			defender_side,
			move,
			false,
			target_resolution,
		)
		return
	if _should_start_embedded_pin(attacker_side, defender_side, move, result):
		# A pinning combination already includes the cover. The normal defender
		# reversal happened above. Flash pins and clean finishers that leave both
		# wrestlers grounded now flow straight into the existing count without a
		# separate Pin press, neutral recovery, or clock step.
		is_resolving_action = false
		await start_pin_sequence(attacker_side, defender_side, true)
		return

	is_resolving_action = false
	_resolve_control_after_action(attacker_side, defender_side, move, result)
	refresh_match_ui()
	ensure_match_can_continue("move resolution")


func _should_start_embedded_pin(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
) -> bool:
	if move == null or move.is_submission or result != ActionResult.CLEAN_SUCCESS:
		return false
	if move.is_flash_pin or move.is_pinning_combination:
		return true
	if not move.is_finisher:
		return false
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	return (
		attacker != null
		and defender != null
		and attacker.current_position == WrestlerResource.Position.GROUNDED
		and defender.current_position == WrestlerResource.Position.GROUNDED
	)


func _run_defender_response(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	target_resolution: Dictionary = {},
) -> int:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	defender.response_attempts += 1
	defender.reversal_opportunities += 1
	var repetition_active := (
		attacker.last_attempted_move_matches(move)
		or attacker.recent_move_type_count(move.move_type, 5) >= 3
		or attacker.setup_pattern_repeats(move)
	)
	if repetition_active:
		attacker.repetition_penalties_applied += 1
	var profile := MatchInteractionModel.build_response_profile(
		attacker,
		defender,
		move,
		defender_side == Side.PLAYER,
		_match_time_seconds,
		&"",
		target_resolution,
	)
	defender.response_profile_total += float(profile.get("ai_success_chance", 0.0))
	defender.response_profile_samples += 1
	var result := MatchInteractionModel.InputResult.FAIL
	if defender_side == Side.PLAYER:
		var request := profile.duplicate(true)
		request["title"] = "%s: %s" % ["ESCAPE" if move.is_submission else "REVERSE", _move_name(move)]
		request["prompt"] = "Stop the moving marker inside the gold zone."
		request["button_text"] = "ESCAPE" if move.is_submission else "REVERSE"
		var response := await _run_visible_reversal_meter(request)
		if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
			return INTERACTION_CANCELLED
		result = (
			MatchInteractionModel.InputResult.SUCCESS
			if int(response.get("result", MatchInteractionModel.InputResult.FAIL)) == MatchInteractionModel.InputResult.SUCCESS
			else MatchInteractionModel.InputResult.FAIL
		)
	else:
		result = _simulate_binary_result(float(profile.get("ai_success_chance", 22.0)))
	if result == MatchInteractionModel.InputResult.SUCCESS:
		defender.response_successes += 1
	if defender_side == Side.AI and OS.is_debug_build():
		print(
			"AI RESPONSE | move=%s chance=%.1f result=%s" % [
				_move_name(move),
				float(profile.get("ai_success_chance", 22.0)),
				"SUCCESS" if result == MatchInteractionModel.InputResult.SUCCESS else "FAIL",
			],
		)
	return result


func _run_visible_timing_circle(request: Dictionary) -> Dictionary:
	_begin_visible_interaction()
	var response := await _interaction_overlay.run_timing_circle(request)
	_end_visible_interaction()
	return response


func _run_visible_reversal_meter(request: Dictionary) -> Dictionary:
	return await _run_visible_control_meter(request)


func _run_visible_control_meter(request: Dictionary) -> Dictionary:
	_begin_visible_interaction()
	var response := await _interaction_overlay.run_control_meter(request)
	_end_visible_interaction()
	return response


func _begin_visible_interaction() -> void:
	contest_prompt_active = true
	_interaction_player_position = player_side_state.current_position
	_interaction_ai_position = ai_side_state.current_position
	_interaction_player_state_key = _side_state_key(player_side_state)
	_interaction_ai_state_key = _side_state_key(ai_side_state)
	_interaction_controller = current_controller
	_interaction_player_wrestler = player_wrestler
	_interaction_ai_wrestler = ai_wrestler
	_moves_radial_menu.close()
	_setup_actions_menu.close()
	refresh_match_ui()


func _end_visible_interaction() -> void:
	contest_prompt_active = false
	refresh_match_ui()


func _interaction_context_changed() -> bool:
	return (
		match_ended
		or player_side_state.current_position != _interaction_player_position
		or ai_side_state.current_position != _interaction_ai_position
		or _side_state_key(player_side_state) != _interaction_player_state_key
		or _side_state_key(ai_side_state) != _interaction_ai_state_key
		or current_controller != _interaction_controller
		or player_wrestler != _interaction_player_wrestler
		or ai_wrestler != _interaction_ai_wrestler
	)


func _side_state_key(state: MatchSideState) -> String:
	if state == null:
		return ""
	return "%d:%d:%d:%d" % [
		state.current_position,
		state.current_orientation,
		state.current_area,
		state.current_motion_state,
	]


func _simulate_binary_result(success_chance: float) -> int:
	return (
		MatchInteractionModel.InputResult.SUCCESS
		if randf() * 100.0 < clampf(success_chance, 0.0, 100.0)
		else MatchInteractionModel.InputResult.FAIL
	)


func _action_result_from_combined_outcome(outcome: int) -> int:
	match outcome:
		MatchInteractionModel.CombinedOutcome.CLEAN_SUCCESS:
			return ActionResult.CLEAN_SUCCESS
		MatchInteractionModel.CombinedOutcome.REVERSAL:
			return ActionResult.REVERSAL
		MatchInteractionModel.CombinedOutcome.CONTESTED_STRUGGLE:
			return ActionResult.CONTESTED_STRUGGLE
		MatchInteractionModel.CombinedOutcome.HIGH_RISK_CRASH:
			return ActionResult.HIGH_RISK_CRASH
		MatchInteractionModel.CombinedOutcome.LABOURED_SUCCESS:
			return ActionResult.LABOURED_SUCCESS
	return ActionResult.BOTCH_OR_SCRAMBLE


func apply_move_result(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
	defender_succeeded: bool = false,
	target_resolution: Dictionary = {},
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if attacker == null or defender == null:
		return
	attacker.last_action_result = result
	defender.last_action_result = result
	defender.last_move_taken = move
	attacker.last_move_was_high_risk = _is_high_risk(move)
	var move_landed := result == ActionResult.CLEAN_SUCCESS
	attacker.record_move_used(move, move_landed)
	var reversal_landed := (
		result == ActionResult.REVERSAL
		or (result == ActionResult.HIGH_RISK_CRASH and defender_succeeded)
	)
	if reversal_landed:
		_recent_reversal_side = defender_side
	elif attacker_side == _recent_reversal_side:
		if not move_landed or not _is_flash_pin_move(move):
			_recent_reversal_side = Side.NONE
	elif _recent_reversal_side != Side.NONE:
		_recent_reversal_side = Side.NONE
	if reversal_landed:
		defender.reversals += 1
	if defender_side == Side.AI and (
		result == ActionResult.REVERSAL
		or (result == ActionResult.HIGH_RISK_CRASH and defender_succeeded)
	):
		_ai_decision_engine.note_reversal_control()
	if result != ActionResult.CLEAN_SUCCESS:
		attacker.last_move_was_finisher = false
	if result == ActionResult.CLEAN_SUCCESS:
		attacker.clean_successes += 1
	elif result == ActionResult.LABOURED_SUCCESS:
		attacker.laboured_successes += 1
		attacker.near_miss_conversions += 1
	elif result == ActionResult.CONTESTED_STRUGGLE:
		attacker.contested_struggles += 1
	if result == ActionResult.BOTCH_OR_SCRAMBLE:
		attacker.botches_scrambles += 1
	if result == ActionResult.HIGH_RISK_CRASH:
		attacker.high_risk_crashes += 1
	apply_damage(attacker_side, defender_side, move, result, target_resolution)
	apply_stamina_fatigue_momentum(attacker_side, defender_side, move, result)
	apply_positions(attacker_side, defender_side, move, result)
	var signature_converted := (
		result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS]
		and attacker.is_signature_move(move)
		and attacker.convert_landed_signature()
	)
	if attacker_side == Side.AI:
		_ai_decision_engine.note_move_result(
			move,
			move_landed,
			result == ActionResult.CLEAN_SUCCESS,
			defender,
			attacker,
			target_resolution,
		)
	if defender_side == Side.AI and result == ActionResult.HIGH_RISK_CRASH:
		_ai_decision_engine.note_player_high_risk_crash()
	if attacker_side == Side.PLAYER:
		if (
			result == ActionResult.CLEAN_SUCCESS
			and not _player_setup_intent.is_empty()
			and _setup_intent_matches_move(_player_setup_intent, move)
		):
			player_side_state.successful_setup_followups += 1
		_player_setup_intent = &""
	var attacker_name := _side_name(attacker_side)
	var defender_name := _side_name(defender_side)
	var move_name := _move_name(move)
	var target_name := MoveTargetResolver.part_label(
		int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))
	).to_lower()
	match result:
		ActionResult.CLEAN_SUCCESS:
			if not move.is_submission:
				var clean_line := "%s plants %s with \"%s\"." % [attacker_name, defender_name, move_name]
				if MoveTargetResolver.is_limb_focus(int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))):
					clean_line = "%s plants %s with \"%s\", driving the attack into the %s." % [
						attacker_name,
						defender_name,
						move_name,
						target_name,
					]
				add_match_log_entry(
					clean_line,
					Color(0.95, 0.78, 0.22, 1.0) if move.is_finisher else Color(0.84, 0.87, 0.92, 1.0),
				)
		ActionResult.LABOURED_SUCCESS:
			if not move.is_submission:
				var variants := [
					"%s muscles through an awkward \"%s\", but it takes a lot out of them.",
					"%s catches enough of \"%s\" to keep control.",
					"%s forces \"%s\" through despite rough timing.",
				]
				add_match_log_entry(str(variants[randi() % variants.size()]) % [attacker_name, move_name])
		ActionResult.REVERSAL:
			add_match_log_entry("%s counters \"%s\" and takes control." % [defender_name, move_name])
		ActionResult.CONTESTED_STRUGGLE:
			if move.is_strike:
				add_match_log_entry(
					"%s connects only glancingly with \"%s\" as %s answers the attack. They reset." % [
						attacker_name,
						move_name,
						defender_name,
					],
				)
			elif not move.is_submission:
				add_match_log_entry(
					"%s fights for \"%s\", but %s blocks the attempt. They reset in a struggle for control." % [
						attacker_name,
						move_name,
						defender_name,
					],
				)
		ActionResult.BOTCH_OR_SCRAMBLE:
			add_match_log_entry(
				"%s mistimes \"%s\", and the exchange breaks down into a scramble." % [attacker_name, move_name],
			)
		ActionResult.HIGH_RISK_CRASH:
			add_match_log_entry(
				"%s commits to \"%s\", but %s moves clear. %s crashes hard to the mat." % [
					attacker_name,
					move_name,
					defender_name,
					attacker_name,
				],
			)
	if signature_converted:
		add_match_log_entry(
			"%s converts the signature into finisher stock (%d/%d)." % [
				attacker_name,
				attacker.finisher_stock,
				MatchSideState.MAX_FINISHER_STOCK,
			],
			Color(0.95, 0.78, 0.22, 1.0),
		)
	attacker.sync_to_resource()
	defender.sync_to_resource()


func apply_damage(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
	target_resolution: Dictionary = {},
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, attacker.target_focus_body_part, defender)
	var attacker_hp_before := attacker.total_hp()
	var defender_hp_before := defender.total_hp()
	var part_hp_before: Dictionary = {}
	for part in target_resolution.get("parts", []):
		part_hp_before[int(part)] = defender.get_part_hp(int(part))
	if result == ActionResult.HIGH_RISK_CRASH:
		attacker.damage_part(MoveResource.MoveTargetParts.BODY, float(move.move_impact) * 0.75)
	elif result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS] or (result == ActionResult.CONTESTED_STRUGGLE and move.is_strike):
		var modifier := 1.0
		if result == ActionResult.LABOURED_SUCCESS:
			modifier = 0.60
		elif result == ActionResult.CONTESTED_STRUGGLE:
			modifier = 0.25
		var parts: Array = target_resolution.get("parts", [MoveResource.MoveTargetParts.BODY])
		var weights: Dictionary = target_resolution.get("damage_weights", {})
		for part in parts:
			var part_id := int(part)
			var current_hp := defender.get_part_hp(part_id)
			# Damaged parts remain rewarding targets, but the vulnerability ramp is
			# deliberately shallow enough that repeated limb work does not snowball
			# entirely from its own bonus damage.
			var damage := float(move.move_impact) + ((100.0 - current_hp) * 0.08)
			defender.damage_part(part_id, damage * modifier * float(weights.get(part_id, 1.0)))
	var attacker_damage := maxf(0.0, attacker_hp_before - attacker.total_hp())
	var defender_damage := maxf(0.0, defender_hp_before - defender.total_hp())
	attacker.damage_taken += attacker_damage
	defender.damage_taken += defender_damage
	attacker.damage_dealt += defender_damage
	var story_part := int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))
	var landed := result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS] or (
		result == ActionResult.CONTESTED_STRUGGLE and move.is_strike
	)
	if attacker.target_focus_body_part != MoveResource.MoveTargetParts.NONE:
		attacker.target_focus_age += 1
	for raw_part in target_resolution.get("parts", [story_part]):
		var part := int(raw_part)
		var part_damage := maxf(
			0.0,
			float(part_hp_before.get(part, defender.get_part_hp(part))) - defender.get_part_hp(part),
		)
		attacker.record_target_resolution(part, part_damage, landed, null)
	if landed:
		if move.is_submission:
			attacker.last_submission_target = story_part
		if move.is_finisher:
			attacker.last_finisher_target = story_part
	if landed:
		_record_body_target_story(attacker, defender, move, target_resolution, part_hp_before)


func _record_body_target_story(
	attacker: MatchSideState,
	defender: MatchSideState,
	move: MoveResource,
	target_resolution: Dictionary,
	part_hp_before: Dictionary,
) -> void:
	var story_part := int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))
	var story_label := MoveTargetResolver.part_label(story_part).to_lower()
	var critical_message := ""
	var threshold_message := ""
	var parts: Array = target_resolution.get("parts", [story_part])
	for raw_part in parts:
		var part := int(raw_part)
		var before_hp := float(part_hp_before.get(part, defender.get_part_hp(part)))
		var crossed := defender.mark_crossed_thresholds(part, before_hp, defender.get_part_hp(part))
		for threshold in [0, 20, 40, 60, 80]:
			if threshold not in crossed:
				continue
			var part_label := MoveTargetResolver.part_label(part).to_lower()
			if threshold <= 20 and critical_message.is_empty():
				critical_message = "%s's %s is in critical condition after the sustained punishment." % [
					_wrestler_name(defender.wrestler),
					part_label,
				]
			elif threshold_message.is_empty():
				threshold_message = "%s has done visible damage to %s's %s." % [
					_wrestler_name(attacker.wrestler),
					_wrestler_name(defender.wrestler),
					part_label,
				]
	var attack_count := int(attacker.target_attack_counts.get(story_part, 0))
	var repeated_message := ""
	if attacker.mark_repeated_target_milestone(story_part, attack_count):
		repeated_message = "%s keeps returning to the %s; that is now a deliberate target." % [
			_wrestler_name(attacker.wrestler),
			story_label,
		]
	var submission_message := ""
	if move.is_submission and defender.get_part_hp(story_part) < 40.0:
		submission_message = "With the %s already damaged, this submission is especially dangerous." % story_label
	var chosen_message := critical_message
	if chosen_message.is_empty():
		chosen_message = submission_message
	if chosen_message.is_empty():
		chosen_message = threshold_message
	if chosen_message.is_empty():
		chosen_message = repeated_message
	if chosen_message.is_empty():
		return
	var critical := not critical_message.is_empty() and chosen_message == critical_message
	if not critical and _match_time_seconds - defender.last_body_commentary_time < 60:
		defender.pending_body_commentary = {
			"message": chosen_message,
			"part": story_part,
		}
		return
	defender.pending_body_commentary.clear()
	defender.last_body_commentary_time = _match_time_seconds
	add_match_log_entry(chosen_message, Color(1.0, 0.68, 0.28, 1.0) if critical else Color(0.72, 0.79, 0.9, 1.0))


func apply_stamina_fatigue_momentum(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var stamina_cost := _stamina_cost(move)
	var attacker_fatigue := 2.0 + (4.0 if _is_high_risk(move) else 0.0) + (4.0 if move.is_finisher else 0.0)
	match result:
		ActionResult.CLEAN_SUCCESS:
			attacker.spend_stamina(stamina_cost)
			attacker.add_fatigue(attacker_fatigue)
			defender.add_fatigue(2.0 + (4.0 if move.is_finisher else 0.0))
			attacker.add_momentum(15.0 if move.is_finisher else 8.0)
			defender.add_momentum(-3.0)
		ActionResult.LABOURED_SUCCESS:
			attacker.spend_stamina(stamina_cost * 1.10)
			attacker.add_fatigue(attacker_fatigue + 1.0)
			defender.add_fatigue(1.0)
			attacker.add_momentum(4.0)
			defender.add_momentum(-1.0)
		ActionResult.CONTESTED_STRUGGLE:
			attacker.spend_stamina(stamina_cost)
			defender.spend_stamina(maxf(2.0, stamina_cost * 0.25))
			attacker.add_fatigue(2.0)
			defender.add_fatigue(2.0)
			attacker.add_momentum(1.0)
			defender.add_momentum(1.0)
		ActionResult.BOTCH_OR_SCRAMBLE:
			var heavy_failure := move.move_impact >= 7 or MatchInteractionModel.get_interaction_type_for_move(move) == MatchInteractionModel.InteractionType.HOLD_POWER
			attacker.spend_stamina(stamina_cost * (0.80 if heavy_failure else 0.60))
			attacker.add_fatigue(3.0)
			attacker.add_momentum(-8.0 if heavy_failure else -5.0)
		ActionResult.REVERSAL, ActionResult.HIGH_RISK_CRASH:
			attacker.spend_stamina(stamina_cost)
			attacker.add_fatigue(attacker_fatigue)
			attacker.add_momentum(-12.0 if move.is_finisher else (-10.0 if result == ActionResult.HIGH_RISK_CRASH else -8.0))
			defender.add_momentum(10.0 if move.is_finisher else (12.0 if result == ActionResult.HIGH_RISK_CRASH else 10.0))
	if result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS] and attacker.pending_taunt_momentum_bonus > 0.0:
		var pending_bonus := attacker.pending_taunt_momentum_bonus
		var momentum_before := attacker.momentum
		attacker.add_momentum(pending_bonus)
		attacker.taunt_bonus_momentum_consumed += attacker.momentum - momentum_before
		attacker.pending_taunt_momentum_bonus = 0.0


func apply_positions(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	match result:
		ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS:
			_apply_move_result_state(attacker, move, true)
			_apply_move_result_state(defender, move, false)
		ActionResult.HIGH_RISK_CRASH:
			_set_high_risk_crash_state(attacker, move)


func _apply_move_result_state(state: MatchSideState, move: MoveResource, attacker_result: bool) -> void:
	if state == null or move == null:
		return
	state.set_match_state(
		move.resulting_attacker_position if attacker_result else move.resulting_target_position,
		move.resulting_attacker_orientation if attacker_result else move.resulting_target_orientation,
		move.resolved_attacker_area(state.current_area) if attacker_result else move.resolved_target_area(state.current_area),
		move.resulting_attacker_motion_state if attacker_result else move.resulting_target_motion_state,
	)


func _set_neutral_ring_stance(state: MatchSideState) -> void:
	state.set_match_state(
		WrestlerResource.Position.STANDING,
		WrestlerResource.Orientation.FRONT,
		WrestlerResource.Area.IN_RING,
		WrestlerResource.MotionState.STATIONARY,
	)


func _set_grounded_in_ring(state: MatchSideState) -> void:
	state.set_match_state(
		WrestlerResource.Position.GROUNDED,
		WrestlerResource.Orientation.FACE_UP,
		WrestlerResource.Area.IN_RING,
		WrestlerResource.MotionState.STATIONARY,
	)


func _set_high_risk_crash_state(state: MatchSideState, move: MoveResource) -> void:
	var landing_area := state.current_area
	if move != null:
		landing_area = move.resolved_attacker_area(state.current_area)
	state.set_match_state(
		WrestlerResource.Position.GROUNDED,
		WrestlerResource.Orientation.FACE_DOWN,
		landing_area,
		WrestlerResource.MotionState.STATIONARY,
	)


func _set_rope_rebound_state(state: MatchSideState) -> void:
	var rebound_area := state.current_area
	if not MatchAreaRules.is_shared_flat_area(rebound_area):
		rebound_area = WrestlerResource.Area.IN_RING
	state.set_match_state(
		WrestlerResource.Position.STANDING,
		WrestlerResource.Orientation.FRONT,
		rebound_area,
		WrestlerResource.MotionState.ROPE_REBOUND,
	)


func _set_corner_state(state: MatchSideState) -> void:
	state.set_match_state(
		WrestlerResource.Position.STANDING,
		WrestlerResource.Orientation.FRONT,
		WrestlerResource.Area.CORNER,
		WrestlerResource.MotionState.STATIONARY,
	)


func _apply_automatic_setup_state(
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> void:
	_apply_projected_setup_state(action_id, actor, target)


func _apply_projected_setup_state(
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> bool:
	var projected := MatchSetupStateRules.project_action(action_id, actor.snapshot(), target.snapshot())
	if not bool(projected.get("valid", false)):
		return false
	_apply_state_snapshot(actor, projected.get("attacker", {}))
	_apply_state_snapshot(target, projected.get("target", {}))
	return true


func _apply_state_snapshot(state: MatchSideState, snapshot: Dictionary) -> void:
	if state == null or snapshot.is_empty():
		return
	state.set_match_state(
		int(snapshot.get("position", state.current_position)),
		int(snapshot.get("orientation", state.current_orientation)),
		int(snapshot.get("area", state.current_area)),
		int(snapshot.get("motion_state", state.current_motion_state)),
	)


func execute_setup_action(side: int, action_id: StringName) -> void:
	if (
		match_ended
		or is_resolving_action
		or contest_prompt_active
		or pin_sequence_active
		or submission_sequence_active
	):
		return
	var neutral_player_recovery := (
		current_controller == ControlState.NEUTRAL
		and side == Side.PLAYER
		and action_id == SetupActionsMenu.STAND_UP
	)
	if not _side_has_control(side) and not neutral_player_recovery:
		return
	var valid_actions := get_valid_setup_actions(side)
	if action_id not in valid_actions:
		return
	var actor := _state_for_side(side)
	var target := _state_for_side(_opponent_side(side))
	if action_id in [
			SetupActionsMenu.WAIT_FOR_COUNT,
			SetupActionsMenu.RETRIEVE_STEEL_CHAIR,
			SetupActionsMenu.PICK_UP_WEAPON,
			SetupActionsMenu.DROP_WEAPON,
		SetupActionsMenu.CHAIR_SHOT,
	]:
		await _execute_rule_action(side, action_id, actor, target)
		return
	var revalidated := MatchSetupStateRules.project_action(action_id, actor.snapshot(), target.snapshot())
	if not bool(revalidated.get("valid", false)):
		return
	_recent_reversal_side = Side.NONE
	is_resolving_action = true
	advance_match_clock()
	if action_id == SetupActionsMenu.TAUNT:
		actor.taunt_cooldown_until_seconds = _match_time_seconds + TAUNT_COOLDOWN_SECONDS
	if MatchInteractionModel.is_contested_setup(action_id):
		await _execute_contested_setup_action(side, action_id, actor, target)
		return
	_apply_automatic_setup_state(action_id, actor, target)
	_emit_ring_state({
		"reason": "automatic setup",
		"actor_id": _ring_participant_id(side),
		"target_id": _ring_participant_id(_opponent_side(side)),
		"shared_interaction": false,
	})
	_emit_ring_event(&"setup_resolved", side, _opponent_side(side), {"label": _setup_action_short_name(action_id)})
	actor.spend_stamina(3.0)
	actor.add_fatigue(1.0)
	actor.add_momentum(2.0)
	actor.setup_actions += 1
	if side == Side.AI:
		_ai_decision_engine.note_setup_executed(action_id, actor)
	else:
		_player_setup_intent = action_id
	last_action_result = ActionResult.SETUP_SUCCESS
	actor.last_action_result = ActionResult.SETUP_SUCCESS
	add_match_log_entry(_setup_log_message(side, action_id), Color(0.55, 0.78, 1.0, 1.0))
	is_resolving_action = false
	_clear_selected_move_if_invalid()
	_set_controller(_control_for_side(side))
	refresh_match_ui()
	ensure_match_can_continue("automatic setup resolution")


func _execute_rule_action(
	side: int,
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> void:
	if actor == null or target == null:
		return
	is_resolving_action = true
	advance_match_clock()
	actor.setup_actions += 1
	var next_control_side := side
	match action_id:
		SetupActionsMenu.WAIT_FOR_COUNT:
			actor.spend_stamina(1.0)
			add_match_log_entry("%s stays safely inside and urges the referee to keep counting." % _side_name(side), Color(0.95, 0.78, 0.22, 1.0))
			_emit_ring_event(&"count_wait", side, _opponent_side(side))
			# Waiting is a pass, not a control-preserving action. The wrestler on
			# the floor receives the next turn and a fair chance to beat the count.
			next_control_side = _opponent_side(side)
		SetupActionsMenu.RETRIEVE_STEEL_CHAIR:
			if actor.held_weapon != null or _chair_is_in_play() or actor.current_area != WrestlerResource.Area.OUTSIDE:
				is_resolving_action = false
				ensure_match_can_continue("invalid weapon retrieval")
				return
			actor.held_weapon = STEEL_CHAIR
			actor.held_weapon_uses_remaining = randi_range(
				mini(STEEL_CHAIR.minimum_durability, STEEL_CHAIR.maximum_durability),
				maxi(STEEL_CHAIR.minimum_durability, STEEL_CHAIR.maximum_durability),
			)
			actor.weapons_retrieved += 1
			actor.last_weapon_action_time = _match_time_seconds
			actor.spend_stamina(2.0)
			add_match_log_entry("%s reaches beneath the ring and pulls out a steel chair." % _side_name(side), Color(1.0, 0.62, 0.3, 1.0))
			if _match_rules.disqualifications_enabled:
				add_match_log_entry("The referee warns %s not to use it." % _side_name(side), Color(1.0, 0.48, 0.42, 1.0))
			_emit_ring_event(&"weapon_retrieved", side, _opponent_side(side), {"weapon": actor.held_weapon.display_name})
		SetupActionsMenu.PICK_UP_WEAPON:
			if actor.held_weapon != null or _dropped_weapon == null or actor.current_area != _dropped_weapon_area:
				is_resolving_action = false
				ensure_match_can_continue("invalid dropped weapon pickup")
				return
			actor.held_weapon = _dropped_weapon
			_dropped_weapon = null
			actor.held_weapon_uses_remaining = _dropped_weapon_uses_remaining
			_dropped_weapon_uses_remaining = 0
			actor.dropped_weapons_picked_up += 1
			actor.last_weapon_action_time = _match_time_seconds
			add_match_log_entry("%s picks the steel chair back up." % _side_name(side), Color(1.0, 0.62, 0.3, 1.0))
			_emit_ring_event(&"weapon_retrieved", side, _opponent_side(side), {"weapon": actor.held_weapon.display_name, "from_floor": true})
		SetupActionsMenu.DROP_WEAPON:
			if actor.held_weapon == null:
				is_resolving_action = false
				ensure_match_can_continue("invalid weapon drop")
				return
			var dropped_name := actor.held_weapon.display_name if actor.held_weapon != null else "weapon"
			_dropped_weapon = actor.held_weapon
			_dropped_weapon_area = actor.current_area
			_dropped_weapon_uses_remaining = actor.held_weapon_uses_remaining
			actor.held_weapon = null
			actor.held_weapon_uses_remaining = 0
			actor.last_weapon_action_time = _match_time_seconds
			add_match_log_entry("%s drops the %s in the current area." % [_side_name(side), dropped_name.to_lower()])
			_emit_ring_event(&"weapon_dropped", side, _opponent_side(side), {"weapon": dropped_name, "area": _dropped_weapon_area})
		SetupActionsMenu.CHAIR_SHOT:
			await _execute_chair_shot(side, actor, target)
			return
	last_action_result = ActionResult.SETUP_SUCCESS
	actor.last_action_result = ActionResult.SETUP_SUCCESS
	is_resolving_action = false
	_set_controller(_control_for_side(next_control_side))
	refresh_match_ui()
	ensure_match_can_continue("rule action resolution")


func _execute_chair_shot(side: int, actor: MatchSideState, target: MatchSideState) -> void:
	if not _weapon_attack_is_mechanically_valid(actor, target):
		is_resolving_action = false
		ensure_match_can_continue("invalid chair attack")
		return
	var weapon := actor.held_weapon
	actor.last_weapon_action_time = _match_time_seconds
	actor.weapon_attacks_attempted += 1
	if weapon.display_name not in actor.weapon_types_used:
		actor.weapon_types_used.append(weapon.display_name)
	add_match_log_entry("%s raises the steel chair and commits to the swing!" % _side_name(side), Color(1.0, 0.48, 0.36, 1.0))
	_emit_ring_event(&"weapon_attack", side, _opponent_side(side), {"weapon": weapon.display_name, "illegal": _match_rules.weapon_attack_causes_disqualification(weapon)})
	var defender_side := _opponent_side(side)
	var defender_input := await _run_setup_defender_response(side, defender_side, SetupActionsMenu.CHAIR_SHOT, actor, target)
	if match_ended:
		return
	if defender_input == INTERACTION_CANCELLED:
		is_resolving_action = false
		_resume_controller_after_cancel(side)
		ensure_match_can_continue("cancelled chair response")
		return
	var reversed := defender_input == MatchInteractionModel.InputResult.SUCCESS
	actor.spend_stamina(weapon.stamina_cost)
	actor.add_fatigue(3.0)
	actor.held_weapon_uses_remaining = maxi(0, actor.held_weapon_uses_remaining - 1)
	if reversed:
		actor.weapon_attacks_reversed += 1
		target.reversals += 1
		target.add_momentum(10.0)
		actor.add_momentum(-10.0)
		last_action_result = ActionResult.REVERSAL
		add_match_log_entry("%s ducks the chair swing and knocks it from %s's hands!" % [_side_name(defender_side), _side_name(side)])
		_emit_ring_event(&"weapon_reversed", defender_side, side, {"weapon": weapon.display_name})
	else:
		actor.weapon_attacks_landed += 1
		var target_resolution := MoveTargetResolver.resolve(_chair_shot_move, actor.target_focus_body_part, target)
		var target_part := int(target_resolution.get("story_part", int(weapon.target_body_part)))
		var target_hp_before := target.get_part_hp(target_part)
		target.damage_part(target_part, float(weapon.impact) * 1.75)
		var dealt_damage := maxf(0.0, target_hp_before - target.get_part_hp(target_part))
		actor.damage_dealt += dealt_damage
		target.damage_taken += dealt_damage
		actor.record_target_resolution(target_part, dealt_damage, true, _chair_shot_move)
		target.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, target.current_area, WrestlerResource.MotionState.STATIONARY)
		actor.add_momentum(12.0)
		last_action_result = ActionResult.CLEAN_SUCCESS
		add_match_log_entry(
			"%s drives the chair into %s's %s!" % [_side_name(side), _side_name(defender_side), MoveTargetResolver.part_label(target_part).to_lower()],
			Color(1.0, 0.48, 0.36, 1.0),
		)
	if reversed and actor.held_weapon_uses_remaining > 0:
		_dropped_weapon = weapon
		_dropped_weapon_area = actor.current_area
		_dropped_weapon_uses_remaining = actor.held_weapon_uses_remaining
		actor.held_weapon = null
		actor.held_weapon_uses_remaining = 0
		_emit_ring_event(&"weapon_dropped", side, defender_side, {"weapon": weapon.display_name, "area": _dropped_weapon_area})
	if _match_rules.weapon_attack_causes_disqualification(weapon):
		actor.illegal_weapon_uses += 1
		actor.disqualifications_caused += 1
		is_resolving_action = false
		add_match_log_entry("The referee immediately calls for the bell — %s used an illegal weapon." % _side_name(side), Color(0.95, 0.78, 0.22, 1.0))
		end_match(defender_side, side, FinishType.DISQUALIFICATION, null, "%s was disqualified for using a steel chair." % _side_name(side), "Steel Chair attack")
		return
	if actor.held_weapon != null and actor.held_weapon_uses_remaining <= 0:
		actor.weapons_broken += 1
		actor.held_weapon = null
		add_match_log_entry("The battered steel chair finally buckles and breaks apart.", Color(1.0, 0.62, 0.3, 1.0))
		_emit_ring_event(&"weapon_broken", side, defender_side, {"weapon": weapon.display_name})
	actor.legal_weapon_attacks += 1
	add_match_log_entry("No disqualifications tonight — the chair shot is legal.", Color(0.95, 0.78, 0.22, 1.0))
	is_resolving_action = false
	_set_controller(_control_for_side(defender_side) if reversed else _control_for_side(side))
	refresh_match_ui()
	ensure_match_can_continue("legal chair attack resolution")


func _execute_contested_setup_action(
	side: int,
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> void:
	if side != Side.AI:
		_player_setup_intent = &""
	actor.setup_actions += 1
	actor.contested_setup_attempts += 1
	var is_taunt := action_id == SetupActionsMenu.TAUNT
	var original_actor_area := actor.current_area
	if is_taunt:
		actor.taunts_attempted += 1
	var defender_side := _opponent_side(side)
	var defender_input := await _run_setup_defender_response(side, defender_side, action_id, actor, target)
	if match_ended:
		return
	if defender_input == INTERACTION_CANCELLED:
		is_resolving_action = false
		_resume_controller_after_cancel(side)
		ensure_match_can_continue("cancelled setup response")
		return
	var reversed := defender_input == MatchInteractionModel.InputResult.SUCCESS
	if reversed:
		if side == Side.AI:
			_ai_decision_engine.note_setup_executed(&"", actor)
		_apply_reversed_setup_positions(action_id, actor, target)
		actor.spend_stamina(3.0)
		actor.add_fatigue(2.0)
		actor.add_momentum(-6.0 if is_taunt else -8.0)
		target.add_momentum(8.0 if is_taunt else 10.0)
		actor.contested_setup_losses += 1
		target.contested_setup_wins += 1
		target.reversals += 1
		if is_taunt:
			actor.taunts_interrupted += 1
		_recent_reversal_side = defender_side
		last_action_result = ActionResult.REVERSAL
		actor.last_action_result = ActionResult.REVERSAL
		add_match_log_entry(
			_taunt_interrupted_log_message(side, original_actor_area) if is_taunt else _reversed_setup_log_message(side, action_id),
		)
	else:
		_apply_clean_setup_positions(action_id, actor, target)
		if is_taunt:
			_apply_successful_taunt(actor)
			actor.taunts_succeeded += 1
		else:
			actor.note_setup_action(action_id)
			actor.spend_stamina(3.0)
			actor.add_fatigue(1.0)
			actor.add_momentum(2.0)
		actor.contested_setup_wins += 1
		actor.clean_successes += 1
		last_action_result = ActionResult.SETUP_SUCCESS
		actor.last_action_result = ActionResult.SETUP_SUCCESS
		add_match_log_entry(
			_taunt_success_log_message(side, actor, target) if is_taunt else _setup_log_message(side, action_id),
			Color(0.95, 0.78, 0.22, 1.0) if is_taunt else Color(0.55, 0.78, 1.0, 1.0),
		)
		if side == Side.AI:
			_ai_decision_engine.note_setup_executed(action_id, actor)
		else:
			_player_setup_intent = &"" if is_taunt else action_id
	actor.sync_to_resource()
	target.sync_to_resource()
	_emit_ring_state({
		"reason": "contested setup resolution",
		"actor_id": _ring_participant_id(side),
		"target_id": _ring_participant_id(defender_side),
		"shared_interaction": not reversed,
	})
	_emit_ring_event(
		&"setup_resolved",
		side,
		defender_side,
		{"label": _setup_action_short_name(action_id), "reversed": reversed},
	)
	is_resolving_action = false
	_clear_selected_move_if_invalid()
	var resolved_control := _control_for_side(defender_side) if reversed else _control_for_side(side)
	if (
		not reversed
		and action_id == SetupActionsMenu.SEND_OPPONENT_OUTSIDE
		and not _has_immediate_outside_followup(side)
	):
		resolved_control = _control_for_side(defender_side)
	_set_resolved_controller(
		resolved_control,
		side,
		defender_side,
	)
	refresh_match_ui()
	ensure_match_can_continue("contested setup resolution")


func _has_immediate_outside_followup(side: int) -> bool:
	if not get_valid_moves(side).is_empty():
		return true
	var actor := _state_for_side(side)
	var target := _state_for_side(_opponent_side(side))
	if actor == null or target == null or actor.wrestler == null:
		return false
	var paths := MatchSetupStateRules.find_followup_paths(
		actor.all_assigned_moves(),
		actor.snapshot(),
		target.snapshot(),
		1,
	)
	for path_data in paths:
		var move := path_data.get("move") as MoveResource
		if move != null and _move_is_unlocked_for_state(actor, move):
			return true
	return false


func _run_setup_defender_response(
	_attacker_side: int,
	defender_side: int,
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> int:
	target.response_attempts += 1
	target.reversal_opportunities += 1
	var profile := MatchInteractionModel.build_response_profile(
		actor,
		target,
		null,
		defender_side == Side.PLAYER,
		_match_time_seconds,
		action_id,
	)
	target.response_profile_total += float(profile.get("ai_success_chance", 0.0))
	target.response_profile_samples += 1
	var result := MatchInteractionModel.InputResult.FAIL
	if defender_side == Side.PLAYER:
		var request := profile.duplicate(true)
		request["title"] = "REVERSE: %s" % _setup_action_short_name(action_id)
		request["prompt"] = "Stop the moving marker inside the gold zone."
		request["button_text"] = "REVERSE"
		var response := await _run_visible_reversal_meter(request)
		if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
			return INTERACTION_CANCELLED
		result = (
			MatchInteractionModel.InputResult.SUCCESS
			if int(response.get("result", MatchInteractionModel.InputResult.FAIL)) == MatchInteractionModel.InputResult.SUCCESS
			else MatchInteractionModel.InputResult.FAIL
		)
	else:
		result = _simulate_binary_result(float(profile.get("ai_success_chance", 25.0)))
	if result == MatchInteractionModel.InputResult.SUCCESS:
		target.response_successes += 1
	if defender_side == Side.AI and OS.is_debug_build():
		print(
			"AI REVERSAL | setup=%s chance=%.1f result=%s" % [
				String(action_id),
				float(profile.get("ai_success_chance", 25.0)),
				"SUCCESS" if result == MatchInteractionModel.InputResult.SUCCESS else "FAIL",
			],
		)
	return result


func _apply_clean_setup_positions(
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> void:
	_apply_projected_setup_state(action_id, actor, target)


func _apply_reversed_setup_positions(
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> void:
	match action_id:
		SetupActionsMenu.IRISH_WHIP:
			target.set_motion_state(WrestlerResource.MotionState.STATIONARY)
			_set_rope_rebound_state(actor)
		SetupActionsMenu.THROW_INTO_CORNER:
			target.set_match_state(
				WrestlerResource.Position.STANDING,
				WrestlerResource.Orientation.FRONT,
				WrestlerResource.Area.IN_RING,
				WrestlerResource.MotionState.STATIONARY,
			)
			_set_corner_state(actor)
		SetupActionsMenu.PICK_OPPONENT_UP:
			actor.set_match_state(
				WrestlerResource.Position.GROUNDED,
				WrestlerResource.Orientation.FACE_UP,
				actor.current_area,
				WrestlerResource.MotionState.STATIONARY,
			)
			target.set_motion_state(WrestlerResource.MotionState.STATIONARY)
		SetupActionsMenu.GRAPPLE_OPPONENT:
			_set_neutral_ring_stance(actor)
			_set_neutral_ring_stance(target)
		SetupActionsMenu.TAUNT:
			if actor.current_area == WrestlerResource.Area.TOP_ROPE:
				actor.set_match_state(
					WrestlerResource.Position.GROUNDED,
					WrestlerResource.Orientation.FACE_UP,
					WrestlerResource.Area.IN_RING,
					WrestlerResource.MotionState.STATIONARY,
				)
			elif actor.current_area == WrestlerResource.Area.APRON:
				_set_neutral_ring_stance(actor)
			else:
				actor.set_motion_state(WrestlerResource.MotionState.STATIONARY)


func _apply_successful_taunt(actor: MatchSideState) -> void:
	var stamina_reward := 4.0
	var momentum_reward := 5.0
	var next_move_bonus := 3.0
	match actor.current_area:
		WrestlerResource.Area.APRON:
			stamina_reward = 3.0
			momentum_reward = 7.0
			next_move_bonus = 4.0
		WrestlerResource.Area.TOP_ROPE:
			stamina_reward = 2.0
			momentum_reward = 9.0
			next_move_bonus = 5.0
	var recovered := actor.recover_stamina(stamina_reward)
	var momentum_before := actor.momentum
	actor.add_momentum(momentum_reward)
	var momentum_gained := actor.momentum - momentum_before
	actor.taunt_stamina_recovered += recovered
	actor.taunt_momentum_gained += momentum_gained
	var pending_before := actor.pending_taunt_momentum_bonus
	actor.pending_taunt_momentum_bonus = maxf(pending_before, next_move_bonus)
	actor.taunt_bonus_momentum_granted += actor.pending_taunt_momentum_bonus - pending_before


func _taunt_success_log_message(side: int, actor: MatchSideState, target: MatchSideState) -> String:
	var actor_name := _side_name(side)
	if actor.current_area == WrestlerResource.Area.TOP_ROPE:
		var top_rope_lines := [
			"%s takes a moment on the top rope, soaking in the reaction.",
			"%s rises above the ring and plays to the crowd from the top turnbuckle.",
		]
		return str(top_rope_lines[randi() % top_rope_lines.size()]) % actor_name
	if actor.current_area == WrestlerResource.Area.APRON:
		var apron_lines := [
			"%s showboats from the apron and feeds off the crowd.",
			"%s pauses on the apron, daring the crowd to get louder.",
		]
		return str(apron_lines[randi() % apron_lines.size()]) % actor_name
	if actor.stamina < 30.0 or actor.fatigue >= 70.0:
		return "%s shakes out their arms and fights to recover their composure." % actor_name
	if target.current_position == WrestlerResource.Position.GROUNDED:
		return "%s stalks around the ring, daring their opponent to get up." % actor_name
	if actor.momentum >= 75.0:
		return "%s fires up and demands a louder reaction from the crowd." % actor_name
	var standing_lines := [
		"%s plays to the crowd.",
		"%s takes a few precious seconds to showboat.",
		"%s fires themselves up in the centre of the ring.",
	]
	return str(standing_lines[randi() % standing_lines.size()]) % actor_name


func _taunt_interrupted_log_message(side: int, original_area: int) -> String:
	var actor := _side_name(side)
	var defender := _side_name(_opponent_side(side))
	if original_area == WrestlerResource.Area.TOP_ROPE:
		return "%s poses on the top rope, but %s recovers and shakes them down!" % [actor, defender]
	if original_area == WrestlerResource.Area.APRON:
		return "%s plays to the crowd from the apron, but %s cuts them off and forces them back inside!" % [actor, defender]
	var interrupted_lines := [
		"%s plays to the crowd, but %s cuts them off!",
		"%s wastes too much time taunting, and %s takes advantage.",
		"%s taunts too long and gets caught by %s.",
	]
	return str(interrupted_lines[randi() % interrupted_lines.size()]) % [actor, defender]


func _reversed_setup_log_message(side: int, action_id: StringName) -> String:
	var actor := _side_name(side)
	var defender := _side_name(_opponent_side(side))
	match action_id:
		SetupActionsMenu.IRISH_WHIP:
			return "%s reverses the Irish whip and sends %s into the ropes instead." % [defender, actor]
		SetupActionsMenu.THROW_INTO_CORNER:
			return "%s reverses the throw and drives %s into the corner instead." % [defender, actor]
		SetupActionsMenu.PICK_OPPONENT_UP:
			return "%s reaches down, but %s was waiting and pulls them into a counter." % [actor, defender]
		SetupActionsMenu.GRAPPLE_OPPONENT:
			return "%s slips the grapple and takes control from %s." % [defender, actor]
		SetupActionsMenu.TAUNT:
			return _taunt_interrupted_log_message(side, _state_for_side(side).current_position)
	return "%s counters the setup and takes control." % defender


func _setup_action_short_name(action_id: StringName) -> String:
	return str(MatchSetupStateRules.action_details(action_id).get("title", "Setup Action")).capitalize()


func start_pin_sequence(
	attacker_side: int,
	defender_side: int,
	embedded_pinning_move: bool = false,
) -> void:
	if match_ended or is_resolving_action:
		return
	if not embedded_pinning_move and not _can_pin(attacker_side):
		return
	is_resolving_action = true
	if attacker_side == Side.PLAYER:
		_player_setup_intent = &""
	pin_sequence_active = true
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	attacker.pin_attempts += 1
	_clear_selected_move()
	if not embedded_pinning_move:
		advance_match_clock()
	_active_pin_context = _build_pin_context(attacker_side, defender_side)
	_recent_reversal_side = Side.NONE
	add_match_log_entry("%s hooks the leg!" % _side_name(attacker_side), Color(0.25, 0.64, 1.0, 1.0))
	_emit_ring_state({
		"reason": "pin started",
		"actor_id": _ring_participant_id(attacker_side),
		"target_id": _ring_participant_id(defender_side),
		"shared_interaction": true,
	})
	_emit_ring_event(&"pin_started", attacker_side, defender_side)
	if bool(_active_pin_context.get("flash_qualified", false)):
		add_match_log_entry(
			"%s catches %s by surprise!" % [_side_name(attacker_side), _side_name(defender_side)],
			Color(0.95, 0.78, 0.22, 1.0),
		)
	refresh_match_ui()
	for count in range(1, 4):
		if match_ended:
			_active_pin_context.clear()
			return
		if count < 3:
			add_match_log_entry(_count_word(count) + "!", Color(0.95, 0.78, 0.22, 1.0))
		var result := await resolve_pin_count(attacker_side, defender_side, count)
		if result < 0 or match_ended:
			pin_sequence_active = false
			is_resolving_action = false
			_active_pin_context.clear()
			_emit_ring_event(&"pin_ended", attacker_side, defender_side)
			if not match_ended:
				refresh_match_ui()
				_resume_controller_after_cancel(attacker_side)
				ensure_match_can_continue("cancelled pin interaction")
			return
		if result == MatchInteractionModel.InputResult.SUCCESS:
			var defender_momentum := [5.0, 8.0, 12.0]
			var attacker_momentum := [-3.0, -5.0, -8.0]
			defender.add_momentum(float(defender_momentum[count - 1]))
			attacker.add_momentum(float(attacker_momentum[count - 1]))
			defender.kickouts += 1
			last_action_result = ActionResult.KICKOUT
			if count == 1 and bool(_active_pin_context.get("early_normal_protection", false)):
				add_match_log_entry(
					"%s kicks out at one, nowhere near finished yet." % _side_name(defender_side),
				)
			elif count == 3:
				add_match_log_entry(
					"THREE—NO! %s kicks out at the last possible moment!" % _side_name(defender_side),
					Color(0.95, 0.78, 0.22, 1.0),
				)
			else:
				add_match_log_entry("%s kicks out at %s!" % [_side_name(defender_side), _count_phrase(count)])
			if count == 2:
				add_match_log_entry("%s nearly had it." % _side_name(attacker_side))
			pin_sequence_active = false
			is_resolving_action = false
			_active_pin_context.clear()
			_emit_ring_event(&"pin_ended", attacker_side, defender_side)
			_set_controller(ControlState.NEUTRAL)
			ensure_match_can_continue("pin kickout")
			return
		if count == 3:
			break
		await get_tree().create_timer(0.2).timeout
	finish_move = _active_pin_context.get("last_move") as MoveResource
	end_match(attacker_side, defender_side, FinishType.PINFALL, finish_move)


func resolve_pin_count(attacker_side: int, defender_side: int, count: int) -> int:
	var bases := [28.0, 18.0, 9.0]
	var times := [1.8, 1.4, 1.1]
	var values := _pin_pressure_and_resistance(attacker_side, defender_side, count)
	var profile := MatchInteractionModel.build_pin_profile(
		float(bases[count - 1]),
		float(times[count - 1]),
		float(values.pressure),
		float(values.resistance),
		count,
	)
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	attacker.finish_pressure_total += float(values.pressure) - float(values.resistance)
	attacker.finish_pressure_samples += 1
	defender.kickout_meter_attempts += 1
	if defender_side != Side.PLAYER:
		var simulated_result := _simulate_binary_result(float(profile.get("ai_success_chance", 20.0)))
		if simulated_result == MatchInteractionModel.InputResult.SUCCESS:
			defender.kickout_meter_successes += 1
		return simulated_result
	var request := profile.duplicate(true)
	request["title"] = "KICK OUT — %s!" % _count_word(count)
	request["prompt"] = "Stop the moving marker inside the gold zone."
	request["button_text"] = "KICK OUT"
	var response := await _run_visible_control_meter(request)
	if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
		return -1
	var result := int(response.get("result", MatchInteractionModel.InputResult.FAIL))
	if result == MatchInteractionModel.InputResult.SUCCESS:
		defender.kickout_meter_successes += 1
	elif bool(response.get("timed_out", false)):
		defender.kickout_meter_timeouts += 1
	elif result == MatchInteractionModel.InputResult.NEAR_MISS:
		defender.kickout_meter_near_misses += 1
	return result


func _pin_pressure_and_resistance(attacker_side: int, defender_side: int, count: int) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var last_move := _active_pin_context.get("last_move") as MoveResource
	var impact := float(last_move.move_impact) if last_move != null else 1.0
	var pressure := attacker.momentum + impact * 4.0 + defender.fatigue - defender.stamina + _match_finish_pressure()
	if bool(_active_pin_context.get("last_move_was_finisher", false)):
		pressure += 35.0
	if bool(_active_pin_context.get("flash_success", false)):
		pressure += 65.0
	if bool(_active_pin_context.get("squash_qualified", false)):
		pressure += 45.0
	if defender.head_hp < 40.0:
		pressure += 10.0
	if defender.body_hp < 40.0:
		pressure += 10.0
	var resistance := defender.stamina + defender.momentum - defender.fatigue
	resistance -= float(MatchInteractionModel.build_late_match_profile(_match_time_seconds).recovery_penalty)
	if bool(_active_pin_context.get("early_normal_protection", false)):
		resistance += 120.0
	elif bool(_active_pin_context.get("under_ten_protection", false)):
		resistance += 55.0
	if bool(_active_pin_context.get("flash_success", false)):
		resistance -= 35.0
	if bool(_active_pin_context.get("squash_qualified", false)):
		resistance -= 25.0
	match count:
		1:
			resistance += 30.0
		2:
			resistance += 5.0
		3:
			resistance -= 20.0
	return {"pressure": pressure, "resistance": resistance}


func _legacy_start_pin_sequence(attacker_side: int, defender_side: int) -> void:
	if not _can_pin(attacker_side) or match_ended or is_resolving_action:
		return
	is_resolving_action = true
	if attacker_side == Side.PLAYER:
		_player_setup_intent = &""
	pin_sequence_active = true
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	attacker.pin_attempts += 1
	_clear_selected_move()
	advance_match_clock()
	_active_pin_context = _build_pin_context(attacker_side, defender_side)
	_recent_reversal_side = Side.NONE
	add_match_log_entry("%s hooks the leg!" % _side_name(attacker_side), Color(0.25, 0.64, 1.0, 1.0))
	if bool(_active_pin_context.get("flash_qualified", false)):
		add_match_log_entry(
			"%s catches %s by surprise!" % [_side_name(attacker_side), _side_name(defender_side)],
			Color(0.95, 0.78, 0.22, 1.0),
		)
	refresh_match_ui()
	var temporary_resistance := 0.0
	for count in range(1, 4):
		if match_ended:
			_active_pin_context.clear()
			return
		if count < 3:
			add_match_log_entry(_count_word(count) + "!", Color(0.95, 0.78, 0.22, 1.0))
		var result := await _legacy_resolve_pin_count(attacker_side, defender_side, count, temporary_resistance)
		if result == ContestTimingBar.GREEN_RESULT:
			defender.add_momentum(5.0)
			attacker.add_momentum(-3.0)
			defender.kickouts += 1
			last_action_result = ActionResult.KICKOUT
			if count == 1 and bool(_active_pin_context.get("early_normal_protection", false)):
				add_match_log_entry(
					"%s kicks out at one, nowhere near finished yet." % _side_name(defender_side),
				)
			elif count == 3:
				add_match_log_entry(
					"THREE—NO! %s kicks out at the last possible moment!" % _side_name(defender_side),
					Color(0.95, 0.78, 0.22, 1.0),
				)
			else:
				add_match_log_entry("%s kicks out at %s!" % [_side_name(defender_side), _count_phrase(count)])
			if count == 2:
				add_match_log_entry("%s nearly had it." % _side_name(attacker_side))
			pin_sequence_active = false
			is_resolving_action = false
			_active_pin_context.clear()
			_set_controller(ControlState.NEUTRAL)
			ensure_match_can_continue("legacy pin kickout")
			return
		if count == 3:
			if result == ContestTimingBar.YELLOW_RESULT:
				add_match_log_entry(
					"%s twists under the cover, but they cannot break free." % _side_name(defender_side),
				)
			break
		elif result == ContestTimingBar.YELLOW_RESULT:
			temporary_resistance = 10.0
			add_match_log_entry("%s twists under the cover, but the referee keeps counting." % _side_name(defender_side))
		else:
			temporary_resistance = 0.0
		await get_tree().create_timer(0.2).timeout
	finish_move = _active_pin_context.get("last_move") as MoveResource
	end_match(attacker_side, defender_side, FinishType.PINFALL, finish_move)


func _legacy_resolve_pin_count(
	attacker_side: int,
	defender_side: int,
	count: int,
	temporary_resistance: float = 0.0,
) -> StringName:
	var probabilities := _pin_probabilities(attacker_side, defender_side, count, temporary_resistance)
	var time_limits := [2.2, 1.8, 1.4]
	var timeout_message := "%s cannot kick out in time." % _side_name(defender_side)
	if count < 3:
		timeout_message = "%s reacts too late to stop the count." % _side_name(defender_side)
	return await _resolve_probability_prompt(
		defender_side,
		probabilities,
		"KICK OUT — COUNT %d" % count,
		"Stop the marker in green to kick out.",
		float(time_limits[count - 1]),
		PackedStringArray(["COUNT", "STRUGGLE", "KICK OUT"]),
		timeout_message,
	)


func start_submission_sequence(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	contested_lock: bool = false,
	target_resolution: Dictionary = {},
) -> void:
	submission_sequence_active = true
	is_resolving_action = true
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, attacker.target_focus_body_part, defender)
	_active_submission_target_resolution = target_resolution.duplicate(true)
	if contested_lock:
		_apply_move_result_state(attacker, move, true)
		_apply_move_result_state(defender, move, false)
	add_match_log_entry(
		"%s traps %s in \"%s\", attacking the %s!" % [
			_side_name(attacker_side),
			_side_name(defender_side),
			_move_name(move),
			MoveTargetResolver.part_label(int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))).to_lower(),
		],
		Color(0.95, 0.78, 0.22, 1.0) if move.is_finisher else Color(0.84, 0.87, 0.92, 1.0),
	)
	_emit_ring_state({
		"reason": "submission started",
		"actor_id": _ring_participant_id(attacker_side),
		"target_id": _ring_participant_id(defender_side),
		"shared_interaction": true,
	})
	_emit_ring_event(
		&"submission_started",
		attacker_side,
		defender_side,
		{
			"label": _move_name(move),
			"is_finisher": move.is_finisher,
			"is_signature": move in attacker.wrestler.signature_moves,
		},
	)
	var squash_context := _is_true_squash_context(attacker, defender, move)
	var submission_context := MatchInteractionModel.build_submission_context(
		attacker,
		defender,
		move,
		_match_time_seconds,
		contested_lock,
		squash_context,
		target_resolution,
	)
	var start_marker := float(submission_context.get("start_marker", 50.0))
	var attacker_score := float(submission_context.get("attacker_score", 50.0))
	var defender_score := float(submission_context.get("defender_score", 50.0))
	attacker.finish_pressure_total += float(submission_context.get("pressure_bonus", 0.0)) - float(submission_context.get("resistance_bonus", 0.0))
	attacker.finish_pressure_samples += 1
	var player_is_attacker := attacker_side == Side.PLAYER
	var request := {
		"title": "SUBMISSION STRUGGLE",
		"move_name": _move_name(move),
		"prompt": "Tap repeatedly to drive the marker toward %s." % ("TAP OUT" if player_is_attacker else "ESCAPE"),
		"button_text": "TAP FOR PRESSURE" if player_is_attacker else "TAP TO ESCAPE",
		"start_marker": start_marker,
		"stall_failsafe_seconds": 30.0,
		"player_direction": 1.0 if player_is_attacker else -1.0,
		"player_score": attacker_score if player_is_attacker else defender_score,
		"ai_score": defender_score if player_is_attacker else attacker_score,
		"tap_out_threshold": float(submission_context.get("tap_out_threshold", 90.0)),
		"escape_threshold": float(submission_context.get("escape_threshold", 10.0)),
		"resolution_speed_multiplier": submission_resolution_speed_multiplier,
	}
	_active_submission_attacker_side = attacker_side
	_active_submission_defender_side = defender_side
	_active_submission_move = move
	_begin_visible_interaction()
	var response := await _interaction_overlay.run_submission_tug(request)
	_end_visible_interaction()
	_active_submission_attacker_side = Side.NONE
	_active_submission_defender_side = Side.NONE
	_active_submission_move = null
	_active_submission_target_resolution.clear()
	if match_ended:
		return
	if bool(response.get("stale", false)):
		submission_sequence_active = false
		is_resolving_action = false
		_emit_ring_event(&"submission_ended", attacker_side, defender_side)
		_resume_controller_after_cancel(attacker_side)
		ensure_match_can_continue("cancelled submission tug")
		return
	var elapsed := float(response.get("elapsed", 0.0))
	attacker.submission_struggle_seconds += elapsed
	defender.submission_struggle_seconds += elapsed
	var outcome := int(response.get("outcome", MatchInteractionModel.CombinedOutcome.BOTCH_OR_SCRAMBLE))
	match outcome:
		MatchInteractionModel.CombinedOutcome.TAP_OUT:
			attacker.submission_wins += 1
			attacker.submission_struggle_wins += 1
			defender.submission_struggle_losses += 1
			last_action_result = ActionResult.TAP_OUT
			_emit_ring_event(&"submission_ended", attacker_side, defender_side)
			end_match(attacker_side, defender_side, FinishType.SUBMISSION, move)
			return
		MatchInteractionModel.CombinedOutcome.SUBMISSION_ESCAPE:
			defender.submission_escapes += 1
			defender.submission_struggle_wins += 1
			attacker.submission_struggle_losses += 1
			defender.add_momentum(8.0)
			attacker.add_momentum(-5.0)
			last_action_result = ActionResult.SUBMISSION_ESCAPE
			add_match_log_entry("%s claws free and breaks the hold." % _side_name(defender_side))
			submission_sequence_active = false
			is_resolving_action = false
			_emit_ring_event(&"submission_ended", attacker_side, defender_side)
			_set_controller(_control_for_side(defender_side))
		MatchInteractionModel.CombinedOutcome.SUBMISSION_CONTINUES:
			attacker.submission_struggle_wins += 1
			defender.submission_struggle_losses += 1
			defender.add_fatigue(3.0)
			attacker.add_momentum(3.0)
			add_match_log_entry(
				"%s cranks back harder, but %s survives the pressure." % [
					_side_name(attacker_side),
					_side_name(defender_side),
				],
			)
			submission_sequence_active = false
			is_resolving_action = false
			_emit_ring_event(&"submission_ended", attacker_side, defender_side)
			_set_controller(_control_for_side(attacker_side))
		_:
			attacker.submission_struggle_losses += 1
			defender.submission_struggle_wins += 1
			attacker.botches_scrambles += 1
			last_action_result = ActionResult.BOTCH_OR_SCRAMBLE
			add_match_log_entry("The hold breaks down into a scramble.")
			submission_sequence_active = false
			is_resolving_action = false
			_emit_ring_event(&"submission_ended", attacker_side, defender_side)
			_set_controller(ControlState.NEUTRAL)
	refresh_match_ui()
	ensure_match_can_continue("submission resolution")


func _on_submission_damage_tick(_request_id: int, marker: float) -> void:
	if not submission_sequence_active or _active_submission_move == null:
		return
	var attacker := _state_for_side(_active_submission_attacker_side)
	var defender := _state_for_side(_active_submission_defender_side)
	if attacker == null or defender == null:
		return
	var damage := 0.5 + maxf(0.0, marker - 50.0) / 50.0 * 0.75
	var parts: Array = _active_submission_target_resolution.get("parts", [MoveResource.MoveTargetParts.BODY])
	var weights: Dictionary = _active_submission_target_resolution.get("damage_weights", {})
	var hp_before := defender.total_hp()
	var part_hp_before: Dictionary = {}
	for part in parts:
		var part_id := int(part)
		part_hp_before[part_id] = defender.get_part_hp(part_id)
		defender.damage_part(part_id, damage * float(weights.get(part_id, 1.0)))
	var applied := maxf(0.0, hp_before - defender.total_hp())
	defender.damage_taken += applied
	attacker.damage_dealt += applied
	var threshold_message := ""
	for raw_part in parts:
		var part := int(raw_part)
		var part_damage := maxf(0.0, float(part_hp_before.get(part, 100.0)) - defender.get_part_hp(part))
		attacker.target_damage_dealt[part] = float(attacker.target_damage_dealt.get(part, 0.0)) + part_damage
		var crossed := defender.mark_crossed_thresholds(
			part,
			float(part_hp_before.get(part, defender.get_part_hp(part))),
			defender.get_part_hp(part),
		)
		if threshold_message.is_empty() and (20 in crossed or 0 in crossed):
			threshold_message = "%s's %s is giving way under the submission pressure." % [
				_wrestler_name(defender.wrestler),
				MoveTargetResolver.part_label(part).to_lower(),
			]
	if not threshold_message.is_empty() and _match_time_seconds - defender.last_body_commentary_time >= 60:
		defender.last_body_commentary_time = _match_time_seconds
		add_match_log_entry(threshold_message, Color(1.0, 0.68, 0.28, 1.0))
	refresh_match_ui()


func _on_submission_state_changed(_request_id: int, state: StringName) -> void:
	if not submission_sequence_active or _active_submission_move == null:
		return
	match state:
		SubmissionTugInteraction.STATE_ATTACKER_GAINING:
			add_match_log_entry("%s cranks back harder on the hold." % _side_name(_active_submission_attacker_side))
		SubmissionTugInteraction.STATE_DEFENDER_GAINING:
			add_match_log_entry("%s fights toward an escape." % _side_name(_active_submission_defender_side))
		SubmissionTugInteraction.STATE_NEAR_TAP:
			add_match_log_entry("%s is fading fast." % _side_name(_active_submission_defender_side))
		SubmissionTugInteraction.STATE_NEAR_ESCAPE:
			add_match_log_entry("%s is almost free." % _side_name(_active_submission_defender_side))


func _legacy_start_submission_sequence(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
) -> void:
	submission_sequence_active = true
	is_resolving_action = true
	add_match_log_entry(
		"%s traps %s in \"%s\"!" % [_side_name(attacker_side), _side_name(defender_side), _move_name(move)],
		Color(0.95, 0.78, 0.22, 1.0) if move.is_finisher else Color(0.84, 0.87, 0.92, 1.0),
	)
	var defender := _state_for_side(defender_side)
	var early_safety := _submission_early_safety_level(defender, move)
	var escape_progress := 1 if early_safety >= 2 else 0
	var tap_pressure := 0
	var tap_pressure_required := 3 if early_safety > 0 else 2
	for stage in range(1, 4):
		if match_ended:
			return
		var result := await _legacy_resolve_submission_stage(attacker_side, defender_side, move, stage)
		var attacker := _state_for_side(attacker_side)
		defender = _state_for_side(defender_side)
		if result == ContestTimingBar.GREEN_RESULT:
			escape_progress += 1
			add_match_log_entry("%s shifts their weight and starts to slip free." % _side_name(defender_side))
		elif result == ContestTimingBar.YELLOW_RESULT:
			defender.add_fatigue(1.0)
			add_match_log_entry("%s grits through the pressure, but the hold stays locked." % _side_name(defender_side))
		else:
			tap_pressure += 1
			defender.add_fatigue(3.0)
			var hp_before := defender.total_hp()
			_apply_submission_stage_damage(defender, move)
			var stage_damage := maxf(0.0, hp_before - defender.total_hp())
			defender.damage_taken += stage_damage
			attacker.damage_dealt += stage_damage
			attacker.add_momentum(2.0)
			add_match_log_entry("%s wrenches back harder on the hold." % _side_name(attacker_side))
		refresh_match_ui()

	if escape_progress >= 2:
		_state_for_side(defender_side).add_momentum(8.0)
		_state_for_side(attacker_side).add_momentum(-5.0)
		_state_for_side(defender_side).submission_escapes += 1
		last_action_result = ActionResult.SUBMISSION_ESCAPE
		add_match_log_entry("%s claws free and breaks the hold." % _side_name(defender_side))
		submission_sequence_active = false
		is_resolving_action = false
		_set_controller(_control_for_side(defender_side))
	elif tap_pressure >= tap_pressure_required:
		last_action_result = ActionResult.TAP_OUT
		end_match(attacker_side, defender_side, FinishType.SUBMISSION, move)
	else:
		_state_for_side(defender_side).add_momentum(8.0)
		_state_for_side(attacker_side).add_momentum(-5.0)
		_state_for_side(defender_side).submission_escapes += 1
		last_action_result = ActionResult.SUBMISSION_ESCAPE
		add_match_log_entry("%s survives the hold, but both wrestlers are left scrambling." % _side_name(defender_side))
		submission_sequence_active = false
		is_resolving_action = false
		_set_controller(ControlState.NEUTRAL)
	if not match_ended:
		ensure_match_can_continue("legacy submission exit")


func _legacy_resolve_submission_stage(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	stage: int,
) -> StringName:
	var probabilities := _submission_probabilities(attacker_side, defender_side, move)
	return await _resolve_probability_prompt(
		defender_side,
		probabilities,
		"SUBMISSION ESCAPE — STAGE %d OF 3" % stage,
		"Stop the marker in green to build escape progress.",
		1.8,
		PackedStringArray(["PRESSURE", "SURVIVE", "ESCAPE"]),
		"%s fades under the pressure of the hold." % _side_name(defender_side),
	)


func end_match(
	winning_side: int,
	losing_side: int,
	result_type: int,
	move: MoveResource = null,
	reason: String = "",
	action_name: String = "",
) -> void:
	if match_ended:
		return
	match_ended = true
	winner_side = winning_side
	loser_side = losing_side
	finish_type = result_type
	finish_move = move
	finish_reason = reason
	finish_action = action_name
	final_time = _match_time_seconds
	is_resolving_action = false
	contest_prompt_active = false
	pin_sequence_active = false
	submission_sequence_active = false
	_referee_count_active = false
	_referee_count_pending_resolution = false
	_update_referee_count_presentation()
	_interaction_overlay.close_interaction(true)
	_moves_radial_menu.close()
	_setup_actions_menu.close()
	var result_message := ""
	if result_type == FinishType.PINFALL:
		if (
			_match_time_seconds >= 1200
			and move != null
			and not move.is_finisher
			and move.move_impact <= 6
			and not bool(_active_pin_context.get("flash_success", false))
			and not bool(_active_pin_context.get("squash_qualified", false))
		):
			add_match_log_entry(
				"Exhaustion takes over; %s cannot summon one more escape after \"%s\"." % [
					_side_name(losing_side),
					_move_name(move),
				],
			)
		if bool(_active_pin_context.get("flash_success", false)):
			result_message = "THREE! %s steals it with a flash pin!" % _side_name(winning_side)
		elif bool(_active_pin_context.get("squash_qualified", false)) and _match_time_seconds < 600:
			result_message = "THREE! %s puts %s away in dominant fashion." % [
				_side_name(winning_side),
				_side_name(losing_side),
			]
		else:
			result_message = "THREE! %s defeats %s by pinfall" % [_side_name(winning_side), _side_name(losing_side)]
			if move != null:
				result_message += " after \"%s\"" % _move_name(move)
			result_message += "."
	elif result_type == FinishType.SUBMISSION:
		result_message = "%s taps out! %s wins by submission." % [_side_name(losing_side), _side_name(winning_side)]
	elif result_type == FinishType.COUNT_OUT:
		result_message = "%s wins by count-out." % _side_name(winning_side)
	elif result_type == FinishType.DISQUALIFICATION:
		result_message = "%s wins by disqualification." % _side_name(winning_side)
	elif result_type == FinishType.DOUBLE_COUNT_OUT:
		result_message = "The match ends in a double count-out."
	elif result_type == FinishType.DOUBLE_DISQUALIFICATION:
		result_message = "The referee throws the match out after a double disqualification."
	elif result_type == FinishType.DRAW:
		result_message = "The match ends in a draw."
	else:
		result_message = "The match is declared a no contest."
	add_match_log_entry(result_message, Color(0.95, 0.78, 0.22, 1.0))
	_active_pin_context.clear()
	_result_banner.text = (
		"%s WINS BY %s" % [_side_name(winning_side), _finish_type_name(result_type).to_upper()]
		if winning_side != Side.NONE
		else _finish_type_name(result_type).to_upper()
	)
	_result_banner.visible = true
	_set_controller(ControlState.MATCH_ENDED, false)
	refresh_match_ui()
	_emit_ring_event(
		&"match_ended",
		winning_side,
		losing_side,
		{"winner_id": _ring_participant_id(winning_side), "result": _finish_type_name(result_type)},
	)
	_latest_match_report = _build_match_report()
	player_side_state.held_weapon = null
	player_side_state.held_weapon_uses_remaining = 0
	ai_side_state.held_weapon = null
	ai_side_state.held_weapon_uses_remaining = 0
	_dropped_weapon = null
	_dropped_weapon_uses_remaining = 0
	_view_report_button.visible = false
	_new_match_button.visible = true
	_show_match_result_after_delay(_turn_generation)
	if OS.is_debug_build():
		print(_ai_decision_engine.debug_summary(ai_side_state))


func _finish_type_name(value: int) -> String:
	match value:
		FinishType.PINFALL: return "Pinfall"
		FinishType.SUBMISSION: return "Submission"
		FinishType.COUNT_OUT: return "Count-Out"
		FinishType.DISQUALIFICATION: return "Disqualification"
		FinishType.DOUBLE_COUNT_OUT: return "Double Count-Out"
		FinishType.DOUBLE_DISQUALIFICATION: return "Double Disqualification"
		FinishType.DRAW: return "Draw"
		FinishType.NO_CONTEST: return "No Contest"
	return "Not Set"


func _show_match_result_after_delay(generation: int) -> void:
	await get_tree().create_timer(MATCH_RESULT_REVEAL_DELAY_SECONDS).timeout
	if not match_ended or generation != _turn_generation or _latest_match_report.is_empty():
		return
	_view_report_button.visible = true
	_match_result_popup.open_result(_build_match_result_summary())


func _resolve_probability_prompt(
	defender_side: int,
	probabilities: Dictionary,
	title: String,
	prompt: String,
	time_limit_seconds: float = 2.0,
	band_labels: PackedStringArray = PackedStringArray(),
	timeout_message: String = "",
) -> StringName:
	if defender_side != Side.PLAYER:
		return _simulate_probability_result(probabilities)
	contest_prompt_active = true
	refresh_match_ui()
	_contest_timing_bar.open_contest(probabilities, title, prompt, time_limit_seconds, band_labels)
	var result: StringName = await _contest_timing_bar.result_selected
	if _contest_timing_bar.last_result_was_timeout and not timeout_message.is_empty() and not match_ended:
		add_match_log_entry(timeout_message, Color(1.0, 0.5, 0.35, 1.0))
	contest_prompt_active = false
	refresh_match_ui()
	return result


func _contest_probabilities(attacker_side: int, defender_side: int, move: MoveResource) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var red := 55.0
	var yellow := 30.0
	var green := 15.0
	if defender.stamina >= 80.0:
		green += 8.0
		red -= 8.0
	elif defender.stamina < 25.0:
		green -= 10.0
		red += 10.0
	elif defender.stamina < 50.0:
		green -= 5.0
		red += 5.0
	if defender.fatigue >= 70.0:
		green -= 10.0
		red += 10.0
	elif defender.fatigue >= 40.0:
		green -= 5.0
		red += 5.0
	if defender.momentum >= 70.0:
		green += 8.0
		red -= 8.0
	elif defender.momentum >= 40.0:
		green += 4.0
		red -= 4.0
	elif defender.momentum < 20.0:
		green -= 4.0
		red += 4.0
	if attacker.momentum >= 70.0:
		green -= 8.0
		red += 8.0
	elif attacker.momentum >= 40.0:
		green -= 4.0
		red += 4.0
	if move.move_impact >= 8:
		green -= 5.0
		red += 5.0
	elif move.move_impact <= 3:
		yellow += 5.0
		red -= 5.0
	if move.is_finisher:
		green -= 10.0
		red += 10.0
	if _is_high_risk(move):
		green += 5.0
		yellow -= 5.0
	var target_hp := defender.average_target_hp(move.move_target_parts)
	if target_hp < 25.0:
		green -= 5.0
		red += 5.0
	elif target_hp < 50.0:
		green -= 3.0
		red += 3.0
	if _match_time_seconds >= 600:
		green -= 2.0
		red += 2.0
	return _normalize_probabilities(red, yellow, green)


func _pin_probabilities(
	attacker_side: int,
	defender_side: int,
	count: int,
	temporary_resistance: float,
) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var last_move := _active_pin_context.get("last_move") as MoveResource
	var impact := float(last_move.move_impact) if last_move != null else 1.0
	var pressure := (
		attacker.momentum
		+ impact * 4.0
		+ defender.fatigue
		- defender.stamina
		+ _match_finish_pressure()
	)
	if bool(_active_pin_context.get("last_move_was_finisher", false)):
		pressure += 35.0
	if bool(_active_pin_context.get("flash_success", false)):
		pressure += 65.0
	if bool(_active_pin_context.get("squash_qualified", false)):
		pressure += 45.0
	if defender.head_hp < 40.0:
		pressure += 10.0
	if defender.body_hp < 40.0:
		pressure += 10.0
	var resistance := defender.stamina + defender.momentum - defender.fatigue + temporary_resistance
	if bool(_active_pin_context.get("early_normal_protection", false)):
		resistance += 120.0
	elif bool(_active_pin_context.get("under_ten_protection", false)):
		resistance += 55.0
	if bool(_active_pin_context.get("flash_success", false)):
		resistance -= 35.0
	if bool(_active_pin_context.get("squash_qualified", false)):
		resistance -= 25.0
	match count:
		1:
			resistance += 30.0
		2:
			resistance += 5.0
		3:
			resistance -= 20.0
	return _pressure_probabilities(pressure, resistance, true)


func _submission_probabilities(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var pressure := (
		attacker.momentum
		+ attacker.wrestler.skill
		+ float(move.move_impact * 5)
		+ defender.fatigue
		+ _match_finish_pressure()
	)
	if move.is_finisher:
		pressure += 35.0
	var target_hp := defender.lowest_target_hp(move.move_target_parts)
	if target_hp < 25.0:
		pressure += 30.0
	elif target_hp < 50.0:
		pressure += 15.0
	if defender.stamina < 30.0:
		pressure += 15.0
	var resistance := defender.stamina + defender.momentum + defender.wrestler.skill - defender.fatigue
	match _submission_early_safety_level(defender, move):
		2:
			resistance += 70.0
		1:
			resistance += 35.0
	return _pressure_probabilities(pressure, resistance, false)


func _build_pin_context(attacker_side: int, defender_side: int) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var last_move := _last_pin_move(attacker)
	var impact := last_move.move_impact if last_move != null else 0
	var last_move_was_finisher := last_move != null and last_move.is_finisher
	var reversal_catch := _recent_reversal_side == attacker_side
	var named_flash_move := last_move != null and _is_flash_pin_move(last_move)
	var high_momentum_catch := (
		last_move != null
		and impact <= 4
		and defender.momentum >= 75.0
	)
	var flash_qualified := named_flash_move or reversal_catch or high_momentum_catch
	var flash_chance := _flash_finish_chance()
	var flash_success := flash_qualified and randf() * 100.0 < flash_chance
	var squash_qualified := _is_squash_finish(attacker, defender, last_move)
	var big_move := impact >= 8
	var heavy_damage := _pin_has_heavy_damage(defender)
	var early_normal_protection := (
		_match_time_seconds < 300
		and not flash_success
		and not squash_qualified
		and not last_move_was_finisher
	)
	var under_ten_protection := (
		_match_time_seconds < 600
		and not early_normal_protection
		and not flash_success
		and not squash_qualified
		and not last_move_was_finisher
		and not big_move
		and not heavy_damage
	)
	return {
		"time_seconds": _match_time_seconds,
		"finish_pressure": _match_finish_pressure(),
		"flash_chance": flash_chance,
		"flash_qualified": flash_qualified,
		"flash_success": flash_success,
		"squash_qualified": squash_qualified,
		"last_move": last_move,
		"last_move_impact": impact,
		"last_move_was_finisher": last_move_was_finisher,
		"big_move": big_move,
		"heavy_damage": heavy_damage,
		"early_normal_protection": early_normal_protection,
		"under_ten_protection": under_ten_protection,
	}


func _last_pin_move(attacker: MatchSideState) -> MoveResource:
	if attacker == null:
		return null
	if attacker.last_action_result not in [ActionResult.CLEAN_SUCCESS, ActionResult.PARTIAL_DEFENCE]:
		return null
	return attacker.last_move_landed


func _match_finish_pressure() -> float:
	return float(MatchInteractionModel.build_late_match_profile(_match_time_seconds).finish_pressure)


func _flash_finish_chance() -> float:
	if _match_time_seconds >= 900:
		return 20.0
	if _match_time_seconds >= 600:
		return 15.0
	if _match_time_seconds >= 300:
		return 10.0
	return 5.0


func _is_flash_pin_move(move: MoveResource) -> bool:
	if move == null:
		return false
	if move.is_flash_pin:
		return true
	var move_name := move.move_name.to_lower().replace("’", "'")
	if move_name.contains("bomb") or move_name.contains("piledriver") or move_name.contains("powerbomb"):
		return false
	for term in [
		"roll-up",
		"roll up",
		"schoolboy",
		"backslide",
		"o'connor",
		"oconnor",
		"small package",
		"cradle",
		"victory roll",
		"sunset flip",
		"rolling crucifix",
		"surprise pin",
	]:
		if move_name.contains(term):
			return true
	return false


func _is_squash_finish(
	attacker: MatchSideState,
	defender: MatchSideState,
	last_move: MoveResource,
) -> bool:
	if attacker == null or defender == null or last_move == null:
		return false
	if last_move.is_finisher:
		return true
	var dominant_momentum := attacker.momentum >= 80.0 and defender.momentum <= 20.0
	var little_defender_offence := defender.moves_landed <= 1 and defender.damage_dealt < 20.0
	var sustained_attacker_offence := attacker.moves_landed >= 3
	var defender_worn_down := (
		defender.fatigue >= 55.0
		or defender.fatigue - attacker.fatigue >= 20.0
		or defender.stamina <= 30.0
	)
	return (
		dominant_momentum
		and little_defender_offence
		and sustained_attacker_offence
		and defender_worn_down
		and last_move.move_impact >= 8
	)


func _is_true_squash_context(
	attacker: MatchSideState,
	defender: MatchSideState,
	last_move: MoveResource,
) -> bool:
	if attacker == null or defender == null or last_move == null:
		return false
	var dominant_momentum := attacker.momentum >= 80.0 and defender.momentum <= 20.0
	var little_defender_offence := defender.moves_landed <= 1 and defender.damage_dealt < 20.0
	var sustained_attacker_offence := attacker.moves_landed >= 3
	var meaningful_damage := defender.damage_taken >= 30.0 or defender.total_hp() <= 450.0
	return dominant_momentum and little_defender_offence and sustained_attacker_offence and meaningful_damage


func _pin_has_heavy_damage(defender: MatchSideState) -> bool:
	return (
		defender.total_hp() <= 390.0
		or defender.head_hp <= 45.0
		or defender.body_hp <= 45.0
		or defender.fatigue >= 70.0
		or defender.stamina <= 25.0
	)


func _submission_early_safety_level(defender: MatchSideState, move: MoveResource) -> int:
	if defender == null or move == null or move.is_finisher:
		return 0
	var target_hp := defender.lowest_target_hp(move.move_target_parts)
	if target_hp <= 25.0:
		return 0
	if _match_time_seconds < 300:
		return 1 if target_hp < 40.0 else 2
	if _match_time_seconds < 600:
		return 1
	return 0


func _pressure_probabilities(pressure: float, resistance: float, pin: bool) -> Dictionary:
	var difference := resistance - pressure
	if difference >= 40.0:
		return _normalize_probabilities(15.0, 30.0 if pin else 35.0, 55.0 if pin else 50.0)
	if difference >= -15.0:
		return _normalize_probabilities(30.0, 35.0, 35.0)
	if difference >= -45.0:
		return _normalize_probabilities(45.0, 35.0, 20.0)
	return _normalize_probabilities(65.0, 27.0, 8.0)


func _normalize_probabilities(red: float, yellow: float, green: float) -> Dictionary:
	return ContestTimingBar.normalize_probabilities({"red": red, "yellow": yellow, "green": green})


func _simulate_probability_result(probabilities: Dictionary) -> StringName:
	var roll := randf() * 100.0
	var red_end := float(probabilities.get("red", 55.0))
	var yellow_end := red_end + float(probabilities.get("yellow", 30.0))
	if roll < red_end:
		return ContestTimingBar.RED_RESULT
	if roll < yellow_end:
		return ContestTimingBar.YELLOW_RESULT
	return ContestTimingBar.GREEN_RESULT


func _resolve_control_after_action(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if result in [ActionResult.REVERSAL, ActionResult.HIGH_RISK_CRASH]:
		_set_resolved_controller(_control_for_side(defender_side), attacker_side, defender_side)
		return
	if result == ActionResult.CLEAN_SUCCESS and move.is_finisher:
		_set_resolved_controller(_control_for_side(attacker_side), attacker_side, defender_side)
		return
	if attacker.current_position == WrestlerResource.Position.GROUNDED and defender.current_position == WrestlerResource.Position.GROUNDED:
		_neutral_recovery_favored_side = (
			attacker_side
			if result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS]
			else Side.NONE
		)
		_set_resolved_controller(ControlState.NEUTRAL, attacker_side, defender_side)
		return
	match result:
		ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS:
			_set_resolved_controller(_control_for_side(attacker_side), attacker_side, defender_side)
		ActionResult.PARTIAL_DEFENCE:
			if _is_high_risk(move) or move.move_impact >= 7:
				_set_resolved_controller(ControlState.NEUTRAL, attacker_side, defender_side)
			else:
				_set_resolved_controller(_control_for_side(attacker_side), attacker_side, defender_side)
		ActionResult.CONTESTED_STRUGGLE, ActionResult.BOTCH_OR_SCRAMBLE:
			var advantaged_side := _advantaged_side(attacker_side, defender_side, attacker, defender)
			_set_resolved_controller(
				ControlState.NEUTRAL if advantaged_side == Side.NONE else _control_for_side(advantaged_side),
				attacker_side,
				defender_side,
			)


func _advantaged_side(
	attacker_side: int,
	defender_side: int,
	attacker: MatchSideState,
	defender: MatchSideState,
) -> int:
	var difference := _neutral_recovery_score(attacker) - _neutral_recovery_score(defender)
	var threshold := float(MatchInteractionModel.build_late_match_profile(_match_time_seconds).control_threshold)
	if attacker.consecutive_neutral_resets >= 2 or defender.consecutive_neutral_resets >= 2:
		threshold = 0.01
	if difference >= threshold:
		return attacker_side
	if difference <= -threshold:
		return defender_side
	return Side.NONE


func _set_resolved_controller(value: int, attacker_side: int, defender_side: int) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if value == ControlState.NEUTRAL:
		attacker.note_neutral_reset()
		defender.note_neutral_reset()
	else:
		attacker.clear_neutral_reset_streak()
		defender.clear_neutral_reset_streak()
	_set_controller(value)


func _set_controller(value: int, schedule_turn: bool = true) -> void:
	var previous_controller := current_controller
	if current_controller == ControlState.PLAYER_CONTROL and value != ControlState.PLAYER_CONTROL:
		_player_setup_intent = &""
	if value != ControlState.NEUTRAL:
		_neutral_recovery_favored_side = Side.NONE
	current_controller = ControlState.MATCH_ENDED if match_ended else value
	match current_controller:
		ControlState.PLAYER_CONTROL:
			current_attacker_side = Side.PLAYER
			current_defender_side = Side.AI
		ControlState.AI_CONTROL:
			current_attacker_side = Side.AI
			current_defender_side = Side.PLAYER
		_:
			current_attacker_side = Side.NONE
			current_defender_side = Side.NONE
	_turn_generation += 1
	_scheduled_ai_generation = -1
	_scheduled_neutral_generation = -1
	if current_controller != ControlState.PLAYER_CONTROL:
		_moves_radial_menu.close()
		_setup_actions_menu.close()
		_clear_selected_move()
	if current_controller != previous_controller:
		_emit_ring_event(&"control_changed", current_attacker_side, current_defender_side)
	refresh_match_ui()
	if not schedule_turn or match_ended:
		return
	_schedule_current_turn()


func _schedule_current_turn() -> void:
	if (
		match_ended
		or not _match_initialized
		or is_resolving_action
		or contest_prompt_active
		or pin_sequence_active
		or submission_sequence_active
	):
		return
	var generation := _turn_generation
	if current_controller == ControlState.AI_CONTROL:
		if _scheduled_ai_generation == generation:
			return
		_scheduled_ai_generation = generation
		_run_ai_turn.call_deferred(generation)
	elif current_controller == ControlState.NEUTRAL:
		if _scheduled_neutral_generation == generation:
			return
		_scheduled_neutral_generation = generation
		_run_neutral_recovery.call_deferred(generation)


func get_match_flow_snapshot(context: String) -> Dictionary:
	var actor_side := current_attacker_side
	var defender_side := current_defender_side
	var valid_moves: Array[MoveResource] = []
	var valid_setups: Array[StringName] = []
	var pin_available := false
	if actor_side in [Side.PLAYER, Side.AI]:
		valid_moves = get_valid_moves(actor_side)
		valid_setups = get_valid_setup_actions(actor_side)
		pin_available = _can_pin(actor_side)
	var ai_candidate_available := false
	if actor_side == Side.AI:
		ai_candidate_available = _ai_decision_engine.has_executable_candidate(
			valid_moves,
			valid_setups,
			pin_available,
		)
	return {
		"context": context,
		"match_time": _match_time_seconds,
		"control": current_controller,
		"actor_side": actor_side,
		"defender_side": defender_side,
		"player_position": player_side_state.current_position,
		"ai_position": ai_side_state.current_position,
		"player_orientation": player_side_state.current_orientation,
		"ai_orientation": ai_side_state.current_orientation,
		"player_area": player_side_state.current_area,
		"ai_area": ai_side_state.current_area,
		"player_motion": player_side_state.current_motion_state,
		"ai_motion": ai_side_state.current_motion_state,
		"resolving": is_resolving_action,
		"contest": contest_prompt_active,
		"overlay": _interaction_overlay.is_interaction_active(),
		"pin_sequence": pin_sequence_active,
		"submission_sequence": submission_sequence_active,
		"valid_move_count": valid_moves.size(),
		"valid_setup_count": valid_setups.size(),
		"pin_available": pin_available,
		"ai_candidate_available": ai_candidate_available,
		"turn_generation": _turn_generation,
		"interaction_request": _interaction_overlay.get_active_request_id(),
		"scheduled_ai_generation": _scheduled_ai_generation,
		"scheduled_neutral_generation": _scheduled_neutral_generation,
		"ai_planned_setup_steps": _ai_decision_engine.planned_setup_actions.size(),
		"ai_planned_followup": _ai_decision_engine.planned_followup_move_key,
	}


func ensure_match_can_continue(context: String) -> void:
	if match_ended or not _match_initialized:
		return
	_settle_referee_count(context)
	if match_ended or _flow_recovery_active:
		return
	_flow_recovery_active = true
	if player_side_state == null or ai_side_state == null:
		push_warning("MATCH FLOW WATCHDOG | missing match-side state at %s" % context)
		_flow_recovery_active = false
		return
	if player_side_state.wrestler == null and player_wrestler != null:
		player_side_state.wrestler = player_wrestler
	if ai_side_state.wrestler == null and ai_wrestler != null:
		ai_side_state.wrestler = ai_wrestler
	var repaired_position := _repair_invalid_positions()
	if current_controller not in [ControlState.PLAYER_CONTROL, ControlState.AI_CONTROL, ControlState.NEUTRAL]:
		current_controller = ControlState.NEUTRAL
		current_attacker_side = Side.NONE
		current_defender_side = Side.NONE
	if current_controller == ControlState.PLAYER_CONTROL:
		current_attacker_side = Side.PLAYER
		current_defender_side = Side.AI
	elif current_controller == ControlState.AI_CONTROL:
		current_attacker_side = Side.AI
		current_defender_side = Side.PLAYER
	else:
		current_attacker_side = Side.NONE
		current_defender_side = Side.NONE
	if repaired_position:
		refresh_match_ui()
	# A visible interaction or an authored sequence owns continuation until its
	# await resumes. The caller invokes this validator again at that boundary.
	if contest_prompt_active or _interaction_overlay.is_interaction_active() or pin_sequence_active or submission_sequence_active:
		_flow_recovery_active = false
		return
	if is_resolving_action:
		if context == "invalid-position repair":
			_flow_recovery_active = false
			return
		if OS.is_debug_build():
			print("MATCH FLOW WATCHDOG | clearing orphaned resolution flag at ", context)
		is_resolving_action = false
	var snapshot := get_match_flow_snapshot(context)
	var has_path := false
	match current_controller:
		ControlState.PLAYER_CONTROL:
			has_path = (
				int(snapshot.valid_move_count) > 0
				or int(snapshot.valid_setup_count) > 0
				or bool(snapshot.pin_available)
			)
		ControlState.AI_CONTROL:
			has_path = bool(snapshot.ai_candidate_available)
			if has_path:
				_schedule_current_turn()
		ControlState.NEUTRAL:
			has_path = true
			_schedule_current_turn()
	if has_path:
		if current_controller != ControlState.NEUTRAL:
			_last_dead_end_signature = ""
			_dead_end_repetitions = 0
			_watchdog_recovery_pending = false
		_flow_recovery_active = false
		return
	var signature := "%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
		current_controller,
		player_side_state.current_position,
		ai_side_state.current_position,
		player_side_state.current_orientation,
		ai_side_state.current_orientation,
		player_side_state.current_area,
		ai_side_state.current_area,
		player_side_state.current_motion_state,
		ai_side_state.current_motion_state,
	]
	if _watchdog_recovery_pending or signature == _last_dead_end_signature:
		_dead_end_repetitions += 1
	else:
		_last_dead_end_signature = signature
		_dead_end_repetitions = 1
	_watchdog_recovery_pending = true
	if OS.is_debug_build():
		print("MATCH FLOW WATCHDOG | ", snapshot)
	var actor := _state_for_side(current_attacker_side)
	if actor != null and not _is_neutral_ring_stance(actor):
		_set_neutral_ring_stance(actor)
		_set_controller(current_controller)
		_flow_recovery_active = false
		return
	if _dead_end_repetitions < 2:
		_set_controller(ControlState.NEUTRAL)
		_flow_recovery_active = false
		return
	# Last-resort recovery is intentionally state-only: it cannot alter match
	# condition, clock, winner, or authored resources.
	_interaction_overlay.close_interaction(true)
	is_resolving_action = false
	contest_prompt_active = false
	pin_sequence_active = false
	submission_sequence_active = false
	_active_pin_context.clear()
	_active_submission_target_resolution.clear()
	_clear_selected_move()
	_player_setup_intent = &""
	_ai_decision_engine.note_setup_executed(&"", ai_side_state)
	_set_neutral_ring_stance(player_side_state)
	_set_neutral_ring_stance(ai_side_state)
	_set_controller(ControlState.NEUTRAL)
	_flow_recovery_active = false


func _resume_controller_after_cancel(preferred_side: int) -> void:
	var resume_controller := current_controller
	if resume_controller not in [ControlState.PLAYER_CONTROL, ControlState.AI_CONTROL, ControlState.NEUTRAL]:
		resume_controller = _control_for_side(preferred_side)
	_set_controller(resume_controller)


func _run_ai_turn(generation: int) -> void:
	await get_tree().create_timer(AI_DELAY_SECONDS).timeout
	if _scheduled_ai_generation == generation:
		_scheduled_ai_generation = -1
	if not _turn_can_continue(generation, ControlState.AI_CONTROL):
		return
	_perform_ai_decision()


func _perform_ai_decision() -> void:
	var valid_moves := get_valid_moves(Side.AI)
	var setup_actions := get_valid_setup_actions(Side.AI)
	var forced_recovery := _ai_special_state_recovery(valid_moves, setup_actions)
	if not forced_recovery.is_empty():
		_ai_decision_engine.note_forced_fallback(ai_side_state)
		execute_setup_action(Side.AI, forced_recovery)
		return
	if not _match_rules.disqualifications_enabled:
		var weapon_action_ready := _match_time_seconds - ai_side_state.last_weapon_action_time >= 90
		if weapon_action_ready and SetupActionsMenu.CHAIR_SHOT in setup_actions and randf() < 0.40:
			execute_setup_action(Side.AI, SetupActionsMenu.CHAIR_SHOT)
			return
		if weapon_action_ready and SetupActionsMenu.PICK_UP_WEAPON in setup_actions and randf() < 0.20:
			execute_setup_action(Side.AI, SetupActionsMenu.PICK_UP_WEAPON)
			return
		if weapon_action_ready and SetupActionsMenu.RETRIEVE_STEEL_CHAIR in setup_actions and randf() < 0.16:
			execute_setup_action(Side.AI, SetupActionsMenu.RETRIEVE_STEEL_CHAIR)
			return
	var decision := _ai_decision_engine.choose_action(
		ai_side_state,
		player_side_state,
		valid_moves,
		setup_actions,
		_match_time_seconds,
	)
	if decision.is_empty():
		_ai_fallback()
		return
	match StringName(decision.get("fallback_log", &"")):
		&"commit":
			add_match_log_entry(
				"%s abandons the extra setup and commits to the attack." % _side_name(Side.AI),
			)
		&"reset":
			add_match_log_entry(
				"%s breaks off the looping setup and resets their stance." % _side_name(Side.AI),
			)
	var kind: StringName = decision.get("kind", &"")
	match kind:
		MatchAIDecisionEngine.KIND_MOVE:
			var move: MoveResource = decision.get("move") as MoveResource
			if move != null:
				var target_resolution: Dictionary = decision.get("target_resolution", {})
				execute_move(Side.AI, move, target_resolution)
				return
		MatchAIDecisionEngine.KIND_SETUP:
			var action_id: StringName = decision.get("setup_action", &"")
			if action_id in setup_actions:
				execute_setup_action(Side.AI, action_id)
				return
		MatchAIDecisionEngine.KIND_PIN:
			if _can_pin(Side.AI):
				start_pin_sequence(Side.AI, Side.PLAYER)
				return
	_ai_fallback()


func _ai_special_state_recovery(
	valid_moves: Array[MoveResource],
	setup_actions: Array[StringName],
) -> StringName:
	if _match_rules.count_outs_enabled and _referee_count_active:
		var remaining := _match_rules.count_out_limit - _referee_count_value
		if _side_is_outside(Side.AI) and remaining <= 3 and SetupActionsMenu.RETURN_TO_RING in setup_actions:
			return SetupActionsMenu.RETURN_TO_RING
		if not _side_is_outside(Side.AI) and _side_is_outside(Side.PLAYER) and remaining <= maxi(3, _match_rules.count_out_limit / 2) and SetupActionsMenu.WAIT_FOR_COUNT in setup_actions:
			return SetupActionsMenu.WAIT_FOR_COUNT
	if not valid_moves.is_empty():
		return &""
	if ai_side_state.current_position in [WrestlerResource.Position.GROUNDED, WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING] and SetupActionsMenu.STAND_UP in setup_actions:
		return SetupActionsMenu.STAND_UP
	if ai_side_state.current_motion_state == WrestlerResource.MotionState.RUNNING and SetupActionsMenu.STOP_RUNNING in setup_actions:
		return SetupActionsMenu.STOP_RUNNING
	if ai_side_state.current_motion_state == WrestlerResource.MotionState.ROPE_REBOUND and SetupActionsMenu.REGAIN_FOOTING in setup_actions:
		return SetupActionsMenu.REGAIN_FOOTING
	if ai_side_state.current_motion_state in [WrestlerResource.MotionState.RISING, WrestlerResource.MotionState.STAGGERING] and SetupActionsMenu.REGAIN_COMPOSURE in setup_actions:
		return SetupActionsMenu.REGAIN_COMPOSURE
	if player_side_state.current_motion_state in [WrestlerResource.MotionState.RISING, WrestlerResource.MotionState.STAGGERING] and SetupActionsMenu.PRESS_ADVANTAGE in setup_actions:
		return SetupActionsMenu.PRESS_ADVANTAGE
	if ai_side_state.current_area == WrestlerResource.Area.TOP_ROPE and SetupActionsMenu.CLIMB_DOWN in setup_actions:
		return SetupActionsMenu.CLIMB_DOWN
	if ai_side_state.current_area in [WrestlerResource.Area.APRON, WrestlerResource.Area.ROPES, WrestlerResource.Area.OUTSIDE, WrestlerResource.Area.RAMP] and SetupActionsMenu.RETURN_TO_RING in setup_actions:
		return SetupActionsMenu.RETURN_TO_RING
	if ai_side_state.current_area == WrestlerResource.Area.CORNER and SetupActionsMenu.LEAVE_CORNER in setup_actions:
		return SetupActionsMenu.LEAVE_CORNER
	for action_id in setup_actions:
		if MatchSetupStateRules.is_recovery(action_id):
			return action_id
	return &""


func _run_neutral_recovery(generation: int) -> void:
	await get_tree().create_timer(AI_DELAY_SECONDS).timeout
	if _scheduled_neutral_generation == generation:
		_scheduled_neutral_generation = -1
	if not _turn_can_continue(generation, ControlState.NEUTRAL):
		return
	is_resolving_action = true
	advance_match_clock()
	var favored_side := _neutral_recovery_favored_side
	_neutral_recovery_favored_side = Side.NONE
	var recovery_side := Side.NONE
	if favored_side != Side.NONE:
		recovery_side = (
			favored_side
			if randf() < GROUNDED_ATTACKER_RECOVERY_CHANCE
			else _opponent_side(favored_side)
		)
	else:
		var player_score := _neutral_recovery_score(player_side_state) + randf_range(-10.0, 10.0)
		var ai_score := _neutral_recovery_score(ai_side_state) + randf_range(-10.0, 10.0)
		recovery_side = Side.PLAYER if player_score >= ai_score else Side.AI
	var recovery_state := _state_for_side(recovery_side)
	var stood_up := recovery_state.current_position == WrestlerResource.Position.GROUNDED
	if stood_up:
		recovery_state.set_match_state(
			WrestlerResource.Position.STANDING,
			WrestlerResource.Orientation.FRONT,
			recovery_state.current_area,
			WrestlerResource.MotionState.STATIONARY,
		)
	add_match_log_entry(
		("%s pushes back to their feet first and takes control." if stood_up else "%s regains the initiative and takes control.") % _side_name(recovery_side),
	)
	is_resolving_action = false
	_set_controller(_control_for_side(recovery_side))
	ensure_match_can_continue("neutral recovery")


func _ai_fallback() -> void:
	_ai_decision_engine.note_forced_fallback(ai_side_state)
	is_resolving_action = true
	advance_match_clock()
	add_match_log_entry("%s circles, looking for an opening." % _side_name(Side.AI))
	if not _is_neutral_ring_stance(ai_side_state):
		_set_neutral_ring_stance(ai_side_state)
	if get_valid_moves(Side.AI).is_empty() and get_valid_setup_actions(Side.AI).is_empty():
		_set_neutral_ring_stance(player_side_state)
		_set_neutral_ring_stance(ai_side_state)
	is_resolving_action = false
	_set_controller(ControlState.NEUTRAL)
	ensure_match_can_continue("AI fallback")


func _neutral_recovery_score(state: MatchSideState) -> float:
	var score := state.stamina + state.momentum - state.fatigue
	var profile := MatchInteractionModel.build_late_match_profile(_match_time_seconds)
	var exhaustion_factor := clampf(((100.0 - state.stamina) + state.fatigue) / 200.0, 0.0, 1.0)
	score -= float(profile.recovery_penalty) * exhaustion_factor
	if state.stamina <= 0.0:
		score -= 25.0
	if state.fatigue >= 80.0:
		score -= 20.0
	if state.momentum >= 90.0:
		score += 15.0
	return score


func _move_is_valid(side: int, move: MoveResource) -> bool:
	if move == null:
		return false
	if move.is_submission and not _match_rules.submission_enabled:
		return false
	var attacker := _state_for_side(side)
	var defender := _state_for_side(_opponent_side(side))
	if attacker == null or defender == null or attacker.wrestler == null or defender.wrestler == null:
		return false
	if move == _chair_shot_move:
		return _match_rules.weapons_enabled and _weapon_attack_is_mechanically_valid(attacker, defender)
	if move not in attacker.all_assigned_moves():
		return false
	if not attacker.can_use_move(move):
		return false
	if not _position_matches(move.required_attacker_position, attacker.current_position):
		return false
	if not _position_matches(move.required_target_position, defender.current_position):
		return false
	if not _orientation_matches(move.required_attacker_orientation, attacker.current_orientation):
		return false
	if not _orientation_matches(move.required_target_orientation, defender.current_orientation):
		return false
	if not MatchAreaRules.move_areas_match(move, attacker.current_area, defender.current_area):
		return false
	if move.required_attacker_motion_state != attacker.current_motion_state or move.required_target_motion_state != defender.current_motion_state:
		return false
	return true


func _player_move_menu_filter(move: MoveResource) -> bool:
	return _move_is_valid(Side.PLAYER, move)


func _player_move_unavailable_reason(move: MoveResource) -> String:
	if move == null:
		return "This move is unavailable."
	if player_side_state.is_signature_move(move) and not player_side_state.signature_ready:
		return "Locked signature: reach 100 momentum to make it ready."
	if player_side_state.is_finisher_move(move) and player_side_state.finisher_stock <= 0:
		return "Locked finisher: land a ready signature to earn finisher stock."
	return "This move is not currently available."


func _position_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Position.NONE or required == actual


func _orientation_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Orientation.NONE or required == actual


func _move_requirements_match_snapshots(move: MoveResource, attacker: Dictionary, defender: Dictionary) -> bool:
	return (
		_position_matches(move.required_attacker_position, int(attacker.get("position", WrestlerResource.Position.NONE)))
		and _position_matches(move.required_target_position, int(defender.get("position", WrestlerResource.Position.NONE)))
		and _orientation_matches(move.required_attacker_orientation, int(attacker.get("orientation", WrestlerResource.Orientation.NONE)))
		and _orientation_matches(move.required_target_orientation, int(defender.get("orientation", WrestlerResource.Orientation.NONE)))
		and MatchAreaRules.move_areas_match(
			move,
			int(attacker.get("area", WrestlerResource.Area.IN_RING)),
			int(defender.get("area", WrestlerResource.Area.IN_RING)),
		)
		and move.required_attacker_motion_state == int(attacker.get("motion_state", WrestlerResource.MotionState.STATIONARY))
		and move.required_target_motion_state == int(defender.get("motion_state", WrestlerResource.MotionState.STATIONARY))
	)


func _setup_intent_matches_move(intent: StringName, move: MoveResource) -> bool:
	match intent:
		SetupActionsMenu.IRISH_WHIP:
			return move.required_target_motion_state == WrestlerResource.MotionState.ROPE_REBOUND or (move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_target_area == WrestlerResource.Area.ROPES)
		SetupActionsMenu.THROW_INTO_CORNER:
			return move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_target_area == WrestlerResource.Area.CORNER
		SetupActionsMenu.START_RUNNING:
			return move.move_type == MoveResource.MoveType.RUNNING
		SetupActionsMenu.CLIMB_TOP_ROPE:
			return move.move_type == MoveResource.MoveType.AERIAL or (move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_attacker_area == WrestlerResource.Area.TOP_ROPE)
		SetupActionsMenu.WAKE_OPPONENT:
			return move.move_type == MoveResource.MoveType.AERIAL and move.required_target_position == WrestlerResource.Position.STANDING
		SetupActionsMenu.PREPARE_SPRINGBOARD:
			return move.move_type == MoveResource.MoveType.SPRINGBOARD
		SetupActionsMenu.PICK_OPPONENT_UP, SetupActionsMenu.GRAPPLE_OPPONENT:
			return move.move_type in [MoveResource.MoveType.GRAPPLE, MoveResource.MoveType.SUBMISSION]
	return move != null and not MatchSetupStateRules.is_recovery(intent) and intent != SetupActionsMenu.TAUNT


func _is_high_risk(move: MoveResource) -> bool:
	return MatchInteractionModel.is_high_risk_move(move)


func _stamina_cost(move: MoveResource) -> float:
	var cost := 4.0
	if move.move_impact >= 9:
		cost = 14.0
	elif move.move_impact >= 7:
		cost = 10.0
	elif move.move_impact >= 4:
		cost = 7.0
	if move.is_strike:
		cost -= 1.0
	if move.is_submission:
		cost += 2.0
	if move.is_finisher:
		cost += 4.0
	if _is_high_risk(move):
		cost += 4.0
	return maxf(0.0, cost)


func _can_pin(side: int) -> bool:
	if not _match_rules.pinfall_enabled or match_ended or is_resolving_action or not _side_has_control(side):
		return false
	var attacker := _state_for_side(side)
	var defender := _state_for_side(_opponent_side(side))
	return (
		attacker != null
		and defender != null
		and attacker.current_position == WrestlerResource.Position.STANDING
		and defender.current_position == WrestlerResource.Position.GROUNDED
		and attacker.current_area == WrestlerResource.Area.IN_RING
		and defender.current_area == WrestlerResource.Area.IN_RING
		and attacker.current_motion_state == WrestlerResource.MotionState.STATIONARY
	)


func _side_has_control(side: int) -> bool:
	return (
		(side == Side.PLAYER and current_controller == ControlState.PLAYER_CONTROL)
		or (side == Side.AI and current_controller == ControlState.AI_CONTROL)
	)


func _state_for_side(side: int) -> MatchSideState:
	if side == Side.PLAYER:
		return player_side_state
	if side == Side.AI:
		return ai_side_state
	return null


func _opponent_side(side: int) -> int:
	return Side.AI if side == Side.PLAYER else Side.PLAYER


func _control_for_side(side: int) -> int:
	return ControlState.PLAYER_CONTROL if side == Side.PLAYER else ControlState.AI_CONTROL


func _turn_can_continue(generation: int, expected_control: int) -> bool:
	return (
		generation == _turn_generation
		and current_controller == expected_control
		and not match_ended
		and not is_resolving_action
		and not contest_prompt_active
		and not pin_sequence_active
		and not submission_sequence_active
	)


func _update_action_availability() -> void:
	var player_control := current_controller == ControlState.PLAYER_CONTROL
	var blocked := match_ended or is_resolving_action or contest_prompt_active or pin_sequence_active or submission_sequence_active
	var valid_moves := get_valid_moves(Side.PLAYER) if player_wrestler != null and ai_wrestler != null else []
	var valid_setups := get_valid_setup_actions(Side.PLAYER) if player_wrestler != null and ai_wrestler != null else []
	var neutral_recovery := (
		current_controller == ControlState.NEUTRAL
		and SetupActionsMenu.STAND_UP in valid_setups
		and not blocked
	)
	_move_selector_button.disabled = blocked or not player_control or valid_moves.is_empty()
	_update_special_state_move_button(valid_moves, player_control and not blocked)
	_setup_actions_button.disabled = blocked or (not player_control and not neutral_recovery) or valid_setups.is_empty()
	_execute_button.disabled = blocked or not player_control or selected_move == null or not _move_is_valid(Side.PLAYER, selected_move)
	_pin_button.disabled = not _can_pin(Side.PLAYER)
	var selector_blocked := match_ended or is_resolving_action or contest_prompt_active or pin_sequence_active or submission_sequence_active
	_player_selector.disabled = selector_blocked or _roster.is_empty()
	_ai_selector.disabled = selector_blocked or _roster.size() < 2
	if _moves_radial_menu.visible and _move_selector_button.disabled:
		_moves_radial_menu.close()
	_pin_button.tooltip_text = "Attempt a pin on the grounded opponent." if not _pin_button.disabled else "Pin requires player control, a standing attacker, and a grounded opponent."
	if selected_move == null:
		_execute_button.text = "EXECUTE"


func _update_special_state_move_button(valid_moves: Array[MoveResource], interaction_allowed: bool) -> void:
	var special_label := ""
	if interaction_allowed and player_side_state.finisher_stock > 0:
		for move in valid_moves:
			if player_side_state.is_finisher_move(move):
				special_label = "SELECT MOVE — FINISHER READY"
				break
	if special_label.is_empty() and interaction_allowed and player_side_state.signature_ready:
		for move in valid_moves:
			if player_side_state.is_signature_move(move):
				special_label = "SELECT MOVE — SIGNATURE READY"
				break
	if special_label.is_empty() and interaction_allowed and player_side_state.current_area == WrestlerResource.Area.TOP_ROPE:
		for move in valid_moves:
			if move.move_type == MoveResource.MoveType.AERIAL:
				special_label = "SELECT MOVE — DIVING AVAILABLE"
				break
	elif special_label.is_empty() and interaction_allowed and player_side_state.current_area == WrestlerResource.Area.APRON:
		for move in valid_moves:
			if move.move_type == MoveResource.MoveType.SPRINGBOARD:
				special_label = "SELECT MOVE — SPRINGBOARD AVAILABLE"
				break
	if special_label.is_empty():
		_move_selector_button.text = "SELECT MOVE"
		_move_selector_button.add_theme_color_override("font_color", _move_button_default_font_color)
		if _move_button_default_style != null:
			_move_selector_button.add_theme_stylebox_override("normal", _move_button_default_style)
		return
	_move_selector_button.text = special_label
	_move_selector_button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35, 1.0))
	if _move_button_available_style != null:
		_move_selector_button.add_theme_stylebox_override("normal", _move_button_available_style)


func _update_match_header() -> void:
	if not is_node_ready():
		return
	_vs_banner.text = _match_presentation_label()
	match current_controller:
		ControlState.PLAYER_CONTROL:
			_attacker_indicator.text = "ATTACKER: %s" % _wrestler_name(player_wrestler)
		ControlState.AI_CONTROL:
			_attacker_indicator.text = "ATTACKER: %s" % _wrestler_name(ai_wrestler)
		ControlState.NEUTRAL:
			_attacker_indicator.text = "ATTACKER: NEUTRAL"
		ControlState.MATCH_ENDED:
			_attacker_indicator.text = "MATCH OVER"
	_match_clock.text = _formatted_match_clock()
	_update_referee_count_presentation()


func _match_presentation_label() -> String:
	for key in ["stipulation", "match_title", "championship"]:
		var value := str(_match_setup_metadata.get(key, "")).strip_edges()
		if not value.is_empty():
			return value.to_upper()
	return "STANDARD SINGLES MATCH"


func _on_move_selector_pressed() -> void:
	if _move_selector_button.disabled:
		return
	_moves_radial_menu.open_for_wrestler(
		player_wrestler,
		true,
		ai_wrestler,
		Callable(self, "_player_move_menu_filter"),
		Callable(self, "_player_move_unavailable_reason"),
		Callable(self, "_player_move_menu_interaction_allowed"),
		ai_side_state,
		_available_player_weapon_moves(),
	)


func _available_player_weapon_moves() -> Array[MoveResource]:
	var moves: Array[MoveResource] = []
	if _chair_shot_move != null and _weapon_attack_is_mechanically_valid(player_side_state, ai_side_state):
		moves.append(_chair_shot_move)
	return moves


func _player_move_menu_interaction_allowed() -> bool:
	return (
		current_controller == ControlState.PLAYER_CONTROL
		and not match_ended
		and not is_resolving_action
		and not contest_prompt_active
		and not pin_sequence_active
		and not submission_sequence_active
	)


func _player_targeting_allowed() -> bool:
	return _player_move_menu_interaction_allowed()


func _on_player_target_focus_changed(part: int) -> void:
	if not _player_targeting_allowed():
		return
	var next_focus := part if MoveTargetResolver.is_target_focus(part) else MoveResource.MoveTargetParts.NONE
	player_side_state.set_target_focus(
		next_focus,
		"Player selection" if next_focus != MoveResource.MoveTargetParts.NONE else "Auto",
	)
	_moves_radial_menu.set_target_focus(next_focus)
	_ai_card.set_target_focus(next_focus)
	_clear_selected_move()
	refresh_match_ui()


func _on_setup_actions_pressed() -> void:
	if _setup_actions_button.disabled:
		return
	_setup_actions_menu.set_rule_context(_match_rules.disqualifications_enabled)
	_setup_actions_menu.open_for_match(player_wrestler, ai_wrestler, get_valid_setup_actions(Side.PLAYER))


func _on_move_selected(move: MoveResource) -> void:
	select_move(Side.PLAYER, move)


func _on_execute_pressed() -> void:
	execute_selected_move(Side.PLAYER)


func _on_setup_action_selected(action_id: StringName) -> void:
	execute_setup_action(Side.PLAYER, action_id)


func _on_pin_pressed() -> void:
	start_pin_sequence(Side.PLAYER, Side.AI)


func _setup_log_message(side: int, action_id: StringName) -> String:
	var actor := _side_name(side)
	var target := _side_name(_opponent_side(side))
	match action_id:
		SetupActionsMenu.STAND_UP:
			return "%s pushes back to their feet." % actor
		SetupActionsMenu.START_RUNNING:
			return "%s hits the ropes and builds speed." % actor
		SetupActionsMenu.CLIMB_TOP_ROPE:
			return "%s climbs to the top rope and measures %s." % [actor, target]
		SetupActionsMenu.PREPARE_SPRINGBOARD:
			return "%s steps onto the apron and sets for a springboard attack." % actor
		SetupActionsMenu.RETURN_TO_RING, SetupActionsMenu.CLIMB_DOWN:
			return "%s returns to the ring and resets their stance." % actor
		SetupActionsMenu.PICK_OPPONENT_UP:
			return "%s drags %s back to their feet." % [actor, target]
		SetupActionsMenu.GRAPPLE_OPPONENT:
			return "%s ties up with %s." % [actor, target]
		SetupActionsMenu.IRISH_WHIP:
			return "%s sends %s into the ropes with an Irish whip." % [actor, target]
		SetupActionsMenu.THROW_INTO_CORNER:
			return "%s drives %s into the corner." % [actor, target]
		SetupActionsMenu.WAKE_OPPONENT:
			return "%s calls %s back to their feet from the top rope." % [actor, target]
		SetupActionsMenu.STOP_RUNNING:
			return "%s slows down and resets their stance." % actor
		SetupActionsMenu.LEAVE_CORNER:
			return "%s steps out of the corner." % actor
		SetupActionsMenu.REGAIN_FOOTING:
			return "%s comes off the ropes and regains their footing." % actor
		SetupActionsMenu.REGAIN_COMPOSURE:
			return "%s takes a moment to regain their composure." % actor
		SetupActionsMenu.PRESS_ADVANTAGE:
			return "%s closes in as %s steadies themselves." % [actor, target]
		SetupActionsMenu.STEP_TO_ROPES:
			return "%s steps onto the ropes and measures the distance to the floor." % actor
		SetupActionsMenu.LEAVE_ROPES:
			return "%s steps away from the ropes and returns inside." % actor
		SetupActionsMenu.GET_BEHIND_OPPONENT:
			return "%s circles behind %s and takes rear control." % [actor, target]
		SetupActionsMenu.TURN_OPPONENT_FACE_UP:
			return "%s turns %s face-up on the mat." % [actor, target]
		SetupActionsMenu.TURN_OPPONENT_FACE_DOWN:
			return "%s turns %s face-down on the mat." % [actor, target]
		SetupActionsMenu.SIT_OPPONENT_UP_FRONT, SetupActionsMenu.SIT_OPPONENT_UP_BACK:
			return "%s hauls %s into a seated position." % [actor, target]
		SetupActionsMenu.PULL_OPPONENT_TO_KNEES_FRONT, SetupActionsMenu.PULL_OPPONENT_TO_KNEES_BACK:
			return "%s pulls %s up onto their knees." % [actor, target]
		SetupActionsMenu.TURN_OPPONENT_IN_CORNER:
			return "%s turns %s around in the corner." % [actor, target]
		SetupActionsMenu.SEAT_OPPONENT_IN_CORNER:
			return "%s forces %s down against the turnbuckles." % [actor, target]
		SetupActionsMenu.LEAN_OPPONENT_ON_ROPES_FRONT, SetupActionsMenu.LEAN_OPPONENT_ON_ROPES_BACK:
			return "%s positions %s against the ropes." % [actor, target]
		SetupActionsMenu.DRAPE_OPPONENT_ON_ROPES_FRONT, SetupActionsMenu.DRAPE_OPPONENT_ON_ROPES_BACK:
			return "%s drapes %s across the ropes." % [actor, target]
		SetupActionsMenu.PLACE_OPPONENT_ON_APRON_FRONT, SetupActionsMenu.PLACE_OPPONENT_ON_APRON_BACK:
			return "%s forces %s out onto the apron." % [actor, target]
		SetupActionsMenu.SET_OPPONENT_ON_TOP_ROPE_FRONT, SetupActionsMenu.SET_OPPONENT_ON_TOP_ROPE_BACK:
			return "%s climbs with %s and positions them on the top rope." % [actor, target]
		SetupActionsMenu.SEND_OPPONENT_OUTSIDE:
			return "%s sends %s out to the floor." % [actor, target]
		SetupActionsMenu.CALL_OPPONENT_OUTSIDE:
			return "%s calls %s out to ringside, and they step through the ropes to meet them." % [actor, target]
		SetupActionsMenu.EXIT_RING:
			return "%s steps through the ropes and drops to the floor alone." % actor
		SetupActionsMenu.TAKE_FIGHT_OUTSIDE:
			return "%s takes the fight with %s to the outside." % [actor, target]
		SetupActionsMenu.FIGHT_UP_RAMP:
			return "%s drives the fight with %s up the ramp." % [actor, target]
		SetupActionsMenu.RETURN_FROM_RAMP:
			return "%s brings the fight back from the ramp." % actor
		SetupActionsMenu.BRING_MATCH_BACK_TO_RING:
			return "%s brings %s back inside and resets the in-ring battle." % [actor, target]
		SetupActionsMenu.CALL_OPPONENT_RUNNING:
			return "%s calls %s forward from the top rope." % [actor, target]
	var details := MatchSetupStateRules.action_details(action_id)
	return "%s uses %s to create an opening." % [actor, str(details.get("title", "a setup action")).to_lower()]


func _apply_submission_stage_damage(defender: MatchSideState, move: MoveResource) -> void:
	var damage := maxf(1.0, float(move.move_impact) * 0.35)
	if move.move_target_parts.is_empty():
		defender.damage_part(MoveResource.MoveTargetParts.BODY, damage)
	else:
		for part in move.move_target_parts:
			defender.damage_part(int(part), damage)


func _repair_invalid_positions() -> bool:
	var repaired := false
	for state in [player_side_state, ai_side_state]:
		if state == null or state.wrestler == null:
			continue
		var invalid: bool = (
			state.current_position < WrestlerResource.Position.STANDING
			or state.current_position > WrestlerResource.Position.PERCHED
			or state.current_orientation < WrestlerResource.Orientation.FRONT
			or state.current_orientation > WrestlerResource.Orientation.FACE_DOWN
			or state.current_area < WrestlerResource.Area.IN_RING
			or state.current_area > WrestlerResource.Area.TOP_ROPE
			or state.current_motion_state < WrestlerResource.MotionState.STATIONARY
			or state.current_motion_state > WrestlerResource.MotionState.STAGGERING
		)
		if invalid:
			push_warning("Invalid match state for %s; resetting to a neutral ring stance." % _wrestler_name(state.wrestler))
			_set_neutral_ring_stance(state)
			repaired = true
	return repaired


func _clear_selected_move() -> void:
	selected_move = null
	selected_move_target_resolution.clear()
	if is_node_ready():
		_execute_button.text = "EXECUTE"


func _clear_selected_move_if_invalid() -> void:
	if selected_move != null and (
		current_controller != ControlState.PLAYER_CONTROL
		or not _move_is_valid(Side.PLAYER, selected_move)
	):
		_clear_selected_move()


func _clear_match_log() -> void:
	if not is_node_ready():
		return
	_match_log_scroll_generation += 1
	_match_log_scroll.scroll_vertical = 0
	for child in _match_log_list.get_children():
		child.queue_free()


func _formatted_match_clock() -> String:
	return "%02d:%02d" % [floori(float(_match_time_seconds) / 60.0), _match_time_seconds % 60]


func _count_word(count: int) -> String:
	match count:
		1:
			return "ONE"
		2:
			return "TWO"
	return "THREE"


func _count_phrase(count: int) -> String:
	match count:
		1:
			return "one"
		2:
			return "two"
	return "the last possible moment"


func _side_name(side: int) -> String:
	var state := _state_for_side(side)
	return _wrestler_name(state.wrestler) if state != null else "Unassigned"


func _wrestler_name(value: WrestlerResource) -> String:
	if value == null:
		return "Unassigned"
	var display_name: String = value.wrestler_name.strip_edges()
	if display_name.is_empty() and not value.resource_path.is_empty():
		display_name = value.resource_path.get_file().get_basename().capitalize()
	return "Unnamed Wrestler" if display_name.is_empty() else display_name


func _move_name(move: MoveResource) -> String:
	if move == null:
		return "Unnamed Move"
	var display_name := move.move_name.strip_edges()
	return "Unnamed Move" if display_name.is_empty() else display_name


func _open_latest_match_report() -> void:
	if _latest_match_report.is_empty():
		return
	_match_result_popup.close_result()
	_match_report_popup.open_report(_latest_match_report)


func _on_result_view_report_requested() -> void:
	_open_latest_match_report()


func _on_result_popup_closed() -> void:
	if _view_report_button.visible:
		_view_report_button.grab_focus()


func _on_match_report_returned() -> void:
	if _view_report_button.visible:
		_view_report_button.grab_focus()


func _open_initial_match_setup() -> void:
	_match_setup_popup.open_setup(
		_roster,
		player_wrestler,
		ai_wrestler,
		false,
		_recent_wrestler_paths(),
	)


func _on_new_match_requested() -> void:
	if not match_ended:
		return
	_match_result_popup.close_result()
	_match_report_popup.close_report()
	_interaction_overlay.close_interaction(true)
	_moves_radial_menu.close()
	_setup_actions_menu.close()
	_match_setup_popup.open_setup(
		_roster,
		player_wrestler,
		ai_wrestler,
		true,
		_recent_wrestler_paths(),
	)


func _on_match_setup_requested(
	player: WrestlerResource,
	opponent: WrestlerResource,
	setup_metadata: Dictionary,
) -> void:
	if player == null or opponent == null:
		_match_setup_popup.reject_launch("Both sides need a loaded wrestler resource.")
		return
	if not _roster_contains_resource(player) or not _roster_contains_resource(opponent):
		_match_setup_popup.reject_launch("That selection is no longer available in the loaded roster.")
		return
	if _same_wrestler(player, opponent):
		_match_setup_popup.reject_launch("Player and AI must be different wrestlers.")
		return
	_match_setup_popup.confirm_launch()
	player_wrestler = player
	ai_wrestler = opponent
	_match_setup_metadata = {
		"match_setup": str(setup_metadata.get("match_setup", "Manual")),
		"player_locked": bool(setup_metadata.get("player_locked", false)),
		"ai_locked": bool(setup_metadata.get("ai_locked", false)),
		"player_randomly_selected": bool(setup_metadata.get("player_randomly_selected", false)),
		"ai_randomly_selected": bool(setup_metadata.get("ai_randomly_selected", false)),
		"match_rules": (setup_metadata.get("match_rules", {}) as Dictionary).duplicate(true),
	}
	_match_rules = MatchRules.from_dictionary(_match_setup_metadata.match_rules).runtime_copy()
	_record_recent_matchup(player, opponent)
	_sync_selector_to_resource(_player_selector, player_wrestler)
	_sync_selector_to_resource(_ai_selector, ai_wrestler)
	_update_disabled_options()
	_selection_status.text = ""
	start_match()


func _roster_contains_resource(wrestler: WrestlerResource) -> bool:
	for roster_wrestler in _roster:
		if _same_wrestler(roster_wrestler, wrestler):
			return true
	return false


func _record_recent_matchup(player: WrestlerResource, opponent: WrestlerResource) -> void:
	var matchup := PackedStringArray()
	if player != null and not player.resource_path.is_empty():
		matchup.append(player.resource_path)
	if opponent != null and not opponent.resource_path.is_empty():
		matchup.append(opponent.resource_path)
	_recent_matchups.append(matchup)
	while _recent_matchups.size() > 5:
		_recent_matchups.pop_front()


func _recent_wrestler_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for matchup in _recent_matchups:
		for path in matchup:
			if path not in paths:
				paths.append(path)
	return paths


func _on_match_setup_cancelled() -> void:
	if match_ended and _new_match_button.visible:
		_new_match_button.grab_focus()


func _build_match_result_summary() -> Dictionary:
	var winner_state := _state_for_side(winner_side)
	return {
		"winner": _side_name(winner_side) if winner_side != Side.NONE else "No Winner",
		"result": _finish_type_name(finish_type),
		"final_time": _format_match_time(final_time),
		"finish_move": _move_name(finish_move) if finish_move != null else (finish_action if not finish_action.is_empty() else finish_reason),
		"damage_dealt": winner_state.damage_dealt if winner_state != null else 0.0,
		"reversals": winner_state.reversals if winner_state != null else 0,
	}


func _build_match_report() -> Dictionary:
	var player_report := _side_report_stats(player_side_state, "PLAYER")
	var ai_report := _side_report_stats(ai_side_state, "AI")
	var result_name := _finish_type_name(finish_type)
	var finish_name := "None"
	if finish_move != null:
		finish_name = _move_name(finish_move)
	elif not finish_action.is_empty():
		finish_name = finish_action
	var report := {
		"title": "MATCH REPORT",
		"subtitle": "%s vs. %s" % [_side_name(Side.PLAYER), _side_name(Side.AI)],
		"winner": _side_name(winner_side) if winner_side != Side.NONE else "No Winner",
		"loser": _side_name(loser_side) if loser_side != Side.NONE else "None",
		"result": result_name,
		"finish_reason": finish_reason,
		"final_time": _format_match_time(final_time),
		"finish_move": finish_name,
		"match_setup": str(_match_setup_metadata.get("match_setup", "Manual")),
		"player_locked": bool(_match_setup_metadata.get("player_locked", false)),
		"ai_locked": bool(_match_setup_metadata.get("ai_locked", false)),
		"player_randomly_selected": bool(_match_setup_metadata.get("player_randomly_selected", false)),
		"ai_randomly_selected": bool(_match_setup_metadata.get("ai_randomly_selected", false)),
		"match_rules": _match_rules.to_dictionary(),
		"rules_summary": _match_rules.summary(),
		"count_started": _referee_count_starts,
		"highest_count": _referee_count_highest,
		"count_resets": _referee_count_resets,
		"final_count": _referee_count_value,
		"count_out_finish": finish_type == FinishType.COUNT_OUT,
		"double_count_out": finish_type == FinishType.DOUBLE_COUNT_OUT,
		"player": player_report,
		"ai": ai_report,
		"log_lines": match_log_entries.duplicate(),
		"file_stem": "%s_vs_%s" % [_side_name(Side.PLAYER), _side_name(Side.AI)],
	}
	report["export_text"] = _build_match_report_text(report)
	return report


func _side_report_stats(state: MatchSideState, role: String) -> Dictionary:
	if state == null:
		return {"heading": "%s — UNASSIGNED" % role}
	return {
		"heading": "%s — %s" % [role, _wrestler_name(state.wrestler)],
		"move_attempts": state.move_attempts,
		"moves_landed": state.moves_landed,
		"finisher_attempts": state.finisher_attempts,
		"finishers_landed": state.finishers_landed,
		"signature_ready": state.signature_ready,
		"signatures_earned": state.signatures_earned,
		"signatures_landed": state.signatures_landed,
		"finisher_stock": state.finisher_stock,
		"finisher_stock_earned": state.finisher_stock_earned,
		"finisher_stock_spent": state.finisher_stock_spent,
		"reversals": state.reversals,
		"setup_actions": state.setup_actions,
		"pin_attempts": state.pin_attempts,
		"kickouts": state.kickouts,
		"submission_attempts": state.submission_attempts,
		"submission_escapes": state.submission_escapes,
		"damage_dealt": state.damage_dealt,
		"damage_taken": state.damage_taken,
		"stamina": state.stamina,
		"fatigue": state.fatigue,
		"momentum": state.momentum,
		"position": _match_state_display_name(state),
		"head_hp": state.head_hp,
		"body_hp": state.body_hp,
		"left_arm_hp": state.left_arm_hp,
		"right_arm_hp": state.right_arm_hp,
		"left_leg_hp": state.left_leg_hp,
		"right_leg_hp": state.right_leg_hp,
		"moves_used": state.move_names_used.duplicate(),
		"move_variety": state.move_variety_count(),
		"top_move": state.top_move_used(),
		"average_impact": state.average_attempted_impact(),
		"setup_followup_chains": state.successful_setup_followups,
		"execution_attempts": state.execution_attempts,
		"execution_successes": state.execution_successes,
		"response_attempts": state.response_attempts,
		"response_successes": state.response_successes,
		"reversal_success_rate": float(state.response_successes) / float(maxi(1, state.response_attempts)) * 100.0,
		"move_landing_rate": float(state.moves_landed) / float(maxi(1, state.move_attempts)) * 100.0,
		"botches_scrambles": state.botches_scrambles,
		"high_risk_crashes": state.high_risk_crashes,
		"submission_wins": state.submission_wins,
		"submission_struggle_wins": state.submission_struggle_wins,
		"submission_struggle_losses": state.submission_struggle_losses,
		"submission_struggle_seconds": state.submission_struggle_seconds,
		"contested_setup_attempts": state.contested_setup_attempts,
		"contested_setup_wins": state.contested_setup_wins,
		"contested_setup_losses": state.contested_setup_losses,
		"contested_setup_draws": state.contested_setup_draws,
		"taunts_attempted": state.taunts_attempted,
		"taunts_succeeded": state.taunts_succeeded,
		"taunts_interrupted": state.taunts_interrupted,
		"taunt_stamina_recovered": state.taunt_stamina_recovered,
		"taunt_momentum_gained": state.taunt_momentum_gained,
		"taunt_bonus_granted": state.taunt_bonus_momentum_granted,
		"taunt_bonus_consumed": state.taunt_bonus_momentum_consumed,
		"pending_taunt_bonus": state.pending_taunt_momentum_bonus,
		"ai_taunts_rejected_cooldown": state.ai_taunts_rejected_cooldown,
		"ai_taunts_rejected_risk": state.ai_taunts_rejected_risk,
		"control_meter_attempts": state.control_meter_attempts,
		"control_meter_successes": state.control_meter_successes,
		"timing_circle_attempts": state.timing_circle_attempts,
		"timing_circle_successes": state.timing_circle_successes,
		"kickout_meter_attempts": state.kickout_meter_attempts,
		"kickout_meter_successes": state.kickout_meter_successes,
		"kickout_meter_near_misses": state.kickout_meter_near_misses,
		"kickout_meter_timeouts": state.kickout_meter_timeouts,
		"reversal_opportunities": state.reversal_opportunities,
		"high_risk_attempts": state.high_risk_attempts,
		"repetition_penalties": state.repetition_penalties_applied,
		"low_stamina_penalties": state.low_stamina_penalties_applied,
		"average_execution_profile": state.average_execution_profile(),
		"average_response_profile": state.average_response_profile(),
		"average_finish_pressure": state.average_finish_pressure(),
		"clean_successes": state.clean_successes,
		"laboured_successes": state.laboured_successes,
		"near_misses": state.near_misses,
		"near_miss_conversions": state.near_miss_conversions,
		"contested_struggles": state.contested_struggles,
		"neutral_resets": state.neutral_resets,
		"max_neutral_reset_streak": state.maximum_consecutive_neutral_resets,
		"max_setup_streak": state.maximum_consecutive_setup_actions,
		"setups_without_followup": state.setup_actions_without_followup,
		"setup_intents_created": state.setup_intents_created,
		"setup_intents_completed": state.setup_intents_completed,
		"setup_intents_abandoned": state.setup_intents_abandoned,
		"setup_loop_penalties": state.setup_loop_penalties,
		"dead_end_setups_prevented": state.dead_end_setups_prevented,
		"forced_fallbacks": state.forced_fallback_actions,
		"average_late_escalation": state.average_late_escalation(),
		"final_target_focus": MoveTargetResolver.part_label(state.target_focus_body_part),
		"target_focus_reason": state.target_focus_reason,
		"most_used_focus": _report_part_label(state.most_used_focus_part()),
		"most_targeted_part": _report_part_label(state.most_targeted_part()),
		"most_damaged_part": MoveTargetResolver.part_label(state.most_damaged_part()),
		"per_part_attacks": _format_part_number_dictionary(state.target_attack_counts, false),
		"per_part_damage": _format_part_number_dictionary(state.target_damage_dealt, true),
		"thresholds_crossed": _format_threshold_dictionary(state.body_part_thresholds_crossed),
		"parts_reaching_zero": _format_part_list(state.get_body_damage_summary().get("parts_reaching_zero", [])),
		"last_submission_target": _report_part_label(state.last_submission_target),
		"last_finisher_target": _report_part_label(state.last_finisher_target),
		"targeting_milestones": _format_threshold_dictionary(state.repeated_target_milestones),
		"outside_seconds": state.outside_seconds,
		"late_count_returns": state.late_count_returns,
		"weapons_retrieved": state.weapons_retrieved,
		"dropped_weapons_picked_up": state.dropped_weapons_picked_up,
		"weapon_types_used": ", ".join(state.weapon_types_used) if not state.weapon_types_used.is_empty() else "None",
		"weapons_broken": state.weapons_broken,
		"weapon_attacks_attempted": state.weapon_attacks_attempted,
		"weapon_attacks_landed": state.weapon_attacks_landed,
		"weapon_attacks_reversed": state.weapon_attacks_reversed,
		"illegal_weapon_uses": state.illegal_weapon_uses,
		"legal_weapon_attacks": state.legal_weapon_attacks,
		"disqualifications_caused": state.disqualifications_caused,
	}


func _format_part_number_dictionary(values: Dictionary, decimals: bool) -> String:
	var entries: Array[String] = []
	for part in [
		MoveResource.MoveTargetParts.HEAD,
		MoveResource.MoveTargetParts.BODY,
		MoveResource.MoveTargetParts.LEFT_ARM,
		MoveResource.MoveTargetParts.RIGHT_ARM,
		MoveResource.MoveTargetParts.LEFT_LEG,
		MoveResource.MoveTargetParts.RIGHT_LEG,
	]:
		if not values.has(part):
			continue
		var value_text := "%.1f" % float(values.get(part, 0.0)) if decimals else str(int(values.get(part, 0)))
		entries.append("%s %s" % [MoveTargetResolver.part_label(part), value_text])
	return ", ".join(entries) if not entries.is_empty() else "None"


func _report_part_label(part: int) -> String:
	return "None" if part == MoveResource.MoveTargetParts.NONE else MoveTargetResolver.part_label(part)


func _format_threshold_dictionary(values: Dictionary) -> String:
	var entries: Array[String] = []
	for part in values:
		var milestones: Array = values.get(part, [])
		if milestones.is_empty():
			continue
		var labels: Array[String] = []
		for milestone in milestones:
			labels.append(str(int(milestone)))
		entries.append("%s [%s]" % [MoveTargetResolver.part_label(int(part)), "/".join(labels)])
	return ", ".join(entries) if not entries.is_empty() else "None"


func _format_part_list(parts: Array) -> String:
	var labels: Array[String] = []
	for part in parts:
		labels.append(MoveTargetResolver.part_label(int(part)))
	return ", ".join(labels) if not labels.is_empty() else "None"


func _build_match_report_text(report: Dictionary) -> String:
	var lines: Array[String] = [
		"RISE TO RELEVANCE — MATCH REPORT",
		"================================",
		str(report.get("subtitle", "Match")),
		"Winner: %s" % str(report.get("winner", "Not Set")),
		"Result: %s" % str(report.get("result", "Not Set")),
		"Final time: %s" % str(report.get("final_time", "00:00")),
		"Finishing move: %s" % str(report.get("finish_move", "None")),
		"Finish reason: %s" % str(report.get("finish_reason", "None")),
		"Match setup: %s" % str(report.get("match_setup", "Manual")),
		"Rules: %s" % str(report.get("rules_summary", "Not Set")),
		"Referee count: %d starts | highest %d | %d resets | final %d" % [
			int(report.get("count_started", 0)),
			int(report.get("highest_count", 0)),
			int(report.get("count_resets", 0)),
			int(report.get("final_count", 0)),
		],
		"Locks: Player %s | AI %s" % [
			"Yes" if bool(report.get("player_locked", false)) else "No",
			"Yes" if bool(report.get("ai_locked", false)) else "No",
		],
		"Random selections: Player %s | AI %s" % [
			"Yes" if bool(report.get("player_randomly_selected", false)) else "No",
			"Yes" if bool(report.get("ai_randomly_selected", false)) else "No",
		],
		"",
	]
	lines.append_array(_side_report_text(report.get("player", {})))
	lines.append("")
	lines.append_array(_side_report_text(report.get("ai", {})))
	lines.append("")
	lines.append("COMPLETE MATCH LOG")
	lines.append("------------------")
	var log_lines: Array = report.get("log_lines", [])
	if log_lines.is_empty():
		lines.append("No match log entries were recorded.")
	else:
		for log_line in log_lines:
			lines.append(str(log_line))
	return "\n".join(lines) + "\n"


func _side_report_text(stats: Dictionary) -> Array[String]:
	var lines: Array[String] = [
		str(stats.get("heading", "UNASSIGNED")),
		"Moves: %d attempted / %d landed" % [int(stats.get("move_attempts", 0)), int(stats.get("moves_landed", 0))],
		"Finishers: %d attempted / %d landed" % [int(stats.get("finisher_attempts", 0)), int(stats.get("finishers_landed", 0))],
		"Signature flow: %d earned / %d landed | Ready: %s" % [
			int(stats.get("signatures_earned", 0)),
			int(stats.get("signatures_landed", 0)),
			"Yes" if bool(stats.get("signature_ready", false)) else "No",
		],
		"Finisher stock: %d/3 | %d earned / %d spent" % [
			int(stats.get("finisher_stock", 0)),
			int(stats.get("finisher_stock_earned", 0)),
			int(stats.get("finisher_stock_spent", 0)),
		],
		"Reversals: %d" % int(stats.get("reversals", 0)),
		"Outside: %ds | Late returns: %d" % [int(stats.get("outside_seconds", 0)), int(stats.get("late_count_returns", 0))],
		"Weapons: %d retrieved | %d floor pickups | %d attempted | %d landed | %d reversed" % [
			int(stats.get("weapons_retrieved", 0)),
			int(stats.get("dropped_weapons_picked_up", 0)),
			int(stats.get("weapon_attacks_attempted", 0)),
			int(stats.get("weapon_attacks_landed", 0)),
			int(stats.get("weapon_attacks_reversed", 0)),
		],
		"Weapon types: %s | Illegal %d | Legal %d | DQs caused %d" % [
			str(stats.get("weapon_types_used", "None")),
			int(stats.get("illegal_weapon_uses", 0)),
			int(stats.get("legal_weapon_attacks", 0)),
			int(stats.get("disqualifications_caused", 0)),
		],
		"Weapons broken: %d" % int(stats.get("weapons_broken", 0)),
		"Setup actions: %d" % int(stats.get("setup_actions", 0)),
		"Pins / Kickouts: %d / %d" % [int(stats.get("pin_attempts", 0)), int(stats.get("kickouts", 0))],
		"Kickout meter: %d attempts | %d successes | %d near misses | %d timeouts" % [
			int(stats.get("kickout_meter_attempts", 0)),
			int(stats.get("kickout_meter_successes", 0)),
			int(stats.get("kickout_meter_near_misses", 0)),
			int(stats.get("kickout_meter_timeouts", 0)),
		],
		"Submissions / Escapes: %d / %d" % [int(stats.get("submission_attempts", 0)), int(stats.get("submission_escapes", 0))],
		"Move variety: %d | Top move: %s" % [int(stats.get("move_variety", 0)), str(stats.get("top_move", "None"))],
		"Average attempted impact: %.1f | Setup follow-up chains: %d" % [float(stats.get("average_impact", 0.0)), int(stats.get("setup_followup_chains", 0))],
		"Move landing rate: %.1f%% | Reversal rate: %.1f%%" % [
			float(stats.get("move_landing_rate", 0.0)),
			float(stats.get("reversal_success_rate", 0.0)),
		],
		"Reversal checks: %d attempted / %d successful" % [int(stats.get("response_attempts", 0)), int(stats.get("response_successes", 0))],
		"Average reversal chance: %.1f%% | Finish pressure: %+.1f" % [
			float(stats.get("average_response_profile", 0.0)),
			float(stats.get("average_finish_pressure", 0.0)),
		],
		"Opportunities: %d reversals | %d high-risk attempts | Repetition penalties: %d" % [
			int(stats.get("reversal_opportunities", 0)),
			int(stats.get("high_risk_attempts", 0)),
			int(stats.get("repetition_penalties", 0)),
		],
		"High-risk crashes: %d" % int(stats.get("high_risk_crashes", 0)),
		"Neutral resets: %d | Longest streak: %d" % [
			int(stats.get("neutral_resets", 0)),
			int(stats.get("max_neutral_reset_streak", 0)),
		],
		"Setup flow: max streak %d | no follow-up %d | loop penalties %d" % [
			int(stats.get("max_setup_streak", 0)),
			int(stats.get("setups_without_followup", 0)),
			int(stats.get("setup_loop_penalties", 0)),
		],
		"Setup intents: %d created | %d completed | %d abandoned" % [
			int(stats.get("setup_intents_created", 0)),
			int(stats.get("setup_intents_completed", 0)),
			int(stats.get("setup_intents_abandoned", 0)),
		],
		"Flow safeguards: %d dead ends prevented | %d forced fallbacks | late pressure %.1f" % [
			int(stats.get("dead_end_setups_prevented", 0)),
			int(stats.get("forced_fallbacks", 0)),
			float(stats.get("average_late_escalation", 0.0)),
		],
		"Target focus: %s (%s) | Most used: %s" % [
			str(stats.get("final_target_focus", "Auto")),
			str(stats.get("target_focus_reason", "Auto")),
			str(stats.get("most_used_focus", "Auto")),
		],
		"Body targeting: most attacked %s | most damaged %s" % [
			str(stats.get("most_targeted_part", "None")),
			str(stats.get("most_damaged_part", "None")),
		],
		"Per-part attacks: %s" % str(stats.get("per_part_attacks", "None")),
		"Per-part damage dealt: %s" % str(stats.get("per_part_damage", "None")),
		"Damage thresholds: %s | At zero: %s" % [
			str(stats.get("thresholds_crossed", "None")),
			str(stats.get("parts_reaching_zero", "None")),
		],
		"Submission target: %s | Finisher target: %s | Repeated targeting: %s" % [
			str(stats.get("last_submission_target", "None")),
			str(stats.get("last_finisher_target", "None")),
			str(stats.get("targeting_milestones", "None")),
		],
		"Reversible setups: %d attempts | %d succeeded | %d reversed" % [
			int(stats.get("contested_setup_attempts", 0)),
			int(stats.get("contested_setup_wins", 0)),
			int(stats.get("contested_setup_losses", 0)),
		],
		"Taunts: %d attempted | %d succeeded | %d interrupted" % [
			int(stats.get("taunts_attempted", 0)),
			int(stats.get("taunts_succeeded", 0)),
			int(stats.get("taunts_interrupted", 0)),
		],
		"Taunt benefits: %.0f stamina | %.0f momentum | %.0f bonus granted / %.0f consumed | %.0f pending" % [
			float(stats.get("taunt_stamina_recovered", 0.0)),
			float(stats.get("taunt_momentum_gained", 0.0)),
			float(stats.get("taunt_bonus_granted", 0.0)),
			float(stats.get("taunt_bonus_consumed", 0.0)),
			float(stats.get("pending_taunt_bonus", 0.0)),
		],
		"AI taunt rejections: %d cooldown | %d risk" % [
			int(stats.get("ai_taunts_rejected_cooldown", 0)),
			int(stats.get("ai_taunts_rejected_risk", 0)),
		],
		"Submission results: %d wins | %d struggle wins | %d losses | %.1fs struggling" % [
			int(stats.get("submission_wins", 0)),
			int(stats.get("submission_struggle_wins", 0)),
			int(stats.get("submission_struggle_losses", 0)),
			float(stats.get("submission_struggle_seconds", 0.0)),
		],
		"Damage dealt / taken: %.1f / %.1f" % [float(stats.get("damage_dealt", 0.0)), float(stats.get("damage_taken", 0.0))],
		"Stamina: %.0f%% | Fatigue: %.0f%% | Momentum: %.0f%%" % [float(stats.get("stamina", 0.0)), float(stats.get("fatigue", 0.0)), float(stats.get("momentum", 0.0))],
		"Final position: %s" % str(stats.get("position", "Not Set")),
		"HP: Head %.0f | Body %.0f | Left Arm %.0f | Right Arm %.0f | Left Leg %.0f | Right Leg %.0f" % [
			float(stats.get("head_hp", 0.0)),
			float(stats.get("body_hp", 0.0)),
			float(stats.get("left_arm_hp", 0.0)),
			float(stats.get("right_arm_hp", 0.0)),
			float(stats.get("left_leg_hp", 0.0)),
			float(stats.get("right_leg_hp", 0.0)),
		],
	]
	var moves_used: Array = stats.get("moves_used", [])
	var move_names := PackedStringArray()
	for move_used in moves_used:
		move_names.append(str(move_used))
	lines.append("Moves used: %s" % (", ".join(move_names) if not move_names.is_empty() else "None"))
	return lines


func _position_display_name(position: int) -> String:
	return _enum_display_name(WrestlerResource.Position, position, "Not Set")


func _match_state_display_name(state: MatchSideState) -> String:
	if state == null:
		return "Not Set"
	return "%s / %s / %s / %s" % [
		_position_display_name(state.current_position),
		_enum_display_name(WrestlerResource.Orientation, state.current_orientation, "No Orientation"),
		_enum_display_name(WrestlerResource.Area, state.current_area, "Unknown Area"),
		_enum_display_name(WrestlerResource.MotionState, state.current_motion_state, "Unknown Motion"),
	]


func _enum_display_name(values: Dictionary, value: int, fallback: String) -> String:
	for key in values:
		if int(values[key]) == value:
			return fallback if key == "NONE" else str(key).replace("_", " ").to_lower().capitalize()
	return fallback


func _is_neutral_ring_stance(state: MatchSideState) -> bool:
	return (
		state != null
		and state.current_position == WrestlerResource.Position.STANDING
		and state.current_orientation == WrestlerResource.Orientation.FRONT
		and state.current_area == WrestlerResource.Area.IN_RING
		and state.current_motion_state == WrestlerResource.MotionState.STATIONARY
	)


func _format_match_time(seconds: int) -> String:
	return "%02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]


func _load_roster() -> void:
	_roster.clear()
	var resource_paths: Array[String] = []
	_collect_wrestler_paths(ROSTER_DIRECTORY, resource_paths)
	for path in resource_paths:
		var resource := ResourceLoader.load(path)
		if resource is WrestlerResource:
			_roster.append(resource as WrestlerResource)
	_roster.sort_custom(func(left: WrestlerResource, right: WrestlerResource) -> bool:
		var left_name: String = left.wrestler_name.strip_edges()
		var right_name: String = right.wrestler_name.strip_edges()
		if left_name.nocasecmp_to(right_name) == 0:
			return left.resource_path.nocasecmp_to(right.resource_path) < 0
		return left_name.nocasecmp_to(right_name) < 0
	)


func _collect_wrestler_paths(directory_path: String, paths: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_wrestler_paths(directory_path.path_join(entry.trim_suffix("/")), paths)
		elif entry.get_extension().to_lower() == "tres":
			paths.append(directory_path.path_join(entry))


func _resolve_initial_assignments() -> void:
	if _roster.is_empty():
		player_wrestler = null
		ai_wrestler = null
		_selection_status.text = "No WrestlerResource files were found in res://Wrestlers."
		return
	if player_wrestler == null:
		player_wrestler = _roster[0]
	if ai_wrestler == null or _same_wrestler(player_wrestler, ai_wrestler):
		ai_wrestler = _first_wrestler_except(player_wrestler)
	if ai_wrestler == null:
		_selection_status.text = "At least two wrestlers are required for a Player vs AI match."


func _populate_selectors() -> void:
	_player_selector.clear()
	_ai_selector.clear()
	if _roster.is_empty():
		_player_selector.add_item("No wrestlers found")
		_ai_selector.add_item("No wrestlers found")
		_player_selector.disabled = true
		_ai_selector.disabled = true
		return
	for roster_wrestler in _roster:
		var display_name: String = roster_wrestler.wrestler_name.strip_edges()
		if display_name.is_empty():
			display_name = roster_wrestler.resource_path.get_file().get_basename().capitalize()
		_player_selector.add_item(display_name)
		_ai_selector.add_item(display_name)
	_sync_selector_to_resource(_player_selector, player_wrestler)
	_sync_selector_to_resource(_ai_selector, ai_wrestler)
	_update_disabled_options()


func _sync_selector_to_resource(selector: OptionButton, value: WrestlerResource) -> void:
	var index := _roster_index(value)
	if index >= 0:
		selector.select(index)


func _update_disabled_options() -> void:
	if _roster.is_empty():
		return
	var player_popup := _player_selector.get_popup()
	var ai_popup := _ai_selector.get_popup()
	for index in _roster.size():
		player_popup.set_item_disabled(index, _same_wrestler(_roster[index], ai_wrestler))
		ai_popup.set_item_disabled(index, _same_wrestler(_roster[index], player_wrestler))


func _on_player_selected(index: int) -> void:
	if index < 0 or index >= _roster.size():
		return
	var selected := _roster[index]
	if _same_wrestler(selected, ai_wrestler):
		_sync_selector_to_resource(_player_selector, player_wrestler)
		_selection_status.text = "Player and AI must be different wrestlers."
		return
	set_player_wrestler(selected)


func _on_ai_selected(index: int) -> void:
	if index < 0 or index >= _roster.size():
		return
	var selected := _roster[index]
	if _same_wrestler(selected, player_wrestler):
		_sync_selector_to_resource(_ai_selector, ai_wrestler)
		_selection_status.text = "Player and AI must be different wrestlers."
		return
	set_ai_wrestler(selected)


func _first_wrestler_except(excluded: WrestlerResource) -> WrestlerResource:
	for roster_wrestler in _roster:
		if not _same_wrestler(roster_wrestler, excluded):
			return roster_wrestler
	return null


func _roster_index(value: WrestlerResource) -> int:
	if value == null:
		return -1
	for index in _roster.size():
		if _same_wrestler(_roster[index], value):
			return index
	return -1


func _same_wrestler(left: WrestlerResource, right: WrestlerResource) -> bool:
	if left == null or right == null:
		return false
	if left == right:
		return true
	return not left.resource_path.is_empty() and left.resource_path == right.resource_path
