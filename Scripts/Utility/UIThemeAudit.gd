extends SceneTree
class_name UIThemeAudit

## Static guard against decorative UI colours drifting away from the permanent
## semantic palette. This script never rewrites files.

const SCAN_ROOTS := [
	"res://Scripts/UI",
	"res://Scripts/Match/UI",
	"res://Scenes/UI",
	"res://Scenes/App",
	"res://Scenes/Match",
]
const SCRIPT_FILES := [
	"res://Scripts/Match/simple_match_ui.gd",
	"res://Scripts/Match/match_screen.gd",
]
const SCRIPT_EXCEPTIONS := [
	"res://Scripts/UI/app_theme_palette.gd",
	"res://Scripts/UI/segmented_overlay.gd",
	"res://Scripts/Match/UI/match_ring_canvas.gd",
	"res://Scripts/Match/UI/wrestler_ring_marker.gd",
]
const LEGACY_SCENE_COLOURS := [
	"Color(0.305882, 0.639216, 1",
	"Color(0.96, 0.8, 0.28",
	"Color(0.72, 0.62, 0.26",
	"Color(0.035, 0.05, 0.08",
]


func _initialize() -> void:
	var result := audit_project()
	var issues: Array = result.get("issues", [])
	print("UI theme audit: %d files checked, %d issue(s)." % [
		int(result.get("files_checked", 0)),
		issues.size(),
	])
	for index in range(mini(issues.size(), 30)):
		print("  %s" % str(issues[index]))
	if issues.size() > 30:
		print("  ... %d additional issue(s)." % (issues.size() - 30))
	quit(0 if issues.is_empty() else 1)


static func audit_project() -> Dictionary:
	var paths := PackedStringArray()
	for root in SCAN_ROOTS:
		_collect_files(root, paths)
	for script_path in SCRIPT_FILES:
		if FileAccess.file_exists(script_path):
			paths.append(script_path)
	var issues: Array[String] = []
	for path in paths:
		if path.ends_with(".gd"):
			_audit_script(path, issues)
		elif path.ends_with(".tscn"):
			_audit_scene(path, issues)
	return {
		"files_checked": paths.size(),
		"issues": issues,
		"passed": issues.is_empty(),
	}


static func _collect_files(root: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := root.path_join(entry)
			if directory.current_is_dir():
				_collect_files(path, output)
			elif path.ends_with(".gd") or path.ends_with(".tscn"):
				output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


static func _audit_script(path: String, issues: Array[String]) -> void:
	if SCRIPT_EXCEPTIONS.has(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		issues.append("%s: could not be read" % path)
		return
	var line_number := 0
	while not file.eof_reached():
		line_number += 1
		var line := file.get_line()
		if not line.contains("Color("):
			continue
		if _is_allowed_neutral_literal(line):
			continue
		issues.append("%s:%d direct Color literal; use AppThemePalette" % [path, line_number])


static func _audit_scene(path: String, issues: Array[String]) -> void:
	var text := FileAccess.get_file_as_string(path)
	for legacy in LEGACY_SCENE_COLOURS:
		if text.contains(legacy):
			issues.append("%s contains legacy decorative colour %s" % [path, legacy])


static func _is_allowed_neutral_literal(line: String) -> bool:
	var compact := line.replace(" ", "")
	if compact.contains("Color(1,1,1") or compact.contains("Color(1.0,1.0,1.0"):
		return true
	if compact.contains("Color(0,0,0") or compact.contains("Color(0.0,0.0,0.0"):
		return true
	# Alpha-preserving copies derive RGB from an existing semantic colour.
	if compact.contains("Color(color.r,color.g,color.b") or compact.contains("Color(c.r,c.g,c.b"):
		return true
	if compact.contains("Color(cc.r,cc.g,cc.b") or compact.contains("Color(accent.r"):
		return true
	if line.contains("self_modulate"):
		return true
	return false
