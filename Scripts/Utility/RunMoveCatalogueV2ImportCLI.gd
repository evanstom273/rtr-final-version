extends SceneTree

const EXPECTED_ENTRY_COUNT := 596
const EXPECTED_TOTAL_MOVE_RESOURCES := 656
const SOURCE_PATH_PREFIX := "res://Moves/Rebuilt/"
const OUTPUT_PATH_PREFIX := "res://Moves/"

const ALLOWED_CATEGORIES := [
	"Aerial",
	"Grapple",
	"Pinning_Move",
	"Running",
	"Springboard",
	"Submission",
]

const EXPECTED_TYPE_COUNTS := {
	"AERIAL": 62,
	"GRAPPLE": 246,
	"PINNING_MOVE": 40,
	"RUNNING": 113,
	"SPRINGBOARD": 55,
	"SUBMISSION": 80,
}

const EXPECTED_FAMILY_COUNTS := {
	"aerial_grounded": 29,
	"aerial_outside": 8,
	"aerial_running_target": 1,
	"aerial_standing": 24,
	"apron_rope_grapple": 25,
	"attacker_running_grounded": 20,
	"attacker_running_standing": 45,
	"corner_grapple": 24,
	"grounded_face_down_submission": 28,
	"grounded_face_up_submission": 24,
	"grounded_grapple": 33,
	"grounded_pin": 11,
	"kneeling_pin": 1,
	"running_corner": 15,
	"special_submission": 12,
	"springboard_grounded": 15,
	"springboard_outside": 12,
	"springboard_standing": 28,
	"standing_back": 54,
	"standing_back_pin": 9,
	"standing_front": 85,
	"standing_front_pin": 19,
	"standing_submission": 16,
	"target_rope_rebound": 33,
	"top_rope_grapple": 25,
}

const EXPECTED_RESOURCE_FIELDS := [
	"move_name",
	"move_type",
	"class_preferrence",
	"move_target_parts",
	"targeting_mode",
	"default_side_target",
	"required_attacker_position",
	"required_attacker_orientation",
	"required_attacker_area_mode",
	"required_attacker_area",
	"required_attacker_motion_state",
	"required_target_position",
	"required_target_orientation",
	"required_target_area_mode",
	"required_target_area",
	"required_target_motion_state",
	"resulting_attacker_position",
	"resulting_attacker_orientation",
	"resulting_attacker_area_mode",
	"resulting_attacker_area",
	"resulting_attacker_motion_state",
	"resulting_target_position",
	"resulting_target_orientation",
	"resulting_target_area_mode",
	"resulting_target_area",
	"resulting_target_motion_state",
	"is_finisher",
	"is_submission",
	"is_flash_pin",
	"is_pinning_combination",
	"interaction_override",
	"is_strike",
	"strike_weight",
	"move_impact",
]

var _errors: Array[String] = []


func _initialize() -> void:
	var catalogue_path := _argument_value("--catalogue=")
	if catalogue_path.is_empty():
		_fail("Missing --catalogue=<absolute JSON path> argument.")
		_finish()
		return
	var json_text := FileAccess.get_file_as_string(catalogue_path)
	if json_text.is_empty():
		_fail("Catalogue is empty or unreadable: %s" % catalogue_path)
		_finish()
		return
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		_fail("Catalogue root must be a JSON object.")
		_finish()
		return
	var root := parsed as Dictionary
	if not root.has("moves") or not root.moves is Array:
		_fail("Catalogue root has no moves array.")
		_finish()
		return
	var records := root.moves as Array
	if records.size() != EXPECTED_ENTRY_COUNT:
		_fail("Expected %d catalogue entries but found %d." % [EXPECTED_ENTRY_COUNT, records.size()])

	var prepared: Array[Dictionary] = []
	var seen_ids := {}
	var seen_names := {}
	var seen_paths := {}
	var type_counts := {}
	var family_counts := {}
	for index in records.size():
		var raw_record: Variant = records[index]
		if not raw_record is Dictionary:
			_fail("Entry %d is not an object." % index)
			continue
		var record := raw_record as Dictionary
		var catalogue_id := str(record.get("catalogue_id", "")).strip_edges()
		var family := str(record.get("family", "")).strip_edges()
		var suggested_path := str(record.get("suggested_path", "")).strip_edges()
		var raw_resource: Variant = record.get("resource")
		if catalogue_id.is_empty():
			_fail("Entry %d has no catalogue_id." % index)
		if family.is_empty():
			_fail("Entry %d has no family." % index)
		if not raw_resource is Dictionary:
			_fail("Entry %d has no resource object." % index)
			continue
		var resource_data := raw_resource as Dictionary
		_validate_resource_shape(resource_data, catalogue_id)
		var move_name := str(resource_data.get("move_name", "")).strip_edges()
		var output_path := _output_path(suggested_path, catalogue_id)
		if seen_ids.has(catalogue_id):
			_fail("Duplicate catalogue_id: %s" % catalogue_id)
		else:
			seen_ids[catalogue_id] = true
		var normalized_name := move_name.to_lower()
		if seen_names.has(normalized_name):
			_fail("Duplicate move_name: %s" % move_name)
		else:
			seen_names[normalized_name] = true
		if not output_path.is_empty():
			if seen_paths.has(output_path):
				_fail("Duplicate output path: %s" % output_path)
			else:
				seen_paths[output_path] = true
		var errors_before := _errors.size()
		var move := _build_move(resource_data, catalogue_id)
		if move == null or output_path.is_empty() or _errors.size() != errors_before:
			continue
		var move_type_name := str(resource_data.get("move_type", ""))
		type_counts[move_type_name] = int(type_counts.get(move_type_name, 0)) + 1
		family_counts[family] = int(family_counts.get(family, 0)) + 1
		prepared.append({
			"catalogue_id": catalogue_id,
			"family": family,
			"path": output_path,
			"move": move,
		})

	_validate_count_map("move type", type_counts, EXPECTED_TYPE_COUNTS)
	_validate_count_map("family", family_counts, EXPECTED_FAMILY_COUNTS)
	if prepared.size() != EXPECTED_ENTRY_COUNT:
		_fail("Prepared %d of %d catalogue entries." % [prepared.size(), EXPECTED_ENTRY_COUNT])
	if not _errors.is_empty():
		_finish()
		return

	var written := 0
	for item in prepared:
		var output_path := str(item.path)
		var directory_path := output_path.get_base_dir()
		var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path))
		if mkdir_error != OK:
			_fail("Could not create %s (error %d)." % [directory_path, mkdir_error])
			continue
		var save_error := ResourceSaver.save(item.move as MoveResource, output_path)
		if save_error != OK:
			_fail("Could not save %s (error %d)." % [output_path, save_error])
			continue
		written += 1

	if written != EXPECTED_ENTRY_COUNT:
		_fail("Wrote %d of %d catalogue resources." % [written, EXPECTED_ENTRY_COUNT])
	_audit_saved_resources(prepared, seen_paths)
	if _errors.is_empty():
		print("MOVE_CATALOGUE_V2_IMPORT: PASS (%d resources written and verified)" % written)
	_finish()


func _validate_resource_shape(resource_data: Dictionary, catalogue_id: String) -> void:
	for field_name in EXPECTED_RESOURCE_FIELDS:
		if not resource_data.has(field_name):
			_fail("%s is missing resource field %s." % [catalogue_id, field_name])
	for field_name in resource_data:
		if str(field_name) not in EXPECTED_RESOURCE_FIELDS:
			_fail("%s has unknown resource field %s." % [catalogue_id, str(field_name)])


func _output_path(suggested_path: String, catalogue_id: String) -> String:
	if not suggested_path.begins_with(SOURCE_PATH_PREFIX):
		_fail("%s has an invalid suggested path: %s" % [catalogue_id, suggested_path])
		return ""
	if suggested_path.get_extension().to_lower() != "tres" or suggested_path.contains(".."):
		_fail("%s has an unsafe suggested path: %s" % [catalogue_id, suggested_path])
		return ""
	var relative_path := suggested_path.trim_prefix(SOURCE_PATH_PREFIX)
	var category := relative_path.get_slice("/", 0)
	if category not in ALLOWED_CATEGORIES:
		_fail("%s has an unsupported category path: %s" % [catalogue_id, category])
		return ""
	return OUTPUT_PATH_PREFIX + relative_path


func _build_move(data: Dictionary, catalogue_id: String) -> MoveResource:
	var errors_before := _errors.size()
	var move := MoveResource.new()
	move.resource_name = str(data.get("move_name", ""))
	move.move_name = str(data.get("move_name", ""))
	move.move_type = _enum_value(MoveResource.MoveType, data.get("move_type"), "move_type", catalogue_id)
	move.class_preferrence = _class_array(data.get("class_preferrence"), catalogue_id)
	move.move_target_parts = _target_part_array(data.get("move_target_parts"), catalogue_id)
	move.targeting_mode = _enum_value(MoveResource.TargetingMode, data.get("targeting_mode"), "targeting_mode", catalogue_id)
	move.default_side_target = _enum_value(MoveResource.MoveTargetParts, data.get("default_side_target"), "default_side_target", catalogue_id)

	move.required_attacker_position = _enum_value(WrestlerResource.Position, data.get("required_attacker_position"), "required_attacker_position", catalogue_id)
	move.required_attacker_orientation = _enum_value(WrestlerResource.Orientation, data.get("required_attacker_orientation"), "required_attacker_orientation", catalogue_id)
	move.required_attacker_area_mode = _enum_value(MoveResource.AreaRequirementMode, data.get("required_attacker_area_mode"), "required_attacker_area_mode", catalogue_id)
	move.required_attacker_area = _enum_value(WrestlerResource.Area, data.get("required_attacker_area"), "required_attacker_area", catalogue_id)
	move.required_attacker_motion_state = _enum_value(WrestlerResource.MotionState, data.get("required_attacker_motion_state"), "required_attacker_motion_state", catalogue_id)

	move.required_target_position = _enum_value(WrestlerResource.Position, data.get("required_target_position"), "required_target_position", catalogue_id)
	move.required_target_orientation = _enum_value(WrestlerResource.Orientation, data.get("required_target_orientation"), "required_target_orientation", catalogue_id)
	move.required_target_area_mode = _enum_value(MoveResource.AreaRequirementMode, data.get("required_target_area_mode"), "required_target_area_mode", catalogue_id)
	move.required_target_area = _enum_value(WrestlerResource.Area, data.get("required_target_area"), "required_target_area", catalogue_id)
	move.required_target_motion_state = _enum_value(WrestlerResource.MotionState, data.get("required_target_motion_state"), "required_target_motion_state", catalogue_id)

	move.resulting_attacker_position = _enum_value(WrestlerResource.Position, data.get("resulting_attacker_position"), "resulting_attacker_position", catalogue_id)
	move.resulting_attacker_orientation = _enum_value(WrestlerResource.Orientation, data.get("resulting_attacker_orientation"), "resulting_attacker_orientation", catalogue_id)
	move.resulting_attacker_area_mode = _enum_value(MoveResource.AreaResultMode, data.get("resulting_attacker_area_mode"), "resulting_attacker_area_mode", catalogue_id)
	move.resulting_attacker_area = _enum_value(WrestlerResource.Area, data.get("resulting_attacker_area"), "resulting_attacker_area", catalogue_id)
	move.resulting_attacker_motion_state = _enum_value(WrestlerResource.MotionState, data.get("resulting_attacker_motion_state"), "resulting_attacker_motion_state", catalogue_id)

	move.resulting_target_position = _enum_value(WrestlerResource.Position, data.get("resulting_target_position"), "resulting_target_position", catalogue_id)
	move.resulting_target_orientation = _enum_value(WrestlerResource.Orientation, data.get("resulting_target_orientation"), "resulting_target_orientation", catalogue_id)
	move.resulting_target_area_mode = _enum_value(MoveResource.AreaResultMode, data.get("resulting_target_area_mode"), "resulting_target_area_mode", catalogue_id)
	move.resulting_target_area = _enum_value(WrestlerResource.Area, data.get("resulting_target_area"), "resulting_target_area", catalogue_id)
	move.resulting_target_motion_state = _enum_value(WrestlerResource.MotionState, data.get("resulting_target_motion_state"), "resulting_target_motion_state", catalogue_id)

	move.is_finisher = bool(data.get("is_finisher"))
	move.is_submission = bool(data.get("is_submission"))
	move.is_flash_pin = bool(data.get("is_flash_pin"))
	move.is_pinning_combination = bool(data.get("is_pinning_combination"))
	move.interaction_override = _enum_value(MoveResource.InteractionOverride, data.get("interaction_override"), "interaction_override", catalogue_id)
	move.is_strike = bool(data.get("is_strike"))
	move.strike_weight = _enum_value(MoveResource.StrikeWeight, data.get("strike_weight"), "strike_weight", catalogue_id)
	move.move_impact = int(data.get("move_impact", 0))
	if move.move_name.strip_edges().is_empty():
		_fail("%s has an empty move_name." % catalogue_id)
	if move.move_impact < 1 or move.move_impact > 10:
		_fail("%s has invalid move_impact %d." % [catalogue_id, move.move_impact])
	return null if _errors.size() != errors_before else move


func _class_array(value: Variant, catalogue_id: String) -> Array[WrestlerResource.WrestlerClass]:
	var result: Array[WrestlerResource.WrestlerClass] = []
	if not value is Array:
		_fail("%s class_preferrence must be an array." % catalogue_id)
		return result
	for entry in value as Array:
		result.append(_enum_value(WrestlerResource.WrestlerClass, entry, "class_preferrence", catalogue_id) as WrestlerResource.WrestlerClass)
	return result


func _target_part_array(value: Variant, catalogue_id: String) -> Array[MoveResource.MoveTargetParts]:
	var result: Array[MoveResource.MoveTargetParts] = []
	if not value is Array:
		_fail("%s move_target_parts must be an array." % catalogue_id)
		return result
	for entry in value as Array:
		result.append(_enum_value(MoveResource.MoveTargetParts, entry, "move_target_parts", catalogue_id) as MoveResource.MoveTargetParts)
	return result


func _enum_value(values: Dictionary, raw_value: Variant, field_name: String, catalogue_id: String) -> int:
	var key := str(raw_value).strip_edges().to_upper()
	if values.has(key):
		return int(values[key])
	_fail("%s has invalid %s value '%s'." % [catalogue_id, field_name, str(raw_value)])
	return 0


func _validate_count_map(label: String, actual: Dictionary, expected: Dictionary) -> void:
	for key in expected:
		if int(actual.get(key, 0)) != int(expected[key]):
			_fail("Unexpected %s count for %s: expected %d, found %d." % [label, key, int(expected[key]), int(actual.get(key, 0))])
	for key in actual:
		if not expected.has(key):
			_fail("Unexpected %s value %s (%d entries)." % [label, key, int(actual[key])])


func _audit_saved_resources(prepared: Array[Dictionary], expected_paths: Dictionary) -> void:
	var verified := 0
	for item in prepared:
		var path := str(item.path)
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not loaded is MoveResource:
			_fail("Generated resource does not reload as MoveResource: %s" % path)
			continue
		var mismatches := _move_mismatches(item.move as MoveResource, loaded as MoveResource)
		if not mismatches.is_empty():
			_fail("Round-trip mismatch in %s: %s" % [path, ", ".join(mismatches)])
			continue
		verified += 1
	if verified != EXPECTED_ENTRY_COUNT:
		_fail("Reloaded and verified %d of %d generated resources." % [verified, EXPECTED_ENTRY_COUNT])

	var generated_paths: Array[String] = []
	for category in ALLOWED_CATEGORIES:
		_collect_tres_paths(OUTPUT_PATH_PREFIX.path_join(category), generated_paths)
	if generated_paths.size() != EXPECTED_ENTRY_COUNT:
		_fail("Generated category folders contain %d resources, expected %d." % [generated_paths.size(), EXPECTED_ENTRY_COUNT])
	for path in generated_paths:
		if not expected_paths.has(path):
			_fail("Unexpected stale generated resource: %s" % path)
		if path.contains("/Rebuilt/"):
			_fail("Generated resource retained the Rebuilt path layer: %s" % path)

	var all_move_paths: Array[String] = []
	_collect_tres_paths("res://Moves", all_move_paths)
	if all_move_paths.size() != EXPECTED_TOTAL_MOVE_RESOURCES:
		_fail("Moves folder contains %d resources, expected %d." % [all_move_paths.size(), EXPECTED_TOTAL_MOVE_RESOURCES])


func _move_mismatches(expected: MoveResource, actual: MoveResource) -> PackedStringArray:
	var result := PackedStringArray()
	_check_equal(result, "move_name", expected.move_name, actual.move_name)
	_check_equal(result, "move_type", expected.move_type, actual.move_type)
	_check_equal(result, "class_preferrence", expected.class_preferrence, actual.class_preferrence)
	_check_equal(result, "move_target_parts", expected.move_target_parts, actual.move_target_parts)
	_check_equal(result, "targeting_mode", expected.targeting_mode, actual.targeting_mode)
	_check_equal(result, "default_side_target", expected.default_side_target, actual.default_side_target)
	_check_equal(result, "required_attacker_position", expected.required_attacker_position, actual.required_attacker_position)
	_check_equal(result, "required_attacker_orientation", expected.required_attacker_orientation, actual.required_attacker_orientation)
	_check_equal(result, "required_attacker_area_mode", expected.required_attacker_area_mode, actual.required_attacker_area_mode)
	_check_equal(result, "required_attacker_area", expected.required_attacker_area, actual.required_attacker_area)
	_check_equal(result, "required_attacker_motion_state", expected.required_attacker_motion_state, actual.required_attacker_motion_state)
	_check_equal(result, "required_target_position", expected.required_target_position, actual.required_target_position)
	_check_equal(result, "required_target_orientation", expected.required_target_orientation, actual.required_target_orientation)
	_check_equal(result, "required_target_area_mode", expected.required_target_area_mode, actual.required_target_area_mode)
	_check_equal(result, "required_target_area", expected.required_target_area, actual.required_target_area)
	_check_equal(result, "required_target_motion_state", expected.required_target_motion_state, actual.required_target_motion_state)
	_check_equal(result, "resulting_attacker_position", expected.resulting_attacker_position, actual.resulting_attacker_position)
	_check_equal(result, "resulting_attacker_orientation", expected.resulting_attacker_orientation, actual.resulting_attacker_orientation)
	_check_equal(result, "resulting_attacker_area_mode", expected.resulting_attacker_area_mode, actual.resulting_attacker_area_mode)
	_check_equal(result, "resulting_attacker_area", expected.resulting_attacker_area, actual.resulting_attacker_area)
	_check_equal(result, "resulting_attacker_motion_state", expected.resulting_attacker_motion_state, actual.resulting_attacker_motion_state)
	_check_equal(result, "resulting_target_position", expected.resulting_target_position, actual.resulting_target_position)
	_check_equal(result, "resulting_target_orientation", expected.resulting_target_orientation, actual.resulting_target_orientation)
	_check_equal(result, "resulting_target_area_mode", expected.resulting_target_area_mode, actual.resulting_target_area_mode)
	_check_equal(result, "resulting_target_area", expected.resulting_target_area, actual.resulting_target_area)
	_check_equal(result, "resulting_target_motion_state", expected.resulting_target_motion_state, actual.resulting_target_motion_state)
	_check_equal(result, "is_finisher", expected.is_finisher, actual.is_finisher)
	_check_equal(result, "is_submission", expected.is_submission, actual.is_submission)
	_check_equal(result, "is_flash_pin", expected.is_flash_pin, actual.is_flash_pin)
	_check_equal(result, "is_pinning_combination", expected.is_pinning_combination, actual.is_pinning_combination)
	_check_equal(result, "interaction_override", expected.interaction_override, actual.interaction_override)
	_check_equal(result, "is_strike", expected.is_strike, actual.is_strike)
	_check_equal(result, "strike_weight", expected.strike_weight, actual.strike_weight)
	_check_equal(result, "move_impact", expected.move_impact, actual.move_impact)
	return result


func _check_equal(mismatches: PackedStringArray, field_name: String, expected: Variant, actual: Variant) -> void:
	if expected != actual:
		mismatches.append(field_name)


func _collect_tres_paths(directory_path: String, results: Array[String]) -> void:
	for entry in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_tres_paths(directory_path.path_join(entry.trim_suffix("/")), results)
		elif entry.get_extension().to_lower() == "tres":
			results.append(directory_path.path_join(entry))


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
