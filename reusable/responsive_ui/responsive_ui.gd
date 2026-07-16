## Portable responsive UI service for Godot 4.x.
##
## INSTALL
## 1. Copy this file into another Godot project.
## 2. Add it in Project > Project Settings > Globals/Autoload.
## 3. Name the autoload ResponsiveUI.
## 4. Register responsive scene roots with register_layout_target(), or add
##    them to the "responsive_ui" group and implement:
##       set_responsive_layout(mode: int, effective_size: Vector2) -> void
## 5. Put a dedicated MarginContainer in the "responsive_safe_area" group,
##    or register it with register_safe_area().
##
## This service never creates UI nodes. It scales the authored canvas, detects
## the device class, applies safe-area margins, and tells authored scenes when
## they should reflow their existing containers.
extends Node

signal compact_mode_changed(compact: bool)
signal responsive_layout_changed(mode: int, effective_size: Vector2)
signal orientation_changed(portrait: bool)
signal content_scale_changed(scale_factor: float)
signal safe_area_changed(margins: Vector4)
signal layout_preview_changed(enabled: bool, mode: int)

enum LayoutMode { PHONE, TABLET, DESKTOP }

## --------------------------------------------------------------------------
## TUNING
## --------------------------------------------------------------------------

## Match this to the resolution your authored Control scenes use.
const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)

## When enabled, this autoload configures the root Window for Control-node UI.
## Disable it if a project deliberately uses viewport scaling or pixel art.
const CONFIGURE_ROOT_STRETCH: bool = true

## DPI-adjusted sizes below either phone limit use Phone mode.
const PHONE_MIN_LOGICAL_WIDTH: float = 600.0
const PHONE_MIN_LOGICAL_HEIGHT: float = 600.0

## A landscape window meeting both limits uses Desktop mode. Everything
## between Phone and Desktop is Tablet mode, including unfolded square screens.
const DESKTOP_MIN_LOGICAL_WIDTH: float = 1100.0
const DESKTOP_MIN_LOGICAL_HEIGHT: float = 620.0

## These values enlarge a 1920x1080 authored canvas on compact devices.
## A larger value produces larger UI and less logical canvas space.
const PHONE_PORTRAIT_CONTENT_SCALE: float = 2.85
const TABLET_CONTENT_SCALE: float = 1.25
const DESKTOP_CONTENT_SCALE: float = 1.0

## Phone landscape is calculated from physical size and DPI, then clamped.
const PHONE_LANDSCAPE_MIN_SCALE: float = 1.0
const PHONE_LANDSCAPE_MAX_SCALE: float = 4.0
const TARGET_MIN_PHYSICAL_SCALE: float = 0.70
const ANDROID_BASE_DPI: float = 160.0
const FALLBACK_MOBILE_DPI: float = 320.0
const DENSITY_CONVERSION_MIN_DPI: float = 180.0
const UI_DENSITY_REFERENCE_DPI: float = 329.23

## Optional minimum portrait insets, useful on devices whose reported safe
## area omits a camera cutout or gesture bar.
const PORTRAIT_MIN_TOP_INSET: float = 28.0
const PORTRAIT_MIN_BOTTOM_INSET: float = 20.0

## Groups provide a no-code registration path through the Godot editor.
const RESPONSIVE_GROUP: StringName = &"responsive_ui"
const SAFE_AREA_GROUP: StringName = &"responsive_safe_area"

## Desktop preview sizes. Preview is intentionally unavailable in exports
## running with the mobile feature tag.
const PREVIEW_PHONE_DEVICE_SIZE: Vector2 = Vector2(390.0, 844.0)
const PREVIEW_TABLET_DEVICE_SIZE: Vector2 = Vector2(880.0, 880.0)
const PREVIEW_DESKTOP_DEVICE_SIZE: Vector2 = Vector2(1280.0, 720.0)
const PREVIEW_PHONE_WINDOW_SIZE: Vector2i = Vector2i(675, 1200)
const PREVIEW_TABLET_WINDOW_SIZE: Vector2i = Vector2i(1000, 1000)
const PREVIEW_DESKTOP_WINDOW_SIZE: Vector2i = Vector2i(1280, 720)

## Common authored spacing helpers. Change these to match a project's theme.
const PHONE_PAGE_MARGIN: int = 16
const TABLET_PAGE_MARGIN: int = 20
const DESKTOP_PAGE_MARGIN: int = 28

## --------------------------------------------------------------------------
## PUBLIC STATE
## --------------------------------------------------------------------------

var current_layout_mode: LayoutMode = LayoutMode.DESKTOP
var current_scale_factor: float = DESKTOP_CONTENT_SCALE
var is_compact_mode: bool = false
var is_portrait_orientation: bool = false
var density_adjusted_viewport_size: Vector2 = DESIGN_SIZE
var effective_viewport_size: Vector2 = DESIGN_SIZE
var safe_area_margins: Vector4 = Vector4.ZERO

var layout_preview_enabled: bool = false
var layout_preview_mode: LayoutMode = LayoutMode.TABLET

var _applying: bool = false
var _refresh_queued: bool = false
var _layout_targets: Array[WeakRef] = []
var _safe_area_targets: Array[WeakRef] = []
var _preview_window_transitioning: bool = false
var _preview_original_window_size: Vector2i = Vector2i.ZERO
var _preview_original_window_position: Vector2i = Vector2i.ZERO
var _preview_original_window_mode: Window.Mode = Window.MODE_WINDOWED
var _preview_has_original_window: bool = false


func _ready() -> void:
	if CONFIGURE_ROOT_STRETCH:
		_configure_root_window()
	get_tree().root.size_changed.connect(_queue_refresh)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_refresh_from_window")


## Re-evaluates the real window. Call this after changing display settings.
func refresh() -> void:
	_queue_refresh()


## Useful for deterministic editor checks without needing a physical device.
## dpi_override <= 0 uses the current display DPI.
func apply_for_window_size(window_size: Vector2i, dpi_override: float = -1.0) -> void:
	if _applying or window_size.x <= 0 or window_size.y <= 0:
		return
	_applying = true

	var raw_size: Vector2 = Vector2(window_size)
	var dpi: float = dpi_override
	if dpi <= 0.0:
		dpi = float(DisplayServer.screen_get_dpi())
	if OS.has_feature("mobile") and dpi < DENSITY_CONVERSION_MIN_DPI:
		dpi = FALLBACK_MOBILE_DPI

	var device_size: Vector2 = raw_size
	if dpi >= DENSITY_CONVERSION_MIN_DPI:
		device_size = raw_size * (ANDROID_BASE_DPI / dpi)

	var portrait: bool = raw_size.y > raw_size.x
	var next_mode: LayoutMode = _classify_layout(device_size, not portrait)
	if layout_preview_enabled:
		next_mode = layout_preview_mode
		device_size = _get_preview_device_size(layout_preview_mode)

	var next_scale: float = _calculate_content_scale(next_mode, raw_size, dpi, portrait)
	var root_window: Window = get_tree().root
	if not is_equal_approx(root_window.content_scale_factor, next_scale):
		root_window.content_scale_factor = next_scale

	var next_effective_size: Vector2 = _calculate_layout_viewport_size(raw_size, next_scale)
	var next_safe_area: Vector4 = _calculate_safe_area(raw_size, next_effective_size, portrait)
	var next_compact: bool = next_mode != LayoutMode.DESKTOP
	var layout_changed: bool = next_mode != current_layout_mode \
		or not next_effective_size.is_equal_approx(effective_viewport_size)
	var scale_changed: bool = not is_equal_approx(next_scale, current_scale_factor)
	var portrait_changed: bool = portrait != is_portrait_orientation
	var safe_changed: bool = not next_safe_area.is_equal_approx(safe_area_margins)

	current_layout_mode = next_mode
	current_scale_factor = next_scale
	is_portrait_orientation = portrait
	density_adjusted_viewport_size = device_size
	effective_viewport_size = next_effective_size
	safe_area_margins = next_safe_area

	if next_compact != is_compact_mode:
		is_compact_mode = next_compact
		compact_mode_changed.emit(is_compact_mode)
	if portrait_changed:
		orientation_changed.emit(is_portrait_orientation)
	if scale_changed:
		content_scale_changed.emit(current_scale_factor)
	if safe_changed:
		safe_area_changed.emit(safe_area_margins)
	_apply_registered_safe_areas()
	if layout_changed or scale_changed:
		responsive_layout_changed.emit(current_layout_mode, effective_viewport_size)
		_apply_registered_layouts()

	_applying = false


func is_phone_mode() -> bool:
	return current_layout_mode == LayoutMode.PHONE


func is_tablet_mode() -> bool:
	return current_layout_mode == LayoutMode.TABLET


func is_desktop_mode() -> bool:
	return current_layout_mode == LayoutMode.DESKTOP


func is_portrait() -> bool:
	return is_portrait_orientation


func get_layout_name(mode: int = -1) -> String:
	var resolved_mode: int = current_layout_mode if mode < 0 else mode
	match resolved_mode:
		LayoutMode.PHONE:
			return "Phone"
		LayoutMode.TABLET:
			return "Tablet"
	return "Desktop"


## Returns one of three values using the active layout mode.
func choose(phone_value: Variant, tablet_value: Variant, desktop_value: Variant) -> Variant:
	match current_layout_mode:
		LayoutMode.PHONE:
			return phone_value
		LayoutMode.TABLET:
			return tablet_value
	return desktop_value


func get_column_count(phone_columns: int = 1, tablet_columns: int = 2, desktop_columns: int = 4) -> int:
	return int(choose(phone_columns, tablet_columns, desktop_columns))


func get_page_margin() -> int:
	return int(choose(PHONE_PAGE_MARGIN, TABLET_PAGE_MARGIN, DESKTOP_PAGE_MARGIN))


## Registered nodes are called immediately and whenever layout state changes.
## The target must implement set_responsive_layout(mode, effective_size).
func register_layout_target(target: Node) -> void:
	if target == null or _contains_target(_layout_targets, target):
		return
	_layout_targets.append(weakref(target))
	_apply_layout_to_target(target)


func unregister_layout_target(target: Node) -> void:
	_remove_target(_layout_targets, target)


## Use a dedicated MarginContainer, because these overrides replace its four
## margin constants with the current device-safe insets.
func register_safe_area(container: MarginContainer) -> void:
	if container == null or _contains_target(_safe_area_targets, container):
		return
	_safe_area_targets.append(weakref(container))
	apply_safe_area_to(container)


func unregister_safe_area(container: MarginContainer) -> void:
	_remove_target(_safe_area_targets, container)


func apply_safe_area_to(container: MarginContainer) -> void:
	if container == null:
		return
	container.add_theme_constant_override("margin_left", roundi(safe_area_margins.x))
	container.add_theme_constant_override("margin_top", roundi(safe_area_margins.y))
	container.add_theme_constant_override("margin_right", roundi(safe_area_margins.z))
	container.add_theme_constant_override("margin_bottom", roundi(safe_area_margins.w))


## --------------------------------------------------------------------------
## DESKTOP LAYOUT PREVIEW
## --------------------------------------------------------------------------

func is_layout_preview_available() -> bool:
	return not OS.has_feature("mobile")


func set_layout_preview(enabled: bool, mode: int = LayoutMode.TABLET) -> void:
	var normalized_mode: LayoutMode = clampi(mode, LayoutMode.PHONE, LayoutMode.DESKTOP) as LayoutMode
	if enabled and not is_layout_preview_available():
		return
	var enabled_changed: bool = enabled != layout_preview_enabled
	var mode_changed: bool = normalized_mode != layout_preview_mode
	if not enabled_changed and not mode_changed:
		return
	if enabled and not layout_preview_enabled:
		_capture_preview_window()
	layout_preview_enabled = enabled
	layout_preview_mode = normalized_mode
	if layout_preview_enabled:
		call_deferred("_apply_preview_window")
	elif enabled_changed:
		call_deferred("_restore_preview_window")
	else:
		_queue_refresh()
	layout_preview_changed.emit(layout_preview_enabled, layout_preview_mode)


## --------------------------------------------------------------------------
## INTERNALS
## --------------------------------------------------------------------------

func _configure_root_window() -> void:
	var root_window: Window = get_tree().root
	root_window.content_scale_size = Vector2i(roundi(DESIGN_SIZE.x), roundi(DESIGN_SIZE.y))
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _queue_refresh() -> void:
	if _refresh_queued or _preview_window_transitioning:
		return
	_refresh_queued = true
	call_deferred("_refresh_from_window")


func _refresh_from_window() -> void:
	_refresh_queued = false
	if _preview_window_transitioning:
		return
	apply_for_window_size(DisplayServer.window_get_size())


func _classify_layout(device_size: Vector2, landscape: bool) -> LayoutMode:
	if device_size.x < PHONE_MIN_LOGICAL_WIDTH or device_size.y < PHONE_MIN_LOGICAL_HEIGHT:
		return LayoutMode.PHONE
	if landscape \
		and device_size.x >= DESKTOP_MIN_LOGICAL_WIDTH \
		and device_size.y >= DESKTOP_MIN_LOGICAL_HEIGHT:
		return LayoutMode.DESKTOP
	return LayoutMode.TABLET


func _calculate_content_scale(mode: LayoutMode, raw_size: Vector2, dpi: float, portrait: bool) -> float:
	match mode:
		LayoutMode.PHONE:
			if portrait:
				return PHONE_PORTRAIT_CONTENT_SCALE
			var physical_scale: float = minf(
				raw_size.x / DESIGN_SIZE.x,
				raw_size.y / DESIGN_SIZE.y,
			)
			var readability_scale: float = TARGET_MIN_PHYSICAL_SCALE / maxf(0.01, physical_scale)
			var density_scale: float = 1.0
			if dpi >= DENSITY_CONVERSION_MIN_DPI:
				density_scale = maxf(1.0, snappedf(dpi / UI_DENSITY_REFERENCE_DPI, 0.01))
			return clampf(
				maxf(readability_scale, density_scale),
				PHONE_LANDSCAPE_MIN_SCALE,
				PHONE_LANDSCAPE_MAX_SCALE,
			)
		LayoutMode.TABLET:
			return TABLET_CONTENT_SCALE
	return DESKTOP_CONTENT_SCALE


func _calculate_layout_viewport_size(window_size: Vector2, scale_factor: float) -> Vector2:
	var safe_scale: float = maxf(0.01, scale_factor)
	var scaled_design: Vector2 = DESIGN_SIZE / safe_scale
	var window_aspect: float = window_size.x / maxf(1.0, window_size.y)
	var design_aspect: float = DESIGN_SIZE.x / DESIGN_SIZE.y
	if window_aspect > design_aspect:
		return Vector2(scaled_design.y * window_aspect, scaled_design.y)
	return Vector2(scaled_design.x, scaled_design.x / maxf(0.01, window_aspect))


func _calculate_safe_area(window_size: Vector2, canvas_size: Vector2, portrait: bool) -> Vector4:
	if not OS.has_feature("mobile") or window_size.x <= 0.0 or window_size.y <= 0.0:
		return Vector4.ZERO
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		safe_rect = Rect2i(Vector2i.ZERO, Vector2i(roundi(window_size.x), roundi(window_size.y)))
	var physical_left: float = maxf(0.0, float(safe_rect.position.x))
	var physical_top: float = maxf(0.0, float(safe_rect.position.y))
	var physical_right: float = maxf(0.0, window_size.x - float(safe_rect.end.x))
	var physical_bottom: float = maxf(0.0, window_size.y - float(safe_rect.end.y))
	var margins: Vector4 = Vector4(
		physical_left / window_size.x * canvas_size.x,
		physical_top / window_size.y * canvas_size.y,
		physical_right / window_size.x * canvas_size.x,
		physical_bottom / window_size.y * canvas_size.y,
	)
	if portrait:
		margins.y = maxf(margins.y, PORTRAIT_MIN_TOP_INSET)
		margins.w = maxf(margins.w, PORTRAIT_MIN_BOTTOM_INSET)
	return margins


func _on_node_added(node: Node) -> void:
	call_deferred("_configure_added_node", node)


func _configure_added_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_in_group(RESPONSIVE_GROUP):
		_apply_layout_to_target(node)
	if node is MarginContainer and node.is_in_group(SAFE_AREA_GROUP):
		apply_safe_area_to(node as MarginContainer)


func _apply_registered_layouts() -> void:
	for node: Node in get_tree().get_nodes_in_group(RESPONSIVE_GROUP):
		_apply_layout_to_target(node)
	for index: int in range(_layout_targets.size() - 1, -1, -1):
		var target: Node = _layout_targets[index].get_ref() as Node
		if not is_instance_valid(target):
			_layout_targets.remove_at(index)
			continue
		_apply_layout_to_target(target)


func _apply_layout_to_target(target: Node) -> void:
	if target != null and target.has_method("set_responsive_layout"):
		target.call("set_responsive_layout", current_layout_mode, effective_viewport_size)


func _apply_registered_safe_areas() -> void:
	for node: Node in get_tree().get_nodes_in_group(SAFE_AREA_GROUP):
		if node is MarginContainer:
			apply_safe_area_to(node as MarginContainer)
	for index: int in range(_safe_area_targets.size() - 1, -1, -1):
		var container: MarginContainer = _safe_area_targets[index].get_ref() as MarginContainer
		if not is_instance_valid(container):
			_safe_area_targets.remove_at(index)
			continue
		apply_safe_area_to(container)


func _contains_target(collection: Array[WeakRef], target: Node) -> bool:
	for reference: WeakRef in collection:
		if reference.get_ref() == target:
			return true
	return false


func _remove_target(collection: Array[WeakRef], target: Node) -> void:
	for index: int in range(collection.size() - 1, -1, -1):
		var existing: Node = collection[index].get_ref() as Node
		if not is_instance_valid(existing) or existing == target:
			collection.remove_at(index)


func _capture_preview_window() -> void:
	if _preview_has_original_window:
		return
	var window: Window = get_window()
	_preview_original_window_size = window.size
	_preview_original_window_position = window.position
	_preview_original_window_mode = window.mode
	_preview_has_original_window = true


func _apply_preview_window() -> void:
	if not layout_preview_enabled:
		return
	_preview_window_transitioning = true
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED
	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	var target_size: Vector2i = _fit_preview_window(
		_get_preview_window_size(layout_preview_mode),
		usable_rect.size,
	)
	window.size = target_size
	window.position = Vector2i(
		usable_rect.position.x + roundi(float(usable_rect.size.x - target_size.x) / 2.0),
		usable_rect.position.y + roundi(float(usable_rect.size.y - target_size.y) / 2.0),
	)
	call_deferred("_finish_preview_window_transition")


func _restore_preview_window() -> void:
	if layout_preview_enabled:
		return
	_preview_window_transitioning = true
	var window: Window = get_window()
	if _preview_has_original_window:
		window.mode = Window.MODE_WINDOWED
		window.size = _preview_original_window_size
		window.position = _preview_original_window_position
		if _preview_original_window_mode != Window.MODE_WINDOWED:
			window.mode = _preview_original_window_mode
	_preview_has_original_window = false
	call_deferred("_finish_preview_window_transition")


func _finish_preview_window_transition() -> void:
	_preview_window_transitioning = false
	_queue_refresh()


func _get_preview_device_size(mode: LayoutMode) -> Vector2:
	match mode:
		LayoutMode.PHONE:
			return PREVIEW_PHONE_DEVICE_SIZE
		LayoutMode.DESKTOP:
			return PREVIEW_DESKTOP_DEVICE_SIZE
	return PREVIEW_TABLET_DEVICE_SIZE


func _get_preview_window_size(mode: LayoutMode) -> Vector2i:
	match mode:
		LayoutMode.PHONE:
			return PREVIEW_PHONE_WINDOW_SIZE
		LayoutMode.DESKTOP:
			return PREVIEW_DESKTOP_WINDOW_SIZE
	return PREVIEW_TABLET_WINDOW_SIZE


func _fit_preview_window(target_size: Vector2i, usable_size: Vector2i) -> Vector2i:
	var available_width: float = maxf(320.0, float(usable_size.x) * 0.90)
	var available_height: float = maxf(320.0, float(usable_size.y) * 0.90)
	var fit_scale: float = minf(
		1.0,
		minf(available_width / float(target_size.x), available_height / float(target_size.y)),
	)
	return Vector2i(
		maxi(320, roundi(float(target_size.x) * fit_scale)),
		maxi(320, roundi(float(target_size.y) * fit_scale)),
	)
