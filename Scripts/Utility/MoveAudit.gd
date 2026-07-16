@tool
extends EditorScript
class_name MoveAuditGenerator

const MOVE_ROOT: String = "res://Moves"
const OUTPUT_PATH: String = "res://move_audit_report.txt"

func _run() -> void:
	var move_paths: Array[String] = []
	_collect_move_paths(MOVE_ROOT, move_paths)

	if move_paths.is_empty():
		push_error("No move resources found under %s" % MOVE_ROOT)
		return

	var moves: Array[Dictionary] = []
	var type_counts: Dictionary = {}
	var finisher_count: int = 0
	var non_finisher_count: int = 0
	var submission_count: int = 0
	var strike_count: int = 0
	var duplicate_name_map: Dictionary = {}
	var warnings: Array[String] = []

	for move_path: String in move_paths:
		var resource: Resource = load(move_path)
		if not (resource is MoveResource):
			continue

		var move: MoveResource = resource as MoveResource
		var move_type_name: String = _move_type_to_string(move.move_type)

		if not type_counts.has(move_type_name):
			type_counts[move_type_name] = 0
		type_counts[move_type_name] += 1

		if move.is_finisher:
			finisher_count += 1
		else:
			non_finisher_count += 1

		if move.is_submission:
			submission_count += 1

		if move.is_strike:
			strike_count += 1

		var normalized_name: String = move.move_name.strip_edges().to_lower()
		if not duplicate_name_map.has(normalized_name):
			duplicate_name_map[normalized_name] = []
		duplicate_name_map[normalized_name].append(move_path)

		var move_warnings: Array[String] = _validate_move(move, move_path)
		for w in move_warnings:
			warnings.append(w)

		moves.append({
			"name": move.move_name,
			"path": move_path,
			"type": move_type_name,
			"impact": move.move_impact,
			"finisher": move.is_finisher,
			"submission": move.is_submission,
			"strike": move.is_strike,
			"classes": _class_array_to_string(move.class_preferrence),
			"parts": _parts_array_to_string(move.move_target_parts),
			"targeting_mode": _targeting_mode_to_string(move.targeting_mode),
			"default_target": MoveTargetResolver.part_label(move.default_side_target),
			"req_attacker": _position_to_string(move.required_attacker_position),
			"req_target": _position_to_string(move.required_target_position),
			"res_attacker": _position_to_string(move.resulting_attacker_position),
			"res_target": _position_to_string(move.resulting_target_position)
		})

	moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["type"] == b["type"]:
			return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
		return str(a["type"]).naturalnocasecmp_to(str(b["type"])) < 0
	)

	var lines: Array[String] = []
	lines.append("MOVE AUDIT REPORT")
	lines.append("=".repeat(100))
	lines.append("")
	lines.append("Move root: %s" % MOVE_ROOT)
	lines.append("Output file: %s" % OUTPUT_PATH)
	lines.append("Total move resources: %s" % str(moves.size()))
	lines.append("Finishers: %s" % str(finisher_count))
	lines.append("Non-finishers: %s" % str(non_finisher_count))
	lines.append("Submissions: %s" % str(submission_count))
	lines.append("Strikes: %s" % str(strike_count))
	lines.append("")

	lines.append("COUNTS BY MOVE TYPE")
	lines.append("-".repeat(100))
	var sorted_types: Array[String] = []
	for k in type_counts.keys():
		sorted_types.append(str(k))
	sorted_types.sort()
	for type_name: String in sorted_types:
		lines.append("%-20s %s" % [type_name + ":", str(type_counts[type_name])])
	lines.append("")

	lines.append("DUPLICATE MOVE NAMES")
	lines.append("-".repeat(100))
	var has_duplicates: bool = false
	var duplicate_keys: Array[String] = []
	for k in duplicate_name_map.keys():
		duplicate_keys.append(str(k))
	duplicate_keys.sort()

	for duplicate_name: String in duplicate_keys:
		var paths: Array = duplicate_name_map[duplicate_name]
		if paths.size() > 1:
			has_duplicates = true
			lines.append("Name: %s" % duplicate_name)
			for p in paths:
				lines.append("  - %s" % str(p))
	if not has_duplicates:
		lines.append("[None]")
	lines.append("")

	lines.append("WARNINGS")
	lines.append("-".repeat(100))
	if warnings.is_empty():
		lines.append("[None]")
	else:
		for w in warnings:
			lines.append("- %s" % w)
	lines.append("")

	lines.append("FULL MOVE LIST")
	lines.append("=".repeat(100))
	lines.append("")

	var current_type: String = ""
	for entry: Dictionary in moves:
		if entry["type"] != current_type:
			current_type = entry["type"]
			lines.append(current_type.to_upper())
			lines.append("~".repeat(60))

		lines.append("Name: %s" % entry["name"])
		lines.append("  Path: %s" % entry["path"])
		lines.append("  Impact: %s | Finisher: %s | Submission: %s | Strike: %s" % [
			str(entry["impact"]),
			str(entry["finisher"]),
			str(entry["submission"]),
			str(entry["strike"])
		])
		lines.append("  Classes: %s" % entry["classes"])
		lines.append("  Target Parts: %s" % entry["parts"])
		lines.append("  Targeting: %s | Default side: %s" % [entry["targeting_mode"], entry["default_target"]])
		lines.append("  Required Positions: Attacker=%s | Target=%s" % [
			entry["req_attacker"], entry["req_target"]
		])
		lines.append("  Result Positions:   Attacker=%s | Target=%s" % [
			entry["res_attacker"], entry["res_target"]
		])
		lines.append("")

	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open output file for writing: %s" % OUTPUT_PATH)
		return

	file.store_string("\n".join(lines))
	file.close()

	print("Move audit report written to: ", OUTPUT_PATH)


func _collect_move_paths(dir_path: String, results: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("Could not open directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var item_name: String = dir.get_next()

	while item_name != "":
		if item_name.begins_with("."):
			item_name = dir.get_next()
			continue

		var full_path: String = dir_path.path_join(item_name)

		if dir.current_is_dir():
			_collect_move_paths(full_path, results)
		elif item_name.get_extension().to_lower() == "tres":
			var resource: Resource = load(full_path)
			if resource is MoveResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()


func _validate_move(move: MoveResource, move_path: String) -> Array[String]:
	var warnings: Array[String] = []

	if move.move_name.strip_edges().is_empty():
		warnings.append("%s has an empty move_name." % move_path)

	if move.move_type == MoveResource.MoveType.NONE:
		warnings.append("%s has move_type NONE." % move.move_name)

	if move.class_preferrence.is_empty():
		warnings.append("%s has no class_preferrence set." % move.move_name)

	if move.move_target_parts.is_empty():
		warnings.append("%s has no target parts set." % move.move_name)

	var has_left_arm := MoveResource.MoveTargetParts.LEFT_ARM in move.move_target_parts
	var has_right_arm := MoveResource.MoveTargetParts.RIGHT_ARM in move.move_target_parts
	var has_left_leg := MoveResource.MoveTargetParts.LEFT_LEG in move.move_target_parts
	var has_right_leg := MoveResource.MoveTargetParts.RIGHT_LEG in move.move_target_parts
	match move.targeting_mode:
		MoveResource.TargetingMode.CHOOSE_ARM:
			if not has_left_arm or not has_right_arm:
				warnings.append("%s uses CHOOSE_ARM without both arm targets." % move.move_name)
			if move.default_side_target not in [
				MoveResource.MoveTargetParts.LEFT_ARM,
				MoveResource.MoveTargetParts.RIGHT_ARM,
			]:
				warnings.append("%s has an invalid default arm target." % move.move_name)
		MoveResource.TargetingMode.CHOOSE_LEG:
			if not has_left_leg or not has_right_leg:
				warnings.append("%s uses CHOOSE_LEG without both leg targets." % move.move_name)
			if move.default_side_target not in [
				MoveResource.MoveTargetParts.LEFT_LEG,
				MoveResource.MoveTargetParts.RIGHT_LEG,
			]:
				warnings.append("%s has an invalid default leg target." % move.move_name)
		MoveResource.TargetingMode.BOTH_ARMS:
			if not has_left_arm or not has_right_arm:
				warnings.append("%s uses BOTH_ARMS without both arm targets." % move.move_name)
			if move.default_side_target != MoveResource.MoveTargetParts.NONE:
				warnings.append("%s uses BOTH_ARMS with an unnecessary side default." % move.move_name)
		MoveResource.TargetingMode.BOTH_LEGS:
			if not has_left_leg or not has_right_leg:
				warnings.append("%s uses BOTH_LEGS without both leg targets." % move.move_name)
			if move.default_side_target != MoveResource.MoveTargetParts.NONE:
				warnings.append("%s uses BOTH_LEGS with an unnecessary side default." % move.move_name)
		_:
			if move.default_side_target != MoveResource.MoveTargetParts.NONE:
				warnings.append("%s uses FIXED_PARTS with an unnecessary side default." % move.move_name)
			if (has_left_arm and has_right_arm) or (has_left_leg and has_right_leg):
				if move.move_name != "Bow and Arrow Hold":
					warnings.append("%s has an unclassified paired-limb target." % move.move_name)

	if move.required_attacker_position == WrestlerResource.Position.NONE:
		warnings.append("%s has required_attacker_position NONE." % move.move_name)

	if move.required_target_position == WrestlerResource.Position.NONE:
		warnings.append("%s has required_target_position NONE." % move.move_name)

	if move.resulting_attacker_position == WrestlerResource.Position.NONE:
		warnings.append("%s has resulting_attacker_position NONE." % move.move_name)

	if move.resulting_target_position == WrestlerResource.Position.NONE:
		warnings.append("%s has resulting_target_position NONE." % move.move_name)

	if move.move_impact < 1 or move.move_impact > 10:
		warnings.append("%s has out-of-range move_impact: %s." % [move.move_name, str(move.move_impact)])

	if move.is_submission and move.is_strike:
		warnings.append("%s is both submission and strike." % move.move_name)

	var expected_positions := _expected_positions_for_type(move.move_type)
	if not expected_positions.is_empty():
		var expected_attacker: int = expected_positions[0]
		var expected_target: int = expected_positions[1]
		if (
			move.required_attacker_position != expected_attacker
			or move.required_target_position != expected_target
		):
			warnings.append(
				"%s has incoherent required positions for %s: %s/%s." % [
					move.move_name,
					_move_type_to_string(move.move_type),
					_position_to_string(move.required_attacker_position),
					_position_to_string(move.required_target_position),
				],
			)

	return warnings


func _expected_positions_for_type(move_type: MoveResource.MoveType) -> Array[int]:
	match move_type:
		MoveResource.MoveType.ROPE_REBOUND:
			return [WrestlerResource.Position.STANDING, WrestlerResource.Position.ROPE_REBOUND]
		MoveResource.MoveType.SPRINGBOARD:
			return [WrestlerResource.Position.APRON, WrestlerResource.Position.STANDING]
		MoveResource.MoveType.CORNER:
			return [WrestlerResource.Position.STANDING, WrestlerResource.Position.IN_CORNER]
		MoveResource.MoveType.DIVING_STANDING:
			return [WrestlerResource.Position.TOP_ROPE, WrestlerResource.Position.STANDING]
		MoveResource.MoveType.DIVING_GROUNDED:
			return [WrestlerResource.Position.TOP_ROPE, WrestlerResource.Position.GROUNDED]
		_:
			return []


func _move_type_to_string(move_type: MoveResource.MoveType) -> String:
	match move_type:
		MoveResource.MoveType.STANDING_FRONT:
			return "Standing_Front"
		MoveResource.MoveType.STANDING_BEHIND:
			return "Standing_Behind"
		MoveResource.MoveType.RUNNING:
			return "Running"
		MoveResource.MoveType.ROPE_REBOUND:
			return "Rope_Rebound"
		MoveResource.MoveType.GROUNDED:
			return "Grounded"
		MoveResource.MoveType.SPRINGBOARD:
			return "Springboard"
		MoveResource.MoveType.CORNER:
			return "Corner"
		MoveResource.MoveType.DIVING_STANDING:
			return "Diving_Standing"
		MoveResource.MoveType.DIVING_GROUNDED:
			return "Diving_Grounded"
		_:
			return "None"


func _targeting_mode_to_string(mode: MoveResource.TargetingMode) -> String:
	match mode:
		MoveResource.TargetingMode.CHOOSE_ARM:
			return "Choose Arm"
		MoveResource.TargetingMode.CHOOSE_LEG:
			return "Choose Leg"
		MoveResource.TargetingMode.BOTH_ARMS:
			return "Both Arms"
		MoveResource.TargetingMode.BOTH_LEGS:
			return "Both Legs"
		_:
			return "Fixed Parts"


func _position_to_string(position: WrestlerResource.Position) -> String:
	match position:
		WrestlerResource.Position.STANDING:
			return "Standing"
		WrestlerResource.Position.GROUNDED:
			return "Grounded"
		WrestlerResource.Position.IN_CORNER:
			return "In_Corner"
		WrestlerResource.Position.RUNNING:
			return "Running"
		WrestlerResource.Position.ROPE_REBOUND:
			return "Rope_Rebound"
		WrestlerResource.Position.TOP_ROPE:
			return "Top_Rope"
		WrestlerResource.Position.APRON:
			return "Apron"
		_:
			return "None"


func _class_array_to_string(classes: Array[WrestlerResource.WrestlerClass]) -> String:
	var names: Array[String] = []

	for c: WrestlerResource.WrestlerClass in classes:
		match c:
			WrestlerResource.WrestlerClass.HIGH_FLYER:
				names.append("High Flyer")
			WrestlerResource.WrestlerClass.POWERHOUSE:
				names.append("Powerhouse")
			WrestlerResource.WrestlerClass.TECHNICIAN:
				names.append("Technician")
			WrestlerResource.WrestlerClass.STRIKER:
				names.append("Striker")
			WrestlerResource.WrestlerClass.HARDCORE:
				names.append("Hardcore")
			_:
				names.append("Unknown")

	return ", ".join(names)


func _parts_array_to_string(parts: Array[MoveResource.MoveTargetParts]) -> String:
	var names: Array[String] = []

	for p: MoveResource.MoveTargetParts in parts:
		match p:
			MoveResource.MoveTargetParts.HEAD:
				names.append("Head")
			MoveResource.MoveTargetParts.BODY:
				names.append("Body")
			MoveResource.MoveTargetParts.LEFT_ARM:
				names.append("Left Arm")
			MoveResource.MoveTargetParts.RIGHT_ARM:
				names.append("Right Arm")
			MoveResource.MoveTargetParts.LEFT_LEG:
				names.append("Left Leg")
			MoveResource.MoveTargetParts.RIGHT_LEG:
				names.append("Right Leg")
			_:
				names.append("None")

	return ", ".join(names)
