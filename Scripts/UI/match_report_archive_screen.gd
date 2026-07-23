extends Control
class_name MatchReportArchiveScreen

signal back_requested

const REPORT_SCENE: PackedScene = preload("res://Scenes/Match/match_report_screen.tscn")

var _visible_entries: Array = []
var _report_screen: MatchReportPopup
var _participant_ids: Array[String] = []
var _winner_ids: Array[String] = []
var _loser_ids: Array[String] = []
var _match_type_ids: Array[String] = []
var _stipulation_ids: Array[String] = []

@onready var _safe_area: MarginContainer = %ArchiveSafeArea
@onready var _outer_margin: MarginContainer = %ArchiveOuterMargin
@onready var _content_row: BoxContainer = %ArchiveContentRow
@onready var _filter_row_one: BoxContainer = %FilterRowOne
@onready var _filter_row_two: BoxContainer = %FilterRowTwo
@onready var _search: LineEdit = %ArchiveSearch
@onready var _wrestler_filter: OptionButton = %WrestlerFilter
@onready var _match_type_filter: OptionButton = %MatchTypeFilter
@onready var _stipulation_filter: OptionButton = %StipulationFilter
@onready var _winner_filter: OptionButton = %WinnerFilter
@onready var _loser_filter: OptionButton = %LoserFilter
@onready var _minimum_rating: OptionButton = %MinimumRating
@onready var _maximum_rating: OptionButton = %MaximumRating
@onready var _sort: OptionButton = %ArchiveSort
@onready var _list: ItemList = %ArchiveList
@onready var _status: Label = %ArchiveStatus
@onready var _history_panel: PanelContainer = %HistoryPanel
@onready var _history_title: Label = %HistoryTitle
@onready var _history_text: Label = %HistoryText
@onready var _highest_button: Button = %HighestRatedButton
@onready var _longest_button: Button = %LongestButton
@onready var _shortest_button: Button = %ShortestButton
@onready var _view_button: Button = %ViewReportButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_search.text_changed.connect(func(_value: String) -> void: _refresh_results())
	for option in [
		_wrestler_filter, _match_type_filter, _stipulation_filter, _winner_filter,
		_loser_filter, _minimum_rating, _maximum_rating, _sort,
	]:
		(option as OptionButton).item_selected.connect(func(_index: int) -> void: _refresh_results())
	_list.item_activated.connect(_open_entry_at)
	_list.item_selected.connect(func(_index: int) -> void: _view_button.disabled = false)
	_view_button.pressed.connect(func() -> void:
		if not _list.get_selected_items().is_empty():
			_open_entry_at(_list.get_selected_items()[0])
	)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_highest_button.pressed.connect(func() -> void: _open_history_match("highest_rated"))
	_longest_button.pressed.connect(func() -> void: _open_history_match("longest"))
	_shortest_button.pressed.connect(func() -> void: _open_history_match("shortest"))
	_populate_filters()
	_refresh_results()


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, _effective_size: Vector2) -> void:
	var phone := mode == ResponsiveUI.LayoutMode.PHONE
	_content_row.vertical = phone
	_filter_row_one.vertical = phone
	_filter_row_two.vertical = phone
	_list.custom_minimum_size.x = 0.0 if phone else 700.0
	_history_panel.custom_minimum_size.x = 0.0 if phone else 390.0
	var horizontal := int(ResponsiveUI.choose(12, 24, 42))
	var vertical := int(ResponsiveUI.choose(10, 18, 28))
	_outer_margin.add_theme_constant_override("margin_left", horizontal)
	_outer_margin.add_theme_constant_override("margin_top", vertical)
	_outer_margin.add_theme_constant_override("margin_right", horizontal)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical)


func prepare_for_scene_exit() -> void:
	if _report_screen != null:
		_report_screen.close_report()
		_report_screen.queue_free()
		_report_screen = null


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _report_screen != null:
		_close_report()
	else:
		back_requested.emit()
	get_viewport().set_input_as_handled()


func _populate_filters() -> void:
	var catalogue: Dictionary = MatchReportArchive.get_filter_catalogue()
	var participants: Dictionary = catalogue.get("participants", {})
	_populate_named_filter(_wrestler_filter, _participant_ids, "All Wrestlers", participants)
	_populate_named_filter(_winner_filter, _winner_ids, "All Winners", participants)
	_populate_named_filter(_loser_filter, _loser_ids, "All Losers", participants)
	_populate_named_filter(
		_match_type_filter, _match_type_ids, "All Match Types",
		catalogue.get("match_types", {}),
	)
	_populate_named_filter(
		_stipulation_filter, _stipulation_ids, "All Stipulations",
		catalogue.get("stipulations", {}),
	)
	_minimum_rating.clear()
	_maximum_rating.clear()
	for step in 21:
		var value := float(step) * 0.25
		_minimum_rating.add_item("Min %.2f" % value)
		_maximum_rating.add_item("Max %.2f" % value)
	_minimum_rating.select(0)
	_maximum_rating.select(20)
	_sort.clear()
	for label in ["Newest", "Oldest", "Highest Rated", "Lowest Rated", "Longest", "Shortest"]:
		_sort.add_item(label)


func _populate_named_filter(
	option: OptionButton,
	ids: Array[String],
	all_label: String,
	values: Dictionary,
) -> void:
	option.clear()
	ids.clear()
	option.add_item(all_label)
	ids.append("")
	var rows: Array[Dictionary] = []
	for key in values:
		rows.append({"id": str(key), "name": str(values[key])})
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", ""))) < 0
	)
	for row in rows:
		option.add_item(str(row.get("name", "")))
		ids.append(str(row.get("id", "")))


func _refresh_results() -> void:
	var filters := {
		"search": _search.text,
		"wrestler_id": _selected_id(_wrestler_filter, _participant_ids),
		"match_type": _selected_id(_match_type_filter, _match_type_ids),
		"stipulation": _selected_id(_stipulation_filter, _stipulation_ids),
		"winner_id": _selected_id(_winner_filter, _winner_ids),
		"loser_id": _selected_id(_loser_filter, _loser_ids),
		"minimum_rating": float(_minimum_rating.selected) * 0.25,
		"maximum_rating": float(_maximum_rating.selected) * 0.25,
	}
	var sort_modes := ["newest", "oldest", "highest", "lowest", "longest", "shortest"]
	var sort_mode: String = sort_modes[clampi(_sort.selected, 0, sort_modes.size() - 1)]
	_visible_entries = MatchReportArchive.query_index(filters, sort_mode)
	_list.clear()
	for entry in _visible_entries:
		_list.add_item(_entry_text(entry))
	_view_button.disabled = true
	_status.text = (
		"No completed matches match these filters."
		if _visible_entries.is_empty()
		else "%d completed %s" % [_visible_entries.size(), "match" if _visible_entries.size() == 1 else "matches"]
	)
	_refresh_wrestler_history(str(filters.get("wrestler_id", "")))


func _entry_text(entry: Dictionary) -> String:
	var participants: Array = entry.get("participant_names", [])
	var matchup := " vs. ".join(PackedStringArray(participants))
	var result_line := (
		"%s defeated %s" % [str(entry.get("winner", "No Winner")), str(entry.get("loser", "None"))]
		if str(entry.get("winner_id", "")) != ""
		else matchup
	)
	return "%s\n%s  •  %s  •  %s — %s  •  %s" % [
		MatchRatingCalculator.format_stars(float(entry.get("stars", 0.0))),
		result_line,
		str(entry.get("final_time", "00:00")),
		str(entry.get("match_type", "Singles")),
		str(entry.get("stipulation", "Standard")),
		str(entry.get("date_display", entry.get("completed_at_utc", ""))),
	]


func _refresh_wrestler_history(participant_id: String) -> void:
	_history_panel.visible = not participant_id.is_empty()
	if participant_id.is_empty():
		return
	var history: Dictionary = MatchReportArchive.get_wrestler_history(participant_id)
	_history_title.text = "%s — RECORDED HISTORY" % str(history.get("name", "Unknown Wrestler")).to_upper()
	_history_text.text = "\n".join([
		"Matches: %d" % int(history.get("matches", 0)),
		"Record: %d wins • %d losses • %d draws" % [
			int(history.get("wins", 0)), int(history.get("losses", 0)), int(history.get("draws", 0)),
		],
		"Win percentage: %.1f%%" % float(history.get("win_percentage", 0.0)),
		"Average rating: %.2f stars" % float(history.get("average_rating", 0.0)),
		"Most common opponent: %s" % str(history.get("most_common_opponent", "None")),
		"Total time wrestled: %s" % _format_duration(int(history.get("total_time_seconds", 0))),
	])
	for pair in [
		[_highest_button, "highest_rated"],
		[_longest_button, "longest"],
		[_shortest_button, "shortest"],
	]:
		var button := pair[0] as Button
		var entry: Dictionary = history.get(str(pair[1]), {})
		button.disabled = entry.is_empty()
		button.set_meta("report_id", str(entry.get("report_id", "")))


func _open_entry_at(index: int) -> void:
	if index < 0 or index >= _visible_entries.size():
		return
	_open_report_id(str((_visible_entries[index] as Dictionary).get("report_id", "")))


func _open_history_match(kind: String) -> void:
	var participant_id := _selected_id(_wrestler_filter, _participant_ids)
	var history: Dictionary = MatchReportArchive.get_wrestler_history(participant_id)
	var entry: Dictionary = history.get(kind, {})
	_open_report_id(str(entry.get("report_id", "")))


func _open_report_id(report_id: String) -> void:
	var report := MatchReportArchive.load_report(report_id)
	if report.is_empty():
		_status.text = "That saved report is unavailable or damaged."
		return
	_report_screen = REPORT_SCENE.instantiate() as MatchReportPopup
	add_child(_report_screen)
	_report_screen.return_requested.connect(_close_report)
	_report_screen.open_report(report, true)


func _close_report() -> void:
	if _report_screen == null:
		return
	_report_screen.close_report()
	_report_screen.queue_free()
	_report_screen = null
	_list.grab_focus()


func _selected_id(option: OptionButton, values: Array[String]) -> String:
	return values[option.selected] if option.selected >= 0 and option.selected < values.size() else ""


func _format_duration(seconds: int) -> String:
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	var remaining_seconds := seconds % 60
	return (
		"%dh %02dm %02ds" % [hours, minutes, remaining_seconds]
		if hours > 0
		else "%dm %02ds" % [minutes, remaining_seconds]
	)
