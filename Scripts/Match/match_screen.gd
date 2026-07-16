@tool
extends Control

# Required unique-name nodes:
# PlayerName, PlayerClass, PlayerGender, PlayerGimmick, PlayerGimmickDescription, PlayerRegion, PlayerCountry, PlayerHeight, PlayerWeight
# PlayerStrengthValue, PlayerSpeedValue, PlayerStaminaValue, PlayerSkillValue, PlayerStrikingValue, PlayerCharismaValue
# PlayerAgeValue
# PlayerHeadBar, PlayerBodyBar, PlayerLeftArmBar, PlayerRightArmBar, PlayerLeftLegBar, PlayerRightLegBar
# PlayerNameBox, PlayerStatsBox
# OpponentName, OpponentClass, OpponentGender, OpponentGimmick, OpponentGimmickDescription, OpponentRegion, OpponentCountry, OpponentHeight, OpponentWeight
# OpponentStrengthValue, OpponentSpeedValue, OpponentStaminaValue, OpponentSkillValue, OpponentStrikingValue, OpponentCharismaValue
# OpponentAgeValue
# OpponentHeadBar, OpponentBodyBar, OpponentLeftArmBar, OpponentRightArmBar, OpponentLeftLegBar, OpponentRightLegBar
# OpponentNameBox, OpponentStatsBox

@export var player_wrestler: WrestlerResource:
	set(value):
		player_wrestler = value
		if is_node_ready():
			_update_player()

@export var player_promotion: PromotionResource:
	set(value):
		player_promotion = value
		if is_node_ready():
			_update_player()

@export var opponent_wrestler: WrestlerResource:
	set(value):
		opponent_wrestler = value
		if is_node_ready():
			_update_opponent()

@export var opponent_promotion: PromotionResource:
	set(value):
		opponent_promotion = value
		if is_node_ready():
			_update_opponent()

@export var player_is_champion: bool = false:
	set(value):
		player_is_champion = value
		if is_node_ready():
			_update_player()

@export var opponent_is_champion: bool = false:
	set(value):
		opponent_is_champion = value
		if is_node_ready():
			_update_opponent()

@export var face_name_color: Color = Color(0.2509804, 0.6392157, 1.0, 1.0)
@export var heel_name_color: Color = Color(0.92156863, 0.2901961, 0.2901961, 1.0)
@export var champion_name_color: Color = Color(0.83137256, 0.6862745, 0.21568628, 1.0)
@export var accent_dim_color: Color = Color(0.72, 0.72, 0.72, 1.0)

const SegmentedOverlayScript := preload("res://Scripts/UI/segmented_overlay.gd")

var _promotion_cache_by_id: Dictionary = {}
var _promotion_cache_ready: bool = false

@onready var _moves_radial_menu = %MovesRadialMenu
@onready var _player_moves_button: Button = %PlayerMovesButton
@onready var _opponent_moves_button: Button = %OpponentMovesButton

@onready var _execute_move_button: Button = %ButtonExecuteMove
var _execute_move_button_default_text: String = ""
var _selected_player_move: MoveResource

@onready var _match_log_scroll: ScrollContainer = %MatchLogScroll
@onready var _match_log_list: VBoxContainer = %MatchLogList
@onready var _tooltip_overlay: PanelContainer = %TooltipOverlay
@onready var _tooltip_text: Label = %TooltipText
@onready var _big_hit_pop: PanelContainer = %BigHitPop
@onready var _big_hit_pop_text: Label = %BigHitPopText

func _ready() -> void:
	_execute_move_button_default_text = _execute_move_button.text
	_player_moves_button.pressed.connect(func(): _moves_radial_menu.open_for_wrestler(player_wrestler, true))
	_opponent_moves_button.pressed.connect(func(): _moves_radial_menu.open_for_wrestler(opponent_wrestler, false))
	if _moves_radial_menu != null and _moves_radial_menu.has_signal("player_move_selected"):
		_moves_radial_menu.connect("player_move_selected", Callable(self, "_on_player_move_selected"))
	_execute_move_button.pressed.connect(_on_execute_move_pressed)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	_setup_hidden_value_labels()
	_attach_segment_overlays()
	_wire_tooltips()
	_wire_accordions()
	_update_player()
	_update_opponent()

func _update_player() -> void:
	var wrestler := player_wrestler
	if not wrestler:
		return

	if _selected_player_move != null:
		_selected_player_move = null
		_update_execute_move_button_text()

	var accent := _get_name_color(wrestler, player_is_champion)

	%PlayerName.text = _format_display_name(wrestler, player_is_champion)
	_apply_name_style(%PlayerName, accent)
	_apply_section_header_style(%PlayerProfileHeader, accent)
	_apply_section_header_style(%PlayerAttributesHeader, accent)
	_apply_section_header_style(%PlayerConditionHeader, accent)

	var promotion = player_promotion
	if not promotion:
		promotion = _find_promotion_for_wrestler(wrestler)
		
	if promotion:
		%PlayerPromotion.text = _format_promotion_label(promotion)
	else:
		%PlayerPromotion.text = "FREE AGENT"

	%PlayerClass.text = _format_class(wrestler.wrestler_class)
	%PlayerGender.text = _format_gender(int(wrestler.wrestler_gender))
	%PlayerGimmick.text = wrestler.gimmick_name
	%PlayerGimmickDescription.text = _format_gimmick_description(wrestler.gimmick_description)
	%PlayerRegion.text = _format_region(wrestler.birthplace)
	%PlayerCountry.text = _format_country(wrestler)
	%PlayerHeight.text = str(wrestler.wrestler_height)
	%PlayerWeight.text = str(wrestler.wrestler_weight) + "lbs"
	%PlayerPopNA.text = _fmt_5(wrestler.pop_north_america)
	%PlayerPopSA.text = _fmt_5(wrestler.pop_south_america)
	%PlayerPopEU.text = _fmt_5(wrestler.pop_europe)
	%PlayerPopAS.text = _fmt_5(wrestler.pop_asia)
	%PlayerPopAF.text = _fmt_5(wrestler.pop_africa)
	%PlayerPopOC.text = _fmt_5(wrestler.pop_oceania)
	%PlayerPopG.text = _fmt_5(wrestler.global_popularity)

	%PlayerStrengthValue.text = _fmt_5(wrestler.strength)
	%PlayerSpeedValue.text = _fmt_5(wrestler.speed)
	%PlayerStaminaValue.text = _fmt_5(wrestler.stamina)
	%PlayerStrikingValue.text = _fmt_5(wrestler.striking)
	%PlayerSkillValue.text = _fmt_5(wrestler.skill)
	%PlayerCharismaValue.text = _fmt_5(wrestler.charisma)
	%PlayerAgeValue.text = str(wrestler.Age)

	%PlayerStrengthBar.value = wrestler.strength
	%PlayerSpeedBar.value = wrestler.speed
	%PlayerStaminaBar.value = wrestler.stamina
	%PlayerStrikingBar.value = wrestler.striking
	%PlayerSkillBar.value = wrestler.skill
	%PlayerCharismaBar.value = wrestler.charisma
	%PlayerFatigueBar.value = wrestler.fatigue
	%PlayerFatigueValue.text = _fmt_5(wrestler.fatigue)
	_set_player_tooltips(wrestler)

	_set_damage_bars(
		wrestler,
		%PlayerHeadBar,
		%PlayerBodyBar,
		%PlayerLeftArmBar,
		%PlayerRightArmBar,
		%PlayerLeftLegBar,
		%PlayerRightLegBar
	)

	_apply_panel_accent(%PlayerNameBox, accent)
	_apply_panel_accent(%PlayerStatsBox, accent)
	_apply_bar_fill(%PlayerStrengthBar, accent)
	_apply_bar_fill(%PlayerSpeedBar, accent)
	_apply_bar_fill(%PlayerStaminaBar, accent)
	_apply_bar_fill(%PlayerStrikingBar, accent)
	_apply_bar_fill(%PlayerSkillBar, accent)
	_apply_bar_fill(%PlayerCharismaBar, accent)
	_apply_bar_fill(%PlayerFatigueBar, accent)
	_apply_bar_fill(%PlayerHeadBar, accent)
	_apply_bar_fill(%PlayerBodyBar, accent)
	_apply_bar_fill(%PlayerLeftArmBar, accent)
	_apply_bar_fill(%PlayerRightArmBar, accent)
	_apply_bar_fill(%PlayerLeftLegBar, accent)
	_apply_bar_fill(%PlayerRightLegBar, accent)
	
func _update_opponent() -> void:
	var wrestler := opponent_wrestler
	if not wrestler:
		return

	var accent := _get_name_color(wrestler, opponent_is_champion)

	%OpponentName.text = _format_display_name(wrestler, opponent_is_champion)
	_apply_name_style(%OpponentName, accent)
	_apply_section_header_style(%OpponentProfileHeader, accent)
	_apply_section_header_style(%OpponentAttributesHeader, accent)
	_apply_section_header_style(%OpponentConditionHeader, accent)

	var promotion = opponent_promotion
	if not promotion:
		promotion = _find_promotion_for_wrestler(wrestler)
		
	if promotion:
		%OpponentPromotion.text = _format_promotion_label(promotion)
	else:
		%OpponentPromotion.text = "FREE AGENT"

	%OpponentClass.text = _format_class(wrestler.wrestler_class)
	%OpponentGender.text = _format_gender(int(wrestler.wrestler_gender))
	%OpponentGimmick.text = wrestler.gimmick_name
	%OpponentGimmickDescription.text = _format_gimmick_description(wrestler.gimmick_description)
	%OpponentRegion.text = _format_region(wrestler.birthplace)
	%OpponentCountry.text = _format_country(wrestler)
	%OpponentHeight.text = str(wrestler.wrestler_height)
	%OpponentWeight.text = str(wrestler.wrestler_weight) + "lbs"
	%OpponentPopNA.text = _fmt_5(wrestler.pop_north_america)
	%OpponentPopSA.text = _fmt_5(wrestler.pop_south_america)
	%OpponentPopEU.text = _fmt_5(wrestler.pop_europe)
	%OpponentPopAS.text = _fmt_5(wrestler.pop_asia)
	%OpponentPopAF.text = _fmt_5(wrestler.pop_africa)
	%OpponentPopOC.text = _fmt_5(wrestler.pop_oceania)
	%OpponentPopG.text = _fmt_5(wrestler.global_popularity)

	%OpponentStrengthValue.text = _fmt_5(wrestler.strength)
	%OpponentSpeedValue.text = _fmt_5(wrestler.speed)
	%OpponentStaminaValue.text = _fmt_5(wrestler.stamina)
	%OpponentStrikingValue.text = _fmt_5(wrestler.striking)
	%OpponentSkillValue.text = _fmt_5(wrestler.skill)
	%OpponentCharismaValue.text = _fmt_5(wrestler.charisma)
	%OpponentAgeValue.text = str(wrestler.Age)

	%OpponentStrengthBar.value = wrestler.strength
	%OpponentSpeedBar.value = wrestler.speed
	%OpponentStaminaBar.value = wrestler.stamina
	%OpponentStrikingBar.value = wrestler.striking
	%OpponentSkillBar.value = wrestler.skill
	%OpponentCharismaBar.value = wrestler.charisma
	%OpponentFatigueBar.value = wrestler.fatigue
	%OpponentFatigueValue.text = _fmt_5(wrestler.fatigue)
	_set_opponent_tooltips(wrestler)

	_set_damage_bars(
		wrestler,
		%OpponentHeadBar,
		%OpponentBodyBar,
		%OpponentLeftArmBar,
		%OpponentRightArmBar,
		%OpponentLeftLegBar,
		%OpponentRightLegBar
	)

	_apply_panel_accent(%OpponentNameBox, accent)
	_apply_panel_accent(%OpponentStatsBox, accent)
	_apply_bar_fill(%OpponentStrengthBar, accent)
	_apply_bar_fill(%OpponentSpeedBar, accent)
	_apply_bar_fill(%OpponentStaminaBar, accent)
	_apply_bar_fill(%OpponentStrikingBar, accent)
	_apply_bar_fill(%OpponentSkillBar, accent)
	_apply_bar_fill(%OpponentCharismaBar, accent)
	_apply_bar_fill(%OpponentFatigueBar, accent)
	_apply_bar_fill(%OpponentHeadBar, accent)
	_apply_bar_fill(%OpponentBodyBar, accent)
	_apply_bar_fill(%OpponentLeftArmBar, accent)
	_apply_bar_fill(%OpponentRightArmBar, accent)
	_apply_bar_fill(%OpponentLeftLegBar, accent)
	_apply_bar_fill(%OpponentRightLegBar, accent)

func _set_damage_bars(
	wrestler: WrestlerResource,
	head_bar: ProgressBar,
	body_bar: ProgressBar,
	left_arm_bar: ProgressBar,
	right_arm_bar: ProgressBar,
	left_leg_bar: ProgressBar,
	right_leg_bar: ProgressBar
) -> void:
	head_bar.value = 0
	body_bar.value = 0
	left_arm_bar.value = 0
	right_arm_bar.value = 0
	left_leg_bar.value = 0
	right_leg_bar.value = 0

	head_bar.value = maxf(0.0, 100.0 - wrestler.head_hp)
	body_bar.value = maxf(0.0, 100.0 - wrestler.body_hp)
	left_arm_bar.value = maxf(0.0, 100.0 - wrestler.left_arm_hp)
	right_arm_bar.value = maxf(0.0, 100.0 - wrestler.right_arm_hp)
	left_leg_bar.value = maxf(0.0, 100.0 - wrestler.left_leg_hp)
	right_leg_bar.value = maxf(0.0, 100.0 - wrestler.right_leg_hp)

func _setup_hidden_value_labels() -> void:
	var nodes := [
		get_node_or_null("%PlayerStrengthValue"),
		get_node_or_null("%PlayerSpeedValue"),
		get_node_or_null("%PlayerStaminaValue"),
		get_node_or_null("%PlayerStrikingValue"),
		get_node_or_null("%PlayerSkillValue"),
		get_node_or_null("%PlayerCharismaValue"),
		get_node_or_null("%PlayerFatigueValue"),
		get_node_or_null("%OpponentStrengthValue"),
		get_node_or_null("%OpponentSpeedValue"),
		get_node_or_null("%OpponentStaminaValue"),
		get_node_or_null("%OpponentStrikingValue"),
		get_node_or_null("%OpponentSkillValue"),
		get_node_or_null("%OpponentCharismaValue"),
		get_node_or_null("%OpponentFatigueValue"),
	]
	for n in nodes:
		if n is CanvasItem:
			(n as CanvasItem).modulate = Color(1, 1, 1, 0)

func _attach_segment_overlays() -> void:
	var bars := [
		get_node_or_null("%PlayerStrengthBar"),
		get_node_or_null("%PlayerSpeedBar"),
		get_node_or_null("%PlayerStaminaBar"),
		get_node_or_null("%PlayerStrikingBar"),
		get_node_or_null("%PlayerSkillBar"),
		get_node_or_null("%PlayerCharismaBar"),
		get_node_or_null("%PlayerFatigueBar"),
		get_node_or_null("%PlayerHeadBar"),
		get_node_or_null("%PlayerBodyBar"),
		get_node_or_null("%PlayerLeftArmBar"),
		get_node_or_null("%PlayerRightArmBar"),
		get_node_or_null("%PlayerLeftLegBar"),
		get_node_or_null("%PlayerRightLegBar"),
		get_node_or_null("%OpponentStrengthBar"),
		get_node_or_null("%OpponentSpeedBar"),
		get_node_or_null("%OpponentStaminaBar"),
		get_node_or_null("%OpponentStrikingBar"),
		get_node_or_null("%OpponentSkillBar"),
		get_node_or_null("%OpponentCharismaBar"),
		get_node_or_null("%OpponentFatigueBar"),
		get_node_or_null("%OpponentHeadBar"),
		get_node_or_null("%OpponentBodyBar"),
		get_node_or_null("%OpponentLeftArmBar"),
		get_node_or_null("%OpponentRightArmBar"),
		get_node_or_null("%OpponentLeftLegBar"),
		get_node_or_null("%OpponentRightLegBar"),
	]
	for b in bars:
		if b is ProgressBar:
			_ensure_segment_overlay(b as ProgressBar)

func _ensure_segment_overlay(bar: ProgressBar) -> void:
	if bar.get_node_or_null("SegmentedOverlay") != null:
		return
	var overlay := Control.new()
	overlay.name = "SegmentedOverlay"
	overlay.set_script(SegmentedOverlayScript)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(overlay)

func _wire_tooltips() -> void:
	var targets := [
		get_node_or_null("%PlayerStrengthBar"),
		get_node_or_null("%PlayerSpeedBar"),
		get_node_or_null("%PlayerStaminaBar"),
		get_node_or_null("%PlayerStrikingBar"),
		get_node_or_null("%PlayerSkillBar"),
		get_node_or_null("%PlayerCharismaBar"),
		get_node_or_null("%PlayerFatigueBar"),
		get_node_or_null("%PlayerHeadBar"),
		get_node_or_null("%PlayerBodyBar"),
		get_node_or_null("%PlayerLeftArmBar"),
		get_node_or_null("%PlayerRightArmBar"),
		get_node_or_null("%PlayerLeftLegBar"),
		get_node_or_null("%PlayerRightLegBar"),
		get_node_or_null("%OpponentStrengthBar"),
		get_node_or_null("%OpponentSpeedBar"),
		get_node_or_null("%OpponentStaminaBar"),
		get_node_or_null("%OpponentStrikingBar"),
		get_node_or_null("%OpponentSkillBar"),
		get_node_or_null("%OpponentCharismaBar"),
		get_node_or_null("%OpponentFatigueBar"),
		get_node_or_null("%OpponentHeadBar"),
		get_node_or_null("%OpponentBodyBar"),
		get_node_or_null("%OpponentLeftArmBar"),
		get_node_or_null("%OpponentRightArmBar"),
		get_node_or_null("%OpponentLeftLegBar"),
		get_node_or_null("%OpponentRightLegBar"),
	]
	for t in targets:
		if t is Control:
			var c := t as Control
			c.mouse_entered.connect(func(): _show_tooltip_for(c))
			c.mouse_exited.connect(_hide_tooltip)

func _wire_accordions() -> void:
	_wire_accordion_header(get_node_or_null("%PlayerProfileHeader") as Label)
	_wire_accordion_header(get_node_or_null("%PlayerAttributesHeader") as Label)
	_wire_accordion_header(get_node_or_null("%PlayerConditionHeader") as Label)
	_wire_accordion_header(get_node_or_null("%OpponentProfileHeader") as Label)
	_wire_accordion_header(get_node_or_null("%OpponentAttributesHeader") as Label)
	_wire_accordion_header(get_node_or_null("%OpponentConditionHeader") as Label)

func _wire_accordion_header(header: Label) -> void:
	if header == null:
		return
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.focus_mode = Control.FOCUS_ALL
	header.gui_input.connect(func(ev: InputEvent): _on_accordion_header_input(header, ev))
	_set_accordion_collapsed(header, false)

func _on_accordion_header_input(header: Label, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_toggle_accordion(header)
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and ((ev as InputEventKey).keycode == KEY_ENTER or (ev as InputEventKey).keycode == KEY_SPACE):
		_toggle_accordion(header)
		get_viewport().set_input_as_handled()

func _toggle_accordion(header: Label) -> void:
	var parent := header.get_parent()
	if parent == null:
		return
	var idx := parent.get_children().find(header)
	if idx < 0:
		return
	var any_visible := false
	for i in range(idx + 1, parent.get_child_count()):
		var c := parent.get_child(i)
		if c is CanvasItem and (c as CanvasItem).visible:
			any_visible = true
			break
	_set_accordion_collapsed(header, any_visible)

func _set_accordion_collapsed(header: Label, collapsed: bool) -> void:
	var parent := header.get_parent()
	if parent == null:
		return
	var idx := parent.get_children().find(header)
	if idx < 0:
		return
	for i in range(idx + 1, parent.get_child_count()):
		var c := parent.get_child(i)
		if c is CanvasItem:
			(c as CanvasItem).visible = not collapsed
	var base := header.text.split(" ")[0]
	header.text = base + (" ▸" if collapsed else " ▾")

func _on_gui_focus_changed(control: Control) -> void:
	if control == null:
		_hide_tooltip()
		return
	_show_tooltip_for(control)

func _show_tooltip_for(control: Control) -> void:
	if control == null:
		return
	var text := String(control.tooltip_text).strip_edges()
	if text.is_empty():
		_hide_tooltip()
		return
	_tooltip_text.text = text
	_tooltip_overlay.visible = true
	_tooltip_overlay.global_position = _clamp_tooltip_pos(control.get_global_rect().end + Vector2(10, 10))

func _clamp_tooltip_pos(pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var s := _tooltip_overlay.size
	var p := pos
	p.x = clampf(p.x, 8.0, maxf(8.0, vp.x - s.x - 8.0))
	p.y = clampf(p.y, 8.0, maxf(8.0, vp.y - s.y - 8.0))
	return p

func _hide_tooltip() -> void:
	_tooltip_overlay.visible = false

func _set_player_tooltips(wrestler: WrestlerResource) -> void:
	%PlayerStrengthBar.tooltip_text = "STRENGTH: " + _fmt_5(wrestler.strength)
	%PlayerSpeedBar.tooltip_text = "SPEED: " + _fmt_5(wrestler.speed)
	%PlayerStaminaBar.tooltip_text = "STAMINA: " + _fmt_5(wrestler.stamina)
	%PlayerStrikingBar.tooltip_text = "STRIKING: " + _fmt_5(wrestler.striking)
	%PlayerSkillBar.tooltip_text = "SKILL: " + _fmt_5(wrestler.skill)
	%PlayerCharismaBar.tooltip_text = "CHARISMA: " + _fmt_5(wrestler.charisma)
	%PlayerFatigueBar.tooltip_text = "FATIGUE: " + _fmt_5(wrestler.fatigue)
	%PlayerHeadBar.tooltip_text = "HEAD: " + _fmt_5(100.0 - wrestler.head_hp)
	%PlayerBodyBar.tooltip_text = "BODY: " + _fmt_5(100.0 - wrestler.body_hp)
	%PlayerLeftArmBar.tooltip_text = "LEFT ARM: " + _fmt_5(100.0 - wrestler.left_arm_hp)
	%PlayerRightArmBar.tooltip_text = "RIGHT ARM: " + _fmt_5(100.0 - wrestler.right_arm_hp)
	%PlayerLeftLegBar.tooltip_text = "LEFT LEG: " + _fmt_5(100.0 - wrestler.left_leg_hp)
	%PlayerRightLegBar.tooltip_text = "RIGHT LEG: " + _fmt_5(100.0 - wrestler.right_leg_hp)

func _set_opponent_tooltips(wrestler: WrestlerResource) -> void:
	%OpponentStrengthBar.tooltip_text = "STRENGTH: " + _fmt_5(wrestler.strength)
	%OpponentSpeedBar.tooltip_text = "SPEED: " + _fmt_5(wrestler.speed)
	%OpponentStaminaBar.tooltip_text = "STAMINA: " + _fmt_5(wrestler.stamina)
	%OpponentStrikingBar.tooltip_text = "STRIKING: " + _fmt_5(wrestler.striking)
	%OpponentSkillBar.tooltip_text = "SKILL: " + _fmt_5(wrestler.skill)
	%OpponentCharismaBar.tooltip_text = "CHARISMA: " + _fmt_5(wrestler.charisma)
	%OpponentFatigueBar.tooltip_text = "FATIGUE: " + _fmt_5(wrestler.fatigue)
	%OpponentHeadBar.tooltip_text = "HEAD: " + _fmt_5(100.0 - wrestler.head_hp)
	%OpponentBodyBar.tooltip_text = "BODY: " + _fmt_5(100.0 - wrestler.body_hp)
	%OpponentLeftArmBar.tooltip_text = "LEFT ARM: " + _fmt_5(100.0 - wrestler.left_arm_hp)
	%OpponentRightArmBar.tooltip_text = "RIGHT ARM: " + _fmt_5(100.0 - wrestler.right_arm_hp)
	%OpponentLeftLegBar.tooltip_text = "LEFT LEG: " + _fmt_5(100.0 - wrestler.left_leg_hp)
	%OpponentRightLegBar.tooltip_text = "RIGHT LEG: " + _fmt_5(100.0 - wrestler.right_leg_hp)

func _on_execute_move_pressed() -> void:
	if _selected_player_move == null:
		_append_match_log("NO MOVE SELECTED", false)
		return
	var label := str(_selected_player_move.move_name)
	var major := bool(_selected_player_move.is_finisher)
	_append_match_log("EXECUTE: " + label, major)
	_show_big_hit_pop(label, major)

func _append_match_log(text: String, is_major: bool) -> void:
	if not _match_log_list:
		return
	var placeholder := _match_log_list.get_node_or_null("MatchLogPlaceholder")
	if placeholder:
		placeholder.queue_free()
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.uppercase = true
	var font_size := 18 if is_major else 16
	var font_color := Color(0.95, 0.85, 0.35, 1) if is_major else accent_dim_color
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", font_color)
	_match_log_list.add_child(l)
	await get_tree().process_frame
	_match_log_scroll.scroll_vertical = int(_match_log_scroll.get_v_scroll_bar().max_value)

func _show_big_hit_pop(text: String, is_major: bool) -> void:
	if not _big_hit_pop:
		return
	_big_hit_pop_text.text = text
	_big_hit_pop.visible = true
	_big_hit_pop.modulate = Color(1, 1, 1, 0)
	_big_hit_pop.scale = Vector2(0.9, 0.9)
	var t := create_tween()
	t.tween_property(_big_hit_pop, "modulate", Color(1, 1, 1, 1), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_big_hit_pop, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6 if is_major else 0.4)
	t.tween_property(_big_hit_pop, "modulate", Color(1, 1, 1, 0), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): _big_hit_pop.visible = false)

func _get_home_popularity(wrestler: WrestlerResource) -> float:
	match wrestler.birthplace:
		WrestlerResource.Region.NORTH_AMERICA:
			return wrestler.pop_north_america
		WrestlerResource.Region.SOUTH_AMERICA:
			return wrestler.pop_south_america
		WrestlerResource.Region.EUROPE:
			return wrestler.pop_europe
		WrestlerResource.Region.ASIA:
			return wrestler.pop_asia
		WrestlerResource.Region.AFRICA:
			return wrestler.pop_africa
		WrestlerResource.Region.OCEANIA:
			return wrestler.pop_oceania
		_:
			return wrestler.global_popularity

func _fmt_5(value: float) -> String:
	return str(int(round(value / 5.0) * 5.0))

func _get_name_color(wrestler: WrestlerResource, is_champion: bool) -> Color:
	if is_champion:
		return champion_name_color
	match int(wrestler.wrestler_disposition):
		WrestlerResource.WrestlerDisposition.HEEL:
			return heel_name_color
		WrestlerResource.WrestlerDisposition.FACE:
			return face_name_color
		_:
			return Color(1, 1, 1, 1)

func _apply_name_style(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 2)

func _apply_section_header_style(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 1)

func _apply_panel_accent(panel: PanelContainer, color: Color) -> void:
	if panel.has_theme_stylebox_override("panel"):
		var existing := panel.get_theme_stylebox("panel")
		if existing is StyleBoxFlat:
			var sb_existing := existing as StyleBoxFlat
			sb_existing.border_color = color
			sb_existing.border_width_left = max(sb_existing.border_width_left, 4)
			sb_existing.border_width_top = max(sb_existing.border_width_top, 4)
			sb_existing.border_width_right = max(sb_existing.border_width_right, 4)
			sb_existing.border_width_bottom = max(sb_existing.border_width_bottom, 4)
			return

	var base := panel.get_theme_stylebox("panel")
	if base is StyleBoxFlat:
		var sb := (base as StyleBoxFlat).duplicate()
		sb.border_color = color
		sb.border_width_left = max(sb.border_width_left, 4)
		sb.border_width_top = max(sb.border_width_top, 4)
		sb.border_width_right = max(sb.border_width_right, 4)
		sb.border_width_bottom = max(sb.border_width_bottom, 4)
		panel.add_theme_stylebox_override("panel", sb)

func _apply_bar_fill(bar: ProgressBar, color: Color) -> void:
	var c := color
	c.a = 0.55

	if bar.has_theme_stylebox_override("fill"):
		var existing := bar.get_theme_stylebox("fill")
		if existing is StyleBoxFlat:
			(existing as StyleBoxFlat).bg_color = c
			return

	var base := bar.get_theme_stylebox("fill")
	if base is StyleBoxFlat:
		var sb := (base as StyleBoxFlat).duplicate()
		sb.bg_color = c
		bar.add_theme_stylebox_override("fill", sb)

func _on_player_move_selected(move: MoveResource) -> void:
	_selected_player_move = move
	_update_execute_move_button_text()

func _update_execute_move_button_text() -> void:
	if not _execute_move_button:
		return
	if _selected_player_move == null:
		_execute_move_button.text = _execute_move_button_default_text
		return
	var label := str(_selected_player_move.move_name)
	if bool(_selected_player_move.is_finisher):
		label += " (FIN)"
	_execute_move_button.text = "Execute:\n" + label + "!"

func _format_class(classes: Array) -> String:
	if classes.is_empty():
		return ""
	var names: Array[String] = []
	for c in classes:
		names.append(_format_enum_name(WrestlerResource.WrestlerClass, int(c)))
	return "/".join(names)

func _format_region(region_value: int) -> String:
	return _format_enum_name(WrestlerResource.Region, region_value)

func _format_country(wrestler: WrestlerResource) -> String:
	match int(wrestler.birthplace):
		WrestlerResource.Region.NORTH_AMERICA:
			return _format_enum_name(WrestlerResource.NA_Countries, int(wrestler.north_american_country))
		WrestlerResource.Region.SOUTH_AMERICA:
			return _format_enum_name(WrestlerResource.SA_Countries, int(wrestler.south_american_country))
		WrestlerResource.Region.EUROPE:
			return _format_enum_name(WrestlerResource.Europe_Countries, int(wrestler.europe_country))
		WrestlerResource.Region.ASIA:
			return _format_enum_name(WrestlerResource.Asia_Countries, int(wrestler.asia_country))
		WrestlerResource.Region.AFRICA:
			return _format_enum_name(WrestlerResource.Africa_Countries, int(wrestler.africa_country))
		WrestlerResource.Region.OCEANIA:
			return _format_enum_name(WrestlerResource.Oceania_Countries, int(wrestler.oceania_country))
		_:
			return ""

func _format_enum_name(enum_dict: Dictionary, value: int) -> String:
	for k in enum_dict.keys():
		if int(enum_dict[k]) == value:
			return _pretty_enum_key(str(k))
	return ""

func _pretty_enum_key(key: String) -> String:
	return key.replace("_", " ").to_lower().capitalize()

func _format_display_name(wrestler: WrestlerResource, is_champion: bool) -> String:
	var prefix := _format_disposition_prefix(int(wrestler.wrestler_disposition))
	var suffix := " (c)" if is_champion else ""
	return "(" + prefix + ") " + wrestler.wrestler_name.to_upper() + suffix

func _format_disposition_prefix(disposition_value: int) -> String:
	match disposition_value:
		WrestlerResource.WrestlerDisposition.HEEL:
			return "h"
		WrestlerResource.WrestlerDisposition.FACE:
			return "f"
		_:
			return ""

func _format_gimmick_description(description: String) -> String:
	if description.strip_edges().is_empty():
		return ""
	return " - " + description

func _format_gender(gender_value: int) -> String:
	return _format_enum_name(WrestlerResource.WrestlerGender, gender_value)

func _format_promotion_label(promotion: PromotionResource) -> String:
	if int(promotion.promotion_id) == 1:
		return "FREE AGENT"
	var initials := str(promotion.promotion_initials).strip_edges()
	if not initials.is_empty():
		return initials
	return str(promotion.promotion_name).strip_edges()

func _get_promotion_cache() -> void:
	if _promotion_cache_ready:
		return

	_promotion_cache_by_id = {}
	var resource_paths: Array[String] = []
	_collect_resource_paths("res://Promotions", resource_paths)
	for resource_path in resource_paths:
		var resource := ResourceLoader.load(resource_path)
		if resource is PromotionResource:
			var promotion := resource as PromotionResource
			_promotion_cache_by_id[int(promotion.promotion_id)] = promotion

	_promotion_cache_ready = true


func _collect_resource_paths(directory_path: String, paths: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_resource_paths(
				directory_path.path_join(entry.trim_suffix("/")),
				paths,
			)
		elif entry.get_extension().to_lower() == "tres":
			paths.append(directory_path.path_join(entry))

func _find_promotion_by_id(promotion_id: int) -> PromotionResource:
	if promotion_id <= 0:
		return null

	_get_promotion_cache()
	return _promotion_cache_by_id.get(promotion_id, null)

func _find_promotion_for_wrestler(wrestler: WrestlerResource) -> PromotionResource:
	if not wrestler:
		return null

	var contract := wrestler.current_contract
	if contract and int(contract.promotion_id) > 0:
		var promo_from_contract = _find_promotion_by_id(int(contract.promotion_id))
		if promo_from_contract:
			return promo_from_contract

	_get_promotion_cache()
	for promo in _promotion_cache_by_id.values():
		if promo == null:
			continue
		var mens = promo.mens_division
		if mens and wrestler in mens:
			return promo
		var womens = promo.womens_division
		if womens and wrestler in womens:
			return promo

	return null
