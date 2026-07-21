extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_test_exhaustion_math()
	_test_cost_and_recovery_curves()
	_test_defence_curves()
	_test_demand_and_pin_equivalence()
	_test_authored_stamina_capacity()
	_test_ai_catch_breath_choice()
	_test_every_move_execution_profile()
	_test_late_match_reversal_separation()
	_test_submission_force_rate_normalization()
	_test_submission_healthy_target_protection()
	_test_submission_commentary_deduplication()
	if _failures.is_empty():
		print("EXHAUSTION_REGRESSION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error("EXHAUSTION_REGRESSION: %s" % failure)
	quit(1)


func _test_exhaustion_math() -> void:
	var state := _state(100.0, 0.0)
	_expect_close(MatchExhaustionModel.combined_exhaustion(state), 0.0, "fresh combined exhaustion")
	_expect_equal(MatchExhaustionModel.exhaustion_band_label(state), "Fresh", "fresh band")
	_expect_close(MatchExhaustionModel.execution_penalty(state, MatchExhaustionModel.Demand.EXPLOSIVE), 0.0, "fresh execution penalty")

	state = _state(0.0, 0.0)
	_expect_close(MatchExhaustionModel.combined_exhaustion(state), 0.65, "zero-stamina low-fatigue combined")
	_expect_close(MatchExhaustionModel.execution_penalty(state, MatchExhaustionModel.Demand.BASIC), 10.0, "basic zero-stamina penalty")
	_expect_close(MatchExhaustionModel.execution_penalty(state, MatchExhaustionModel.Demand.STANDARD), 15.0, "standard zero-stamina penalty")
	_expect_close(MatchExhaustionModel.execution_penalty(state, MatchExhaustionModel.Demand.EXPLOSIVE), 25.0, "explosive zero-stamina penalty")

	state = _state(0.0, 100.0)
	_expect_close(MatchExhaustionModel.combined_exhaustion(state), 1.0, "spent combined exhaustion")
	_expect_equal(MatchExhaustionModel.exhaustion_band_label(state), "Spent", "spent band")
	_expect_close(MatchExhaustionModel.execution_penalty(state, MatchExhaustionModel.Demand.EXPLOSIVE), 35.0, "explosive penalty cap")


func _test_cost_and_recovery_curves() -> void:
	for sample in [
		[0.0, 1.0],
		[50.0, 0.75],
		[75.0, 0.50],
		[90.0, 0.25],
		[100.0, 0.10],
	]:
		var state := _state(100.0, float(sample[0]))
		_expect_close(
			MatchExhaustionModel.stamina_recovery_multiplier(state),
			float(sample[1]),
			"recovery multiplier at fatigue %.0f" % float(sample[0]),
		)
	var spent := _state(0.0, 100.0)
	_expect_close(
		MatchExhaustionModel.stamina_cost_multiplier(spent, MatchExhaustionModel.Demand.EXPLOSIVE),
		1.725,
		"spent explosive cost multiplier",
	)
	_expect_close(MatchExhaustionModel.recovery_delay_chance(spent), 25.0, "spent recovery delay")
	_expect_close(MatchExhaustionModel.recovery_delay_chance(spent, true), 35.0, "post-crash recovery delay cap")


func _test_defence_curves() -> void:
	var fresh := _state(100.0, 0.0)
	_expect_close(MatchExhaustionModel.reversal_penalty(fresh), 0.0, "fresh reversal penalty")
	_expect_close(MatchExhaustionModel.kickout_penalty(fresh), 0.0, "fresh kickout penalty")
	_expect_close(MatchExhaustionModel.submission_escape_penalty(fresh), 0.0, "fresh submission penalty")
	var spent := _state(0.0, 100.0)
	_expect_close(MatchExhaustionModel.reversal_penalty(spent), 20.0, "spent reversal cap")
	_expect_close(MatchExhaustionModel.kickout_penalty(spent), 32.0, "spent kickout cap")
	_expect_close(MatchExhaustionModel.submission_escape_penalty(spent), 35.0, "spent submission cap")
	_expect_close(
		MatchExhaustionModel.control_retention_chance(spent, MatchExhaustionModel.Demand.EXPLOSIVE),
		60.0,
		"spent explosive retention floor",
	)


func _test_demand_and_pin_equivalence() -> void:
	var basic := MoveResource.new()
	basic.move_type = MoveResource.MoveType.STRIKE
	basic.move_impact = 3
	_expect_equal(MatchExhaustionModel.move_demand(basic), MatchExhaustionModel.Demand.BASIC, "basic strike demand")
	var aerial := MoveResource.new()
	aerial.move_type = MoveResource.MoveType.AERIAL
	aerial.move_impact = 5
	_expect_equal(MatchExhaustionModel.move_demand(aerial), MatchExhaustionModel.Demand.EXPLOSIVE, "aerial demand")
	var defender := _state(0.0, 100.0)
	var pin := MatchInteractionModel.build_pin_profile(28.0, 1.8, 50.0, 50.0, 1, defender)
	_expect_equal(
		float(pin.get("ai_success_chance", 0.0)) > float(pin.get("success_window", 0.0)),
		true,
		"AI kickout uses unshrunk pressure probability",
	)
	_expect_close(float(pin.get("exhaustion_penalty", 0.0)), 32.0, "pin exhaustion diagnostic")
	var fresh_defender := _state(90.0, 9.0)
	var early_one := MatchInteractionModel.build_pin_profile(28.0, 1.8, 42.0, 153.0, 1, fresh_defender)
	var early_two := MatchInteractionModel.build_pin_profile(18.0, 1.4, 42.0, 128.0, 2, fresh_defender)
	var early_three := MatchInteractionModel.build_pin_profile(9.0, 1.1, 42.0, 103.0, 3, fresh_defender)
	var early_pinfall_probability := (
		(1.0 - float(early_one.get("ai_success_chance", 0.0)) / 100.0)
		* (1.0 - float(early_two.get("ai_success_chance", 0.0)) / 100.0)
		* (1.0 - float(early_three.get("ai_success_chance", 0.0)) / 100.0)
	)
	_expect_equal(early_pinfall_probability < 0.05, true, "fresh ordinary 04:10 AI pinfall stays below five percent")


func _test_authored_stamina_capacity() -> void:
	var wrestler := WrestlerResource.new()
	wrestler.wrestler_name = "Capacity Test"
	wrestler.stamina = 65.0
	var state := MatchSideState.new()
	state.initialize(wrestler)
	var expected_capacity := ceilf(65.0 * MatchSideState.STAMINA_POOL_MULTIPLIER)
	_expect_close(state.max_stamina, expected_capacity, "authored stamina scales into runtime capacity")
	_expect_close(state.stamina, expected_capacity, "match starts at full scaled stamina capacity")
	_expect_close(state.stamina_percent(), 100.0, "authored stamina starts full")
	state.spend_stamina(20.0)
	_expect_close(
		state.stamina_percent(),
		(expected_capacity - 20.0) / expected_capacity * 100.0,
		"condition uses scaled relative stamina",
	)
	var expected_recovery := expected_capacity * MatchExhaustionModel.CATCH_BREATH_BASE_RECOVERY / 100.0
	_expect_close(
		MatchExhaustionModel.catch_breath_recovery(state),
		expected_recovery,
		"Catch Breath scales with authored capacity",
	)
	state.recover_stamina(100.0)
	_expect_close(state.stamina, expected_capacity, "recovery respects scaled stamina maximum")


func _test_ai_catch_breath_choice() -> void:
	var ai_wrestler := WrestlerResource.new()
	ai_wrestler.wrestler_name = "AI Breath Test"
	ai_wrestler.stamina = 70.0
	var target_wrestler := WrestlerResource.new()
	target_wrestler.wrestler_name = "Target"
	target_wrestler.stamina = 70.0
	var ai_state := MatchSideState.new()
	ai_state.initialize(ai_wrestler)
	ai_state.stamina = 10.0
	var target_state := MatchSideState.new()
	target_state.initialize(target_wrestler)
	var available_actions := MatchSetupStateRules.get_candidate_actions(ai_state, target_state)
	_expect_equal(
		MatchSetupStateRules.CATCH_BREATH in available_actions,
		true,
		"Catch Breath is available to an exhausted AI",
	)
	var engine := MatchAIDecisionEngine.new()
	engine.set_seed(20260719)
	var decision := engine.choose_action(
		ai_state,
		target_state,
		[],
		[MatchSetupStateRules.CATCH_BREATH],
		600,
	)
	_expect_equal(decision.get("kind", &""), MatchAIDecisionEngine.KIND_SETUP, "AI selects a setup action")
	_expect_equal(
		decision.get("setup_action", &""),
		MatchSetupStateRules.CATCH_BREATH,
		"AI can select Catch Breath",
	)


func _test_every_move_execution_profile() -> void:
	var wrestler := WrestlerResource.new()
	wrestler.wrestler_name = "Execution Test"
	wrestler.stamina = 70.0
	wrestler.skill = 70.0
	wrestler.striking = 70.0
	var state := MatchSideState.new()
	state.initialize(wrestler)
	var basic := MoveResource.new()
	basic.move_name = "Basic Test Strike"
	basic.move_type = MoveResource.MoveType.STRIKE
	basic.is_strike = true
	basic.move_impact = 3
	var basic_profile := MatchInteractionModel.build_execution_profile(
		state,
		basic,
		MatchInteractionModel.get_interaction_type_for_move(basic),
	)
	_expect_close(
		float(basic_profile.get("success_window", -1.0)),
		float(basic_profile.get("ai_success_chance", -2.0)),
		"calculated execution profile remains available for AI scoring",
	)
	_expect_close(float(basic_profile.get("gold_zone_scale", 0.0)), 1.0 / 7.0, "execution target one-seventh scale")
	_expect_equal(
		float(basic_profile.get("success_window", 0.0)) * float(basic_profile.get("gold_zone_scale", 1.0))
		< float(basic_profile.get("ai_success_chance", 0.0)),
		true,
		"player execution target is narrower than calculated chance",
	)
	_expect_equal(bool(basic_profile.get("one_way", false)), true, "execution meter is one-shot")
	var table_move := MoveResource.new()
	table_move.move_name = "Table Follow-up"
	table_move.move_type = MoveResource.MoveType.GRAPPLE
	table_move.move_impact = 6
	_expect_equal(
		MatchExhaustionModel.effective_move_demand(table_move, false, false, true),
		MatchExhaustionModel.Demand.EXPLOSIVE,
		"environmental follow-up demand",
	)
	state.stamina = 0.0
	state.fatigue = 100.0
	var spent_profile := MatchInteractionModel.build_execution_profile(
		state,
		basic,
		MatchInteractionModel.get_interaction_type_for_move(basic),
	)
	_expect_equal(
		float(spent_profile.get("ai_success_chance", 100.0)) < float(basic_profile.get("ai_success_chance", 0.0)),
		true,
		"spent execution is harder than fresh execution",
	)


func _test_late_match_reversal_separation() -> void:
	var attacker_wrestler := WrestlerResource.new()
	attacker_wrestler.wrestler_name = "Attacker"
	attacker_wrestler.stamina = 70.0
	var defender_wrestler := WrestlerResource.new()
	defender_wrestler.wrestler_name = "Defender"
	defender_wrestler.stamina = 70.0
	var attacker := MatchSideState.new()
	attacker.initialize(attacker_wrestler)
	var defender := MatchSideState.new()
	defender.initialize(defender_wrestler)
	var move := MoveResource.new()
	move.move_name = "Reversal Test"
	move.move_type = MoveResource.MoveType.GRAPPLE
	move.move_impact = 5
	var early := MatchInteractionModel.reversal_success_chance(attacker, defender, move, &"", 899)
	var late := MatchInteractionModel.reversal_success_chance(attacker, defender, move, &"", 2100)
	_expect_close(late, early, "late recovery penalty does not leak into reversals")


func _test_submission_force_rate_normalization() -> void:
	_expect_close(
		SubmissionTugInteraction.AI_FORCE_RATE_NORMALIZER,
		1.6,
		"AI submission force is normalized from five pulses to eight player inputs",
	)


func _test_submission_healthy_target_protection() -> void:
	var attacker := _state(100.0, 0.0)
	var defender := _state(100.0, 0.0)
	var move := MoveResource.new()
	move.move_name = "Healthy Target Test"
	move.move_type = MoveResource.MoveType.SUBMISSION
	move.is_submission = true
	move.move_target_parts = [MoveResource.MoveTargetParts.BODY as MoveResource.MoveTargetParts]
	for sample in [
		[299, 70.0, 98.0],
		[300, 53.0, 95.0],
		[600, 35.0, 92.0],
		[900, 35.0, 91.0],
		[1500, 35.0, 87.0],
		[2100, 35.0, 84.0],
	]:
		var healthy := MatchInteractionModel.build_submission_context(attacker, defender, move, int(sample[0]), false)
		_expect_close(
			float(healthy.get("resistance_bonus", 0.0)),
			float(sample[1]),
			"healthy resistance at %d seconds" % int(sample[0]),
		)
		_expect_close(
			float(healthy.get("tap_out_threshold", 0.0)),
			float(sample[2]),
			"healthy threshold at %d seconds" % int(sample[0]),
		)

	defender.body_hp = 80.0
	var boundary := MatchInteractionModel.build_submission_context(attacker, defender, move, 700, false)
	_expect_close(float(boundary.get("resistance_bonus", 0.0)), 35.0, "80 HP receives healthy resistance")
	_expect_close(float(boundary.get("tap_out_threshold", 0.0)), 92.0, "80 HP receives healthy threshold")

	defender.body_hp = 79.0
	var below_boundary := MatchInteractionModel.build_submission_context(attacker, defender, move, 700, false)
	_expect_close(float(below_boundary.get("resistance_bonus", 0.0)), 15.0, "79 HP keeps existing resistance")
	_expect_close(float(below_boundary.get("tap_out_threshold", 0.0)), 90.0, "79 HP keeps existing threshold")

	defender.body_hp = 100.0
	move.is_finisher = true
	var finisher := MatchInteractionModel.build_submission_context(attacker, defender, move, 700, false)
	_expect_close(float(finisher.get("resistance_bonus", 0.0)), 30.0, "finisher keeps existing healthy resistance")
	_expect_close(float(finisher.get("tap_out_threshold", 0.0)), 90.0, "finisher excludes healthy threshold modifier")


func _test_submission_commentary_deduplication() -> void:
	var state := MatchSideState.new()
	state.begin_submission_tracking(88.0)
	_expect_equal(state.note_submission_commentary_state(&"attacker_gaining"), true, "first submission state is accepted")
	_expect_equal(state.note_submission_commentary_state(&"attacker_gaining"), false, "duplicate submission state is rejected")
	_expect_equal(state.note_submission_commentary_state(&"near_escape"), true, "different submission state is accepted")
	state.begin_submission_tracking(72.0)
	_expect_equal(state.note_submission_commentary_state(&"attacker_gaining"), true, "new submission resets commentary states")
	_expect_close(state.last_submission_target_hp_at_lock_in, 72.0, "new submission records lock-in HP")
	_expect_close(state.last_submission_target_hp_at_resolution, -1.0, "new submission clears prior resolution HP")


func _state(stamina: float, fatigue: float) -> MatchSideState:
	var state := MatchSideState.new()
	state.stamina = stamina
	state.fatigue = fatigue
	return state


func _expect_close(actual: float, expected: float, label: String, tolerance: float = 0.001) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s: expected %.4f, got %.4f" % [label, expected, actual])


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
