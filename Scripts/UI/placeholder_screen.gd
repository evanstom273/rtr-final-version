extends Control
class_name PlaceholderScreen

signal back_requested

@onready var _title: Label = %PlaceholderTitle
@onready var _message: Label = %PlaceholderMessage
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_back_button.grab_focus()


func configure(title: String, message: String) -> void:
	if not is_node_ready():
		await ready
	_title.text = title
	_message.text = message


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

