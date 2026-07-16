extends Control
class_name MatchResultPopup

signal view_report_requested
signal new_match_requested
signal closed

const INPUT_LOCK_SECONDS := 0.75

var _input_locked: bool = false
var _open_generation: int = 0

@onready var _safe_area: MarginContainer = %ResultSafeArea
@onready var _outer_margin: MarginContainer = %ResultOuterMargin
@onready var _panel: PanelContainer = %ResultPanel
@onready var _buttons: BoxContainer = %ResultButtons
@onready var _winner: Label = %WinnerValue
@onready var _result: Label = %ResultValue
@onready var _final_time: Label = %FinalTimeValue
@onready var _finish: Label = %FinishValue
@onready var _winner_stats: Label = %WinnerStats
@onready var _view_report_button: Button = %ViewFullReportButton
@onready var _new_match_button: Button = %NewMatchButton
@onready var _close_button: Button = %CloseResultButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_view_report_button.pressed.connect(_on_view_report_pressed)
	_new_match_button.pressed.connect(_on_new_match_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, _effective_size: Vector2) -> void:
	var phone_layout := mode == ResponsiveUI.LayoutMode.PHONE
	_buttons.vertical = phone_layout
	_panel.custom_minimum_size = Vector2(
		float(ResponsiveUI.choose(440, 540, 600)),
		float(ResponsiveUI.choose(390, 410, 430)),
	)
	var horizontal_margin := int(ResponsiveUI.choose(12, 22, 30))
	var vertical_margin := int(ResponsiveUI.choose(10, 18, 24))
	_outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	_outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	_buttons.add_theme_constant_override("separation", int(ResponsiveUI.choose(8, 12, 14)))


func open_result(summary: Dictionary) -> void:
	_open_generation += 1
	var generation := _open_generation
	_input_locked = true
	_view_report_button.disabled = true
	_new_match_button.disabled = true
	_close_button.disabled = true
	_view_report_button.release_focus()
	_new_match_button.release_focus()
	_close_button.release_focus()
	_winner.text = str(summary.get("winner", "Not Set"))
	_result.text = str(summary.get("result", "Not Set"))
	_final_time.text = str(summary.get("final_time", "00:00"))
	_finish.text = str(summary.get("finish_move", "None"))
	_winner_stats.text = "Damage dealt: %.1f    Reversals: %d" % [
		float(summary.get("damage_dealt", 0.0)),
		int(summary.get("reversals", 0)),
	]
	visible = true
	await get_tree().process_frame
	await get_tree().create_timer(INPUT_LOCK_SECONDS).timeout
	if not visible or generation != _open_generation:
		return
	_input_locked = false
	_view_report_button.disabled = false
	_new_match_button.disabled = false
	_close_button.disabled = false
	_view_report_button.grab_focus()


func close_result() -> void:
	_open_generation += 1
	_input_locked = false
	_view_report_button.disabled = false
	_new_match_button.disabled = false
	_close_button.disabled = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if not _input_locked:
			_on_close_pressed()
		get_viewport().set_input_as_handled()


func _on_view_report_pressed() -> void:
	if not visible or _input_locked:
		return
	close_result()
	view_report_requested.emit()


func _on_new_match_pressed() -> void:
	if not visible or _input_locked:
		return
	close_result()
	new_match_requested.emit()


func _on_close_pressed() -> void:
	if not visible or _input_locked:
		return
	close_result()
	closed.emit()
