extends SceneTree

const DEFAULT_OUTPUT_ROOT := "res://Moves/Strikes/Standing_Front"
const EXPECTED_COLUMNS := 22

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
	if records.size() != 60:
		_fail("Expected 60 move rows but parsed %d." % records.size())
	if not _errors.is_empty():
		_finish()
		return

	var written := 0
	for record in records:
		var move := _build_move(record, catalogue_path)
		if move == null:
			continue
		var weight_name := str(record.get("weight", "Weak"))
		var directory := "%s/%s" % [output_root.trim_suffix("/"), weight_name]
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
		print("MOVE_CATALOGUE_IMPORT: PASS (%d resources written)" % written)
	else:
		_fail("Wrote %d of %d parsed resources." % [written, records.size()])
	_finish()


func _parse_catalogue(markdown: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var current_weight := ""
	for raw_line in markdown.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("## 1. Weak"):
			current_weight = "Weak"
			continue
		if line.begins_with("## 2. Medium"):
			current_weight = "Medium"
			continue
		if line.begins_with("## 3. Heavy"):
			current_weight = "Heavy"
			continue
		if current_weight.is_empty() or not line.begins_with("|"):
			continue
		var columns := _table_columns(line)
		if columns.is_empty() or columns[0] == "Move Name" or columns[0].begins_with("---"):
			continue
		if columns.size() != EXPECTED_COLUMNS:
			_fail("%s row has %d columns instead of %d." % [columns[0], columns.size(), EXPECTED_COLUMNS])
			continue
		records.append({
			"weight": current_weight,
			"name": columns[0],
			"description": columns[1],
			"target": columns[2],
			"required_attacker_position": columns[3],
			"required_attacker_orientation": columns[4],
			"required_attacker_area_mode": columns[5],
			"required_attacker_motion": columns[6],
			"required_target_position": columns[7],
			"required_target_orientation": columns[8],
			"required_target_area_mode": columns[9],
			"required_target_motion": columns[10],
			"resulting_attacker_position": columns[11],
			"resulting_attacker_orientation": columns[12],
			"resulting_attacker_area_mode": columns[13],
			"resulting_attacker_motion": columns[14],
			"resulting_target_position": columns[15],
			"resulting_target_orientation": columns[16],
			"resulting_target_area_mode": columns[17],
			"resulting_target_motion": columns[18],
			"style_tags": columns[19],
			"confidence": columns[20],
			"notes": columns[21],
		})
	return records


func _build_move(record: Dictionary, catalogue_path: String) -> MoveResource:
	var move := MoveResource.new()
	move.resource_name = str(record.name)
	move.move_name = str(record.name)
	move.move_type = MoveResource.MoveType.STRIKE
	move.class_preferrence = _class_preferences(str(record.style_tags))
	move.move_target_parts = _target_parts(str(record.target), str(record.notes))
	if str(record.notes).to_lower().contains("may be mirrored to either leg") or str(record.notes).to_lower().contains("may be mirrored to either foot"):
		move.targeting_mode = MoveResource.TargetingMode.CHOOSE_LEG
		move.default_side_target = MoveResource.MoveTargetParts.LEFT_LEG
	else:
		move.targeting_mode = MoveResource.TargetingMode.FIXED_PARTS
		move.default_side_target = MoveResource.MoveTargetParts.NONE

	move.required_attacker_position = _enum_value(WrestlerResource.Position, str(record.required_attacker_position), "attacker position", move.move_name)
	move.required_attacker_orientation = _enum_value(WrestlerResource.Orientation, str(record.required_attacker_orientation), "attacker orientation", move.move_name)
	move.required_attacker_area_mode = _enum_value(MoveResource.AreaRequirementMode, str(record.required_attacker_area_mode), "attacker area mode", move.move_name)
	move.required_attacker_area = WrestlerResource.Area.IN_RING
	move.required_attacker_motion_state = _enum_value(WrestlerResource.MotionState, str(record.required_attacker_motion), "attacker motion", move.move_name)

	move.required_target_position = _enum_value(WrestlerResource.Position, str(record.required_target_position), "target position", move.move_name)
	move.required_target_orientation = _enum_value(WrestlerResource.Orientation, str(record.required_target_orientation), "target orientation", move.move_name)
	move.required_target_area_mode = _enum_value(MoveResource.AreaRequirementMode, str(record.required_target_area_mode), "target area mode", move.move_name)
	move.required_target_area = WrestlerResource.Area.IN_RING
	move.required_target_motion_state = _enum_value(WrestlerResource.MotionState, str(record.required_target_motion), "target motion", move.move_name)

	move.resulting_attacker_position = _enum_value(WrestlerResource.Position, str(record.resulting_attacker_position), "attacker result position", move.move_name)
	move.resulting_attacker_orientation = _enum_value(WrestlerResource.Orientation, str(record.resulting_attacker_orientation), "attacker result orientation", move.move_name)
	move.resulting_attacker_area_mode = _enum_value(MoveResource.AreaResultMode, str(record.resulting_attacker_area_mode), "attacker result area mode", move.move_name)
	move.resulting_attacker_area = WrestlerResource.Area.IN_RING
	move.resulting_attacker_motion_state = _enum_value(WrestlerResource.MotionState, str(record.resulting_attacker_motion), "attacker result motion", move.move_name)

	move.resulting_target_position = _enum_value(WrestlerResource.Position, str(record.resulting_target_position), "target result position", move.move_name)
	move.resulting_target_orientation = _enum_value(WrestlerResource.Orientation, str(record.resulting_target_orientation), "target result orientation", move.move_name)
	move.resulting_target_area_mode = _enum_value(MoveResource.AreaResultMode, str(record.resulting_target_area_mode), "target result area mode", move.move_name)
	move.resulting_target_area = WrestlerResource.Area.IN_RING
	move.resulting_target_motion_state = _enum_value(WrestlerResource.MotionState, str(record.resulting_target_motion), "target result motion", move.move_name)

	move.is_finisher = false
	move.is_submission = false
	move.is_flash_pin = false
	move.interaction_override = MoveResource.InteractionOverride.AUTO
	move.is_strike = true
	match str(record.weight):
		"Weak":
			move.strike_weight = MoveResource.StrikeWeight.STRIKE_WEAK
			move.move_impact = 2
		"Medium":
			move.strike_weight = MoveResource.StrikeWeight.STRIKE_MEDIUM
			move.move_impact = 5
		"Heavy":
			move.strike_weight = MoveResource.StrikeWeight.STRIKE_HEAVY
			move.move_impact = 8

	move.set_meta("physical_description", str(record.description))
	var preserved_style_tags := PackedStringArray()
	for raw_tag in str(record.style_tags).split(",", false):
		preserved_style_tags.append(raw_tag.strip_edges())
	move.set_meta("style_tags", preserved_style_tags)
	move.set_meta("confidence", str(record.confidence))
	move.set_meta("catalogue_notes", str(record.notes))
	move.set_meta("catalogue_source", catalogue_path.get_file())
	return null if not _errors.is_empty() else move


func _target_parts(target_name: String, notes: String) -> Array[MoveResource.MoveTargetParts]:
	var parts: Array[MoveResource.MoveTargetParts] = []
	var target := _enum_value(MoveResource.MoveTargetParts, target_name, "body target", target_name)
	if target == MoveResource.MoveTargetParts.LEFT_LEG and (
		notes.to_lower().contains("may be mirrored to either leg")
		or notes.to_lower().contains("may be mirrored to either foot")
	):
		parts.append(MoveResource.MoveTargetParts.LEFT_LEG)
		parts.append(MoveResource.MoveTargetParts.RIGHT_LEG)
	else:
		parts.append(target as MoveResource.MoveTargetParts)
	return parts


func _class_preferences(style_tags: String) -> Array[WrestlerResource.WrestlerClass]:
	var result: Array[WrestlerResource.WrestlerClass] = []
	for raw_tag in style_tags.split(",", false):
		var tag := raw_tag.strip_edges().to_upper()
		var wrestler_class := -1
		match tag:
			"STRIKER", "STRONG_STYLE", "MARTIAL_ARTS":
				wrestler_class = WrestlerResource.WrestlerClass.STRIKER
			"POWER", "POWERHOUSE":
				wrestler_class = WrestlerResource.WrestlerClass.POWERHOUSE
			"TECHNICIAN":
				wrestler_class = WrestlerResource.WrestlerClass.TECHNICIAN
			"HARDCORE":
				wrestler_class = WrestlerResource.WrestlerClass.HARDCORE
		if wrestler_class >= 0 and wrestler_class not in result:
			result.append(wrestler_class as WrestlerResource.WrestlerClass)
	return result


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
	var slug := value.strip_edges().to_lower()
	for character in [" ", "-", "/", "'", "’", "(", ")"]:
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
