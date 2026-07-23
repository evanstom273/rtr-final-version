extends Control
class_name MatchPauseMenu

signal resumed
signal return_to_exhibition_requested
signal return_to_main_menu_requested

var _tree_was_paused := false

@onready var _resume_button: Button = %ResumeButton
@onready var _exhibition_button: Button = %ReturnToExhibitionButton
@onready var _main_menu_button: Button = %ReturnToMainMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(close_menu)
	_exhibition_button.pressed.connect(_return_to_exhibition)
	_main_menu_button.pressed.connect(_return_to_main_menu)
	visible = false


func open_menu() -> void:
	if visible:
		return
	_tree_was_paused = get_tree().paused
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _tree_was_paused
	resumed.emit()


func force_close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _tree_was_paused


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()


func _return_to_exhibition() -> void:
	force_close()
	return_to_exhibition_requested.emit()


func _return_to_main_menu() -> void:
	force_close()
	return_to_main_menu_requested.emit()
