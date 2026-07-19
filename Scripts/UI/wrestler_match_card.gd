extends PanelContainer
class_name WrestlerMatchCard

signal target_focus_requested(part: int)

@export var role_title: String = "WRESTLER"
@export var accent_color: Color = Color(0.25, 0.64, 1.0, 1.0)

var wrestler: WrestlerResource
var match_state: Dictionary = {}

@onready var _role_title: Label = %RoleTitle
@onready var _name_value: Label = %NameValue
@onready var _origin_value: Label = %OriginValue
@onready var _gimmick_value: Label = %GimmickValue
@onready var _height_value: Label = %HeightValue
@onready var _weight_value: Label = %WeightValue
@onready var _age_value: Label = %AgeValue
@onready var _gender_value: Label = %GenderValue
@onready var _disposition_value: Label = %DispositionValue
@onready var _classes_value: Label = %ClassesValue
@onready var _position_value: Label = %PositionValue
@onready var _signature_moves_value: Label = %SignatureMovesValue
@onready var _finisher_moves_value: Label = %FinisherMovesValue
@onready var _held_weapon_value: Label = %HeldWeaponValue

@onready var _margin: MarginContainer = $Margin
@onready var _content: VBoxContainer = $Margin/Content
@onready var _profile_grid: GridContainer = $Margin/Content/ProfileGrid
@onready var _attributes_grid: GridContainer = $Margin/Content/AttributesGrid
@onready var _status_grid: GridContainer = $Margin/Content/ConditionPanel/StatusGrid
@onready var _body_damage_mannequin = %BodyDamageMannequin
@onready var _gimmick_label: Label = $Margin/Content/GimmickLabel
@onready var _profile_heading: Label = $Margin/Content/ProfileHeading
@onready var _attributes_heading: Label = $Margin/Content/AttributesHeading
@onready var _condition_heading: Label = $Margin/Content/ConditionHeading

@onready var _strength_bar: ProgressBar = %StrengthBar
@onready var _speed_bar: ProgressBar = %SpeedBar
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _skill_bar: ProgressBar = %SkillBar
@onready var _striking_bar: ProgressBar = %StrikingBar
@onready var _charisma_bar: ProgressBar = %CharismaBar
@onready var _popularity_bar: ProgressBar = %PopularityBar

@onready var _fatigue_bar: ProgressBar = %FatigueBar
@onready var _match_stamina_bar: ProgressBar = %MatchStaminaBar
@onready var _momentum_bar: ProgressBar = %MomentumBar


func _ready() -> void:
	ResponsiveUI.register_layout_target(self)
	_apply_compact_layout(false)
	_apply_accent()
	_body_damage_mannequin.target_focus_requested.connect(_on_target_focus_requested)
	refresh()


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	var portrait_phone := mode == ResponsiveUI.LayoutMode.PHONE and effective_size.y > effective_size.x
	_apply_compact_layout(portrait_phone)


func _apply_compact_layout(portrait_phone: bool) -> void:
	var horizontal_margin := 9 if portrait_phone else 14
	var vertical_margin := 7 if portrait_phone else 12
	var content_separation := 4 if portrait_phone else 8
	var horizontal_separation := 6 if portrait_phone else 10
	var vertical_separation := 2 if portrait_phone else 7
	_margin.add_theme_constant_override("margin_left", horizontal_margin)
	_margin.add_theme_constant_override("margin_top", vertical_margin)
	_margin.add_theme_constant_override("margin_right", horizontal_margin)
	_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	_content.add_theme_constant_override("separation", content_separation)
	_profile_grid.columns = 6 if portrait_phone else 4
	_attributes_grid.columns = 6 if portrait_phone else 4
	_status_grid.columns = 4
	for grid in [_profile_grid, _attributes_grid, _status_grid]:
		grid.add_theme_constant_override("h_separation", horizontal_separation)
		grid.add_theme_constant_override("v_separation", vertical_separation)
	_gimmick_label.visible = false
	_role_title.add_theme_font_size_override("font_size", 14 if portrait_phone else 16)
	_name_value.add_theme_font_size_override("font_size", 20 if portrait_phone else 25)
	_signature_moves_value.add_theme_font_size_override("font_size", 11 if portrait_phone else 13)
	_finisher_moves_value.add_theme_font_size_override("font_size", 11 if portrait_phone else 13)
	for heading in [_profile_heading, _attributes_heading, _condition_heading]:
		heading.add_theme_font_size_override("font_size", 13 if portrait_phone else 15)
	add_theme_font_size_override("font_size", 13 if portrait_phone else 15)
	var label_width := 54.0 if portrait_phone else 78.0
	for grid in [_profile_grid, _attributes_grid, _status_grid]:
		for child in grid.get_children():
			if child is Label and not child.name.ends_with("Value"):
				(child as Label).custom_minimum_size.x = label_width
	for bar in _all_bars():
		bar.custom_minimum_size.y = 17.0 if portrait_phone else 25.0


func set_wrestler(value: WrestlerResource) -> void:
	wrestler = value
	if is_node_ready():
		refresh()


func set_match_state(value: Dictionary) -> void:
	match_state = value
	if is_node_ready():
		refresh()


func refresh() -> void:
	if not is_node_ready():
		return

	_role_title.text = role_title
	if wrestler == null:
		_show_unassigned()
		return

	_name_value.text = _display_or_fallback(wrestler.wrestler_name, "Unnamed Wrestler")
	_origin_value.text = _format_origin(wrestler)
	_gimmick_value.text = "Gimmick: %s" % _format_gimmick(wrestler).replace("\n", " — ")
	_height_value.text = _display_or_fallback(wrestler.wrestler_height, "Not Set")
	_weight_value.text = "%d lb" % wrestler.wrestler_weight
	_age_value.text = str(wrestler.Age)
	_gender_value.text = _format_enum(WrestlerResource.WrestlerGender, int(wrestler.wrestler_gender), "Not Set")
	_disposition_value.text = _format_enum(WrestlerResource.WrestlerDisposition, int(wrestler.wrestler_disposition), "Not Set")
	_classes_value.text = _format_classes(wrestler.wrestler_class)
	var signature_ready := bool(match_state.get("signature_ready", false))
	var finisher_stock := clampi(int(match_state.get("finisher_stock", 0)), 0, 3)
	_signature_moves_value.text = "SIGNATURE %s  %s" % [
		"[READY]" if signature_ready else "[LOCKED]",
		_format_move_names(wrestler.signature_moves),
	]
	_finisher_moves_value.text = "FINISHERS %s  %s" % [
		_format_finisher_stock(finisher_stock),
		_format_move_names(wrestler.finisher_moves),
	]
	_signature_moves_value.add_theme_color_override(
		"font_color",
		Color(0.98, 0.82, 0.3, 1.0) if signature_ready else Color(0.58, 0.68, 0.82, 1.0),
	)
	_finisher_moves_value.add_theme_color_override(
		"font_color",
		Color(0.98, 0.82, 0.3, 1.0) if finisher_stock > 0 else Color(0.62, 0.65, 0.7, 1.0),
	)
	var held_weapon_name := str(match_state.get("held_weapon_name", "")).strip_edges()
	var durability := int(match_state.get("held_weapon_uses_remaining", 0))
	_held_weapon_value.text = "HELD WEAPON  %s" % (
		"%s  •  %d USE%s" % [held_weapon_name, durability, "" if durability == 1 else "S"]
		if not held_weapon_name.is_empty()
		else "None"
	)
	_held_weapon_value.add_theme_color_override(
		"font_color",
		Color(1.0, 0.58, 0.38, 1.0) if not held_weapon_name.is_empty() else Color(0.56, 0.62, 0.72, 1.0),
	)
	_position_value.text = _format_match_state()
	_name_value.tooltip_text = _name_value.text
	_origin_value.tooltip_text = _origin_value.text
	_classes_value.tooltip_text = _classes_value.text
	_signature_moves_value.tooltip_text = _signature_moves_value.text
	_finisher_moves_value.tooltip_text = _finisher_moves_value.text
	_position_value.tooltip_text = _position_value.text.replace("\n", " • ")

	_strength_bar.value = wrestler.strength
	_speed_bar.value = wrestler.speed
	_stamina_bar.value = wrestler.stamina
	_skill_bar.value = wrestler.skill
	_striking_bar.value = wrestler.striking
	_charisma_bar.value = wrestler.charisma
	_popularity_bar.value = wrestler.global_popularity

	_body_damage_mannequin.set_health(
		float(match_state.get("head_hp", wrestler.head_hp)),
		float(match_state.get("body_hp", wrestler.body_hp)),
		float(match_state.get("left_arm_hp", wrestler.left_arm_hp)),
		float(match_state.get("right_arm_hp", wrestler.right_arm_hp)),
		float(match_state.get("left_leg_hp", wrestler.left_leg_hp)),
		float(match_state.get("right_leg_hp", wrestler.right_leg_hp))
	)
	_fatigue_bar.value = float(match_state.get("fatigue", wrestler.fatigue))
	_match_stamina_bar.value = float(match_state.get("stamina", 100.0))
	_momentum_bar.value = float(match_state.get("momentum", wrestler.momentum))


func set_target_focus(part: int) -> void:
	_body_damage_mannequin.set_target_focus(part)


func set_targeting_enabled(enabled: bool) -> void:
	_body_damage_mannequin.set_targeting_enabled(enabled)


func _on_target_focus_requested(part: int) -> void:
	target_focus_requested.emit(part)


func _show_unassigned() -> void:
	_name_value.text = "No wrestler assigned"
	_origin_value.text = "—"
	_gimmick_value.text = "—"
	_height_value.text = "—"
	_weight_value.text = "—"
	_age_value.text = "—"
	_gender_value.text = "—"
	_disposition_value.text = "—"
	_classes_value.text = "—"
	_signature_moves_value.text = "SIGNATURE [LOCKED]  None assigned"
	_finisher_moves_value.text = "FINISHERS [ ][ ][ ]  None assigned"
	_held_weapon_value.text = "HELD WEAPON  None"
	_position_value.text = "Not Set"
	_body_damage_mannequin.clear_health()

	for bar: ProgressBar in _all_bars():
		bar.value = 0.0


func _format_move_names(moves: Array[MoveResource]) -> String:
	var names: Array[String] = []
	for move in moves:
		if move == null:
			continue
		var move_name := move.move_name.strip_edges()
		if not move_name.is_empty() and move_name not in names:
			names.append(move_name)
	return " • ".join(names) if not names.is_empty() else "None assigned"


func _format_finisher_stock(stock: int) -> String:
	var cells := ""
	for index in range(3):
		cells += "[F]" if index < stock else "[ ]"
	return cells


func _apply_accent() -> void:
	_role_title.add_theme_color_override("font_color", accent_color)
	_name_value.add_theme_color_override("font_color", accent_color)

	var panel_style := get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		var card_style := (panel_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		card_style.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.85)
		add_theme_stylebox_override("panel", card_style)

	for bar: ProgressBar in [
		_strength_bar,
		_speed_bar,
		_stamina_bar,
		_skill_bar,
		_striking_bar,
		_charisma_bar,
		_popularity_bar,
	]:
		var fill_style := bar.get_theme_stylebox("fill")
		if fill_style is StyleBoxFlat:
			var accent_fill := (fill_style as StyleBoxFlat).duplicate() as StyleBoxFlat
			accent_fill.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.8)
			bar.add_theme_stylebox_override("fill", accent_fill)


func _all_bars() -> Array[ProgressBar]:
	return [
		_strength_bar,
		_speed_bar,
		_stamina_bar,
		_skill_bar,
		_striking_bar,
		_charisma_bar,
		_popularity_bar,
		_fatigue_bar,
		_match_stamina_bar,
		_momentum_bar,
	]


func _format_origin(value: WrestlerResource) -> String:
	var region := _format_enum(WrestlerResource.Region, int(value.birthplace), "Not Set")
	var country := ""

	match int(value.birthplace):
		WrestlerResource.Region.NORTH_AMERICA:
			country = _format_enum(WrestlerResource.NA_Countries, int(value.north_american_country), "")
		WrestlerResource.Region.SOUTH_AMERICA:
			country = _format_enum(WrestlerResource.SA_Countries, int(value.south_american_country), "")
		WrestlerResource.Region.EUROPE:
			country = _format_enum(WrestlerResource.Europe_Countries, int(value.europe_country), "")
		WrestlerResource.Region.ASIA:
			country = _format_enum(WrestlerResource.Asia_Countries, int(value.asia_country), "")
		WrestlerResource.Region.AFRICA:
			country = _format_enum(WrestlerResource.Africa_Countries, int(value.africa_country), "")
		WrestlerResource.Region.OCEANIA:
			country = _format_enum(WrestlerResource.Oceania_Countries, int(value.oceania_country), "")

	if country.is_empty() or country == "Other":
		return region
	return "%s, %s" % [country, region]


func _format_gimmick(value: WrestlerResource) -> String:
	var gimmick_name := value.gimmick_name.strip_edges()
	var description := value.gimmick_description.strip_edges()
	if gimmick_name.is_empty() and description.is_empty():
		return "None"
	if gimmick_name.is_empty():
		return description
	if description.is_empty():
		return gimmick_name
	return "%s\n%s" % [gimmick_name, description]


func _format_classes(classes: Array) -> String:
	if classes.is_empty():
		return "None"
	var names: Array[String] = []
	for wrestler_class in classes:
		names.append(_format_enum(WrestlerResource.WrestlerClass, int(wrestler_class), "Unknown"))
	return ", ".join(names)


func _format_position(value: int) -> String:
	if value == WrestlerResource.Position.NONE:
		return "Not Set"
	return _format_enum(WrestlerResource.Position, value, "Not Set")


func _format_match_state() -> String:
	var position := _format_position(int(match_state.get("position", wrestler.position)))
	var orientation := _format_enum(
		WrestlerResource.Orientation,
		int(match_state.get("orientation", wrestler.orientation)),
		"None",
	)
	var area := _format_enum(
		WrestlerResource.Area,
		int(match_state.get("area", wrestler.area)),
		"Ring",
	)
	var motion := _format_enum(
		WrestlerResource.MotionState,
		int(match_state.get("motion_state", wrestler.motion_state)),
		"Still",
	)
	return "%s • %s\n%s • %s" % [position, orientation, area, motion]


func _format_enum(enum_values: Dictionary, value: int, fallback: String) -> String:
	for key in enum_values:
		if int(enum_values[key]) == value:
			return _pretty_enum_key(str(key))
	return fallback


func _pretty_enum_key(key: String) -> String:
	match key:
		"USA":
			return "USA"
		"UK":
			return "UK"
	var words := key.to_lower().split("_")
	var pretty_words: Array[String] = []
	for word in words:
		pretty_words.append(word.capitalize())
	return " ".join(pretty_words)


func _display_or_fallback(value: String, fallback: String) -> String:
	var clean_value := value.strip_edges()
	return fallback if clean_value.is_empty() else clean_value
