extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var normal := MatchRules.from_dictionary({})
	_check(normal.disqualifications_enabled, "Normal rules should enable DQ.")
	_check(normal.count_outs_enabled, "Normal rules should enable count-outs.")
	_check(normal.count_out_limit == 10, "Normal count limit should be ten.")
	_check(normal.action_clock_seconds == 20, "Normal action clock step should default to twenty seconds.")
	_check(normal.stipulation == MatchRules.Stipulation.STANDARD, "Normal rules should use the standard stipulation.")
	for clock_step in MatchRules.ACTION_CLOCK_OPTIONS:
		var clock_rules := MatchRules.from_dictionary({"action_clock_seconds": clock_step})
		_check(
			clock_rules.action_clock_seconds == clock_step,
			"Action clock step %d should survive dictionary conversion." % clock_step,
		)
	var invalid_clock := MatchRules.from_dictionary({"action_clock_seconds": 17})
	_check(invalid_clock.action_clock_seconds == 20, "Unsupported clock steps should fall back to twenty seconds.")
	var no_dq := MatchRules.from_dictionary({"disqualifications_enabled": false})
	var table_scaffold := MatchRules.from_dictionary({"stipulation": MatchRules.Stipulation.TABLES})
	_check(table_scaffold.stipulation == MatchRules.Stipulation.TABLES, "Tables scaffold should survive dictionary conversion.")
	_check(table_scaffold.to_dictionary().get("stipulation") == MatchRules.Stipulation.TABLES, "Tables scaffold should serialize.")
	var ladder_scaffold := MatchRules.from_dictionary({"stipulation": MatchRules.Stipulation.LADDER})
	_check(ladder_scaffold.stipulation == MatchRules.Stipulation.LADDER, "Ladder scaffold should survive dictionary conversion.")
	var chair := load("res://Weapons/steel_chair.tres") as WeaponResource
	_check(chair != null, "Steel chair resource should load.")
	_check(not no_dq.weapon_attack_causes_disqualification(chair), "Chair should be legal in no-DQ rules.")
	_check(normal.weapon_attack_causes_disqualification(chair), "Chair should cause DQ under normal rules.")
	_check(normal.is_outside_area(WrestlerResource.Area.APRON), "Apron should count as outside.")
	_check(not normal.is_outside_area(WrestlerResource.Area.ROPES), "Ropes should count as inside.")

	_check(chair.minimum_durability == 1, "Steel chair minimum durability should be one committed swing.")
	_check(chair.maximum_durability == 4, "Steel chair maximum durability should be four committed swings.")
	var custom := MatchRules.from_dictionary({
		"disqualifications_enabled": false,
		"count_outs_enabled": false,
		"count_out_limit": 7,
		"action_clock_seconds": 20,
	})
	_check(not custom.disqualifications_enabled, "No-DQ configuration should survive dictionary conversion.")
	_check(not custom.count_outs_enabled, "No-count-out configuration should survive dictionary conversion.")
	_check(custom.count_out_limit == 7, "Custom count limit should survive dictionary conversion.")
	_check(custom.action_clock_seconds == 20, "Custom action clock step should survive dictionary conversion.")

	if _failures.is_empty():
		print("MATCH_RULES_REGRESSION: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("MATCH_RULES_REGRESSION: %s" % failure)
	quit(1)
