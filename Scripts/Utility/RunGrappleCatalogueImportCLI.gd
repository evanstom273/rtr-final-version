extends SceneTree

const DEFAULT_OUTPUT_ROOT := "res://Moves/Grapples"
const EXPECTED_COLUMNS := 26
const EXPECTED_RECORDS := 108

const SECTION_DIRECTORIES := {
	"Standing Front": "Standing_Front",
	"Standing Back": "Standing_Back",
	"Grounded": "Grounded",
	"Corner": "Corner",
	"Top-Rope / Perched": "Top_Rope_Perched",
	"Apron / Rope": "Apron_Rope",
	"Outside-Ring": "Outside_Ring",
}

var _errors: Array[String] = []


func _initialize() -> void:
	var catalogue_path := _argument_value("--catalogue=")
	var output_root := _argument_value("--output=")
	if output_root.is_empty():
		output_root = DEFAULT_OUTPUT_ROOT
	if catalogue_path.is_empty():
		_fail("Missing --catalogue=<absolute markdown path> argument.")
		_finish()
		return
	var markdown := FileAccess.get_file_as_string(catalogue_path)
	if markdown.is_empty():
		_fail("Catalogue is empty or unreadable: %s" % catalogue_path)
		_finish()
		return

	var records := _parse_catalogue(markdown)
	if records.size() != EXPECTED_RECORDS:
		_fail("Expected %d retained grapple rows but parsed %d." % [EXPECTED_RECORDS, records.size()])
	if not _errors.is_empty():
		_finish()
		return

	var written := 0
	for record in records:
		var move := _build_move(record, catalogue_path)
		if move == null:
			continue
		var section := str(record.get("section", ""))
		var directory_name := str(SECTION_DIRECTORIES.get(section, ""))
		if directory_name.is_empty():
			_fail("%s has an unknown catalogue section '%s'." % [move.move_name, section])
			continue
		var directory := "%s/%s" % [output_root.trim_suffix("/"), directory_name]
		var absolute_directory := ProjectSettings.globalize_path(directory)
		var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
		if mkdir_error != OK:
			_fail("Could not create %s (error %d)." % [directory, mkdir_error])
			continue
		var resource_path := "%s/%s.tres" % [directory, _slugify(move.move_name)]
		var save_error := ResourceSaver.save(move, resource_path)
		if save_error != OK:
			_fail("Could not save %s (error %d)." % [resource_path, save_error])
			continue
		written += 1

	if _errors.is_empty() and written == records.size():
		print("GRAPPLE_CATALOGUE_IMPORT: PASS (%d resources written)" % written)
	else:
		_fail("Wrote %d of %d parsed grapple resources." % [written, records.size()])
	_finish()


func _parse_catalogue(markdown: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var current_section := ""
	for raw_line in markdown.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("## "):
			current_section = ""
			for section_name in SECTION_DIRECTORIES:
				if line == "## Revised %s Grapples" % section_name:
					current_section = section_name
					break
			continue
		if current_section.is_empty() or not line.begins_with("|"):
			continue
		var columns := _table_columns(line)
		if columns.is_empty() or columns[0] == "Move Name" or columns[0].begins_with("---"):
			continue
		if columns.size() != EXPECTED_COLUMNS:
			_fail("%s row has %d columns instead of %d." % [columns[0], columns.size(), EXPECTED_COLUMNS])
			continue
		records.append({
			"section": current_section,
			"name": columns[0],
			"description": columns[1],
			"target": columns[2],
			"grapple_tags": columns[3],
			"required_attacker_position": columns[4],
			"required_attacker_orientation": columns[5],
			"required_attacker_area_mode": columns[6],
			"required_attacker_area": columns[7],
			"required_attacker_motion": columns[8],
			"required_target_position": columns[9],
			"required_target_orientation": columns[10],
			"required_target_area_mode": columns[11],
			"required_target_area": columns[12],
			"required_target_motion": columns[13],
			"resulting_attacker_position": columns[14],
			"resulting_attacker_orientation": columns[15],
			"resulting_attacker_area_mode": columns[16],
			"resulting_attacker_area": columns[17],
			"resulting_attacker_motion": columns[18],
			"resulting_target_position": columns[19],
			"resulting_target_orientation": columns[20],
			"resulting_target_area_mode": columns[21],
			"resulting_target_area": columns[22],
			"resulting_target_motion": columns[23],
			"confidence": columns[24],
			"notes": columns[25],
		})
	return records


func _build_move(record: Dictionary, catalogue_path: String) -> MoveResource:
	var move := MoveResource.new()
	move.resource_name = str(record.get("name", ""))
	move.move_name = str(record.get("name", ""))
	move.move_type = MoveResource.MoveType.GRAPPLE
	move.class_preferrence = []
	_configure_targeting(move, str(record.get("target", "")), str(record.get("notes", "")))

	move.required_attacker_position = _enum_value(WrestlerResource.Position, str(record.get("required_attacker_position", "")), "attacker position", move.move_name)
	move.required_attacker_orientation = _enum_value(WrestlerResource.Orientation, str(record.get("required_attacker_orientation", "")), "attacker orientation", move.move_name)
	if str(record.get("notes", "")).contains("shared flat areas only"):
		move.required_attacker_area_mode = MoveResource.AreaRequirementMode.SHARED_FLAT_AREA
	else:
		move.required_attacker_area_mode = _enum_value(MoveResource.AreaRequirementMode, str(record.get("required_attacker_area_mode", "")), "attacker area mode", move.move_name)
	move.required_attacker_area = _area_value(str(record.get("required_attacker_area", "")), "attacker required area", move.move_name)
	move.required_attacker_motion_state = _enum_value(WrestlerResource.MotionState, str(record.get("required_attacker_motion", "")), "attacker motion", move.move_name)

	move.required_target_position = _enum_value(WrestlerResource.Position, str(record.get("required_target_position", "")), "target position", move.move_name)
	move.required_target_orientation = _enum_value(WrestlerResource.Orientation, str(record.get("required_target_orientation", "")), "target orientation", move.move_name)
	move.required_target_area_mode = _enum_value(MoveResource.AreaRequirementMode, str(record.get("required_target_area_mode", "")), "target area mode", move.move_name)
	move.required_target_area = _area_value(str(record.get("required_target_area", "")), "target required area", move.move_name)
	move.required_target_motion_state = _enum_value(WrestlerResource.MotionState, str(record.get("required_target_motion", "")), "target motion", move.move_name)

	move.resulting_attacker_position = _enum_value(WrestlerResource.Position, str(record.get("resulting_attacker_position", "")), "attacker result position", move.move_name)
	move.resulting_attacker_orientation = _enum_value(WrestlerResource.Orientation, str(record.get("resulting_attacker_orientation", "")), "attacker result orientation", move.move_name)
	move.resulting_attacker_area_mode = _enum_value(MoveResource.AreaResultMode, str(record.get("resulting_attacker_area_mode", "")), "attacker result area mode", move.move_name)
	move.resulting_attacker_area = _area_value(str(record.get("resulting_attacker_area", "")), "attacker result area", move.move_name)
	move.resulting_attacker_motion_state = _enum_value(WrestlerResource.MotionState, str(record.get("resulting_attacker_motion", "")), "attacker result motion", move.move_name)

	move.resulting_target_position = _enum_value(WrestlerResource.Position, str(record.get("resulting_target_position", "")), "target result position", move.move_name)
	move.resulting_target_orientation = _enum_value(WrestlerResource.Orientation, str(record.get("resulting_target_orientation", "")), "target result orientation", move.move_name)
	move.resulting_target_area_mode = _enum_value(MoveResource.AreaResultMode, str(record.get("resulting_target_area_mode", "")), "target result area mode", move.move_name)
	move.resulting_target_area = _area_value(str(record.get("resulting_target_area", "")), "target result area", move.move_name)
	move.resulting_target_motion_state = _enum_value(WrestlerResource.MotionState, str(record.get("resulting_target_motion", "")), "target result motion", move.move_name)

	var tags := _tags(str(record.get("grapple_tags", "")))
	move.is_finisher = false
	move.is_submission = false
	move.is_pinning_combination = "PINNING_COMBINATION" in tags
	move.is_flash_pin = move.is_pinning_combination and _is_surprise_pin_name(move.move_name)
	move.interaction_override = MoveResource.InteractionOverride.HOLD_POWER
	move.is_strike = false
	move.strike_weight = MoveResource.StrikeWeight.STRIKE_WEAK
	move.move_impact = _impact_for(tags)

	move.set_meta("physical_description", str(record.get("description", "")))
	move.set_meta("grapple_tags", tags)
	move.set_meta("catalogue_section", str(record.get("section", "")))
	move.set_meta("confidence", str(record.get("confidence", "")))
	move.set_meta("catalogue_notes", str(record.get("notes", "")))
	move.set_meta("catalogue_source", catalogue_path.get_file())
	move.set_meta("impact_assignment", _impact_basis(tags))
	return null if not _errors.is_empty() else move


func _configure_targeting(move: MoveResource, target_name: String, notes: String) -> void:
	var target := _enum_value(MoveResource.MoveTargetParts, target_name, "body target", move.move_name)
	var lower_notes := notes.to_lower()
	if target == MoveResource.MoveTargetParts.RIGHT_ARM and (
		lower_notes.contains("either arm")
		or lower_notes.contains("either shoulder")
		or lower_notes.contains("may be mirrored")
	):
		move.move_target_parts = [
			MoveResource.MoveTargetParts.LEFT_ARM,
			MoveResource.MoveTargetParts.RIGHT_ARM,
		]
		move.targeting_mode = MoveResource.TargetingMode.CHOOSE_ARM
		move.default_side_target = MoveResource.MoveTargetParts.RIGHT_ARM
	elif target == MoveResource.MoveTargetParts.LEFT_LEG and lower_notes.contains("may be mirrored"):
		move.move_target_parts = [
			MoveResource.MoveTargetParts.LEFT_LEG,
			MoveResource.MoveTargetParts.RIGHT_LEG,
		]
		move.targeting_mode = MoveResource.TargetingMode.CHOOSE_LEG
		move.default_side_target = MoveResource.MoveTargetParts.LEFT_LEG
	else:
		move.move_target_parts = [target as MoveResource.MoveTargetParts]
		move.targeting_mode = MoveResource.TargetingMode.FIXED_PARTS
		move.default_side_target = MoveResource.MoveTargetParts.NONE


func _impact_for(tags: PackedStringArray) -> int:
	if "AVALANCHE" in tags:
		return 9
	if "ENVIRONMENTAL" in tags:
		return 8
	if "POWERBOMB" in tags or "DRIVER" in tags:
		return 7
	if (
		"SUPLEX" in tags
		or "SLAM" in tags
		or "BACKBREAKER" in tags
		or "FACEBUSTER" in tags
		or "NECKBREAKER" in tags
		or "LIFT" in tags
	):
		return 6
	return 4


func _impact_basis(tags: PackedStringArray) -> String:
	if "AVALANCHE" in tags:
		return "Catalogue tag tier: AVALANCHE = 9"
	if "ENVIRONMENTAL" in tags:
		return "Catalogue tag tier: ENVIRONMENTAL = 8"
	if "POWERBOMB" in tags or "DRIVER" in tags:
		return "Catalogue tag tier: POWERBOMB/DRIVER = 7"
	if (
		"SUPLEX" in tags
		or "SLAM" in tags
		or "BACKBREAKER" in tags
		or "FACEBUSTER" in tags
		or "NECKBREAKER" in tags
		or "LIFT" in tags
	):
		return "Catalogue tag tier: major grapple = 6"
	return "Catalogue tag tier: takedown/throw/pinning = 4"


func _is_surprise_pin_name(move_name: String) -> bool:
	var normalized := move_name.to_lower().replace("’", "'")
	for term in ["roll-up", "roll up", "o'connor", "oklahoma roll", "jackknife pin", "cradle", "crucifix pin"]:
		if normalized.contains(term):
			return true
	return false


func _tags(raw_tags: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_tag in raw_tags.split(",", false):
		var tag := raw_tag.strip_edges().to_upper()
		if not tag.is_empty():
			result.append(tag)
	return result


func _area_value(key: String, field_name: String, move_name: String) -> int:
	var normalized := key.strip_edges().to_upper()
	if normalized == "N/A" or normalized.is_empty():
		return WrestlerResource.Area.IN_RING
	if normalized == "OUTSIDE_RING":
		normalized = "OUTSIDE"
	return _enum_value(WrestlerResource.Area, normalized, field_name, move_name)


func _enum_value(values: Dictionary, key: String, field_name: String, move_name: String) -> int:
	var normalized := key.strip_edges().to_upper()
	if values.has(normalized):
		return int(values[normalized])
	_fail("%s has unknown %s '%s'." % [move_name, field_name, key])
	return 0


func _table_columns(line: String) -> PackedStringArray:
	var source := line.trim_prefix("|").trim_suffix("|")
	var values := PackedStringArray()
	for column in source.split("|", true):
		values.append(column.strip_edges())
	return values


func _slugify(value: String) -> String:
	var slug := value.strip_edges().to_lower().replace("’", "'")
	for character in [" ", "-", "/", "'", "(", ")"]:
		slug = slug.replace(character, "_")
	while slug.contains("__"):
		slug = slug.replace("__", "_")
	return slug.trim_prefix("_").trim_suffix("_")


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _fail(message: String) -> void:
	_errors.append(message)
	push_error(message)


func _finish() -> void:
	quit(_errors.size())
