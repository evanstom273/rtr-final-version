@tool
extends EditorScript
class_name MovesetGenerator

## Safe, deterministic editor-only moveset generator.
##
## Running this script with its default constants performs an audit/dry run only.
## Wrestler resources can only be saved through apply_preview(), with dry_run
## disabled, allow_save enabled, and the exact confirmation token supplied.

enum Operation {
	AUDIT_EXISTING,
	GENERATE_ALL,
	GENERATE_MISSING,
	GENERATE_ONE,
	GENERATE_SELECTED,
}

const MOVE_ROOT := "res://Moves"
const WRESTLER_ROOT := "res://Wrestlers"
const DEFAULT_REPORT_PATH := "res://moveset_generation_report.txt"
const SAVE_CONFIRMATION_TOKEN := "APPLY_MOVESETS"

const REGULAR_MOVE_TARGET := 40
const DEFAULT_SIGNATURE_TARGET := 2
const MINIMUM_SIGNATURES := 1
const FINISHER_TARGET := 3
const MAX_SETUP_STEPS := 2

# Editable run configuration used when this script is launched from the Godot
# script editor. GENERATE_ALL builds the preview and, with the three explicit
# save settings below, applies it to the complete discovered roster.
const RUN_OPERATION := Operation.GENERATE_ALL
const RUN_DRY_RUN := false
const RUN_ALLOW_SAVE := true
const RUN_CONFIRMATION_TOKEN := "APPLY_MOVESETS"
const RUN_BASE_SEED := 20260719
const RUN_RANDOM_SEED := false
const RUN_SIGNATURE_TARGET := DEFAULT_SIGNATURE_TARGET
const RUN_PRESERVE_REGULAR := false
const RUN_PRESERVE_SIGNATURES := false
const RUN_PRESERVE_FINISHERS := false
const RUN_WRESTLER_PATH := ""
const RUN_WRESTLER_PATHS: Array[String] = []
const RUN_WRITE_REPORT := true

const CATEGORY_STRIKE := &"strike"
const CATEGORY_GRAPPLE := &"grapple"
const CATEGORY_RUNNING := &"running"
const CATEGORY_SUBMISSION := &"submission"
const CATEGORY_AERIAL := &"aerial"
const CATEGORY_PIN := &"pin"
const CATEGORY_OTHER := &"other"

const ROLE_STANDING_FRONT := &"standing_front"
const ROLE_STANDING_BACK := &"standing_back"
const ROLE_GROUNDED_FACE_UP := &"grounded_face_up"
const ROLE_GROUNDED_FACE_DOWN := &"grounded_face_down"
const ROLE_RUNNING_REBOUND := &"running_rebound"
const ROLE_CORNER := &"corner"
const ROLE_PINNING := &"pinning"

const COVERAGE_TARGETS := {
	ROLE_STANDING_FRONT: 10,
	ROLE_STANDING_BACK: 3,
	ROLE_GROUNDED_FACE_UP: 3,
	ROLE_GROUNDED_FACE_DOWN: 2,
	ROLE_RUNNING_REBOUND: 3,
	ROLE_CORNER: 2,
	ROLE_PINNING: 2,
}

const CATEGORY_MINIMUMS := {
	CATEGORY_STRIKE: 8,
	CATEGORY_GRAPPLE: 10,
	CATEGORY_RUNNING: 3,
	CATEGORY_SUBMISSION: 0,
	CATEGORY_AERIAL: 0,
	CATEGORY_PIN: 2,
}

const CATEGORY_MAXIMUMS := {
	CATEGORY_STRIKE: 17,
	CATEGORY_GRAPPLE: 20,
	CATEGORY_RUNNING: 7,
	CATEGORY_SUBMISSION: 6,
	CATEGORY_AERIAL: 12,
	CATEGORY_PIN: 5,
	CATEGORY_OTHER: 4,
}

const NEUTRAL_PROFILE := {
	CATEGORY_STRIKE: 12.0,
	CATEGORY_GRAPPLE: 14.0,
	CATEGORY_RUNNING: 4.0,
	CATEGORY_SUBMISSION: 3.0,
	CATEGORY_AERIAL: 3.0,
	CATEGORY_PIN: 4.0,
}

const CLASS_PROFILES := {
	WrestlerResource.WrestlerClass.HIGH_FLYER: {
		CATEGORY_STRIKE: 9.0,
		CATEGORY_GRAPPLE: 10.0,
		CATEGORY_RUNNING: 5.0,
		CATEGORY_SUBMISSION: 1.0,
		CATEGORY_AERIAL: 11.0,
		CATEGORY_PIN: 4.0,
	},
	WrestlerResource.WrestlerClass.POWERHOUSE: {
		CATEGORY_STRIKE: 9.0,
		CATEGORY_GRAPPLE: 19.0,
		CATEGORY_RUNNING: 5.0,
		CATEGORY_SUBMISSION: 2.0,
		CATEGORY_AERIAL: 1.0,
		CATEGORY_PIN: 4.0,
	},
	WrestlerResource.WrestlerClass.TECHNICIAN: {
		CATEGORY_STRIKE: 9.0,
		CATEGORY_GRAPPLE: 15.0,
		CATEGORY_RUNNING: 4.0,
		CATEGORY_SUBMISSION: 6.0,
		CATEGORY_AERIAL: 2.0,
		CATEGORY_PIN: 4.0,
	},
	WrestlerResource.WrestlerClass.STRIKER: {
		CATEGORY_STRIKE: 16.0,
		CATEGORY_GRAPPLE: 12.0,
		CATEGORY_RUNNING: 5.0,
		CATEGORY_SUBMISSION: 2.0,
		CATEGORY_AERIAL: 1.0,
		CATEGORY_PIN: 4.0,
	},
	WrestlerResource.WrestlerClass.HARDCORE: {
		CATEGORY_STRIKE: 14.0,
		CATEGORY_GRAPPLE: 15.0,
		CATEGORY_RUNNING: 5.0,
		CATEGORY_SUBMISSION: 2.0,
		CATEGORY_AERIAL: 1.0,
		CATEGORY_PIN: 3.0,
	},
}

const _CONTEXT_NAME_WORDS := [
	"aerial", "apron", "avalanche", "corner", "diving", "grounded",
	"rebound", "rope", "running", "springboard", "standing", "top",
]

var _reachability_cache: Dictionary = {}


func _run() -> void:
	var options := default_options()
	var started_at := Time.get_ticks_msec()
	print("MovesetGenerator: starting %s (dry_run=%s)." % [
		_operation_name(int(options.operation)),
		str(options.dry_run),
	])
	var result := (
		audit_existing(options)
		if int(options.operation) == Operation.AUDIT_EXISTING
		else preview_generation(options)
	)
	if (
		str(result.get("kind", "")) == "preview"
		and not bool(options.dry_run)
		and bool(options.allow_save)
	):
		result = apply_preview(result, RUN_CONFIRMATION_TOKEN)
	_print_result(result)
	print("MovesetGenerator: finished in %.2f seconds." % [
		float(Time.get_ticks_msec() - started_at) / 1000.0,
	])
	if RUN_WRITE_REPORT:
		write_report(result, DEFAULT_REPORT_PATH)


func default_options() -> Dictionary:
	return {
		"operation": RUN_OPERATION,
		"dry_run": RUN_DRY_RUN,
		"allow_save": RUN_ALLOW_SAVE,
		"base_seed": RUN_BASE_SEED,
		"random_seed": RUN_RANDOM_SEED,
		"signature_target": RUN_SIGNATURE_TARGET,
		"preserve_regular": RUN_PRESERVE_REGULAR,
		"preserve_signatures": RUN_PRESERVE_SIGNATURES,
		"preserve_finishers": RUN_PRESERVE_FINISHERS,
		"wrestler_path": RUN_WRESTLER_PATH,
		"wrestler_paths": PackedStringArray(RUN_WRESTLER_PATHS),
	}


func audit_existing(options: Dictionary = {}) -> Dictionary:
	var run_options := _normalized_options(options)
	var wrestler_paths: Array[String] = []
	_collect_resource_paths(WRESTLER_ROOT, wrestler_paths)
	wrestler_paths.sort()
	var selected_paths := _select_wrestler_paths(wrestler_paths, run_options, true)
	var entries: Array[Dictionary] = []
	var errors: Array[String] = []
	for wrestler_index in selected_paths.size():
		var path := selected_paths[wrestler_index]
		if wrestler_index % 25 == 0:
			print("MovesetGenerator audit: %d/%d wrestlers..." % [wrestler_index, selected_paths.size()])
		var snapshot := _load_wrestler_snapshot(path)
		var wrestler: WrestlerResource = snapshot.wrestler
		if wrestler == null:
			errors.append_array(snapshot.hard_errors)
			continue
		var audit := _audit_assignment(
			wrestler,
			wrestler.move_set,
			wrestler.signature_moves,
			wrestler.finisher_moves,
		)
		audit["wrestler_path"] = path
		audit["wrestler_name"] = _wrestler_name(wrestler)
		audit.hard_errors.append_array(snapshot.hard_errors)
		audit.warnings.append_array(snapshot.warnings)
		if not audit.hard_errors.is_empty():
			errors.append("%s has audit failures; see its report entry." % _wrestler_name(wrestler))
		entries.append(audit)
	var result := {
		"kind": "audit",
		"success": errors.is_empty(),
		"applied": false,
		"seed": int(run_options.base_seed),
		"options": run_options,
		"entries": entries,
		"hard_errors": errors,
		"warnings": [],
	}
	result["report"] = _render_report(result)
	return result


func preview_generation(options: Dictionary = {}) -> Dictionary:
	var run_options := _normalized_options(options)
	var seed_value := int(run_options.base_seed)
	if bool(run_options.random_seed):
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.randomize()
		seed_value = seed_rng.randi()
	run_options["base_seed"] = seed_value
	_reachability_cache.clear()

	var catalogue := _load_catalogue()
	print("MovesetGenerator preview: catalogue indexed; preparing wrestler snapshots.")
	var errors: Array[String] = []
	errors.append_array(catalogue.hard_errors)
	var warnings: Array[String] = []
	warnings.append_array(catalogue.warnings)

	var wrestler_paths: Array[String] = []
	_collect_resource_paths(WRESTLER_ROOT, wrestler_paths)
	wrestler_paths.sort()
	var selected_paths := _select_wrestler_paths(wrestler_paths, run_options, false)
	if selected_paths.is_empty():
		errors.append("No wrestler resources matched the requested operation.")

	var entries: Array[Dictionary] = []
	for wrestler_index in selected_paths.size():
		var wrestler_path := selected_paths[wrestler_index]
		if wrestler_index % 10 == 0:
			print("MovesetGenerator preview: %d/%d wrestlers..." % [wrestler_index, selected_paths.size()])
		var snapshot := _load_wrestler_snapshot(wrestler_path)
		var wrestler: WrestlerResource = snapshot.wrestler
		if wrestler == null:
			errors.append_array(snapshot.hard_errors)
			continue
		warnings.append_array(snapshot.warnings)
		if int(run_options.operation) == Operation.GENERATE_MISSING and not _moveset_is_missing(wrestler, run_options):
			entries.append({
				"wrestler_path": wrestler_path,
				"wrestler_name": _wrestler_name(wrestler),
				"skipped": true,
				"skip_reason": "All moveset sections already satisfy their configured counts.",
				"hard_errors": [],
				"warnings": [],
			})
			continue
		var wrestler_options := run_options.duplicate(true)
		wrestler_options["wrestler_path"] = wrestler_path
		wrestler_options["derived_seed"] = _seed_for_wrestler(seed_value, wrestler_path, wrestler)
		var generated := generate_wrestler(wrestler, catalogue, wrestler_options)
		generated["wrestler_path"] = wrestler_path
		generated["wrestler_name"] = _wrestler_name(wrestler)
		generated.warnings.append_array(snapshot.warnings)
		entries.append(generated)
		errors.append_array(generated.hard_errors)
		warnings.append_array(generated.warnings)

	var result := {
		"kind": "preview",
		"success": errors.is_empty(),
		"applied": false,
		"seed": seed_value,
		"options": run_options,
		"catalogue_counts": catalogue.counts,
		"entries": entries,
		"hard_errors": errors,
		"warnings": warnings,
	}
	result["report"] = _render_report(result)
	return result


func apply_preview(preview: Dictionary, confirmation_token: String) -> Dictionary:
	var result := preview.duplicate(true)
	result["applied"] = false
	var errors: Array[String] = []
	if str(preview.get("kind", "")) != "preview":
		errors.append("Only a generation preview can be applied.")
	if not bool(preview.get("success", false)):
		errors.append("The preview contains hard errors and cannot be applied.")
	var options: Dictionary = preview.get("options", {})
	if bool(options.get("dry_run", true)):
		errors.append("dry_run must be disabled before applying a preview.")
	if not bool(options.get("allow_save", false)):
		errors.append("allow_save must be enabled before applying a preview.")
	if confirmation_token != SAVE_CONFIRMATION_TOKEN:
		errors.append("The moveset save confirmation token is missing or incorrect.")
	if not errors.is_empty():
		result["hard_errors"] = errors
		result["report"] = _render_report(result)
		return result

	var run_id := _safe_run_id(int(preview.get("seed", 0)))
	var staging_root := "user://moveset_generator/staging/%s" % run_id
	var backup_root := "user://moveset_generator/backups/%s" % run_id
	var staged_entries: Array[Dictionary] = []
	for entry: Dictionary in preview.get("entries", []):
		if bool(entry.get("skipped", false)):
			continue
		var staged := _stage_entry(entry, staging_root)
		if not bool(staged.get("success", false)):
			errors.append(str(staged.get("error", "Unknown staging failure.")))
			break
		staged_entries.append(staged)
	if not errors.is_empty():
		result["hard_errors"] = errors
		result["report"] = _render_report(result)
		return result

	var written_paths: Array[String] = []
	var backup_paths: Dictionary = {}
	for staged in staged_entries:
		var original_path := str(staged.original_path)
		var backup_path := "%s/%s" % [backup_root, original_path.trim_prefix("res://")]
		var backup_error := _backup_resource(original_path, backup_path)
		if backup_error != OK:
			errors.append("Could not back up %s (error %d)." % [original_path, backup_error])
			break
		backup_paths[original_path] = backup_path
		var staged_resource := ResourceLoader.load(str(staged.staging_path), "", ResourceLoader.CACHE_MODE_IGNORE)
		if not (staged_resource is WrestlerResource):
			errors.append("Staged wrestler failed to reload: %s" % staged.staging_path)
			break
		var save_error := ResourceSaver.save(staged_resource, original_path)
		if save_error != OK:
			errors.append("Could not save %s (error %d)." % [original_path, save_error])
			break
		written_paths.append(original_path)
	if not errors.is_empty():
		_rollback_resources(written_paths, backup_paths)
		result["hard_errors"] = errors
		result["report"] = _render_report(result)
		return result

	result["success"] = true
	result["applied"] = true
	result["backup_root"] = backup_root
	result["staging_root"] = staging_root
	result["report"] = _render_report(result)
	return result


func generate_wrestler(
	wrestler: WrestlerResource,
	catalogue: Dictionary,
	options: Dictionary = {},
) -> Dictionary:
	var run_options := _normalized_options(options)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run_options.get("derived_seed", run_options.base_seed))
	var missing_mode := int(run_options.operation) == Operation.GENERATE_MISSING

	var preserve_regular := bool(run_options.preserve_regular)
	var preserve_signatures := bool(run_options.preserve_signatures)
	var preserve_finishers := bool(run_options.preserve_finishers)
	if missing_mode:
		preserve_regular = preserve_regular or _regular_section_valid(wrestler.move_set)
		preserve_signatures = preserve_signatures or _signature_section_valid(wrestler.signature_moves, int(run_options.signature_target))
		preserve_finishers = preserve_finishers or _finisher_section_valid(wrestler.finisher_moves)

	var finishers: Array[MoveResource] = []
	if preserve_finishers:
		finishers = _copy_section(wrestler.finisher_moves, &"finisher", errors)
	else:
		finishers = _select_special_moves(
			wrestler,
			catalogue.finishers,
			FINISHER_TARGET,
			{},
			rng,
			&"finisher",
			warnings,
		)

	var protected_paths := _resource_path_set(finishers)
	if preserve_regular:
		for move in wrestler.move_set:
			if move != null:
				protected_paths[_resource_key(move)] = true

	var signatures: Array[MoveResource] = []
	if preserve_signatures:
		signatures = _copy_section(wrestler.signature_moves, &"signature", errors)
	else:
		signatures = _select_special_moves(
			wrestler,
			catalogue.signatures,
			int(run_options.signature_target),
			protected_paths,
			rng,
			&"signature",
			warnings,
		)
	protected_paths.merge(_resource_path_set(signatures), true)

	var regular: Array[MoveResource] = []
	if preserve_regular:
		regular = _copy_section(wrestler.move_set, &"regular", errors)
	else:
		regular = _select_regular_moves(
			wrestler,
			catalogue.regular,
			protected_paths,
			rng,
			warnings,
		)

	var audit := _audit_assignment(wrestler, regular, signatures, finishers)
	errors.append_array(audit.hard_errors)
	warnings.append_array(audit.warnings)
	return {
		"skipped": false,
		"derived_seed": int(run_options.get("derived_seed", run_options.base_seed)),
		"preserved_regular": preserve_regular,
		"preserved_signatures": preserve_signatures,
		"preserved_finishers": preserve_finishers,
		"regular_moves": regular,
		"signature_moves": signatures,
		"finisher_moves": finishers,
		"before": {
			"regular": wrestler.move_set.size(),
			"signatures": wrestler.signature_moves.size(),
			"finishers": wrestler.finisher_moves.size(),
		},
		"after": {
			"regular": regular.size(),
			"signatures": signatures.size(),
			"finishers": finishers.size(),
		},
		"categories": audit.categories,
		"coverage": audit.coverage,
		"hard_errors": _unique_strings(errors),
		"warnings": _unique_strings(warnings),
	}


func write_report(result: Dictionary, path: String = DEFAULT_REPORT_PATH) -> Error:
	var report := str(result.get("report", _render_report(result)))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("MovesetGenerator could not write report: %s" % path)
		return FileAccess.get_open_error()
	file.store_string(report)
	file.close()
	print("MovesetGenerator report: %s" % ProjectSettings.globalize_path(path))
	return OK


func _load_catalogue() -> Dictionary:
	var paths: Array[String] = []
	_collect_resource_paths(MOVE_ROOT, paths)
	paths.sort()
	var loaded_moves: Array[Dictionary] = []
	var regular: Array[Dictionary] = []
	var signatures: Array[Dictionary] = []
	var finishers: Array[Dictionary] = []
	var all_candidates: Array[Dictionary] = []
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var seen_names: Dictionary = {}
	var seen_paths: Dictionary = {}
	for path in paths:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if not (resource is MoveResource):
			errors.append("Not a MoveResource: %s" % path)
			continue
		var move := resource as MoveResource
		var validation := _validate_move(move, path)
		errors.append_array(validation.hard_errors)
		warnings.append_array(validation.warnings)
		var name_key := move.move_name.strip_edges().to_lower()
		if seen_paths.has(path):
			errors.append("Duplicate move path: %s" % path)
			continue
		if seen_names.has(name_key):
			errors.append("Duplicate move name '%s': %s and %s" % [move.move_name, seen_names[name_key], path])
			continue
		seen_paths[path] = true
		seen_names[name_key] = path
		loaded_moves.append({"move": move, "path": path})
	print("MovesetGenerator: loaded %d catalogue moves; calculating shared setup reachability..." % loaded_moves.size())
	_cache_setup_depths(loaded_moves)
	for loaded: Dictionary in loaded_moves:
		var move: MoveResource = loaded.move
		var candidate := _candidate_from_move(move, str(loaded.path))
		all_candidates.append(candidate)
		if move.is_finisher:
			finishers.append(candidate)
		else:
			regular.append(candidate)
			if move.move_impact >= 7:
				signatures.append(candidate)
	_cache_similarity_links(all_candidates)
	return {
		"regular": regular,
		"signatures": signatures,
		"finishers": finishers,
		"hard_errors": _unique_strings(errors),
		"warnings": _unique_strings(warnings),
		"counts": {
			"all": paths.size(),
			"regular": regular.size(),
			"signature_candidates": signatures.size(),
			"finishers": finishers.size(),
		},
	}


func _candidate_from_move(move: MoveResource, path: String) -> Dictionary:
	return {
		"move": move,
		"path": path,
		"category": _move_category(move),
		"family": _move_family(move.move_name),
		"name_tokens": _meaningful_name_tokens(move.move_name),
		"state_key": _required_state_key(move),
		"target_group": _target_group(move),
		"setup_depth": _setup_depth(move),
	}


func _select_regular_moves(
	wrestler: WrestlerResource,
	candidates: Array,
	excluded_paths: Dictionary,
	rng: RandomNumberGenerator,
	warnings: Array[String],
) -> Array[MoveResource]:
	var selected: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if excluded_paths.has(str(candidate.path)):
			continue
		if _candidate_allowed(wrestler, candidate):
			remaining.append(candidate)
	var profile := _profile_for_wrestler(wrestler)

	for role: StringName in COVERAGE_TARGETS:
		while _coverage_count(selected, role) < int(COVERAGE_TARGETS[role]) and selected.size() < REGULAR_MOVE_TARGET:
			var pool := _eligible_candidates(wrestler, remaining, selected, profile, role, &"")
			if pool.is_empty():
				warnings.append("%s lacks candidates for coverage role %s." % [_wrestler_name(wrestler), role])
				break
			var picked := _pick_weighted(wrestler, pool, selected, profile, rng, role, &"regular")
			_add_candidate(picked, selected, remaining)

	var identity_minimums := _identity_minimums(wrestler, profile)
	for category: StringName in identity_minimums:
		while _category_count(selected, category) < int(identity_minimums[category]) and selected.size() < REGULAR_MOVE_TARGET:
			var pool := _eligible_candidates(wrestler, remaining, selected, profile, &"", category)
			if pool.is_empty():
				warnings.append("%s lacks candidates for category minimum %s." % [_wrestler_name(wrestler), category])
				break
			var picked := _pick_weighted(wrestler, pool, selected, profile, rng, &"", &"regular")
			_add_candidate(picked, selected, remaining)

	while selected.size() < REGULAR_MOVE_TARGET:
		var pool := _eligible_candidates(wrestler, remaining, selected, profile, &"", &"")
		if pool.is_empty():
			warnings.append("%s ran out of valid unique regular candidates at %d/%d." % [
				_wrestler_name(wrestler), selected.size(), REGULAR_MOVE_TARGET,
			])
			break
		var picked := _pick_weighted(wrestler, pool, selected, profile, rng, &"", &"regular")
		_add_candidate(picked, selected, remaining)

	var moves: Array[MoveResource] = []
	for candidate in selected:
		moves.append(candidate.move)
	return moves


func _select_special_moves(
	wrestler: WrestlerResource,
	candidates: Array,
	target_count: int,
	excluded_paths: Dictionary,
	rng: RandomNumberGenerator,
	section: StringName,
	warnings: Array[String],
) -> Array[MoveResource]:
	var selected: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if excluded_paths.has(str(candidate.path)):
			continue
		if _candidate_allowed(wrestler, candidate):
			remaining.append(candidate)
	var profile := _profile_for_wrestler(wrestler)
	while selected.size() < target_count and not remaining.is_empty():
		var picked := _pick_weighted(wrestler, remaining, selected, profile, rng, &"", section)
		_add_candidate(picked, selected, remaining)
	if selected.size() < target_count:
		warnings.append("%s has only %d/%d suitable %s candidates." % [
			_wrestler_name(wrestler), selected.size(), target_count, section,
		])
	var moves: Array[MoveResource] = []
	for candidate in selected:
		moves.append(candidate.move)
	return moves


func _eligible_candidates(
	wrestler: WrestlerResource,
	remaining: Array[Dictionary],
	selected: Array[Dictionary],
	profile: Dictionary,
	role: StringName,
	category: StringName,
) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var submission_cap := _submission_cap(wrestler)
	var category_counts := _selected_category_counts(selected)
	for candidate in remaining:
		var candidate_category := StringName(candidate.category)
		if role != &"" and not _candidate_covers_role(candidate, role):
			continue
		if category != &"" and candidate_category != category:
			continue
		var maximum := int(CATEGORY_MAXIMUMS.get(candidate_category, REGULAR_MOVE_TARGET))
		if candidate_category == CATEGORY_SUBMISSION:
			maximum = mini(maximum, submission_cap)
		if int(category_counts.get(candidate_category, 0)) >= maximum:
			continue
		pool.append(candidate)
	if pool.is_empty() and role == &"" and category == &"":
		# Soft category ceilings must not prevent reaching 40 if the catalogue or
		# capability filters leave an unusual wrestler with a narrow pool.
		for candidate in remaining:
			if StringName(candidate.category) == CATEGORY_SUBMISSION and int(category_counts.get(CATEGORY_SUBMISSION, 0)) >= submission_cap:
				continue
			pool.append(candidate)
	return pool


func _pick_weighted(
	wrestler: WrestlerResource,
	pool: Array[Dictionary],
	selected: Array[Dictionary],
	profile: Dictionary,
	rng: RandomNumberGenerator,
	coverage_role: StringName,
	section: StringName,
) -> Dictionary:
	var weighted: Array[Dictionary] = []
	var total := 0.0
	var selection_context := _selection_context(selected)
	for candidate in pool:
		var weight := _candidate_weight(wrestler, candidate, selection_context, profile, coverage_role, section)
		weight = maxf(1.0, weight)
		total += weight
		weighted.append({"candidate": candidate, "ceiling": total})
	var roll := rng.randf_range(0.0, total)
	for entry in weighted:
		if roll <= float(entry.ceiling):
			return entry.candidate
	return weighted.back().candidate


func _candidate_weight(
	wrestler: WrestlerResource,
	candidate: Dictionary,
	selection_context: Dictionary,
	profile: Dictionary,
	coverage_role: StringName,
	section: StringName,
) -> float:
	var move: MoveResource = candidate.move
	var category := StringName(candidate.category)
	var weight := 100.0
	for wrestler_class in wrestler.wrestler_class:
		if wrestler_class in move.class_preferrence:
			weight += 70.0
	weight += _class_type_bonus(wrestler, category)
	weight += (_relevant_attribute(wrestler, category) - 50.0) * 1.2
	if category == CATEGORY_GRAPPLE and move.move_impact >= 8:
		weight += (wrestler.strength - 50.0) * 0.6
	if category == CATEGORY_AERIAL:
		weight += (wrestler.speed - 50.0) * 0.5
	match int(candidate.setup_depth):
		0:
			weight += 25.0
		1:
			weight += 15.0
		2:
			weight += 5.0
	if coverage_role != &"" and _candidate_covers_role(candidate, coverage_role):
		weight += 100.0
	var target := float(profile.get(category, 0.0))
	var category_counts: Dictionary = selection_context.category_counts
	var deficit := target - float(category_counts.get(category, 0))
	if deficit > 0.0:
		weight += deficit * 8.0
	if section == &"signature":
		weight += float(move.move_impact) * 15.0
		weight += _special_variety_bonus(candidate, selection_context)
	elif section == &"finisher":
		weight += float(move.move_impact) * 20.0
		weight += _special_variety_bonus(candidate, selection_context)
	weight += _target_variety_bonus(candidate, selection_context, section)
	weight -= _similarity_penalty(candidate, selection_context)
	return weight


func _candidate_allowed(wrestler: WrestlerResource, candidate: Dictionary) -> bool:
	var move: MoveResource = candidate.move
	if int(candidate.setup_depth) < 0 or int(candidate.setup_depth) > MAX_SETUP_STEPS:
		return false
	var aerial_like := move.move_type in [MoveResource.MoveType.AERIAL, MoveResource.MoveType.SPRINGBOARD]
	aerial_like = aerial_like or move.required_attacker_position == WrestlerResource.Position.PERCHED
	if aerial_like and (wrestler.speed < 40.0 or wrestler.skill < 35.0):
		return false
	if move.is_submission or move.move_type == MoveResource.MoveType.SUBMISSION:
		if wrestler.skill < 35.0:
			return false
		if move.move_impact >= 8 and wrestler.skill < 55.0:
			return false
	if (
		move.move_type == MoveResource.MoveType.GRAPPLE
		and move.move_impact >= 9
		and wrestler.strength < 45.0
		and WrestlerResource.WrestlerClass.TECHNICIAN not in move.class_preferrence
	):
		return false
	return true


func _profile_for_wrestler(wrestler: WrestlerResource) -> Dictionary:
	if wrestler.wrestler_class.is_empty():
		return _normalize_profile(NEUTRAL_PROFILE)
	var aggregate: Dictionary = {}
	for category in NEUTRAL_PROFILE:
		aggregate[category] = 0.0
	var matched := 0
	for wrestler_class in wrestler.wrestler_class:
		if not CLASS_PROFILES.has(wrestler_class):
			continue
		matched += 1
		var class_profile: Dictionary = CLASS_PROFILES[wrestler_class]
		for category in aggregate:
			aggregate[category] = float(aggregate[category]) + float(class_profile.get(category, 0.0))
	if matched == 0:
		return _normalize_profile(NEUTRAL_PROFILE)
	for category in aggregate:
		aggregate[category] = float(aggregate[category]) / float(matched)
	return _normalize_profile(aggregate)


func _normalize_profile(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var fractions: Array[Dictionary] = []
	var assigned := 0
	var total := 0.0
	for category in profile:
		total += float(profile[category])
	if total <= 0.0:
		return NEUTRAL_PROFILE.duplicate(true)
	for category in profile:
		var scaled := float(profile[category]) * float(REGULAR_MOVE_TARGET) / total
		var whole := floori(scaled)
		result[category] = whole
		assigned += whole
		fractions.append({"category": category, "fraction": scaled - float(whole)})
	fractions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.fraction) > float(b.fraction)
	)
	var index := 0
	while assigned < REGULAR_MOVE_TARGET and not fractions.is_empty():
		var category = fractions[index % fractions.size()].category
		result[category] = int(result[category]) + 1
		assigned += 1
		index += 1
	return result


func _identity_minimums(wrestler: WrestlerResource, profile: Dictionary) -> Dictionary:
	var result := CATEGORY_MINIMUMS.duplicate(true)
	if _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
		result[CATEGORY_AERIAL] = mini(8, int(profile.get(CATEGORY_AERIAL, 8)))
	if _has_class(wrestler, WrestlerResource.WrestlerClass.TECHNICIAN):
		result[CATEGORY_SUBMISSION] = mini(4, int(profile.get(CATEGORY_SUBMISSION, 4)))
	if _has_class(wrestler, WrestlerResource.WrestlerClass.STRIKER):
		result[CATEGORY_STRIKE] = mini(10, int(profile.get(CATEGORY_STRIKE, 10)))
	return result


func _class_type_bonus(wrestler: WrestlerResource, category: StringName) -> float:
	var bonus := 0.0
	for wrestler_class in wrestler.wrestler_class:
		match wrestler_class:
			WrestlerResource.WrestlerClass.HIGH_FLYER:
				bonus += {
					CATEGORY_AERIAL: 85.0, CATEGORY_RUNNING: 30.0,
					CATEGORY_PIN: 10.0, CATEGORY_GRAPPLE: -10.0,
					CATEGORY_SUBMISSION: -15.0,
				}.get(category, 0.0)
			WrestlerResource.WrestlerClass.POWERHOUSE:
				bonus += {
					CATEGORY_GRAPPLE: 75.0, CATEGORY_RUNNING: 20.0,
					CATEGORY_STRIKE: 10.0, CATEGORY_AERIAL: -75.0,
					CATEGORY_SUBMISSION: -10.0,
				}.get(category, 0.0)
			WrestlerResource.WrestlerClass.TECHNICIAN:
				bonus += {
					CATEGORY_GRAPPLE: 45.0, CATEGORY_SUBMISSION: 85.0,
					CATEGORY_PIN: 60.0, CATEGORY_RUNNING: 10.0,
					CATEGORY_AERIAL: -20.0,
				}.get(category, 0.0)
			WrestlerResource.WrestlerClass.STRIKER:
				bonus += {
					CATEGORY_STRIKE: 90.0, CATEGORY_RUNNING: 25.0,
					CATEGORY_GRAPPLE: 10.0, CATEGORY_SUBMISSION: -30.0,
					CATEGORY_AERIAL: -10.0,
				}.get(category, 0.0)
			WrestlerResource.WrestlerClass.HARDCORE:
				bonus += {
					CATEGORY_STRIKE: 50.0, CATEGORY_GRAPPLE: 45.0,
					CATEGORY_RUNNING: 20.0, CATEGORY_PIN: 5.0,
					CATEGORY_SUBMISSION: -10.0,
				}.get(category, 0.0)
	return bonus / float(maxi(1, wrestler.wrestler_class.size()))


func _relevant_attribute(wrestler: WrestlerResource, category: StringName) -> float:
	match category:
		CATEGORY_STRIKE:
			return wrestler.striking
		CATEGORY_GRAPPLE:
			return wrestler.skill * 0.55 + wrestler.strength * 0.45
		CATEGORY_SUBMISSION, CATEGORY_PIN:
			return wrestler.skill
		CATEGORY_AERIAL:
			return wrestler.speed * 0.60 + wrestler.skill * 0.40
		CATEGORY_RUNNING:
			return wrestler.speed * 0.55 + wrestler.stamina * 0.25 + wrestler.strength * 0.20
	return 50.0


func _audit_assignment(
	wrestler: WrestlerResource,
	regular: Array[MoveResource],
	signatures: Array[MoveResource],
	finishers: Array[MoveResource],
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var all_paths: Dictionary = {}
	if regular.size() != REGULAR_MOVE_TARGET:
		errors.append("%s has %d regular moves; expected %d." % [_wrestler_name(wrestler), regular.size(), REGULAR_MOVE_TARGET])
	if signatures.size() < MINIMUM_SIGNATURES:
		errors.append("%s has no usable signature." % _wrestler_name(wrestler))
	if finishers.size() != FINISHER_TARGET:
		errors.append("%s has %d finishers; expected %d." % [_wrestler_name(wrestler), finishers.size(), FINISHER_TARGET])
	for move in regular:
		if move == null:
			errors.append("%s has a null regular move." % _wrestler_name(wrestler))
			continue
		if move.is_finisher:
			errors.append("Regular section contains finisher: %s" % move.move_name)
		_register_unique_move(move, all_paths, errors)
	for move in signatures:
		if move == null:
			errors.append("%s has a null signature." % _wrestler_name(wrestler))
			continue
		if move.is_finisher or move.move_impact < 7:
			errors.append("Invalid signature candidate: %s" % move.move_name)
		_register_unique_move(move, all_paths, errors)
	for move in finishers:
		if move == null:
			errors.append("%s has a null finisher." % _wrestler_name(wrestler))
			continue
		if not move.is_finisher:
			errors.append("Finisher section contains non-finisher: %s" % move.move_name)
		_register_unique_move(move, all_paths, errors)
	var categories := _category_counts_for_moves(regular)
	var coverage := _coverage_counts_for_moves(regular)
	var submission_cap := _submission_cap(wrestler)
	if int(categories.get(CATEGORY_SUBMISSION, 0)) > submission_cap:
		errors.append("%s exceeds the submission cap of %d." % [_wrestler_name(wrestler), submission_cap])
	for role in COVERAGE_TARGETS:
		if int(coverage.get(role, 0)) < int(COVERAGE_TARGETS[role]):
			warnings.append("%s coverage %s is %d/%d." % [
				_wrestler_name(wrestler), role, int(coverage.get(role, 0)), int(COVERAGE_TARGETS[role]),
			])
	return {
		"categories": categories,
		"coverage": coverage,
		"hard_errors": _unique_strings(errors),
		"warnings": _unique_strings(warnings),
		"regular_moves": regular,
		"signature_moves": signatures,
		"finisher_moves": finishers,
	}


func _validate_move(move: MoveResource, path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if move.move_name.strip_edges().is_empty():
		errors.append("Move has no name: %s" % path)
	if move.move_type not in MoveResource.MoveType.values() or move.move_type == MoveResource.MoveType.NONE:
		errors.append("Move has invalid type: %s" % path)
	if move.required_attacker_position not in WrestlerResource.Position.values():
		errors.append("Move has invalid attacker position: %s" % path)
	if move.required_target_position not in WrestlerResource.Position.values():
		errors.append("Move has invalid target position: %s" % path)
	if move.required_attacker_orientation not in WrestlerResource.Orientation.values():
		errors.append("Move has invalid attacker orientation: %s" % path)
	if move.required_target_orientation not in WrestlerResource.Orientation.values():
		errors.append("Move has invalid target orientation: %s" % path)
	if move.required_attacker_area_mode not in MoveResource.AreaRequirementMode.values():
		errors.append("Move has invalid attacker area mode: %s" % path)
	if move.required_target_area_mode not in MoveResource.AreaRequirementMode.values():
		errors.append("Move has invalid target area mode: %s" % path)
	if move.resulting_attacker_area_mode not in MoveResource.AreaResultMode.values():
		errors.append("Move has invalid attacker area result mode: %s" % path)
	if move.resulting_target_area_mode not in MoveResource.AreaResultMode.values():
		errors.append("Move has invalid target area result mode: %s" % path)
	if move.required_attacker_motion_state not in WrestlerResource.MotionState.values():
		errors.append("Move has invalid attacker motion: %s" % path)
	if move.required_target_motion_state not in WrestlerResource.MotionState.values():
		errors.append("Move has invalid target motion: %s" % path)
	if move.move_impact < 1 or move.move_impact > 10:
		errors.append("Move impact is outside 1-10: %s" % path)
	if move.is_finisher and move.move_impact < 4:
		warnings.append("Low-impact finisher: %s" % move.move_name)
	return {"hard_errors": errors, "warnings": warnings}


func _copy_section(source: Array[MoveResource], section: StringName, errors: Array[String]) -> Array[MoveResource]:
	var copied: Array[MoveResource] = []
	for move in source:
		if move == null:
			errors.append("Preserved %s section contains a null resource." % section)
			continue
		copied.append(move)
	return copied


func _regular_section_valid(moves: Array[MoveResource]) -> bool:
	if moves.size() != REGULAR_MOVE_TARGET:
		return false
	for move in moves:
		if move == null or move.is_finisher:
			return false
	return _resource_path_set(moves).size() == moves.size()


func _signature_section_valid(moves: Array[MoveResource], target: int) -> bool:
	if moves.size() < MINIMUM_SIGNATURES or moves.size() != target:
		return false
	for move in moves:
		if move == null or move.is_finisher or move.move_impact < 7:
			return false
	return _resource_path_set(moves).size() == moves.size()


func _finisher_section_valid(moves: Array[MoveResource]) -> bool:
	if moves.size() != FINISHER_TARGET:
		return false
	for move in moves:
		if move == null or not move.is_finisher:
			return false
	return _resource_path_set(moves).size() == moves.size()


func _moveset_is_missing(wrestler: WrestlerResource, options: Dictionary) -> bool:
	return (
		not _regular_section_valid(wrestler.move_set)
		or not _signature_section_valid(wrestler.signature_moves, int(options.signature_target))
		or not _finisher_section_valid(wrestler.finisher_moves)
	)


func _setup_depth(move: MoveResource) -> int:
	var key := _resource_key(move)
	return int(_reachability_cache.get(key, -1))


func _cache_setup_depths(loaded_moves: Array[Dictionary]) -> void:
	_reachability_cache.clear()
	var moves: Array[MoveResource] = []
	for loaded in loaded_moves:
		var move: MoveResource = loaded.move
		moves.append(move)
		_reachability_cache[_resource_key(move)] = -1
	var attacker := _neutral_snapshot()
	var target := _neutral_snapshot()
	var paths := MatchSetupStateRules.find_followup_paths(moves, attacker, target, MAX_SETUP_STEPS)
	var result_states: Dictionary = {}
	for path_data in paths:
		_record_reachable_path(path_data)
		_register_move_result_state(path_data, result_states)

	# A grounded, seated, kneeling, staggering, or other follow-up move is not
	# expected to be reachable from the opening bell through setup actions alone.
	# It becomes reachable after a preceding move authors that state. Evaluate
	# the same bounded setup planner from every clean result state produced by an
	# opening-reachable move so those legitimate follow-ups are not discarded.
	_record_reachability_from_result_states(moves, result_states)


func _record_reachable_path(path_data: Dictionary) -> void:
	var move: MoveResource = path_data.move
	var key := _resource_key(move)
	var depth := int(path_data.actions.size())
	var previous := int(_reachability_cache.get(key, -1))
	if previous < 0 or depth < previous:
		_reachability_cache[key] = depth


func _record_reachability_from_result_states(moves: Array[MoveResource], result_states: Dictionary) -> void:
	# Multi-source breadth-first planning is intentionally shared across every
	# move-result state. Calling find_followup_paths() once per state repeats the
	# same large search and can freeze the editor for minutes.
	var frontier: Array[Dictionary] = []
	var visited: Dictionary = {}
	for state_data: Dictionary in result_states.values():
		var attacker: Dictionary = state_data.attacker
		var target: Dictionary = state_data.target
		var key := _snapshot_pair_key(attacker, target)
		if visited.has(key):
			continue
		visited[key] = 0
		frontier.append({
			"attacker": attacker,
			"target": target,
			"actions": [],
		})
	for depth in range(MAX_SETUP_STEPS + 1):
		var next_frontier: Array[Dictionary] = []
		for node: Dictionary in frontier:
			var attacker: Dictionary = node.attacker
			var target: Dictionary = node.target
			for move: MoveResource in moves:
				if MatchSetupStateRules.move_matches_snapshots(move, attacker, target):
					var key := _resource_key(move)
					var previous := int(_reachability_cache.get(key, -1))
					if previous < 0 or depth < previous:
						_reachability_cache[key] = depth
			if depth >= MAX_SETUP_STEPS:
				continue
			var actions: Array = node.actions
			for action_id: StringName in MatchSetupStateRules.get_candidate_actions(attacker, target):
				if action_id in actions:
					continue
				var projected := MatchSetupStateRules.project_action(action_id, attacker, target)
				if not bool(projected.get("valid", false)):
					continue
				var next_attacker: Dictionary = projected.attacker
				var next_target: Dictionary = projected.target
				var state_key := _snapshot_pair_key(next_attacker, next_target)
				if int(visited.get(state_key, 999)) <= depth + 1:
					continue
				visited[state_key] = depth + 1
				var next_actions := actions.duplicate()
				next_actions.append(action_id)
				next_frontier.append({
					"attacker": next_attacker,
					"target": next_target,
					"actions": next_actions,
				})
		frontier = next_frontier
		if frontier.is_empty():
			break


func _register_move_result_state(path_data: Dictionary, result_states: Dictionary) -> void:
	var move: MoveResource = path_data.move
	if move == null:
		return
	var attacker: Dictionary = _result_snapshot(path_data.attacker, move, true)
	var target: Dictionary = _result_snapshot(path_data.target, move, false)
	var key := _snapshot_pair_key(attacker, target)
	if not result_states.has(key):
		result_states[key] = {"attacker": attacker, "target": target}


func _result_snapshot(current: Dictionary, move: MoveResource, attacker_result: bool) -> Dictionary:
	var result := current.duplicate(true)
	if attacker_result:
		result.position = int(move.resulting_attacker_position)
		result.orientation = int(move.resulting_attacker_orientation)
		result.motion_state = int(move.resulting_attacker_motion_state)
		if move.resulting_attacker_area_mode == MoveResource.AreaResultMode.SPECIFIC:
			result.area = int(move.resulting_attacker_area)
	else:
		result.position = int(move.resulting_target_position)
		result.orientation = int(move.resulting_target_orientation)
		result.motion_state = int(move.resulting_target_motion_state)
		if move.resulting_target_area_mode == MoveResource.AreaResultMode.SPECIFIC:
			result.area = int(move.resulting_target_area)
	return result


func _snapshot_pair_key(attacker: Dictionary, target: Dictionary) -> String:
	return "%d:%d:%d:%d|%d:%d:%d:%d" % [
		int(attacker.get("position", WrestlerResource.Position.NONE)),
		int(attacker.get("orientation", WrestlerResource.Orientation.NONE)),
		int(attacker.get("area", WrestlerResource.Area.IN_RING)),
		int(attacker.get("motion_state", WrestlerResource.MotionState.STATIONARY)),
		int(target.get("position", WrestlerResource.Position.NONE)),
		int(target.get("orientation", WrestlerResource.Orientation.NONE)),
		int(target.get("area", WrestlerResource.Area.IN_RING)),
		int(target.get("motion_state", WrestlerResource.MotionState.STATIONARY)),
	]


func _neutral_snapshot() -> Dictionary:
	return {
		"position": WrestlerResource.Position.STANDING,
		"orientation": WrestlerResource.Orientation.FRONT,
		"area": WrestlerResource.Area.IN_RING,
		"motion_state": WrestlerResource.MotionState.STATIONARY,
	}


func _move_category(move: MoveResource) -> StringName:
	match move.move_type:
		MoveResource.MoveType.STRIKE:
			return CATEGORY_STRIKE
		MoveResource.MoveType.GRAPPLE:
			return CATEGORY_GRAPPLE
		MoveResource.MoveType.RUNNING:
			return CATEGORY_RUNNING
		MoveResource.MoveType.SUBMISSION:
			return CATEGORY_SUBMISSION
		MoveResource.MoveType.AERIAL, MoveResource.MoveType.SPRINGBOARD:
			return CATEGORY_AERIAL
		MoveResource.MoveType.PINNING_MOVE:
			return CATEGORY_PIN
	return CATEGORY_OTHER


func _candidate_covers_role(candidate: Dictionary, role: StringName) -> bool:
	var move: MoveResource = candidate.move
	match role:
		ROLE_STANDING_FRONT:
			return (
				move.required_attacker_position == WrestlerResource.Position.STANDING
				and move.required_attacker_orientation == WrestlerResource.Orientation.FRONT
				and move.required_target_position == WrestlerResource.Position.STANDING
				and move.required_target_orientation == WrestlerResource.Orientation.FRONT
			)
		ROLE_STANDING_BACK:
			return (
				move.required_target_position == WrestlerResource.Position.STANDING
				and move.required_target_orientation == WrestlerResource.Orientation.BACK
			)
		ROLE_GROUNDED_FACE_UP:
			return (
				move.required_target_position == WrestlerResource.Position.GROUNDED
				and move.required_target_orientation == WrestlerResource.Orientation.FACE_UP
			)
		ROLE_GROUNDED_FACE_DOWN:
			return (
				move.required_target_position == WrestlerResource.Position.GROUNDED
				and move.required_target_orientation == WrestlerResource.Orientation.FACE_DOWN
			)
		ROLE_RUNNING_REBOUND:
			return (
				move.required_attacker_motion_state == WrestlerResource.MotionState.RUNNING
				or move.required_target_motion_state == WrestlerResource.MotionState.ROPE_REBOUND
			)
		ROLE_CORNER:
			return (
				(move.required_attacker_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_attacker_area == WrestlerResource.Area.CORNER)
				or (move.required_target_area_mode == MoveResource.AreaRequirementMode.SPECIFIC and move.required_target_area == WrestlerResource.Area.CORNER)
			)
		ROLE_PINNING:
			return move.move_type == MoveResource.MoveType.PINNING_MOVE or move.is_pinning_combination or move.is_flash_pin
	return false


func _coverage_count(selected: Array[Dictionary], role: StringName) -> int:
	var count := 0
	for candidate in selected:
		if _candidate_covers_role(candidate, role):
			count += 1
	return count


func _category_count(selected: Array[Dictionary], category: StringName) -> int:
	var count := 0
	for candidate in selected:
		if StringName(candidate.category) == category:
			count += 1
	return count


func _selected_category_counts(selected: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for candidate in selected:
		var category := StringName(candidate.category)
		counts[category] = int(counts.get(category, 0)) + 1
	return counts


func _category_counts_for_moves(moves: Array[MoveResource]) -> Dictionary:
	var counts := {
		CATEGORY_STRIKE: 0,
		CATEGORY_GRAPPLE: 0,
		CATEGORY_RUNNING: 0,
		CATEGORY_SUBMISSION: 0,
		CATEGORY_AERIAL: 0,
		CATEGORY_PIN: 0,
		CATEGORY_OTHER: 0,
	}
	for move in moves:
		if move == null:
			continue
		var category := _move_category(move)
		counts[category] = int(counts.get(category, 0)) + 1
	return counts


func _coverage_counts_for_moves(moves: Array[MoveResource]) -> Dictionary:
	var counts: Dictionary = {}
	for role in COVERAGE_TARGETS:
		counts[role] = 0
	for move in moves:
		if move == null:
			continue
		var candidate := {"move": move}
		for role in COVERAGE_TARGETS:
			if _candidate_covers_role(candidate, role):
				counts[role] = int(counts[role]) + 1
	return counts


func _submission_cap(wrestler: WrestlerResource) -> int:
	return 6 if _has_class(wrestler, WrestlerResource.WrestlerClass.TECHNICIAN) else 3


func _has_class(wrestler: WrestlerResource, wrestler_class: int) -> bool:
	return wrestler_class in wrestler.wrestler_class


func _selection_context(selected: Array[Dictionary]) -> Dictionary:
	var selected_paths: Dictionary = {}
	var family_counts: Dictionary = {}
	var state_counts: Dictionary = {}
	var target_counts: Dictionary = {}
	for candidate in selected:
		selected_paths[str(candidate.path)] = true
		var family := str(candidate.family)
		var state_key := str(candidate.state_key)
		var target_group := str(candidate.target_group)
		family_counts[family] = int(family_counts.get(family, 0)) + 1
		state_counts[state_key] = int(state_counts.get(state_key, 0)) + 1
		target_counts[target_group] = int(target_counts.get(target_group, 0)) + 1
	return {
		"selected_count": selected.size(),
		"selected_paths": selected_paths,
		"family_counts": family_counts,
		"state_counts": state_counts,
		"target_counts": target_counts,
		"category_counts": _selected_category_counts(selected),
	}


func _special_variety_bonus(candidate: Dictionary, selection_context: Dictionary) -> float:
	if int(selection_context.selected_count) == 0:
		return 30.0
	var state_counts: Dictionary = selection_context.state_counts
	var duplicate_state := int(state_counts.get(str(candidate.state_key), 0))
	return 30.0 if duplicate_state == 0 else -45.0 * float(duplicate_state)


func _target_variety_bonus(candidate: Dictionary, selection_context: Dictionary, section: StringName) -> float:
	if section not in [&"signature", &"finisher"] or int(selection_context.selected_count) == 0:
		return 0.0
	var target_counts: Dictionary = selection_context.target_counts
	if int(target_counts.get(str(candidate.target_group), 0)) > 0:
		return -25.0
	return 20.0


func _similarity_penalty(candidate: Dictionary, selection_context: Dictionary) -> float:
	var family_counts: Dictionary = selection_context.family_counts
	var penalty := 40.0 * float(family_counts.get(str(candidate.family), 0))
	var selected_paths: Dictionary = selection_context.selected_paths
	for similar_path in candidate.get("similar_paths", []):
		if selected_paths.has(str(similar_path)):
			penalty += 60.0
	return penalty


func _cache_similarity_links(candidates: Array[Dictionary]) -> void:
	for candidate in candidates:
		candidate["similar_paths"] = []
	for left_index in candidates.size():
		var left: Dictionary = candidates[left_index]
		for right_index in range(left_index + 1, candidates.size()):
			var right: Dictionary = candidates[right_index]
			if str(left.family) == str(right.family):
				continue
			if _token_similarity(left.name_tokens, right.name_tokens) < 0.75:
				continue
			left.similar_paths.append(str(right.path))
			right.similar_paths.append(str(left.path))


func _token_similarity(left: Array, right: Array) -> float:
	if left.is_empty() or right.is_empty():
		return 0.0
	var union: Dictionary = {}
	var intersection := 0
	for token in left:
		union[token] = true
	for token in right:
		if union.has(token):
			intersection += 1
		union[token] = true
	return float(intersection) / float(maxi(1, union.size()))


func _move_family(move_name: String) -> String:
	return "_".join(_meaningful_name_tokens(move_name))


func _meaningful_name_tokens(move_name: String) -> Array[String]:
	var cleaned := move_name.to_lower()
	for separator in ["-", "/", "'", "(", ")"]:
		cleaned = cleaned.replace(separator, " ")
	var tokens: Array[String] = []
	for token in cleaned.split(" ", false):
		if token in _CONTEXT_NAME_WORDS:
			continue
		tokens.append(token)
	if tokens.is_empty():
		tokens.append(move_name.to_lower().replace(" ", "_"))
	return tokens


func _required_state_key(move: MoveResource) -> String:
	return "%d:%d:%d:%d:%d|%d:%d:%d:%d:%d" % [
		move.required_attacker_position,
		move.required_attacker_orientation,
		move.required_attacker_area_mode,
		move.required_attacker_area,
		move.required_attacker_motion_state,
		move.required_target_position,
		move.required_target_orientation,
		move.required_target_area_mode,
		move.required_target_area,
		move.required_target_motion_state,
	]


func _target_group(move: MoveResource) -> String:
	var parts: Array[String] = []
	for part in move.move_target_parts:
		parts.append(str(part))
	parts.sort()
	return ",".join(parts)


func _add_candidate(candidate: Dictionary, selected: Array[Dictionary], remaining: Array[Dictionary]) -> void:
	selected.append(candidate)
	remaining.erase(candidate)


func _register_unique_move(move: MoveResource, paths: Dictionary, errors: Array[String]) -> void:
	var key := _resource_key(move)
	if paths.has(key):
		errors.append("Move is assigned more than once: %s" % move.move_name)
	else:
		paths[key] = true


func _resource_path_set(moves: Array[MoveResource]) -> Dictionary:
	var paths: Dictionary = {}
	for move in moves:
		if move != null:
			paths[_resource_key(move)] = true
	return paths


func _resource_key(move: MoveResource) -> String:
	if move.resource_path.is_empty():
		return "memory://%d:%s" % [move.get_instance_id(), move.move_name]
	return move.resource_path


func _select_wrestler_paths(all_paths: Array[String], options: Dictionary, audit_all_default: bool) -> Array[String]:
	var operation := int(options.operation)
	if audit_all_default and operation == Operation.AUDIT_EXISTING:
		return _copy_string_array(all_paths)
	match operation:
		Operation.GENERATE_ONE:
			var one_path := str(options.wrestler_path)
			var one_result: Array[String] = []
			if one_path in all_paths:
				one_result.append(one_path)
			return one_result
		Operation.GENERATE_SELECTED:
			var requested: PackedStringArray = options.wrestler_paths
			if requested.is_empty() and get_editor_interface() != null:
				requested = get_editor_interface().get_selected_paths()
			var selected: Array[String] = []
			for path in requested:
				if path in all_paths and path not in selected:
					selected.append(path)
			selected.sort()
			return selected
		Operation.GENERATE_ALL, Operation.GENERATE_MISSING, Operation.AUDIT_EXISTING:
			return _copy_string_array(all_paths)
	var empty: Array[String] = []
	return empty


func _copy_string_array(source: Array[String]) -> Array[String]:
	var result: Array[String] = []
	result.append_array(source)
	return result


func _normalized_options(options: Dictionary) -> Dictionary:
	var result := default_options()
	result.merge(options, true)
	result["signature_target"] = maxi(MINIMUM_SIGNATURES, int(result.signature_target))
	if not (result.wrestler_paths is PackedStringArray):
		var paths := PackedStringArray()
		for path in result.wrestler_paths:
			paths.append(str(path))
		result["wrestler_paths"] = paths
	return result


func _collect_resource_paths(root: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var path := root.path_join(name)
			if directory.current_is_dir():
				_collect_resource_paths(path, output)
			elif name.get_extension().to_lower() == "tres":
				output.append(path)
		name = directory.get_next()
	directory.list_dir_end()


func _load_wrestler_snapshot(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return {
			"wrestler": null,
			"hard_errors": ["Could not read WrestlerResource text: %s" % path],
			"warnings": [],
		}
	var properties := _resource_properties(raw)
	if properties.is_empty():
		return {
			"wrestler": null,
			"hard_errors": ["WrestlerResource has no resource properties: %s" % path],
			"warnings": [],
		}
	var wrestler := WrestlerResource.new()
	wrestler.wrestler_name = _string_property(properties, "wrestler_name", path.get_file().get_basename())
	wrestler.gimmick_name = _string_property(properties, "gimmick_name", "")
	wrestler.gimmick_description = _string_property(properties, "gimmick_description", "")
	wrestler.wrestler_id = _int_property(properties, "wrestler_id", 0)
	wrestler.wrestler_class = _class_property(properties)
	wrestler.wrestler_gender = _int_property(properties, "wrestler_gender", WrestlerResource.WrestlerGender.MALE)
	wrestler.wrestler_disposition = _int_property(properties, "wrestler_disposition", WrestlerResource.WrestlerDisposition.FACE)
	wrestler.Age = _int_property(properties, "Age", 25)
	wrestler.wrestler_height = _string_property(properties, "wrestler_height", "6'0")
	wrestler.wrestler_weight = _int_property(properties, "wrestler_weight", 220)
	wrestler.strength = _float_property(properties, "strength", 10.0)
	wrestler.speed = _float_property(properties, "speed", 10.0)
	wrestler.stamina = _float_property(properties, "stamina", 10.0)
	wrestler.skill = _float_property(properties, "skill", 10.0)
	wrestler.striking = _float_property(properties, "striking", 10.0)
	wrestler.charisma = _float_property(properties, "charisma", 10.0)

	var warnings: Array[String] = []
	var dependency_paths := _move_dependency_paths(raw)
	wrestler.move_set = _load_text_move_section(properties, dependency_paths, "move_set", path, warnings)
	wrestler.signature_moves = _load_text_move_section(properties, dependency_paths, "signature_moves", path, warnings)
	wrestler.finisher_moves = _load_text_move_section(properties, dependency_paths, "finisher_moves", path, warnings)
	return {
		"wrestler": wrestler,
		"hard_errors": [],
		"warnings": warnings,
	}


func _resource_properties(raw: String) -> Dictionary:
	var properties: Dictionary = {}
	var in_resource := false
	for line in raw.split("\n"):
		var stripped := line.strip_edges()
		if stripped == "[resource]":
			in_resource = true
			continue
		if not in_resource or stripped.is_empty() or stripped.begins_with("#"):
			continue
		var separator := stripped.find("=")
		if separator <= 0:
			continue
		var key := stripped.substr(0, separator).strip_edges()
		var value := stripped.substr(separator + 1).strip_edges()
		properties[key] = value
	return properties


func _move_dependency_paths(raw: String) -> Dictionary:
	var paths: Dictionary = {}
	for line in raw.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("[ext_resource"):
			continue
		var resource_path := _quoted_attribute(stripped, "path")
		var resource_id := _quoted_attribute(stripped, "id")
		if not resource_id.is_empty() and resource_path.begins_with("res://Moves/"):
			paths[resource_id] = resource_path
	return paths


func _quoted_attribute(line: String, attribute: String) -> String:
	var marker := "%s=\"" % attribute
	var start := line.find(marker)
	if start < 0:
		return ""
	start += marker.length()
	var finish := line.find("\"", start)
	return line.substr(start, finish - start) if finish >= start else ""


func _load_text_move_section(
	properties: Dictionary,
	dependency_paths: Dictionary,
	property_name: String,
	wrestler_path: String,
	warnings: Array[String],
) -> Array[MoveResource]:
	var moves: Array[MoveResource] = []
	var serialized := str(properties.get(property_name, ""))
	if serialized.is_empty():
		return moves
	var id_regex := RegEx.new()
	id_regex.compile("ExtResource\\(\\\"([^\\\"]+)\\\"\\)")
	var missing: Array[String] = []
	for match_result in id_regex.search_all(serialized):
		var resource_id := match_result.get_string(1)
		if not dependency_paths.has(resource_id):
			continue
		var move_path := str(dependency_paths[resource_id])
		if not ResourceLoader.exists(move_path):
			missing.append(move_path)
			continue
		var resource := ResourceLoader.load(move_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if resource is MoveResource:
			moves.append(resource)
		else:
			missing.append(move_path)
	if not missing.is_empty():
		var examples := missing.slice(0, mini(3, missing.size()))
		warnings.append("%s has %d unavailable %s dependencies, for example: %s" % [
			wrestler_path,
			missing.size(),
			property_name,
			", ".join(examples),
		])
	return moves


func _string_property(properties: Dictionary, property_name: String, fallback: String) -> String:
	if not properties.has(property_name):
		return fallback
	var parsed = JSON.parse_string(str(properties[property_name]))
	return str(parsed) if parsed is String else fallback


func _int_property(properties: Dictionary, property_name: String, fallback: int) -> int:
	if not properties.has(property_name):
		return fallback
	return int(str(properties[property_name]))


func _float_property(properties: Dictionary, property_name: String, fallback: float) -> float:
	if not properties.has(property_name):
		return fallback
	return float(str(properties[property_name]))


func _class_property(properties: Dictionary) -> Array[WrestlerResource.WrestlerClass]:
	var classes: Array[WrestlerResource.WrestlerClass] = []
	var serialized := str(properties.get("wrestler_class", ""))
	var contents_regex := RegEx.new()
	contents_regex.compile("\\(\\[([^\\]]*)\\]\\)")
	var contents := contents_regex.search(serialized)
	if contents == null:
		return classes
	for value in contents.get_string(1).split(",", false):
		var class_value := int(value.strip_edges())
		if class_value in WrestlerResource.WrestlerClass.values():
			classes.append(class_value as WrestlerResource.WrestlerClass)
	return classes


func _seed_for_wrestler(base_seed: int, path: String, wrestler: WrestlerResource) -> int:
	var identity := "%d|%s|%d|%s" % [base_seed, path, wrestler.wrestler_id, wrestler.wrestler_name]
	var value := 2166136261
	for byte in identity.to_utf8_buffer():
		value = int((value ^ int(byte)) * 16777619) & 0x7fffffff
	return value


func _wrestler_name(wrestler: WrestlerResource) -> String:
	return wrestler.wrestler_name if not wrestler.wrestler_name.strip_edges().is_empty() else wrestler.resource_path.get_file()


func _safe_run_id(seed_value: int) -> String:
	return "%s_seed_%d" % [Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_"), seed_value]


func _stage_entry(entry: Dictionary, staging_root: String) -> Dictionary:
	var original_path := str(entry.wrestler_path)
	var sanitized_path := "%s/source/%s" % [staging_root, original_path.trim_prefix("res://")]
	var sanitize_error := _write_sanitized_wrestler(original_path, sanitized_path)
	if sanitize_error != OK:
		return {"success": false, "error": "Could not prepare dependency-safe copy of %s." % original_path}
	var resource := ResourceLoader.load(sanitized_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var wrestler := resource as WrestlerResource if resource is WrestlerResource else null
	if wrestler == null:
		return {"success": false, "error": "Could not load dependency-safe wrestler copy: %s" % original_path}
	var staged := wrestler.duplicate(true) as WrestlerResource
	if staged == null:
		return {"success": false, "error": "Could not duplicate wrestler for staging: %s" % original_path}
	staged.move_set = _typed_moves(entry.regular_moves)
	staged.signature_moves = _typed_moves(entry.signature_moves)
	staged.finisher_moves = _typed_moves(entry.finisher_moves)
	var staging_path := "%s/%s" % [staging_root, original_path.trim_prefix("res://")]
	var ensure_error := _ensure_parent_directory(staging_path)
	if ensure_error != OK:
		return {"success": false, "error": "Could not create staging directory for %s." % original_path}
	var save_error := ResourceSaver.save(staged, staging_path)
	if save_error != OK:
		return {"success": false, "error": "Could not stage %s (error %d)." % [original_path, save_error]}
	var reloaded := ResourceLoader.load(staging_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (reloaded is WrestlerResource):
		return {"success": false, "error": "Staged resource failed validation: %s" % staging_path}
	var audit := _audit_assignment(reloaded, reloaded.move_set, reloaded.signature_moves, reloaded.finisher_moves)
	if not audit.hard_errors.is_empty():
		return {"success": false, "error": "Staged resource failed moveset audit: %s" % original_path}
	return {"success": true, "original_path": original_path, "staging_path": staging_path}


func _write_sanitized_wrestler(original_path: String, sanitized_path: String) -> Error:
	var raw := FileAccess.get_file_as_string(original_path)
	if raw.is_empty():
		return ERR_FILE_CANT_READ
	var lines: Array[String] = []
	for line in raw.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("[ext_resource") and _quoted_attribute(stripped, "path").begins_with("res://Moves/"):
			continue
		if (
			stripped.begins_with("move_set =")
			or stripped.begins_with("signature_moves =")
			or stripped.begins_with("finisher_moves =")
		):
			continue
		lines.append(line)
	var ensure_error := _ensure_parent_directory(sanitized_path)
	if ensure_error != OK:
		return ensure_error
	var file := FileAccess.open(sanitized_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines))
	file.close()
	return OK


func _typed_moves(source: Array) -> Array[MoveResource]:
	var moves: Array[MoveResource] = []
	for move in source:
		if move is MoveResource:
			moves.append(move)
	return moves


func _backup_resource(original_path: String, backup_path: String) -> Error:
	var ensure_error := _ensure_parent_directory(backup_path)
	if ensure_error != OK:
		return ensure_error
	return DirAccess.copy_absolute(
		ProjectSettings.globalize_path(original_path),
		ProjectSettings.globalize_path(backup_path),
	)


func _rollback_resources(written_paths: Array[String], backup_paths: Dictionary) -> void:
	for original_path in written_paths:
		if not backup_paths.has(original_path):
			continue
		var restore_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(str(backup_paths[original_path])),
			ProjectSettings.globalize_path(original_path),
		)
		if restore_error != OK:
			push_error("MovesetGenerator rollback failed for %s (error %d)." % [original_path, restore_error])


func _ensure_parent_directory(path: String) -> Error:
	var global_directory := ProjectSettings.globalize_path(path.get_base_dir())
	return DirAccess.make_dir_recursive_absolute(global_directory)


func _render_report(result: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("MOVESET GENERATOR REPORT")
	lines.append("=".repeat(96))
	lines.append("Kind: %s" % str(result.get("kind", "unknown")))
	lines.append("Seed: %s" % str(result.get("seed", "n/a")))
	lines.append("Success: %s" % str(result.get("success", false)))
	lines.append("Applied: %s" % str(result.get("applied", false)))
	var options: Dictionary = result.get("options", {})
	if not options.is_empty():
		lines.append("Operation: %s" % _operation_name(int(options.get("operation", Operation.AUDIT_EXISTING))))
		lines.append("Dry run: %s | Save enabled: %s" % [options.get("dry_run", true), options.get("allow_save", false)])
		lines.append("Preserve regular/signatures/finishers: %s / %s / %s" % [
			options.get("preserve_regular", false),
			options.get("preserve_signatures", false),
			options.get("preserve_finishers", false),
		])
	if result.has("catalogue_counts"):
		lines.append("Catalogue: %s" % str(result.catalogue_counts))
	lines.append("")
	var errors: Array = result.get("hard_errors", [])
	lines.append("HARD ERRORS (%d)" % errors.size())
	for error in errors:
		lines.append("- %s" % str(error))
	var warnings: Array = result.get("warnings", [])
	lines.append("")
	lines.append("WARNINGS (%d)" % warnings.size())
	for warning in warnings:
		lines.append("- %s" % str(warning))
	lines.append("")
	lines.append("WRESTLERS")
	lines.append("-".repeat(96))
	for entry: Dictionary in result.get("entries", []):
		lines.append("%s | %s" % [entry.get("wrestler_name", "Unknown"), entry.get("wrestler_path", "")])
		if bool(entry.get("skipped", false)):
			lines.append("  SKIPPED: %s" % entry.get("skip_reason", "No reason supplied."))
			continue
		if entry.has("before"):
			lines.append("  Before: %s | After: %s" % [entry.before, entry.after])
		lines.append("  Categories: %s" % str(entry.get("categories", {})))
		lines.append("  Coverage: %s" % str(entry.get("coverage", {})))
		lines.append("  Regular: %s" % _move_names(entry.get("regular_moves", [])))
		lines.append("  Signatures: %s" % _move_names(entry.get("signature_moves", [])))
		lines.append("  Finishers: %s" % _move_names(entry.get("finisher_moves", [])))
		for error in entry.get("hard_errors", []):
			lines.append("  ERROR: %s" % error)
		for warning in entry.get("warnings", []):
			lines.append("  WARNING: %s" % warning)
		lines.append("")
	return "\n".join(lines) + "\n"


func _move_names(moves: Array) -> String:
	var names: Array[String] = []
	for move in moves:
		if move is MoveResource:
			names.append(move.move_name)
	return ", ".join(names) if not names.is_empty() else "[None]"


func _operation_name(operation: int) -> String:
	return Operation.keys()[operation] if operation >= 0 and operation < Operation.size() else "UNKNOWN"


func _print_result(result: Dictionary) -> void:
	var entries: Array = result.get("entries", [])
	var errors: Array = result.get("hard_errors", [])
	var warnings: Array = result.get("warnings", [])
	var skipped := 0
	var entry_failures := 0
	for entry: Dictionary in entries:
		if bool(entry.get("skipped", false)):
			skipped += 1
		if not entry.get("hard_errors", []).is_empty():
			entry_failures += 1
	print("MovesetGenerator summary")
	print("  Mode: %s | Seed: %s | Applied: %s" % [
		str(result.get("kind", "unknown")),
		str(result.get("seed", "n/a")),
		str(result.get("applied", false)),
	])
	print("  Wrestlers: %d total | %d skipped | %d with errors" % [
		entries.size(), skipped, entry_failures,
	])
	print("  Run messages: %d hard errors | %d warnings" % [errors.size(), warnings.size()])
	for index in mini(5, errors.size()):
		print("  ERROR: %s" % str(errors[index]))
	if errors.size() > 5:
		print("  ... %d additional errors are in the report file." % (errors.size() - 5))
	print("  Detailed wrestler and move breakdown is written to the report file only.")


func _unique_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if value not in result:
			result.append(value)
	return result
