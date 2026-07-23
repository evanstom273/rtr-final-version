extends Control
class_name ExhibitionFlowController

signal main_menu_requested

const ROSTER_DIRECTORY := "res://Wrestlers"
const SETUP_SCENE: PackedScene = preload("res://Scenes/Match/exhibition_setup.tscn")
const MATCH_SCENE: PackedScene = preload("res://Scenes/Match/simple_match_ui.tscn")
const REPORT_SCENE: PackedScene = preload("res://Scenes/Match/match_report_screen.tscn")

var _roster: Array[WrestlerResource] = []
var _recent_matchups: Array[PackedStringArray] = []
var _setup_screen: MatchSetupPopup
var _match_screen: SimpleMatchUI
var _report_screen: MatchReportPopup
var _last_match_request: Dictionary = {}

@onready var _current_screen: Control = %CurrentScreen


func _ready() -> void:
	_load_roster()
	_show_setup(true)


func _show_setup(allow_cancel: bool) -> void:
	_last_match_request.clear()
	_clear_report_screen()
	_clear_match_screen()
	_clear_setup_screen()
	_setup_screen = SETUP_SCENE.instantiate() as MatchSetupPopup
	_current_screen.add_child(_setup_screen)
	_setup_screen.match_requested.connect(_on_setup_match_requested)
	_setup_screen.cancelled.connect(_on_setup_cancelled)
	_setup_screen.open_setup(_roster, null, null, allow_cancel, _recent_wrestler_paths())


func _show_match(player: WrestlerResource, opponent: WrestlerResource, setup_metadata: Dictionary) -> void:
	_clear_report_screen()
	_clear_setup_screen()
	_clear_match_screen()
	_match_screen = MATCH_SCENE.instantiate() as SimpleMatchUI
	_current_screen.add_child(_match_screen)
	_match_screen.full_report_requested.connect(_on_match_full_report_requested)
	_match_screen.new_match_requested.connect(_on_new_match_requested)
	_match_screen.return_to_exhibition_requested.connect(_on_pause_return_to_exhibition)
	_match_screen.return_to_main_menu_requested.connect(_on_pause_return_to_main_menu)
	if not _match_screen.configure_match(player, opponent, setup_metadata):
		_clear_match_screen()
		_show_setup(false)
		if _setup_screen != null:
			_setup_screen.reject_launch("That match could not be started from the selected resources.")
		return
	_record_recent_matchup(player, opponent)
	_store_last_match_request(player, opponent, setup_metadata)


func _show_report(report: Dictionary) -> void:
	if _match_screen != null:
		_match_screen.visible = false
	_clear_report_screen()
	_report_screen = REPORT_SCENE.instantiate() as MatchReportPopup
	_current_screen.add_child(_report_screen)
	_report_screen.return_requested.connect(_on_report_return_requested)
	_report_screen.new_match_requested.connect(_on_new_match_requested)
	_report_screen.rematch_requested.connect(_on_report_rematch_requested)
	_report_screen.open_report(report)


func _on_setup_match_requested(
	player: WrestlerResource,
	opponent: WrestlerResource,
	setup_metadata: Dictionary,
) -> void:
	if player == null or opponent == null:
		_setup_screen.reject_launch("Both sides need a loaded wrestler resource.")
		return
	if not _roster_contains_resource(player) or not _roster_contains_resource(opponent):
		_setup_screen.reject_launch("That selection is no longer available in the loaded roster.")
		return
	if _same_wrestler(player, opponent):
		_setup_screen.reject_launch("Player and AI must be different wrestlers.")
		return
	_setup_screen.confirm_launch()
	_show_match(player, opponent, setup_metadata.duplicate(true))


func _on_setup_cancelled() -> void:
	if _match_screen != null:
		_clear_setup_screen()
		_match_screen.visible = true
		return
	main_menu_requested.emit()


func _on_match_full_report_requested(report: Dictionary) -> void:
	if report.is_empty():
		return
	_show_report(report.duplicate(true))


func _on_report_return_requested() -> void:
	_clear_report_screen()
	if _match_screen != null:
		_match_screen.restore_finished_match_screen()


func _on_new_match_requested() -> void:
	_show_setup(true)


func _on_pause_return_to_exhibition() -> void:
	_show_setup(true)


func _on_pause_return_to_main_menu() -> void:
	main_menu_requested.emit()


func _on_report_rematch_requested() -> void:
	if _last_match_request.is_empty():
		_show_setup(true)
		return
	var player := _last_match_request.get("player") as WrestlerResource
	var opponent := _last_match_request.get("opponent") as WrestlerResource
	var setup_metadata := (_last_match_request.get("setup_metadata", {}) as Dictionary).duplicate(true)
	if player == null or opponent == null:
		_show_setup(true)
		return
	_show_match(player, opponent, setup_metadata)


func prepare_for_scene_exit() -> void:
	_clear_report_screen()
	_clear_match_screen()
	_clear_setup_screen()


func handle_app_cancel() -> bool:
	if _report_screen != null:
		_on_report_return_requested()
		return true
	if _match_screen == null or not _match_screen.visible:
		return false
	_match_screen.request_pause()
	return true


func _clear_setup_screen() -> void:
	if _setup_screen == null:
		return
	_setup_screen.queue_free()
	_setup_screen = null


func _clear_match_screen() -> void:
	if _match_screen == null:
		return
	_match_screen.prepare_for_scene_exit()
	_match_screen.queue_free()
	_match_screen = null


func _clear_report_screen() -> void:
	if _report_screen == null:
		return
	_report_screen.close_report()
	_report_screen.queue_free()
	_report_screen = null


func _load_roster() -> void:
	_roster.clear()
	var resource_paths: Array[String] = []
	_collect_wrestler_paths(ROSTER_DIRECTORY, resource_paths)
	for path in resource_paths:
		var resource: Resource = ResourceLoader.load(path)
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


func _roster_contains_resource(wrestler: WrestlerResource) -> bool:
	for roster_wrestler in _roster:
		if _same_wrestler(roster_wrestler, wrestler):
			return true
	return false


func _same_wrestler(left: WrestlerResource, right: WrestlerResource) -> bool:
	if left == null or right == null:
		return false
	if left == right:
		return true
	return not left.resource_path.is_empty() and left.resource_path == right.resource_path


func _record_recent_matchup(player: WrestlerResource, opponent: WrestlerResource) -> void:
	var matchup := PackedStringArray()
	if player != null and not player.resource_path.is_empty():
		matchup.append(player.resource_path)
	if opponent != null and not opponent.resource_path.is_empty():
		matchup.append(opponent.resource_path)
	_recent_matchups.append(matchup)
	while _recent_matchups.size() > 5:
		_recent_matchups.pop_front()


func _store_last_match_request(
	player: WrestlerResource,
	opponent: WrestlerResource,
	setup_metadata: Dictionary,
) -> void:
	_last_match_request = {
		"player": player,
		"opponent": opponent,
		"setup_metadata": setup_metadata.duplicate(true),
	}


func _recent_wrestler_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for matchup in _recent_matchups:
		for path in matchup:
			if path not in paths:
				paths.append(path)
	return paths
