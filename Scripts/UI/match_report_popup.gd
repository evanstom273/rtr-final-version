extends Control
class_name MatchReportPopup

signal return_requested
signal new_match_requested

const REPORT_DIRECTORY := "user://match_reports"
const TOUCH_SCROLL_DEADZONE := 8.0

var _report: Dictionary = {}
var latest_export_path: String = ""
var _touch_scroll_active: bool = false
var _touch_scroll_index: int = -1
var _touch_scroll_distance: float = 0.0

@onready var _safe_area: MarginContainer = %ReportSafeArea
@onready var _outer_margin: MarginContainer = %ReportOuterMargin
@onready var _header_row: BoxContainer = %ReportHeaderRow
@onready var _report_buttons: BoxContainer = %ReportButtons
@onready var _stats_row: BoxContainer = %ReportStatsRow
@onready var _page_scroll: ScrollContainer = %ReportPageScroll
@onready var _title: Label = %ReportTitle
@onready var _subtitle: Label = %ReportSubtitle
@onready var _winner_value: Label = %WinnerValue
@onready var _result_value: Label = %ResultValue
@onready var _time_value: Label = %TimeValue
@onready var _finish_move_value: Label = %FinishMoveValue
@onready var _setup_method_value: Label = %SetupMethodValue
@onready var _locks_value: Label = %LocksValue
@onready var _randomized_value: Label = %RandomizedValue
@onready var _player_heading: Label = %PlayerReportHeading
@onready var _player_stats: Label = %PlayerReportStats
@onready var _ai_heading: Label = %AIReportHeading
@onready var _ai_stats: Label = %AIReportStats
@onready var _match_log_text: Label = %FullMatchLog
@onready var _match_log_scroll: ScrollContainer = %FullMatchLogScroll
@onready var _status: Label = %ExportStatus
@onready var _export_button: Button = %ExportReportButton
@onready var _new_match_button: Button = %NewMatchButton
@onready var _return_button: Button = %ReturnToMatchButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_export_button.pressed.connect(_export_text_report)
	_new_match_button.pressed.connect(_on_new_match_pressed)
	_return_button.pressed.connect(_return_to_match)
	# The complete report uses one authoritative vertical scroller. The inner
	# match-log container is retained for scene compatibility but must not capture
	# mobile drags from the outer report page.
	_match_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_match_log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_match_log_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match_log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, _effective_size: Vector2) -> void:
	var phone_layout := mode == ResponsiveUI.LayoutMode.PHONE
	_header_row.vertical = phone_layout
	_stats_row.vertical = phone_layout
	_report_buttons.vertical = phone_layout
	var horizontal_margin := int(ResponsiveUI.choose(12, 24, 42))
	var vertical_margin := int(ResponsiveUI.choose(10, 18, 28))
	_outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	_outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	_header_row.add_theme_constant_override("separation", int(ResponsiveUI.choose(10, 18, 22)))
	_stats_row.add_theme_constant_override("separation", int(ResponsiveUI.choose(10, 14, 18)))


func open_report(report: Dictionary) -> void:
	_report = report.duplicate(true)
	latest_export_path = ""
	_export_button.disabled = false
	_title.text = str(_report.get("title", "MATCH REPORT"))
	_subtitle.text = str(_report.get("subtitle", "Full one-on-one match overview"))
	_winner_value.text = str(_report.get("winner", "Not Set"))
	_result_value.text = str(_report.get("result", "Not Set"))
	_time_value.text = str(_report.get("final_time", "00:00"))
	_finish_move_value.text = str(_report.get("finish_move", "None"))
	_setup_method_value.text = "%s\n%s" % [
		str(_report.get("match_setup", "Manual")),
		str(_report.get("rules_summary", "Rules not recorded")),
	]
	_locks_value.text = "Player %s / AI %s" % [
		"Locked" if bool(_report.get("player_locked", false)) else "Open",
		"Locked" if bool(_report.get("ai_locked", false)) else "Open",
	]
	_randomized_value.text = "Player %s / AI %s" % [
		"Yes" if bool(_report.get("player_randomly_selected", false)) else "No",
		"Yes" if bool(_report.get("ai_randomly_selected", false)) else "No",
	]
	var player_stats: Dictionary = _report.get("player", {})
	var ai_stats: Dictionary = _report.get("ai", {})
	_player_heading.text = str(player_stats.get("heading", "PLAYER"))
	_ai_heading.text = str(ai_stats.get("heading", "AI"))
	_player_stats.text = _format_side_stats(player_stats)
	_ai_stats.text = _format_side_stats(ai_stats)
	var log_lines: Array = _report.get("log_lines", [])
	var rendered_log := PackedStringArray()
	for log_line in log_lines:
		rendered_log.append(str(log_line))
	_match_log_text.text = "\n".join(rendered_log) if not rendered_log.is_empty() else "No match log entries were recorded."
	_status.text = ""
	visible = true
	await get_tree().process_frame
	_page_scroll.scroll_vertical = 0
	_match_log_scroll.scroll_vertical = 0
	_return_button.grab_focus()


func close_report() -> void:
	_reset_touch_scroll()
	visible = false


func _input(event: InputEvent) -> void:
	if not visible or not is_instance_valid(_page_scroll):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _page_scroll.get_global_rect().has_point(touch.position):
				_touch_scroll_active = true
				_touch_scroll_index = touch.index
				_touch_scroll_distance = 0.0
		elif _touch_scroll_active and touch.index == _touch_scroll_index:
			_reset_touch_scroll()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touch_scroll_active or drag.index != _touch_scroll_index:
			return
		_touch_scroll_distance += absf(drag.relative.y)
		if _touch_scroll_distance < TOUCH_SCROLL_DEADZONE:
			return
		_page_scroll.scroll_vertical -= roundi(drag.relative.y)
		get_viewport().set_input_as_handled()


func _reset_touch_scroll() -> void:
	_touch_scroll_active = false
	_touch_scroll_index = -1
	_touch_scroll_distance = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_return_to_match()
		get_viewport().set_input_as_handled()


func _return_to_match() -> void:
	close_report()
	return_requested.emit()


func _on_new_match_pressed() -> void:
	close_report()
	new_match_requested.emit()


func _export_text_report() -> void:
	if _report.is_empty():
		_status.text = "There is no completed match report to export."
		return
	var report_filename := _build_report_filename()
	if OS.has_feature("android"):
		_export_android_report(report_filename)
		return
	_export_report_to_user_directory(report_filename)


func _export_android_report(report_filename: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_status.text = "The Android document picker is unavailable. Saving inside the app instead."
		_export_report_to_user_directory(report_filename)
		return
	_export_button.disabled = true
	_status.text = "Choose where to save the match report."
	var dialog_error := DisplayServer.file_dialog_show(
		"Save Match Report",
		"",
		report_filename,
		false,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.txt;Text Report;text/plain"]),
		_on_android_report_destination_selected,
	)
	if dialog_error != OK:
		_export_button.disabled = false
		_status.text = "The Android document picker could not open. Saving inside the app instead."
		_export_report_to_user_directory(report_filename)


func _on_android_report_destination_selected(
	status: bool,
	selected_paths: PackedStringArray,
	_selected_filter_index: int,
) -> void:
	_export_button.disabled = false
	if not status or selected_paths.is_empty():
		_status.text = "Export cancelled."
		return
	var selected_uri := selected_paths[0]
	if _write_report_file(selected_uri):
		latest_export_path = selected_uri
		_status.text = "Match report saved to the selected Android location."
	else:
		_status.text = "The match report could not be written to that location."


func _export_report_to_user_directory(report_filename: String) -> void:
	var user_directory := DirAccess.open("user://")
	if user_directory == null:
		_status.text = "Could not open the game's user data folder."
		return
	var directory_error := user_directory.make_dir_recursive("match_reports")
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_status.text = "Could not create the match_reports folder."
		return
	var report_path := "%s/%s" % [REPORT_DIRECTORY, report_filename]
	if not _write_report_file(report_path):
		_status.text = "The match report could not be written."
		return
	latest_export_path = ProjectSettings.globalize_path(report_path)
	_status.text = "Saved: %s" % latest_export_path


func _write_report_file(report_path: String) -> bool:
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		return false
	report_file.store_string(str(_report.get("export_text", "")))
	report_file.close()
	return true


func _build_report_filename() -> String:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var file_stem := _safe_filename(str(_report.get("file_stem", "match_report")))
	return "%s_%s.txt" % [file_stem, timestamp]


func _format_side_stats(stats: Dictionary) -> String:
	return "\n".join([
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
		"Weapons: %d retrieved | %d attempted | %d landed | %d reversed" % [
			int(stats.get("weapons_retrieved", 0)),
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
		"Weapon aftermath: %d dropped | %d broken | Bleeding caused %d | Final bleeding %s" % [
			int(stats.get("weapons_dropped", 0)),
			int(stats.get("weapons_broken", 0)),
			int(stats.get("bleeding_caused", 0)),
			str(stats.get("final_bleeding", "None")),
		],
		"Tables: %d set | %d stacked | %d broken | %d delivered / %d taken" % [int(stats.get("tables_set", 0)), int(stats.get("tables_stacked", 0)), int(stats.get("tables_broken", 0)), int(stats.get("table_spots_landed", 0)), int(stats.get("table_spots_taken", 0))],
		"Ladders: %d set | %d stages | %d interrupted | %d dives | %d crashes" % [int(stats.get("ladder_setups", 0)), int(stats.get("ladder_climb_stages", 0)), int(stats.get("ladder_climbs_interrupted", 0)), int(stats.get("ladder_dives", 0)), int(stats.get("ladder_crashes", 0))],
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
		"Move variety: %d    Top move: %s" % [int(stats.get("move_variety", 0)), str(stats.get("top_move", "None"))],
		"Average impact: %.1f    Setup chains: %d" % [float(stats.get("average_impact", 0.0)), int(stats.get("setup_followup_chains", 0))],
		"Landing rate: %.1f%%    Reversal rate: %.1f%%" % [
			float(stats.get("move_landing_rate", 0.0)),
			float(stats.get("reversal_success_rate", 0.0)),
		],
		_execution_report_line(stats),
		"Reversal checks: %d attempted / %d successful" % [int(stats.get("response_attempts", 0)), int(stats.get("response_successes", 0))],
		"Avg reversal chance: %.1f%%    Finish pressure: %+.1f" % [
			float(stats.get("average_response_profile", 0.0)),
			float(stats.get("average_finish_pressure", 0.0)),
		],
		"Reversal checks / high-risk attempts: %d / %d    Repeat penalties: %d" % [
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
		"Intent: %d created | %d completed | %d abandoned" % [
			int(stats.get("setup_intents_created", 0)),
			int(stats.get("setup_intents_completed", 0)),
			int(stats.get("setup_intents_abandoned", 0)),
		],
		"Flow guards: %d dead ends | %d forced fallbacks | %d mandatory recoveries | late pressure %.1f" % [
			int(stats.get("dead_end_setups_prevented", 0)),
			int(stats.get("forced_fallbacks", 0)),
			int(stats.get("mandatory_recoveries", 0)),
			float(stats.get("average_late_escalation", 0.0)),
		],
		"Target focus: %s (%s)    Most used: %s" % [
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
		"Damage thresholds: %s    At zero: %s" % [
			str(stats.get("thresholds_crossed", "None")),
			str(stats.get("parts_reaching_zero", "None")),
		],
		"Submission target: %s (HP %s at lock-in / %s at resolution) | Finisher target: %s" % [
			str(stats.get("last_submission_target", "None")),
			_submission_hp_label(stats.get("last_submission_target_hp_at_lock_in", -1.0)),
			_submission_hp_label(stats.get("last_submission_target_hp_at_resolution", -1.0)),
			str(stats.get("last_finisher_target", "None")),
		],
		"Repeated targeting: %s" % str(stats.get("targeting_milestones", "None")),
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
		"Submission struggles: %d wins / %d losses / %.1fs" % [
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
		"Exhaustion actions: %d at zero stamina / %d successful | %d high-risk | %d demanding weapons" % [
			int(stats.get("zero_stamina_attempts", 0)),
			int(stats.get("zero_stamina_successes", 0)),
			int(stats.get("exhausted_high_risk_attempts", 0)),
			int(stats.get("exhausted_demanding_weapon_attempts", 0)),
		],
		"Recovery: %d Catch Breath | %.1f stamina restored | %d delayed recoveries | %d control losses" % [
			int(stats.get("catch_breath_uses", 0)),
			float(stats.get("total_stamina_recovered", 0.0)),
			int(stats.get("delayed_recoveries", 0)),
			int(stats.get("exhaustion_control_losses", 0)),
		],
		"Average exhaustion tuning: %.1f%% execution penalty | %.2fx fatigue amplification" % [
			float(stats.get("average_stamina_execution_penalty", 0.0)),
			float(stats.get("average_fatigue_amplification", 1.0)),
		],
		"Damage dealt / taken: %.1f / %.1f" % [float(stats.get("damage_dealt", 0.0)), float(stats.get("damage_taken", 0.0))],
		"Stamina: %.1f / %.1f (%.0f%%)    Fatigue: %.0f%%" % [
			float(stats.get("stamina", 0.0)),
			float(stats.get("max_stamina", 100.0)),
			float(stats.get("stamina_percent", 0.0)),
			float(stats.get("fatigue", 0.0)),
		],
		"Momentum: %.0f%%    Position: %s" % [float(stats.get("momentum", 0.0)), str(stats.get("position", "Not Set"))],
		"HP — Head %.0f | Body %.0f" % [float(stats.get("head_hp", 0.0)), float(stats.get("body_hp", 0.0))],
		"Arms — L %.0f | R %.0f" % [float(stats.get("left_arm_hp", 0.0)), float(stats.get("right_arm_hp", 0.0))],
		"Legs — L %.0f | R %.0f" % [float(stats.get("left_leg_hp", 0.0)), float(stats.get("right_leg_hp", 0.0))],
	])


func _execution_report_line(stats: Dictionary) -> String:
	if str(stats.get("execution_mode", "meter")) == "automatic_reversal_only":
		return "Execution: Automatic — defender reversal only"
	return "Execution meter: %d attempted / %d successful" % [
		int(stats.get("execution_attempts", 0)),
		int(stats.get("execution_successes", 0)),
	]


func _submission_hp_label(value: Variant) -> String:
	var hp := float(value)
	return "N/A" if hp < 0.0 else "%d%%" % int(roundf(hp))


func _safe_filename(value: String) -> String:
	var cleaned := value.strip_edges().to_lower().replace(" ", "_")
	var safe := ""
	for character in cleaned:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe += character
	return "match_report" if safe.is_empty() else safe
