extends PanelContainer
class_name BodyDamageMannequin

signal target_focus_requested(part: int)

const HEALTHY_COLOR := AppThemePalette.SUCCESS
const WARNING_COLOR := AppThemePalette.WARNING
const DAMAGED_COLOR := AppThemePalette.WARNING
const CRITICAL_COLOR := AppThemePalette.ERROR
const UNASSIGNED_COLOR := AppThemePalette.DISABLED_TEXT
const VALUE_TEXT_COLOR := AppThemePalette.PRIMARY_TEXT

@onready var _head_piece: TextureRect = %HeadPiece
@onready var _body_piece: TextureRect = %BodyPiece
@onready var _left_arm_piece: TextureRect = %LeftArmPiece
@onready var _right_arm_piece: TextureRect = %RightArmPiece
@onready var _left_leg_piece: TextureRect = %LeftLegPiece
@onready var _right_leg_piece: TextureRect = %RightLegPiece

@onready var _head_label: Label = %HeadValue
@onready var _body_label: Label = %BodyValue
@onready var _left_arm_label: Label = %LeftArmValue
@onready var _right_arm_label: Label = %RightArmValue
@onready var _left_leg_label: Label = %LeftLegValue
@onready var _right_leg_label: Label = %RightLegValue
@onready var _target_focus_chip: Label = %TargetFocusChip
@onready var _head_hit: Button = %HeadHit
@onready var _body_hit: Button = %BodyHit
@onready var _left_arm_hit: Button = %LeftArmHit
@onready var _right_arm_hit: Button = %RightArmHit
@onready var _left_leg_hit: Button = %LeftLegHit
@onready var _right_leg_hit: Button = %RightLegHit

var _target_focus: int = MoveResource.MoveTargetParts.NONE
var _targeting_enabled: bool = false


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	_apply_responsive_size(Vector2(1280.0, 720.0), false)
	_configure_value_labels()
	_head_hit.pressed.connect(_on_part_pressed.bind(MoveResource.MoveTargetParts.HEAD))
	_body_hit.pressed.connect(_on_part_pressed.bind(MoveResource.MoveTargetParts.BODY))
	_left_arm_hit.pressed.connect(_on_part_pressed.bind(MoveResource.MoveTargetParts.LEFT_ARM))
	_right_arm_hit.pressed.connect(_on_part_pressed.bind(MoveResource.MoveTargetParts.RIGHT_ARM))
	_left_leg_hit.pressed.connect(_on_part_pressed.bind(MoveResource.MoveTargetParts.LEFT_LEG))
	_right_leg_hit.pressed.connect(_on_part_pressed.bind(MoveResource.MoveTargetParts.RIGHT_LEG))
	clear_health()
	_update_target_focus_display()


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var compact := mode == ResponsiveUI.LayoutMode.PHONE
	_apply_responsive_size(effective_size, compact)


func set_health(
	head: float,
	body: float,
	left_arm: float,
	right_arm: float,
	left_leg: float,
	right_leg: float
) -> void:
	_set_part(_head_piece, _head_label, "HEAD", head)
	_set_part(_body_piece, _body_label, "BODY", body)
	_set_part(_left_arm_piece, _left_arm_label, "L ARM", left_arm)
	_set_part(_right_arm_piece, _right_arm_label, "R ARM", right_arm)
	_set_part(_left_leg_piece, _left_leg_label, "L LEG", left_leg)
	_set_part(_right_leg_piece, _right_leg_label, "R LEG", right_leg)


func clear_health() -> void:
	_set_empty_part(_head_piece, _head_label, "HEAD")
	_set_empty_part(_body_piece, _body_label, "BODY")
	_set_empty_part(_left_arm_piece, _left_arm_label, "L ARM")
	_set_empty_part(_right_arm_piece, _right_arm_label, "R ARM")
	_set_empty_part(_left_leg_piece, _left_leg_label, "L LEG")
	_set_empty_part(_right_leg_piece, _right_leg_label, "R LEG")


func set_target_focus(part: int) -> void:
	_target_focus = part if MoveTargetResolver.is_target_focus(part) else MoveResource.MoveTargetParts.NONE
	if is_node_ready():
		_update_target_focus_display()


func set_targeting_enabled(enabled: bool) -> void:
	_targeting_enabled = enabled
	if is_node_ready():
		_update_target_focus_display()


func get_target_focus() -> int:
	return _target_focus


func _set_part(piece: TextureRect, label: Label, prefix: String, value: float) -> void:
	var health := clampf(value, 0.0, 100.0)
	var color := _health_color(health)
	piece.self_modulate = color
	label.text = "%s %d%%" % [prefix, roundi(health)]
	label.add_theme_color_override("font_color", VALUE_TEXT_COLOR)


func _set_empty_part(piece: TextureRect, label: Label, prefix: String) -> void:
	piece.self_modulate = UNASSIGNED_COLOR
	label.text = "%s --" % prefix
	label.add_theme_color_override("font_color", UNASSIGNED_COLOR)


func _health_color(value: float) -> Color:
	if value >= 70.0:
		return WARNING_COLOR.lerp(HEALTHY_COLOR, (value - 70.0) / 30.0)
	if value >= 40.0:
		return DAMAGED_COLOR.lerp(WARNING_COLOR, (value - 40.0) / 30.0)
	return CRITICAL_COLOR.lerp(DAMAGED_COLOR, value / 40.0)


func _apply_responsive_size(effective_size: Vector2, compact: bool) -> void:
	var height_ratio := 0.26 if compact else 0.31
	custom_minimum_size.y = clampf(effective_size.y * height_ratio, 170.0, 220.0)
	var label_size := 12 if compact or effective_size.y < 800.0 else 14
	for label: Label in [
		_head_label,
		_body_label,
		_left_arm_label,
		_right_arm_label,
		_left_leg_label,
		_right_leg_label,
	]:
		label.add_theme_font_size_override("font_size", label_size)
	_target_focus_chip.add_theme_font_size_override("font_size", 11 if compact else 13)


func _configure_value_labels() -> void:
	for label: Label in [
		_head_label,
		_body_label,
		_left_arm_label,
		_right_arm_label,
		_left_leg_label,
		_right_leg_label,
	]:
		var backing := StyleBoxFlat.new()
		backing.bg_color = AppThemePalette.with_alpha(AppThemePalette.MAIN_BACKGROUND, 0.9)
		backing.border_color = AppThemePalette.with_alpha(AppThemePalette.BORDER, 0.75)
		backing.set_border_width_all(1)
		backing.set_corner_radius_all(5)
		backing.content_margin_left = 6.0
		backing.content_margin_right = 6.0
		label.add_theme_stylebox_override("normal", backing)
		label.add_theme_color_override("font_color", VALUE_TEXT_COLOR)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		label.add_theme_constant_override("outline_size", 2)


func _on_part_pressed(part: int) -> void:
	if not _targeting_enabled:
		return
	var next_focus := MoveResource.MoveTargetParts.NONE if _target_focus == part else part
	set_target_focus(next_focus)
	target_focus_requested.emit(next_focus)


func _update_target_focus_display() -> void:
	var buttons := {
		MoveResource.MoveTargetParts.HEAD: _head_hit,
		MoveResource.MoveTargetParts.BODY: _body_hit,
		MoveResource.MoveTargetParts.LEFT_ARM: _left_arm_hit,
		MoveResource.MoveTargetParts.RIGHT_ARM: _right_arm_hit,
		MoveResource.MoveTargetParts.LEFT_LEG: _left_leg_hit,
		MoveResource.MoveTargetParts.RIGHT_LEG: _right_leg_hit,
	}
	for part in buttons:
		var button := buttons[part] as Button
		button.disabled = not _targeting_enabled
		button.mouse_filter = Control.MOUSE_FILTER_STOP if _targeting_enabled else Control.MOUSE_FILTER_IGNORE
		button.remove_theme_stylebox_override("normal")
		if int(part) == _target_focus:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = AppThemePalette.with_alpha(AppThemePalette.ACTIVE, 0.08)
			selected_style.border_color = AppThemePalette.with_alpha(AppThemePalette.ACTIVE, 0.95)
			selected_style.set_border_width_all(2)
			selected_style.set_corner_radius_all(8)
			button.add_theme_stylebox_override("normal", selected_style)
	var labels := {
		MoveResource.MoveTargetParts.HEAD: _head_label,
		MoveResource.MoveTargetParts.BODY: _body_label,
		MoveResource.MoveTargetParts.LEFT_ARM: _left_arm_label,
		MoveResource.MoveTargetParts.RIGHT_ARM: _right_arm_label,
		MoveResource.MoveTargetParts.LEFT_LEG: _left_leg_label,
		MoveResource.MoveTargetParts.RIGHT_LEG: _right_leg_label,
	}
	for part in labels:
		var label := labels[part] as Label
		var selected := int(part) == _target_focus
		label.add_theme_color_override("font_color", VALUE_TEXT_COLOR)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		label.add_theme_constant_override("outline_size", 2)
	_target_focus_chip.visible = _targeting_enabled or _target_focus != MoveResource.MoveTargetParts.NONE
	_target_focus_chip.text = "TARGET: %s" % MoveTargetResolver.part_label(_target_focus).to_upper()
