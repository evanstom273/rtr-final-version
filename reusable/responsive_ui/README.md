# Portable Responsive UI for Godot 4.x

This folder contains a standalone responsive UI autoload extracted from the
NewGame interface. It has no game-specific dependencies.

It provides:

- DPI-aware Phone, Tablet/Foldable, and Desktop classification.
- Separate phone portrait, phone landscape, tablet, and desktop scaling.
- Live updates for rotation, folding/unfolding, window resizing, and split screen.
- Android/iOS safe-area margin support for camera cutouts and gesture bars.
- A desktop preview API for checking all three layouts before exporting.
- Helpers for common column counts and page margins.
- Scene-editor groups or explicit registration for responsive authored scenes.

## Install

1. Copy `responsive_ui.gd` into the target project.
2. Open **Project > Project Settings > Globals/Autoload**.
3. Add the script and name it `ResponsiveUI`.
4. Keep screen roots and their important children as authored `Control` scenes.

The script configures the root window to use a 1920x1080 `canvas_items` design
with `expand` aspect handling. Change `DESIGN_SIZE` at the top of the script if
the target project uses another authored resolution.

## Make a screen responsive

Either register it from its controller:

```gdscript
extends Control

func _ready() -> void:
	ResponsiveUI.register_layout_target(self)


func _exit_tree() -> void:
	ResponsiveUI.unregister_layout_target(self)


func set_responsive_layout(mode: int, effective_size: Vector2) -> void:
	%CardGrid.columns = ResponsiveUI.get_column_count(1, 2, 4)
	%Sidebar.visible = mode == ResponsiveUI.LayoutMode.DESKTOP
	%BottomNav.visible = mode != ResponsiveUI.LayoutMode.DESKTOP
	%MainRow.vertical = mode == ResponsiveUI.LayoutMode.PHONE
	%PageMargin.add_theme_constant_override("margin_left", ResponsiveUI.get_page_margin())
	%PageMargin.add_theme_constant_override("margin_right", ResponsiveUI.get_page_margin())
```

Or add the scene root to the `responsive_ui` group in the Godot editor and
implement the same `set_responsive_layout()` method. Grouped nodes are updated
automatically when they enter the tree.

## Safe areas

Add a dedicated full-rect `MarginContainer` around the application's authored
content. Put it in the `responsive_safe_area` group, or register it:

```gdscript
func _ready() -> void:
	ResponsiveUI.register_safe_area(%SafeArea)
```

The service writes the device safe insets into that container's four margin
constants. Use a dedicated container because those four overrides are replaced.

## Desktop layout preview

```gdscript
ResponsiveUI.set_layout_preview(true, ResponsiveUI.LayoutMode.PHONE)
ResponsiveUI.set_layout_preview(true, ResponsiveUI.LayoutMode.TABLET)
ResponsiveUI.set_layout_preview(true, ResponsiveUI.LayoutMode.DESKTOP)
ResponsiveUI.set_layout_preview(false)
```

Preview temporarily resizes and centres the desktop window, then restores its
previous size, position, and display mode when disabled.

## Important limitation

Scaling alone cannot reflow arbitrary fixed-position UI. Use authored Godot
containers (`GridContainer`, `BoxContainer`, `FlowContainer`,
`MarginContainer`, and `ScrollContainer`) and change their existing properties
inside `set_responsive_layout()`. The autoload deliberately does not construct
UI hierarchies in GDScript.

## Main tuning values

- `DESIGN_SIZE`
- `PHONE_PORTRAIT_CONTENT_SCALE`
- `TABLET_CONTENT_SCALE`
- Phone/Desktop logical breakpoints
- Page margins
- Preview window sizes

Increasing a content scale makes the interface larger while reducing the
logical canvas space available to the authored layout.
