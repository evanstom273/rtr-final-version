@tool
extends EditorScript
class_name MovesetAuditGenerator

const WRESTLER_ROOT: String = "res://Wrestlers"
const OUTPUT_PATH: String = "res://moveset_audit_report.txt"

const MIN_EXPECTED_MOVES: int = 50
const MAX_EXPECTED_MOVES: int = 50
const EXPECTED_FINISHERS: int = 3

const MIN_STANDING_FRONT: int = 6
const MIN_RUNNING_OR_REBOUND: int = 3
const MIN_GROUNDED: int = 3

const MAX_SPRINGBOARD_NON_FLYER: int = 1
const MAX_DIVING_NON_FLYER: int = 2

const MAX_SUBMISSIONS_NON_TECHNICIAN: int = 4
const MAX_SUBMISSIONS_TECHNICIAN: int = 10

const MAX_STRIKES_NON_STRIKER: int = 8
const MAX_STRIKES_STRIKER: int = 16

const MIN_STRIKER_REGULAR_STRIKES: int = 10
const MIN_STRIKER_NON_STRIKE_STYLE_MOVES: int = 14

const MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL: int = 8
const MIN_HIGH_FLYER_REGULAR_SPRINGBOARD: int = 2
const MIN_HIGH_FLYER_REGULAR_DIVING_STANDING: int = 2
const MIN_HIGH_FLYER_REGULAR_DIVING_GROUNDED: int = 2

const MIN_POWERHOUSE_REGULAR_STANDING_FRONT: int = 8
const MIN_TECHNICIAN_REGULAR_SUBMISSIONS: int = 4
const MIN_HARDCORE_BRAWL_OR_GROUNDED: int = 6


func _run() -> void:
	var wrestler_paths: Array[String] = []
	_collect_wrestler_paths(WRESTLER_ROOT, wrestler_paths)

	if wrestler_paths.is_empty():
		push_error("No wrestler resources found under %s" % WRESTLER_ROOT)
		return

	var wrestler_entries: Array[Dictionary] = []
	var hard_issues: Array[String] = []
	var soft_warnings: Array[String] = []

	var move_usage_map: Dictionary = {}
	var finisher_usage_map: Dictionary = {}
	var primary_class_counts: Dictionary = {}
	var all_class_counts: Dictionary = {}

	var total_moves_assigned: int = 0
	var total_regular_moves_assigned: int = 0
	var total_finishers_assigned: int = 0

	var wrestlers_with_empty_movesets: int = 0
	var wrestlers_with_wrong_finisher_count: int = 0
	var wrestlers_under_min: int = 0
	var wrestlers_over_max: int = 0
	var wrestlers_with_duplicate_names: int = 0
	var wrestlers_with_duplicate_resources: int = 0

	for wrestler_path: String in wrestler_paths:
		var resource: Resource = load(wrestler_path)
		if not (resource is WrestlerResource):
			continue

		var wrestler: WrestlerResource = resource as WrestlerResource
		var move_set: Array[MoveResource] = wrestler.move_set

		var display_name: String = _get_wrestler_display_name(wrestler)
		var classes_string: String = _class_array_to_string(wrestler.wrestler_class)
		var primary_class: WrestlerResource.WrestlerClass = _get_primary_class(wrestler)
		var primary_class_label: String = _class_to_string(primary_class)

		if not primary_class_counts.has(primary_class_label):
			primary_class_counts[primary_class_label] = 0
		primary_class_counts[primary_class_label] += 1

		for wrestler_class: WrestlerResource.WrestlerClass in wrestler.wrestler_class:
			var class_label: String = _class_to_string(wrestler_class)
			if not all_class_counts.has(class_label):
				all_class_counts[class_label] = 0
			all_class_counts[class_label] += 1

		var stats: Dictionary = _build_moveset_stats(move_set)

		var total_count: int = int(stats["total_count"])
		var regular_count: int = int(stats["regular_count"])
		var finisher_count: int = int(stats["finisher_count"])

		total_moves_assigned += total_count
		total_regular_moves_assigned += regular_count
		total_finishers_assigned += finisher_count

		if total_count == 0:
			wrestlers_with_empty_movesets += 1
		if total_count < MIN_EXPECTED_MOVES:
			wrestlers_under_min += 1
		if total_count > MAX_EXPECTED_MOVES:
			wrestlers_over_max += 1
		if finisher_count != EXPECTED_FINISHERS:
			wrestlers_with_wrong_finisher_count += 1

		var per_hard_issues: Array[String] = []
		var per_soft_warnings: Array[String] = []

		_validate_hard_rules(wrestler, display_name, stats, per_hard_issues)
		_validate_soft_flavour_rules(wrestler, display_name, stats, per_soft_warnings)

		if int(stats["duplicate_name_count"]) > 0:
			wrestlers_with_duplicate_names += 1

		if int(stats["duplicate_resource_count"]) > 0:
			wrestlers_with_duplicate_resources += 1

		for move: MoveResource in move_set:
			if move == null:
				continue

			var move_name: String = move.move_name

			if not move_usage_map.has(move_name):
				move_usage_map[move_name] = 0
			move_usage_map[move_name] += 1

			if move.is_finisher:
				if not finisher_usage_map.has(move_name):
					finisher_usage_map[move_name] = 0
				finisher_usage_map[move_name] += 1

		for issue: String in per_hard_issues:
			hard_issues.append(issue)

		for warning: String in per_soft_warnings:
			soft_warnings.append(warning)

		wrestler_entries.append({
			"name": display_name,
			"path": wrestler_path,
			"classes": classes_string,
			"primary_class": primary_class_label,
			"stats": stats,
			"hard_issues": per_hard_issues,
			"soft_warnings": per_soft_warnings,
			"moves": _moveset_to_lines(move_set)
		})

	wrestler_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
	)

	var lines: Array[String] = []

	lines.append("MOVESET AUDIT REPORT")
	lines.append("=".repeat(100))
	lines.append("")
	lines.append("Wrestler root: %s" % WRESTLER_ROOT)
	lines.append("Output file: %s" % OUTPUT_PATH)
	lines.append("Total wrestlers scanned: %s" % str(wrestler_entries.size()))
	lines.append("Total assigned moves across roster: %s" % str(total_moves_assigned))
	lines.append("Total regular moves across roster: %s" % str(total_regular_moves_assigned))
	lines.append("Total finishers across roster: %s" % str(total_finishers_assigned))
	lines.append("")

	lines.append("ROSTER SUMMARY")
	lines.append("-".repeat(100))
	lines.append("Empty movesets: %s" % str(wrestlers_with_empty_movesets))
	lines.append("Under %s moves: %s" % [str(MIN_EXPECTED_MOVES), str(wrestlers_under_min)])
	lines.append("Over %s moves: %s" % [str(MAX_EXPECTED_MOVES), str(wrestlers_over_max)])
	lines.append("Wrong finisher count: %s" % str(wrestlers_with_wrong_finisher_count))
	lines.append("Wrestlers with duplicate move names: %s" % str(wrestlers_with_duplicate_names))
	lines.append("Wrestlers with duplicate move resources: %s" % str(wrestlers_with_duplicate_resources))
	lines.append("Hard issues: %s" % str(hard_issues.size()))
	lines.append("Soft warnings: %s" % str(soft_warnings.size()))
	lines.append("")

	lines.append("PRIMARY CLASS COUNTS")
	lines.append("-".repeat(100))
	_append_count_table(lines, primary_class_counts)
	lines.append("")

	lines.append("ALL CLASS MEMBERSHIP COUNTS")
	lines.append("-".repeat(100))
	_append_count_table(lines, all_class_counts)
	lines.append("")

	lines.append("MOST USED MOVES ACROSS ROSTER")
	lines.append("-".repeat(100))
	_append_usage_table(lines, move_usage_map, 50)
	lines.append("")

	lines.append("MOST USED FINISHERS ACROSS ROSTER")
	lines.append("-".repeat(100))
	_append_usage_table(lines, finisher_usage_map, 50)
	lines.append("")

	lines.append("HARD ISSUES")
	lines.append("-".repeat(100))
	if hard_issues.is_empty():
		lines.append("[None]")
	else:
		for issue: String in hard_issues:
			lines.append("- %s" % issue)
	lines.append("")

	lines.append("SOFT WARNINGS")
	lines.append("-".repeat(100))
	if soft_warnings.is_empty():
		lines.append("[None]")
	else:
		for warning: String in soft_warnings:
			lines.append("- %s" % warning)
	lines.append("")

	lines.append("FULL WRESTLER MOVESET BREAKDOWN")
	lines.append("=".repeat(100))
	lines.append("")

	for entry: Dictionary in wrestler_entries:
		var stats: Dictionary = entry["stats"]

		lines.append("Name: %s" % entry["name"])
		lines.append("  Path: %s" % entry["path"])
		lines.append("  Classes: %s" % entry["classes"])
		lines.append("  Primary Class: %s" % entry["primary_class"])

		lines.append("  Move Count: %s | Regular: %s | Finishers: %s" % [
			str(stats["total_count"]),
			str(stats["regular_count"]),
			str(stats["finisher_count"])
		])

		lines.append("  Total Traits: Submissions=%s | Strikes=%s | Springboards=%s | Diving=%s" % [
			str(stats["submission_total_count"]),
			str(stats["strike_total_count"]),
			str(stats["springboard_total_count"]),
			str(stats["diving_total_count"])
		])

		lines.append("  Regular Traits: Submissions=%s | Strikes=%s | Springboards=%s | Diving=%s | Aerial=%s | StrikerStyle=%s | StrikerNonStrike=%s" % [
			str(stats["submission_regular_count"]),
			str(stats["strike_regular_count"]),
			str(stats["springboard_regular_count"]),
			str(stats["diving_regular_count"]),
			str(stats["aerial_regular_count"]),
			str(stats["striker_style_regular_count"]),
			str(stats["striker_non_strike_style_regular_count"])
		])

		lines.append("  Finisher Traits: Submissions=%s | Strikes=%s | Springboards=%s | Diving=%s" % [
			str(stats["submission_finisher_count"]),
			str(stats["strike_finisher_count"]),
			str(stats["springboard_finisher_count"]),
			str(stats["diving_finisher_count"])
		])

		lines.append("  Regular Type Counts: SF=%s | SB=%s | Run=%s | Rebound=%s | Grounded=%s | Springboard=%s | Corner=%s | DiveS=%s | DiveG=%s" % [
			str(stats["standing_front_regular_count"]),
			str(stats["standing_behind_regular_count"]),
			str(stats["running_regular_count"]),
			str(stats["rebound_regular_count"]),
			str(stats["grounded_regular_count"]),
			str(stats["springboard_regular_count"]),
			str(stats["corner_regular_count"]),
			str(stats["diving_standing_regular_count"]),
			str(stats["diving_grounded_regular_count"])
		])

		lines.append("  Finisher Type Counts: SF=%s | SB=%s | Run=%s | Rebound=%s | Grounded=%s | Springboard=%s | Corner=%s | DiveS=%s | DiveG=%s" % [
			str(stats["standing_front_finisher_count"]),
			str(stats["standing_behind_finisher_count"]),
			str(stats["running_finisher_count"]),
			str(stats["rebound_finisher_count"]),
			str(stats["grounded_finisher_count"]),
			str(stats["springboard_finisher_count"]),
			str(stats["corner_finisher_count"]),
			str(stats["diving_standing_finisher_count"]),
			str(stats["diving_grounded_finisher_count"])
		])

		lines.append("  Duplicate Move Names: %s" % str(stats["duplicate_name_count"]))
		if not Array(stats["duplicate_name_lines"]).is_empty():
			for duplicate_line: String in stats["duplicate_name_lines"]:
				lines.append("    - %s" % duplicate_line)

		lines.append("  Duplicate Move Resources: %s" % str(stats["duplicate_resource_count"]))
		if not Array(stats["duplicate_resource_lines"]).is_empty():
			for duplicate_line: String in stats["duplicate_resource_lines"]:
				lines.append("    - %s" % duplicate_line)

		lines.append("  Hard Issues: %s" % str(Array(entry["hard_issues"]).size()))
		if Array(entry["hard_issues"]).is_empty():
			lines.append("    [None]")
		else:
			for issue: String in entry["hard_issues"]:
				lines.append("    - %s" % issue)

		lines.append("  Soft Warnings: %s" % str(Array(entry["soft_warnings"]).size()))
		if Array(entry["soft_warnings"]).is_empty():
			lines.append("    [None]")
		else:
			for warning: String in entry["soft_warnings"]:
				lines.append("    - %s" % warning)

		lines.append("  Moves:")
		for move_line: String in entry["moves"]:
			lines.append("    %s" % move_line)

		lines.append("")

	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open output file for writing: %s" % OUTPUT_PATH)
		return

	file.store_string("\n".join(lines))
	file.close()

	print("Moveset audit report written to: ", OUTPUT_PATH)


func _build_moveset_stats(move_set: Array[MoveResource]) -> Dictionary:
	var stats: Dictionary = {
		"total_count": 0,
		"regular_count": 0,
		"finisher_count": 0,

		"submission_total_count": 0,
		"submission_regular_count": 0,
		"submission_finisher_count": 0,

		"strike_total_count": 0,
		"strike_regular_count": 0,
		"strike_finisher_count": 0,

		"springboard_total_count": 0,
		"springboard_regular_count": 0,
		"springboard_finisher_count": 0,

		"diving_total_count": 0,
		"diving_regular_count": 0,
		"diving_finisher_count": 0,

		"aerial_regular_count": 0,

		"standing_front_regular_count": 0,
		"standing_behind_regular_count": 0,
		"running_regular_count": 0,
		"rebound_regular_count": 0,
		"grounded_regular_count": 0,
		"corner_regular_count": 0,
		"diving_standing_regular_count": 0,
		"diving_grounded_regular_count": 0,

		"standing_front_finisher_count": 0,
		"standing_behind_finisher_count": 0,
		"running_finisher_count": 0,
		"rebound_finisher_count": 0,
		"grounded_finisher_count": 0,
		"corner_finisher_count": 0,
		"diving_standing_finisher_count": 0,
		"diving_grounded_finisher_count": 0,

		"striker_style_regular_count": 0,
		"striker_non_strike_style_regular_count": 0,

		"null_move_count": 0,
		"duplicate_name_count": 0,
		"duplicate_resource_count": 0,
		"duplicate_name_lines": [],
		"duplicate_resource_lines": []
	}

	var name_map: Dictionary = {}
	var resource_map: Dictionary = {}

	for move: MoveResource in move_set:
		stats["total_count"] = int(stats["total_count"]) + 1

		if move == null:
			stats["null_move_count"] = int(stats["null_move_count"]) + 1
			continue

		var is_finisher: bool = move.is_finisher

		if is_finisher:
			stats["finisher_count"] = int(stats["finisher_count"]) + 1
		else:
			stats["regular_count"] = int(stats["regular_count"]) + 1

		if not is_finisher:
			if move.class_preferrence.has(WrestlerResource.WrestlerClass.STRIKER):
				stats["striker_style_regular_count"] = int(stats["striker_style_regular_count"]) + 1

				if not move.is_strike:
					stats["striker_non_strike_style_regular_count"] = int(stats["striker_non_strike_style_regular_count"]) + 1

		if move.is_submission:
			stats["submission_total_count"] = int(stats["submission_total_count"]) + 1
			if is_finisher:
				stats["submission_finisher_count"] = int(stats["submission_finisher_count"]) + 1
			else:
				stats["submission_regular_count"] = int(stats["submission_regular_count"]) + 1

		if move.is_strike:
			stats["strike_total_count"] = int(stats["strike_total_count"]) + 1
			if is_finisher:
				stats["strike_finisher_count"] = int(stats["strike_finisher_count"]) + 1
			else:
				stats["strike_regular_count"] = int(stats["strike_regular_count"]) + 1

		match move.move_type:
			MoveResource.MoveType.STANDING_FRONT:
				if is_finisher:
					stats["standing_front_finisher_count"] = int(stats["standing_front_finisher_count"]) + 1
				else:
					stats["standing_front_regular_count"] = int(stats["standing_front_regular_count"]) + 1

			MoveResource.MoveType.STANDING_BEHIND:
				if is_finisher:
					stats["standing_behind_finisher_count"] = int(stats["standing_behind_finisher_count"]) + 1
				else:
					stats["standing_behind_regular_count"] = int(stats["standing_behind_regular_count"]) + 1

			MoveResource.MoveType.RUNNING:
				if is_finisher:
					stats["running_finisher_count"] = int(stats["running_finisher_count"]) + 1
				else:
					stats["running_regular_count"] = int(stats["running_regular_count"]) + 1

			MoveResource.MoveType.ROPE_REBOUND:
				if is_finisher:
					stats["rebound_finisher_count"] = int(stats["rebound_finisher_count"]) + 1
				else:
					stats["rebound_regular_count"] = int(stats["rebound_regular_count"]) + 1

			MoveResource.MoveType.GROUNDED:
				if is_finisher:
					stats["grounded_finisher_count"] = int(stats["grounded_finisher_count"]) + 1
				else:
					stats["grounded_regular_count"] = int(stats["grounded_regular_count"]) + 1

			MoveResource.MoveType.SPRINGBOARD:
				stats["springboard_total_count"] = int(stats["springboard_total_count"]) + 1
				if is_finisher:
					stats["springboard_finisher_count"] = int(stats["springboard_finisher_count"]) + 1
				else:
					stats["springboard_regular_count"] = int(stats["springboard_regular_count"]) + 1
					stats["aerial_regular_count"] = int(stats["aerial_regular_count"]) + 1

			MoveResource.MoveType.CORNER:
				if is_finisher:
					stats["corner_finisher_count"] = int(stats["corner_finisher_count"]) + 1
				else:
					stats["corner_regular_count"] = int(stats["corner_regular_count"]) + 1

			MoveResource.MoveType.DIVING_STANDING:
				stats["diving_total_count"] = int(stats["diving_total_count"]) + 1
				if is_finisher:
					stats["diving_finisher_count"] = int(stats["diving_finisher_count"]) + 1
					stats["diving_standing_finisher_count"] = int(stats["diving_standing_finisher_count"]) + 1
				else:
					stats["diving_regular_count"] = int(stats["diving_regular_count"]) + 1
					stats["diving_standing_regular_count"] = int(stats["diving_standing_regular_count"]) + 1
					stats["aerial_regular_count"] = int(stats["aerial_regular_count"]) + 1

			MoveResource.MoveType.DIVING_GROUNDED:
				stats["diving_total_count"] = int(stats["diving_total_count"]) + 1
				if is_finisher:
					stats["diving_finisher_count"] = int(stats["diving_finisher_count"]) + 1
					stats["diving_grounded_finisher_count"] = int(stats["diving_grounded_finisher_count"]) + 1
				else:
					stats["diving_regular_count"] = int(stats["diving_regular_count"]) + 1
					stats["diving_grounded_regular_count"] = int(stats["diving_grounded_regular_count"]) + 1
					stats["aerial_regular_count"] = int(stats["aerial_regular_count"]) + 1

			_:
				pass

		var normalized_name: String = _normalize_name(move.move_name)
		if not name_map.has(normalized_name):
			name_map[normalized_name] = []
		name_map[normalized_name].append(move.move_name)

		var resource_key: String = str(move.get_instance_id())
		if not resource_map.has(resource_key):
			resource_map[resource_key] = []
		resource_map[resource_key].append(move.move_name)

	var duplicate_name_lines: Array[String] = []
	for key in name_map.keys():
		var names: Array = name_map[key]
		if names.size() > 1:
			duplicate_name_lines.append("%s appears %s times" % [str(names[0]), str(names.size())])

	var duplicate_resource_lines: Array[String] = []
	for key in resource_map.keys():
		var names: Array = resource_map[key]
		if names.size() > 1:
			duplicate_resource_lines.append("%s appears %s times as same resource" % [str(names[0]), str(names.size())])

	stats["duplicate_name_lines"] = duplicate_name_lines
	stats["duplicate_resource_lines"] = duplicate_resource_lines
	stats["duplicate_name_count"] = duplicate_name_lines.size()
	stats["duplicate_resource_count"] = duplicate_resource_lines.size()

	return stats


func _validate_hard_rules(
	wrestler: WrestlerResource,
	display_name: String,
	stats: Dictionary,
	issues: Array[String]
) -> void:
	var total_count: int = int(stats["total_count"])
	var finisher_count: int = int(stats["finisher_count"])

	if total_count == 0:
		issues.append("%s has an empty moveset." % display_name)

	if total_count < MIN_EXPECTED_MOVES:
		issues.append("%s has only %s moves." % [display_name, str(total_count)])

	if total_count > MAX_EXPECTED_MOVES:
		issues.append("%s has %s moves." % [display_name, str(total_count)])

	if finisher_count != EXPECTED_FINISHERS:
		issues.append("%s has %s finishers, expected %s." % [
			display_name,
			str(finisher_count),
			str(EXPECTED_FINISHERS)
		])

	if int(stats["null_move_count"]) > 0:
		issues.append("%s has %s null move references." % [
			display_name,
			str(stats["null_move_count"])
		])

	if int(stats["duplicate_name_count"]) > 0:
		issues.append("%s has duplicate move names." % display_name)

	if int(stats["duplicate_resource_count"]) > 0:
		issues.append("%s has duplicate move resources." % display_name)

	var has_high_flyer: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER)
	var has_technician: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.TECHNICIAN)
	var has_striker: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.STRIKER)

	if has_high_flyer:
		if int(stats["springboard_regular_count"]) < MIN_HIGH_FLYER_REGULAR_SPRINGBOARD:
			issues.append("%s has High Flyer class but low regular springboard count: %s." % [
				display_name,
				str(stats["springboard_regular_count"])
			])

		if int(stats["diving_standing_regular_count"]) < MIN_HIGH_FLYER_REGULAR_DIVING_STANDING:
			issues.append("%s has High Flyer class but low regular diving standing count: %s." % [
				display_name,
				str(stats["diving_standing_regular_count"])
			])

		if int(stats["diving_grounded_regular_count"]) < MIN_HIGH_FLYER_REGULAR_DIVING_GROUNDED:
			issues.append("%s has High Flyer class but low regular diving grounded count: %s." % [
				display_name,
				str(stats["diving_grounded_regular_count"])
			])

		if int(stats["aerial_regular_count"]) < MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL:
			issues.append("%s has High Flyer class but low regular aerial count: %s." % [
				display_name,
				str(stats["aerial_regular_count"])
			])
	else:
		if int(stats["springboard_regular_count"]) > MAX_SPRINGBOARD_NON_FLYER:
			issues.append("%s is not a High Flyer but has %s regular springboards." % [
				display_name,
				str(stats["springboard_regular_count"])
			])

		if int(stats["diving_regular_count"]) > MAX_DIVING_NON_FLYER:
			issues.append("%s is not a High Flyer but has %s regular diving moves." % [
				display_name,
				str(stats["diving_regular_count"])
			])

	if has_technician:
		if int(stats["submission_regular_count"]) > MAX_SUBMISSIONS_TECHNICIAN:
			issues.append("%s has Technician class but has %s regular submissions, above cap %s." % [
				display_name,
				str(stats["submission_regular_count"]),
				str(MAX_SUBMISSIONS_TECHNICIAN)
			])
	else:
		if int(stats["submission_regular_count"]) > MAX_SUBMISSIONS_NON_TECHNICIAN:
			issues.append("%s is not a Technician but has %s regular submissions." % [
				display_name,
				str(stats["submission_regular_count"])
			])

	if has_striker:
		if int(stats["strike_regular_count"]) > MAX_STRIKES_STRIKER:
			issues.append("%s has Striker class but has %s regular strikes, above cap %s." % [
				display_name,
				str(stats["strike_regular_count"]),
				str(MAX_STRIKES_STRIKER)
			])
	else:
		if int(stats["strike_regular_count"]) > MAX_STRIKES_NON_STRIKER:
			issues.append("%s is not a Striker but has %s regular strikes." % [
				display_name,
				str(stats["strike_regular_count"])
			])

	if int(stats["standing_front_regular_count"]) < MIN_STANDING_FRONT:
		issues.append("%s has low regular standing front count: %s." % [
			display_name,
			str(stats["standing_front_regular_count"])
		])

	var running_rebound_count: int = int(stats["running_regular_count"]) + int(stats["rebound_regular_count"])
	if running_rebound_count < MIN_RUNNING_OR_REBOUND:
		issues.append("%s has low regular running/rebound count: %s." % [
			display_name,
			str(running_rebound_count)
		])

	if int(stats["grounded_regular_count"]) < MIN_GROUNDED:
		issues.append("%s has low regular grounded count: %s." % [
			display_name,
			str(stats["grounded_regular_count"])
		])


func _validate_soft_flavour_rules(
	wrestler: WrestlerResource,
	display_name: String,
	stats: Dictionary,
	warnings: Array[String]
) -> void:
	var primary_class: WrestlerResource.WrestlerClass = _get_primary_class(wrestler)

	var has_high_flyer: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER)
	var has_technician: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.TECHNICIAN)
	var has_striker: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.STRIKER)
	var has_powerhouse: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.POWERHOUSE)
	var has_hardcore: bool = _has_class(wrestler, WrestlerResource.WrestlerClass.HARDCORE)

	if has_high_flyer:
		var aerial_minimum: int = MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL
		if primary_class != WrestlerResource.WrestlerClass.HIGH_FLYER:
			aerial_minimum = 5

		if int(stats["aerial_regular_count"]) < aerial_minimum:
			warnings.append("%s has High Flyer class but only %s regular aerial moves." % [
				display_name,
				str(stats["aerial_regular_count"])
			])

	if has_technician:
		var submission_minimum: int = MIN_TECHNICIAN_REGULAR_SUBMISSIONS
		if primary_class != WrestlerResource.WrestlerClass.TECHNICIAN:
			submission_minimum = 2

		if int(stats["submission_regular_count"]) < submission_minimum:
			warnings.append("%s has Technician class but low regular submission count: %s." % [
				display_name,
				str(stats["submission_regular_count"])
			])

	if has_striker:
		var strike_minimum: int = MIN_STRIKER_REGULAR_STRIKES
		if primary_class != WrestlerResource.WrestlerClass.STRIKER:
			strike_minimum = 6

		if int(stats["strike_regular_count"]) < strike_minimum:
			warnings.append("%s has Striker class but low regular strike count: %s." % [
				display_name,
				str(stats["strike_regular_count"])
			])

		# Only enforce the non-strike striker-style minimum for primary Strikers.
		if primary_class == WrestlerResource.WrestlerClass.STRIKER:
			if int(stats["striker_non_strike_style_regular_count"]) < MIN_STRIKER_NON_STRIKE_STYLE_MOVES:
				warnings.append("%s has Striker class but low regular non-strike striker-style count: %s." % [
					display_name,
					str(stats["striker_non_strike_style_regular_count"])
				])

	if has_powerhouse:
		var standing_front_minimum: int = MIN_POWERHOUSE_REGULAR_STANDING_FRONT
		if primary_class != WrestlerResource.WrestlerClass.POWERHOUSE:
			standing_front_minimum = 6

		if int(stats["standing_front_regular_count"]) < standing_front_minimum:
			warnings.append("%s has Powerhouse class but low regular standing front count: %s." % [
				display_name,
				str(stats["standing_front_regular_count"])
			])

	if has_hardcore:
		var brawl_grounded_score: int = int(stats["strike_regular_count"]) + int(stats["grounded_regular_count"])

		var hardcore_minimum: int = MIN_HARDCORE_BRAWL_OR_GROUNDED
		if primary_class != WrestlerResource.WrestlerClass.HARDCORE:
			hardcore_minimum = 4

		if brawl_grounded_score < hardcore_minimum:
			warnings.append("%s has Hardcore class but low brawl/grounded flavour: %s." % [
				display_name,
				str(brawl_grounded_score)
			])


func _moveset_to_lines(move_set: Array[MoveResource]) -> Array[String]:
	var lines: Array[String] = []

	var indexed_moves: Array[Dictionary] = []
	for move: MoveResource in move_set:
		if move == null:
			indexed_moves.append({
				"name": "[NULL MOVE]",
				"sort_name": "[NULL MOVE]"
			})
			continue

		var bucket: String = "Regular"
		if move.is_finisher:
			bucket = "Finisher"

		indexed_moves.append({
			"name": "%s | %s | %s | Submission=%s | Strike=%s | Impact=%s | Classes=%s" % [
				move.move_name,
				_move_type_to_string(move.move_type),
				bucket,
				str(move.is_submission),
				str(move.is_strike),
				str(move.move_impact),
				_class_array_to_string(move.class_preferrence)
			],
			"sort_name": move.move_name
		})

	indexed_moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["sort_name"]).naturalnocasecmp_to(str(b["sort_name"])) < 0
	)

	for entry: Dictionary in indexed_moves:
		lines.append(str(entry["name"]))

	return lines


func _append_usage_table(lines: Array[String], usage_map: Dictionary, limit: int) -> void:
	var usage_entries: Array[Dictionary] = []

	for move_name in usage_map.keys():
		usage_entries.append({
			"name": str(move_name),
			"count": int(usage_map[move_name])
		})

	usage_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) == int(b["count"]):
			return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
		return int(a["count"]) > int(b["count"])
	)

	if usage_entries.is_empty():
		lines.append("[None]")
		return

	var top_limit: int = min(limit, usage_entries.size())
	for i in range(top_limit):
		lines.append("%-45s %s" % [
			str(usage_entries[i]["name"]) + ":",
			str(usage_entries[i]["count"])
		])


func _append_count_table(lines: Array[String], count_map: Dictionary) -> void:
	var keys: Array[String] = []
	for k in count_map.keys():
		keys.append(str(k))
	keys.sort()

	if keys.is_empty():
		lines.append("[None]")
		return

	for key: String in keys:
		lines.append("%-20s %s" % [key + ":", str(count_map[key])])


func _collect_wrestler_paths(dir_path: String, results: Array[String]) -> void:
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
			_collect_wrestler_paths(full_path, results)
		elif item_name.get_extension().to_lower() == "tres":
			var resource: Resource = load(full_path)
			if resource is WrestlerResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()


func _get_wrestler_display_name(wrestler: WrestlerResource) -> String:
	if not wrestler.gimmick_name.strip_edges().is_empty():
		return wrestler.gimmick_name
	if not wrestler.wrestler_name.strip_edges().is_empty():
		return wrestler.wrestler_name
	return "[Unnamed Wrestler]"


func _get_primary_class(wrestler: WrestlerResource) -> WrestlerResource.WrestlerClass:
	if wrestler.wrestler_class.is_empty():
		return WrestlerResource.WrestlerClass.HIGH_FLYER
	return wrestler.wrestler_class[0]


func _has_class(wrestler: WrestlerResource, wrestler_class: WrestlerResource.WrestlerClass) -> bool:
	return wrestler.wrestler_class.has(wrestler_class)


func _class_to_string(c: WrestlerResource.WrestlerClass) -> String:
	match c:
		WrestlerResource.WrestlerClass.HIGH_FLYER:
			return "High Flyer"
		WrestlerResource.WrestlerClass.POWERHOUSE:
			return "Powerhouse"
		WrestlerResource.WrestlerClass.TECHNICIAN:
			return "Technician"
		WrestlerResource.WrestlerClass.STRIKER:
			return "Striker"
		WrestlerResource.WrestlerClass.HARDCORE:
			return "Hardcore"
		_:
			return "Unknown"


func _class_array_to_string(classes: Array[WrestlerResource.WrestlerClass]) -> String:
	var names: Array[String] = []

	for c: WrestlerResource.WrestlerClass in classes:
		names.append(_class_to_string(c))

	if names.is_empty():
		return "[None]"

	return ", ".join(names)


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


func _normalize_name(move_name: String) -> String:
	return move_name.strip_edges().to_lower()
