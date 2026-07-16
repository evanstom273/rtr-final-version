extends Control
class_name MatchSetupPopup

signal match_requested(player: WrestlerResource, opponent: WrestlerResource)
signal cancelled

const PROMOTIONS_DIRECTORY := "res://Promotions"
const FACE_COLOR := Color(0.3, 0.68, 1.0, 1.0)
const HEEL_COLOR := Color(1.0, 0.34, 0.36, 1.0)
const CHAMPION_COLOR := Color(0.96, 0.8, 0.28, 1.0)

var _roster: Array[WrestlerResource] = []
var _champion_paths: Dictionary = {}
var _promotion_initials_by_path: Dictionary = {}
var _promotion_names_by_path: Dictionary = {}
var _player_filtered_indices: Array[int] = []
var _opponent_filtered_indices: Array[int] = []
var _selected_player: WrestlerResource
var _selected_opponent: WrestlerResource
var _allow_cancel: bool = false

@onready var _safe_area: MarginContainer = %SetupSafeArea
@onready var _outer_margin: MarginContainer = %SetupOuterMargin
@onready var _selection_row: BoxContainer = %SelectionRow
@onready var _buttons: BoxContainer = %SetupButtons
@onready var _player_filters: BoxContainer = %PlayerFilters
@onready var _opponent_filters: BoxContainer = %OpponentFilters
@onready var _player_search: LineEdit = %PlayerSearch
@onready var _opponent_search: LineEdit = %OpponentSearch
@onready var _player_class_filter: OptionButton = %PlayerClassFilter
@onready var _opponent_class_filter: OptionButton = %OpponentClassFilter
@onready var _player_promotion_filter: OptionButton = %PlayerPromotionFilter
@onready var _opponent_promotion_filter: OptionButton = %OpponentPromotionFilter
@onready var _player_list: ItemList = %PlayerRosterList
@onready var _opponent_list: ItemList = %OpponentRosterList
@onready var _player_summary_name: Label = %PlayerSummaryName
@onready var _player_summary_details: Label = %PlayerSummaryDetails
@onready var _opponent_summary_name: Label = %OpponentSummaryName
@onready var _opponent_summary_details: Label = %OpponentSummaryDetails
@onready var _status: Label = %SetupStatus
@onready var _start_button: Button = %StartMatchButton
@onready var _cancel_button: Button = %CancelSetupButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_populate_class_filters()
	_player_search.text_changed.connect(_on_player_filter_changed)
	_opponent_search.text_changed.connect(_on_opponent_filter_changed)
	_player_class_filter.item_selected.connect(_on_player_class_changed)
	_opponent_class_filter.item_selected.connect(_on_opponent_class_changed)
	_player_promotion_filter.item_selected.connect(_on_player_promotion_changed)
	_opponent_promotion_filter.item_selected.connect(_on_opponent_promotion_changed)
	_player_list.item_selected.connect(_on_player_selected)
	_opponent_list.item_selected.connect(_on_opponent_selected)
	_player_list.item_activated.connect(_on_player_selected)
	_opponent_list.item_activated.connect(_on_opponent_selected)
	_start_button.pressed.connect(_on_start_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var portrait_phone := mode == ResponsiveUI.LayoutMode.PHONE and effective_size.y > effective_size.x
	_selection_row.vertical = portrait_phone
	_buttons.vertical = portrait_phone
	_player_filters.vertical = portrait_phone
	_opponent_filters.vertical = portrait_phone
	var horizontal_margin := int(ResponsiveUI.choose(10, 20, 34))
	var vertical_margin := int(ResponsiveUI.choose(8, 16, 24))
	_outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	_outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	_selection_row.add_theme_constant_override("separation", int(ResponsiveUI.choose(10, 14, 18)))
	_buttons.add_theme_constant_override("separation", int(ResponsiveUI.choose(8, 12, 14)))
	var list_height := 150.0 if portrait_phone else float(ResponsiveUI.choose(230, 300, 360))
	_player_list.custom_minimum_size.y = list_height
	_opponent_list.custom_minimum_size.y = list_height


func open_setup(
	roster: Array[WrestlerResource],
	current_player: WrestlerResource = null,
	current_opponent: WrestlerResource = null,
	allow_cancel: bool = false,
) -> void:
	_roster = roster.duplicate()
	_load_champion_paths()
	_populate_promotion_filters()
	_selected_player = current_player if _contains_wrestler(current_player) else null
	_selected_opponent = current_opponent if _contains_wrestler(current_opponent) else null
	if _selected_player == null and not _roster.is_empty():
		_selected_player = _roster[0]
	if _selected_opponent == null or _same_wrestler(_selected_player, _selected_opponent):
		_selected_opponent = _first_wrestler_except(_selected_player)
	_allow_cancel = allow_cancel
	_cancel_button.visible = allow_cancel
	_player_search.clear()
	_opponent_search.clear()
	_player_class_filter.select(0)
	_opponent_class_filter.select(0)
	_player_promotion_filter.select(0)
	_opponent_promotion_filter.select(0)
	_status.text = ""
	_refresh_player_list()
	_refresh_opponent_list()
	_refresh_selection_state()
	visible = true
	_player_search.grab_focus()


func close_setup() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _allow_cancel:
		_on_cancel_pressed()
	get_viewport().set_input_as_handled()


func _populate_class_filters() -> void:
	for filter in [_player_class_filter, _opponent_class_filter]:
		filter.clear()
		filter.add_item("All Classes", -1)
		for key in WrestlerResource.WrestlerClass:
			filter.add_item(_pretty_enum_key(str(key)), int(WrestlerResource.WrestlerClass[key]))


func _populate_promotion_filters() -> void:
	var initials: Array[String] = []
	for value in _promotion_initials_by_path.values():
		var promotion_initials := str(value)
		if not promotion_initials.is_empty() and promotion_initials not in initials:
			initials.append(promotion_initials)
	initials.sort_custom(func(left: String, right: String) -> bool:
		return left.nocasecmp_to(right) < 0
	)
	for filter in [_player_promotion_filter, _opponent_promotion_filter]:
		filter.clear()
		filter.add_item("All Promotions")
		for promotion_initials in initials:
			var item_index: int = filter.item_count
			filter.add_item(promotion_initials)
			filter.set_item_metadata(item_index, promotion_initials)


func _refresh_player_list() -> void:
	_player_filtered_indices = _populate_list(
		_player_list,
		_player_search.text,
		_selected_class_id(_player_class_filter),
		_selected_promotion_initials(_player_promotion_filter),
		_selected_player,
	)


func _refresh_opponent_list() -> void:
	_opponent_filtered_indices = _populate_list(
		_opponent_list,
		_opponent_search.text,
		_selected_class_id(_opponent_class_filter),
		_selected_promotion_initials(_opponent_promotion_filter),
		_selected_opponent,
	)


func _selected_class_id(filter: OptionButton) -> int:
	return -1 if filter.selected <= 0 else filter.get_selected_id()


func _selected_promotion_initials(filter: OptionButton) -> String:
	return "" if filter.selected <= 0 else str(filter.get_item_metadata(filter.selected))


func _populate_list(
	list: ItemList,
	search_text: String,
	class_id: int,
	promotion_initials: String,
	selected: WrestlerResource,
) -> Array[int]:
	list.clear()
	var filtered: Array[int] = []
	var normalized_search := search_text.strip_edges().to_lower()
	for roster_index in _roster.size():
		var wrestler := _roster[roster_index]
		if class_id >= 0 and class_id not in wrestler.wrestler_class:
			continue
		if not promotion_initials.is_empty() and _promotion_initials_for(wrestler) != promotion_initials:
			continue
		if not normalized_search.is_empty() and not _searchable_text(wrestler).contains(normalized_search):
			continue
		filtered.append(roster_index)
		var item_index := list.add_item(_roster_item_text(wrestler))
		list.set_item_metadata(item_index, roster_index)
		list.set_item_custom_fg_color(item_index, _name_color(wrestler))
		if _same_wrestler(wrestler, selected):
			list.select(item_index)
	if filtered.is_empty():
		var empty_index := list.add_item("No wrestlers match these filters")
		list.set_item_disabled(empty_index, true)
	return filtered


func _on_player_filter_changed(_value: String) -> void:
	_refresh_player_list()


func _on_opponent_filter_changed(_value: String) -> void:
	_refresh_opponent_list()


func _on_player_class_changed(_index: int) -> void:
	_refresh_player_list()


func _on_opponent_class_changed(_index: int) -> void:
	_refresh_opponent_list()


func _on_player_promotion_changed(_index: int) -> void:
	_refresh_player_list()


func _on_opponent_promotion_changed(_index: int) -> void:
	_refresh_opponent_list()


func _on_player_selected(list_index: int) -> void:
	if list_index < 0 or list_index >= _player_list.item_count or _player_list.is_item_disabled(list_index):
		return
	var roster_index := int(_player_list.get_item_metadata(list_index))
	if roster_index < 0 or roster_index >= _roster.size():
		return
	_selected_player = _roster[roster_index]
	_refresh_selection_state()


func _on_opponent_selected(list_index: int) -> void:
	if list_index < 0 or list_index >= _opponent_list.item_count or _opponent_list.is_item_disabled(list_index):
		return
	var roster_index := int(_opponent_list.get_item_metadata(list_index))
	if roster_index < 0 or roster_index >= _roster.size():
		return
	_selected_opponent = _roster[roster_index]
	_refresh_selection_state()


func _refresh_selection_state() -> void:
	_update_wrestler_summary(_player_summary_name, _player_summary_details, _selected_player)
	_update_wrestler_summary(_opponent_summary_name, _opponent_summary_details, _selected_opponent)
	var duplicate := _same_wrestler(_selected_player, _selected_opponent)
	_start_button.disabled = _selected_player == null or _selected_opponent == null or duplicate
	if _roster.size() < 2:
		_status.text = "At least two wrestlers are required to start a match."
	elif duplicate:
		_status.text = "Choose two different wrestlers."
	else:
		_status.text = "Ready: %s vs. %s" % [_display_name(_selected_player), _display_name(_selected_opponent)]


func _on_start_pressed() -> void:
	if _start_button.disabled:
		return
	var player := _selected_player
	var opponent := _selected_opponent
	close_setup()
	match_requested.emit(player, opponent)


func _on_cancel_pressed() -> void:
	if not _allow_cancel:
		return
	close_setup()
	cancelled.emit()


func _roster_item_text(wrestler: WrestlerResource) -> String:
	return _formatted_roster_name(wrestler)


func _update_wrestler_summary(name_label: Label, details_label: Label, wrestler: WrestlerResource) -> void:
	if wrestler == null:
		name_label.text = "No wrestler selected"
		name_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.8, 1.0))
		details_label.text = ""
		return
	name_label.text = _formatted_roster_name(wrestler)
	name_label.add_theme_color_override("font_color", _name_color(wrestler))
	var gimmick := wrestler.gimmick_name.strip_edges()
	if gimmick.is_empty():
		gimmick = "None"
	var gimmick_description := wrestler.gimmick_description.strip_edges()
	if not gimmick_description.is_empty():
		gimmick += " — %s" % gimmick_description
	details_label.text = "Finishers: %s\nClass: %s\nGimmick: %s\nNationality: %s\nPromotion: %s" % [
		_format_finishers(wrestler),
		_format_classes(wrestler.wrestler_class),
		gimmick,
		_format_origin(wrestler),
		_format_promotion(wrestler),
	]


func _searchable_text(wrestler: WrestlerResource) -> String:
	return " ".join([
		_display_name(wrestler),
		wrestler.gimmick_name,
		wrestler.gimmick_description,
		_format_classes(wrestler.wrestler_class),
		_format_origin(wrestler),
		_format_disposition(wrestler),
		_disposition_search_terms(wrestler),
		_format_promotion(wrestler),
	]).to_lower()


func _formatted_roster_name(wrestler: WrestlerResource) -> String:
	var champion_prefix := "(c) " if _is_champion(wrestler) else ""
	var disposition_suffix := ""
	match int(wrestler.wrestler_disposition):
		WrestlerResource.WrestlerDisposition.FACE:
			disposition_suffix = " (f)"
		WrestlerResource.WrestlerDisposition.HEEL:
			disposition_suffix = " (h)"
	return "%s%s%s" % [champion_prefix, _display_name(wrestler), disposition_suffix]


func _name_color(wrestler: WrestlerResource) -> Color:
	if _is_champion(wrestler):
		return CHAMPION_COLOR
	if wrestler != null and wrestler.wrestler_disposition == WrestlerResource.WrestlerDisposition.FACE:
		return FACE_COLOR
	if wrestler != null and wrestler.wrestler_disposition == WrestlerResource.WrestlerDisposition.HEEL:
		return HEEL_COLOR
	return Color(0.84, 0.88, 0.95, 1.0)


func _format_finishers(wrestler: WrestlerResource) -> String:
	var names: Array[String] = []
	for move in wrestler.move_set:
		if move != null and move.is_finisher:
			var move_name := move.move_name.strip_edges()
			if not move_name.is_empty() and move_name not in names:
				names.append(move_name)
	names.sort_custom(func(left: String, right: String) -> bool:
		return left.nocasecmp_to(right) < 0
	)
	return ", ".join(names) if not names.is_empty() else "None assigned"


func _format_disposition(wrestler: WrestlerResource) -> String:
	return _format_enum(
		WrestlerResource.WrestlerDisposition,
		int(wrestler.wrestler_disposition),
		"Not Set",
	)


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
	var initials := _promotion_initials_for(wrestler)
	var promotion_name := str(_promotion_names_by_path.get(wrestler.resource_path, ""))
	if initials.is_empty():
		return "Independent / Not Assigned"
	return initials if promotion_name.is_empty() else "%s — %s" % [initials, promotion_name]


func _format_classes(classes: Array) -> String:
	if classes.is_empty():
		return "No Class"
	var names: Array[String] = []
	for wrestler_class in classes:
		names.append(_format_enum(WrestlerResource.WrestlerClass, int(wrestler_class), "Unknown"))
	return ", ".join(names)


func _format_origin(wrestler: WrestlerResource) -> String:
	var region := _format_enum(WrestlerResource.Region, int(wrestler.birthplace), "Not Set")
	var country := ""
	match int(wrestler.birthplace):
		WrestlerResource.Region.NORTH_AMERICA:
			country = _format_enum(WrestlerResource.NA_Countries, int(wrestler.north_american_country), "")
		WrestlerResource.Region.SOUTH_AMERICA:
			country = _format_enum(WrestlerResource.SA_Countries, int(wrestler.south_american_country), "")
		WrestlerResource.Region.EUROPE:
			country = _format_enum(WrestlerResource.Europe_Countries, int(wrestler.europe_country), "")
		WrestlerResource.Region.ASIA:
			country = _format_enum(WrestlerResource.Asia_Countries, int(wrestler.asia_country), "")
		WrestlerResource.Region.AFRICA:
			country = _format_enum(WrestlerResource.Africa_Countries, int(wrestler.africa_country), "")
		WrestlerResource.Region.OCEANIA:
			country = _format_enum(WrestlerResource.Oceania_Countries, int(wrestler.oceania_country), "")
	return region if country.is_empty() or country == "Other" else "%s, %s" % [country, region]


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


func _contains_wrestler(wrestler: WrestlerResource) -> bool:
	if wrestler == null:
		return false
	for roster_wrestler in _roster:
		if _same_wrestler(roster_wrestler, wrestler):
			return true
	return false


func _load_champion_paths() -> void:
	_champion_paths.clear()
	_promotion_initials_by_path.clear()
	_promotion_names_by_path.clear()
	var promotion_paths: Array[String] = []
	_collect_resource_paths(PROMOTIONS_DIRECTORY, promotion_paths)
	for path in promotion_paths:
		var resource := ResourceLoader.load(path)
		if not resource is PromotionResource:
			continue
		var promotion := resource as PromotionResource
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
				if wrestler != null and wrestler.wrestler_id == title.current_holder_id:
					_champion_paths[wrestler.resource_path] = true


func _collect_resource_paths(directory_path: String, paths: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_resource_paths(directory_path.path_join(entry.trim_suffix("/")), paths)
		elif entry.get_extension().to_lower() == "tres":
			paths.append(directory_path.path_join(entry))


func _is_champion(wrestler: WrestlerResource) -> bool:
	return wrestler != null and not wrestler.resource_path.is_empty() and _champion_paths.has(wrestler.resource_path)


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
