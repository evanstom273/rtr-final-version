extends Control
class_name MainMenu

signal career_requested
signal exhibition_requested
signal database_requested
signal match_reports_requested
signal settings_requested
signal quit_requested

@onready var _career_button: Button = %CareerButton
@onready var _exhibition_button: Button = %ExhibitionButton
@onready var _database_button: Button = %DatabaseButton
@onready var _match_reports_button: Button = %MatchReportsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_career_button.pressed.connect(func() -> void: career_requested.emit())
	_exhibition_button.pressed.connect(func() -> void: exhibition_requested.emit())
	_database_button.pressed.connect(func() -> void: database_requested.emit())
	_match_reports_button.pressed.connect(func() -> void: match_reports_requested.emit())
	_settings_button.pressed.connect(func() -> void: settings_requested.emit())
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_exhibition_button.grab_focus()

