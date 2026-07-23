extends Control
class_name SimpleMatchUI

signal match_presentation_state_changed(snapshots: Array, context: Dictionary)
signal match_presentation_event(event: Dictionary)
signal full_report_requested(report: Dictionary)
signal new_match_requested
signal return_to_exhibition_requested
signal return_to_main_menu_requested

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
	TABLE_BREAK,
	LADDER_RETRIEVAL,
}

const ROSTER_DIRECTORY := "res://Wrestlers"
const AI_DELAY_SECONDS := 0.6
const MATCH_RESULT_REVEAL_DELAY_SECONDS := 0.65
const GROUNDED_ATTACKER_RECOVERY_CHANCE := 0.80
const TAUNT_COOLDOWN_SECONDS := 120
const INTERACTION_CANCELLED := -100
const COUNT_OUT_INTERVAL_SECONDS := 30
const SUCCESSFUL_MOVE_MOMENTUM := 10.0
const REVERSAL_ATTACKER_MOMENTUM_LOSS := 5.0
const REVERSAL_DEFENDER_MOMENTUM_GAIN := 5.0
const DIFFICULTY_DIAGNOSTICS_SCRIPT = preload("res://Scripts/Match/match_difficulty_diagnostics.gd")
const WEAPON_CATALOGUE: WeaponCatalogueResource = preload("res://Weapons/weapon_catalogue.tres")
const STEEL_CHAIR: WeaponResource = preload("res://Weapons/steel_chair.tres") # Legacy compatibility only.

@export var player_wrestler: WrestlerResource
@export var ai_wrestler: WrestlerResource
@export_range(0.05, 2.0, 0.05) var live_refresh_interval: float = 0.2
@export_range(1.0, 3.0, 0.05) var submission_resolution_speed_multiplier: float = 1.5
@export var difficulty_diagnostics_enabled: bool = false

var player_side_state := MatchSideState.new()
var ai_side_state := MatchSideState.new()
var _ai_decision_engine := MatchAIDecisionEngine.new()
var _difficulty_diagnostics = DIFFICULTY_DIAGNOSTICS_SCRIPT.new()
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
var _match_story_events: Array[Dictionary] = []
var _archive_report_saved: bool = false
var _archive_save_error: String = ""
var _match_setup_metadata: Dictionary = {}
var _match_rules := MatchRules.new()
var _environment_state := MatchEnvironmentState.new()
var _objective_state = preload("res://Scripts/Match/match_objective_state.gd").new()
var _dropped_weapon: WeaponResource # Legacy unfinished-screen compatibility.
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
var _last_player_pin_count: int = 0
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
var _move_button_prestige_style: StyleBoxFlat
var _move_button_default_font_color: Color
var _weapon_runtime_moves: Dictionary = {}
var _weapon_move_metadata: Dictionary = {}
var _pending_weapon_action: Dictionary = {}
var _ai_illegal_weapon_gate_open: bool = false
var _chair_shot_move: MoveResource # Retained for the unused legacy helper.

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
@onready var _weapon_radial_menu: WeaponRadialMenu = %WeaponRadialMenu
@onready var _interaction_overlay: MatchInteractionOverlay = %MatchInteractionOverlay
@onready var _match_result_popup = %MatchResultPopup
@onready var _pause_button: Button = %PauseButton
@onready var _pause_menu: MatchPauseMenu = %MatchPauseMenu


func _ready() -> void:
	_build_runtime_weapon_moves()
	var legacy_chair_moves: Array = _weapon_runtime_moves.get("steel_chair", [])
	_chair_shot_move = legacy_chair_moves[0] if not legacy_chair_moves.is_empty() else null
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
	_weapon_radial_menu.weapon_selected.connect(_on_weapon_selected)
	_weapon_radial_menu.cancelled.connect(_on_weapon_selection_cancelled)
	_interaction_overlay.submission_damage_tick.connect(_on_submission_damage_tick)
	_interaction_overlay.submission_state_changed.connect(_on_submission_state_changed)
	_interaction_overlay.pin_count_reached.connect(_on_pin_count_reached)
	_match_result_popup.view_report_requested.connect(_on_result_view_report_requested)
	_match_result_popup.new_match_requested.connect(_on_new_match_requested)
	_match_result_popup.closed.connect(_on_result_popup_closed)
	_pause_button.pressed.connect(_open_pause_menu)
	_pause_menu.return_to_exhibition_requested.connect(_on_pause_return_to_exhibition)
	_pause_menu.return_to_main_menu_requested.connect(_on_pause_return_to_main_menu)
	_pause_button.visible = OS.has_feature("mobile") or OS.has_feature("android")
	_cache_move_button_styles()
	_load_roster()
	_resolve_initial_assignments()
	_populate_selectors()


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
		_move_button_prestige_style = normal_style.duplicate() as StyleBoxFlat
	if _move_button_available_style != null:
		_move_button_available_style.bg_color = AppThemePalette.SECONDARY_PANEL
		_move_button_available_style.border_color = AppThemePalette.ACTIVE
		_move_button_available_style.border_width_left = 2
		_move_button_available_style.border_width_top = 2
		_move_button_available_style.border_width_right = 2
		_move_button_available_style.border_width_bottom = 2
	if _move_button_prestige_style != null:
		_move_button_prestige_style.bg_color = AppThemePalette.SECONDARY_PANEL
		_move_button_prestige_style.border_color = AppThemePalette.PRESTIGE
		_move_button_prestige_style.border_width_left = 2
		_move_button_prestige_style.border_width_top = 2
		_move_button_prestige_style.border_width_right = 2
		_move_button_prestige_style.border_width_bottom = 2
	_move_button_default_font_color = _move_selector_button.get_theme_color("font_color")


func _exit_tree() -> void:
	_turn_generation += 1
	if is_instance_valid(_pause_menu):
		_pause_menu.force_close()
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
	var vertical_margin := page_margin
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
	_environment_state.reset()
	_objective_state.reset()
	_reset_referee_count_runtime()
	is_resolving_action = false
	contest_prompt_active = false
	pin_sequence_active = false
	submission_sequence_active = false
	_latest_match_report.clear()
	_match_story_events.clear()
	_archive_report_saved = false
	_archive_save_error = ""
	match_log_entries.clear()
	player_side_state.initialize(player_wrestler)
	ai_side_state.initialize(ai_wrestler)
	_difficulty_diagnostics.begin_match(
		difficulty_diagnostics_enabled,
		{
			"player": _side_name(Side.PLAYER),
			"ai": _side_name(Side.AI),
			"clock_increment_seconds": (
				_match_rules.action_clock_seconds
				if _match_rules != null
				else MatchRules.DEFAULT_ACTION_CLOCK_SECONDS
			),
			"setup": _match_setup_metadata,
		},
	)
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
	_weapon_radial_menu.close_menu()
	_pending_weapon_action.clear()
	_interaction_overlay.close_interaction(true)
	_result_banner.visible = false
	_result_banner.text = ""
	_view_report_button.visible = false
	_new_match_button.visible = false
	_match_result_popup.close_result()
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
	var presentation_context := context.duplicate(true)
	presentation_context["environment_objects"] = _environment_state.snapshots()
	match_presentation_state_changed.emit(snapshots, presentation_context)


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
		"disposition": int(state.wrestler.wrestler_disposition),
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
		"bleeding_label": state.bleeding_label(),
		"bleeding_severity": state.bleeding_severity,
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
			state.add_fatigue(state.bleeding_fatigue_per_action())
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
				add_match_log_entry("%s dives back inside at %d!" % [_side_name(side), _referee_count_value], AppThemePalette.WARNING)
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
		add_match_log_entry("Neither wrestler made it back — the referee calls for the bell.", AppThemePalette.ERROR)
		end_match(Side.NONE, Side.NONE, FinishType.DOUBLE_COUNT_OUT, null, "Both wrestlers failed to answer the count.", "Referee count %d" % _referee_count_value)
		return
	var counted_out_side: int = int(outside_sides[0])
	var winning_side := _opponent_side(counted_out_side)
	add_match_log_entry("That's %d! %s has been counted out." % [_match_rules.count_out_limit, _side_name(counted_out_side)], AppThemePalette.ERROR)
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
	add_match_log_entry("The referee begins the count.", AppThemePalette.WARNING)
	_emit_ring_event(&"count_started", Side.NONE, Side.NONE, {"count": 0, "limit": _match_rules.count_out_limit})
	_update_referee_count_presentation()


func _announce_referee_count(value: int) -> void:
	if value <= _last_count_commentary_value:
		return
	_last_count_commentary_value = value
	var words := ["", "ONE!", "TWO!", "THREE!", "FOUR!", "FIVE!", "SIX!", "SEVEN!", "EIGHT!", "NINE!", "TEN!"]
	var count_text: String = str(words[value]) if value < words.size() else "%d!" % value
	add_match_log_entry(count_text, AppThemePalette.WARNING)
	if value == _match_rules.count_out_limit - 1:
		add_match_log_entry("They are one count away from losing the match on the floor.", AppThemePalette.ERROR)
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
	if state == null:
		return false
	if state.current_area == WrestlerResource.Area.LADDER:
		return _match_rules.is_outside_area(_ladder_base_area(side))
	return _match_rules.is_outside_area(state.current_area)


func _update_referee_count_presentation() -> void:
	if not is_node_ready() or not is_instance_valid(_referee_count_badge):
		return
	_referee_count_badge.visible = _referee_count_active and not match_ended
	_referee_count_badge.text = "COUNT: %d / %d" % [_referee_count_value, _match_rules.count_out_limit]


func add_match_log_entry(
	message: String,
	color: Color = AppThemePalette.PRIMARY_TEXT,
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
	timestamp.add_theme_color_override("font_color", AppThemePalette.SECONDARY_TEXT)
	var divider := Label.new()
	divider.text = "—"
	divider.add_theme_color_override("font_color", AppThemePalette.DISABLED_TEXT)
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
	for weapon_move in _available_weapon_moves(side):
		if weapon_move not in valid:
			valid.append(weapon_move)
	var armed_environment := _positioned_environment_for_side(_opponent_side(side))
	if armed_environment != null and armed_environment.positioned_by_side == side:
		var filtered: Array[MoveResource] = []
		var stacked := armed_environment.lifecycle == MatchWeaponInstance.Lifecycle.SET_STACKED
		for candidate in valid:
			if _qualifies_environment_followup(candidate, armed_environment, stacked):
				filtered.append(candidate)
		valid = filtered
	return valid


func get_valid_setup_actions(side: int) -> Array[StringName]:
	var actor := _state_for_side(side)
	var target := _state_for_side(_opponent_side(side))
	if actor == null or target == null or actor.wrestler == null:
		return []
	var cache_key := "%d|%s|%s|%d|%d|%d|%d|%d|%s|%s|%d|%d|%s|%d|%d|%d" % [
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
		_environment_cache_key(),
		roundi(actor.stamina),
		roundi(actor.fatigue),
		actor.catch_breath_cooldown_until_seconds,
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
		if action_id == SetupActionsMenu.CATCH_BREATH and (
			actor.stamina_percent() >= MatchExhaustionModel.CATCH_BREATH_STAMINA_THRESHOLD
			or _match_time_seconds < actor.catch_breath_cooldown_until_seconds
		):
			continue
		if (
			MatchSetupStateRules.is_recovery(action_id)
			or action_id == SetupActionsMenu.TAUNT
			or action_id == SetupActionsMenu.CATCH_BREATH
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
	var ai_may_use_weapons := side != Side.AI or _ai_weapon_rule_gate(actor, target)
	if (
		actor.held_weapon == null
		and actor.current_area == WrestlerResource.Area.OUTSIDE
		and actor.current_position == WrestlerResource.Position.STANDING
		and actor.current_motion_state == WrestlerResource.MotionState.STATIONARY
		and ai_may_use_weapons
		and not _available_retrieval_weapons().is_empty()
	):
		actions.append(SetupActionsMenu.RETRIEVE_WEAPON)
	if (
		actor.held_weapon == null
		and not _dropped_instances_in_area(actor.current_area).is_empty()
		and actor.current_position == WrestlerResource.Position.STANDING
		and actor.current_motion_state == WrestlerResource.MotionState.STATIONARY
		and ai_may_use_weapons
	):
		actions.append(SetupActionsMenu.PICK_UP_WEAPON)
	if actor.held_weapon != null:
		actions.append(SetupActionsMenu.DROP_WEAPON)
		match actor.held_weapon.weapon_kind:
			WeaponResource.WeaponKind.TABLE:
				if actor.current_area in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.OUTSIDE]:
					actions.append(SetupActionsMenu.SET_TABLE_FLAT)
					if _environment_state.find_setup(WeaponResource.WeaponKind.TABLE, actor.current_area, MatchWeaponInstance.Lifecycle.SET_FLAT) != null:
						actions.append(SetupActionsMenu.STACK_TABLE)
				if actor.current_area == WrestlerResource.Area.IN_RING:
					actions.append(SetupActionsMenu.SET_TABLE_CORNER)
			WeaponResource.WeaponKind.LADDER:
				if actor.current_area in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.OUTSIDE]:
					actions.append(SetupActionsMenu.SET_UP_LADDER)
			WeaponResource.WeaponKind.THUMBTACKS:
				if actor.current_area in [WrestlerResource.Area.IN_RING, WrestlerResource.Area.OUTSIDE]:
					actions.append(SetupActionsMenu.SPREAD_THUMBTACKS)
	_append_active_environment_actions(side, actor, target, actions)


func _ai_weapon_rule_gate(actor: MatchSideState, target: MatchSideState) -> bool:
	if not _match_rules.disqualifications_enabled:
		return true
	return _ai_illegal_weapon_gate_open


func _roll_ai_illegal_weapon_gate(actor: MatchSideState, target: MatchSideState) -> bool:
	if not _match_rules.disqualifications_enabled:
		return true
	if actor == null or target == null:
		return false
	var heel_gate: bool = (
		actor.wrestler != null
		and actor.wrestler.wrestler_disposition == WrestlerResource.WrestlerDisposition.HEEL
		and randf() < 0.02
	)
	var damage_gap: float = actor.damage_taken - target.damage_taken
	var desperation_gate: bool = (
		_match_time_seconds >= 900
		and (target.momentum - actor.momentum >= 35.0 or damage_gap >= 30.0)
		and randf() < 0.05
	)
	return heel_gate or desperation_gate


func _available_retrieval_weapons() -> Array[WeaponResource]:
	var result: Array[WeaponResource] = []
	if WEAPON_CATALOGUE == null:
		return result
	for weapon in WEAPON_CATALOGUE.valid_weapons():
		if _environment_state.can_retrieve(weapon):
			result.append(weapon)
	return result


func _dropped_instances_in_area(area: int) -> Array[MatchWeaponInstance]:
	return _environment_state.instances_in_area(area, [MatchWeaponInstance.Lifecycle.DROPPED])


func _append_active_environment_actions(
	side: int,
	actor: MatchSideState,
	target: MatchSideState,
	actions: Array[StringName],
) -> void:
	var table := _active_table(target.current_area)
	if table != null:
		if table.positioned_side == side:
			actions.append(SetupActionsMenu.MOVE_CLEAR_TABLE)
		elif table.positioned_side == Side.NONE and _has_qualifying_environment_followup(side, table, table.lifecycle == MatchWeaponInstance.Lifecycle.SET_STACKED):
			if table.lifecycle == MatchWeaponInstance.Lifecycle.SET_CORNER:
				actions.append(SetupActionsMenu.POSITION_AT_CORNER_TABLE)
			else:
				actions.append(SetupActionsMenu.LAY_ON_TABLE if target.current_position in [WrestlerResource.Position.GROUNDED, WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING] else SetupActionsMenu.POSITION_AT_TABLE)
	var tacks := _active_tacks(target.current_area)
	if tacks != null:
		if tacks.positioned_side == side:
			actions.append(SetupActionsMenu.MOVE_CLEAR_THUMBTACKS)
		elif tacks.positioned_side == Side.NONE and _has_qualifying_environment_followup(side, tacks, false):
			actions.append(SetupActionsMenu.POSITION_OVER_THUMBTACKS)
	var ladder := _environment_state.find_setup(WeaponResource.WeaponKind.LADDER, actor.current_area, MatchWeaponInstance.Lifecycle.SET_LADDER)
	if ladder != null:
		if actor.current_area != WrestlerResource.Area.LADDER and actor.current_position == WrestlerResource.Position.STANDING and _has_ladder_aerial(side):
			actions.append(SetupActionsMenu.CLIMB_LADDER)
		elif actor.current_area == WrestlerResource.Area.LADDER and actor.current_position == WrestlerResource.Position.CLIMBING:
			actions.append(SetupActionsMenu.CLIMB_LADDER_TOP)
			actions.append(SetupActionsMenu.CLIMB_DOWN_LADDER)
		elif actor.current_area == WrestlerResource.Area.LADDER and actor.current_position == WrestlerResource.Position.PERCHED:
			actions.append(SetupActionsMenu.CLIMB_DOWN_LADDER)
	if target.current_area == WrestlerResource.Area.LADDER and target.current_position in [WrestlerResource.Position.CLIMBING, WrestlerResource.Position.PERCHED]:
		actions.append(SetupActionsMenu.TIP_LADDER)


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


func _build_runtime_weapon_moves() -> void:
	_weapon_runtime_moves.clear()
	_weapon_move_metadata.clear()
	if WEAPON_CATALOGUE == null:
		return
	for weapon in WEAPON_CATALOGUE.valid_weapons():
		var moves: Array[MoveResource] = []
		for attack in weapon.attack_set:
			if attack == null:
				continue
			var move := MoveResource.new()
			move.move_name = attack.display_name
			move.move_type = MoveResource.MoveType.WEAPON
			move.move_target_parts = [weapon.target_body_part]
			move.targeting_mode = MoveResource.TargetingMode.FIXED_PARTS
			move.required_weapon_id = weapon.weapon_id
			move.required_attacker_position = WrestlerResource.Position.STANDING
			move.required_attacker_orientation = WrestlerResource.Orientation.NONE
			move.required_attacker_area_mode = MoveResource.AreaRequirementMode.ANY
			move.required_attacker_motion_state = WrestlerResource.MotionState.STATIONARY
			move.required_target_position = (
				WrestlerResource.Position.STANDING
				if attack.target_posture == WeaponAttackResource.TargetPosture.STANDING
				else WrestlerResource.Position.GROUNDED
			)
			if attack.target_posture == WeaponAttackResource.TargetPosture.GROUNDED:
				move.additional_valid_target_positions = [WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING]
			move.required_target_orientation = WrestlerResource.Orientation.NONE
			move.required_target_area_mode = MoveResource.AreaRequirementMode.SAME_AS_OTHER
			move.required_target_motion_state = WrestlerResource.MotionState.STATIONARY
			move.resulting_attacker_position = WrestlerResource.Position.STANDING
			move.resulting_target_position = attack.resulting_target_position
			move.resulting_target_orientation = attack.resulting_target_orientation
			move.move_impact = clampi(weapon.impact + attack.impact_modifier, 1, 10)
			move.is_strike = attack.is_strike
			move.interaction_override = attack.interaction_override
			moves.append(move)
			_weapon_move_metadata[move.get_instance_id()] = {"weapon": weapon, "attack": attack}
		_weapon_runtime_moves[String(weapon.weapon_id)] = moves


func _weapon_metadata_for_move(move: MoveResource) -> Dictionary:
	if move == null:
		return {}
	return _weapon_move_metadata.get(move.get_instance_id(), {})


func _available_weapon_moves(side: int) -> Array[MoveResource]:
	var result: Array[MoveResource] = []
	var actor := _state_for_side(side)
	if actor == null or actor.held_weapon == null or actor.held_weapon_uses_remaining <= 0:
		return result
	var candidates: Array = _weapon_runtime_moves.get(String(actor.held_weapon.weapon_id), [])
	for candidate in candidates:
		var move := candidate as MoveResource
		if move != null and _move_is_valid(side, move):
			result.append(move)
	return result


func _match_state_cache_key(state: MatchSideState) -> String:
	if state == null:
		return "none"
	return "%d:%d:%d:%d" % [
		state.current_position,
		state.current_orientation,
		state.current_area,
		state.current_motion_state,
	]


func _environment_cache_key() -> String:
	var parts: Array[String] = []
	for instance in _environment_state.instances:
		if instance == null or not instance.is_live():
			continue
		parts.append("%d:%d:%d:%d:%d" % [instance.instance_id, instance.lifecycle, instance.area, instance.positioned_side, instance.durability])
	return ",".join(parts)


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
				AppThemePalette.WARNING,
			)
		_clear_selected_move()
		refresh_match_ui()
		return
	if not _weapon_metadata_for_move(move).is_empty():
		await _execute_weapon_move(attacker_side, move, target_resolution)
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
	var environmental_followup := _is_environmental_followup(
		attacker_side,
		defender_side,
		move,
	)
	var started_at_zero_stamina := attacker_state != null and attacker_state.stamina <= 0.0
	if attacker_state != null:
		var exhaustion_profile := MatchExhaustionModel.profile(
			attacker_state,
			move,
			attacker_state.is_signature_move(move),
			_is_ladder_variant(move, attacker_state),
			environmental_followup,
		)
		attacker_state.note_exhaustion_profile(exhaustion_profile)
		if float(exhaustion_profile.get("execution_penalty", 0.0)) > 0.0:
			attacker_state.low_stamina_penalties_applied += 1
		if started_at_zero_stamina:
			attacker_state.actions_attempted_at_zero_stamina += 1
		if _is_high_risk(move) and int(exhaustion_profile.get("band", 0)) >= MatchExhaustionModel.ExhaustionBand.EXHAUSTED:
			attacker_state.exhausted_high_risk_attempts += 1
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
	if match_ended:
		return
	# Resolve authored ring-entry/exit before an embedded cover or submission.
	# Apron springboards remain count-out safe; moves that land outside keep the
	# referee count alive (or complete it) before the next interaction begins.
	_settle_referee_count("move result state")
	if match_ended:
		return
	_note_exhaustion_action_result(attacker_side, attacker_state, result, started_at_zero_stamina)
	_difficulty_diagnostics.record(
		&"move_resolved",
		{
			"match_time": _match_time_seconds,
			"actor": _side_name(attacker_side),
			"move": _move_name(move),
			"result": _ring_action_result_name(result),
			"stamina_after": attacker_state.stamina,
			"fatigue_after": attacker_state.fatigue,
			"momentum_after": attacker_state.momentum,
			"reversed": reversed,
		},
	)
	if match_ended:
		return
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
	_resolve_control_after_action(
		attacker_side,
		defender_side,
		move,
		result,
		MatchExhaustionModel.Demand.EXPLOSIVE if environmental_followup else -1,
	)
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
	if not _pin_area_is_legal(attacker_side, defender_side):
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
	var attribute_reversal_profile := MatchAttributeModel.get_reversal_modifier(
		attacker,
		defender,
		move,
		&"",
	)
	defender.note_attribute_reversal_profile(attribute_reversal_profile)
	var result := MatchInteractionModel.InputResult.FAIL
	if defender_side == Side.PLAYER:
		var request := profile.duplicate(true)
		request["title"] = "%s: %s" % ["ESCAPE" if move.is_submission else "REVERSE", _move_name(move)]
		request["prompt"] = "Stop the moving marker inside the green zone."
		request["button_text"] = "ESCAPE" if move.is_submission else "REVERSE"
		var response := await _run_visible_reversal_meter(request)
		if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
			return INTERACTION_CANCELLED
		result = (
			MatchInteractionModel.InputResult.SUCCESS
			if int(response.get("result", MatchInteractionModel.InputResult.FAIL)) == MatchInteractionModel.InputResult.SUCCESS
			else MatchInteractionModel.InputResult.FAIL
		)
	elif attacker_side == Side.PLAYER:
		# The AI's reversal chance is player-facing rather than resolved by a
		# hidden roll. Hitting gold means the Player breaks through the attempted
		# counter; missing means the AI completes the reversal.
		var request := _build_ai_reversal_breakthrough_request(profile, move)
		var response := await _run_visible_control_meter(request)
		if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
			return INTERACTION_CANCELLED
		var player_broke_through := (
			int(response.get("result", MatchInteractionModel.InputResult.FAIL))
			== MatchInteractionModel.InputResult.SUCCESS
		)
		result = (
			MatchInteractionModel.InputResult.FAIL
			if player_broke_through
			else MatchInteractionModel.InputResult.SUCCESS
		)
	else:
		result = _simulate_binary_result(float(profile.get("ai_success_chance", 22.0)))
	if result == MatchInteractionModel.InputResult.SUCCESS:
		defender.response_successes += 1
	_difficulty_diagnostics.record(
		&"defender_response",
		{
			"match_time": _match_time_seconds,
			"attacker": _side_name(attacker_side),
			"defender": _side_name(defender_side),
			"move": _move_name(move),
			"chance": profile.get("ai_success_chance", 0.0),
			"result": "success" if result == MatchInteractionModel.InputResult.SUCCESS else "fail",
		},
	)
	return result


func _build_ai_reversal_breakthrough_request(profile: Dictionary, move: MoveResource) -> Dictionary:
	var request := profile.duplicate(true)
	var ai_reversal_chance := clampf(float(profile.get("ai_success_chance", 22.0)), 5.0, 75.0)
	# This is a timing challenge, not a second probability roll. Inverting the AI
	# chance makes stronger reversal pressure visibly narrow the Player's safe
	# target. Keep the one-eighth visual scale, but cap the raw breakthrough
	# window at 32 rather than the defender meter's 65: ordinary AI reversal
	# profiles were otherwise pinning this Player-offence target at an overly
	# generous 8.125% for most moves.
	var player_breakthrough_chance := 100.0 - ai_reversal_chance
	var visible_window := player_breakthrough_chance * 0.78
	request["success_window"] = clampf(visible_window, 24.0, 32.0)
	request["gold_zone_scale"] = 1.0 / 8.0
	request["raw_zone_min"] = 24.0
	request["raw_zone_max"] = 32.0
	request["title"] = "BEAT THE REVERSAL: %s" % _move_name(move)
	request["prompt"] = "Stop the marker in gold to land the move. Miss and the opponent reverses."
	request["button_text"] = "LAND MOVE"
	request["binary_only"] = true
	request["marker_speed"] = 1.6
	request["edge_forgiveness"] = 0.0
	request["edge_forgiveness_pixels"] = 0.0
	request["touch_edge_forgiveness"] = 0.0
	request["touch_edge_forgiveness_pixels"] = 0.0
	request["ai_reversal_chance"] = ai_reversal_chance
	request["player_breakthrough_window"] = (
		float(request["success_window"])
		* float(request["gold_zone_scale"])
	)
	return request


func _build_ai_setup_reversal_breakthrough_request(
	profile: Dictionary,
	action_id: StringName,
) -> Dictionary:
	var request := _build_ai_reversal_breakthrough_request(profile, null)
	request["title"] = "BEAT THE REVERSAL: %s" % _setup_action_short_name(action_id)
	request["prompt"] = "Stop the marker in gold to complete the setup. Miss and the opponent reverses."
	request["button_text"] = "COMPLETE SETUP"
	return request


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
		_record_story_event(&"reversal", defender_side, {
			"move": _move_name(move),
			"against": _side_name(attacker_side),
		})
	var reversed_finisher_reward := 0
	if reversal_landed and attacker.is_finisher_move(move):
		reversed_finisher_reward = defender.grant_finisher_stock()
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
		_record_story_event(&"high_risk_crash", attacker_side, {"move": _move_name(move)})
	apply_damage(attacker_side, defender_side, move, result, target_resolution)
	apply_stamina_fatigue_momentum(attacker_side, defender_side, move, result)
	apply_positions(attacker_side, defender_side, move, result)
	_resolve_environment_after_move(attacker_side, defender_side, move, result, target_resolution)
	if match_ended:
		return
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
					AppThemePalette.PRESTIGE if move.is_finisher else AppThemePalette.PRIMARY_TEXT,
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
			if reversed_finisher_reward > 0:
				add_match_log_entry(
					"%s turns the finisher reversal into finisher stock (%d/%d)." % [
						defender_name,
						defender.finisher_stock,
						MatchSideState.MAX_FINISHER_STOCK,
					],
					AppThemePalette.PRESTIGE,
				)
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
			if reversed_finisher_reward > 0:
				add_match_log_entry(
					"%s turns the finisher reversal into finisher stock (%d/%d)." % [
						defender_name,
						defender.finisher_stock,
						MatchSideState.MAX_FINISHER_STOCK,
					],
					AppThemePalette.PRESTIGE,
				)
	if signature_converted:
		add_match_log_entry(
			"%s converts the signature into finisher stock (%d/%d)." % [
				attacker_name,
				attacker.finisher_stock,
				MatchSideState.MAX_FINISHER_STOCK,
			],
			AppThemePalette.PRESTIGE,
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
	var ladder_variant := _is_ladder_variant(move, attacker)
	var attribute_profile := MatchAttributeModel.get_move_attribute_profile(
		attacker,
		defender,
		move,
		{
			"ladder_variant": ladder_variant,
			"environmental_followup": _is_environmental_followup(attacker_side, defender_side, move),
		},
	)
	var attribute_damage_multiplier := float(attribute_profile.get("damage_multiplier", 1.0))
	var part_hp_before: Dictionary = {}
	for part in target_resolution.get("parts", []):
		part_hp_before[int(part)] = defender.get_part_hp(int(part))
	if result == ActionResult.HIGH_RISK_CRASH:
		attacker.damage_part(MoveResource.MoveTargetParts.BODY, float(move.move_impact) * 0.75 * (1.25 if ladder_variant else 1.0))
		if ladder_variant:
			attacker.ladder_crashes += 1
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
			defender.damage_part(part_id, damage * modifier * float(weights.get(part_id, 1.0)) * (1.20 if ladder_variant else 1.0) * attribute_damage_multiplier)
		if ladder_variant:
			attacker.ladder_dives += 1
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
		attacker.note_attribute_damage_profile(attribute_profile)
		_record_story_event(
			&"move_landed",
			attacker_side,
			{
				"move": _move_name(move),
				"impact": move.move_impact,
				"signature": attacker.is_signature_move(move),
				"finisher": attacker.is_finisher_move(move),
				"high_risk": _is_high_risk(move),
			},
		)
		if attacker.is_signature_move(move):
			_record_story_event(&"signature_landed", attacker_side, {"move": _move_name(move)})
		if attacker.is_finisher_move(move):
			_record_story_event(&"finisher_landed", attacker_side, {"move": _move_name(move)})
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
	add_match_log_entry(chosen_message, AppThemePalette.ERROR if critical else AppThemePalette.SECONDARY_TEXT)


func apply_stamina_fatigue_momentum(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var stamina_cost := _stamina_cost(move)
	var ladder_variant := _is_ladder_variant(move, attacker)
	if ladder_variant:
		stamina_cost *= 1.25
	var demand := MatchExhaustionModel.effective_move_demand(
		move,
		attacker.is_signature_move(move),
		ladder_variant,
		_is_environmental_followup(attacker_side, defender_side, move),
	)
	stamina_cost *= MatchExhaustionModel.stamina_cost_multiplier(attacker, demand)
	var attacker_fatigue := 2.0 + (4.0 if _is_high_risk(move) else 0.0) + (4.0 if move.is_finisher else 0.0)
	match result:
		ActionResult.CLEAN_SUCCESS:
			attacker.spend_stamina(stamina_cost)
			attacker.add_fatigue(attacker_fatigue)
			defender.add_fatigue(2.0 + (4.0 if move.is_finisher else 0.0))
			_apply_successful_move_momentum(attacker)
		ActionResult.LABOURED_SUCCESS:
			attacker.spend_stamina(stamina_cost * 1.10)
			attacker.add_fatigue(attacker_fatigue + 1.0)
			defender.add_fatigue(1.0)
			_apply_successful_move_momentum(attacker)
		ActionResult.CONTESTED_STRUGGLE:
			attacker.spend_stamina(stamina_cost)
			defender.spend_stamina(maxf(2.0, stamina_cost * 0.25))
			attacker.add_fatigue(2.0)
			defender.add_fatigue(2.0)
		ActionResult.BOTCH_OR_SCRAMBLE:
			var heavy_failure := move.move_impact >= 7 or MatchInteractionModel.get_interaction_type_for_move(move) == MatchInteractionModel.InteractionType.HOLD_POWER
			attacker.spend_stamina(stamina_cost * (0.80 if heavy_failure else 0.60))
			attacker.add_fatigue(3.0)
		ActionResult.REVERSAL:
			attacker.spend_stamina(stamina_cost)
			attacker.add_fatigue(attacker_fatigue)
			_apply_reversal_momentum(attacker, defender)
		ActionResult.HIGH_RISK_CRASH:
			attacker.spend_stamina(stamina_cost)
			attacker.add_fatigue(attacker_fatigue)
			_apply_reversal_momentum(attacker, defender)
	_emit_exhaustion_threshold_commentary(attacker_side, attacker)
	_emit_exhaustion_threshold_commentary(defender_side, defender)


func _apply_successful_move_momentum(attacker: MatchSideState) -> void:
	if attacker != null:
		attacker.add_momentum(SUCCESSFUL_MOVE_MOMENTUM)


func _apply_reversal_momentum(attacker: MatchSideState, defender: MatchSideState) -> void:
	if attacker != null:
		attacker.add_momentum(-REVERSAL_ATTACKER_MOMENTUM_LOSS)
	if defender != null:
		defender.add_momentum(REVERSAL_DEFENDER_MOMENTUM_GAIN)


func _apply_setup_interruption_momentum(defender: MatchSideState) -> void:
	# Interrupting positioning earns reversal momentum, but the initiator has not
	# committed an offensive move and therefore does not lose move momentum.
	if defender != null:
		defender.add_momentum(REVERSAL_DEFENDER_MOMENTUM_GAIN)


func apply_positions(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var ladder_variant := _is_ladder_variant(move, attacker)
	var ladder_base_area := _ladder_base_area(attacker_side) if ladder_variant else WrestlerResource.Area.IN_RING
	match result:
		ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS:
			_apply_move_result_state(attacker, move, true)
			_apply_move_result_state(defender, move, false)
			if ladder_variant and attacker.current_area == WrestlerResource.Area.LADDER:
				attacker.current_area = ladder_base_area
		ActionResult.HIGH_RISK_CRASH:
			_set_high_risk_crash_state(attacker, move)
			if ladder_variant:
				attacker.current_area = ladder_base_area


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
			SetupActionsMenu.RETRIEVE_WEAPON,
			SetupActionsMenu.PICK_UP_WEAPON,
			SetupActionsMenu.DROP_WEAPON,
			SetupActionsMenu.CHAIR_SHOT,
			SetupActionsMenu.SET_TABLE_FLAT,
			SetupActionsMenu.SET_TABLE_CORNER,
			SetupActionsMenu.STACK_TABLE,
			SetupActionsMenu.POSITION_AT_TABLE,
			SetupActionsMenu.LAY_ON_TABLE,
			SetupActionsMenu.POSITION_AT_CORNER_TABLE,
			SetupActionsMenu.MOVE_CLEAR_TABLE,
			SetupActionsMenu.SET_UP_LADDER,
			SetupActionsMenu.CLIMB_LADDER,
			SetupActionsMenu.CLIMB_LADDER_TOP,
			SetupActionsMenu.TIP_LADDER,
			SetupActionsMenu.CLIMB_DOWN_LADDER,
			SetupActionsMenu.SPREAD_THUMBTACKS,
			SetupActionsMenu.POSITION_OVER_THUMBTACKS,
			SetupActionsMenu.MOVE_CLEAR_THUMBTACKS,
	]:
		await _execute_rule_action(side, action_id, actor, target)
		return
	var revalidated := MatchSetupStateRules.project_action(action_id, actor.snapshot(), target.snapshot())
	if not bool(revalidated.get("valid", false)):
		return
	_recent_reversal_side = Side.NONE
	is_resolving_action = true
	advance_match_clock()
	_record_setup_action(actor, action_id)
	if _resolve_recovery_delay_if_needed(side, action_id, actor):
		return
	if action_id == SetupActionsMenu.CATCH_BREATH:
		_execute_catch_breath(side, actor)
		return
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
	var recovery_action := MatchSetupStateRules.is_recovery(action_id)
	var setup_demand := MatchExhaustionModel.Demand.BASIC if recovery_action else MatchExhaustionModel.Demand.STANDARD
	var setup_cost := (1.0 if recovery_action else 3.0) * MatchExhaustionModel.stamina_cost_multiplier(actor, setup_demand)
	actor.spend_stamina(setup_cost)
	actor.add_fatigue(0.5 if recovery_action else 1.0)
	_emit_exhaustion_threshold_commentary(side, actor)
	if side == Side.AI:
		_ai_decision_engine.note_setup_executed(action_id, actor)
	else:
		_player_setup_intent = action_id
	last_action_result = ActionResult.SETUP_SUCCESS
	actor.last_action_result = ActionResult.SETUP_SUCCESS
	add_match_log_entry(_setup_log_message(side, action_id), AppThemePalette.ACTIVE)
	is_resolving_action = false
	_clear_selected_move_if_invalid()
	_set_controller(_control_for_side(side))
	refresh_match_ui()
	ensure_match_can_continue("automatic setup resolution")


func _execute_catch_breath(side: int, actor: MatchSideState) -> void:
	actor.catch_breath_cooldown_until_seconds = _match_time_seconds + MatchExhaustionModel.CATCH_BREATH_COOLDOWN_SECONDS
	actor.catch_breath_uses += 1
	var recovery := MatchExhaustionModel.catch_breath_recovery(actor)
	var recovered := actor.recover_stamina(recovery)
	add_match_log_entry(
		"%s backs away, catches their breath, and recovers %.1f stamina." % [_side_name(side), recovered],
		AppThemePalette.SUCCESS,
	)
	if side == Side.AI:
		_ai_decision_engine.note_setup_executed(SetupActionsMenu.CATCH_BREATH, actor)
	else:
		_player_setup_intent = &""
	last_action_result = ActionResult.SETUP_SUCCESS
	actor.last_action_result = ActionResult.SETUP_SUCCESS
	is_resolving_action = false
	_clear_selected_move_if_invalid()
	# Catching breath deliberately surrenders initiative: the opponent receives
	# the existing 80/20 favored-side neutral recovery roll.
	_neutral_recovery_favored_side = _opponent_side(side)
	_set_resolved_controller(ControlState.NEUTRAL, side, _opponent_side(side))
	_difficulty_diagnostics.record(
		&"catch_breath",
		{
			"match_time": _match_time_seconds,
			"actor": _side_name(side),
			"recovered": recovered,
			"stamina_after": actor.stamina,
			"fatigue": actor.fatigue,
			"favored_next_side": _side_name(_opponent_side(side)),
		},
	)
	refresh_match_ui()
	ensure_match_can_continue("catch breath resolution")


func _resolve_recovery_delay_if_needed(
	side: int,
	action_id: StringName,
	actor: MatchSideState,
) -> bool:
	if actor == null or not _is_delayable_recovery_action(action_id):
		return false
	if actor.recovery_delay_protected:
		actor.recovery_delay_protected = false
		return false
	var chance := MatchExhaustionModel.recovery_delay_chance(
		actor,
		actor.last_action_result == ActionResult.HIGH_RISK_CRASH,
	)
	if randf() * 100.0 >= chance:
		return false
	actor.recovery_delay_protected = true
	actor.exhaustion_delayed_recoveries += 1
	actor.spend_stamina(MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.BASIC))
	actor.add_fatigue(0.5)
	add_match_log_entry(
		"%s tries to recover, but exhaustion keeps them down for another beat." % _side_name(side),
		AppThemePalette.WARNING,
	)
	_emit_exhaustion_threshold_commentary(side, actor)
	is_resolving_action = false
	_set_resolved_controller(ControlState.NEUTRAL, side, _opponent_side(side))
	refresh_match_ui()
	ensure_match_can_continue("exhaustion recovery delay")
	return true


func _is_delayable_recovery_action(action_id: StringName) -> bool:
	return action_id in [
		SetupActionsMenu.STAND_UP,
		SetupActionsMenu.STOP_RUNNING,
		SetupActionsMenu.REGAIN_FOOTING,
		SetupActionsMenu.REGAIN_COMPOSURE,
	]


func _record_setup_action(actor: MatchSideState, action_id: StringName) -> void:
	if actor == null:
		return
	actor.setup_actions += 1
	actor.note_attribute_setup_profile(MatchAttributeModel.get_setup_modifier(actor, null, action_id))
	if action_id in [SetupActionsMenu.CATCH_BREATH, SetupActionsMenu.TAUNT]:
		return
	if MatchSetupStateRules.is_recovery(action_id):
		actor.recovery_setup_actions += 1
	else:
		actor.tactical_setup_actions += 1


func _execute_rule_action(
	side: int,
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
	selected_weapon_id: StringName = &"",
	selected_instance_id: int = 0,
) -> void:
	if actor == null or target == null:
		return
	if side == Side.PLAYER and action_id == SetupActionsMenu.RETRIEVE_WEAPON and selected_weapon_id.is_empty():
		_pending_weapon_action = {"side": side, "action": action_id}
		is_resolving_action = true
		var all_weapons: Array[WeaponResource] = []
		if WEAPON_CATALOGUE != null:
			all_weapons = WEAPON_CATALOGUE.valid_weapons()
		var availability: Dictionary = {}
		for weapon in all_weapons:
			availability[String(weapon.weapon_id)] = _environment_state.can_retrieve(weapon)
		_weapon_radial_menu.open_for_retrieval(all_weapons, availability, _match_rules.disqualifications_enabled)
		refresh_match_ui()
		return
	if side == Side.PLAYER and action_id == SetupActionsMenu.PICK_UP_WEAPON and selected_instance_id <= 0:
		_pending_weapon_action = {"side": side, "action": action_id}
		is_resolving_action = true
		_weapon_radial_menu.open_for_pickup(_dropped_instances_in_area(actor.current_area))
		refresh_match_ui()
		return
	is_resolving_action = true
	advance_match_clock()
	_record_setup_action(actor, action_id)
	var next_control_side := side
	match action_id:
		SetupActionsMenu.WAIT_FOR_COUNT:
			actor.spend_stamina(MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.BASIC))
			add_match_log_entry("%s stays safely inside and urges the referee to keep counting." % _side_name(side), AppThemePalette.WARNING)
			_emit_ring_event(&"count_wait", side, _opponent_side(side))
			# Waiting is a pass, not a control-preserving action. The wrestler on
			# the floor receives the next turn and a fair chance to beat the count.
			next_control_side = _opponent_side(side)
		SetupActionsMenu.RETRIEVE_STEEL_CHAIR, SetupActionsMenu.RETRIEVE_WEAPON:
			var weapon := _weapon_by_id(selected_weapon_id)
			if weapon == null and side == Side.AI:
				weapon = _choose_ai_weapon(actor, target)
			if actor.held_weapon != null or weapon == null or actor.current_area != WrestlerResource.Area.OUTSIDE:
				is_resolving_action = false
				ensure_match_can_continue("invalid weapon retrieval")
				return
			var durability := randi_range(mini(weapon.minimum_durability, weapon.maximum_durability), maxi(weapon.minimum_durability, weapon.maximum_durability))
			var instance := _environment_state.create_held_instance(weapon, side, actor.current_area, durability)
			if instance == null:
				is_resolving_action = false
				ensure_match_can_continue("weapon capacity rejected retrieval")
				return
			_set_held_instance(actor, instance)
			actor.weapons_retrieved += 1
			actor.last_weapon_action_time = _match_time_seconds
			actor.spend_stamina(2.0 * MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.BASIC))
			add_match_log_entry("%s reaches beneath the ring and retrieves a %s." % [_side_name(side), weapon.display_name.to_lower()], AppThemePalette.WARNING)
			if _match_rules.disqualifications_enabled:
				add_match_log_entry("The referee warns %s not to use it." % _side_name(side), AppThemePalette.WARNING)
			_emit_ring_event(&"weapon_retrieved", side, _opponent_side(side), {"weapon": weapon.display_name, "instance_id": instance.instance_id})
		SetupActionsMenu.PICK_UP_WEAPON:
			var dropped := _environment_state.get_instance(selected_instance_id)
			if dropped == null and side == Side.AI:
				var choices := _dropped_instances_in_area(actor.current_area)
				dropped = choices[0] if not choices.is_empty() else null
			if actor.held_weapon != null or dropped == null or dropped.area != actor.current_area or dropped.lifecycle != MatchWeaponInstance.Lifecycle.DROPPED:
				is_resolving_action = false
				ensure_match_can_continue("invalid dropped weapon pickup")
				return
			_environment_state.hold(dropped, side, actor.current_area)
			_set_held_instance(actor, dropped)
			actor.dropped_weapons_picked_up += 1
			actor.last_weapon_action_time = _match_time_seconds
			add_match_log_entry("%s picks the %s back up." % [_side_name(side), actor.held_weapon.display_name.to_lower()], AppThemePalette.WARNING)
			_emit_ring_event(&"weapon_retrieved", side, _opponent_side(side), {"weapon": actor.held_weapon.display_name, "from_floor": true})
		SetupActionsMenu.DROP_WEAPON:
			if actor.held_weapon == null:
				is_resolving_action = false
				ensure_match_can_continue("invalid weapon drop")
				return
			var dropped_name := actor.held_weapon.display_name
			var held := _held_instance(actor)
			if held != null:
				_environment_state.drop(held, actor.current_area)
			_clear_held_weapon(actor)
			actor.last_weapon_action_time = _match_time_seconds
			add_match_log_entry("%s drops the %s in the current area." % [_side_name(side), dropped_name.to_lower()])
			_emit_ring_event(&"weapon_dropped", side, _opponent_side(side), {"weapon": dropped_name, "area": actor.current_area})
		SetupActionsMenu.CHAIR_SHOT:
			is_resolving_action = false
			ensure_match_can_continue("legacy chair action ignored")
			return
		_:
			if action_id in _environment_action_ids():
				await _execute_environment_action(side, action_id, actor, target)
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
	add_match_log_entry("%s raises the steel chair and commits to the swing!" % _side_name(side), AppThemePalette.DESTRUCTIVE)
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
	actor.spend_stamina(
		weapon.stamina_cost
		* MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.EXPLOSIVE)
	)
	actor.add_fatigue(3.0)
	actor.held_weapon_uses_remaining = maxi(0, actor.held_weapon_uses_remaining - 1)
	if reversed:
		actor.weapon_attacks_reversed += 1
		target.reversals += 1
		_apply_reversal_momentum(actor, target)
		last_action_result = ActionResult.REVERSAL
		add_match_log_entry("%s ducks the chair swing and knocks it from %s's hands!" % [_side_name(defender_side), _side_name(side)])
		_emit_ring_event(&"weapon_reversed", defender_side, side, {"weapon": weapon.display_name})
	else:
		actor.weapon_attacks_landed += 1
		var target_resolution := MoveTargetResolver.resolve(_chair_shot_move, actor.target_focus_body_part, target)
		var target_part := int(target_resolution.get("story_part", int(weapon.target_body_part)))
		var attribute_profile := MatchAttributeModel.get_move_attribute_profile(actor, target, _chair_shot_move)
		var attribute_damage_multiplier := float(attribute_profile.get("damage_multiplier", 1.0))
		var target_hp_before := target.get_part_hp(target_part)
		target.damage_part(target_part, float(weapon.impact) * 1.75 * attribute_damage_multiplier)
		var dealt_damage := maxf(0.0, target_hp_before - target.get_part_hp(target_part))
		actor.damage_dealt += dealt_damage
		target.damage_taken += dealt_damage
		actor.note_attribute_damage_profile(attribute_profile)
		actor.record_target_resolution(target_part, dealt_damage, true, _chair_shot_move)
		target.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, target.current_area, WrestlerResource.MotionState.STATIONARY)
		_apply_successful_move_momentum(actor)
		last_action_result = ActionResult.CLEAN_SUCCESS
		add_match_log_entry(
			"%s drives the chair into %s's %s!" % [_side_name(side), _side_name(defender_side), MoveTargetResolver.part_label(target_part).to_lower()],
			AppThemePalette.DESTRUCTIVE,
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
		add_match_log_entry("The referee immediately calls for the bell — %s used an illegal weapon." % _side_name(side), AppThemePalette.ERROR)
		end_match(defender_side, side, FinishType.DISQUALIFICATION, null, "%s was disqualified for using a steel chair." % _side_name(side), "Steel Chair attack")
		return
	if actor.held_weapon != null and actor.held_weapon_uses_remaining <= 0:
		actor.weapons_broken += 1
		actor.held_weapon = null
		add_match_log_entry("The battered steel chair finally buckles and breaks apart.", AppThemePalette.WARNING)
		_emit_ring_event(&"weapon_broken", side, defender_side, {"weapon": weapon.display_name})
	actor.legal_weapon_attacks += 1
	add_match_log_entry("No disqualifications tonight — the chair shot is legal.", AppThemePalette.WARNING)
	is_resolving_action = false
	_set_controller(_control_for_side(defender_side) if reversed else _control_for_side(side))
	refresh_match_ui()
	ensure_match_can_continue("legal chair attack resolution")


func _execute_weapon_move(side: int, move: MoveResource, target_resolution: Dictionary) -> void:
	var actor := _state_for_side(side)
	var defender_side := _opponent_side(side)
	var target := _state_for_side(defender_side)
	var metadata := _weapon_metadata_for_move(move)
	var weapon := metadata.get("weapon") as WeaponResource
	var attack := metadata.get("attack") as WeaponAttackResource
	if actor == null or target == null or weapon == null or attack == null or not _move_is_valid(side, move):
		is_resolving_action = false
		ensure_match_can_continue("invalid weapon attack")
		return
	is_resolving_action = true
	last_move_used = move
	_clear_selected_move()
	var started_at_zero_stamina := actor.stamina <= 0.0
	var weapon_profile := MatchExhaustionModel.profile(actor, move)
	actor.note_exhaustion_profile(weapon_profile)
	if float(weapon_profile.get("execution_penalty", 0.0)) > 0.0:
		actor.low_stamina_penalties_applied += 1
	if started_at_zero_stamina:
		actor.actions_attempted_at_zero_stamina += 1
	if int(weapon_profile.get("band", 0)) >= MatchExhaustionModel.ExhaustionBand.EXHAUSTED:
		actor.exhausted_demanding_weapon_attempts += 1
	advance_match_clock()
	actor.last_weapon_action_time = _match_time_seconds
	actor.weapon_attacks_attempted += 1
	if weapon.display_name not in actor.weapon_types_used:
		actor.weapon_types_used.append(weapon.display_name)
	add_match_log_entry("%s commits to %s with the %s!" % [_side_name(side), attack.display_name.to_lower(), weapon.display_name.to_lower()], AppThemePalette.DESTRUCTIVE)
	_emit_ring_event(&"weapon_attack", side, defender_side, {"weapon": weapon.display_name, "illegal": _match_rules.weapon_attack_causes_disqualification(weapon)})
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, actor.target_focus_body_part, target)
	var defender_input := await _run_defender_response(side, defender_side, move, target_resolution)
	if match_ended:
		return
	if defender_input == INTERACTION_CANCELLED:
		is_resolving_action = false
		_resume_controller_after_cancel(side)
		ensure_match_can_continue("cancelled weapon response")
		return
	var reversed := defender_input == MatchInteractionModel.InputResult.SUCCESS
	actor.spend_stamina(
		maxf(0.0, weapon.stamina_cost + attack.stamina_modifier)
		* MatchExhaustionModel.stamina_cost_multiplier(
			actor,
			MatchExhaustionModel.move_demand(move),
		)
	)
	actor.add_fatigue(3.0)
	var held := _held_instance(actor)
	if held != null:
		held.durability = maxi(0, held.durability - 1)
		actor.held_weapon_uses_remaining = held.durability
	if reversed:
		actor.weapon_attacks_reversed += 1
		target.reversals += 1
		_apply_reversal_momentum(actor, target)
		last_action_result = ActionResult.REVERSAL
		add_match_log_entry("%s avoids the %s and knocks it from %s's hands!" % [_side_name(defender_side), weapon.display_name.to_lower(), _side_name(side)])
		_emit_ring_event(&"weapon_reversed", defender_side, side, {"weapon": weapon.display_name})
	else:
		actor.weapon_attacks_landed += 1
		var target_part := int(target_resolution.get("story_part", int(weapon.target_body_part)))
		var attribute_profile := MatchAttributeModel.get_move_attribute_profile(actor, target, move)
		var attribute_damage_multiplier := float(attribute_profile.get("damage_multiplier", 1.0))
		var before_hp := target.get_part_hp(target_part)
		target.damage_part(target_part, float(move.move_impact) * 1.75 * attribute_damage_multiplier)
		var dealt_damage := maxf(0.0, before_hp - target.get_part_hp(target_part))
		actor.damage_dealt += dealt_damage
		target.damage_taken += dealt_damage
		actor.note_attribute_damage_profile(attribute_profile)
		actor.record_target_resolution(target_part, dealt_damage, true, move)
		target.set_match_state(attack.resulting_target_position, attack.resulting_target_orientation, target.current_area, WrestlerResource.MotionState.STATIONARY)
		_apply_successful_move_momentum(actor)
		last_action_result = ActionResult.CLEAN_SUCCESS
		add_match_log_entry("%s drives the %s into %s's %s!" % [_side_name(side), weapon.display_name.to_lower(), _side_name(defender_side), MoveTargetResolver.part_label(target_part).to_lower()], AppThemePalette.DESTRUCTIVE)
		_maybe_advance_bleeding(actor, target, weapon, move, target_resolution, true)
	_note_exhaustion_action_result(
		side,
		actor,
		ActionResult.REVERSAL if reversed else ActionResult.CLEAN_SUCCESS,
		started_at_zero_stamina,
	)
	if reversed and held != null and held.durability > 0:
		_environment_state.drop(held, actor.current_area)
		_clear_held_weapon(actor)
		actor.weapons_dropped += 1
		_emit_ring_event(&"weapon_dropped", side, defender_side, {"weapon": weapon.display_name, "area": actor.current_area})
	if not reversed and _match_rules.weapon_attack_causes_disqualification(weapon):
		actor.illegal_weapon_uses += 1
		actor.disqualifications_caused += 1
		is_resolving_action = false
		add_match_log_entry("The referee immediately calls for the bell — %s used an illegal weapon." % _side_name(side), AppThemePalette.ERROR)
		end_match(defender_side, side, FinishType.DISQUALIFICATION, null, "%s was disqualified for landing an illegal %s attack." % [_side_name(side), weapon.display_name], "%s attack" % weapon.display_name)
		return
	if held != null and held.durability <= 0:
		actor.weapons_broken += 1
		_environment_state.consume(held, true)
		_clear_held_weapon(actor)
		add_match_log_entry("The %s breaks after the committed attack." % weapon.display_name.to_lower(), AppThemePalette.WARNING)
		_emit_ring_event(&"weapon_broken", side, defender_side, {"weapon": weapon.display_name})
	if not _match_rules.disqualifications_enabled:
		actor.legal_weapon_attacks += 1
	is_resolving_action = false
	if reversed:
		_set_controller(_control_for_side(defender_side))
	else:
		_resolve_control_after_action(side, defender_side, move, ActionResult.CLEAN_SUCCESS)
	_difficulty_diagnostics.record(
		&"weapon_resolved",
		{
			"match_time": _match_time_seconds,
			"actor": _side_name(side),
			"weapon": weapon.display_name,
			"result": "reversal" if reversed else "clean_success",
			"stamina_after": actor.stamina,
			"fatigue_after": actor.fatigue,
			"durability_after": held.durability if held != null else 0,
		},
	)
	refresh_match_ui()
	ensure_match_can_continue("weapon attack resolution")


func _weapon_by_id(weapon_id: StringName) -> WeaponResource:
	return WEAPON_CATALOGUE.get_weapon(weapon_id) if WEAPON_CATALOGUE != null else null


func _held_instance(state: MatchSideState) -> MatchWeaponInstance:
	if state == null or state.held_weapon_instance_id <= 0:
		return null
	return _environment_state.get_instance(state.held_weapon_instance_id)


func _set_held_instance(state: MatchSideState, instance: MatchWeaponInstance) -> void:
	if state == null or instance == null:
		return
	state.held_weapon = instance.weapon
	state.held_weapon_uses_remaining = instance.durability
	state.held_weapon_instance_id = instance.instance_id


func _clear_held_weapon(state: MatchSideState) -> void:
	if state == null:
		return
	state.held_weapon = null
	state.held_weapon_uses_remaining = 0
	state.held_weapon_instance_id = 0


func _choose_ai_weapon(actor: MatchSideState, target: MatchSideState) -> WeaponResource:
	var choices := _available_retrieval_weapons()
	if choices.is_empty():
		return null
	var best: WeaponResource = choices[0]
	var best_score := -INF
	for weapon in choices:
		var score := weapon.ai_weight * 10.0 + weapon.impact * 2.0 + weapon.bleed_rating * 0.08
		if actor.wrestler != null and WrestlerResource.WrestlerClass.HARDCORE in actor.wrestler.wrestler_class:
			score += 12.0
		if weapon.weapon_kind == WeaponResource.WeaponKind.LADDER and _has_ladder_aerial(Side.AI):
			score += 8.0
		if target.current_position in [WrestlerResource.Position.GROUNDED, WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING]:
			score += 4.0
		if score > best_score:
			best_score = score
			best = weapon
	return best


func _on_weapon_selected(weapon_id: StringName, instance_id: int) -> void:
	if _pending_weapon_action.is_empty():
		return
	var side := int(_pending_weapon_action.get("side", Side.NONE))
	var action := StringName(_pending_weapon_action.get("action", &""))
	_pending_weapon_action.clear()
	is_resolving_action = false
	await _execute_rule_action(side, action, _state_for_side(side), _state_for_side(_opponent_side(side)), weapon_id, instance_id)


func _on_weapon_selection_cancelled() -> void:
	_pending_weapon_action.clear()
	is_resolving_action = false
	refresh_match_ui()
	ensure_match_can_continue("weapon selection cancelled")


func _environment_action_ids() -> Array[StringName]:
	return [
		SetupActionsMenu.SET_TABLE_FLAT,
		SetupActionsMenu.SET_TABLE_CORNER,
		SetupActionsMenu.STACK_TABLE,
		SetupActionsMenu.POSITION_AT_TABLE,
		SetupActionsMenu.LAY_ON_TABLE,
		SetupActionsMenu.POSITION_AT_CORNER_TABLE,
		SetupActionsMenu.MOVE_CLEAR_TABLE,
		SetupActionsMenu.SET_UP_LADDER,
		SetupActionsMenu.CLIMB_LADDER,
		SetupActionsMenu.CLIMB_LADDER_TOP,
		SetupActionsMenu.TIP_LADDER,
		SetupActionsMenu.CLIMB_DOWN_LADDER,
		SetupActionsMenu.SPREAD_THUMBTACKS,
		SetupActionsMenu.POSITION_OVER_THUMBTACKS,
		SetupActionsMenu.MOVE_CLEAR_THUMBTACKS,
	]


func _execute_environment_action(side: int, action_id: StringName, actor: MatchSideState, target: MatchSideState) -> void:
	var defender_side := _opponent_side(side)
	var held := _held_instance(actor)
	if action_id in [SetupActionsMenu.SET_TABLE_FLAT, SetupActionsMenu.SET_TABLE_CORNER, SetupActionsMenu.SET_UP_LADDER, SetupActionsMenu.SPREAD_THUMBTACKS]:
		if held == null or held.weapon == null:
			is_resolving_action = false
			ensure_match_can_continue("missing held environment object")
			return
		held.holder_side = Side.NONE
		held.area = actor.current_area
		match action_id:
			SetupActionsMenu.SET_TABLE_FLAT:
				held.lifecycle = MatchWeaponInstance.Lifecycle.SET_FLAT
				actor.tables_set += 1
			SetupActionsMenu.SET_TABLE_CORNER:
				held.lifecycle = MatchWeaponInstance.Lifecycle.SET_CORNER
				actor.tables_set += 1
			SetupActionsMenu.SET_UP_LADDER:
				held.lifecycle = MatchWeaponInstance.Lifecycle.SET_LADDER
				actor.ladder_setups += 1
				_objective_state.note_ladder_setup(held.area)
			SetupActionsMenu.SPREAD_THUMBTACKS:
				held.lifecycle = MatchWeaponInstance.Lifecycle.SPREAD
				actor.thumbtack_patches_spread += 1
		_clear_held_weapon(actor)
		actor.spend_stamina(
			(4.0 if action_id == SetupActionsMenu.SPREAD_THUMBTACKS else 6.0)
			* MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.STANDARD)
		)
		add_match_log_entry(_environment_setup_log(side, action_id), AppThemePalette.WARNING)
		_emit_ring_event(&"environment_setup", side, defender_side, {"action": String(action_id), "weapon": held.weapon.display_name, "instance_id": held.instance_id})
		_finish_environment_action(side, ActionResult.SETUP_SUCCESS)
		return
	if action_id == SetupActionsMenu.STACK_TABLE:
		var base := _environment_state.find_setup(WeaponResource.WeaponKind.TABLE, actor.current_area, MatchWeaponInstance.Lifecycle.SET_FLAT)
		if held == null or held.weapon == null or held.weapon.weapon_kind != WeaponResource.WeaponKind.TABLE or base == null:
			is_resolving_action = false
			ensure_match_can_continue("invalid table stack")
			return
		held.lifecycle = MatchWeaponInstance.Lifecycle.SET_STACKED
		held.holder_side = Side.NONE
		held.area = actor.current_area
		base.lifecycle = MatchWeaponInstance.Lifecycle.SET_STACKED
		base.stacked_instance_ids = [held.instance_id]
		held.stacked_instance_ids = [base.instance_id]
		_clear_held_weapon(actor)
		actor.tables_stacked += 1
		actor.spend_stamina(7.0 * MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.EXPLOSIVE))
		add_match_log_entry("%s stacks a second table onto the first." % _side_name(side), AppThemePalette.WARNING)
		_finish_environment_action(side, ActionResult.SETUP_SUCCESS)
		return
	if action_id in [SetupActionsMenu.MOVE_CLEAR_TABLE, SetupActionsMenu.MOVE_CLEAR_THUMBTACKS]:
		var kind := WeaponResource.WeaponKind.TABLE if action_id == SetupActionsMenu.MOVE_CLEAR_TABLE else WeaponResource.WeaponKind.THUMBTACKS
		var object := _environment_state.find_setup(kind, actor.current_area)
		if object != null and object.positioned_side == side:
			object.clear_positioning()
			actor.spend_stamina(2.0 * MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.BASIC))
		add_match_log_entry("%s scrambles clear of the danger." % _side_name(side))
		_finish_environment_action(side, ActionResult.SETUP_SUCCESS)
		return
	if action_id == SetupActionsMenu.CLIMB_DOWN_LADDER:
		var ladder := _environment_state.find_setup(WeaponResource.WeaponKind.LADDER, WrestlerResource.Area.IN_RING, MatchWeaponInstance.Lifecycle.SET_LADDER)
		if ladder == null:
			ladder = _environment_state.find_setup(WeaponResource.WeaponKind.LADDER, WrestlerResource.Area.OUTSIDE, MatchWeaponInstance.Lifecycle.SET_LADDER)
		if ladder != null:
			actor.set_match_state(WrestlerResource.Position.STANDING, WrestlerResource.Orientation.FRONT, ladder.area, WrestlerResource.MotionState.STATIONARY)
			ladder.ladder_climber_side = Side.NONE
			ladder.ladder_climb_stage = 0
		add_match_log_entry("%s climbs carefully back down from the ladder." % _side_name(side))
		_finish_environment_action(side, ActionResult.SETUP_SUCCESS)
		return
	var contested_object := _environment_object_for_action(action_id, actor, target)
	if contested_object == null:
		is_resolving_action = false
		ensure_match_can_continue("missing environment setup target")
		return
	var defender_input := await _run_setup_defender_response(side, defender_side, action_id, actor, target)
	if defender_input == INTERACTION_CANCELLED:
		is_resolving_action = false
		_resume_controller_after_cancel(side)
		ensure_match_can_continue("cancelled environment action")
		return
	var reversed := defender_input == MatchInteractionModel.InputResult.SUCCESS
	var environment_demand := (
		MatchExhaustionModel.Demand.EXPLOSIVE
		if action_id in [SetupActionsMenu.CLIMB_LADDER, SetupActionsMenu.CLIMB_LADDER_TOP, SetupActionsMenu.TIP_LADDER]
		else MatchExhaustionModel.Demand.STANDARD
	)
	actor.spend_stamina(3.0 * MatchExhaustionModel.stamina_cost_multiplier(actor, environment_demand))
	actor.add_fatigue(1.0)
	if reversed:
		actor.environmental_reversals += 1
		target.reversals += 1
		_apply_reversal_momentum(actor, target)
		if action_id in [SetupActionsMenu.CLIMB_LADDER, SetupActionsMenu.CLIMB_LADDER_TOP]:
			actor.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, contested_object.area, WrestlerResource.MotionState.STATIONARY)
			contested_object.lifecycle = MatchWeaponInstance.Lifecycle.DROPPED
			contested_object.ladder_climber_side = Side.NONE
			contested_object.ladder_climb_stage = 0
			actor.ladder_climbs_interrupted += 1
		else:
			contested_object.clear_positioning()
		add_match_log_entry("%s interrupts %s before the environmental setup can take hold." % [_side_name(defender_side), _side_name(side)])
		is_resolving_action = false
		_set_controller(_control_for_side(defender_side))
		refresh_match_ui()
		ensure_match_can_continue("environment action reversal")
		return
	match action_id:
		SetupActionsMenu.POSITION_AT_TABLE, SetupActionsMenu.LAY_ON_TABLE, SetupActionsMenu.POSITION_AT_CORNER_TABLE:
			contested_object.positioned_side = defender_side
			contested_object.positioned_by_side = side
			if action_id == SetupActionsMenu.LAY_ON_TABLE:
				target.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, contested_object.area, WrestlerResource.MotionState.STATIONARY)
		SetupActionsMenu.POSITION_OVER_THUMBTACKS:
			contested_object.positioned_side = defender_side
			contested_object.positioned_by_side = side
		SetupActionsMenu.CLIMB_LADDER:
			actor.set_match_state(WrestlerResource.Position.CLIMBING, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.LADDER, WrestlerResource.MotionState.STATIONARY)
			contested_object.ladder_climber_side = side
			contested_object.ladder_climb_stage = 1
			actor.ladder_climb_stages += 1
			_objective_state.note_ladder_stage(side, 1, contested_object.area)
		SetupActionsMenu.CLIMB_LADDER_TOP:
			actor.set_match_state(WrestlerResource.Position.PERCHED, WrestlerResource.Orientation.FRONT, WrestlerResource.Area.LADDER, WrestlerResource.MotionState.STATIONARY)
			contested_object.ladder_climber_side = side
			contested_object.ladder_climb_stage = 2
			actor.ladder_climb_stages += 1
			_objective_state.note_ladder_stage(side, 2, contested_object.area)
		SetupActionsMenu.TIP_LADDER:
			target.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, contested_object.area, WrestlerResource.MotionState.STATIONARY)
			contested_object.lifecycle = MatchWeaponInstance.Lifecycle.DROPPED
			contested_object.ladder_climber_side = Side.NONE
			contested_object.ladder_climb_stage = 0
	add_match_log_entry(_environment_setup_log(side, action_id), AppThemePalette.WARNING)
	_finish_environment_action(side, ActionResult.SETUP_SUCCESS)


func _finish_environment_action(side: int, result: int) -> void:
	last_action_result = result
	_emit_exhaustion_threshold_commentary(side, _state_for_side(side))
	is_resolving_action = false
	_clear_selected_move_if_invalid()
	_set_controller(_control_for_side(side))
	refresh_match_ui()
	ensure_match_can_continue("environment action resolution")


func _environment_object_for_action(action_id: StringName, actor: MatchSideState, target: MatchSideState) -> MatchWeaponInstance:
	if action_id in [SetupActionsMenu.POSITION_AT_TABLE, SetupActionsMenu.LAY_ON_TABLE, SetupActionsMenu.POSITION_AT_CORNER_TABLE]:
		return _active_table(target.current_area)
	if action_id == SetupActionsMenu.POSITION_OVER_THUMBTACKS:
		return _active_tacks(target.current_area)
	if action_id in [SetupActionsMenu.CLIMB_LADDER, SetupActionsMenu.CLIMB_LADDER_TOP]:
		var ladder_area := actor.current_area if actor.current_area != WrestlerResource.Area.LADDER else _ladder_base_area(side_for_state(actor))
		return _environment_state.find_setup(WeaponResource.WeaponKind.LADDER, ladder_area, MatchWeaponInstance.Lifecycle.SET_LADDER)
	if action_id == SetupActionsMenu.TIP_LADDER:
		return _environment_state.find_setup(WeaponResource.WeaponKind.LADDER, _ladder_base_area(side_for_state(target)), MatchWeaponInstance.Lifecycle.SET_LADDER)
	return null


func _active_table(area: int) -> MatchWeaponInstance:
	for instance in _environment_state.instances_in_area(area):
		if instance != null and instance.weapon != null and instance.weapon.weapon_kind == WeaponResource.WeaponKind.TABLE and instance.is_table_setup():
			return instance
	return null


func _active_tacks(area: int) -> MatchWeaponInstance:
	return _environment_state.find_setup(WeaponResource.WeaponKind.THUMBTACKS, area, MatchWeaponInstance.Lifecycle.SPREAD)


func side_for_state(state: MatchSideState) -> int:
	return Side.PLAYER if state == player_side_state else Side.AI if state == ai_side_state else Side.NONE


func _ladder_base_area(side: int) -> int:
	for instance in _environment_state.instances:
		if instance != null and instance.weapon != null and instance.weapon.weapon_kind == WeaponResource.WeaponKind.LADDER and instance.ladder_climber_side == side:
			return instance.area
	return WrestlerResource.Area.IN_RING


func _has_ladder_aerial(side: int) -> bool:
	var state := _state_for_side(side)
	if state == null:
		return false
	for move in state.all_assigned_moves():
		if move != null and move.move_type == MoveResource.MoveType.AERIAL:
			return true
	return false


func _has_qualifying_environment_followup(side: int, object: MatchWeaponInstance, stacked: bool) -> bool:
	var state := _state_for_side(side)
	if state == null:
		return false
	for move in state.all_assigned_moves():
		if move == null or move.is_submission or (not move.is_finisher and move.move_type not in [MoveResource.MoveType.GRAPPLE, MoveResource.MoveType.RUNNING, MoveResource.MoveType.AERIAL, MoveResource.MoveType.SPRINGBOARD]):
			continue
		if move.resulting_target_position == WrestlerResource.Position.GROUNDED and (move.move_impact >= (8 if stacked else 6) or (move.is_finisher and move.move_impact >= 6)):
			return true
	return false


func _environment_setup_log(side: int, action_id: StringName) -> String:
	match action_id:
		SetupActionsMenu.SET_TABLE_FLAT: return "%s unfolds a table and sets it flat." % _side_name(side)
		SetupActionsMenu.SET_TABLE_CORNER: return "%s wedges a table into the corner." % _side_name(side)
		SetupActionsMenu.SET_UP_LADDER: return "%s opens the ladder and sets it in place." % _side_name(side)
		SetupActionsMenu.SPREAD_THUMBTACKS: return "%s scatters thumbtacks across the floor." % _side_name(side)
		SetupActionsMenu.POSITION_AT_TABLE: return "%s lines the opponent up with the table." % _side_name(side)
		SetupActionsMenu.LAY_ON_TABLE: return "%s lays the opponent across the table." % _side_name(side)
		SetupActionsMenu.POSITION_AT_CORNER_TABLE: return "%s traps the opponent against the corner table." % _side_name(side)
		SetupActionsMenu.POSITION_OVER_THUMBTACKS: return "%s manoeuvres the opponent over the thumbtacks." % _side_name(side)
		SetupActionsMenu.CLIMB_LADDER: return "%s starts climbing the ladder." % _side_name(side)
		SetupActionsMenu.CLIMB_LADDER_TOP: return "%s reaches the top of the ladder." % _side_name(side)
		SetupActionsMenu.TIP_LADDER: return "%s tips the ladder and sends the opponent crashing down!" % _side_name(side)
	return "%s adjusts the environmental setup." % _side_name(side)


func _maybe_advance_bleeding(
	attacker: MatchSideState,
	defender: MatchSideState,
	weapon: WeaponResource,
	move: MoveResource,
	target_resolution: Dictionary,
	clean: bool,
) -> void:
	if attacker == null or defender == null or weapon == null or weapon.bleed_rating <= 0.0:
		return
	var part := int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY))
	if not weapon.can_bleed_any_target and part != MoveResource.MoveTargetParts.HEAD:
		return
	var part_damage := 100.0 - defender.get_part_hp(part)
	var chance := weapon.bleed_rating + maxf(0.0, float(move.move_impact - 5)) * 3.0 + part_damage * 0.18
	chance += defender.bleeding_severity * 4.0
	if not clean:
		chance *= 0.65
	if randf() * 100.0 >= clampf(chance, 0.0, 95.0):
		return
	if defender.advance_bleeding():
		attacker.bleeding_inflicted += 1
		add_match_log_entry("%s is now bleeding %s after the %s connects." % [_side_name(side_for_state(defender)), defender.bleeding_label().to_lower(), weapon.display_name.to_lower()], AppThemePalette.ERROR)


func _resolve_environment_after_move(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
	result: int,
	target_resolution: Dictionary,
) -> void:
	if move == null or move.move_type == MoveResource.MoveType.WEAPON:
		return
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if attacker == null or defender == null:
		return
	var object := _positioned_environment_for_side(defender_side)
	var redirected := false
	var victim := defender
	var victim_side := defender_side
	if object != null and result in [ActionResult.REVERSAL, ActionResult.HIGH_RISK_CRASH]:
		redirected = true
		victim = attacker
		victim_side = attacker_side
	if object == null and result in [ActionResult.REVERSAL, ActionResult.HIGH_RISK_CRASH]:
		object = _positioned_environment_for_side(attacker_side)
		redirected = object != null
		victim = attacker
		victim_side = attacker_side
	if object == null or object.weapon == null:
		return
	var stacked := object.lifecycle == MatchWeaponInstance.Lifecycle.SET_STACKED
	if not _qualifies_environment_followup(move, object, stacked):
		return
	var offensive_success := result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS]
	var defensive_redirect := result == ActionResult.REVERSAL
	var crash_into_object := result == ActionResult.HIGH_RISK_CRASH and _is_high_risk(move)
	if not offensive_success and not defensive_redirect and not crash_into_object:
		return
	var bonus := 4.0
	var attribute_profile := MatchAttributeModel.get_move_attribute_profile(
		attacker,
		defender,
		move,
		{"environmental_followup": true},
	)
	var attribute_damage_multiplier := float(attribute_profile.get("damage_multiplier", 1.0))
	if object.weapon.weapon_kind == WeaponResource.WeaponKind.TABLE:
		bonus = 8.0 if stacked else 5.0 if object.lifecycle == MatchWeaponInstance.Lifecycle.SET_CORNER else 4.0
		var final_bonus := bonus * attribute_damage_multiplier
		victim.damage_part(MoveResource.MoveTargetParts.BODY, final_bonus)
		victim.damage_taken += final_bonus
		var credited := defender if redirected else attacker
		credited.damage_dealt += final_bonus
		credited.note_attribute_damage_profile(attribute_profile)
		credited.tables_broken += 1
		credited.table_spots_landed += 1
		victim.table_spots_taken += 1
		victim.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, object.area, WrestlerResource.MotionState.STATIONARY)
		var broken_ids: Array[int] = [object.instance_id]
		for paired_id in object.stacked_instance_ids:
			broken_ids.append(int(paired_id))
		_objective_state.note_table_break(attacker_side, victim_side, broken_ids)
		_consume_table_setup(object)
		add_match_log_entry("%s crashes through %s!" % [_side_name(victim_side), "the stacked tables" if stacked else "the table"], AppThemePalette.DESTRUCTIVE)
		_emit_ring_event(&"table_broken", attacker_side, victim_side, {"instance_id": object.instance_id, "redirected": defensive_redirect or redirected, "stacked": stacked})
		if offensive_success and _match_rules.disqualifications_enabled:
			is_resolving_action = false
			end_match(defender_side, attacker_side, FinishType.DISQUALIFICATION, move, "%s was disqualified for driving the opponent through a table." % _side_name(attacker_side), "Table spot")
	elif object.weapon.weapon_kind == WeaponResource.WeaponKind.THUMBTACKS:
		var part := int(target_resolution.get("story_part", MoveResource.MoveTargetParts.BODY)) if victim == defender else MoveResource.MoveTargetParts.BODY
		var final_bonus := bonus * attribute_damage_multiplier
		victim.damage_part(part, final_bonus)
		victim.damage_taken += final_bonus
		var credited := defender if redirected else attacker
		credited.damage_dealt += final_bonus
		credited.note_attribute_damage_profile(attribute_profile)
		credited.thumbtack_spots_landed += 1
		victim.thumbtack_spots_taken += 1
		victim.set_match_state(WrestlerResource.Position.GROUNDED, WrestlerResource.Orientation.FACE_UP, object.area, WrestlerResource.MotionState.STATIONARY)
		_maybe_advance_bleeding(credited, victim, object.weapon, move, {"story_part": part}, result == ActionResult.CLEAN_SUCCESS)
		_environment_state.consume(object)
		add_match_log_entry("%s is driven into the thumbtacks!" % _side_name(victim_side), AppThemePalette.DESTRUCTIVE)
		_emit_ring_event(&"thumbtacks_used", attacker_side, victim_side, {"instance_id": object.instance_id, "redirected": defensive_redirect or redirected})
		if offensive_success and _match_rules.disqualifications_enabled:
			is_resolving_action = false
			end_match(defender_side, attacker_side, FinishType.DISQUALIFICATION, move, "%s was disqualified for driving the opponent onto thumbtacks." % _side_name(attacker_side), "Thumbtack spot")


func _positioned_environment_for_side(side: int) -> MatchWeaponInstance:
	for instance in _environment_state.instances:
		if instance != null and instance.is_live() and instance.positioned_side == side:
			return instance
	return null


func _is_environmental_followup(attacker_side: int, defender_side: int, move: MoveResource) -> bool:
	if move == null:
		return false
	var object := _positioned_environment_for_side(defender_side)
	if object == null:
		object = _positioned_environment_for_side(attacker_side)
	if object == null:
		return false
	return _qualifies_environment_followup(
		move,
		object,
		object.lifecycle == MatchWeaponInstance.Lifecycle.SET_STACKED,
	)


func _qualifies_environment_followup(move: MoveResource, object: MatchWeaponInstance, stacked: bool) -> bool:
	if move == null or move.is_submission:
		return false
	if not move.is_finisher and move.move_type not in [MoveResource.MoveType.GRAPPLE, MoveResource.MoveType.RUNNING, MoveResource.MoveType.AERIAL, MoveResource.MoveType.SPRINGBOARD]:
		return false
	if move.resulting_target_position != WrestlerResource.Position.GROUNDED:
		return false
	if stacked:
		return move.move_impact >= 8 or (move.is_finisher and move.move_impact >= 6)
	return move.move_impact >= 6


func _consume_table_setup(table: MatchWeaponInstance) -> void:
	var paired_ids := table.stacked_instance_ids.duplicate()
	_environment_state.consume(table, true)
	for paired_id in paired_ids:
		var paired := _environment_state.get_instance(int(paired_id))
		if paired != null:
			_environment_state.consume(paired, true)


func _execute_contested_setup_action(
	side: int,
	action_id: StringName,
	actor: MatchSideState,
	target: MatchSideState,
) -> void:
	if side != Side.AI:
		_player_setup_intent = &""
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
		actor.spend_stamina(3.0 * MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.STANDARD))
		actor.add_fatigue(2.0)
		_apply_setup_interruption_momentum(target)
		actor.contested_setup_losses += 1
		target.contested_setup_defensive_interruptions += 1
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
			actor.spend_stamina(3.0 * MatchExhaustionModel.stamina_cost_multiplier(actor, MatchExhaustionModel.Demand.STANDARD))
			actor.add_fatigue(1.0)
		actor.contested_setup_wins += 1
		actor.clean_successes += 1
		last_action_result = ActionResult.SETUP_SUCCESS
		actor.last_action_result = ActionResult.SETUP_SUCCESS
		add_match_log_entry(
			_taunt_success_log_message(side, actor, target) if is_taunt else _setup_log_message(side, action_id),
			AppThemePalette.SUCCESS if is_taunt else AppThemePalette.ACTIVE,
		)
		if side == Side.AI:
			_ai_decision_engine.note_setup_executed(action_id, actor)
		else:
			_player_setup_intent = &"" if is_taunt else action_id
	actor.sync_to_resource()
	target.sync_to_resource()
	_emit_exhaustion_threshold_commentary(side, actor)
	_emit_exhaustion_threshold_commentary(defender_side, target)
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
	if action_id in [SetupActionsMenu.CLIMB_LADDER, SetupActionsMenu.CLIMB_LADDER_TOP]:
		var reduction := 0.0
		if target.current_position in [WrestlerResource.Position.GROUNDED, WrestlerResource.Position.SEATED, WrestlerResource.Position.KNEELING]:
			reduction += 22.0
		if target.fatigue >= 70.0 or target.stamina_percent() <= 25.0:
			reduction += 12.0
		var ladder_area := _ladder_base_area(_attacker_side)
		if target.current_area != ladder_area:
			reduction += 18.0
		var adjusted := clampf(float(profile.get("ai_success_chance", 25.0)) - reduction, 5.0, 65.0)
		profile["ai_success_chance"] = adjusted
		profile["reversal_chance"] = adjusted
		profile["success_window"] = clampf(adjusted * 0.78 if defender_side == Side.PLAYER else adjusted, 24.0, 65.0)
	target.response_profile_total += float(profile.get("ai_success_chance", 0.0))
	target.response_profile_samples += 1
	var attribute_reversal_profile := MatchAttributeModel.get_reversal_modifier(
		actor,
		target,
		null,
		action_id,
	)
	target.note_attribute_reversal_profile(attribute_reversal_profile)
	var result := MatchInteractionModel.InputResult.FAIL
	if defender_side == Side.PLAYER:
		var request := profile.duplicate(true)
		request["title"] = "REVERSE: %s" % _setup_action_short_name(action_id)
		request["prompt"] = "Stop the moving marker inside the green zone."
		request["button_text"] = "REVERSE"
		var response := await _run_visible_reversal_meter(request)
		if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
			return INTERACTION_CANCELLED
		result = (
			MatchInteractionModel.InputResult.SUCCESS
			if int(response.get("result", MatchInteractionModel.InputResult.FAIL)) == MatchInteractionModel.InputResult.SUCCESS
			else MatchInteractionModel.InputResult.FAIL
		)
	elif _attacker_side == Side.PLAYER:
		# Player-initiated contested setups expose the AI's reversal pressure using
		# the same readable breakthrough meter as ordinary Player offence. Gold
		# completes the setup; a miss is the AI's successful reversal.
		var request := _build_ai_setup_reversal_breakthrough_request(profile, action_id)
		var response := await _run_visible_control_meter(request)
		if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
			return INTERACTION_CANCELLED
		var player_broke_through := (
			int(response.get("result", MatchInteractionModel.InputResult.FAIL))
			== MatchInteractionModel.InputResult.SUCCESS
		)
		result = (
			MatchInteractionModel.InputResult.FAIL
			if player_broke_through
			else MatchInteractionModel.InputResult.SUCCESS
		)
	else:
		result = _simulate_binary_result(float(profile.get("ai_success_chance", 25.0)))
	if result == MatchInteractionModel.InputResult.SUCCESS:
		target.response_successes += 1
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
	var target: MatchSideState = ai_side_state if actor == player_side_state else player_side_state
	var taunt_profile := MatchAttributeModel.get_taunt_profile(actor, target)
	var stamina_reward := 4.0
	match actor.current_area:
		WrestlerResource.Area.APRON:
			stamina_reward = 3.0
		WrestlerResource.Area.TOP_ROPE:
			stamina_reward = 2.0
	stamina_reward *= MatchExhaustionModel.stamina_recovery_multiplier(actor)
	stamina_reward *= float(taunt_profile.get("stamina_multiplier", 1.0))
	var recovered := actor.recover_stamina(stamina_reward)
	var momentum_before := actor.momentum
	actor.add_momentum(maxf(1.0, SUCCESSFUL_MOVE_MOMENTUM + float(taunt_profile.get("momentum_bonus", 0.0))))
	var momentum_gained := actor.momentum - momentum_before
	actor.taunt_stamina_recovered += recovered
	actor.taunt_momentum_gained += momentum_gained
	actor.note_attribute_taunt_profile(taunt_profile)


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
	if actor.stamina_percent() < 30.0 or actor.fatigue >= 70.0:
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
	if embedded_pinning_move and not _pin_area_is_legal(attacker_side, defender_side):
		pin_sequence_active = false
		is_resolving_action = false
		_active_pin_context.clear()
		_set_controller(_control_for_side(attacker_side))
		refresh_match_ui()
		ensure_match_can_continue("rejected outside embedded pin")
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
	add_match_log_entry("%s hooks the leg!" % _side_name(attacker_side), AppThemePalette.ACTIVE)
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
			AppThemePalette.WARNING,
		)
	refresh_match_ui()
	if defender_side == Side.PLAYER:
		var player_result := await _resolve_player_hold_release_pin(attacker_side, defender_side)
		if player_result < 0 or match_ended:
			pin_sequence_active = false
			is_resolving_action = false
			_active_pin_context.clear()
			_emit_ring_event(&"pin_ended", attacker_side, defender_side)
			if not match_ended:
				refresh_match_ui()
				_resume_controller_after_cancel(attacker_side)
				ensure_match_can_continue("cancelled hold-release pin interaction")
			return
		if player_result == MatchInteractionModel.InputResult.SUCCESS:
			_complete_pin_kickout(attacker_side, defender_side, _last_player_pin_count)
			return
		finish_move = _active_pin_context.get("last_move") as MoveResource
		end_match(attacker_side, defender_side, FinishType.PINFALL, finish_move)
		return
	for count in range(1, 4):
		if match_ended:
			_active_pin_context.clear()
			return
		if count < 3:
			add_match_log_entry(_count_word(count) + "!", AppThemePalette.WARNING)
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
			defender.kickouts += 1
			last_action_result = ActionResult.KICKOUT
			if count == 1 and bool(_active_pin_context.get("early_normal_protection", false)):
				add_match_log_entry(
					"%s kicks out at one, nowhere near finished yet." % _side_name(defender_side),
				)
			elif count == 3:
				_record_story_event(&"near_fall_late", defender_side, {"count": count})
				add_match_log_entry(
					"THREE—NO! %s kicks out at the last possible moment!" % _side_name(defender_side),
					AppThemePalette.SUCCESS,
				)
			else:
				if count >= 2:
					_record_story_event(&"near_fall", defender_side, {"count": count})
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


func _resolve_player_hold_release_pin(attacker_side: int, defender_side: int) -> int:
	# Use the existing count-two pressure baseline as the single continuous
	# hold-meter difficulty. All authored time, damage, momentum, finisher, flash,
	# squash, bleeding, and exhaustion factors remain part of this calculation.
	var count := 2
	var values := _pin_pressure_and_resistance(attacker_side, defender_side, count)
	var profile := MatchInteractionModel.build_pin_profile(
		18.0,
		3.0,
		float(values.pressure),
		float(values.resistance),
		count,
		_state_for_side(defender_side),
	)
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	attacker.finish_pressure_total += float(values.pressure) - float(values.resistance)
	attacker.finish_pressure_samples += 1
	defender.kickout_meter_attempts += 1
	_last_player_pin_count = 0
	var request := profile.duplicate(true)
	request["title"] = "KICK OUT BEFORE THREE"
	request["prompt"] = "Hold to fill the bar. Release inside gold to kick out."
	request["button_text"] = "HOLD - RELEASE IN GOLD"
	request["pin_count_mode"] = true
	request["time_limit"] = 3.0
	request["fill_duration"] = 2.7
	request["edge_forgiveness_pixels"] = 2.0
	request["touch_edge_forgiveness_pixels"] = 4.0
	var response := await _run_visible_hold_release(request)
	if bool(response.get("stale", false)) or match_ended or _interaction_context_changed():
		return -1
	_last_player_pin_count = int(response.get("count_reached", _last_player_pin_count))
	var result := int(response.get("result", MatchInteractionModel.InputResult.FAIL))
	if result == MatchInteractionModel.InputResult.SUCCESS:
		defender.kickout_meter_successes += 1
	elif bool(response.get("timed_out", false)):
		defender.kickout_meter_timeouts += 1
	else:
		defender.kickout_meter_near_misses += 1
	_difficulty_diagnostics.record(&"kickout_hold_release", {
		"match_time": _match_time_seconds,
		"defender": _side_name(defender_side),
		"pressure": values.pressure,
		"resistance": values.resistance,
		"visible_width": profile.get("success_window", 0.0),
		"result": "success" if result == MatchInteractionModel.InputResult.SUCCESS else "fail",
		"timed_out": response.get("timed_out", false),
		"release_missed": response.get("release_missed", false),
		"release_value": response.get("release_value", -1.0),
		"count_reached": _last_player_pin_count,
	})
	return result


func _run_visible_hold_release(request: Dictionary) -> Dictionary:
	_begin_visible_interaction()
	var response := await _interaction_overlay.run_hold_release(request)
	_end_visible_interaction()
	return response


func _on_pin_count_reached(_request_id: int, count: int) -> void:
	if not pin_sequence_active or match_ended:
		return
	_last_player_pin_count = count
	if count < 3:
		add_match_log_entry(_count_word(count) + "!", AppThemePalette.WARNING)


func _complete_pin_kickout(attacker_side: int, defender_side: int, count: int) -> void:
	var defender := _state_for_side(defender_side)
	defender.kickouts += 1
	last_action_result = ActionResult.KICKOUT
	if count >= 3:
		_record_story_event(&"near_fall_late", defender_side, {"count": count})
	elif count >= 2:
		_record_story_event(&"near_fall", defender_side, {"count": count})
	if count <= 0:
		add_match_log_entry("%s powers out before one!" % _side_name(defender_side))
	elif count == 1 and bool(_active_pin_context.get("early_normal_protection", false)):
		add_match_log_entry(
			"%s kicks out at one, nowhere near finished yet." % _side_name(defender_side),
		)
	else:
		add_match_log_entry("%s kicks out at %s!" % [_side_name(defender_side), _count_phrase(mini(count, 2))])
	pin_sequence_active = false
	is_resolving_action = false
	_active_pin_context.clear()
	_emit_ring_event(&"pin_ended", attacker_side, defender_side)
	_set_controller(ControlState.NEUTRAL)
	ensure_match_can_continue("hold-release pin kickout")


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
		_state_for_side(defender_side),
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
		_difficulty_diagnostics.record(&"kickout_check", {
			"match_time": _match_time_seconds,
			"defender": _side_name(defender_side),
			"count": count,
			"pressure": values.pressure,
			"resistance": values.resistance,
			"visible_width": profile.get("success_window", 0.0),
			"ai_probability": profile.get("ai_success_chance", 0.0),
			"unshrunk_calculated_window": profile.get("ai_calculated_window", 0.0),
			"result": "success" if simulated_result == MatchInteractionModel.InputResult.SUCCESS else "fail",
		})
		return simulated_result
	var request := profile.duplicate(true)
	request["title"] = "KICK OUT — %s!" % _count_word(count)
	request["prompt"] = "Stop the moving marker inside the green zone."
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
	_difficulty_diagnostics.record(&"kickout_check", {
		"match_time": _match_time_seconds,
		"defender": _side_name(defender_side),
		"count": count,
		"pressure": values.pressure,
		"resistance": values.resistance,
		"visible_width": profile.get("success_window", 0.0),
		"ai_probability": profile.get("ai_success_chance", 0.0),
		"result": "success" if result == MatchInteractionModel.InputResult.SUCCESS else "fail",
		"timed_out": response.get("timed_out", false),
		"marker_value": response.get("marker_value", -1.0),
	})
	return result


func _pin_pressure_and_resistance(attacker_side: int, defender_side: int, count: int) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var last_move := _active_pin_context.get("last_move") as MoveResource
	var impact := float(last_move.move_impact) if last_move != null else 1.0
	var pressure := attacker.momentum + impact * 4.0 + _match_finish_pressure()
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
	var resistance := defender.momentum
	resistance -= defender.bleeding_resistance_penalty()
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
	add_match_log_entry("%s hooks the leg!" % _side_name(attacker_side), AppThemePalette.ACTIVE)
	if bool(_active_pin_context.get("flash_qualified", false)):
		add_match_log_entry(
			"%s catches %s by surprise!" % [_side_name(attacker_side), _side_name(defender_side)],
			AppThemePalette.WARNING,
		)
	refresh_match_ui()
	var temporary_resistance := 0.0
	for count in range(1, 4):
		if match_ended:
			_active_pin_context.clear()
			return
		if count < 3:
			add_match_log_entry(_count_word(count) + "!", AppThemePalette.WARNING)
		var result := await _legacy_resolve_pin_count(attacker_side, defender_side, count, temporary_resistance)
		if result == ContestTimingBar.GREEN_RESULT:
			defender.kickouts += 1
			last_action_result = ActionResult.KICKOUT
			if count == 1 and bool(_active_pin_context.get("early_normal_protection", false)):
				add_match_log_entry(
					"%s kicks out at one, nowhere near finished yet." % _side_name(defender_side),
				)
			elif count == 3:
				add_match_log_entry(
					"THREE—NO! %s kicks out at the last possible moment!" % _side_name(defender_side),
					AppThemePalette.SUCCESS,
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
	if move == null or not _submission_area_is_legal(attacker_side, defender_side):
		submission_sequence_active = false
		is_resolving_action = false
		_active_submission_target_resolution.clear()
		_set_controller(_control_for_side(attacker_side))
		refresh_match_ui()
		ensure_match_can_continue("rejected outside submission")
		return
	submission_sequence_active = true
	is_resolving_action = true
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if target_resolution.is_empty():
		target_resolution = MoveTargetResolver.resolve(move, attacker.target_focus_body_part, defender)
	_active_submission_target_resolution = target_resolution.duplicate(true)
	attacker.begin_submission_tracking(MoveTargetResolver.target_hp(defender, target_resolution))
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
		AppThemePalette.PRESTIGE if move.is_finisher else AppThemePalette.PRIMARY_TEXT,
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
	attacker.note_attribute_submission_attack(float(submission_context.get("attribute_submission_attack", 0.0)))
	defender.note_attribute_submission_defence(float(submission_context.get("attribute_submission_defence", 0.0)))
	_difficulty_diagnostics.record(&"submission_started", {
		"match_time": _match_time_seconds,
		"attacker": _side_name(attacker_side),
		"defender": _side_name(defender_side),
		"move": _move_name(move),
		"target": target_resolution.get("full_tag", "BODY"),
		"start_marker": start_marker,
		"attacker_score": attacker_score,
		"defender_score": defender_score,
		"tap_out_threshold": submission_context.get("tap_out_threshold", 90.0),
		"escape_threshold": submission_context.get("escape_threshold", 10.0),
	})
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
	attacker.last_submission_target_hp_at_resolution = MoveTargetResolver.target_hp(defender, target_resolution)
	var elapsed := float(response.get("elapsed", 0.0))
	attacker.submission_struggle_seconds += elapsed
	defender.submission_struggle_seconds += elapsed
	var outcome := int(response.get("outcome", MatchInteractionModel.CombinedOutcome.BOTCH_OR_SCRAMBLE))
	_difficulty_diagnostics.record(&"submission_resolved", {
		"match_time": _match_time_seconds,
		"attacker": _side_name(attacker_side),
		"defender": _side_name(defender_side),
		"move": _move_name(move),
		"outcome": outcome,
		"elapsed": elapsed,
		"final_marker": response.get("marker", 50.0),
		"timed_out": response.get("timed_out", false),
	})
	match outcome:
		MatchInteractionModel.CombinedOutcome.TAP_OUT:
			attacker.submission_wins += 1
			attacker.submission_struggle_wins += 1
			defender.submission_struggle_losses += 1
			last_action_result = ActionResult.TAP_OUT
			_record_story_event(&"submission_finish", attacker_side, {
				"move": _move_name(move),
				"elapsed": elapsed,
			})
			_emit_ring_event(&"submission_ended", attacker_side, defender_side)
			end_match(attacker_side, defender_side, FinishType.SUBMISSION, move)
			return
		MatchInteractionModel.CombinedOutcome.SUBMISSION_ESCAPE:
			defender.submission_escapes += 1
			defender.submission_struggle_wins += 1
			attacker.submission_struggle_losses += 1
			last_action_result = ActionResult.SUBMISSION_ESCAPE
			_record_story_event(&"submission_escape", defender_side, {
				"move": _move_name(move),
				"elapsed": elapsed,
			})
			add_match_log_entry("%s claws free and breaks the hold." % _side_name(defender_side))
			submission_sequence_active = false
			is_resolving_action = false
			_emit_ring_event(&"submission_ended", attacker_side, defender_side)
			_set_controller(_control_for_side(defender_side))
		MatchInteractionModel.CombinedOutcome.SUBMISSION_CONTINUES:
			attacker.submission_struggle_wins += 1
			defender.submission_struggle_losses += 1
			defender.add_fatigue(3.0)
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
		add_match_log_entry(threshold_message, AppThemePalette.WARNING)
	refresh_match_ui()


func _on_submission_state_changed(_request_id: int, state: StringName) -> void:
	if not submission_sequence_active or _active_submission_move == null:
		return
	if state not in [
		SubmissionTugInteraction.STATE_ATTACKER_GAINING,
		SubmissionTugInteraction.STATE_DEFENDER_GAINING,
		SubmissionTugInteraction.STATE_NEAR_TAP,
		SubmissionTugInteraction.STATE_NEAR_ESCAPE,
	]:
		return
	var attacker := _state_for_side(_active_submission_attacker_side)
	if attacker == null or not attacker.note_submission_commentary_state(state):
		return
	if state == SubmissionTugInteraction.STATE_NEAR_TAP:
		_record_story_event(&"submission_near_tap", _active_submission_attacker_side, {
			"move": _move_name(_active_submission_move),
		})
	elif state == SubmissionTugInteraction.STATE_NEAR_ESCAPE:
		_record_story_event(&"submission_near_escape", _active_submission_defender_side, {
			"move": _move_name(_active_submission_move),
		})
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
		AppThemePalette.PRESTIGE if move.is_finisher else AppThemePalette.PRIMARY_TEXT,
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
			add_match_log_entry("%s wrenches back harder on the hold." % _side_name(attacker_side))
		refresh_match_ui()

	if escape_progress >= 2:
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
	_weapon_radial_menu.close_menu()
	_pending_weapon_action.clear()
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
	add_match_log_entry(result_message, AppThemePalette.PRESTIGE)
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
	var archive_result: Dictionary = MatchReportArchive.save_completed_match(_latest_match_report)
	if bool(archive_result.get("ok", false)):
		_archive_report_saved = true
		_latest_match_report["report_id"] = str(archive_result.get("report_id", _latest_match_report.get("report_id", "")))
	else:
		_archive_save_error = str(archive_result.get("error", "The match could not be added to history."))
		_latest_match_report["archive_save_error"] = _archive_save_error
	_difficulty_diagnostics.close({
		"match_time": _match_time_seconds,
		"winner": _side_name(winning_side) if winning_side != Side.NONE else "None",
		"finish_type": _finish_type_name(result_type),
	})
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
		FinishType.TABLE_BREAK: return "Table Break"
		FinishType.LADDER_RETRIEVAL: return "Ladder Retrieval"
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
		add_match_log_entry(timeout_message, AppThemePalette.ERROR)
	contest_prompt_active = false
	refresh_match_ui()
	return result


func _contest_probabilities(attacker_side: int, defender_side: int, move: MoveResource) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var red := 55.0
	var yellow := 30.0
	var green := 15.0
	if defender.stamina_percent() >= 80.0:
		green += 8.0
		red -= 8.0
	elif defender.stamina_percent() < 25.0:
		green -= 10.0
		red += 10.0
	elif defender.stamina_percent() < 50.0:
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
	var pressure := attacker.momentum + impact * 4.0 + _match_finish_pressure()
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
	var resistance := defender.momentum + temporary_resistance
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
	var probabilities := _pressure_probabilities(pressure, resistance, true)
	var survival_multiplier := 1.0 - MatchExhaustionModel.kickout_penalty(defender) / 100.0
	probabilities["green"] = float(probabilities.get("green", 20.0)) * survival_multiplier
	return _normalize_probabilities(
		float(probabilities.get("red", 55.0)),
		float(probabilities.get("yellow", 25.0)),
		float(probabilities.get("green", 20.0)),
	)


func _submission_probabilities(
	attacker_side: int,
	defender_side: int,
	move: MoveResource,
) -> Dictionary:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	var pressure := attacker.momentum + attacker.wrestler.skill + float(move.move_impact * 5) + _match_finish_pressure()
	if move.is_finisher:
		pressure += 35.0
	var target_hp := defender.lowest_target_hp(move.move_target_parts)
	if target_hp < 25.0:
		pressure += 30.0
	elif target_hp < 50.0:
		pressure += 15.0
	var resistance := defender.momentum + defender.wrestler.skill
	match _submission_early_safety_level(defender, move):
		2:
			resistance += 70.0
		1:
			resistance += 35.0
	var probabilities := _pressure_probabilities(pressure, resistance, false)
	var escape_multiplier := 1.0 - MatchExhaustionModel.submission_escape_penalty(defender) / 100.0
	probabilities["green"] = float(probabilities.get("green", 20.0)) * escape_multiplier
	return _normalize_probabilities(
		float(probabilities.get("red", 55.0)),
		float(probabilities.get("yellow", 25.0)),
		float(probabilities.get("green", 20.0)),
	)


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
		or defender.stamina_percent() <= 30.0
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
		or defender.stamina_percent() <= 25.0
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
	demand_override: int = -1,
) -> void:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	if result in [ActionResult.REVERSAL, ActionResult.HIGH_RISK_CRASH]:
		_set_resolved_controller(_control_for_side(defender_side), attacker_side, defender_side)
		return
	if result == ActionResult.CLEAN_SUCCESS and move.is_finisher:
		_set_resolved_controller(_control_for_side(attacker_side), attacker_side, defender_side)
		return
	if (
		result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS]
		and move != null
		and not move.is_pinning_combination
		and not move.is_flash_pin
	):
		var demand := demand_override
		if demand < 0:
			demand = MatchExhaustionModel.move_demand(
				move,
				attacker.is_signature_move(move),
				_is_ladder_variant(move, attacker),
			)
		var retention_chance := MatchExhaustionModel.control_retention_chance(attacker, demand)
		var retention_roll := randf() * 100.0
		_difficulty_diagnostics.record(
			&"control_retention",
			{
				"match_time": _match_time_seconds,
				"actor": _side_name(attacker_side),
				"move": _move_name(move),
				"demand": MatchExhaustionModel.demand_label(demand),
				"chance": retention_chance,
				"roll": retention_roll,
				"retained": demand == MatchExhaustionModel.Demand.BASIC or retention_roll < retention_chance,
			},
		)
		if demand != MatchExhaustionModel.Demand.BASIC and retention_roll >= retention_chance:
			attacker.exhaustion_control_losses += 1
			if _match_time_seconds - attacker.exhaustion_last_control_loss_log_time >= 60:
				attacker.exhaustion_last_control_loss_log_time = _match_time_seconds
				add_match_log_entry(
					"%s cannot maintain control after the effort." % _side_name(attacker_side),
					AppThemePalette.SECONDARY_TEXT,
				)
			_set_resolved_controller(ControlState.NEUTRAL, attacker_side, defender_side)
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


func _note_exhaustion_action_result(
	side: int,
	state: MatchSideState,
	result: int,
	started_at_zero_stamina: bool,
) -> void:
	if state == null:
		return
	if started_at_zero_stamina and result in [ActionResult.CLEAN_SUCCESS, ActionResult.LABOURED_SUCCESS]:
		state.successful_actions_at_zero_stamina += 1
		if not state.exhaustion_heroic_success_announced:
			state.exhaustion_heroic_success_announced = true
			add_match_log_entry(
				"%s finds one last burst of energy and somehow lands the attack." % _side_name(side),
				AppThemePalette.SUCCESS,
			)
	_emit_exhaustion_threshold_commentary(side, state)


func _emit_exhaustion_threshold_commentary(side: int, state: MatchSideState) -> void:
	if state == null or state.wrestler == null:
		return
	if state.stamina_percent() < 50.0 and not state.exhaustion_low_stamina_announced:
		state.exhaustion_low_stamina_announced = true
		add_match_log_entry("%s is visibly running out of energy." % _side_name(side), AppThemePalette.WARNING)
	if state.fatigue > 75.0 and not state.exhaustion_high_fatigue_announced:
		state.exhaustion_high_fatigue_announced = true
		add_match_log_entry("%s is struggling to recover between exchanges." % _side_name(side), AppThemePalette.WARNING)
	if (
		MatchExhaustionModel.exhaustion_band(state) == MatchExhaustionModel.ExhaustionBand.SPENT
		and not state.exhaustion_spent_announced
	):
		state.exhaustion_spent_announced = true
		add_match_log_entry("%s is completely spent." % _side_name(side), AppThemePalette.ERROR)


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
		_weapon_radial_menu.close_menu()
		_pending_weapon_action.clear()
		_clear_selected_move()
	if current_controller != previous_controller:
		if (
			previous_controller in [ControlState.PLAYER_CONTROL, ControlState.AI_CONTROL]
			and current_controller in [ControlState.PLAYER_CONTROL, ControlState.AI_CONTROL]
		):
			_record_story_event(&"control_swing", current_attacker_side, {
				"from": previous_controller,
				"to": current_controller,
			})
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
	_ai_illegal_weapon_gate_open = _roll_ai_illegal_weapon_gate(ai_side_state, player_side_state)
	var valid_moves := get_valid_moves(Side.AI)
	var setup_actions := get_valid_setup_actions(Side.AI)
	var ready_special := ai_side_state.signature_ready or ai_side_state.finisher_stock > 0
	var forced_recovery := _ai_special_state_recovery(valid_moves, setup_actions)
	var special_continuation := false
	var offensive_setup_continuation := false
	# Path search is only needed when the legacy safety recovery would otherwise
	# undo a useful position. Ordinary AI turns keep the existing cheap path.
	if not forced_recovery.is_empty():
		if ready_special:
			special_continuation = _ai_decision_engine.has_ready_special_continuation(
				ai_side_state,
				player_side_state,
				valid_moves,
				setup_actions,
			)
		if not special_continuation:
			offensive_setup_continuation = _ai_decision_engine.has_reachable_offensive_setup(
				ai_side_state,
				player_side_state,
				setup_actions,
			)
	var urgent_count_out_recovery := _ai_recovery_is_urgent_count_out(forced_recovery)
	if (
		not forced_recovery.is_empty()
		and (
			urgent_count_out_recovery
			or (not special_continuation and not offensive_setup_continuation)
		)
	):
		_ai_decision_engine.note_mandatory_recovery(ai_side_state)
		execute_setup_action(Side.AI, forced_recovery)
		return
	var catch_available := SetupActionsMenu.CATCH_BREATH in setup_actions
	var critical_catch := catch_available and ai_side_state.stamina_percent() < 20.0
	var credible_finish := _ai_decision_engine.has_credible_finish(
		ai_side_state,
		player_side_state,
		valid_moves,
		_can_pin(Side.AI),
		_match_time_seconds,
	)
	if critical_catch and not credible_finish:
		_difficulty_diagnostics.record(
			&"ai_urgent_recovery",
			{
				"match_time": _match_time_seconds,
				"stamina_percent": ai_side_state.stamina_percent(),
				"fatigue": ai_side_state.fatigue,
				"selected": String(SetupActionsMenu.CATCH_BREATH),
			},
		)
		execute_setup_action(Side.AI, SetupActionsMenu.CATCH_BREATH)
		return
	var protect_recovery_choice := catch_available and ai_side_state.stamina_percent() < 40.0
	if (
		not ready_special
		and not protect_recovery_choice
		and (not _match_rules.disqualifications_enabled or _ai_illegal_weapon_gate_open)
	):
		var weapon_action_ready := _match_time_seconds - ai_side_state.last_weapon_action_time >= 90
		var weapon_moves := _available_weapon_moves(Side.AI)
		if weapon_action_ready and not weapon_moves.is_empty() and randf() < 0.34:
			execute_move(Side.AI, weapon_moves[randi() % weapon_moves.size()])
			return
		if weapon_action_ready and SetupActionsMenu.PICK_UP_WEAPON in setup_actions and randf() < 0.20:
			execute_setup_action(Side.AI, SetupActionsMenu.PICK_UP_WEAPON)
			return
		if weapon_action_ready and SetupActionsMenu.RETRIEVE_WEAPON in setup_actions and randf() < 0.16:
			execute_setup_action(Side.AI, SetupActionsMenu.RETRIEVE_WEAPON)
			return
		for environment_action in [SetupActionsMenu.SET_TABLE_FLAT, SetupActionsMenu.SET_TABLE_CORNER, SetupActionsMenu.SET_UP_LADDER, SetupActionsMenu.SPREAD_THUMBTACKS, SetupActionsMenu.POSITION_AT_TABLE, SetupActionsMenu.LAY_ON_TABLE, SetupActionsMenu.POSITION_AT_CORNER_TABLE, SetupActionsMenu.POSITION_OVER_THUMBTACKS, SetupActionsMenu.CLIMB_LADDER, SetupActionsMenu.CLIMB_LADDER_TOP]:
			if environment_action in setup_actions and randf() < 0.18:
				execute_setup_action(Side.AI, environment_action)
				return
	var decision := _ai_decision_engine.choose_action(
		ai_side_state,
		player_side_state,
		valid_moves,
		setup_actions,
		_match_time_seconds,
	)
	_difficulty_diagnostics.record(
		&"ai_decision",
		{
			"match_time": _match_time_seconds,
			"stamina": ai_side_state.stamina,
			"max_stamina": ai_side_state.max_stamina,
			"fatigue": ai_side_state.fatigue,
			"diagnostics": _ai_decision_engine.last_decision_diagnostics,
		},
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


func _ai_recovery_is_urgent_count_out(action_id: StringName) -> bool:
	if (
		action_id.is_empty()
		or not _match_rules.count_outs_enabled
		or not _referee_count_active
	):
		return false
	var remaining := _match_rules.count_out_limit - _referee_count_value
	if (
		action_id == SetupActionsMenu.RETURN_TO_RING
		and _side_is_outside(Side.AI)
		and remaining <= 3
	):
		return true
	return (
		action_id == SetupActionsMenu.WAIT_FOR_COUNT
		and not _side_is_outside(Side.AI)
		and _side_is_outside(Side.PLAYER)
		and remaining <= maxi(3, _match_rules.count_out_limit / 2)
	)


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
	if ai_side_state.current_motion_state == WrestlerResource.MotionState.RISING and SetupActionsMenu.REGAIN_COMPOSURE in setup_actions:
		return SetupActionsMenu.REGAIN_COMPOSURE
	if player_side_state.current_motion_state == WrestlerResource.MotionState.RISING and SetupActionsMenu.PRESS_ADVANTAGE in setup_actions:
		return SetupActionsMenu.PRESS_ADVANTAGE
	if player_side_state.current_motion_state in [WrestlerResource.MotionState.RUNNING, WrestlerResource.MotionState.ROPE_REBOUND] and SetupActionsMenu.CATCH_OPPONENT_RUNNING in setup_actions:
		return SetupActionsMenu.CATCH_OPPONENT_RUNNING
	if player_side_state.current_area == WrestlerResource.Area.CORNER and SetupActionsMenu.PULL_OPPONENT_FROM_CORNER in setup_actions:
		return SetupActionsMenu.PULL_OPPONENT_FROM_CORNER
	if player_side_state.current_area == WrestlerResource.Area.ROPES and SetupActionsMenu.PULL_OPPONENT_FROM_ROPES in setup_actions:
		return SetupActionsMenu.PULL_OPPONENT_FROM_ROPES
	if player_side_state.current_area in [WrestlerResource.Area.APRON, WrestlerResource.Area.TOP_ROPE] and SetupActionsMenu.BRING_OPPONENT_INTO_RING in setup_actions:
		return SetupActionsMenu.BRING_OPPONENT_INTO_RING
	if ai_side_state.current_area == WrestlerResource.Area.TOP_ROPE and SetupActionsMenu.CLIMB_DOWN in setup_actions:
		return SetupActionsMenu.CLIMB_DOWN
	if ai_side_state.current_area == WrestlerResource.Area.LADDER and SetupActionsMenu.CLIMB_DOWN_LADDER in setup_actions:
		return SetupActionsMenu.CLIMB_DOWN_LADDER
	if player_side_state.current_area == WrestlerResource.Area.LADDER and SetupActionsMenu.TIP_LADDER in setup_actions:
		return SetupActionsMenu.TIP_LADDER
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
	if recovery_state.recovery_delay_protected:
		recovery_state.recovery_delay_protected = false
	else:
		var delay_chance := MatchExhaustionModel.recovery_delay_chance(
			recovery_state,
			recovery_state.last_action_result == ActionResult.HIGH_RISK_CRASH,
		)
		if randf() * 100.0 < delay_chance:
			recovery_state.recovery_delay_protected = true
			recovery_state.exhaustion_delayed_recoveries += 1
			add_match_log_entry(
				"%s struggles to recover, and neither wrestler can claim control yet." % _side_name(recovery_side),
				AppThemePalette.WARNING,
			)
			is_resolving_action = false
			_set_controller(ControlState.NEUTRAL)
			ensure_match_can_continue("delayed neutral recovery")
			return
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
	# Runtime stamina is a scaled pool, while momentum and fatigue remain
	# percentages. Compare like-for-like values so a larger stamina capacity does
	# not dominate neutral-control recovery merely because its raw number is high.
	var score := state.stamina_percent() + state.momentum - state.fatigue
	var profile := MatchInteractionModel.build_late_match_profile(_match_time_seconds)
	var exhaustion_factor := MatchExhaustionModel.combined_exhaustion(state)
	score -= float(profile.recovery_penalty) * exhaustion_factor
	score -= exhaustion_factor * 25.0
	score += (MatchExhaustionModel.stamina_recovery_multiplier(state) - 1.0) * 12.0
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
	if (
		(move.is_submission or move.move_type == MoveResource.MoveType.SUBMISSION)
		and not _submission_area_is_legal(side, _opponent_side(side))
	):
		return false
	var weapon_metadata := _weapon_metadata_for_move(move)
	if not weapon_metadata.is_empty():
		if not _match_rules.weapons_enabled or not _weapon_attack_is_mechanically_valid(attacker, defender):
			return false
		if actor_weapon_id(attacker) != move.required_weapon_id:
			return false
	elif move not in attacker.all_assigned_moves():
		return false
	if weapon_metadata.is_empty() and not attacker.can_use_move(move):
		return false
	if not _position_matches(move.required_attacker_position, attacker.current_position):
		return false
	if not _move_target_position_matches(move, defender.current_position):
		return false
	if not _orientation_matches(move.required_attacker_orientation, attacker.current_orientation):
		return false
	if not _orientation_matches(move.required_target_orientation, defender.current_orientation):
		return false
	var ladder_variant := _is_ladder_variant(move, attacker)
	if not ladder_variant and not MatchAreaRules.move_areas_match(move, attacker.current_area, defender.current_area):
		return false
	if ladder_variant and not MatchAreaRules.move_areas_match(move, WrestlerResource.Area.TOP_ROPE, defender.current_area):
		return false
	if (
		not MatchSetupStateRules.motion_matches(move.required_attacker_motion_state, attacker.current_motion_state)
		or not MatchSetupStateRules.motion_matches(move.required_target_motion_state, defender.current_motion_state)
	):
		return false
	return true


func _is_ladder_variant(move: MoveResource, attacker: MatchSideState) -> bool:
	return (
		move != null
		and attacker != null
		and attacker.current_area == WrestlerResource.Area.LADDER
		and attacker.current_position == WrestlerResource.Position.PERCHED
		and move.move_type == MoveResource.MoveType.AERIAL
		and move.required_attacker_position == WrestlerResource.Position.PERCHED
		and move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC
		and move.required_attacker_area == WrestlerResource.Area.TOP_ROPE
	)


func actor_weapon_id(state: MatchSideState) -> StringName:
	return state.held_weapon.weapon_id if state != null and state.held_weapon != null else &""


func _move_target_position_matches(move: MoveResource, actual: int) -> bool:
	if _position_matches(move.required_target_position, actual):
		return true
	return actual in move.additional_valid_target_positions


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
		and _move_target_position_matches(move, int(defender.get("position", WrestlerResource.Position.NONE)))
		and _orientation_matches(move.required_attacker_orientation, int(attacker.get("orientation", WrestlerResource.Orientation.NONE)))
		and _orientation_matches(move.required_target_orientation, int(defender.get("orientation", WrestlerResource.Orientation.NONE)))
		and MatchAreaRules.move_areas_match(
			move,
			int(attacker.get("area", WrestlerResource.Area.IN_RING)),
			int(defender.get("area", WrestlerResource.Area.IN_RING)),
		)
		and MatchSetupStateRules.motion_matches(move.required_attacker_motion_state, int(attacker.get("motion_state", WrestlerResource.MotionState.STATIONARY)))
		and MatchSetupStateRules.motion_matches(move.required_target_motion_state, int(defender.get("motion_state", WrestlerResource.MotionState.STATIONARY)))
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


func _pin_area_is_legal(attacker_side: int, defender_side: int) -> bool:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	return (
		attacker != null
		and defender != null
		and attacker.current_area == WrestlerResource.Area.IN_RING
		and defender.current_area == WrestlerResource.Area.IN_RING
	)


func _submission_area_is_legal(attacker_side: int, defender_side: int) -> bool:
	var attacker := _state_for_side(attacker_side)
	var defender := _state_for_side(defender_side)
	return (
		attacker != null
		and defender != null
		and attacker.current_area not in [
			WrestlerResource.Area.APRON,
			WrestlerResource.Area.OUTSIDE,
			WrestlerResource.Area.RAMP,
			WrestlerResource.Area.LADDER,
		]
		and defender.current_area not in [
			WrestlerResource.Area.APRON,
			WrestlerResource.Area.OUTSIDE,
			WrestlerResource.Area.RAMP,
			WrestlerResource.Area.LADDER,
		]
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
	var prestige_ready := special_label.contains("FINISHER") or special_label.contains("SIGNATURE")
	_move_selector_button.add_theme_color_override(
		"font_color",
		AppThemePalette.PRESTIGE if prestige_ready else AppThemePalette.ACTIVE,
	)
	var special_style := _move_button_prestige_style if prestige_ready else _move_button_available_style
	if special_style != null:
		_move_selector_button.add_theme_stylebox_override("normal", special_style)


func _update_match_header() -> void:
	if not is_node_ready():
		return
	_vs_banner.text = _match_presentation_label()
	_vs_banner.add_theme_color_override(
		"font_color",
		AppThemePalette.PRESTIGE
		if not str(_match_setup_metadata.get("championship", "")).strip_edges().is_empty()
		else AppThemePalette.PRIMARY_TEXT,
	)
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
	return _available_weapon_moves(Side.PLAYER)


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
		SetupActionsMenu.PULL_OPPONENT_FROM_CORNER:
			return "%s pulls %s out of the corner and back into the ring." % [actor, target]
		SetupActionsMenu.PULL_OPPONENT_FROM_ROPES:
			return "%s drags %s away from the ropes and back into open space." % [actor, target]
		SetupActionsMenu.BRING_OPPONENT_INTO_RING:
			return "%s brings %s down and back into the ring." % [actor, target]
		SetupActionsMenu.CATCH_OPPONENT_RUNNING:
			return "%s cuts off %s's run and stops them in their tracks." % [actor, target]
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
			or state.current_position > WrestlerResource.Position.CLIMBING
			or state.current_orientation < WrestlerResource.Orientation.FRONT
			or state.current_orientation > WrestlerResource.Orientation.FACE_DOWN
			or state.current_area < WrestlerResource.Area.IN_RING
			or state.current_area > WrestlerResource.Area.LADDER
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
	full_report_requested.emit(_latest_match_report.duplicate(true))


func _on_result_view_report_requested() -> void:
	_open_latest_match_report()


func _on_result_popup_closed() -> void:
	if _view_report_button.visible:
		_view_report_button.grab_focus()


func _on_new_match_requested() -> void:
	if not match_ended:
		return
	request_new_match()


func restore_finished_match_screen() -> void:
	visible = true
	if _view_report_button.visible:
		_view_report_button.grab_focus()


func configure_match(
	player: WrestlerResource,
	opponent: WrestlerResource,
	setup_metadata: Dictionary,
) -> bool:
	if player == null or opponent == null:
		return false
	if not _roster_contains_resource(player) or not _roster_contains_resource(opponent):
		return false
	if _same_wrestler(player, opponent):
		return false
	player_wrestler = player
	ai_wrestler = opponent
	_match_setup_metadata = setup_metadata.duplicate(true)
	_match_setup_metadata["match_setup"] = str(_match_setup_metadata.get("match_setup", "Manual"))
	_match_setup_metadata["player_locked"] = bool(_match_setup_metadata.get("player_locked", false))
	_match_setup_metadata["ai_locked"] = bool(_match_setup_metadata.get("ai_locked", false))
	_match_setup_metadata["player_randomly_selected"] = bool(_match_setup_metadata.get("player_randomly_selected", false))
	_match_setup_metadata["ai_randomly_selected"] = bool(_match_setup_metadata.get("ai_randomly_selected", false))
	if not _match_setup_metadata.has("match_rules") or not (_match_setup_metadata["match_rules"] is Dictionary):
		_match_setup_metadata["match_rules"] = {}
	_match_rules = MatchRules.from_dictionary((_match_setup_metadata["match_rules"] as Dictionary)).runtime_copy()
	_record_recent_matchup(player, opponent)
	_sync_selector_to_resource(_player_selector, player_wrestler)
	_sync_selector_to_resource(_ai_selector, ai_wrestler)
	_update_disabled_options()
	_selection_status.text = ""
	start_match()
	return true


func request_new_match() -> void:
	prepare_for_scene_exit()
	new_match_requested.emit()


func request_pause() -> void:
	_open_pause_menu()


func prepare_for_scene_exit() -> void:
	_turn_generation += 1
	_scheduled_ai_generation = -1
	_scheduled_neutral_generation = -1
	is_resolving_action = false
	contest_prompt_active = false
	pin_sequence_active = false
	submission_sequence_active = false
	_match_result_popup.close_result()
	_interaction_overlay.close_interaction(true)
	_moves_radial_menu.close()
	_setup_actions_menu.close()
	_weapon_radial_menu.close_menu()
	_pending_weapon_action.clear()
	if is_instance_valid(_pause_menu):
		_pause_menu.force_close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _pause_menu.is_open():
		_open_pause_menu()
		get_viewport().set_input_as_handled()


func _open_pause_menu() -> void:
	if not is_instance_valid(_pause_menu):
		return
	_pause_menu.open_menu()


func _on_pause_return_to_exhibition() -> void:
	prepare_for_scene_exit()
	return_to_exhibition_requested.emit()


func _on_pause_return_to_main_menu() -> void:
	prepare_for_scene_exit()
	return_to_main_menu_requested.emit()


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
	var player_report := _side_report_stats(player_side_state, ai_side_state, "PLAYER")
	var ai_report := _side_report_stats(ai_side_state, player_side_state, "AI")
	var result_name := _finish_type_name(finish_type)
	var finish_name := "None"
	if finish_move != null:
		finish_name = _move_name(finish_move)
	elif not finish_action.is_empty():
		finish_name = finish_action
	var completed_at_utc := Time.get_datetime_string_from_system(true, true)
	var local_datetime := Time.get_datetime_dict_from_system()
	var date_display := "%04d-%02d-%02d %02d:%02d" % [
		int(local_datetime.get("year", 0)),
		int(local_datetime.get("month", 0)),
		int(local_datetime.get("day", 0)),
		int(local_datetime.get("hour", 0)),
		int(local_datetime.get("minute", 0)),
	]
	var player_participant := _report_participant(Side.PLAYER)
	var ai_participant := _report_participant(Side.AI)
	var winner_id := _participant_id_for_side(winner_side)
	var loser_id := _participant_id_for_side(loser_side)
	var stipulation_id := _stipulation_id(_match_rules.stipulation)
	var stipulation_name := _stipulation_name(_match_rules.stipulation)
	_record_story_event(&"match_finish", winner_side, {
		"result": result_name,
		"move": finish_name,
	})
	var report := {
		"title": "MATCH REPORT",
		"subtitle": "%s vs. %s" % [_side_name(Side.PLAYER), _side_name(Side.AI)],
		"schema_version": 1,
		"completed_at_utc": completed_at_utc,
		"date_display": date_display,
		"participants": [player_participant, ai_participant],
		"winner": _side_name(winner_side) if winner_side != Side.NONE else "No Winner",
		"loser": _side_name(loser_side) if loser_side != Side.NONE else "None",
		"winner_id": winner_id,
		"loser_id": loser_id,
		"result": result_name,
		"finish_reason": finish_reason,
		"duration_seconds": final_time,
		"final_time": _format_match_time(final_time),
		"finish_move": finish_name,
		"match_type_id": "singles",
		"match_type": "Singles",
		"stipulation_id": stipulation_id,
		"stipulation": stipulation_name,
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
		"environment_objects": _environment_state.snapshots(),
		"player": player_report,
		"ai": ai_report,
		"story_events": _match_story_events.duplicate(true),
		"log_lines": match_log_entries.duplicate(),
		"file_stem": "%s_vs_%s" % [_side_name(Side.PLAYER), _side_name(Side.AI)],
	}
	var rating: Dictionary = MatchRatingCalculator.calculate(report, _match_story_events)
	report["rating"] = rating
	report["rating_highlights"] = rating.get("highlights", [])
	report["diagnostics"] = {
		"player": player_report.duplicate(true),
		"ai": ai_report.duplicate(true),
		"rating_components": (rating.get("components", {}) as Dictionary).duplicate(true),
		"environment_objects": _environment_state.snapshots(),
		"count_started": _referee_count_starts,
		"highest_count": _referee_count_highest,
		"count_resets": _referee_count_resets,
		"final_count": _referee_count_value,
	}
	report["export_text"] = _build_match_report_text(report)
	return report


func _record_story_event(event_type: StringName, side: int, details: Dictionary = {}) -> void:
	if not _match_initialized and event_type != &"match_finish":
		return
	var event := {
		"type": str(event_type),
		"time_seconds": _match_time_seconds,
		"time": _format_match_time(_match_time_seconds),
		"side": side,
		"wrestler": _side_name(side) if side in [Side.PLAYER, Side.AI] else "",
	}
	for key in details:
		event[key] = details[key]
	_match_story_events.append(event)


func _report_participant(side: int) -> Dictionary:
	var state: MatchSideState = _state_for_side(side)
	var wrestler: WrestlerResource = state.wrestler if state != null else null
	if wrestler == null:
		return {"id": "", "resource_path": "", "wrestler_id": 0, "name": "Unknown"}
	return {
		"id": _participant_id_for_side(side),
		"resource_path": wrestler.resource_path,
		"wrestler_id": wrestler.wrestler_id,
		"name": _wrestler_name(wrestler),
	}


func _participant_id_for_side(side: int) -> String:
	if side not in [Side.PLAYER, Side.AI]:
		return ""
	var state := _state_for_side(side)
	if state == null or state.wrestler == null:
		return ""
	if not state.wrestler.resource_path.is_empty():
		return state.wrestler.resource_path
	return "wrestler:%d:%s" % [state.wrestler.wrestler_id, _wrestler_name(state.wrestler).to_lower()]


func _stipulation_id(value: int) -> String:
	match value:
		MatchRules.Stipulation.NO_DISQUALIFICATION: return "no_disqualification"
		MatchRules.Stipulation.TABLES: return "tables"
		MatchRules.Stipulation.LADDER: return "ladder"
	return "standard"


func _stipulation_name(value: int) -> String:
	match value:
		MatchRules.Stipulation.NO_DISQUALIFICATION: return "No Disqualification"
		MatchRules.Stipulation.TABLES: return "Tables"
		MatchRules.Stipulation.LADDER: return "Ladder"
	return "Standard"


func _side_report_stats(state: MatchSideState, opponent: MatchSideState, role: String) -> Dictionary:
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
		"tactical_setup_actions": state.tactical_setup_actions,
		"recovery_setup_actions": state.recovery_setup_actions,
		"pin_attempts": state.pin_attempts,
		"kickouts": state.kickouts,
		"submission_attempts": state.submission_attempts,
		"submission_escapes": state.submission_escapes,
		"damage_dealt": state.damage_dealt,
		"damage_taken": state.damage_taken,
		"stamina": state.stamina,
		"max_stamina": state.max_stamina,
		"stamina_percent": state.stamina_percent(),
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
		"execution_mode": "automatic_reversal_only",
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
		"contested_setup_defensive_interruptions": state.contested_setup_defensive_interruptions,
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
		"mandatory_recoveries": state.mandatory_recovery_actions,
		"average_late_escalation": state.average_late_escalation(),
		"final_exhaustion_band": MatchExhaustionModel.exhaustion_band_label(state),
		"zero_stamina_attempts": state.actions_attempted_at_zero_stamina,
		"zero_stamina_successes": state.successful_actions_at_zero_stamina,
		"exhausted_high_risk_attempts": state.exhausted_high_risk_attempts,
		"exhausted_demanding_weapon_attempts": state.exhausted_demanding_weapon_attempts,
		"exhaustion_control_losses": state.exhaustion_control_losses,
		"delayed_recoveries": state.exhaustion_delayed_recoveries,
		"catch_breath_uses": state.catch_breath_uses,
		"total_stamina_recovered": state.total_stamina_recovered,
		"average_stamina_execution_penalty": state.average_stamina_execution_penalty(),
		"average_fatigue_amplification": state.average_fatigue_amplification(),
		"average_attribute_damage_multiplier": state.average_attribute_damage_multiplier(),
		"average_attribute_reversal_modifier": state.average_attribute_reversal_modifier(),
		"average_attribute_reversal_difficulty": state.average_attribute_reversal_difficulty(),
		"average_attribute_setup_modifier": state.average_attribute_setup_modifier(),
		"average_attribute_submission_attack": state.average_attribute_submission_attack(),
		"average_attribute_submission_defence": state.average_attribute_submission_defence(),
		"average_attribute_taunt_momentum_bonus": state.average_attribute_taunt_momentum_bonus(),
		"average_attribute_movement_recovery": state.average_attribute_movement_recovery(),
		"last_attribute_profile": MatchAttributeModel.get_debug_summary(state.last_attribute_profile),
		"minimum_stamina": state.minimum_stamina_reached,
		"minimum_stamina_percent": (
			state.minimum_stamina_reached / state.max_stamina * 100.0
			if state.max_stamina > 0.0
			else 0.0
		),
		"maximum_fatigue": state.maximum_fatigue_reached,
		"final_target_focus": MoveTargetResolver.part_label(state.target_focus_body_part),
		"target_focus_reason": state.target_focus_reason,
		"most_used_focus": _report_part_label(state.most_used_focus_part()),
		"most_targeted_part": _report_part_label(state.most_targeted_part()),
		"most_damaged_part": MoveTargetResolver.part_label(opponent.most_damaged_part()) if opponent != null else "None",
		"target_most_damaged_part": MoveTargetResolver.part_label(opponent.most_damaged_part()) if opponent != null else "None",
		"own_most_damaged_part": MoveTargetResolver.part_label(state.most_damaged_part()),
		"per_part_attacks": _format_part_number_dictionary(state.target_attack_counts, false),
		"per_part_damage": _format_part_number_dictionary(state.target_damage_dealt, true),
		"thresholds_crossed": _format_threshold_dictionary(state.body_part_thresholds_crossed),
		"parts_reaching_zero": _format_part_list(state.get_body_damage_summary().get("parts_reaching_zero", [])),
		"last_submission_target": _report_part_label(state.last_submission_target),
		"last_submission_target_hp_at_lock_in": state.last_submission_target_hp_at_lock_in,
		"last_submission_target_hp_at_resolution": state.last_submission_target_hp_at_resolution,
		"last_finisher_target": _report_part_label(state.last_finisher_target),
		"targeting_milestones": _format_threshold_dictionary(state.repeated_target_milestones),
		"outside_seconds": state.outside_seconds,
		"late_count_returns": state.late_count_returns,
		"weapons_retrieved": state.weapons_retrieved,
		"dropped_weapons_picked_up": state.dropped_weapons_picked_up,
		"weapon_types_used": ", ".join(state.weapon_types_used) if not state.weapon_types_used.is_empty() else "None",
		"weapons_broken": state.weapons_broken,
		"weapons_dropped": state.weapons_dropped,
		"weapon_attacks_attempted": state.weapon_attacks_attempted,
		"weapon_attacks_landed": state.weapon_attacks_landed,
		"weapon_attacks_reversed": state.weapon_attacks_reversed,
		"illegal_weapon_uses": state.illegal_weapon_uses,
		"legal_weapon_attacks": state.legal_weapon_attacks,
		"disqualifications_caused": state.disqualifications_caused,
		"bleeding_caused": state.bleeding_inflicted,
		"final_bleeding": state.bleeding_label(),
		"tables_set": state.tables_set,
		"tables_stacked": state.tables_stacked,
		"tables_broken": state.tables_broken,
		"table_spots_landed": state.table_spots_landed,
		"table_spots_taken": state.table_spots_taken,
		"ladder_setups": state.ladder_setups,
		"ladder_climb_stages": state.ladder_climb_stages,
		"ladder_climbs_interrupted": state.ladder_climbs_interrupted,
		"ladder_dives": state.ladder_dives,
		"ladder_crashes": state.ladder_crashes,
		"thumbtack_patches_spread": state.thumbtack_patches_spread,
		"thumbtack_spots_landed": state.thumbtack_spots_landed,
		"thumbtack_spots_taken": state.thumbtack_spots_taken,
		"environmental_reversals": state.environmental_reversals,
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


func _format_environment_report(objects: Array) -> String:
	var entries: Array[String] = []
	for raw in objects:
		if not raw is Dictionary:
			continue
		var data := raw as Dictionary
		entries.append("%s #%d (%s, durability %d)" % [
			str(data.get("weapon_name", "Object")),
			int(data.get("instance_id", 0)),
			MatchAreaRules.area_name(int(data.get("area", WrestlerResource.Area.OUTSIDE))),
			int(data.get("durability", 0)),
		])
	return "; ".join(entries) if not entries.is_empty() else "None"


func _build_match_report_text(report: Dictionary) -> String:
	var rating: Dictionary = report.get("rating", {})
	var participants: Array = report.get("participants", [])
	var player_name := "Player"
	var opponent_name := "Opponent"
	if participants.size() > 0 and participants[0] is Dictionary:
		player_name = str((participants[0] as Dictionary).get("name", player_name))
	if participants.size() > 1 and participants[1] is Dictionary:
		opponent_name = str((participants[1] as Dictionary).get("name", opponent_name))
	var lines: Array[String] = [
		"RISE TO RELEVANCE",
		"MATCH REPORT",
		"================================",
		"",
		MatchRatingCalculator.format_stars(float(rating.get("stars", 0.0))),
		"",
		"%s vs. %s" % [player_name, opponent_name],
		"Winner: %s" % str(report.get("winner", "No Winner")),
		"Loser: %s" % str(report.get("loser", "None")),
		"Duration: %s" % str(report.get("final_time", "00:00")),
		"Match: %s — %s" % [str(report.get("match_type", "Singles")), str(report.get("stipulation", "Standard"))],
		"Result: %s" % str(report.get("result", "Not Set")),
		"Finish: %s" % str(report.get("finish_move", "None")),
		"",
		"MATCH NOTES",
		"-----------",
	]
	var highlights: Array = report.get("rating_highlights", [])
	if highlights.is_empty():
		lines.append("- A straightforward wrestling contest")
	else:
		for highlight in highlights:
			lines.append("- %s" % str(highlight))
	lines.append_array(["", "COMPLETE PLAY-BY-PLAY", "---------------------"])
	var log_lines: Array = report.get("log_lines", [])
	if log_lines.is_empty():
		lines.append("No match log entries were recorded.")
	else:
		for log_line in log_lines:
			lines.append(str(log_line))
	return "\n".join(lines) + "\n"


func _build_legacy_match_report_text(report: Dictionary) -> String:
	var lines: Array[String] = [
		"RISE TO RELEVANCE - MATCH REPORT",
		"================================",
		"",
		"MATCH SUMMARY",
		"-------------",
		"Match: %s" % str(report.get("subtitle", "Match")),
		"Winner: %s" % str(report.get("winner", "Not Set")),
		"Result: %s" % str(report.get("result", "Not Set")),
		"Match time: %s" % str(report.get("final_time", "00:00")),
		"Finish: %s" % str(report.get("finish_move", "None")),
		"",
		"Major turning points:",
	]
	var turning_points := _extract_major_turning_points(report.get("log_lines", []))
	if turning_points.is_empty():
		lines.append("- No major turning points were recorded.")
	else:
		for turning_point in turning_points:
			lines.append("- %s" % turning_point)
	lines.append_array(["", "KEY STATS", "---------"])
	lines.append_array(_side_key_report_text(report.get("player", {})))
	lines.append("")
	lines.append_array(_side_key_report_text(report.get("ai", {})))
	lines.append_array([
		"",
		"DEBUG METRICS",
		"-------------",
		"Match configuration",
		"~~~~~~~~~~~~~~~~~~~",
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
		"Final environmental objects: %s" % _format_environment_report(report.get("environment_objects", [])),
		"",
		"Complete tracked wrestler metrics",
		"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
	])
	lines.append_array(_side_report_text(report.get("player", {})))
	lines.append("")
	lines.append_array(_side_report_text(report.get("ai", {})))
	lines.append_array(["", "Complete match log", "~~~~~~~~~~~~~~~~~~"])
	var log_lines: Array = report.get("log_lines", [])
	if log_lines.is_empty():
		lines.append("No match log entries were recorded.")
	else:
		for log_line in log_lines:
			lines.append(str(log_line))
	return "\n".join(lines) + "\n"


func _side_key_report_text(stats: Dictionary) -> Array[String]:
	return [
		str(stats.get("heading", "UNASSIGNED")),
		"Moves landed: %d / %d" % [int(stats.get("moves_landed", 0)), int(stats.get("move_attempts", 0))],
		"Reversals: %d" % int(stats.get("reversals", 0)),
		"Stamina / Fatigue: %d/%d (%.0f%%) / %.0f%%" % [
			roundi(float(stats.get("stamina", 0.0))),
			roundi(float(stats.get("max_stamina", 100.0))),
			float(stats.get("stamina_percent", 0.0)),
			float(stats.get("fatigue", 0.0)),
		],
		"Pins / Kickouts: %d / %d" % [int(stats.get("pin_attempts", 0)), int(stats.get("kickouts", 0))],
		"Submissions / Escapes / Wins: %d / %d / %d" % [
			int(stats.get("submission_attempts", 0)),
			int(stats.get("submission_escapes", 0)),
			int(stats.get("submission_wins", 0)),
		],
		"Signatures: %d earned / %d landed | Ready: %s" % [
			int(stats.get("signatures_earned", 0)),
			int(stats.get("signatures_landed", 0)),
			"Yes" if bool(stats.get("signature_ready", false)) else "No",
		],
		"Finishers: %d attempted / %d landed | Stock: %d/3" % [
			int(stats.get("finisher_attempts", 0)),
			int(stats.get("finishers_landed", 0)),
			int(stats.get("finisher_stock", 0)),
		],
	]


func _extract_major_turning_points(raw_log_lines: Array) -> Array[String]:
	const MAX_TURNING_POINTS := 8
	var candidates: Array[String] = []
	for raw_line in raw_log_lines:
		var log_line := str(raw_line).strip_edges()
		var lower := log_line.to_lower()
		if (
			"kicks out" in lower
			or "three!" in lower
			or "taps out" in lower
			or "wins by" in lower
			or "defeats" in lower
			or "counted out" in lower
			or "disqualified" in lower
			or "crashes hard" in lower
			or "cannot maintain control" in lower
			or "breaks the hold" in lower
			or "claws free" in lower
			or "by surprise" in lower
			or "through the table" in lower
			or "onto the thumbtacks" in lower
			or "completely spent" in lower
			or "one last burst" in lower
			or "signature" in lower
			or "finisher" in lower
		):
			if log_line not in candidates:
				candidates.append(log_line)
	if candidates.size() <= MAX_TURNING_POINTS:
		return candidates
	var sampled: Array[String] = []
	for index in range(MAX_TURNING_POINTS):
		var source_index := roundi(float(index) * float(candidates.size() - 1) / float(MAX_TURNING_POINTS - 1))
		var candidate := candidates[source_index]
		if candidate not in sampled:
			sampled.append(candidate)
	return sampled


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
		"Weapons dropped: %d | Bleeding caused: %d | Final bleeding: %s" % [int(stats.get("weapons_dropped", 0)), int(stats.get("bleeding_caused", 0)), str(stats.get("final_bleeding", "None"))],
		"Tables: %d set | %d stacked | %d broken | %d delivered / %d taken" % [int(stats.get("tables_set", 0)), int(stats.get("tables_stacked", 0)), int(stats.get("tables_broken", 0)), int(stats.get("table_spots_landed", 0)), int(stats.get("table_spots_taken", 0))],
		"Ladders: %d set | %d climb stages | %d interrupted | %d dives | %d crashes" % [int(stats.get("ladder_setups", 0)), int(stats.get("ladder_climb_stages", 0)), int(stats.get("ladder_climbs_interrupted", 0)), int(stats.get("ladder_dives", 0)), int(stats.get("ladder_crashes", 0))],
		"Thumbtacks: %d spread | %d delivered / %d taken | Environmental reversals %d" % [int(stats.get("thumbtack_patches_spread", 0)), int(stats.get("thumbtack_spots_landed", 0)), int(stats.get("thumbtack_spots_taken", 0)), int(stats.get("environmental_reversals", 0))],
		"Setup actions: %d total | %d tactical | %d recoveries | %d Catch Breath | %d taunts" % [
			int(stats.get("setup_actions", 0)),
			int(stats.get("tactical_setup_actions", 0)),
			int(stats.get("recovery_setup_actions", 0)),
			int(stats.get("catch_breath_uses", 0)),
			int(stats.get("taunts_attempted", 0)),
		],
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
		_report_execution_line(stats),
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
		"Flow safeguards: %d dead ends prevented | %d forced fallbacks | %d mandatory recoveries | late pressure %.1f" % [
			int(stats.get("dead_end_setups_prevented", 0)),
			int(stats.get("forced_fallbacks", 0)),
			int(stats.get("mandatory_recoveries", 0)),
			float(stats.get("average_late_escalation", 0.0)),
		],
		"Target focus: %s (%s) | Most used: %s" % [
			str(stats.get("final_target_focus", "Auto")),
			str(stats.get("target_focus_reason", "Auto")),
			str(stats.get("most_used_focus", "Auto")),
		],
		"Body targeting: most attacked target %s | target's most damaged %s | own most damaged %s" % [
			str(stats.get("most_targeted_part", "None")),
			str(stats.get("target_most_damaged_part", stats.get("most_damaged_part", "None"))),
			str(stats.get("own_most_damaged_part", stats.get("most_damaged_part", "None"))),
		],
		"Per-part attacks: %s" % str(stats.get("per_part_attacks", "None")),
		"Per-part damage dealt: %s" % str(stats.get("per_part_damage", "None")),
		"Damage thresholds: %s | At zero: %s" % [
			str(stats.get("thresholds_crossed", "None")),
			str(stats.get("parts_reaching_zero", "None")),
		],
		"Submission target: %s (HP %s at lock-in / %s at resolution) | Finisher target: %s | Repeated targeting: %s" % [
			str(stats.get("last_submission_target", "None")),
			_report_submission_hp_label(stats.get("last_submission_target_hp_at_lock_in", -1.0)),
			_report_submission_hp_label(stats.get("last_submission_target_hp_at_resolution", -1.0)),
			str(stats.get("last_finisher_target", "None")),
			str(stats.get("targeting_milestones", "None")),
		],
		"Reversible setups: %d initiated | %d completed | %d reversed | %d defensive interruptions" % [
			int(stats.get("contested_setup_attempts", 0)),
			int(stats.get("contested_setup_wins", 0)),
			int(stats.get("contested_setup_losses", 0)),
			int(stats.get("contested_setup_defensive_interruptions", 0)),
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
		"Exhaustion: %s | minimum stamina %.1f / %.1f (%.0f%%) | maximum fatigue %.0f%%" % [
			str(stats.get("final_exhaustion_band", "Fresh")),
			float(stats.get("minimum_stamina", 100.0)),
			float(stats.get("max_stamina", 100.0)),
			float(stats.get("minimum_stamina_percent", stats.get("minimum_stamina", 100.0))),
			float(stats.get("maximum_fatigue", 0.0)),
		],
		"Zero-stamina actions: %d attempted | %d successful | exhausted high-risk %d | demanding weapons %d" % [
			int(stats.get("zero_stamina_attempts", 0)),
			int(stats.get("zero_stamina_successes", 0)),
			int(stats.get("exhausted_high_risk_attempts", 0)),
			int(stats.get("exhausted_demanding_weapon_attempts", 0)),
		],
		"Recovery: %d Catch Breath | %.1f stamina restored | %d delays | %d exhaustion control losses" % [
			int(stats.get("catch_breath_uses", 0)),
			float(stats.get("total_stamina_recovered", 0.0)),
			int(stats.get("delayed_recoveries", 0)),
			int(stats.get("exhaustion_control_losses", 0)),
		],
		"Average exhaustion tuning: %.1f%% execution penalty | %.2fx fatigue amplification" % [
			float(stats.get("average_stamina_execution_penalty", 0.0)),
			float(stats.get("average_fatigue_amplification", 1.0)),
		],
		"Average attribute tuning: damage x%.3f | defender reversal %+.1f | attacker difficulty %+.1f | setup %+.1f" % [
			float(stats.get("average_attribute_damage_multiplier", 1.0)),
			float(stats.get("average_attribute_reversal_modifier", 0.0)),
			float(stats.get("average_attribute_reversal_difficulty", 0.0)),
			float(stats.get("average_attribute_setup_modifier", 0.0)),
		],
		"Submission attribute tuning: attack %+.1f | defence %+.1f | taunt momentum %+.1f | movement recovery %+.1f" % [
			float(stats.get("average_attribute_submission_attack", 0.0)),
			float(stats.get("average_attribute_submission_defence", 0.0)),
			float(stats.get("average_attribute_taunt_momentum_bonus", 0.0)),
			float(stats.get("average_attribute_movement_recovery", 0.0)),
		],
		"Last attribute profile: %s" % str(stats.get("last_attribute_profile", "neutral")),
		"Damage dealt / taken: %.1f / %.1f" % [float(stats.get("damage_dealt", 0.0)), float(stats.get("damage_taken", 0.0))],
		"Stamina: %.1f / %.1f (%.0f%%) | Fatigue: %.0f%% | Momentum: %.0f%%" % [
			float(stats.get("stamina", 0.0)),
			float(stats.get("max_stamina", 100.0)),
			float(stats.get("stamina_percent", 0.0)),
			float(stats.get("fatigue", 0.0)),
			float(stats.get("momentum", 0.0)),
		],
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


func _report_execution_line(stats: Dictionary) -> String:
	if str(stats.get("execution_mode", "meter")) == "automatic_reversal_only":
		return "Execution: Automatic — defender reversal only"
	return "Execution meter: %d attempted / %d successful" % [
		int(stats.get("execution_attempts", 0)),
		int(stats.get("execution_successes", 0)),
	]


func _report_submission_hp_label(value: Variant) -> String:
	var hp := float(value)
	return "N/A" if hp < 0.0 else "%d%%" % int(roundf(hp))


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
