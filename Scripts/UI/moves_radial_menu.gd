extends Control
class_name MovesRadialMenu

signal move_selected(move: MoveResource)
signal player_move_selected(move: MoveResource)
signal target_focus_changed(part: int)

const FINISHER_COLOR := Color(0.95, 0.78, 0.22, 1.0)
const MOVE_BUTTON_HEIGHT := 58.0
const MOVE_GRID_GAP := 8.0
const MOVE_GRID_RESERVED_HEIGHT := 205.0
const MIN_MOVE_BUTTON_WIDTH := 150.0
const CATEGORY_DEFINITIONS: Array[Dictionary] = [
	{"id": MoveResource.MoveType.STRIKE, "label": "Strikes", "icon_id": &"strike"},
	{"id": MoveResource.MoveType.GRAPPLE, "label": "Grapples", "icon_id": &"grapple"},
	{"id": MoveResource.MoveType.SUBMISSION, "label": "Submissions", "icon_id": &"submission"},
	{"id": MoveResource.MoveType.AERIAL, "label": "Aerial", "icon_id": &"aerial"},
	{"id": MoveResource.MoveType.SPRINGBOARD, "label": "Springboard", "icon_id": &"springboard"},
	{"id": MoveResource.MoveType.RUNNING, "label": "Running", "icon_id": &"running"},
	{"id": MoveResource.MoveType.REVERSAL, "label": "Reversals", "icon_id": &"reversal"},
	{"id": MoveResource.MoveType.PINNING_MOVE, "label": "Pinning Moves", "icon_id": &"pinning"},
	{"id": MoveResource.MoveType.WEAPON, "label": "Weapons", "icon_id": &"weapon"},
	{"id": MoveResource.MoveType.ENVIRONMENTAL, "label": "Environment", "icon_id": &"environmental"},
]

var _wrestler: WrestlerResource
var _target: WrestlerResource
var _target_state: MatchSideState
var _extra_moves: Array[MoveResource] = []
var _valid_move_filter: Callable
var _unavailable_reason_filter: Callable
var _interaction_allowed_filter: Callable
var _last_attacker_position: int = -1
var _last_target_position: int = -1
var _last_attacker_state_key: String = ""
var _last_target_state_key: String = ""
var _visible_move_count: int = 0
var _move_panel_size: Vector2 = Vector2(980, 650)
var _target_focus: int = MoveResource.MoveTargetParts.NONE
var _active_move_type: int = MoveResource.MoveType.NONE

@onready var _category_menu: MoveCategoryRadialMenu = %CategoryMenu
@onready var _move_panel: PanelContainer = %MovePanel
@onready var _move_category_title: Label = %MoveCategoryTitle
@onready var _move_grid: GridContainer = %MoveGrid
@onready var _target_focus_selector: OptionButton = %TargetFocusSelector
@onready var _back_button: Button = %BackButton
@onready var _close_moves_button: Button = %CloseMovesButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	_category_menu.category_selected.connect(_show_move_category)
	_category_menu.cancelled.connect(_on_category_cancelled)
	_back_button.pressed.connect(_show_categories)
	_close_moves_button.pressed.connect(close)
	_configure_target_focus_selector()
	_target_focus_selector.item_selected.connect(_on_target_focus_selected)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var phone_layout := mode == ResponsiveUI.LayoutMode.PHONE
	var tablet_layout := mode == ResponsiveUI.LayoutMode.TABLET
	if phone_layout:
		_move_panel_size = Vector2(
			clampf(effective_size.x - 32.0, 620.0, 1180.0),
			clampf(effective_size.y - 24.0, 500.0, 900.0),
		)
	elif tablet_layout:
		_move_panel_size = Vector2(820, 650)
	else:
		_move_panel_size = Vector2(980, 650)
	_move_panel.custom_minimum_size = _move_panel_size
	_apply_move_grid_columns(mode)


func open_for_wrestler(
	value: WrestlerResource,
	_player_controlled: bool = true,
	target: WrestlerResource = null,
	valid_move_filter: Callable = Callable(),
	unavailable_reason_filter: Callable = Callable(),
	interaction_allowed_filter: Callable = Callable(),
	target_state: MatchSideState = null,
	extra_moves: Array[MoveResource] = [],
) -> void:
	_wrestler = value
	_target = target
	_valid_move_filter = valid_move_filter
	_unavailable_reason_filter = unavailable_reason_filter
	_interaction_allowed_filter = interaction_allowed_filter
	_target_state = target_state
	_extra_moves = extra_moves.duplicate()
	_last_attacker_position = value.position if value != null else -1
	_last_target_position = target.position if target != null else -1
	_last_attacker_state_key = _resource_state_key(value)
	_last_target_state_key = _resource_state_key(target)
	visible = true
	_show_categories()


func refresh_match_state(
	attacker: WrestlerResource,
	target: WrestlerResource,
	valid_move_filter: Callable = Callable(),
	unavailable_reason_filter: Callable = Callable(),
	target_state: MatchSideState = null,
) -> void:
	var next_attacker_position := attacker.position if attacker != null else -1
	var next_target_position := target.position if target != null else -1
	var next_attacker_state_key := _resource_state_key(attacker)
	var next_target_state_key := _resource_state_key(target)
	var state_changed := (
		attacker != _wrestler
		or target != _target
		or next_attacker_position != _last_attacker_position
		or next_target_position != _last_target_position
		or next_attacker_state_key != _last_attacker_state_key
		or next_target_state_key != _last_target_state_key
	)
	_wrestler = attacker
	_target = target
	_valid_move_filter = valid_move_filter
	_unavailable_reason_filter = unavailable_reason_filter
	_target_state = target_state
	_last_attacker_position = next_attacker_position
	_last_target_position = next_target_position
	_last_attacker_state_key = next_attacker_state_key
	_last_target_state_key = next_target_state_key
	if not is_node_ready():
		return
	if state_changed and visible:
		close()
		return


func close() -> void:
	_category_menu.close_menu(true)
	visible = false
	_clear_move_buttons()
	_active_move_type = MoveResource.MoveType.NONE


func set_target_focus(part: int) -> void:
	_target_focus = part if MoveTargetResolver.is_target_focus(part) else MoveResource.MoveTargetParts.NONE
	_sync_target_focus_selector()
	if is_node_ready() and _move_panel.visible and _active_move_type != MoveResource.MoveType.NONE:
		_show_move_category(_active_move_type)


func get_target_focus() -> int:
	return _target_focus


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _category_menu.visible:
			return
		close()
		get_viewport().set_input_as_handled()


func _show_categories() -> void:
	if not _interaction_is_allowed():
		close()
		return
	_clear_move_buttons()
	_move_panel.visible = false
	_refresh_category_menu()
	_category_menu.show_menu()


func _show_move_category(move_type: int) -> void:
	if not _interaction_is_allowed():
		close()
		return
	_clear_move_buttons()
	var moves := _display_moves_for_type(move_type)
	if moves.is_empty():
		_show_categories()
		return
	_category_menu.close_menu(true)
	_active_move_type = move_type
	_move_panel.visible = true
	_move_category_title.text = _format_move_type(move_type)
	_visible_move_count = moves.size()
	_apply_move_grid_columns(ResponsiveUI.current_layout_mode)

	moves.sort_custom(func(left: MoveResource, right: MoveResource) -> bool:
		if left.is_finisher != right.is_finisher:
			return not left.is_finisher
		return left.move_name.nocasecmp_to(right.move_name) < 0
	)
	for move in moves:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, MOVE_BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var prefix := ""
		if move.is_finisher:
			prefix += "(F)"
		elif _wrestler != null and move in _wrestler.signature_moves:
			prefix += "(SIG)"
		if move.is_submission:
			prefix += "(S)"
		var target_resolution := MoveTargetResolver.resolve(move, _target_focus, _target_state)
		var target_tag := str(target_resolution.get(
			"compact_tag" if ResponsiveUI.current_layout_mode == ResponsiveUI.LayoutMode.PHONE else "full_tag",
			"BODY",
		))
		prefix += " [%s]" % target_tag
		var available := _move_is_valid(move)
		button.text = prefix.strip_edges() + " " + _move_name(move)
		button.tooltip_text = "Targets: %s" % str(target_resolution.get("full_tag", "BODY"))
		button.disabled = not available
		if not available:
			button.text += " — LOCKED"
			button.tooltip_text += "\n%s" % _unavailable_reason(move)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if move.is_finisher:
			button.add_theme_color_override("font_color", FINISHER_COLOR)
			button.add_theme_color_override("font_hover_color", FINISHER_COLOR.lightened(0.15))
			button.add_theme_color_override("font_pressed_color", FINISHER_COLOR)
		elif _wrestler != null and move in _wrestler.signature_moves:
			var signature_color := Color(0.48, 0.78, 1.0, 1.0)
			button.add_theme_color_override("font_color", signature_color)
			button.add_theme_color_override("font_hover_color", signature_color.lightened(0.15))
			button.add_theme_color_override("font_pressed_color", signature_color)
		button.pressed.connect(_select_move.bind(move))
		_move_grid.add_child(button)


func _select_move(move: MoveResource) -> void:
	move_selected.emit(move)
	player_move_selected.emit(move)
	close()


func _refresh_category_menu() -> void:
	var categories: Array[Dictionary] = []
	for definition in CATEGORY_DEFINITIONS:
		var move_type := int(definition.get("id", MoveResource.MoveType.NONE))
		var valid_moves := _valid_moves_for_type(move_type)
		var locked_finishers := _locked_finishers_for_type(move_type)
		var has_valid_finisher := false
		for move in valid_moves:
			if move.is_finisher:
				has_valid_finisher = true
				break
		var valid_count := valid_moves.size()
		var locked_count := locked_finishers.size()
		categories.append({
			"id": move_type,
			"label": str(definition.get("label", "Moves")),
			"icon_id": StringName(definition.get("icon_id", &"generic")),
			"valid_count": valid_count,
			"enabled": valid_count > 0 or locked_count > 0,
			"locked_only": valid_count == 0 and locked_count > 0,
			"has_valid_finisher": has_valid_finisher,
			"has_locked_finisher": locked_count > 0,
		})
	_category_menu.set_menu_data(
		categories,
		_state_label(_wrestler),
		_state_label(_target),
	)


func _on_category_cancelled() -> void:
	close()


func _interaction_is_allowed() -> bool:
	return not _interaction_allowed_filter.is_valid() or bool(_interaction_allowed_filter.call())


func _valid_moves_for_type(move_type: int) -> Array[MoveResource]:
	var matches: Array[MoveResource] = []
	if _wrestler == null:
		return matches
	for move in _all_assigned_moves():
		if (
			move != null
			and int(move.move_type) == move_type
			and _move_is_valid(move)
		):
			matches.append(move)
	return matches


func _display_moves_for_type(move_type: int) -> Array[MoveResource]:
	var matches: Array[MoveResource] = []
	if _wrestler == null:
		return matches
	for move in _all_assigned_moves():
		if (
			move != null
			and int(move.move_type) == move_type
			and _positions_are_valid(move)
			and (_move_is_valid(move) or move.is_finisher)
		):
			matches.append(move)
	return matches


func _all_assigned_moves() -> Array[MoveResource]:
	var moves: Array[MoveResource] = []
	if _wrestler == null:
		return moves
	for move in _wrestler.move_set:
		if move != null and move not in moves:
			moves.append(move)
	for move in _wrestler.signature_moves:
		if move != null and move not in moves:
			moves.append(move)
	for move in _wrestler.finisher_moves:
		if move != null and move not in moves:
			moves.append(move)
	for move in _extra_moves:
		if move != null and move not in moves:
			moves.append(move)
	return moves


func _locked_finishers_for_type(move_type: int) -> Array[MoveResource]:
	var matches: Array[MoveResource] = []
	for move in _display_moves_for_type(move_type):
		if move.is_finisher and not _move_is_valid(move):
			matches.append(move)
	return matches


func _move_is_valid(move: MoveResource) -> bool:
	# Older match screens do not provide a target yet; preserve their existing
	# unfiltered menu while the simple match UI always supplies both wrestlers.
	if _target == null:
		return not _valid_move_filter.is_valid() or bool(_valid_move_filter.call(move))
	return _positions_are_valid(move) and (
		not _valid_move_filter.is_valid()
		or bool(_valid_move_filter.call(move))
	)


func _positions_are_valid(move: MoveResource) -> bool:
	if _target == null:
		return true
	return (
		_position_matches(move.required_attacker_position, _wrestler.position)
		and _position_matches(move.required_target_position, _target.position)
		and _orientation_matches(move.required_attacker_orientation, _wrestler.orientation)
		and _orientation_matches(move.required_target_orientation, _target.orientation)
		and MatchAreaRules.move_areas_match(move, _wrestler.area, _target.area)
		and move.required_attacker_motion_state == _wrestler.motion_state
		and move.required_target_motion_state == _target.motion_state
	)


func _unavailable_reason(move: MoveResource) -> String:
	if _unavailable_reason_filter.is_valid():
		return str(_unavailable_reason_filter.call(move))
	return "This finisher is not currently available."


func _position_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Position.NONE or required == actual


func _orientation_matches(required: int, actual: int) -> bool:
	return required == WrestlerResource.Orientation.NONE or required == actual


func _clear_move_buttons() -> void:
	_visible_move_count = 0
	for child in _move_grid.get_children():
		_move_grid.remove_child(child)
		child.queue_free()


func _configure_target_focus_selector() -> void:
	_target_focus_selector.clear()
	_target_focus_selector.add_item("Auto", MoveResource.MoveTargetParts.NONE)
	_target_focus_selector.add_item("Head", MoveResource.MoveTargetParts.HEAD)
	_target_focus_selector.add_item("Body", MoveResource.MoveTargetParts.BODY)
	_target_focus_selector.add_item("Left Arm", MoveResource.MoveTargetParts.LEFT_ARM)
	_target_focus_selector.add_item("Right Arm", MoveResource.MoveTargetParts.RIGHT_ARM)
	_target_focus_selector.add_item("Left Leg", MoveResource.MoveTargetParts.LEFT_LEG)
	_target_focus_selector.add_item("Right Leg", MoveResource.MoveTargetParts.RIGHT_LEG)
	_sync_target_focus_selector()


func _sync_target_focus_selector() -> void:
	if not is_instance_valid(_target_focus_selector):
		return
	for index in range(_target_focus_selector.item_count):
		if _target_focus_selector.get_item_id(index) == _target_focus:
			_target_focus_selector.select(index)
			return
	_target_focus_selector.select(0)


func _on_target_focus_selected(index: int) -> void:
	var next_focus := _target_focus_selector.get_item_id(index)
	if next_focus == _target_focus:
		return
	_target_focus = next_focus
	target_focus_changed.emit(_target_focus)
	if _move_panel.visible and _active_move_type != MoveResource.MoveType.NONE:
		_show_move_category(_active_move_type)


func _apply_move_grid_columns(mode: int) -> void:
	if not is_instance_valid(_move_grid):
		return
	var preferred_columns := 4
	match mode:
		ResponsiveUI.LayoutMode.PHONE:
			preferred_columns = 2
		ResponsiveUI.LayoutMode.TABLET:
			preferred_columns = 3
	var available_width := maxf(1.0, _move_panel_size.x - 40.0)
	var available_height := maxf(
		MOVE_BUTTON_HEIGHT,
		_move_panel_size.y - MOVE_GRID_RESERVED_HEIGHT,
	)
	var maximum_columns := maxi(
		1,
		floori((available_width + MOVE_GRID_GAP) / (MIN_MOVE_BUTTON_WIDTH + MOVE_GRID_GAP)),
	)
	var maximum_rows := maxi(
		1,
		floori((available_height + MOVE_GRID_GAP) / (MOVE_BUTTON_HEIGHT + MOVE_GRID_GAP)),
	)
	var columns_needed_to_fit := ceili(
		float(_visible_move_count) / float(maximum_rows)
	) if _visible_move_count > 0 else 1
	_move_grid.columns = clampi(
		maxi(preferred_columns, columns_needed_to_fit),
		1,
		mini(maximum_columns, maxi(1, _visible_move_count)),
	)


func _format_move_type(move_type: int) -> String:
	for key in MoveResource.MoveType:
		if int(MoveResource.MoveType[key]) == move_type:
			return str(key).replace("_", " ").to_lower().capitalize()
	return "Moves"


func _position_label(position: int) -> String:
	for key in WrestlerResource.Position:
		if int(WrestlerResource.Position[key]) == position:
			if key == "NONE":
				return "Not Set"
			if key == "IN_CORNER":
				return "Corner"
			return str(key).replace("_", " ").to_lower().capitalize()
	return "Unknown"


func _state_label(wrestler: WrestlerResource) -> String:
	if wrestler == null:
		return "Not Set"
	return "%s %s · %s · %s" % [
		_position_label(wrestler.position),
		_enum_label(WrestlerResource.Orientation, wrestler.orientation),
		_enum_label(WrestlerResource.Area, wrestler.area),
		_enum_label(WrestlerResource.MotionState, wrestler.motion_state),
	]


func _resource_state_key(wrestler: WrestlerResource) -> String:
	if wrestler == null:
		return ""
	return "%d:%d:%d:%d" % [wrestler.position, wrestler.orientation, wrestler.area, wrestler.motion_state]


func _enum_label(values: Dictionary, value: int) -> String:
	for key in values:
		if int(values[key]) == value:
			return str(key).replace("_", " ").to_lower().capitalize()
	return "Unknown"


func _move_name(move: MoveResource) -> String:
	var display_name := move.move_name.strip_edges()
	return "Unnamed Move" if display_name.is_empty() else display_name
