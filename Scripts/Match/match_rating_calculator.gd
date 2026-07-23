extends RefCounted
class_name MatchRatingCalculator


static func calculate(report: Dictionary, story_events: Array = []) -> Dictionary:
	var player: Dictionary = report.get("player", {})
	var ai: Dictionary = report.get("ai", {})
	var player_damage := maxf(0.0, float(player.get("damage_dealt", 0.0)))
	var ai_damage := maxf(0.0, float(ai.get("damage_dealt", 0.0)))
	var player_landed := maxi(0, int(player.get("moves_landed", 0)))
	var ai_landed := maxi(0, int(ai.get("moves_landed", 0)))
	var total_landed := player_landed + ai_landed

	var damage_balance := _balance(player_damage, ai_damage)
	var offence_balance := _balance(float(player_landed), float(ai_landed))
	var control_swings := _event_count(story_events, &"control_swing")
	if control_swings == 0:
		control_swings = int(player.get("reversals", 0)) + int(ai.get("reversals", 0))
	var competitiveness := (
		damage_balance * 10.0
		+ offence_balance * 7.0
		+ minf(float(control_swings), 5.0)
	)

	var reversals := int(player.get("reversals", 0)) + int(ai.get("reversals", 0))
	var late_near_falls := _event_count(story_events, &"near_fall_late")
	var near_falls := late_near_falls + _event_count(story_events, &"near_fall")
	if near_falls == 0:
		near_falls = maxi(0, int(player.get("kickouts", 0)) + int(ai.get("kickouts", 0)) - 1)
	var submission_escapes := int(player.get("submission_escapes", 0)) + int(ai.get("submission_escapes", 0))
	var submission_seconds := float(player.get("submission_struggle_seconds", 0.0)) + float(ai.get("submission_struggle_seconds", 0.0))
	var drama := minf(6.0, float(reversals) * 0.75)
	drama += minf(9.0, float(near_falls) * 2.0 + float(late_near_falls) * 1.5)
	drama += minf(7.0, float(submission_escapes) * 2.0 + submission_seconds / 8.0)

	var signatures := int(player.get("signatures_landed", 0)) + int(ai.get("signatures_landed", 0))
	var finisher_attempts := int(player.get("finisher_attempts", 0)) + int(ai.get("finisher_attempts", 0))
	var finishers := int(player.get("finishers_landed", 0)) + int(ai.get("finishers_landed", 0))
	var big_moments := (
		int(player.get("high_risk_crashes", 0))
		+ int(ai.get("high_risk_crashes", 0))
		+ int(player.get("table_spots_landed", 0))
		+ int(ai.get("table_spots_landed", 0))
		+ int(player.get("ladder_dives", 0))
		+ int(ai.get("ladder_dives", 0))
	)
	var weapon_moments := int(player.get("weapon_attacks_landed", 0)) + int(ai.get("weapon_attacks_landed", 0))
	var blood_moments := int(player.get("bleeding_caused", 0)) + int(ai.get("bleeding_caused", 0))
	var escalation := minf(5.0, float(signatures) * 2.0)
	escalation += minf(8.0, float(finisher_attempts) * 1.0 + float(finishers) * 2.0)
	escalation += minf(4.0, float(big_moments) * 1.25)
	escalation += minf(3.0, float(weapon_moments) * 0.5 + float(blood_moments) * 1.5)

	var player_variety := maxi(0, int(player.get("move_variety", 0)))
	var ai_variety := maxi(0, int(ai.get("move_variety", 0)))
	var total_variety := player_variety + ai_variety
	var variety_ratio := float(total_variety) / float(maxi(1, total_landed))
	var both_sides_bonus := 3.0 * offence_balance
	var variety := clampf(variety_ratio * 11.0 + both_sides_bonus, 0.0, 14.0)

	var setup_actions := (
		int(player.get("setup_actions", 0))
		+ int(ai.get("setup_actions", 0))
		+ int(player.get("neutral_resets", 0))
		+ int(ai.get("neutral_resets", 0))
	)
	var productive_ratio := float(total_landed) / float(maxi(1, total_landed + setup_actions))
	var duration_seconds := maxi(1, int(report.get("duration_seconds", _parse_time(str(report.get("final_time", "00:00"))))))
	var action_density := float(total_landed + reversals + near_falls + signatures + finishers) / maxf(1.0, float(duration_seconds) / 60.0)
	var pacing := clampf(productive_ratio * 9.0 + minf(5.0, action_density * 0.7), 0.0, 14.0)

	var result := str(report.get("result", ""))
	var finish_move := str(report.get("finish_move", "None"))
	var finish_payoff := 2.0
	if result in ["Pinfall", "Submission", "Table Break", "Ladder Retrieval"]:
		finish_payoff += 2.0
	if finish_move != "None" and not finish_move.is_empty():
		finish_payoff += 1.0
	if finishers > 0 or signatures > 0:
		finish_payoff += 2.0
	if near_falls > 0 or submission_seconds >= 6.0:
		finish_payoff += 1.0
	finish_payoff = minf(8.0, finish_payoff)

	var repetition_penalty := minf(
		8.0,
		float(int(player.get("repetition_penalties", 0)) + int(ai.get("repetition_penalties", 0))) * 0.75,
	)
	var loop_penalty := minf(
		8.0,
		float(
			int(player.get("setup_loop_penalties", 0))
			+ int(ai.get("setup_loop_penalties", 0))
			+ int(player.get("forced_fallbacks", 0))
			+ int(ai.get("forced_fallbacks", 0))
		) * 1.25,
	)
	var inactivity_penalty := 0.0
	if duration_seconds >= 1800 and action_density < 1.25:
		inactivity_penalty = minf(6.0, (1.25 - action_density) * 8.0)
	var penalties := repetition_penalty + loop_penalty + inactivity_penalty

	var raw_score := clampf(
		competitiveness + drama + escalation + variety + pacing + finish_payoff - penalties,
		0.0,
		100.0,
	)
	var stars := clampf(roundf(raw_score / 5.0) * 0.25, 0.0, 5.0)
	var components := {
		"competitiveness": snappedf(competitiveness, 0.01),
		"drama": snappedf(drama, 0.01),
		"escalation": snappedf(escalation, 0.01),
		"variety": snappedf(variety, 0.01),
		"pacing": snappedf(pacing, 0.01),
		"finish_payoff": snappedf(finish_payoff, 0.01),
		"penalties": snappedf(penalties, 0.01),
	}
	return {
		"score": snappedf(raw_score, 0.01),
		"stars": stars,
		"highlights": _build_highlights(components, damage_balance, near_falls, signatures, finishers, penalties),
		"components": components,
	}


static func format_stars(stars: float) -> String:
	var clamped := clampf(stars, 0.0, 5.0)
	var full_stars := floori(clamped)
	var remainder := clamped - float(full_stars)
	var glyphs := ""
	for index in 5:
		glyphs += "★" if index < full_stars else "☆"
	var fraction := ""
	if is_equal_approx(remainder, 0.25):
		fraction = " ¼"
	elif is_equal_approx(remainder, 0.5):
		fraction = " ½"
	elif is_equal_approx(remainder, 0.75):
		fraction = " ¾"
	return "%s%s  %.2f" % [glyphs, fraction, clamped]


static func _balance(left: float, right: float) -> float:
	var largest := maxf(left, right)
	if largest <= 0.0:
		return 0.0
	return minf(left, right) / largest


static func _event_count(events: Array, event_type: StringName) -> int:
	var count := 0
	for raw_event in events:
		if raw_event is Dictionary and StringName(str(raw_event.get("type", ""))) == event_type:
			count += 1
	return count


static func _parse_time(value: String) -> int:
	var parts := value.split(":")
	if parts.size() != 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])


static func _build_highlights(
	components: Dictionary,
	damage_balance: float,
	near_falls: int,
	signatures: int,
	finishers: int,
	penalties: float,
) -> Array[String]:
	var highlights: Array[String] = []
	if near_falls >= 2:
		highlights.append("Dramatic late near falls")
	if float(components.get("drama", 0.0)) >= 12.0:
		highlights.append("Frequent reversals and submission drama")
	if damage_balance >= 0.72:
		highlights.append("A fiercely competitive contest")
	elif damage_balance < 0.28:
		highlights.append("A one-sided contest")
	if signatures > 0 and finishers > 0:
		highlights.append("Strong signature-to-finisher escalation")
	elif finishers > 0:
		highlights.append("A decisive finisher sequence")
	if float(components.get("variety", 0.0)) >= 10.5:
		highlights.append("Excellent offensive variety")
	if float(components.get("pacing", 0.0)) >= 11.0:
		highlights.append("Consistent, purposeful pacing")
	if penalties >= 5.0:
		highlights.append("Repetition slowed the match")
	while highlights.size() > 4:
		highlights.pop_back()
	if highlights.size() < 2:
		highlights.append("A straightforward wrestling contest")
	if highlights.size() < 2:
		highlights.append("A clear and decisive conclusion")
	return highlights
