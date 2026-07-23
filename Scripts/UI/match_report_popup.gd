extends Control
class_name MatchReportPopup

signal return_requested
signal new_match_requested
signal rematch_requested

const REPORT_DIRECTORY := "user://match_reports"
const TOUCH_SCROLL_DEADZONE := 8.0

var _report: Dictionary = {}
var _archive_context := false
var latest_export_path := ""
var _touch_scroll_active := false
var _touch_scroll_index := -1
var _touch_scroll_distance := 0.0

@onready var _safe_area: MarginContainer = %ReportSafeArea
@onready var _outer_margin: MarginContainer = %ReportOuterMargin
@onready var _header_row: BoxContainer = %ReportHeaderRow
@onready var _report_buttons: BoxContainer = %ReportButtons
@onready var _page_scroll: ScrollContainer = %ReportPageScroll
@onready var _title: Label = %ReportTitle
@onready var _subtitle: Label = %ReportSubtitle
@onready var _rating: Label = %RatingValue
@onready var _winner: Label = %WinnerValue
@onready var _loser: Label = %LoserValue
@onready var _duration: Label = %DurationValue
@onready var _match_type: Label = %MatchTypeValue
@onready var _stipulation: Label = %StipulationValue
@onready var _method: Label = %MethodValue
@onready var _finish: Label = %FinishValue
@onready var _highlights: Label = %RatingHighlights
@onready var _match_log_text: Label = %FullMatchLog
@onready var _status: Label = %ExportStatus
@onready var _export_button: Button = %ExportReportButton
@onready var _retry_archive_button: Button = %RetryArchiveButton
@onready var _rematch_button: Button = %RematchButton
@onready var _new_match_button: Button = %NewMatchButton
@onready var _return_button: Button = %ReturnToMatchButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_export_button.pressed.connect(_export_text_report)
	_retry_archive_button.pressed.connect(_retry_archive_save)
	_rematch_button.pressed.connect(func() -> void:
		close_report()
		rematch_requested.emit()
	)
	_new_match_button.pressed.connect(func() -> void:
		close_report()
		new_match_requested.emit()
	)
	_return_button.pressed.connect(_return_from_report)
	_match_log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, _effective_size: Vector2) -> void:
	var phone_layout := mode == ResponsiveUI.LayoutMode.PHONE
	_header_row.vertical = phone_layout
	_report_buttons.vertical = phone_layout
	var horizontal_margin := int(ResponsiveUI.choose(12, 24, 42))
	var vertical_margin := int(ResponsiveUI.choose(10, 18, 28))
	_outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	_outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)


func open_report(report: Dictionary, archive_context: bool = false) -> void:
	_report = report.duplicate(true)
	_archive_context = archive_context
	latest_export_path = ""
	_export_button.disabled = false
	_title.text = "MATCH REPORT"
	_subtitle.text = str(_report.get("subtitle", "Completed wrestling match"))
	var rating_data: Dictionary = _report.get("rating", {})
	_rating.text = MatchRatingCalculator.format_stars(float(rating_data.get("stars", 0.0)))
	_winner.text = str(_report.get("winner", "No Winner"))
	_loser.text = str(_report.get("loser", "None"))
	_duration.text = str(_report.get("final_time", "00:00"))
	_match_type.text = str(_report.get("match_type", "Singles"))
	_stipulation.text = str(_report.get("stipulation", "Standard"))
	_method.text = str(_report.get("result", "Not Set"))
	_finish.text = str(_report.get("finish_move", "None"))
	var highlight_lines := PackedStringArray()
	for highlight in (_report.get("rating_highlights", []) as Array):
		highlight_lines.append("• %s" % str(highlight))
	_highlights.text = "\n".join(highlight_lines) if not highlight_lines.is_empty() else "• A straightforward wrestling contest"
	var rendered_log := PackedStringArray()
	for log_line in (_report.get("log_lines", []) as Array):
		rendered_log.append(str(log_line))
	_match_log_text.text = "\n".join(rendered_log) if not rendered_log.is_empty() else "No match log entries were recorded."
	_return_button.text = "BACK TO ARCHIVE" if _archive_context else "RETURN TO MATCH"
	_rematch_button.visible = not _archive_context
	_new_match_button.visible = not _archive_context
	var archive_error := str(_report.get("archive_save_error", ""))
	_retry_archive_button.visible = not archive_error.is_empty()
	_set_export_status(archive_error, "warning")
	visible = true
	await get_tree().process_frame
	_page_scroll.scroll_vertical = 0
	_return_button.grab_focus()


func close_report() -> void:
	_reset_touch_scroll()
	visible = false


func _input(event: InputEvent) -> void:
	if not visible or not is_instance_valid(_page_scroll):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _page_scroll.get_global_rect().has_point(touch.position):
			_touch_scroll_active = true
			_touch_scroll_index = touch.index
			_touch_scroll_distance = 0.0
		elif not touch.pressed and touch.index == _touch_scroll_index:
			_reset_touch_scroll()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_scroll_active and drag.index == _touch_scroll_index:
			_touch_scroll_distance += absf(drag.relative.y)
			if _touch_scroll_distance >= TOUCH_SCROLL_DEADZONE:
				_page_scroll.scroll_vertical -= roundi(drag.relative.y)
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_return_from_report()
		get_viewport().set_input_as_handled()


func _reset_touch_scroll() -> void:
	_touch_scroll_active = false
	_touch_scroll_index = -1
	_touch_scroll_distance = 0.0


func _return_from_report() -> void:
	close_report()
	return_requested.emit()


func _export_text_report() -> void:
	if _report.is_empty():
		_set_export_status("There is no completed match report to export.", "error")
		return
	var report_filename := _build_report_filename()
	if OS.has_feature("android"):
		_export_android_report(report_filename)
	else:
		_export_report_to_user_directory(report_filename)


func _retry_archive_save() -> void:
	if _report.is_empty():
		return
	_retry_archive_button.disabled = true
	var result: Dictionary = MatchReportArchive.save_completed_match(_report)
	_retry_archive_button.disabled = false
	if bool(result.get("ok", false)):
		_report["report_id"] = str(result.get("report_id", ""))
		_report.erase("archive_save_error")
		_retry_archive_button.visible = false
		_set_export_status("Added to Match Reports.", "success")
	else:
		_set_export_status(str(result.get("error", "The archive save failed again.")), "error")


func _export_android_report(report_filename: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_set_export_status("The Android document picker is unavailable. Saving inside the app instead.", "warning")
		_export_report_to_user_directory(report_filename)
		return
	_export_button.disabled = true
	_set_export_status("Choose where to save the match report.", "active")
	var error := DisplayServer.file_dialog_show(
		"Save Match Report", "", report_filename, false,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.txt;Text Report;text/plain"]),
		_on_android_report_destination_selected,
	)
	if error != OK:
		_export_button.disabled = false
		_export_report_to_user_directory(report_filename)


func _on_android_report_destination_selected(
	status: bool,
	selected_paths: PackedStringArray,
	_selected_filter_index: int,
) -> void:
	_export_button.disabled = false
	if not status or selected_paths.is_empty():
		_set_export_status("Export cancelled.", "warning")
		return
	if _write_report_file(selected_paths[0]):
		latest_export_path = selected_paths[0]
		_set_export_status("Match report saved.", "success")
	else:
		_set_export_status("The report could not be written.", "error")


func _export_report_to_user_directory(report_filename: String) -> void:
	var directory := DirAccess.open("user://")
	if directory == null or directory.make_dir_recursive("match_reports") not in [OK, ERR_ALREADY_EXISTS]:
		_set_export_status("Could not create the match_reports folder.", "error")
		return
	var path := "%s/%s" % [REPORT_DIRECTORY, report_filename]
	if not _write_report_file(path):
		_set_export_status("The match report could not be written.", "error")
		return
	latest_export_path = ProjectSettings.globalize_path(path)
	_set_export_status("Saved: %s" % latest_export_path, "success")


func _write_report_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(str(_report.get("export_text", "")))
	file.close()
	return true


func _build_report_filename() -> String:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	return "%s_%s.txt" % [_safe_filename(str(_report.get("file_stem", "match_report"))), timestamp]


func _safe_filename(value: String) -> String:
	var result := value.to_lower()
	for character in [" ", "\"", "'", "/", "\\", ":", "*", "?", "<", ">", "|"]:
		result = result.replace(character, "_")
	while "__" in result:
		result = result.replace("__", "_")
	return result.trim_prefix("_").trim_suffix("_")


func _set_export_status(message: String, semantic: String = "secondary") -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", AppThemePalette.semantic_text(semantic))
