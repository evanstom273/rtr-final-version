@tool
extends EditorScript
class_name MovesetGen

const WRESTLER_FOLDER: String = "res://Wrestlers"
const MOVE_FOLDER: String = "res://Moves"

const MIN_TOTAL_MOVES: int = 50
const MAX_TOTAL_MOVES: int = 50
const FINISHER_COUNT: int = 3

const ARCHETYPE_RATIO_MIN: float = 0.70
const ARCHETYPE_RATIO_MAX: float = 0.80
const HARDCORE_GENERAL_BONUS: float = 0.05

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
const MAX_STRIKER_REGULAR_STRIKES: int = 16
const MIN_STRIKER_NON_STRIKE_STYLE_MOVES: int = 14

const MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL: int = 8
const MIN_HIGH_FLYER_REGULAR_SPRINGBOARD: int = 2
const MIN_HIGH_FLYER_REGULAR_DIVING_STANDING: int = 2
const MIN_HIGH_FLYER_REGULAR_DIVING_GROUNDED: int = 2

const SAVE_AFTER_ASSIGN: bool = true
const REPLACE_EXISTING_MOVESET: bool = true

const MAX_GENERATION_ATTEMPTS: int = 250
const MAX_REPAIR_ATTEMPTS: int = 300
const MAX_SECONDS_PER_WRESTLER: float = 3.0


func _run() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var all_moves: Array[MoveResource] = _load_all_moves(MOVE_FOLDER)
	if all_moves.is_empty():
		push_error("No moves found in %s" % MOVE_FOLDER)
		return

	var wrestler_paths: Array[String] = []
	_collect_wrestler_paths(WRESTLER_FOLDER, wrestler_paths)

	if wrestler_paths.is_empty():
		push_error("No wrestlers found in %s" % WRESTLER_FOLDER)
		return

	var processed: int = 0
	var failed: int = 0
	var wrestler_index: int = 0

	for wrestler_path: String in wrestler_paths:
		wrestler_index += 1

		if wrestler_index % 25 == 0:
			print("Processed %s / %s wrestler paths..." % [
				str(wrestler_index),
				str(wrestler_paths.size())
			])

		var res: Resource = load(wrestler_path)
		if not (res is WrestlerResource):
			continue

		var wrestler: WrestlerResource = res as WrestlerResource

		var start_time_msec: int = Time.get_ticks_msec()
		var generated: Array[MoveResource] = []
		var success: bool = false

		for attempt: int in range(MAX_GENERATION_ATTEMPTS):
			var elapsed_seconds: float = float(Time.get_ticks_msec() - start_time_msec) / 1000.0
			if elapsed_seconds > MAX_SECONDS_PER_WRESTLER:
				break

			generated = _generate_moveset_for_wrestler(wrestler, all_moves, rng)
			if not generated.is_empty():
				success = true
				break

		if not success:
			failed += 1
			push_warning("Failed to generate moveset for %s (%s) after %s attempts or time limit." % [
				wrestler_path,
				_display_name(wrestler),
				str(MAX_GENERATION_ATTEMPTS)
			])
			continue

		if REPLACE_EXISTING_MOVESET:
			wrestler.move_set.clear()

		wrestler.move_set = generated

		if SAVE_AFTER_ASSIGN:
			var save_result: int = ResourceSaver.save(wrestler, wrestler_path)
			if save_result != OK:
				failed += 1
				push_warning("Failed saving wrestler %s" % wrestler_path)
				continue

		processed += 1
		print("Generated moveset for %s (%s moves)" % [wrestler_path, str(generated.size())])

	print("")
	print("========================================")
	print("Moveset generation complete")
	print("Processed: %s" % str(processed))
	print("Failed: %s" % str(failed))
	print("Move pool size: %s" % str(all_moves.size()))
	print("========================================")


func _generate_moveset_for_wrestler(
	wrestler: WrestlerResource,
	all_moves: Array[MoveResource],
	rng: RandomNumberGenerator
) -> Array[MoveResource]:
	if wrestler.wrestler_class.is_empty():
		return []

	var primary_class: WrestlerResource.WrestlerClass = _primary_class(wrestler)

	if primary_class == WrestlerResource.WrestlerClass.STRIKER:
		return _generate_striker_moveset_for_wrestler(wrestler, all_moves, rng)

	return _generate_standard_moveset_for_wrestler(wrestler, all_moves, rng)


func _generate_standard_moveset_for_wrestler(
	wrestler: WrestlerResource,
	all_moves: Array[MoveResource],
	rng: RandomNumberGenerator
) -> Array[MoveResource]:
	var total_slots: int = rng.randi_range(MIN_TOTAL_MOVES, MAX_TOTAL_MOVES)
	var regular_slots: int = total_slots - FINISHER_COUNT
	var primary_class: WrestlerResource.WrestlerClass = _primary_class(wrestler)

	var archetype_ratio: float = rng.randf_range(ARCHETYPE_RATIO_MIN, ARCHETYPE_RATIO_MAX)
	if primary_class == WrestlerResource.WrestlerClass.HARDCORE:
		archetype_ratio = max(ARCHETYPE_RATIO_MIN, archetype_ratio - HARDCORE_GENERAL_BONUS)

	var archetype_regular_slots: int = int(round(float(regular_slots) * archetype_ratio))
	var general_regular_slots: int = regular_slots - archetype_regular_slots

	var finisher_pool: Array[MoveResource] = _dedupe_resources(
		_filter_finisher_pool(all_moves, wrestler.wrestler_class)
	)

	var archetype_pool: Array[MoveResource] = _dedupe_resources(
		_filter_archetype_regular_pool(all_moves, wrestler.wrestler_class)
	)

	var general_pool: Array[MoveResource] = _dedupe_resources(
		_filter_general_regular_pool(all_moves)
	)

	var chosen: Array[MoveResource] = []

	var chosen_finishers: Array[MoveResource] = _pick_legal_moves(
		chosen,
		finisher_pool,
		FINISHER_COUNT,
		wrestler,
		rng,
		true
	)

	if chosen_finishers.size() != FINISHER_COUNT:
		return []

	chosen.append_array(chosen_finishers)

	var chosen_archetype: Array[MoveResource] = _pick_legal_moves(
		chosen,
		archetype_pool,
		archetype_regular_slots,
		wrestler,
		rng,
		false
	)
	chosen.append_array(chosen_archetype)

	var chosen_general: Array[MoveResource] = _pick_legal_moves(
		chosen,
		general_pool,
		general_regular_slots,
		wrestler,
		rng,
		false
	)
	chosen.append_array(chosen_general)

	if chosen.size() < total_slots:
		var fallback_pool: Array[MoveResource] = _build_fallback_pool(all_moves, wrestler, chosen, false)
		var refill: Array[MoveResource] = _pick_legal_moves(
			chosen,
			fallback_pool,
			total_slots - chosen.size(),
			wrestler,
			rng,
			false
		)
		chosen.append_array(refill)

	chosen = _repair_moveset(chosen, all_moves, wrestler, total_slots, rng)
	chosen = _trim_if_needed(chosen, wrestler, total_slots, all_moves, rng)

	if not _moveset_meets_hard_rules(chosen, wrestler, total_slots):
		return []

	return chosen


func _generate_striker_moveset_for_wrestler(
	wrestler: WrestlerResource,
	all_moves: Array[MoveResource],
	rng: RandomNumberGenerator
) -> Array[MoveResource]:
	var total_slots: int = rng.randi_range(MIN_TOTAL_MOVES, MAX_TOTAL_MOVES)
	var regular_slots: int = total_slots - FINISHER_COUNT

	var chosen: Array[MoveResource] = []

	var finisher_pool: Array[MoveResource] = _dedupe_resources(
		_filter_finisher_pool(all_moves, wrestler.wrestler_class)
	)

	var chosen_finishers: Array[MoveResource] = _pick_legal_moves(
		chosen,
		finisher_pool,
		FINISHER_COUNT,
		wrestler,
		rng,
		true
	)

	if chosen_finishers.size() != FINISHER_COUNT:
		return []

	chosen.append_array(chosen_finishers)

	var target_regular_strikes: int = rng.randi_range(
		MIN_STRIKER_REGULAR_STRIKES,
		MAX_STRIKER_REGULAR_STRIKES
	)
	target_regular_strikes = min(target_regular_strikes, MAX_STRIKES_STRIKER)

	var striker_strike_pool: Array[MoveResource] = _dedupe_resources(
		_filter_striker_regular_strike_pool(all_moves)
	)

	var striker_non_strike_style_pool: Array[MoveResource] = _dedupe_resources(
		_filter_striker_regular_non_strike_style_pool(all_moves)
	)

	var general_non_strike_pool: Array[MoveResource] = _dedupe_resources(
		_filter_general_regular_non_strike_pool(all_moves)
	)

	var support_non_strike_pool: Array[MoveResource] = _dedupe_resources(
		_filter_support_regular_non_strike_pool(all_moves, wrestler.wrestler_class)
	)

	var chosen_strikes: Array[MoveResource] = _pick_legal_moves(
		chosen,
		striker_strike_pool,
		target_regular_strikes,
		wrestler,
		rng,
		false
	)
	chosen.append_array(chosen_strikes)

	var chosen_non_strike_style: Array[MoveResource] = _pick_legal_moves(
		chosen,
		striker_non_strike_style_pool,
		MIN_STRIKER_NON_STRIKE_STYLE_MOVES,
		wrestler,
		rng,
		false
	)
	chosen.append_array(chosen_non_strike_style)

	var archetype_ratio: float = rng.randf_range(ARCHETYPE_RATIO_MIN, ARCHETYPE_RATIO_MAX)
	var target_archetype_regular: int = int(round(float(regular_slots) * archetype_ratio))

	var current_regular_archetype: int = _count_regular_class_style_moves(
		chosen,
		WrestlerResource.WrestlerClass.STRIKER
	)

	var extra_archetype_needed: int = max(0, target_archetype_regular - current_regular_archetype)

	if extra_archetype_needed > 0:
		var extra_style_moves: Array[MoveResource] = _pick_legal_moves(
			chosen,
			striker_non_strike_style_pool,
			extra_archetype_needed,
			wrestler,
			rng,
			false
		)
		chosen.append_array(extra_style_moves)

	if chosen.size() < total_slots:
		var general_needed: int = total_slots - chosen.size()

		var chosen_general: Array[MoveResource] = _pick_legal_moves(
			chosen,
			general_non_strike_pool,
			general_needed,
			wrestler,
			rng,
			false
		)
		chosen.append_array(chosen_general)

	if chosen.size() < total_slots:
		var support_needed: int = total_slots - chosen.size()

		var chosen_support: Array[MoveResource] = _pick_legal_moves(
			chosen,
			support_non_strike_pool,
			support_needed,
			wrestler,
			rng,
			false
		)
		chosen.append_array(chosen_support)

	if chosen.size() < total_slots:
		var fallback_pool: Array[MoveResource] = _build_fallback_pool(
			all_moves,
			wrestler,
			chosen,
			false
		)

		var refill: Array[MoveResource] = _pick_legal_moves(
			chosen,
			fallback_pool,
			total_slots - chosen.size(),
			wrestler,
			rng,
			false
		)
		chosen.append_array(refill)

	chosen = _repair_moveset(chosen, all_moves, wrestler, total_slots, rng)
	chosen = _trim_if_needed(chosen, wrestler, total_slots, all_moves, rng)

	if not _moveset_meets_hard_rules(chosen, wrestler, total_slots):
		return []

	return chosen


func _pick_legal_moves(
	current_moveset: Array[MoveResource],
	candidate_pool: Array[MoveResource],
	desired_count: int,
	wrestler: WrestlerResource,
	rng: RandomNumberGenerator,
	require_finisher: bool
) -> Array[MoveResource]:
	var chosen: Array[MoveResource] = []
	var working_pool: Array[MoveResource] = candidate_pool.duplicate()

	while chosen.size() < desired_count and not working_pool.is_empty():
		var candidate: MoveResource = _pick_one_weighted(working_pool, wrestler, rng)
		if candidate == null:
			break

		working_pool = _remove_resource_once(working_pool, candidate)

		if require_finisher and not candidate.is_finisher:
			continue

		if not require_finisher and candidate.is_finisher:
			continue

		if _move_is_legal_addition(candidate, current_moveset, chosen, wrestler):
			chosen.append(candidate)

	return chosen


func _move_is_legal_addition(
	candidate: MoveResource,
	base_moveset: Array[MoveResource],
	pending_additions: Array[MoveResource],
	wrestler: WrestlerResource
) -> bool:
	var combined: Array[MoveResource] = base_moveset.duplicate()
	combined.append_array(pending_additions)

	if _contains_resource(combined, candidate):
		return false

	if _contains_move_name(combined, candidate.move_name):
		return false

	if candidate.is_finisher:
		if not _move_matches_any_class(candidate, wrestler.wrestler_class):
			return false

	if not _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
		if candidate.move_type == MoveResource.MoveType.SPRINGBOARD:
			if _count_regular_type(combined, MoveResource.MoveType.SPRINGBOARD) >= MAX_SPRINGBOARD_NON_FLYER:
				return false

		if candidate.move_type == MoveResource.MoveType.DIVING_STANDING or candidate.move_type == MoveResource.MoveType.DIVING_GROUNDED:
			if _count_regular_diving(combined) >= MAX_DIVING_NON_FLYER:
				return false

	if candidate.is_submission:
		if _primary_class(wrestler) == WrestlerResource.WrestlerClass.TECHNICIAN:
			if _count_regular_submissions(combined) >= MAX_SUBMISSIONS_TECHNICIAN:
				return false
		else:
			if _count_regular_submissions(combined) >= MAX_SUBMISSIONS_NON_TECHNICIAN:
				return false

	if candidate.is_strike:
		if _primary_class(wrestler) == WrestlerResource.WrestlerClass.STRIKER:
			if _count_regular_strikes(combined) >= MAX_STRIKES_STRIKER:
				return false
		else:
			if _count_regular_strikes(combined) >= MAX_STRIKES_NON_STRIKER:
				return false

	return true


func _repair_moveset(
	moveset: Array[MoveResource],
	all_moves: Array[MoveResource],
	wrestler: WrestlerResource,
	target_size: int,
	rng: RandomNumberGenerator
) -> Array[MoveResource]:
	var result: Array[MoveResource] = moveset.duplicate()
	var attempts: int = 0

	result = _dedupe_by_name_and_resource(result)

	while attempts < MAX_REPAIR_ATTEMPTS:
		attempts += 1

		var violation: Dictionary = _find_first_violation(result, wrestler, target_size)
		if violation.is_empty():
			break

		var remove_index: int = int(violation["index"])
		if remove_index < 0:
			break

		var replacement_pool: Array[MoveResource] = _build_replacement_pool(
			all_moves,
			wrestler,
			result,
			bool(violation["need_finisher"]),
			str(violation["reason"])
		)

		var repaired: bool = false
		var working_pool: Array[MoveResource] = replacement_pool.duplicate()

		while not working_pool.is_empty():
			var candidate: MoveResource = _pick_one_weighted(working_pool, wrestler, rng)
			if candidate == null:
				break

			working_pool = _remove_resource_once(working_pool, candidate)

			if result[remove_index] == candidate:
				continue

			var trial: Array[MoveResource] = result.duplicate()
			trial.remove_at(remove_index)

			if _contains_resource(trial, candidate):
				continue

			if _contains_move_name(trial, candidate.move_name):
				continue

			if not _move_is_legal_addition(candidate, trial, [], wrestler):
				continue

			trial.insert(remove_index, candidate)

			if _violation_count(trial, wrestler, target_size) < _violation_count(result, wrestler, target_size):
				result = trial
				repaired = true
				break

		if not repaired:
			if not bool(violation["need_finisher"]) and result.size() > target_size:
				result.remove_at(remove_index)
			else:
				break

	if result.size() < target_size:
		var refill_pool: Array[MoveResource] = _build_fallback_pool(all_moves, wrestler, result, false)
		var refill: Array[MoveResource] = _pick_legal_moves(
			result,
			refill_pool,
			target_size - result.size(),
			wrestler,
			rng,
			false
		)
		result.append_array(refill)

	result = _dedupe_by_name_and_resource(result)

	return result


func _trim_if_needed(
	moveset: Array[MoveResource],
	wrestler: WrestlerResource,
	target_size: int,
	all_moves: Array[MoveResource],
	rng: RandomNumberGenerator
) -> Array[MoveResource]:
	var result: Array[MoveResource] = moveset.duplicate()

	while result.size() > target_size:
		var removed: bool = false

		for i in range(result.size() - 1, -1, -1):
			if not result[i].is_finisher:
				result.remove_at(i)
				removed = true
				break

		if not removed:
			break

	result = _repair_moveset(result, all_moves, wrestler, target_size, rng)
	return result


func _find_first_violation(
	moveset: Array[MoveResource],
	wrestler: WrestlerResource,
	target_size: int
) -> Dictionary:
	for i in range(moveset.size()):
		var move: MoveResource = moveset[i]
		if move == null:
			return {"index": i, "need_finisher": false, "reason": "null"}

	var seen_resources: Array[MoveResource] = []
	var seen_names: Array[String] = []

	for i in range(moveset.size()):
		var move: MoveResource = moveset[i]

		if _contains_resource(seen_resources, move):
			return {"index": i, "need_finisher": move.is_finisher, "reason": "duplicate_resource"}

		seen_resources.append(move)

		var normalized_name: String = _normalize_name(move.move_name)
		if seen_names.has(normalized_name):
			return {"index": i, "need_finisher": move.is_finisher, "reason": "duplicate_name"}

		seen_names.append(normalized_name)

	if _count_finishers(moveset) != FINISHER_COUNT:
		for i in range(moveset.size()):
			if not moveset[i].is_finisher:
				return {"index": i, "need_finisher": false, "reason": "bad_finisher_count"}

	if _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
		if _count_regular_type(moveset, MoveResource.MoveType.SPRINGBOARD) < MIN_HIGH_FLYER_REGULAR_SPRINGBOARD:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].move_type != MoveResource.MoveType.SPRINGBOARD:
					return {"index": i, "need_finisher": false, "reason": "need_springboard"}

		if _count_regular_diving_standing(moveset) < MIN_HIGH_FLYER_REGULAR_DIVING_STANDING:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].move_type != MoveResource.MoveType.DIVING_STANDING:
					return {"index": i, "need_finisher": false, "reason": "need_diving_standing"}

		if _count_regular_diving_grounded(moveset) < MIN_HIGH_FLYER_REGULAR_DIVING_GROUNDED:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].move_type != MoveResource.MoveType.DIVING_GROUNDED:
					return {"index": i, "need_finisher": false, "reason": "need_diving_grounded"}

		if _count_regular_aerial(moveset) < MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher:
					var is_aerial: bool = (
						moveset[i].move_type == MoveResource.MoveType.SPRINGBOARD
						or moveset[i].move_type == MoveResource.MoveType.DIVING_STANDING
						or moveset[i].move_type == MoveResource.MoveType.DIVING_GROUNDED
					)

					if not is_aerial:
						return {"index": i, "need_finisher": false, "reason": "need_aerial"}
	else:
		if _count_regular_type(moveset, MoveResource.MoveType.SPRINGBOARD) > MAX_SPRINGBOARD_NON_FLYER:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].move_type == MoveResource.MoveType.SPRINGBOARD:
					return {"index": i, "need_finisher": false, "reason": "springboard_cap"}

		if _count_regular_diving(moveset) > MAX_DIVING_NON_FLYER:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and (
					moveset[i].move_type == MoveResource.MoveType.DIVING_STANDING
					or moveset[i].move_type == MoveResource.MoveType.DIVING_GROUNDED
				):
					return {"index": i, "need_finisher": false, "reason": "diving_cap"}

	if _primary_class(wrestler) == WrestlerResource.WrestlerClass.TECHNICIAN:
		if _count_regular_submissions(moveset) > MAX_SUBMISSIONS_TECHNICIAN:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].is_submission:
					return {"index": i, "need_finisher": false, "reason": "submission_cap"}
	else:
		if _count_regular_submissions(moveset) > MAX_SUBMISSIONS_NON_TECHNICIAN:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].is_submission:
					return {"index": i, "need_finisher": false, "reason": "submission_cap"}

	if _primary_class(wrestler) == WrestlerResource.WrestlerClass.STRIKER:
		if _count_regular_strikes(moveset) > MAX_STRIKES_STRIKER:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].is_strike:
					return {"index": i, "need_finisher": false, "reason": "strike_cap"}
	else:
		if _count_regular_strikes(moveset) > MAX_STRIKES_NON_STRIKER:
			for i in range(moveset.size()):
				if not moveset[i].is_finisher and moveset[i].is_strike:
					return {"index": i, "need_finisher": false, "reason": "strike_cap"}

	if _count_regular_type(moveset, MoveResource.MoveType.STANDING_FRONT) < MIN_STANDING_FRONT:
		for i in range(moveset.size()):
			if not moveset[i].is_finisher and moveset[i].move_type != MoveResource.MoveType.STANDING_FRONT:
				return {"index": i, "need_finisher": false, "reason": "need_standing_front"}

	if _count_regular_running_rebound(moveset) < MIN_RUNNING_OR_REBOUND:
		for i in range(moveset.size()):
			if not moveset[i].is_finisher:
				if moveset[i].move_type != MoveResource.MoveType.RUNNING and moveset[i].move_type != MoveResource.MoveType.ROPE_REBOUND:
					return {"index": i, "need_finisher": false, "reason": "need_running_rebound"}

	if _count_regular_type(moveset, MoveResource.MoveType.GROUNDED) < MIN_GROUNDED:
		for i in range(moveset.size()):
			if not moveset[i].is_finisher and moveset[i].move_type != MoveResource.MoveType.GROUNDED:
				return {"index": i, "need_finisher": false, "reason": "need_grounded"}

	if moveset.size() > target_size:
		for i in range(moveset.size() - 1, -1, -1):
			if not moveset[i].is_finisher:
				return {"index": i, "need_finisher": false, "reason": "oversized"}

	if moveset.size() < target_size:
		return {"index": -1, "need_finisher": false, "reason": "undersized"}

	return {}


func _violation_count(
	moveset: Array[MoveResource],
	wrestler: WrestlerResource,
	target_size: int
) -> int:
	var count: int = 0

	var seen_resources: Array[MoveResource] = []
	var seen_names: Array[String] = []

	for move: MoveResource in moveset:
		if move == null:
			count += 1
			continue

		if _contains_resource(seen_resources, move):
			count += 1
		else:
			seen_resources.append(move)

		var n: String = _normalize_name(move.move_name)
		if seen_names.has(n):
			count += 1
		else:
			seen_names.append(n)

	count += abs(_count_finishers(moveset) - FINISHER_COUNT)

	if _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
		count += max(0, MIN_HIGH_FLYER_REGULAR_SPRINGBOARD - _count_regular_type(moveset, MoveResource.MoveType.SPRINGBOARD))
		count += max(0, MIN_HIGH_FLYER_REGULAR_DIVING_STANDING - _count_regular_diving_standing(moveset))
		count += max(0, MIN_HIGH_FLYER_REGULAR_DIVING_GROUNDED - _count_regular_diving_grounded(moveset))
		count += max(0, MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL - _count_regular_aerial(moveset))
	else:
		count += max(0, _count_regular_type(moveset, MoveResource.MoveType.SPRINGBOARD) - MAX_SPRINGBOARD_NON_FLYER)
		count += max(0, _count_regular_diving(moveset) - MAX_DIVING_NON_FLYER)

	if _primary_class(wrestler) == WrestlerResource.WrestlerClass.TECHNICIAN:
		count += max(0, _count_regular_submissions(moveset) - MAX_SUBMISSIONS_TECHNICIAN)
	else:
		count += max(0, _count_regular_submissions(moveset) - MAX_SUBMISSIONS_NON_TECHNICIAN)

	if _primary_class(wrestler) == WrestlerResource.WrestlerClass.STRIKER:
		count += max(0, _count_regular_strikes(moveset) - MAX_STRIKES_STRIKER)
	else:
		count += max(0, _count_regular_strikes(moveset) - MAX_STRIKES_NON_STRIKER)

	count += max(0, MIN_STANDING_FRONT - _count_regular_type(moveset, MoveResource.MoveType.STANDING_FRONT))
	count += max(0, MIN_RUNNING_OR_REBOUND - _count_regular_running_rebound(moveset))
	count += max(0, MIN_GROUNDED - _count_regular_type(moveset, MoveResource.MoveType.GROUNDED))

	count += abs(moveset.size() - target_size)

	return count


func _moveset_meets_hard_rules(
	moveset: Array[MoveResource],
	wrestler: WrestlerResource,
	target_size: int
) -> bool:
	if moveset.size() != target_size:
		return false

	if _count_finishers(moveset) != FINISHER_COUNT:
		return false

	var seen_resources: Array[MoveResource] = []
	var seen_names: Array[String] = []

	for move: MoveResource in moveset:
		if move == null:
			return false

		if _contains_resource(seen_resources, move):
			return false

		seen_resources.append(move)

		var normalized_name: String = _normalize_name(move.move_name)
		if seen_names.has(normalized_name):
			return false

		seen_names.append(normalized_name)

	if _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
		if _count_regular_type(moveset, MoveResource.MoveType.SPRINGBOARD) < MIN_HIGH_FLYER_REGULAR_SPRINGBOARD:
			return false

		if _count_regular_diving_standing(moveset) < MIN_HIGH_FLYER_REGULAR_DIVING_STANDING:
			return false

		if _count_regular_diving_grounded(moveset) < MIN_HIGH_FLYER_REGULAR_DIVING_GROUNDED:
			return false

		if _count_regular_aerial(moveset) < MIN_HIGH_FLYER_REGULAR_AERIAL_TOTAL:
			return false
	else:
		if _count_regular_type(moveset, MoveResource.MoveType.SPRINGBOARD) > MAX_SPRINGBOARD_NON_FLYER:
			return false

		if _count_regular_diving(moveset) > MAX_DIVING_NON_FLYER:
			return false

	if _primary_class(wrestler) == WrestlerResource.WrestlerClass.TECHNICIAN:
		if _count_regular_submissions(moveset) > MAX_SUBMISSIONS_TECHNICIAN:
			return false
	else:
		if _count_regular_submissions(moveset) > MAX_SUBMISSIONS_NON_TECHNICIAN:
			return false

	if _primary_class(wrestler) == WrestlerResource.WrestlerClass.STRIKER:
		if _count_regular_strikes(moveset) > MAX_STRIKES_STRIKER:
			return false
	else:
		if _count_regular_strikes(moveset) > MAX_STRIKES_NON_STRIKER:
			return false

	if _count_regular_type(moveset, MoveResource.MoveType.STANDING_FRONT) < MIN_STANDING_FRONT:
		return false

	if _count_regular_running_rebound(moveset) < MIN_RUNNING_OR_REBOUND:
		return false

	if _count_regular_type(moveset, MoveResource.MoveType.GROUNDED) < MIN_GROUNDED:
		return false

	return true


func _filter_finisher_pool(
	all_moves: Array[MoveResource],
	classes: Array[WrestlerResource.WrestlerClass]
) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue

		if move.is_finisher and _move_matches_any_class(move, classes):
			result.append(move)

	return result


func _filter_archetype_regular_pool(
	all_moves: Array[MoveResource],
	classes: Array[WrestlerResource.WrestlerClass]
) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue

		if not move.is_finisher and _move_matches_any_class(move, classes):
			result.append(move)

	return result


func _filter_general_regular_pool(all_moves: Array[MoveResource]) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue

		if not move.is_finisher and move.class_preferrence.is_empty():
			result.append(move)

	return result


func _filter_striker_regular_strike_pool(all_moves: Array[MoveResource]) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue
		if move.is_finisher:
			continue
		if not move.is_strike:
			continue
		if move.class_preferrence.has(WrestlerResource.WrestlerClass.STRIKER):
			result.append(move)

	return result


func _filter_striker_regular_non_strike_style_pool(all_moves: Array[MoveResource]) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue
		if move.is_finisher:
			continue
		if move.is_strike:
			continue
		if move.class_preferrence.has(WrestlerResource.WrestlerClass.STRIKER):
			result.append(move)

	return result


func _filter_general_regular_non_strike_pool(all_moves: Array[MoveResource]) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue
		if move.is_finisher:
			continue
		if move.is_strike:
			continue
		if move.class_preferrence.is_empty():
			result.append(move)

	return result


func _filter_support_regular_non_strike_pool(
	all_moves: Array[MoveResource],
	wrestler_classes: Array[WrestlerResource.WrestlerClass]
) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue
		if move.is_finisher:
			continue
		if move.is_strike:
			continue

		if move.class_preferrence.is_empty() or _move_matches_any_class(move, wrestler_classes):
			result.append(move)

	return result


func _build_fallback_pool(
	all_moves: Array[MoveResource],
	wrestler: WrestlerResource,
	current_moveset: Array[MoveResource],
	require_finisher: bool
) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue

		if require_finisher != move.is_finisher:
			continue

		if _contains_resource(current_moveset, move):
			continue

		if _contains_move_name(current_moveset, move.move_name):
			continue

		if require_finisher:
			if not _move_matches_any_class(move, wrestler.wrestler_class):
				continue
		else:
			if not (_move_matches_any_class(move, wrestler.wrestler_class) or move.class_preferrence.is_empty()):
				continue

		if _move_is_legal_addition(move, current_moveset, [], wrestler):
			result.append(move)

	return _dedupe_resources(result)


func _build_replacement_pool(
	all_moves: Array[MoveResource],
	wrestler: WrestlerResource,
	current_moveset: Array[MoveResource],
	require_finisher: bool,
	reason: String
) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in all_moves:
		if move == null:
			continue

		if move.is_finisher != require_finisher:
			continue

		if _contains_resource(current_moveset, move):
			continue

		if _contains_move_name(current_moveset, move.move_name):
			continue

		if require_finisher:
			if not _move_matches_any_class(move, wrestler.wrestler_class):
				continue
		else:
			if not (_move_matches_any_class(move, wrestler.wrestler_class) or move.class_preferrence.is_empty()):
				continue

		match reason:
			"need_springboard":
				if move.move_type != MoveResource.MoveType.SPRINGBOARD:
					continue

			"need_diving_standing":
				if move.move_type != MoveResource.MoveType.DIVING_STANDING:
					continue

			"need_diving_grounded":
				if move.move_type != MoveResource.MoveType.DIVING_GROUNDED:
					continue

			"need_aerial":
				if not (
					move.move_type == MoveResource.MoveType.SPRINGBOARD
					or move.move_type == MoveResource.MoveType.DIVING_STANDING
					or move.move_type == MoveResource.MoveType.DIVING_GROUNDED
				):
					continue

			"need_standing_front":
				if move.move_type != MoveResource.MoveType.STANDING_FRONT:
					continue

			"need_running_rebound":
				if not (
					move.move_type == MoveResource.MoveType.RUNNING
					or move.move_type == MoveResource.MoveType.ROPE_REBOUND
				):
					continue

			"need_grounded":
				if move.move_type != MoveResource.MoveType.GROUNDED:
					continue

			_:
				pass

		if _move_is_legal_addition(move, current_moveset, [], wrestler):
			result.append(move)

	return _dedupe_resources(result)


func _pick_one_weighted(
	pool: Array[MoveResource],
	wrestler: WrestlerResource,
	rng: RandomNumberGenerator
) -> MoveResource:
	if pool.is_empty():
		return null

	var total_weight: float = 0.0
	var weights: Array[float] = []

	for move: MoveResource in pool:
		var w: float = _move_weight(move, wrestler)
		weights.append(w)
		total_weight += w

	if total_weight <= 0.0:
		return pool[rng.randi_range(0, pool.size() - 1)]

	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0

	for i in range(pool.size()):
		cumulative += weights[i]

		if roll <= cumulative:
			return pool[i]

	return pool[pool.size() - 1]


func _move_weight(move: MoveResource, wrestler: WrestlerResource) -> float:
	var primary_class: WrestlerResource.WrestlerClass = _primary_class(wrestler)
	var weight: float = 1.0

	weight += float(move.move_impact) * 0.10

	if move.class_preferrence.has(primary_class):
		weight += 1.25

	if move.class_preferrence.is_empty():
		weight += 0.35

	match primary_class:
		WrestlerResource.WrestlerClass.HIGH_FLYER:
			if move.move_type == MoveResource.MoveType.SPRINGBOARD:
				weight += 2.0
			elif move.move_type == MoveResource.MoveType.DIVING_STANDING:
				weight += 2.0
			elif move.move_type == MoveResource.MoveType.DIVING_GROUNDED:
				weight += 2.0
			elif move.move_type == MoveResource.MoveType.ROPE_REBOUND:
				weight += 1.0

		WrestlerResource.WrestlerClass.POWERHOUSE:
			if move.move_type == MoveResource.MoveType.STANDING_FRONT:
				weight += 1.0

			if move.move_impact >= 7:
				weight += 1.0

		WrestlerResource.WrestlerClass.TECHNICIAN:
			if move.is_submission:
				weight += 1.25

			if move.move_type == MoveResource.MoveType.GROUNDED:
				weight += 0.75

			if move.move_target_parts.size() > 0:
				weight += 0.20

		WrestlerResource.WrestlerClass.STRIKER:
			if move.is_strike:
				weight += 0.65

				if move.strike_weight == MoveResource.StrikeWeight.STRIKE_HEAVY:
					weight += 0.25
			else:
				if move.class_preferrence.has(WrestlerResource.WrestlerClass.STRIKER):
					weight += 1.10

				if move.move_type == MoveResource.MoveType.STANDING_FRONT:
					weight += 0.35
				elif move.move_type == MoveResource.MoveType.STANDING_BEHIND:
					weight += 0.30
				elif move.move_type == MoveResource.MoveType.GROUNDED:
					weight += 0.40
				elif move.move_type == MoveResource.MoveType.RUNNING:
					weight += 0.35
				elif move.move_type == MoveResource.MoveType.ROPE_REBOUND:
					weight += 0.35

		WrestlerResource.WrestlerClass.HARDCORE:
			if move.move_impact >= 6:
				weight += 0.75

			if move.is_strike:
				weight += 0.25

			if move.move_type == MoveResource.MoveType.GROUNDED:
				weight += 0.25

	if _has_class(wrestler, WrestlerResource.WrestlerClass.HIGH_FLYER):
		if primary_class != WrestlerResource.WrestlerClass.HIGH_FLYER:
			if move.move_type == MoveResource.MoveType.SPRINGBOARD:
				weight += 1.25
			elif move.move_type == MoveResource.MoveType.DIVING_STANDING:
				weight += 1.25
			elif move.move_type == MoveResource.MoveType.DIVING_GROUNDED:
				weight += 1.25

	return max(weight, 0.1)


func _move_matches_any_class(
	move: MoveResource,
	classes: Array[WrestlerResource.WrestlerClass]
) -> bool:
	for c: WrestlerResource.WrestlerClass in classes:
		if move.class_preferrence.has(c):
			return true

	return false


func _has_class(
	wrestler: WrestlerResource,
	wrestler_class: WrestlerResource.WrestlerClass
) -> bool:
	return wrestler.wrestler_class.has(wrestler_class)


func _primary_class(wrestler: WrestlerResource) -> WrestlerResource.WrestlerClass:
	if wrestler.wrestler_class.is_empty():
		return WrestlerResource.WrestlerClass.HIGH_FLYER

	return wrestler.wrestler_class[0]


func _count_finishers(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			count += 1

	return count


func _count_regular_type(
	moveset: Array[MoveResource],
	move_type: MoveResource.MoveType
) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.move_type == move_type:
			count += 1

	return count


func _count_regular_diving(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.move_type == MoveResource.MoveType.DIVING_STANDING or move.move_type == MoveResource.MoveType.DIVING_GROUNDED:
			count += 1

	return count


func _count_regular_diving_standing(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.move_type == MoveResource.MoveType.DIVING_STANDING:
			count += 1

	return count


func _count_regular_diving_grounded(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.move_type == MoveResource.MoveType.DIVING_GROUNDED:
			count += 1

	return count


func _count_regular_aerial(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.move_type == MoveResource.MoveType.SPRINGBOARD:
			count += 1
		elif move.move_type == MoveResource.MoveType.DIVING_STANDING:
			count += 1
		elif move.move_type == MoveResource.MoveType.DIVING_GROUNDED:
			count += 1

	return count


func _count_regular_submissions(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.is_submission:
			count += 1

	return count


func _count_regular_strikes(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.is_strike:
			count += 1

	return count


func _count_regular_running_rebound(moveset: Array[MoveResource]) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.move_type == MoveResource.MoveType.RUNNING or move.move_type == MoveResource.MoveType.ROPE_REBOUND:
			count += 1

	return count


func _count_regular_class_style_moves(
	moveset: Array[MoveResource],
	wrestler_class: WrestlerResource.WrestlerClass
) -> int:
	var count: int = 0

	for move: MoveResource in moveset:
		if move == null:
			continue

		if move.is_finisher:
			continue

		if move.class_preferrence.has(wrestler_class):
			count += 1

	return count


func _dedupe_by_name_and_resource(arr: Array[MoveResource]) -> Array[MoveResource]:
	var result: Array[MoveResource] = []
	var seen_names: Array[String] = []

	for move: MoveResource in arr:
		if move == null:
			continue

		if _contains_resource(result, move):
			continue

		var normalized_name: String = _normalize_name(move.move_name)

		if seen_names.has(normalized_name):
			continue

		result.append(move)
		seen_names.append(normalized_name)

	return result


func _dedupe_resources(arr: Array[MoveResource]) -> Array[MoveResource]:
	var result: Array[MoveResource] = []

	for move: MoveResource in arr:
		if move == null:
			continue

		if not _contains_resource(result, move):
			result.append(move)

	return result


func _contains_resource(arr: Array[MoveResource], target: MoveResource) -> bool:
	for item: MoveResource in arr:
		if item == target:
			return true

	return false


func _contains_move_name(arr: Array[MoveResource], move_name: String) -> bool:
	var normalized_name: String = _normalize_name(move_name)

	for item: MoveResource in arr:
		if item == null:
			continue

		if _normalize_name(item.move_name) == normalized_name:
			return true

	return false


func _normalize_name(move_name: String) -> String:
	return move_name.strip_edges().to_lower()


func _remove_resource_once(
	arr: Array[MoveResource],
	target: MoveResource
) -> Array[MoveResource]:
	var result: Array[MoveResource] = []
	var removed: bool = false

	for item: MoveResource in arr:
		if not removed and item == target:
			removed = true
			continue

		result.append(item)

	return result


func _display_name(wrestler: WrestlerResource) -> String:
	if not wrestler.gimmick_name.strip_edges().is_empty():
		return wrestler.gimmick_name

	if not wrestler.wrestler_name.strip_edges().is_empty():
		return wrestler.wrestler_name

	return "[Unnamed Wrestler]"


func _load_all_moves(root_folder: String) -> Array[MoveResource]:
	var result: Array[MoveResource] = []
	var move_paths: Array[String] = []

	_collect_move_paths(root_folder, move_paths)

	for path: String in move_paths:
		var res: Resource = load(path)

		if res is MoveResource:
			result.append(res as MoveResource)

	return result


func _collect_move_paths(dir_path: String, results: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)

	if dir == null:
		push_warning("Could not open move directory: %s" % dir_path)
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
			var res: Resource = load(full_path)

			if res is MoveResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()


func _collect_wrestler_paths(dir_path: String, results: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)

	if dir == null:
		push_warning("Could not open wrestler directory: %s" % dir_path)
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
			var res: Resource = load(full_path)

			if res is WrestlerResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()
