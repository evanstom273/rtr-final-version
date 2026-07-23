extends Control
class_name MatchSetupPopup

signal match_requested(player: WrestlerResource, opponent: WrestlerResource, setup_metadata: Dictionary)
signal cancelled

const PROMOTIONS_DIRECTORY := "res://Promotions"
const FACE_COLOR := AppThemePalette.FACE
const HEEL_COLOR := AppThemePalette.HEEL
const CHAMPION_COLOR := AppThemePalette.PRESTIGE
const TEXT_COLOR := AppThemePalette.PRIMARY_TEXT
const MUTED_COLOR := AppThemePalette.SECONDARY_TEXT
const DRAG_HOLD_SECONDS := 0.32
const SCROLL_DISTANCE_THRESHOLD := 10.0

enum SortMode {
	ALPHA_ASC,
	ALPHA_DESC,
	STRENGTH,
	SPEED,
	STAMINA,
	SKILL,
	STRIKING,
	CHARISMA,
	GLOBAL_POPULARITY,
	POP_NORTH_AMERICA,
	POP_SOUTH_AMERICA,
	POP_EUROPE,
	POP_ASIA,
	POP_AFRICA,
	POP_OCEANIA
}

var _roster: Array[WrestlerResource] = []
var _filtered_indices: Array[int] = []
var _player_filtered_indices: Array[int] = []
var _opponent_filtered_indices: Array[int] = []
var _team_a: Array[WrestlerResource] = []
var _team_b: Array[WrestlerResource] = []
var _selected_player: WrestlerResource
var _selected_opponent: WrestlerResource
var _champion_paths: Dictionary = {}
var _title_names_by_path: Dictionary = {}
var _promotion_initials_by_path: Dictionary = {}
var _promotion_names_by_path: Dictionary = {}
var _allow_cancel: bool = false
var _player_locked: bool = false
var _ai_locked: bool = false
var _launch_pending: bool = false
var _recent_wrestler_paths := PackedStringArray()
var _rng := RandomNumberGenerator.new()
var _pending_setup_method: String = "Manual"
var _player_randomly_selected: bool = false
var _ai_randomly_selected: bool = false
var _press_state: Dictionary = {}
var _dragging_wrestler: WrestlerResource
var _details_wrestler: WrestlerResource

@onready var _safe_area: MarginContainer = %SetupSafeArea
@onready var _outer_margin: MarginContainer = %SetupOuterMargin
@onready var _builder_row: BoxContainer = %BuilderRow
@onready var _buttons: BoxContainer = %SetupButtons
@onready var _random_buttons: BoxContainer = %RandomButtons
@onready var _filter_grid: GridContainer = %FilterGrid
@onready var _roster_search: LineEdit = %RosterSearch
@onready var _country_filter: OptionButton = %CountryFilter
@onready var _class_filter: OptionButton = %ClassFilter
@onready var _gender_filter: OptionButton = %GenderFilter
@onready var _promotion_filter: OptionButton = %PromotionFilter
@onready var _disposition_filter: OptionButton = %DispositionFilter
@onready var _champion_filter: OptionButton = %ChampionFilter
@onready var _sort_filter: OptionButton = %SortFilter
@onready var _roster_list: ItemList = %RosterList
@onready var _player_list: ItemList = %RosterList
@onready var _opponent_list: ItemList = %RosterList
@onready var _team_a_panel: PanelContainer = %TeamAPanel
@onready var _team_b_panel: PanelContainer = %TeamBPanel
@onready var _team_a_list: VBoxContainer = %TeamAList
@onready var _team_b_list: VBoxContainer = %TeamBList
@onready var _status: Label = %SetupStatus
@onready var _start_button: Button = %StartMatchButton
@onready var _cancel_button: Button = %CancelSetupButton
@onready var _player_lock: CheckButton = %PlayerLock
@onready var _ai_lock: CheckButton = %AILock
@onready var _random_match_button: Button = %RandomMatchButton
@onready var _random_player_button: Button = %RandomPlayerButton
@onready var _random_ai_button: Button = %RandomAIButton
@onready var _rules_row: BoxContainer = %RulesRow
@onready var _dq_enabled: CheckButton = %DQEnabled
@onready var _count_outs_enabled: CheckButton = %CountOutsEnabled
@onready var _count_limit: SpinBox = %CountLimit
@onready var _action_clock_step: OptionButton = %ActionClockStep
@onready var _rules_summary: Label = %RulesSummary
@onready var _drag_preview: PanelContainer = %DragPreview
@onready var _drag_preview_label: Label = %DragPreviewLabel
@onready var _details_dimmer: ColorRect = %DetailsDimmer
@onready var _details_panel: PanelContainer = %DetailsPanel
@onready var _details_title: Label = %DetailsTitle
@onready var _details_close_button: Button = %DetailsCloseButton
@onready var _details_text: RichTextLabel = %DetailsText
@onready var _details_scroll: ScrollContainer = %DetailsScroll


func _ready() -> void:
	_rng.randomize()
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_populate_static_filters()
	_roster_search.text_changed.connect(_on_filter_changed)
	for filter in [_country_filter, _class_filter, _gender_filter, _promotion_filter, _disposition_filter, _champion_filter, _sort_filter]:
		filter.item_selected.connect(_on_filter_selected)
	_roster_list.gui_input.connect(_on_roster_list_gui_input)
	_roster_list.item_activated.connect(_on_roster_item_activated)
	_start_button.pressed.connect(_on_start_pressed)
	_player_lock.toggled.connect(_on_player_lock_toggled)
	_ai_lock.toggled.connect(_on_ai_lock_toggled)
	_random_match_button.pressed.connect(_on_random_match_pressed)
	_random_player_button.pressed.connect(_on_random_player_pressed)
	_random_ai_button.pressed.connect(_on_random_ai_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_dq_enabled.toggled.connect(_on_rules_changed)
	_count_outs_enabled.toggled.connect(_on_rules_changed)
	_count_limit.value_changed.connect(_on_count_limit_changed)
	_configure_action_clock_steps()
	_action_clock_step.item_selected.connect(_on_action_clock_step_changed)
	_details_close_button.pressed.connect(_close_details)
	_details_dimmer.gui_input.connect(_on_details_dimmer_input)
	_refresh_rules_summary()
	set_process(false)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var portrait_phone := mode == ResponsiveUI.LayoutMode.PHONE and effective_size.y > effective_size.x
	_builder_row.vertical = portrait_phone
	_buttons.vertical = portrait_phone
	_random_buttons.vertical = portrait_phone
	_rules_row.vertical = portrait_phone
	var columns := 1 if portrait_phone else int(ResponsiveUI.choose(2, 3, 3))
	_filter_grid.columns = columns
	var horizontal_margin := int(ResponsiveUI.choose(10, 20, 34))
	var vertical_margin := horizontal_margin
	_outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	_outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	_builder_row.add_theme_constant_override("separation", int(ResponsiveUI.choose(10, 14, 18)))
	_buttons.add_theme_constant_override("separation", int(ResponsiveUI.choose(8, 12, 14)))
	_random_buttons.add_theme_constant_override("separation", int(ResponsiveUI.choose(8, 12, 14)))
	# The complete builder chrome is tall. Keep its only scrollable region
	# bounded so the outer smoked-glass panel can honour both vertical gutters
	# instead of overflowing through them.
	var list_height := 180.0 if portrait_phone else minf(float(ResponsiveUI.choose(250, 300, 330)), clampf(effective_size.y * 0.34, 220.0, 360.0))
	_roster_list.custom_minimum_size.y = list_height
	var team_width := 0.0 if portrait_phone else float(ResponsiveUI.choose(330, 390, 430))
	_team_a_panel.custom_minimum_size.x = team_width
	_team_b_panel.custom_minimum_size.x = team_width
	var details_width := clampf(effective_size.x - float(horizontal_margin * 4), 420.0, 740.0)
	var details_height := clampf(effective_size.y - float(vertical_margin * 4), 360.0, 640.0)
	_details_panel.custom_minimum_size = Vector2(details_width, details_height)
	_details_panel.offset_left = -details_width * 0.5
	_details_panel.offset_right = details_width * 0.5
	_details_panel.offset_top = -details_height * 0.5
	_details_panel.offset_bottom = details_height * 0.5


func open_setup(
	roster: Array[WrestlerResource],
	_current_player: WrestlerResource = null,
	_current_opponent: WrestlerResource = null,
	allow_cancel: bool = false,
	recent_wrestler_paths: PackedStringArray = PackedStringArray(),
) -> void:
	_roster = roster.duplicate()
	_sort_roster_alphabetically()
	_load_promotion_and_title_data()
	_populate_dynamic_filters()
	_team_a.clear()
	_team_b.clear()
	_sync_legacy_selection_fields()
	_allow_cancel = allow_cancel
	_recent_wrestler_paths = recent_wrestler_paths.duplicate()
	_launch_pending = false
	_pending_setup_method = "Manual"
	_player_randomly_selected = false
	_ai_randomly_selected = false
	_cancel_button.visible = allow_cancel
	_cancel_button.text = "BACK TO MAIN MENU" if allow_cancel else "CANCEL"
	_roster_search.clear()
	_reset_filter_selections()
	_set_status("")
	_refresh_roster_list()
	_refresh_team_cards()
	_refresh_selection_state()
	_apply_lock_state()
	_close_details()
	_cancel_drag()
	visible = true
	_roster_search.grab_focus()


func close_setup() -> void:
	visible = false
	_launch_pending = false
	_cancel_drag()
	_close_details()


func confirm_launch() -> void:
	if not _launch_pending:
		return
	_launch_pending = false
	visible = false
	_cancel_drag()
	_close_details()


func reject_launch(message: String) -> void:
	_launch_pending = false
	_set_status(message, &"error")
	_refresh_selection_state(false)
	_apply_lock_state()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _details_panel.visible:
		_close_details()
	elif _allow_cancel:
		_on_cancel_pressed()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _dragging_wrestler != null:
		_update_drag_preview(_current_pointer_position())
		return
	if _press_state.is_empty():
		set_process(false)
		return
	if bool(_press_state.get("scrolled", false)):
		return
	var elapsed := Time.get_ticks_msec() - int(_press_state.get("started_msec", 0))
	if elapsed >= int(DRAG_HOLD_SECONDS * 1000.0):
		_begin_drag(int(_press_state.get("item_index", -1)), _current_pointer_position())


func _populate_static_filters() -> void:
	_class_filter.clear()
	_class_filter.add_item("All Classes", -1)
	for key in WrestlerResource.WrestlerClass:
		_class_filter.add_item(_pretty_enum_key(str(key)), int(WrestlerResource.WrestlerClass[key]))
	_gender_filter.clear()
	_gender_filter.add_item("All Genders", -1)
	_gender_filter.add_item("Male", WrestlerResource.WrestlerGender.MALE)
	_gender_filter.add_item("Female", WrestlerResource.WrestlerGender.FEMALE)
	_disposition_filter.clear()
	_disposition_filter.add_item("Face or Heel", -1)
	_disposition_filter.add_item("Face", WrestlerResource.WrestlerDisposition.FACE)
	_disposition_filter.add_item("Heel", WrestlerResource.WrestlerDisposition.HEEL)
	_sort_filter.clear()
	var sort_items: Array[Dictionary] = [
		{"label": "Sort: Alphabetical A-Z", "id": SortMode.ALPHA_ASC},
		{"label": "Sort: Alphabetical Z-A", "id": SortMode.ALPHA_DESC},
		{"label": "Sort: Strength", "id": SortMode.STRENGTH},
		{"label": "Sort: Speed", "id": SortMode.SPEED},
		{"label": "Sort: Stamina", "id": SortMode.STAMINA},
		{"label": "Sort: Skill", "id": SortMode.SKILL},
		{"label": "Sort: Striking", "id": SortMode.STRIKING},
		{"label": "Sort: Charisma", "id": SortMode.CHARISMA},
		{"label": "Sort: Global Popularity", "id": SortMode.GLOBAL_POPULARITY},
		{"label": "Sort: North America Pop.", "id": SortMode.POP_NORTH_AMERICA},
		{"label": "Sort: South America Pop.", "id": SortMode.POP_SOUTH_AMERICA},
		{"label": "Sort: Europe Pop.", "id": SortMode.POP_EUROPE},
		{"label": "Sort: Asia Pop.", "id": SortMode.POP_ASIA},
		{"label": "Sort: Africa Pop.", "id": SortMode.POP_AFRICA},
		{"label": "Sort: Oceania Pop.", "id": SortMode.POP_OCEANIA},
	]
	for item in sort_items:
		_sort_filter.add_item(str(item.get("label", "Sort")), int(item.get("id", SortMode.ALPHA_ASC)))


func _populate_dynamic_filters() -> void:
	_country_filter.clear()
	_country_filter.add_item("All Countries")
	var countries: Array[String] = []
	for wrestler in _roster:
		var country := _country_filter_label(wrestler)
		if not country.is_empty() and country not in countries:
			countries.append(country)
	countries.sort_custom(func(left: String, right: String) -> bool:
		return left.nocasecmp_to(right) < 0
	)
	for country in countries:
		var item_index: int = _country_filter.item_count
		_country_filter.add_item(country)
		_country_filter.set_item_metadata(item_index, country)
	_promotion_filter.clear()
	_promotion_filter.add_item("All Promotions")
	var promotions: Array[String] = []
	for value in _promotion_initials_by_path.values():
		var initials: String = str(value)
		if not initials.is_empty() and initials not in promotions:
			promotions.append(initials)
	promotions.sort_custom(func(left: String, right: String) -> bool:
		return left.nocasecmp_to(right) < 0
	)
	for initials in promotions:
		var item_index: int = _promotion_filter.item_count
		_promotion_filter.add_item(initials)
		_promotion_filter.set_item_metadata(item_index, initials)
	_champion_filter.clear()
	_champion_filter.add_item("All Title Status")
	_champion_filter.set_item_metadata(0, "ALL")
	_champion_filter.add_item("Champions Only")
	_champion_filter.set_item_metadata(1, "CHAMPIONS")
	_champion_filter.add_item("Non-Champions")
	_champion_filter.set_item_metadata(2, "NON_CHAMPIONS")
	var title_names: Array[String] = []
	for value in _title_names_by_path.values():
		for title_name in value:
			var title: String = str(title_name)
			if not title.is_empty() and title not in title_names:
				title_names.append(title)
	title_names.sort_custom(func(left: String, right: String) -> bool:
		return left.nocasecmp_to(right) < 0
	)
	for title in title_names:
		var item_index: int = _champion_filter.item_count
		_champion_filter.add_item(title)
		_champion_filter.set_item_metadata(item_index, "TITLE:%s" % title)


func _reset_filter_selections() -> void:
	for filter in [_country_filter, _class_filter, _gender_filter, _promotion_filter, _disposition_filter, _champion_filter, _sort_filter]:
		if filter.item_count > 0:
			filter.select(0)


func _on_filter_changed(_value: String) -> void:
	_refresh_roster_list()


func _on_filter_selected(_index: int) -> void:
	_refresh_roster_list()


func _refresh_roster_list() -> void:
	_roster_list.clear()
	_filtered_indices = _filtered_roster_indices()
	_sort_filtered_indices()
	_player_filtered_indices = _filtered_indices.duplicate()
	_opponent_filtered_indices = _filtered_indices.duplicate()
	for roster_index in _filtered_indices:
		var wrestler: WrestlerResource = _roster[roster_index]
		var item_index: int = _roster_list.add_item(_roster_item_text(wrestler))
		_roster_list.set_item_metadata(item_index, roster_index)
		_roster_list.set_item_custom_fg_color(item_index, _name_color(wrestler))
		if _assigned_anywhere(wrestler):
			_roster_list.set_item_tooltip(item_index, "Already assigned. Remove from a team before assigning again.")
	if _filtered_indices.is_empty():
		var empty_index: int = _roster_list.add_item("No wrestlers match these filters")
		_roster_list.set_item_disabled(empty_index, true)
	_refresh_selection_state(false)


func _filtered_roster_indices() -> Array[int]:
	var results: Array[int] = []
	var normalized_search: String = _roster_search.text.strip_edges().to_lower()
	var country_filter: String = _selected_metadata_string(_country_filter)
	var class_id: int = _selected_id_or_all(_class_filter)
	var gender_id: int = _selected_id_or_all(_gender_filter)
	var promotion_filter: String = _selected_metadata_string(_promotion_filter)
	var disposition_id: int = _selected_id_or_all(_disposition_filter)
	var champion_filter: String = _selected_metadata_string(_champion_filter)
	for roster_index in _roster.size():
		var wrestler: WrestlerResource = _roster[roster_index]
		if wrestler == null:
			continue
		if _assigned_anywhere(wrestler):
			continue
		if not country_filter.is_empty() and _country_filter_label(wrestler) != country_filter:
			continue
		if class_id >= 0 and class_id not in wrestler.wrestler_class:
			continue
		if gender_id >= 0 and int(wrestler.wrestler_gender) != gender_id:
			continue
		if not promotion_filter.is_empty() and _promotion_initials_for(wrestler) != promotion_filter:
			continue
		if disposition_id >= 0 and int(wrestler.wrestler_disposition) != disposition_id:
			continue
		if not _passes_champion_filter(wrestler, champion_filter):
			continue
		if not normalized_search.is_empty() and not _searchable_text(wrestler).contains(normalized_search):
			continue
		results.append(roster_index)
	return results


func _sort_filtered_indices() -> void:
	var sort_id: int = _sort_filter.get_selected_id()
	_filtered_indices.sort_custom(func(left_index: int, right_index: int) -> bool:
		var left: WrestlerResource = _roster[left_index]
		var right: WrestlerResource = _roster[right_index]
		if sort_id == SortMode.ALPHA_DESC:
			return _display_name(left).naturalnocasecmp_to(_display_name(right)) > 0
		if sort_id == SortMode.ALPHA_ASC:
			return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0
		var left_value: float = _sort_value(left, sort_id)
		var right_value: float = _sort_value(right, sort_id)
		if not is_equal_approx(left_value, right_value):
			return left_value > right_value
		return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0
	)


func _sort_value(wrestler: WrestlerResource, sort_id: int) -> float:
	match sort_id:
		SortMode.STRENGTH:
			return wrestler.strength
		SortMode.SPEED:
			return wrestler.speed
		SortMode.STAMINA:
			return wrestler.stamina
		SortMode.SKILL:
			return wrestler.skill
		SortMode.STRIKING:
			return wrestler.striking
		SortMode.CHARISMA:
			return wrestler.charisma
		SortMode.GLOBAL_POPULARITY:
			return wrestler.global_popularity
		SortMode.POP_NORTH_AMERICA:
			return wrestler.pop_north_america
		SortMode.POP_SOUTH_AMERICA:
			return wrestler.pop_south_america
		SortMode.POP_EUROPE:
			return wrestler.pop_europe
		SortMode.POP_ASIA:
			return wrestler.pop_asia
		SortMode.POP_AFRICA:
			return wrestler.pop_africa
		SortMode.POP_OCEANIA:
			return wrestler.pop_oceania
	return 0.0


func _on_roster_list_gui_input(event: InputEvent, _legacy_list: ItemList = null) -> void:
	if _launch_pending:
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_start_press(mouse.position, _roster_list.get_global_mouse_position(), -1)
		else:
			_finish_press(_roster_list.get_global_mouse_position())
		_roster_list.accept_event()
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_update_press_motion(motion.position, _roster_list.get_global_mouse_position())
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		var global_pos: Vector2 = _roster_list.get_global_transform() * touch.position
		if touch.pressed:
			_start_press(touch.position, global_pos, touch.index)
		else:
			_finish_press(global_pos)
		_roster_list.accept_event()
		return
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		var global_pos: Vector2 = _roster_list.get_global_transform() * drag.position
		_update_press_motion(drag.position, global_pos)
		_roster_list.accept_event()


func _start_press(local_position: Vector2, global_position: Vector2, touch_index: int) -> void:
	var item_index: int = _roster_list.get_item_at_position(local_position, true)
	if item_index < 0 or item_index >= _roster_list.item_count or _roster_list.is_item_disabled(item_index):
		return
	_press_state = {
		"item_index": item_index,
		"local_start": local_position,
		"global_position": global_position,
		"touch_index": touch_index,
		"started_msec": Time.get_ticks_msec(),
		"scrolled": false,
		"distance": 0.0,
	}
	set_process(true)


func _update_press_motion(local_position: Vector2, global_position: Vector2) -> void:
	if _dragging_wrestler != null:
		_update_drag_preview(global_position)
		return
	if _press_state.is_empty():
		return
	var local_start: Vector2 = _press_state.get("local_start", local_position)
	var distance: float = local_start.distance_to(local_position)
	_press_state["distance"] = distance
	_press_state["global_position"] = global_position
	if distance >= SCROLL_DISTANCE_THRESHOLD:
		_press_state["scrolled"] = true
		var scroll_bar: VScrollBar = _roster_list.get_v_scroll_bar()
		if scroll_bar != null:
			scroll_bar.value -= local_position.y - local_start.y
		_press_state["local_start"] = local_position


func _finish_press(global_position: Vector2) -> void:
	if _dragging_wrestler != null:
		_drop_drag(global_position)
		return
	if _press_state.is_empty():
		return
	var item_index: int = int(_press_state.get("item_index", -1))
	var scrolled: bool = bool(_press_state.get("scrolled", false))
	_press_state.clear()
	set_process(false)
	if scrolled:
		return
	_open_details_for_item(item_index)


func _begin_drag(item_index: int, global_position: Vector2) -> void:
	if item_index < 0 or item_index >= _roster_list.item_count or _roster_list.is_item_disabled(item_index):
		_press_state.clear()
		set_process(false)
		return
	var roster_index: int = int(_roster_list.get_item_metadata(item_index))
	if roster_index < 0 or roster_index >= _roster.size():
		return
	_dragging_wrestler = _roster[roster_index]
	_drag_preview_label.text = _formatted_roster_name(_dragging_wrestler)
	_drag_preview.visible = true
	_update_drag_preview(global_position)


func _drop_drag(global_position: Vector2) -> void:
	var wrestler: WrestlerResource = _dragging_wrestler
	_cancel_drag()
	if wrestler == null:
		return
	if _team_a_panel.get_global_rect().has_point(global_position):
		_assign_to_team(wrestler, true)
	elif _team_b_panel.get_global_rect().has_point(global_position):
		_assign_to_team(wrestler, false)
	else:
		_set_status("Drop %s onto Team A or Team B." % _display_name(wrestler), &"warning")


func _cancel_drag() -> void:
	_press_state.clear()
	_dragging_wrestler = null
	if is_node_ready():
		_drag_preview.visible = false
		_team_a_panel.remove_theme_stylebox_override("panel")
		_team_b_panel.remove_theme_stylebox_override("panel")
		_team_a_panel.modulate = Color(1.0, 1.0, 1.0, 0.62 if _player_locked else 1.0)
		_team_b_panel.modulate = Color(1.0, 1.0, 1.0, 0.62 if _ai_locked else 1.0)
	set_process(false)


func _update_drag_preview(global_position: Vector2) -> void:
	_drag_preview.global_position = global_position + Vector2(14, 14)
	var on_a: bool = _team_a_panel.get_global_rect().has_point(global_position)
	var on_b: bool = _team_b_panel.get_global_rect().has_point(global_position)
	_set_drop_target_style(_team_a_panel, on_a)
	_set_drop_target_style(_team_b_panel, on_b)
	_team_a_panel.modulate = Color(1.0, 1.0, 1.0, 0.62 if _player_locked else 1.0)
	_team_b_panel.modulate = Color(1.0, 1.0, 1.0, 0.62 if _ai_locked else 1.0)


func _set_drop_target_style(panel: PanelContainer, active: bool) -> void:
	if active:
		panel.add_theme_stylebox_override("panel", AppThemePalette.make_control_style(&"focus", &"active"))
	else:
		panel.remove_theme_stylebox_override("panel")


func _current_pointer_position() -> Vector2:
	if _press_state.has("global_position"):
		return _press_state["global_position"]
	return get_global_mouse_position()


func _on_roster_item_activated(item_index: int) -> void:
	_open_details_for_item(item_index)


func _open_details_for_item(item_index: int) -> void:
	if item_index < 0 or item_index >= _roster_list.item_count or _roster_list.is_item_disabled(item_index):
		return
	var roster_index: int = int(_roster_list.get_item_metadata(item_index))
	if roster_index < 0 or roster_index >= _roster.size():
		return
	_open_details(_roster[roster_index])


func _open_details(wrestler: WrestlerResource) -> void:
	if wrestler == null:
		return
	_details_wrestler = wrestler
	_details_title.text = _formatted_roster_name(wrestler)
	_details_title.add_theme_color_override("font_color", _name_color(wrestler))
	_details_text.text = _details_bbcode(wrestler)
	_details_scroll.scroll_vertical = 0
	_details_dimmer.visible = true
	_details_panel.visible = true


func _close_details() -> void:
	if not is_node_ready():
		return
	_details_wrestler = null
	_details_dimmer.visible = false
	_details_panel.visible = false


func _on_details_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_details()
		_details_dimmer.accept_event()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_close_details()
		_details_dimmer.accept_event()


func _assign_to_team(wrestler: WrestlerResource, team_a: bool) -> void:
	if wrestler == null:
		return
	if _assigned_anywhere(wrestler):
		_set_status("%s is already assigned. Remove them before placing them on another team." % _display_name(wrestler), &"warning")
		return
	if team_a:
		if _player_locked:
			_set_status("Team A is locked.", &"warning")
			return
		_team_a.append(wrestler)
		_player_randomly_selected = false
	else:
		if _ai_locked:
			_set_status("Team B is locked.", &"warning")
			return
		_team_b.append(wrestler)
		_ai_randomly_selected = false
	_update_pending_setup_method()
	_sync_legacy_selection_fields()
	_refresh_team_cards()
	_refresh_roster_list()
	_refresh_selection_state()


func _refresh_team_cards() -> void:
	_build_team_list(_team_a_list, _team_a, true)
	_build_team_list(_team_b_list, _team_b, false)


func _build_team_list(container: VBoxContainer, team: Array[WrestlerResource], team_a: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	if team.is_empty():
		var empty: Label = Label.new()
		empty.text = "Drop wrestlers here"
		empty.add_theme_color_override("font_color", MUTED_COLOR)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 80)
		container.add_child(empty)
		return
	for index in team.size():
		container.add_child(_make_team_member_row(team[index], index, team_a))


func _make_team_member_row(wrestler: WrestlerResource, index: int, team_a: bool) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style(_name_color(wrestler), index == 0))
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	var label: Label = Label.new()
	label.text = "%d. %s" % [index + 1, _formatted_roster_name(wrestler)]
	label.tooltip_text = _team_tooltip(wrestler)
	label.add_theme_color_override("font_color", _name_color(wrestler))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var up_button: Button = _small_team_button("UP")
	up_button.disabled = index <= 0 or _team_locked(team_a)
	up_button.pressed.connect(_move_team_member.bind(team_a, index, -1))
	row.add_child(up_button)
	var down_button: Button = _small_team_button("DOWN")
	var team_size: int = _team_a.size()
	if not team_a:
		team_size = _team_b.size()
	down_button.disabled = index >= team_size - 1 or _team_locked(team_a)
	down_button.pressed.connect(_move_team_member.bind(team_a, index, 1))
	row.add_child(down_button)
	var remove_button: Button = _small_team_button("X")
	remove_button.disabled = _team_locked(team_a)
	remove_button.pressed.connect(_remove_team_member.bind(team_a, index))
	row.add_child(remove_button)
	return panel


func _small_team_button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(48, 34)
	button.focus_mode = Control.FOCUS_NONE
	if text_value == "X":
		AppThemePalette.apply_button_semantic(button, &"destructive")
	return button


func _move_team_member(team_a: bool, index: int, direction: int) -> void:
	var team: Array[WrestlerResource] = []
	if team_a:
		team = _team_a.duplicate()
	else:
		team = _team_b.duplicate()
	var target_index: int = index + direction
	if index < 0 or index >= team.size() or target_index < 0 or target_index >= team.size():
		return
	var wrestler: WrestlerResource = team[index]
	team.remove_at(index)
	team.insert(target_index, wrestler)
	if team_a:
		_team_a = team
	else:
		_team_b = team
	_sync_legacy_selection_fields()
	_refresh_team_cards()
	_refresh_selection_state()


func _remove_team_member(team_a: bool, index: int) -> void:
	var team: Array[WrestlerResource] = []
	if team_a:
		team = _team_a.duplicate()
	else:
		team = _team_b.duplicate()
	if index < 0 or index >= team.size():
		return
	var wrestler: WrestlerResource = team[index]
	team.remove_at(index)
	if team_a:
		_team_a = team
		_player_randomly_selected = false
	else:
		_team_b = team
		_ai_randomly_selected = false
	_update_pending_setup_method()
	_sync_legacy_selection_fields()
	_refresh_team_cards()
	_refresh_roster_list()
	_refresh_selection_state()
	_set_status("Removed %s." % _display_name(wrestler), &"success")


func _row_style(accent: Color, active_starter: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = AppThemePalette.SECONDARY_PANEL
	style.border_width_left = 2 if active_starter else 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = accent if active_starter else AppThemePalette.BORDER
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _refresh_selection_state(update_status: bool = true) -> void:
	var reason: String = _launch_block_reason()
	_start_button.disabled = not reason.is_empty() or _launch_pending
	_random_match_button.disabled = _launch_pending or _roster.size() < 2
	_random_player_button.disabled = _launch_pending or _player_locked or _filtered_indices.is_empty()
	_random_ai_button.disabled = _launch_pending or _ai_locked or _filtered_indices.is_empty()
	if not update_status:
		return
	if _roster.size() < 2:
		_set_status("At least two wrestlers are required to start a match.", &"error")
	elif not reason.is_empty():
		_set_status(reason, &"warning")
	else:
		_set_status("Ready: %s vs. %s" % [_display_name(_team_a[0]), _display_name(_team_b[0])], &"success")


func _launch_block_reason() -> String:
	if _team_a.is_empty():
		return "Team A needs one wrestler."
	if _team_b.is_empty():
		return "Team B needs one wrestler."
	if _team_a.size() > 1 or _team_b.size() > 1:
		return "Team cards are future-ready, but this match type currently starts only with one wrestler per team."
	if _same_wrestler(_team_a[0], _team_b[0]):
		return "Choose two different wrestlers."
	return ""


func _on_start_pressed() -> void:
	if _start_button.disabled:
		_refresh_selection_state()
		return
	var method: String = _pending_setup_method
	if method == "Random Both" and (_player_locked or _ai_locked):
		method = "Random With Locks"
	_request_launch(
		_team_a[0],
		_team_b[0],
		method,
		_player_randomly_selected,
		_ai_randomly_selected,
	)


func _on_random_match_pressed() -> void:
	if _launch_pending:
		return
	if _player_locked and _ai_locked:
		_pending_setup_method = "Random With Locks"
		_refresh_selection_state()
		return
	var pair: Dictionary = _choose_random_pair(_player_locked, _ai_locked)
	if pair.is_empty():
		_set_status("No valid matchup exists within the active filters and locks.", &"warning")
		return
	var random_player: WrestlerResource = pair.get("player", null) as WrestlerResource
	var random_opponent: WrestlerResource = pair.get("opponent", null) as WrestlerResource
	if not _player_locked:
		_team_a.clear()
		_team_a.append(random_player)
		_player_randomly_selected = true
	if not _ai_locked:
		_team_b.clear()
		_team_b.append(random_opponent)
		_ai_randomly_selected = true
	_sync_legacy_selection_fields()
	_pending_setup_method = "Random With Locks" if _player_locked or _ai_locked else "Random Both"
	_refresh_after_team_change()
	_set_status("Random preview: %s vs. %s. Press START MATCH to continue or adjust either team." % [
		_display_name(_team_a[0]),
		_display_name(_team_b[0]),
	], &"success")


func _on_random_player_pressed() -> void:
	if _launch_pending or _player_locked:
		return
	var wrestler: WrestlerResource = _choose_random_side(_filtered_indices, _team_first(_team_b))
	if wrestler == null:
		_set_status("No filtered Team A wrestler can face the current Team B wrestler.", &"warning")
		return
	_team_a.clear()
	_team_a.append(wrestler)
	_player_randomly_selected = true
	_sync_legacy_selection_fields()
	_update_pending_setup_method()
	_refresh_after_team_change()
	_set_status("Random Team A selected: %s. Press START MATCH when ready." % _display_name(wrestler), &"success")


func _on_random_ai_pressed() -> void:
	if _launch_pending or _ai_locked:
		return
	var wrestler: WrestlerResource = _choose_random_side(_filtered_indices, _team_first(_team_a))
	if wrestler == null:
		_set_status("No filtered Team B wrestler can face the current Team A wrestler.", &"warning")
		return
	_team_b.clear()
	_team_b.append(wrestler)
	_ai_randomly_selected = true
	_sync_legacy_selection_fields()
	_update_pending_setup_method()
	_refresh_after_team_change()
	_set_status("Random Team B selected: %s. Press START MATCH when ready." % _display_name(wrestler), &"success")


func _refresh_after_team_change() -> void:
	_refresh_team_cards()
	_refresh_roster_list()
	_refresh_selection_state()
	_apply_lock_state()


func _update_pending_setup_method() -> void:
	if _player_randomly_selected and _ai_randomly_selected:
		_pending_setup_method = "Random With Locks" if _player_locked or _ai_locked else "Random Both"
	elif _player_randomly_selected:
		_pending_setup_method = "Random Player"
	elif _ai_randomly_selected:
		_pending_setup_method = "Random AI"
	else:
		_pending_setup_method = "Manual"


func _request_launch(
	player: WrestlerResource,
	opponent: WrestlerResource,
	method: String,
	player_random: bool,
	ai_random: bool,
) -> void:
	if _launch_pending:
		return
	var reason: String = _launch_block_reason()
	if not reason.is_empty():
		_set_status(reason, &"warning")
		return
	_launch_pending = true
	_set_status("Starting %s vs. %s..." % [_display_name(player), _display_name(opponent)], &"success")
	_apply_lock_state()
	match_requested.emit(player, opponent, {
		"match_setup": method,
		"player_locked": _player_locked,
		"ai_locked": _ai_locked,
		"player_randomly_selected": player_random,
		"ai_randomly_selected": ai_random,
		"team_builder_used": true,
		"team_a_paths": _team_paths(_team_a),
		"team_b_paths": _team_paths(_team_b),
		"match_rules": _selected_rules_dictionary(),
	})


func _on_player_lock_toggled(pressed: bool) -> void:
	_player_locked = pressed
	_update_pending_setup_method()
	_apply_lock_state()


func _on_ai_lock_toggled(pressed: bool) -> void:
	_ai_locked = pressed
	_update_pending_setup_method()
	_apply_lock_state()


func _apply_lock_state() -> void:
	_player_lock.button_pressed = _player_locked
	_ai_lock.button_pressed = _ai_locked
	_player_lock.disabled = _launch_pending
	_ai_lock.disabled = _launch_pending
	_cancel_button.disabled = _launch_pending
	_team_a_panel.modulate.a = 0.62 if _player_locked else 1.0
	_team_b_panel.modulate.a = 0.62 if _ai_locked else 1.0
	_refresh_team_cards()
	_refresh_selection_state(false)


func _on_cancel_pressed() -> void:
	if not _allow_cancel:
		return
	close_setup()
	cancelled.emit()


func _on_rules_changed(_enabled: bool) -> void:
	_count_limit.editable = _count_outs_enabled.button_pressed
	_refresh_rules_summary()


func _on_count_limit_changed(_value: float) -> void:
	_refresh_rules_summary()


func _on_action_clock_step_changed(_index: int) -> void:
	_refresh_rules_summary()


func _configure_action_clock_steps() -> void:
	_action_clock_step.clear()
	for seconds in MatchRules.ACTION_CLOCK_OPTIONS:
		_action_clock_step.add_item("%d SEC" % int(seconds), int(seconds))
		if int(seconds) == MatchRules.DEFAULT_ACTION_CLOCK_SECONDS:
			_action_clock_step.select(_action_clock_step.item_count - 1)


func _selected_rules_dictionary() -> Dictionary:
	return {
		"disqualifications_enabled": _dq_enabled.button_pressed,
		"count_outs_enabled": _count_outs_enabled.button_pressed,
		"count_out_limit": int(_count_limit.value),
		"action_clock_seconds": _action_clock_step.get_selected_id(),
		"weapons_enabled": true,
		"pinfall_enabled": true,
		"submission_enabled": true,
	}


func _refresh_rules_summary() -> void:
	if not is_node_ready():
		return
	var rules: MatchRules = MatchRules.from_dictionary(_selected_rules_dictionary())
	_rules_summary.text = rules.summary()


func _choose_random_pair(lock_player: bool, lock_ai: bool) -> Dictionary:
	var player_candidates: Array[WrestlerResource] = _candidate_wrestlers(_player_filtered_indices)
	var ai_candidates: Array[WrestlerResource] = _candidate_wrestlers(_opponent_filtered_indices)
	if lock_player:
		player_candidates.clear()
		var current_player: WrestlerResource = _team_first(_team_a)
		if _contains_wrestler(_selected_player):
			current_player = _selected_player
		if _contains_wrestler(current_player):
			player_candidates.append(current_player)
	if lock_ai:
		ai_candidates.clear()
		var current_ai: WrestlerResource = _team_first(_team_b)
		if _contains_wrestler(_selected_opponent):
			current_ai = _selected_opponent
		if _contains_wrestler(current_ai):
			ai_candidates.append(current_ai)
	var pairs: Array[Dictionary] = _viable_pairs(player_candidates, ai_candidates, true)
	if pairs.is_empty():
		pairs = _viable_pairs(player_candidates, ai_candidates, false)
	return {} if pairs.is_empty() else pairs[_rng.randi_range(0, pairs.size() - 1)]


func _choose_random_side(indices: Array[int], excluded: WrestlerResource) -> WrestlerResource:
	var candidates: Array[WrestlerResource] = _candidate_wrestlers(indices)
	var preferred: Array[WrestlerResource] = []
	for wrestler in candidates:
		if not _same_wrestler(wrestler, excluded) and not _was_recent(wrestler):
			preferred.append(wrestler)
	if preferred.is_empty():
		for wrestler in candidates:
			if not _same_wrestler(wrestler, excluded):
				preferred.append(wrestler)
	return null if preferred.is_empty() else preferred[_rng.randi_range(0, preferred.size() - 1)]


func _candidate_wrestlers(indices: Array[int]) -> Array[WrestlerResource]:
	var candidates: Array[WrestlerResource] = []
	for roster_index in indices:
		if roster_index < 0 or roster_index >= _roster.size():
			continue
		var wrestler: WrestlerResource = _roster[roster_index]
		if wrestler != null:
			candidates.append(wrestler)
	return candidates


func _viable_pairs(
	players: Array[WrestlerResource],
	opponents: Array[WrestlerResource],
	avoid_recent: bool,
) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for player in players:
		for opponent in opponents:
			if player == null or opponent == null or _same_wrestler(player, opponent):
				continue
			if avoid_recent and ((not _player_locked and _was_recent(player)) or (not _ai_locked and _was_recent(opponent))):
				continue
			pairs.append({"player": player, "opponent": opponent})
	return pairs


func _was_recent(wrestler: WrestlerResource) -> bool:
	return wrestler != null and not wrestler.resource_path.is_empty() and wrestler.resource_path in _recent_wrestler_paths


func _roster_item_text(wrestler: WrestlerResource) -> String:
	return _formatted_roster_name(wrestler)


func _details_bbcode(wrestler: WrestlerResource) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=%s][b]%s[/b][/color]" % [_color_hex(_name_color(wrestler)), _bb(_formatted_roster_name(wrestler))])
	lines.append("[color=%s]%s[/color]" % [_color_hex(MUTED_COLOR), _bb(_format_promotion(wrestler))])
	lines.append("")
	lines.append("[b]Identity[/b]")
	lines.append("Name: %s" % _bb(_display_name(wrestler)))
	lines.append("Gimmick: %s" % _bb(_format_gimmick(wrestler)))
	lines.append("Origin: %s" % _bb(_format_origin(wrestler)))
	lines.append("Gender: %s | Age: %d | Height: %s | Weight: %d lb" % [_format_gender(wrestler), wrestler.Age, _bb(wrestler.wrestler_height), wrestler.wrestler_weight])
	lines.append("Disposition: %s | Classes: %s" % [_format_disposition(wrestler), _bb(_format_classes(wrestler.wrestler_class))])
	var current_titles: String = _bb(_current_titles(wrestler))
	if _is_champion(wrestler):
		current_titles = "[color=%s]%s[/color]" % [_color_hex(CHAMPION_COLOR), current_titles]
	lines.append("Champion Status: %s" % current_titles)
	lines.append("")
	lines.append("[b]Attributes[/b]")
	lines.append("Strength %s | Speed %s | Stamina %s" % [_percent(wrestler.strength), _percent(wrestler.speed), _percent(wrestler.stamina)])
	lines.append("Skill %s | Striking %s | Charisma %s" % [_percent(wrestler.skill), _percent(wrestler.striking), _percent(wrestler.charisma)])
	lines.append("")
	lines.append("[b]Popularity[/b]")
	lines.append("Global %s | North America %s | South America %s" % [_percent(wrestler.global_popularity), _percent(wrestler.pop_north_america), _percent(wrestler.pop_south_america)])
	lines.append("Europe %s | Asia %s | Africa %s | Oceania %s" % [_percent(wrestler.pop_europe), _percent(wrestler.pop_asia), _percent(wrestler.pop_africa), _percent(wrestler.pop_oceania)])
	lines.append("")
	lines.append("[b]Moves[/b]")
	lines.append("Signatures: %s" % _bb(_format_signatures(wrestler)))
	lines.append("Finishers: %s" % _bb(_format_finishers(wrestler)))
	return "\n".join(lines)


func _team_tooltip(wrestler: WrestlerResource) -> String:
	return "%s\n%s\n%s\nSignatures: %s\nFinishers: %s" % [
		_display_name(wrestler),
		_format_origin(wrestler),
		_format_promotion(wrestler),
		_format_signatures(wrestler),
		_format_finishers(wrestler),
	]


func _searchable_text(wrestler: WrestlerResource) -> String:
	return " ".join([
		_display_name(wrestler),
		wrestler.gimmick_name,
		wrestler.gimmick_description,
		_format_classes(wrestler.wrestler_class),
		_format_origin(wrestler),
		_country_search_terms(wrestler),
		_format_disposition(wrestler),
		_disposition_search_terms(wrestler),
		_format_promotion(wrestler),
		_current_titles(wrestler),
		_format_signatures(wrestler),
		_format_finishers(wrestler),
	]).to_lower()


func _formatted_roster_name(wrestler: WrestlerResource) -> String:
	var champion_prefix: String = "(c) " if _is_champion(wrestler) else ""
	var disposition_suffix: String = ""
	match int(wrestler.wrestler_disposition):
		WrestlerResource.WrestlerDisposition.FACE:
			disposition_suffix = " (f)"
		WrestlerResource.WrestlerDisposition.HEEL:
			disposition_suffix = " (h)"
	return "%s%s%s" % [champion_prefix, _display_name(wrestler), disposition_suffix]


func _name_color(wrestler: WrestlerResource) -> Color:
	return AppThemePalette.wrestler_color(wrestler, _is_champion(wrestler))


func _set_status(message: String, semantic := &"secondary") -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", AppThemePalette.semantic_text(semantic))


func _format_finishers(wrestler: WrestlerResource) -> String:
	var assigned: Array[MoveResource] = []
	assigned.append_array(wrestler.finisher_moves)
	if assigned.is_empty():
		for move in wrestler.move_set:
			if move != null and move.is_finisher:
				assigned.append(move)
	return _format_move_names(assigned)


func _format_signatures(wrestler: WrestlerResource) -> String:
	return _format_move_names(wrestler.signature_moves)


func _format_move_names(moves: Array[MoveResource]) -> String:
	var names: Array[String] = []
	for move in moves:
		if move != null:
			var move_name: String = move.move_name.strip_edges()
			if not move_name.is_empty() and move_name not in names:
				names.append(move_name)
	names.sort_custom(func(left: String, right: String) -> bool:
		return left.nocasecmp_to(right) < 0
	)
	return ", ".join(names) if not names.is_empty() else "None assigned"


func _format_gimmick(wrestler: WrestlerResource) -> String:
	var gimmick: String = wrestler.gimmick_name.strip_edges()
	if gimmick.is_empty():
		gimmick = "None"
	var description: String = wrestler.gimmick_description.strip_edges()
	if not description.is_empty():
		gimmick += " - %s" % description
	return gimmick


func _format_gender(wrestler: WrestlerResource) -> String:
	return _format_enum(WrestlerResource.WrestlerGender, int(wrestler.wrestler_gender), "Not Set")


func _format_disposition(wrestler: WrestlerResource) -> String:
	return _format_enum(WrestlerResource.WrestlerDisposition, int(wrestler.wrestler_disposition), "Not Set")


func _disposition_search_terms(wrestler: WrestlerResource) -> String:
	match int(wrestler.wrestler_disposition):
		WrestlerResource.WrestlerDisposition.FACE:
			return "face babyface f"
		WrestlerResource.WrestlerDisposition.HEEL:
			return "heel villain h"
	return ""


func _display_name(wrestler: WrestlerResource) -> String:
	if wrestler == null:
		return "Unassigned"
	var value: String = str(wrestler.wrestler_name).strip_edges()
	return wrestler.resource_path.get_file().get_basename().capitalize() if value.is_empty() else value


func _promotion_initials_for(wrestler: WrestlerResource) -> String:
	if wrestler == null:
		return ""
	return str(_promotion_initials_by_path.get(wrestler.resource_path, ""))


func _format_promotion(wrestler: WrestlerResource) -> String:
	var initials: String = _promotion_initials_for(wrestler)
	var promotion_name: String = str(_promotion_names_by_path.get(wrestler.resource_path, ""))
	if initials.is_empty():
		return "Independent / Not Assigned"
	return initials if promotion_name.is_empty() else "%s - %s" % [initials, promotion_name]


func _format_classes(classes: Array) -> String:
	if classes.is_empty():
		return "No Class"
	var names: Array[String] = []
	for wrestler_class in classes:
		names.append(_format_enum(WrestlerResource.WrestlerClass, int(wrestler_class), "Unknown"))
	return ", ".join(names)


func _format_origin(wrestler: WrestlerResource) -> String:
	var region: String = _format_enum(WrestlerResource.Region, int(wrestler.birthplace), "Not Set")
	var country: String = _country_display_name(wrestler)
	return region if country.is_empty() or country == "Other" else "%s, %s" % [country, region]


func _country_filter_label(wrestler: WrestlerResource) -> String:
	var country: String = _country_display_name(wrestler)
	if country == "UK":
		return "UK / England"
	return country


func _country_display_name(wrestler: WrestlerResource) -> String:
	match int(wrestler.birthplace):
		WrestlerResource.Region.NORTH_AMERICA:
			return _format_enum(WrestlerResource.NA_Countries, int(wrestler.north_american_country), "")
		WrestlerResource.Region.SOUTH_AMERICA:
			return _format_enum(WrestlerResource.SA_Countries, int(wrestler.south_american_country), "")
		WrestlerResource.Region.EUROPE:
			return _format_enum(WrestlerResource.Europe_Countries, int(wrestler.europe_country), "")
		WrestlerResource.Region.ASIA:
			return _format_enum(WrestlerResource.Asia_Countries, int(wrestler.asia_country), "")
		WrestlerResource.Region.AFRICA:
			return _format_enum(WrestlerResource.Africa_Countries, int(wrestler.africa_country), "")
		WrestlerResource.Region.OCEANIA:
			return _format_enum(WrestlerResource.Oceania_Countries, int(wrestler.oceania_country), "")
	return ""


func _country_search_terms(wrestler: WrestlerResource) -> String:
	if int(wrestler.birthplace) == WrestlerResource.Region.EUROPE and int(wrestler.europe_country) == WrestlerResource.Europe_Countries.UK:
		return "uk england britain british united kingdom"
	return _country_display_name(wrestler)


func _format_enum(values: Dictionary, value: int, fallback: String) -> String:
	for key in values:
		if int(values[key]) == value:
			return _pretty_enum_key(str(key))
	return fallback


func _pretty_enum_key(key: String) -> String:
	if key in ["USA", "UK"]:
		return key
	var words := key.to_lower().split("_")
	var result: Array[String] = []
	for word in words:
		result.append(word.capitalize())
	return " ".join(result)


func _percent(value: float) -> String:
	return "%d%%" % roundi(value)


func _current_titles(wrestler: WrestlerResource) -> String:
	var titles: PackedStringArray = _title_names_by_path.get(wrestler.resource_path, PackedStringArray())
	return ", ".join(titles) if not titles.is_empty() else "None"


func _passes_champion_filter(wrestler: WrestlerResource, filter_value: String) -> bool:
	if filter_value.is_empty() or filter_value == "ALL":
		return true
	if filter_value == "CHAMPIONS":
		return _is_champion(wrestler)
	if filter_value == "NON_CHAMPIONS":
		return not _is_champion(wrestler)
	if filter_value.begins_with("TITLE:"):
		var title: String = filter_value.substr(6)
		var titles: PackedStringArray = _title_names_by_path.get(wrestler.resource_path, PackedStringArray())
		return titles.has(title)
	return true


func _selected_metadata_string(filter: OptionButton) -> String:
	if filter.selected <= 0:
		return ""
	var value: Variant = filter.get_item_metadata(filter.selected)
	return "" if value == null else str(value)


func _selected_id_or_all(filter: OptionButton) -> int:
	return -1 if filter.selected <= 0 else filter.get_selected_id()


func _load_promotion_and_title_data() -> void:
	_champion_paths.clear()
	_title_names_by_path.clear()
	_promotion_initials_by_path.clear()
	_promotion_names_by_path.clear()
	var promotion_paths: Array[String] = []
	_collect_resource_paths(PROMOTIONS_DIRECTORY, promotion_paths)
	for path in promotion_paths:
		var resource: Resource = ResourceLoader.load(path)
		if not resource is PromotionResource:
			continue
		var promotion: PromotionResource = resource as PromotionResource
		var division: Array[WrestlerResource] = []
		division.append_array(promotion.mens_division)
		division.append_array(promotion.womens_division)
		for wrestler in division:
			if wrestler == null or wrestler.resource_path.is_empty():
				continue
			_promotion_initials_by_path[wrestler.resource_path] = promotion.promotion_initials.strip_edges()
			_promotion_names_by_path[wrestler.resource_path] = promotion.promotion_name.strip_edges()
		for title in promotion.titles:
			if title == null or title.current_holder_id <= 0:
				continue
			for wrestler in division:
				if wrestler == null or wrestler.resource_path.is_empty():
					continue
				if int(wrestler.wrestler_id) != int(title.current_holder_id):
					continue
				_champion_paths[wrestler.resource_path] = true
				var titles: PackedStringArray = _title_names_by_path.get(wrestler.resource_path, PackedStringArray())
				titles.append(title.title_name)
				_title_names_by_path[wrestler.resource_path] = titles


func _collect_resource_paths(directory_path: String, paths: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_resource_paths(directory_path.path_join(entry.trim_suffix("/")), paths)
		elif entry.get_extension().to_lower() == "tres":
			paths.append(directory_path.path_join(entry))


func _is_champion(wrestler: WrestlerResource) -> bool:
	return wrestler != null and not wrestler.resource_path.is_empty() and _champion_paths.has(wrestler.resource_path)


func _assigned_anywhere(wrestler: WrestlerResource) -> bool:
	return _team_contains(_team_a, wrestler) or _team_contains(_team_b, wrestler)


func _team_contains(team: Array[WrestlerResource], wrestler: WrestlerResource) -> bool:
	for member in team:
		if _same_wrestler(member, wrestler):
			return true
	return false


func _team_locked(team_a: bool) -> bool:
	return _player_locked if team_a else _ai_locked


func _team_first(team: Array[WrestlerResource]) -> WrestlerResource:
	return null if team.is_empty() else team[0]


func _team_paths(team: Array[WrestlerResource]) -> PackedStringArray:
	var paths := PackedStringArray()
	for wrestler in team:
		paths.append(wrestler.resource_path if wrestler != null else "")
	return paths


func _sync_legacy_selection_fields() -> void:
	_selected_player = _team_first(_team_a)
	_selected_opponent = _team_first(_team_b)


func _contains_wrestler(wrestler: WrestlerResource) -> bool:
	if wrestler == null:
		return false
	for roster_wrestler in _roster:
		if _same_wrestler(roster_wrestler, wrestler):
			return true
	return false


func _first_wrestler_except(excluded: WrestlerResource) -> WrestlerResource:
	for wrestler in _roster:
		if not _same_wrestler(wrestler, excluded):
			return wrestler
	return null


func _same_wrestler(left: WrestlerResource, right: WrestlerResource) -> bool:
	if left == null or right == null:
		return false
	if left == right:
		return true
	return not left.resource_path.is_empty() and left.resource_path == right.resource_path


func _sort_roster_alphabetically() -> void:
	_roster.sort_custom(func(left: WrestlerResource, right: WrestlerResource) -> bool:
		return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0
	)


func _color_hex(color: Color) -> String:
	return "#%s" % color.to_html(false)


func _bb(value: String) -> String:
	return value.replace("[", "(").replace("]", ")")
