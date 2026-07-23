extends RefCounted
class_name AppThemePalette

## Rise to Relevance's application-wide semantic palette.
##
## UI code should use these constants instead of introducing local decorative
## colours. Alpha variants are created with [method with_alpha].

const MAIN_BACKGROUND := Color("#090909")
const PRIMARY_PANEL := Color("#141414")
const SECONDARY_PANEL := Color("#1B1B1B")
const BORDER := Color("#343434")
const PRIMARY_TEXT := Color("#F5F5F5")
const SECONDARY_TEXT := Color("#B0B0B0")
const DISABLED_TEXT := Color("#6D6D6D")

const PRESTIGE := Color("#D4AF37")
const FACE := Color("#4EA3FF")
const ACTIVE := Color("#7C5CFF")
const ACTIVE_HOVER := Color("#9275FF")
const ACTIVE_PRESSED := Color("#6544E8")
const ACTIVE_GLOW := Color(0.486275, 0.360784, 1.0, 0.18)
const HEEL := Color("#E05858")
const DESTRUCTIVE := HEEL
const ERROR := HEEL
const SUCCESS := Color("#4CAF50")
const WARNING := Color("#E89C32")

const HOVER_PANEL := Color("#232323")
const PRESSED_PANEL := Color("#101010")
const DISABLED_PANEL := Color("#171717")
const SHADOW := Color(0.0, 0.0, 0.0, 0.65)
const PANEL_TOP := Color("#1A1A1A")
const PANEL_BOTTOM := Color("#141414")

enum Elevation {
	APPLICATION,
	PANEL,
	CARD,
	MODAL,
}


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


static func wrestler_color(wrestler: WrestlerResource, champion := false) -> Color:
	if champion:
		return PRESTIGE
	if wrestler == null:
		return PRIMARY_TEXT
	match wrestler.wrestler_disposition:
		WrestlerResource.WrestlerDisposition.FACE:
			return FACE
		WrestlerResource.WrestlerDisposition.HEEL:
			return HEEL
	return PRIMARY_TEXT


static func disposition_color(disposition: int) -> Color:
	match disposition:
		WrestlerResource.WrestlerDisposition.FACE:
			return FACE
		WrestlerResource.WrestlerDisposition.HEEL:
			return HEEL
	return PRIMARY_TEXT


static func make_panel(
	background := PRIMARY_PANEL,
	border := BORDER,
	border_width := 1,
	corner_radius := 8,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.shadow_color = with_alpha(SHADOW, 0.52)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0.0, 2.0)
	style.anti_aliasing = true
	return style


static func make_elevated_panel(elevation := Elevation.PANEL, corner_radius := 8) -> StyleBoxFlat:
	var background := with_alpha(PRIMARY_PANEL, 0.78)
	var shadow_alpha := 0.42
	var shadow_size := 4
	var shadow_offset := Vector2(0.0, 2.0)
	match elevation:
		Elevation.APPLICATION:
			background = with_alpha(MAIN_BACKGROUND, 0.70)
			shadow_alpha = 0.28
			shadow_size = 2
			shadow_offset = Vector2(0.0, 1.0)
		Elevation.CARD:
			background = with_alpha(SECONDARY_PANEL, 0.86)
			shadow_alpha = 0.58
			shadow_size = 7
			shadow_offset = Vector2(0.0, 3.0)
		Elevation.MODAL:
			background = with_alpha(HOVER_PANEL, 0.95)
			shadow_alpha = 0.70
			shadow_size = 12
			shadow_offset = Vector2(0.0, 5.0)
	var style := make_panel(background, BORDER, 1, corner_radius)
	style.border_width_left = 0
	style.border_width_right = 0
	style.shadow_color = with_alpha(SHADOW, shadow_alpha)
	style.shadow_size = shadow_size
	style.shadow_offset = shadow_offset
	return style


static func make_control_style(state := &"normal", semantic := &"neutral") -> StyleBoxFlat:
	var background := with_alpha(SECONDARY_PANEL, 0.82)
	var border := BORDER
	var border_width := 1
	match state:
		&"hover":
			background = with_alpha(HOVER_PANEL, 0.90)
			border = ACTIVE_HOVER
		&"pressed":
			background = with_alpha(PRESSED_PANEL, 0.92)
			border = ACTIVE_PRESSED
		&"focus":
			background = with_alpha(SECONDARY_PANEL, 0.88)
			border = ACTIVE
			border_width = 1
		&"disabled":
			background = with_alpha(DISABLED_PANEL, 0.68)
	match semantic:
		&"success":
			border = SUCCESS
		&"warning":
			border = WARNING
		&"destructive", &"error":
			border = DESTRUCTIVE
		&"prestige":
			border = PRESTIGE
		&"active":
			border = ACTIVE
		&"face":
			border = FACE
		&"heel":
			border = HEEL
	return make_panel(background, border, border_width, 7)


static func apply_button_semantic(button: Button, semantic := &"neutral") -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", make_control_style(&"normal", semantic))
	button.add_theme_stylebox_override("hover", make_control_style(&"hover", semantic))
	button.add_theme_stylebox_override("pressed", make_control_style(&"pressed", semantic))
	button.add_theme_stylebox_override("focus", make_control_style(&"focus", semantic))
	button.add_theme_stylebox_override("disabled", make_control_style(&"disabled", semantic))
	button.add_theme_color_override("font_color", PRIMARY_TEXT)
	button.add_theme_color_override("font_hover_color", PRIMARY_TEXT)
	button.add_theme_color_override("font_pressed_color", PRIMARY_TEXT)
	button.add_theme_color_override("font_focus_color", PRIMARY_TEXT)
	button.add_theme_color_override("font_disabled_color", DISABLED_TEXT)


static func semantic_text(semantic: StringName) -> Color:
	match semantic:
		&"primary":
			return PRIMARY_TEXT
		&"secondary":
			return SECONDARY_TEXT
		&"disabled":
			return DISABLED_TEXT
		&"success":
			return SUCCESS
		&"warning":
			return WARNING
		&"destructive", &"error", &"heel":
			return HEEL
		&"prestige", &"champion":
			return PRESTIGE
		&"face":
			return FACE
		&"active", &"focus":
			return ACTIVE
	return PRIMARY_TEXT
