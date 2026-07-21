extends Control
class_name WeaponRadialMenu

signal weapon_selected(weapon_id: StringName, instance_id: int)
signal cancelled()

const ITEM_SIZE := Vector2(176, 92)
const INNER_COUNT := 5

var _entries: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _input_enabled := false

@onready var _dismiss: Button = %DismissArea
@onready var _safe_area: MarginContainer = %WeaponSafeArea
@onready var _panel: PanelContainer = %WheelPanel
@onready var _wheel: Control = %WheelArea
@onready var _layer: Control = %ItemLayer
@onready var _context: Label = %ContextLabel
@onready var _close: Button = %CloseButton


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	ResponsiveUI.register_safe_area(_safe_area)
	_dismiss.pressed.connect(_cancel)
	_close.pressed.connect(_cancel)
	_wheel.resized.connect(_layout_items)
	visible = false


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)
	ResponsiveUI.unregister_safe_area(_safe_area)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var panel_size := Vector2(minf(1040.0, effective_size.x - 32.0), minf(760.0, effective_size.y - 28.0))
	if mode == ResponsiveUI.LayoutMode.PHONE:
		panel_size = Vector2(maxf(840.0, effective_size.x - 24.0), maxf(470.0, effective_size.y - 20.0))
	_panel.custom_minimum_size = panel_size
	_wheel.custom_minimum_size = panel_size
	call_deferred("_layout_items")


func open_for_retrieval(weapons: Array[WeaponResource], availability: Dictionary, disqualifications_enabled: bool) -> void:
	var data: Array[Dictionary] = []
	for weapon in weapons:
		data.append({
			"weapon_id": weapon.weapon_id,
			"instance_id": 0,
			"name": weapon.display_name,
			"icon_id": weapon.icon_id,
			"impact": "—" if weapon.weapon_kind == WeaponResource.WeaponKind.THUMBTACKS else weapon.impact,
			"durability": weapon.durability_range_text(),
			"warning": (
				"OBJECT LIMIT REACHED"
				if not bool(availability.get(String(weapon.weapon_id), false))
				else "DQ ON CONTACT" if disqualifications_enabled and weapon.is_illegal_under_normal_rules else "LEGAL"
			),
			"enabled": bool(availability.get(String(weapon.weapon_id), false)),
		})
	_open(data, "CHOOSE A WEAPON")


func open_for_pickup(instances: Array[MatchWeaponInstance]) -> void:
	var data: Array[Dictionary] = []
	for instance in instances:
		if instance == null or instance.weapon == null:
			continue
		data.append({
			"weapon_id": instance.weapon.weapon_id,
			"instance_id": instance.instance_id,
			"name": instance.weapon.display_name,
			"icon_id": instance.weapon.icon_id,
			"impact": instance.weapon.impact,
			"durability": str(instance.durability),
			"warning": "PICK UP",
			"enabled": true,
		})
	_open(data, "OBJECTS IN THIS AREA")


func close_menu() -> void:
	_input_enabled = false
	visible = false


func _open(data: Array[Dictionary], heading: String) -> void:
	_entries = data
	_context.text = heading
	_rebuild()
	visible = true
	_input_enabled = true
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.14)
	call_deferred("_layout_items")


func _rebuild() -> void:
	for child in _layer.get_children():
		child.queue_free()
	_buttons.clear()
	for entry in _entries:
		var card := PanelContainer.new()
		card.custom_minimum_size = ITEM_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.055, 0.075, 0.11, 0.98)
		style.border_color = Color(0.33, 0.45, 0.64, 0.95)
		style.set_border_width_all(1)
		style.set_corner_radius_all(14)
		card.add_theme_stylebox_override("panel", style)
		_layer.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var icon := WeaponIcon.new()
		icon.custom_minimum_size = Vector2(46, 46)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_icon(StringName(entry.get("icon_id", &"weapon")), bool(entry.get("enabled", true)))
		row.add_child(icon)
		var labels := VBoxContainer.new()
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(labels)
		var title := Label.new()
		title.text = str(entry.get("name", "Weapon")).to_upper()
		title.add_theme_color_override("font_color", Color(0.94, 0.95, 0.92, 1))
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		labels.add_child(title)
		var stats := Label.new()
		stats.text = "IMPACT %s  •  USES %s" % [entry.get("impact", "—"), entry.get("durability", "—")]
		stats.add_theme_color_override("font_color", Color(0.67, 0.74, 0.84, 1))
		stats.add_theme_font_size_override("font_size", 12)
		labels.add_child(stats)
		var warning := Label.new()
		warning.text = str(entry.get("warning", ""))
		warning.add_theme_color_override("font_color", Color(0.94, 0.66, 0.27, 1))
		warning.add_theme_font_size_override("font_size", 11)
		labels.add_child(warning)
		var button := Button.new()
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.flat = true
		button.disabled = not bool(entry.get("enabled", true))
		button.tooltip_text = "%s — impact %s, durability %s" % [entry.get("name", "Weapon"), entry.get("impact", "—"), entry.get("durability", "—")]
		button.pressed.connect(_select.bind(StringName(entry.get("weapon_id", &"")), int(entry.get("instance_id", 0))))
		card.add_child(button)
		_buttons.append(button)


func _layout_items() -> void:
	if not is_node_ready() or _wheel.size.x <= 0.0:
		return
	var cards := _layer.get_children()
	var center := _wheel.size * 0.5
	for index in range(cards.size()):
		var inner := index < INNER_COUNT
		var ring_index := index if inner else index - INNER_COUNT
		var count := mini(INNER_COUNT, cards.size()) if inner else maxi(1, cards.size() - INNER_COUNT)
		var angle := -PI * 0.5 + TAU * float(ring_index) / float(count) + (0.0 if inner else PI / float(count))
		var radius := Vector2(_wheel.size.x * (0.23 if inner else 0.41), _wheel.size.y * (0.22 if inner else 0.39))
		var card := cards[index] as Control
		card.size = ITEM_SIZE
		card.position = center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) - ITEM_SIZE * 0.5


func _select(weapon_id: StringName, instance_id: int) -> void:
	if not _input_enabled:
		return
	_input_enabled = false
	visible = false
	weapon_selected.emit(weapon_id, instance_id)


func _cancel() -> void:
	if not _input_enabled:
		return
	close_menu()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
