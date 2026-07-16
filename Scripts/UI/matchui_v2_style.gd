extends Control

const SegmentedOverlayScene := preload("res://Scripts/UI/segmented_overlay.gd")

@export_range(4, 50) var bar_segments: int = 20
@export var header_text: Color = Color(0.9, 0.92, 0.95, 1.0)
@export var accent_left: Color = Color(0.21, 0.62, 0.98, 1.0)
@export var accent_right: Color = Color(0.95, 0.25, 0.25, 1.0)
@export var accent_neutral: Color = Color(0.62, 0.65, 0.7, 1.0)
@export var tick_color: Color = Color(1.0, 1.0, 1.0, 0.14)
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.78)

@export var log_color_hit: Color = Color(0.92, 0.79, 0.30, 1.0)
@export var log_color_reversal: Color = Color(0.30, 0.86, 0.95, 1.0)
@export var log_color_nearfall: Color = Color(0.98, 0.55, 0.20, 1.0)
@export var log_color_finisher: Color = Color(0.95, 0.22, 0.22, 1.0)
@export var log_color_neutral: Color = Color(0.55, 0.55, 0.55, 1.0)
@export var condition_good: Color = Color(0.32, 0.82, 0.36, 1.0)
@export var condition_mid: Color = Color(0.95, 0.78, 0.22, 1.0)
@export var condition_low: Color = Color(0.95, 0.35, 0.26, 1.0)

var _log_card: StyleBox
var _progress_bg: StyleBox
var _progress_fill: StyleBox
var _separator: StyleBox

var _log_vbox: VBoxContainer
var _left_root: PanelContainer
var _right_root: PanelContainer
var _left_actor: String = ""
var _right_actor: String = ""

func _ready() -> void:
	_log_card = load("res://UI/Themes/MatchUI_V2/panel_log_card.tres")
	_progress_bg = load("res://UI/Themes/MatchUI_V2/progress_bg.tres")
	_progress_fill = load("res://UI/Themes/MatchUI_V2/progress_fill_gold.tres")
	_separator = load("res://UI/Themes/MatchUI_V2/separator_thin.tres")

	_left_root = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/PanelContainer") as PanelContainer
	_right_root = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/PanelContainer2") as PanelContainer

	_apply_side_panel_accents()
	_apply_label_styling()
	_apply_separator_styling()
	_setup_progress_bars()
	_setup_match_log()

func _apply_label_styling() -> void:
	var labels := find_children("*", "Label", true, false)
	for n in labels:
		var label := n as Label
		if label == null:
			continue
		if _is_headerish_label(label):
			label.add_theme_color_override("font_color", header_text)
			label.add_theme_color_override("font_outline_color", outline_color)
			label.add_theme_constant_override("outline_size", 2)

	_apply_side_nameplate_colors()

func _apply_side_nameplate_colors() -> void:
	var left_label := _find_nameplate_label(_left_root)
	if left_label != null:
		left_label.add_theme_color_override("font_color", accent_left)
		left_label.add_theme_color_override("font_outline_color", outline_color)
		left_label.add_theme_constant_override("outline_size", 2)
		_left_actor = _extract_actor_name(left_label.text)

	var right_label := _find_nameplate_label(_right_root)
	if right_label != null:
		right_label.add_theme_color_override("font_color", accent_right)
		right_label.add_theme_color_override("font_outline_color", outline_color)
		right_label.add_theme_constant_override("outline_size", 2)
		_right_actor = _extract_actor_name(right_label.text)

func _find_nameplate_label(root: PanelContainer) -> Label:
	if root == null:
		return null
	var labels := root.find_children("*", "Label", true, false)
	for n in labels:
		var l := n as Label
		if l == null:
			continue
		var t := l.text
		if t.contains("\n") and t.contains("/"):
			return l
	return null

func _extract_actor_name(t: String) -> String:
	var first_line := t.split("\n", false)[0].strip_edges()
	if first_line.length() >= 3 and first_line[0] == "(":
		var close := first_line.find(")")
		if close != -1:
			first_line = first_line.substr(close + 1).strip_edges()
	return first_line.to_upper()

func _apply_separator_styling() -> void:
	if _separator == null:
		return
	var sep := _separator
	if sep is StyleBoxLine:
		var line := (sep as StyleBoxLine).duplicate(true) as StyleBoxLine
		line.color = Color(1.0, 1.0, 1.0, 0.08)
		sep = line
	var seps := find_children("*", "VSeparator", true, false)
	for n in seps:
		var s := n as VSeparator
		if s == null:
			continue
		s.add_theme_stylebox_override("separator", sep)

func _apply_side_panel_accents() -> void:
	if _left_root != null:
		_tint_panel_border(_left_root, accent_left, 0.65)
	if _right_root != null:
		_tint_panel_border(_right_root, accent_right, 0.65)

func _tint_panel_border(panel: PanelContainer, color: Color, alpha: float) -> void:
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	var copy := sb.duplicate(true) as StyleBoxFlat
	copy.border_color = Color(color.r, color.g, color.b, alpha)
	panel.add_theme_stylebox_override("panel", copy)

func _is_headerish_label(label: Label) -> bool:
	var t := label.text.strip_edges()
	if t.is_empty():
		return false
	var up := t.to_upper()
	if up in ["MATCH LOG", "MOMENTUM", "ATTRIBUTES", "PROFILE", "POPULARITY", "CONDITION", "SELECTED MOVE:"]:
		return true
	if label.uppercase and t.length() <= 14:
		return true
	return false

func _setup_progress_bars() -> void:
	var bars := find_children("*", "ProgressBar", true, false)
	for n in bars:
		var bar := n as ProgressBar
		if bar == null:
			continue
		bar.add_theme_stylebox_override("background", _progress_bg)
		bar.add_theme_stylebox_override("fill", _pick_bar_fill(bar))
		bar.modulate = Color(1, 1, 1, 1)

		var has_overlay := false
		for c in bar.get_children():
			if c is Control and c.get_script() == SegmentedOverlayScene:
				has_overlay = true
				break
		if has_overlay:
			continue

		var overlay := SegmentedOverlayScene.new()
		overlay.name = "SegmentedOverlay"
		overlay.segments = bar_segments
		overlay.line_color = tick_color
		overlay.line_width = 1.0
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = 2
		overlay.offset_right = -2
		overlay.offset_top = 2
		overlay.offset_bottom = -2
		bar.add_child(overlay)

func _pick_bar_fill(bar: ProgressBar) -> StyleBox:
	var base := _progress_fill as StyleBoxFlat
	if base == null:
		return _progress_fill
	var fill := base.duplicate(true) as StyleBoxFlat

	var is_attribute := bar.size_flags_vertical == 6
	if is_attribute:
		var side := _bar_side(bar)
		var c := accent_neutral
		if side < 0:
			c = accent_left
		elif side > 0:
			c = accent_right
		fill.bg_color = Color(c.r, c.g, c.b, fill.bg_color.a)
		return fill

	var ratio := 1.0
	if bar.max_value > 0.0:
		ratio = clampf(bar.value / bar.max_value, 0.0, 1.0)
	var cc := condition_good
	if ratio < 0.4:
		cc = condition_low
	elif ratio < 0.7:
		cc = condition_mid
	fill.bg_color = Color(cc.r, cc.g, cc.b, fill.bg_color.a)
	return fill

func _bar_side(bar: Control) -> int:
	if _left_root != null and _is_descendant_of(bar, _left_root):
		return -1
	if _right_root != null and _is_descendant_of(bar, _right_root):
		return 1
	return 0

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false

func _setup_match_log() -> void:
	_log_vbox = _find_match_log_vbox()
	if _log_vbox == null:
		return

	_log_vbox.resized.connect(_log_vbox.queue_redraw)
	_log_vbox.child_entered_tree.connect(_on_log_children_changed)
	_log_vbox.child_exiting_tree.connect(_on_log_children_changed)
	_log_vbox.draw.connect(_on_log_vbox_draw)
	_recolor_log_rows()
	_log_vbox.queue_redraw()

func _find_match_log_vbox() -> VBoxContainer:
	var labels := find_children("*", "Label", true, false)
	for n in labels:
		var label := n as Label
		if label == null:
			continue
		if label.text.strip_edges().to_upper() != "MATCH LOG":
			continue

		var container := label.get_parent() as Node
		if container == null:
			continue
		var scroll := container.find_child("ScrollContainer", false, false) as ScrollContainer
		if scroll == null:
			continue
		var vbox := scroll.find_child("VBoxContainer", false, false) as VBoxContainer
		if vbox == null:
			continue
		return vbox
	return null

func _on_log_children_changed(_n: Node) -> void:
	_recolor_log_rows()
	if _log_vbox != null:
		_log_vbox.queue_redraw()

func _on_log_vbox_draw() -> void:
	if _log_vbox == null or _log_card == null:
		return

	var pad := Vector2(8, 6)
	for c in _log_vbox.get_children():
		var row := c as Control
		if row == null or not (row is GridContainer):
			continue
		var r := Rect2(row.position - pad, row.size + (pad * 2.0))
		_log_vbox.draw_style_box(_log_card, r)

func _recolor_log_rows() -> void:
	if _log_vbox == null:
		return

	for c in _log_vbox.get_children():
		var row := c as GridContainer
		if row == null:
			continue

		var color_rect: ColorRect = null
		var text_label: Label = null

		var row_children := row.find_children("*", "ColorRect", true, false)
		if row_children.size() > 0:
			color_rect = row_children[0] as ColorRect

		var label_children := row.find_children("*", "Label", true, false)
		for ln in label_children:
			var l := ln as Label
			if l == null:
				continue
			if l.text.contains("\n"):
				text_label = l
				break

		if color_rect == null:
			continue

		var t := ""
		var actor := ""
		if text_label != null:
			t = text_label.text.to_lower()
			actor = text_label.text.split("\n", false)[0].strip_edges().to_upper()

		if not _left_actor.is_empty() and actor == _left_actor:
			color_rect.color = accent_left
		elif not _right_actor.is_empty() and actor == _right_actor:
			color_rect.color = accent_right
		else:
			color_rect.color = _pick_log_color(t)

func _pick_log_color(t: String) -> Color:
	if t.contains("fin") or t.contains("finisher"):
		return log_color_finisher
	if t.contains("reversed") or t.contains("counter"):
		return log_color_reversal
	if t.contains("kickout") or t.contains("1...2") or t.contains("nearfall"):
		return log_color_nearfall
	if t.contains("high impact") or t.contains("impact") or t.contains("rocked") or t.contains("stunned"):
		return log_color_hit
	return log_color_neutral
