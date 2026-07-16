extends Control
class_name SetupActionsMenu

signal action_selected(action_id: StringName)

const STAND_UP := &"stand_up"
const PREPARE_SPRINGBOARD := &"prepare_springboard"
const START_RUNNING := &"start_running"
const CLIMB_TOP_ROPE := &"climb_top_rope"
const PICK_OPPONENT_UP := &"pick_opponent_up"
const IRISH_WHIP := &"irish_whip"
const GRAPPLE_OPPONENT := &"grapple_opponent"
const THROW_INTO_CORNER := &"throw_into_corner"
const WAKE_OPPONENT := &"wake_opponent"
const STOP_RUNNING := &"stop_running"
const LEAVE_CORNER := &"leave_corner"
const REGAIN_FOOTING := &"regain_footing"
const CLIMB_DOWN := &"climb_down"
const RETURN_TO_RING := &"return_to_ring"
const RESET_STANCE := &"reset_stance"
const TAUNT := &"taunt"

var _attacker: WrestlerResource
var _target: WrestlerResource
var _allowed_actions: Array[StringName] = []

@onready var _state_label: Label = %StateLabel
@onready var _action_list: VBoxContainer = %ActionList
@onready var _action_scroll: ScrollContainer = %ActionScroll
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	visible = false


func open_for_match(
	attacker: WrestlerResource,
	target: WrestlerResource,
	allowed_actions: Array[StringName] = [],
) -> void:
	_attacker = attacker
	_target = target
	_allowed_actions = allowed_actions
	_rebuild_actions()
	visible = true
	_close_button.grab_focus()


func close() -> void:
	visible = false
	_clear_actions()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


static func get_valid_actions(
	attacker: WrestlerResource,
	target: WrestlerResource,
	allow_reset_stance: bool = false,
) -> Array[StringName]:
	var actions: Array[StringName] = []
	if attacker == null or target == null:
		return actions

	var standing := WrestlerResource.Position.STANDING
	var grounded := WrestlerResource.Position.GROUNDED
	var top_rope := WrestlerResource.Position.TOP_ROPE

	match attacker.position:
		WrestlerResource.Position.GROUNDED:
			actions.append(STAND_UP)
		WrestlerResource.Position.RUNNING:
			actions.append(STOP_RUNNING)
		WrestlerResource.Position.IN_CORNER:
			actions.append(LEAVE_CORNER)
		WrestlerResource.Position.ROPE_REBOUND:
			actions.append(REGAIN_FOOTING)
		WrestlerResource.Position.TOP_ROPE:
			actions.append(CLIMB_DOWN)
		WrestlerResource.Position.APRON:
			actions.append(RETURN_TO_RING)

	if attacker.position == standing:
		actions.append(START_RUNNING)
		actions.append(CLIMB_TOP_ROPE)
		actions.append(PREPARE_SPRINGBOARD)
	if (
		attacker.position in [standing, WrestlerResource.Position.APRON, top_rope]
		and target.position in [standing, grounded]
	):
		actions.append(TAUNT)

	if attacker.position == standing and target.position == grounded:
		actions.append(PICK_OPPONENT_UP)
	if attacker.position == standing and target.position == standing:
		actions.append(GRAPPLE_OPPONENT)
		actions.append(IRISH_WHIP)
		actions.append(THROW_INTO_CORNER)
	if attacker.position == top_rope and target.position == grounded:
		actions.append(WAKE_OPPONENT)

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
	_clear_actions()
	if _attacker == null or _target == null:
		_state_label.text = "Assign both wrestlers to use setup actions."
		return

	_state_label.text = "%s: %s   |   %s: %s" % [
		_wrestler_name(_attacker),
		_position_name(_attacker.position),
		_wrestler_name(_target),
		_position_name(_target.position),
	]

	var actions := _allowed_actions
	if actions.is_empty():
		actions = get_valid_actions(_attacker, _target, true)
	for action_id in actions:
		var details := _action_details(action_id, _attacker.position)
		_add_action(action_id, str(details.title), str(details.description))

	await get_tree().process_frame
	_action_scroll.scroll_vertical = 0


static func _action_details(
	action_id: StringName,
	attacker_position: int = WrestlerResource.Position.STANDING,
) -> Dictionary:
	match action_id:
		STAND_UP:
			return {"title": "STAND UP / RETURN TO STANDING", "description": "Push back to a standing position."}
		START_RUNNING:
			return {"title": "START RUNNING", "description": "Hit the ropes and build speed for a running attack."}
		CLIMB_TOP_ROPE:
			return {"title": "CLIMB TOP ROPE", "description": "Climb to the top turnbuckle for a diving move."}
		PREPARE_SPRINGBOARD:
			return {"title": "STEP TO APRON", "description": "Move onto the apron for a springboard move."}
		RETURN_TO_RING:
			return {"title": "RETURN TO RING", "description": "Return from the apron or top rope to standing."}
		CLIMB_DOWN:
			return {"title": "CLIMB DOWN", "description": "Leave the top rope and return to standing in the ring."}
		PICK_OPPONENT_UP:
			return {"title": "PICK OPPONENT UP", "description": "Drag the grounded opponent back to standing."}
		GRAPPLE_OPPONENT:
			return {"title": "GRAPPLE OPPONENT", "description": "Tie up while both wrestlers remain standing."}
		IRISH_WHIP:
			return {"title": "IRISH WHIP OPPONENT", "description": "Force the standing opponent into a rope rebound."}
		THROW_INTO_CORNER:
			return {"title": "THROW OPPONENT INTO CORNER", "description": "Drive the standing opponent into the corner."}
		WAKE_OPPONENT:
			return {"title": "WAKE OPPONENT / CALL TO FEET", "description": "Call the grounded opponent up while staying on the top rope."}
		STOP_RUNNING:
			return {"title": "STOP RUNNING / RESET STANCE", "description": "Slow down and return to standing."}
		LEAVE_CORNER:
			return {"title": "LEAVE THE CORNER", "description": "Step out of the corner and return to standing."}
		REGAIN_FOOTING:
			return {"title": "REGAIN FOOTING", "description": "Recover from the forced rope rebound."}
		RESET_STANCE:
			return {"title": "RESET STANCE", "description": "Use the match fallback and return to standing."}
		TAUNT:
			match attacker_position:
				WrestlerResource.Position.TOP_ROPE:
					return {"title": "TOP-ROPE TAUNT", "description": "Risk a high-reward pose from the top rope."}
				WrestlerResource.Position.APRON:
					return {"title": "APRON TAUNT", "description": "Play to the crowd from the apron for momentum."}
			return {"title": "TAUNT / PLAY TO CROWD", "description": "Showboat for stamina, momentum, and a next-move boost."}
	return {"title": "SETUP ACTION", "description": "Change the current match position."}


func _add_action(action_id: StringName, title: String, description: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = title
	button.tooltip_text = description
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_select_action.bind(action_id))
	_action_list.add_child(button)


func _select_action(action_id: StringName) -> void:
	action_selected.emit(action_id)
	close()


func _clear_actions() -> void:
	for child in _action_list.get_children():
		child.queue_free()


func _position_name(current_position: int) -> String:
	for key in WrestlerResource.Position:
		if int(WrestlerResource.Position[key]) == current_position:
			return "Not Set" if key == "NONE" else str(key).replace("_", " ").to_lower().capitalize()
	return "Unknown"


func _wrestler_name(wrestler: WrestlerResource) -> String:
	var display_name: String = wrestler.wrestler_name.strip_edges()
	return "Unnamed Wrestler" if display_name.is_empty() else display_name
