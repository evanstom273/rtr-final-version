extends Button
class_name MoveCategoryItem

signal category_activated(category_id: int)

const OFF_WHITE := AppThemePalette.PRIMARY_TEXT
const MUTED_TEXT := AppThemePalette.SECONDARY_TEXT
const GRAPHITE := AppThemePalette.SECONDARY_PANEL
const GRAPHITE_HOVER := AppThemePalette.HOVER_PANEL
const ACCENT := AppThemePalette.ACTIVE
const ACCENT_BRIGHT := AppThemePalette.ACTIVE
const GOLD := AppThemePalette.PRESTIGE
const VALID_BORDER := AppThemePalette.BORDER
static var DISABLED_BORDER := AppThemePalette.with_alpha(AppThemePalette.BORDER, 0.75)

var category_id: int = 0
var _enabled_for_selection: bool = false

@onready var _icon: MoveCategoryIcon = %CategoryIcon
@onready var _name_label: Label = %CategoryName
@onready var _count_label: Label = %CategoryCount


func _ready() -> void:
	pressed.connect(_on_pressed)
	resized.connect(_update_pivot)
	_update_pivot()


func set_category_data(data: Dictionary) -> void:
	category_id = int(data.get("id", 0))
	_enabled_for_selection = bool(data.get("enabled", false))
	var valid_count := int(data.get("valid_count", 0))
	var locked_only := bool(data.get("locked_only", false))
	var has_valid_finisher := bool(data.get("has_valid_finisher", false))
	var has_locked_finisher := bool(data.get("has_locked_finisher", false))
	var special := locked_only or has_valid_finisher

	_name_label.text = str(data.get("label", "Moves")).to_upper()
	if locked_only:
		_count_label.text = "0 VALID • FINISHER LOCKED"
	elif not _enabled_for_selection:
		_count_label.text = "0 • NO VALID MOVES"
	else:
		_count_label.text = "%d VALID" % valid_count
		if has_locked_finisher:
			_count_label.text += " • F LOCKED"

	disabled = not _enabled_for_selection
	focus_mode = Control.FOCUS_ALL if _enabled_for_selection else Control.FOCUS_NONE
	modulate = Color.WHITE if _enabled_for_selection else AppThemePalette.with_alpha(AppThemePalette.DISABLED_TEXT, 0.55)
	_icon.icon_id = StringName(data.get("icon_id", &"generic"))
	_icon.locked = locked_only
	_icon.icon_color = GOLD if special else OFF_WHITE
	_name_label.add_theme_color_override("font_color", OFF_WHITE)
	_count_label.add_theme_color_override("font_color", GOLD if special or has_locked_finisher else MUTED_TEXT)
	tooltip_text = _tooltip_text(valid_count, locked_only, has_valid_finisher)
	_apply_styles(special, locked_only)


func play_selection_pulse() -> void:
	_update_pivot()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.04, 1.04), 0.04)
	tween.tween_property(self, "scale", Vector2.ONE, 0.04)
	await tween.finished


func _on_pressed() -> void:
	if _enabled_for_selection:
		category_activated.emit(category_id)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _apply_styles(special: bool, locked_only: bool) -> void:
	var normal_border := GOLD.darkened(0.18) if special else VALID_BORDER
	var normal_background := AppThemePalette.PRIMARY_PANEL if locked_only else GRAPHITE
	add_theme_stylebox_override("normal", _make_style(normal_background, normal_border, 1, special))
	add_theme_stylebox_override("hover", _make_style(GRAPHITE_HOVER, ACCENT_BRIGHT, 2, true))
	add_theme_stylebox_override("pressed", _make_style(AppThemePalette.PRESSED_PANEL, ACCENT_BRIGHT, 2, true))
	add_theme_stylebox_override("focus", _make_style(AppThemePalette.SECONDARY_PANEL, ACCENT, 2, true))
	add_theme_stylebox_override("disabled", _make_style(AppThemePalette.with_alpha(AppThemePalette.DISABLED_PANEL, 0.92), DISABLED_BORDER, 1, false))


func _make_style(background: Color, border: Color, border_width: int, glow: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(14)
	if glow:
		style.shadow_color = AppThemePalette.with_alpha(border, 0.16)
		style.shadow_size = 4
	return style


func _tooltip_text(valid_count: int, locked_only: bool, has_valid_finisher: bool) -> String:
	if locked_only:
		return "Open this category to inspect its currently locked finisher."
	if not _enabled_for_selection:
		return "No moves match the current posture, orientation, area, and motion state."
	if has_valid_finisher:
		return "%d valid moves, including an available finisher." % valid_count
	return "Open %d currently valid moves." % valid_count
