extends Control
class_name MoveCategoryRadialMenu

signal category_selected(category_id: int)
signal cancelled()

const CategoryItemScene := preload("res://Scenes/Match/move_category_item.tscn")
const OPEN_SECONDS := 0.14
const CLOSE_SECONDS := 0.10
const START_ANGLE := -PI * 0.5

var _category_data: Array[Dictionary] = []
var _items: Array[MoveCategoryItem] = []
var _item_size := Vector2(190, 74)
var _badge_size := Vector2(230, 120)
var _input_enabled: bool = false
var _animation_generation: int = 0
var _active_tween: Tween

@onready var _dismiss_area: Button = %DismissArea
@onready var _safe_area: MarginContainer = %CategorySafeArea
@onready var _wheel_panel: PanelContainer = %WheelPanel
@onready var _wheel_area: Control = %WheelArea
@onready var _guide: Control = %WheelGuide
@onready var _category_layer: Control = %CategoryLayer
@onready var _center_badge: Panel = %CenterBadge
@onready var _context_label: Label = %ContextLabel
@onready var _close_button: Button = %WheelCloseButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_dismiss_area.pressed.connect(request_cancel)
	_close_button.pressed.connect(request_cancel)
	_wheel_area.resized.connect(_queue_layout)
	_guide.draw.connect(_draw_wheel_guide)
	_context_label.clip_text = true
	_context_label.max_lines_visible = 4
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var portrait := effective_size.y > effective_size.x
	var panel_size := Vector2(980, 780)
	match mode:
		ResponsiveUI.LayoutMode.PHONE:
			if portrait:
				panel_size = Vector2(
					clampf(effective_size.x - 32.0, 620.0, 700.0),
					clampf(effective_size.y - 32.0, 760.0, 920.0),
				)
				_item_size = Vector2(154, 68)
				_badge_size = Vector2(205, 112)
			else:
				panel_size = Vector2(
					clampf(effective_size.x - 32.0, 900.0, 1180.0),
					clampf(effective_size.y - 24.0, 500.0, 620.0),
				)
				_item_size = Vector2(174, 60)
				_badge_size = Vector2(220, 100)
		ResponsiveUI.LayoutMode.TABLET:
			panel_size = Vector2(
				minf(900.0, effective_size.x - 40.0),
				minf(760.0, effective_size.y - 40.0),
			)
			_item_size = Vector2(176, 70)
			_badge_size = Vector2(220, 116)
		_:
			_item_size = Vector2(190, 74)
			_badge_size = Vector2(230, 120)
	_wheel_panel.custom_minimum_size = panel_size
	_wheel_area.custom_minimum_size = panel_size
	_queue_layout()


func set_menu_data(
	categories: Array[Dictionary],
	attacker_position_label: String,
	target_position_label: String,
) -> void:
	_category_data.clear()
	for category in categories:
		_category_data.append(category.duplicate(true))
	_context_label.text = "%s vs %s" % [attacker_position_label, target_position_label]
	_rebuild_items()


func show_menu() -> void:
	_animation_generation += 1
	var generation := _animation_generation
	_kill_tween()
	visible = true
	_input_enabled = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	call_deferred("_play_open_animation", generation)


func close_menu(immediate: bool = true) -> void:
	_animation_generation += 1
	var generation := _animation_generation
	_input_enabled = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	if immediate or not visible:
		visible = false
		_wheel_panel.scale = Vector2.ONE
		_wheel_panel.modulate = Color.WHITE
		return
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_wheel_panel, "scale", Vector2(0.97, 0.97), CLOSE_SECONDS)
	_active_tween.tween_property(_wheel_panel, "modulate:a", 0.0, CLOSE_SECONDS)
	await _active_tween.finished
	if generation == _animation_generation:
		visible = false


func request_cancel() -> void:
	if not visible or not _input_enabled:
		return
	_input_enabled = false
	await close_menu(false)
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		request_cancel()
		get_viewport().set_input_as_handled()


func _play_open_animation(generation: int) -> void:
	if generation != _animation_generation or not visible:
		return
	_layout_items()
	_wheel_panel.pivot_offset = _wheel_panel.size * 0.5
	_wheel_panel.scale = Vector2(0.96, 0.96)
	_wheel_panel.modulate = Color(1, 1, 1, 0)
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_wheel_panel, "scale", Vector2.ONE, OPEN_SECONDS)
	_active_tween.tween_property(_wheel_panel, "modulate:a", 1.0, OPEN_SECONDS)
	_focus_first_enabled()


func _rebuild_items() -> void:
	for child in _category_layer.get_children():
		_category_layer.remove_child(child)
		child.queue_free()
	_items.clear()
	for data in _category_data:
		var item := CategoryItemScene.instantiate() as MoveCategoryItem
		_category_layer.add_child(item)
		item.set_category_data(data)
		item.category_activated.connect(_on_category_activated.bind(item))
		_items.append(item)
	_queue_layout()


func _on_category_activated(category_id: int, item: MoveCategoryItem) -> void:
	if not _input_enabled or not visible:
		return
	var matching_data := _data_for_category(category_id)
	if matching_data.is_empty() or not bool(matching_data.get("enabled", false)):
		return
	_input_enabled = false
	var generation := _animation_generation
	await item.play_selection_pulse()
	if generation == _animation_generation and visible:
		category_selected.emit(category_id)


func _data_for_category(category_id: int) -> Dictionary:
	for data in _category_data:
		if int(data.get("id", -1)) == category_id:
			return data
	return {}


func _queue_layout() -> void:
	if not is_node_ready():
		return
	call_deferred("_layout_items")


func _layout_items() -> void:
	if not is_node_ready() or _wheel_area.size.x <= 0.0 or _wheel_area.size.y <= 0.0:
		return
	var center := _wheel_area.size * 0.5
	var radii := _wheel_radii()
	var item_count := _items.size()
	for index in range(item_count):
		var item := _items[index]
		var angle := START_ANGLE + TAU * float(index) / float(maxi(1, item_count))
		var item_center := center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		item.custom_minimum_size = _item_size
		item.size = _item_size
		item.position = item_center - _item_size * 0.5
		item.pivot_offset = _item_size * 0.5
	_center_badge.custom_minimum_size = _badge_size
	_center_badge.size = _badge_size
	_center_badge.position = center - _badge_size * 0.5
	_close_button.position = Vector2(_wheel_area.size.x - 62.0, 14.0)
	_link_focus_neighbors()
	_guide.queue_redraw()


func _wheel_radii() -> Vector2:
	return Vector2(
		maxf(100.0, _wheel_area.size.x * 0.5 - _item_size.x * 0.5 - 18.0),
		maxf(100.0, _wheel_area.size.y * 0.5 - _item_size.y * 0.5 - 44.0),
	)


func _draw_wheel_guide() -> void:
	if _guide.size.x <= 0.0 or _guide.size.y <= 0.0:
		return
	var center := _guide.size * 0.5
	var radii := _wheel_radii() + _item_size * Vector2(0.26, 0.22)
	var outer := _ellipse_points(center, radii, 72)
	_guide.draw_colored_polygon(outer, AppThemePalette.with_alpha(AppThemePalette.MAIN_BACKGROUND, 0.96))
	var outline := PackedVector2Array(outer)
	outline.append(outer[0])
	_guide.draw_polyline(outline, AppThemePalette.with_alpha(AppThemePalette.BORDER, 0.62), 2.0, true)
	var inner := _ellipse_points(center, radii * 0.58, 72)
	inner.append(inner[0])
	_guide.draw_polyline(inner, AppThemePalette.with_alpha(AppThemePalette.BORDER, 0.34), 1.0, true)
	for index in range(_items.size()):
		var angle := START_ANGLE + TAU * float(index) / float(maxi(1, _items.size()))
		var endpoint := center + Vector2(cos(angle) * radii.x * 0.78, sin(angle) * radii.y * 0.78)
		_guide.draw_line(center, endpoint, AppThemePalette.with_alpha(AppThemePalette.BORDER, 0.18), 1.0, true)


func _ellipse_points(center: Vector2, radii: Vector2, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(point_count):
		var angle := TAU * float(index) / float(point_count)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _link_focus_neighbors() -> void:
	var enabled_items: Array[MoveCategoryItem] = []
	for item in _items:
		if not item.disabled:
			enabled_items.append(item)
	if enabled_items.is_empty():
		return
	for index in range(enabled_items.size()):
		var item := enabled_items[index]
		var previous := enabled_items[posmod(index - 1, enabled_items.size())]
		var next := enabled_items[(index + 1) % enabled_items.size()]
		item.focus_neighbor_left = item.get_path_to(previous)
		item.focus_neighbor_top = item.get_path_to(previous)
		item.focus_previous = item.get_path_to(previous)
		item.focus_neighbor_right = item.get_path_to(next)
		item.focus_neighbor_bottom = item.get_path_to(next)
		item.focus_next = item.get_path_to(next)


func _focus_first_enabled() -> void:
	for item in _items:
		if not item.disabled:
			item.grab_focus()
			return
	_close_button.grab_focus()


func _kill_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
