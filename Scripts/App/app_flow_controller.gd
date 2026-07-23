extends Control
class_name AppFlowController

const MAIN_MENU_SCENE: PackedScene = preload("res://Scenes/UI/main_menu.tscn")
const EXHIBITION_SCENE: PackedScene = preload("res://Scenes/Match/exhibition_flow.tscn")
const MATCH_REPORT_ARCHIVE_SCENE: PackedScene = preload("res://Scenes/UI/match_report_archive_screen.tscn")
const PLACEHOLDER_SCENE: PackedScene = preload("res://Scenes/UI/placeholder_screen.tscn")
const FADE_TIME := 0.28
const LOADING_FADE_TIME := 0.16
const LOADING_SETTLE_TIME := 0.12

var _current_screen: Control
var _transitioning := false

@onready var _screen_container: Control = %CurrentScreen
@onready var _fade: ColorRect = %FadeToBlack
@onready var _loading_overlay: Control = %LoadingOverlay
@onready var _loading_label: Label = %LoadingLabel
@onready var _loading_bar: ProgressBar = %LoadingBar


func _ready() -> void:
	_fade.visible = true
	_fade.modulate.a = 1.0
	_show_main_menu(true)


func _show_main_menu(immediate := false) -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as MainMenu
	menu.career_requested.connect(func() -> void:
		_show_placeholder("CAREER", "Career mode is not wired in yet. This screen is ready for the future career hub.")
	)
	menu.exhibition_requested.connect(func() -> void:
		_show_exhibition()
	)
	menu.database_requested.connect(func() -> void:
		_show_placeholder("DATABASE", "The wrestler, promotion, title and move database will live here.")
	)
	menu.match_reports_requested.connect(func() -> void:
		_show_match_reports()
	)
	menu.settings_requested.connect(func() -> void:
		_show_placeholder("SETTINGS", "Settings are not wired in yet. This will become the options and accessibility screen.")
	)
	menu.quit_requested.connect(_quit_game)
	_set_screen(menu, immediate)


func _show_exhibition() -> void:
	_transition_to_scene(EXHIBITION_SCENE, "LOADING EXHIBITION")


func _show_match_reports() -> void:
	_transition_to_scene(MATCH_REPORT_ARCHIVE_SCENE, "LOADING MATCH HISTORY")


func _show_placeholder(title: String, message: String) -> void:
	var placeholder := PLACEHOLDER_SCENE.instantiate() as PlaceholderScreen
	placeholder.back_requested.connect(func() -> void:
		_show_main_menu()
	)
	placeholder.configure(title, message)
	_set_screen(placeholder)


func _transition_to_scene(scene: PackedScene, loading_text: String) -> void:
	if scene == null or _transitioning:
		return
	_transitioning = true
	await _fade_to(1.0)
	_show_loading(loading_text, 8.0)
	await get_tree().process_frame
	_set_loading_progress(32.0)
	var next_screen := scene.instantiate() as Control
	if next_screen is ExhibitionFlowController:
		(next_screen as ExhibitionFlowController).main_menu_requested.connect(func() -> void:
			_show_main_menu()
		)
	elif next_screen is MatchReportArchiveScreen:
		(next_screen as MatchReportArchiveScreen).back_requested.connect(func() -> void:
			_show_main_menu()
		)
	_set_loading_progress(72.0)
	await get_tree().process_frame
	_replace_screen(next_screen)
	_set_loading_progress(100.0)
	await get_tree().create_timer(LOADING_SETTLE_TIME).timeout
	await _fade_loading_out()
	await _fade_to(0.0)
	_transitioning = false


func _set_screen(next_screen: Control, immediate := false) -> void:
	if next_screen == null or _transitioning:
		if next_screen != null:
			next_screen.queue_free()
		return
	_transitioning = true
	if immediate:
		_replace_screen(next_screen)
		_fade.modulate.a = 1.0
		_hide_loading()
		await _fade_to(0.0)
		_transitioning = false
		return
	await _fade_to(1.0)
	_replace_screen(next_screen)
	_hide_loading()
	await _fade_to(0.0)
	_transitioning = false


func _replace_screen(next_screen: Control) -> void:
	if _current_screen != null:
		if _current_screen.has_method("prepare_for_scene_exit"):
			_current_screen.call("prepare_for_scene_exit")
		_current_screen.queue_free()
	_current_screen = next_screen
	_screen_container.add_child(_current_screen)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished


func _show_loading(text: String, progress: float) -> void:
	_loading_label.text = text
	_loading_bar.value = clampf(progress, 0.0, 100.0)
	_loading_overlay.modulate.a = 1.0
	_loading_overlay.visible = true


func _set_loading_progress(progress: float) -> void:
	_loading_bar.value = clampf(progress, 0.0, 100.0)


func _hide_loading() -> void:
	_loading_overlay.visible = false
	_loading_overlay.modulate.a = 1.0
	_loading_bar.value = 0.0


func _fade_loading_out() -> void:
	if not _loading_overlay.visible:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_loading_overlay, "modulate:a", 0.0, LOADING_FADE_TIME)
	await tween.finished
	_hide_loading()


func _quit_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	await _fade_to(1.0)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _transitioning:
		return
	if (
		_current_screen is ExhibitionFlowController
		and (_current_screen as ExhibitionFlowController).handle_app_cancel()
	):
		get_viewport().set_input_as_handled()
		return
	if _current_screen is MainMenu:
		_quit_game()
	else:
		_show_main_menu()
	get_viewport().set_input_as_handled()
