extends Control
class_name SetupActionsMenu

signal action_selected(action_id: StringName)

const STAND_UP := MatchSetupStateRules.STAND_UP
const PREPARE_SPRINGBOARD := MatchSetupStateRules.PREPARE_SPRINGBOARD
const START_RUNNING := MatchSetupStateRules.START_RUNNING
const CLIMB_TOP_ROPE := MatchSetupStateRules.CLIMB_TOP_ROPE
const PICK_OPPONENT_UP := MatchSetupStateRules.PICK_OPPONENT_UP
const IRISH_WHIP := MatchSetupStateRules.IRISH_WHIP
const GRAPPLE_OPPONENT := MatchSetupStateRules.GRAPPLE_OPPONENT
const THROW_INTO_CORNER := MatchSetupStateRules.THROW_INTO_CORNER
const WAKE_OPPONENT := MatchSetupStateRules.WAKE_OPPONENT
const STOP_RUNNING := MatchSetupStateRules.STOP_RUNNING
const LEAVE_CORNER := MatchSetupStateRules.LEAVE_CORNER
const REGAIN_FOOTING := MatchSetupStateRules.REGAIN_FOOTING
const CLIMB_DOWN := MatchSetupStateRules.CLIMB_DOWN
const RETURN_TO_RING := MatchSetupStateRules.RETURN_TO_RING
const RESET_STANCE := MatchSetupStateRules.RESET_STANCE
const TAUNT := MatchSetupStateRules.TAUNT
const STEP_TO_ROPES := MatchSetupStateRules.STEP_TO_ROPES
const LEAVE_ROPES := MatchSetupStateRules.LEAVE_ROPES
const GET_BEHIND_OPPONENT := MatchSetupStateRules.GET_BEHIND_OPPONENT
const TURN_OPPONENT_FACE_UP := MatchSetupStateRules.TURN_OPPONENT_FACE_UP
const TURN_OPPONENT_FACE_DOWN := MatchSetupStateRules.TURN_OPPONENT_FACE_DOWN
const SIT_OPPONENT_UP_FRONT := MatchSetupStateRules.SIT_OPPONENT_UP_FRONT
const SIT_OPPONENT_UP_BACK := MatchSetupStateRules.SIT_OPPONENT_UP_BACK
const PULL_OPPONENT_TO_KNEES_FRONT := MatchSetupStateRules.PULL_OPPONENT_TO_KNEES_FRONT
const PULL_OPPONENT_TO_KNEES_BACK := MatchSetupStateRules.PULL_OPPONENT_TO_KNEES_BACK
const TURN_OPPONENT_IN_CORNER := MatchSetupStateRules.TURN_OPPONENT_IN_CORNER
const SEAT_OPPONENT_IN_CORNER := MatchSetupStateRules.SEAT_OPPONENT_IN_CORNER
const LEAN_OPPONENT_ON_ROPES_FRONT := MatchSetupStateRules.LEAN_OPPONENT_ON_ROPES_FRONT
const LEAN_OPPONENT_ON_ROPES_BACK := MatchSetupStateRules.LEAN_OPPONENT_ON_ROPES_BACK
const DRAPE_OPPONENT_ON_ROPES_FRONT := MatchSetupStateRules.DRAPE_OPPONENT_ON_ROPES_FRONT
const DRAPE_OPPONENT_ON_ROPES_BACK := MatchSetupStateRules.DRAPE_OPPONENT_ON_ROPES_BACK
const PLACE_OPPONENT_ON_APRON_FRONT := MatchSetupStateRules.PLACE_OPPONENT_ON_APRON_FRONT
const PLACE_OPPONENT_ON_APRON_BACK := MatchSetupStateRules.PLACE_OPPONENT_ON_APRON_BACK
const SET_OPPONENT_ON_TOP_ROPE_FRONT := MatchSetupStateRules.SET_OPPONENT_ON_TOP_ROPE_FRONT
const SET_OPPONENT_ON_TOP_ROPE_BACK := MatchSetupStateRules.SET_OPPONENT_ON_TOP_ROPE_BACK
const SEND_OPPONENT_OUTSIDE := MatchSetupStateRules.SEND_OPPONENT_OUTSIDE
const CALL_OPPONENT_OUTSIDE := MatchSetupStateRules.CALL_OPPONENT_OUTSIDE
const EXIT_RING := MatchSetupStateRules.EXIT_RING
const TAKE_FIGHT_OUTSIDE := MatchSetupStateRules.TAKE_FIGHT_OUTSIDE
const FIGHT_UP_RAMP := MatchSetupStateRules.FIGHT_UP_RAMP
const RETURN_FROM_RAMP := MatchSetupStateRules.RETURN_FROM_RAMP
const BRING_MATCH_BACK_TO_RING := MatchSetupStateRules.BRING_MATCH_BACK_TO_RING
const CALL_OPPONENT_RUNNING := MatchSetupStateRules.CALL_OPPONENT_RUNNING
const REGAIN_COMPOSURE := MatchSetupStateRules.REGAIN_COMPOSURE
const PRESS_ADVANTAGE := MatchSetupStateRules.PRESS_ADVANTAGE
const WAIT_FOR_COUNT := MatchSetupStateRules.WAIT_FOR_COUNT
const RETRIEVE_STEEL_CHAIR := MatchSetupStateRules.RETRIEVE_STEEL_CHAIR
const PICK_UP_WEAPON := MatchSetupStateRules.PICK_UP_WEAPON
const DROP_WEAPON := MatchSetupStateRules.DROP_WEAPON
const CHAIR_SHOT := MatchSetupStateRules.CHAIR_SHOT

enum ActionGroup { RECOVERY, MOVEMENT, OPPONENT_SETUP, RING_POSITION, SHOWBOAT, WEAPON }

var _attacker: WrestlerResource
var _target: WrestlerResource
var _allowed_actions: Array[StringName] = []
var _grid_columns: int = 4
var _button_height: float = 54.0
var _disqualifications_enabled: bool = true

@onready var _panel: PanelContainer = %SetupPanel
@onready var _context_label: Label = %StateLabel
@onready var _sections: VBoxContainer = %ActionSections
@onready var _close_button: Button = %CloseButton
@onready var _safe_area: MarginContainer = %ActionSafeArea


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_close_button.pressed.connect(close)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var portrait := effective_size.y > effective_size.x
	_grid_columns = 2 if mode == ResponsiveUI.LayoutMode.PHONE and portrait else (3 if mode != ResponsiveUI.LayoutMode.DESKTOP else 4)
	var panel_size := Vector2(
		clampf(effective_size.x - 32.0, 600.0, 1120.0),
		clampf(effective_size.y - 28.0, 460.0, 820.0),
	)
	_panel.custom_minimum_size = panel_size
	_button_height = 46.0 if panel_size.y < 600.0 else 54.0
	if visible:
		_rebuild_actions()


func open_for_match(
	attacker: WrestlerResource,
	target: WrestlerResource,
	allowed_actions: Array[StringName] = [],
) -> void:
	_attacker = attacker
	_target = target
	_allowed_actions = allowed_actions
	if _allowed_actions.is_empty() and _attacker != null and _target != null:
		_allowed_actions = get_valid_actions(_attacker, _target, true)
	_rebuild_actions()
	visible = true
	_close_button.grab_focus()


func set_rule_context(disqualifications_enabled: bool) -> void:
	_disqualifications_enabled = disqualifications_enabled


func close() -> void:
	visible = false
	_clear_sections()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


static func get_valid_actions(
	attacker: WrestlerResource,
	target: WrestlerResource,
	allow_reset_stance: bool = false,
) -> Array[StringName]:
	var actions := MatchSetupStateRules.get_candidate_actions(attacker, target)
	if actions.is_empty() and allow_reset_stance:
		actions.append(RESET_STANCE)
	return actions


static func has_valid_actions(
	attacker: WrestlerResource,
	target: WrestlerResource,
	allow_reset_stance: bool = false,
) -> bool:
	return not get_valid_actions(attacker, target, allow_reset_stance).is_empty()


func _rebuild_actions() -> void:
	_clear_sections()
	if _attacker == null or _target == null:
		_context_label.text = "Assign both wrestlers to use setup actions."
		return
	_context_label.text = "%s vs %s" % [_state_name(_attacker), _state_name(_target)]
	var grouped: Dictionary = {}
	for group in ActionGroup.values():
		grouped[group] = []
	for action_id in _allowed_actions:
		(grouped[_group_for_action(action_id)] as Array).append(action_id)
	for group in ActionGroup.values():
		var actions: Array = grouped[group]
		if actions.is_empty():
			continue
		_add_group_section(group, actions)


func _add_group_section(group: int, actions: Array) -> void:
	var details := _group_details(group)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	var heading := Label.new()
	heading.text = "%s  •  %d" % [str(details.label).to_upper(), actions.size()]
	heading.add_theme_color_override("font_color", details.color)
	heading.add_theme_font_size_override("font_size", 14)
	section.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = mini(_grid_columns, actions.size())
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	section.add_child(grid)
	for action_value in actions:
		var action_id := StringName(action_value)
		var action_details := _action_details(action_id, _attacker.position, _attacker.area)
		if action_id == CHAIR_SHOT and _disqualifications_enabled:
			action_details.title = "CHAIR SHOT — WILL CAUSE DISQUALIFICATION"
			action_details.description = "Committing this illegal chair attack will immediately cost the match."
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, _button_height)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = str(action_details.title)
		button.tooltip_text = str(action_details.description)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_select_action.bind(action_id))
		grid.add_child(button)
	_sections.add_child(section)


func _select_action(action_id: StringName) -> void:
	action_selected.emit(action_id)
	close()


func _clear_sections() -> void:
	for child in _sections.get_children():
		child.queue_free()


func _group_for_action(action_id: StringName) -> int:
	if action_id == TAUNT:
		return ActionGroup.SHOWBOAT
	if action_id in [RETRIEVE_STEEL_CHAIR, PICK_UP_WEAPON, DROP_WEAPON, CHAIR_SHOT]:
		return ActionGroup.WEAPON
	if MatchSetupStateRules.is_recovery(action_id) or action_id == RESET_STANCE:
		return ActionGroup.RECOVERY
	if action_id in [START_RUNNING, CLIMB_TOP_ROPE, PREPARE_SPRINGBOARD, STEP_TO_ROPES]:
		return ActionGroup.MOVEMENT
	if action_id in [SEND_OPPONENT_OUTSIDE, CALL_OPPONENT_OUTSIDE, EXIT_RING, TAKE_FIGHT_OUTSIDE, FIGHT_UP_RAMP, RETURN_FROM_RAMP, BRING_MATCH_BACK_TO_RING]:
		return ActionGroup.RING_POSITION
	return ActionGroup.OPPONENT_SETUP


func _group_details(group: int) -> Dictionary:
	match group:
		ActionGroup.RECOVERY:
			return {"label": "Recovery", "color": Color(0.44, 0.75, 1.0, 1.0)}
		ActionGroup.MOVEMENT:
			return {"label": "Movement", "color": Color(0.55, 0.8, 1.0, 1.0)}
		ActionGroup.OPPONENT_SETUP:
			return {"label": "Opponent Setup", "color": Color(0.92, 0.93, 0.9, 1.0)}
		ActionGroup.RING_POSITION:
			return {"label": "Ring Position", "color": Color(0.83, 0.67, 0.24, 1.0)}
		ActionGroup.SHOWBOAT:
			return {"label": "Showboat", "color": Color(0.96, 0.8, 0.28, 1.0)}
		ActionGroup.WEAPON:
			return {"label": "Weapons", "color": Color(1.0, 0.48, 0.36, 1.0)}
	return {"label": "Setup", "color": Color(0.84, 0.87, 0.92, 1.0)}


static func _action_details(
	action_id: StringName,
	attacker_position: int = WrestlerResource.Position.STANDING,
	attacker_area: int = WrestlerResource.Area.IN_RING,
) -> Dictionary:
	return MatchSetupStateRules.action_details(action_id, {
		"position": attacker_position,
		"orientation": WrestlerResource.Orientation.FRONT,
		"area": attacker_area,
		"motion_state": WrestlerResource.MotionState.STATIONARY,
	})


func _state_name(wrestler: WrestlerResource) -> String:
	return "Unassigned" if wrestler == null else MatchSetupStateRules.state_name(wrestler)
