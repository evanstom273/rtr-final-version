extends Resource
class_name MatchRules

enum Stipulation { STANDARD, NO_DISQUALIFICATION, TABLES, LADDER }

const DEFAULT_ACTION_CLOCK_SECONDS := 20
const ACTION_CLOCK_OPTIONS := [10, 15, 20, 25, 30]

@export var disqualifications_enabled: bool = true
@export var count_outs_enabled: bool = true
@export_range(1, 100, 1) var count_out_limit: int = 10
@export_enum("10 Seconds:10", "15 Seconds:15", "20 Seconds:20", "25 Seconds:25", "30 Seconds:30") var action_clock_seconds: int = DEFAULT_ACTION_CLOCK_SECONDS
@export var weapons_enabled: bool = true
@export var pinfall_enabled: bool = true
@export var submission_enabled: bool = true
@export var stipulation: Stipulation = Stipulation.STANDARD


static func from_dictionary(values: Dictionary) -> MatchRules:
	var rules := MatchRules.new()
	rules.disqualifications_enabled = bool(values.get("disqualifications_enabled", true))
	rules.count_outs_enabled = bool(values.get("count_outs_enabled", true))
	rules.count_out_limit = clampi(int(values.get("count_out_limit", 10)), 1, 100)
	rules.action_clock_seconds = normalized_action_clock_seconds(
		int(values.get("action_clock_seconds", DEFAULT_ACTION_CLOCK_SECONDS))
	)
	rules.weapons_enabled = bool(values.get("weapons_enabled", true))
	rules.pinfall_enabled = bool(values.get("pinfall_enabled", true))
	rules.submission_enabled = bool(values.get("submission_enabled", true))
	rules.stipulation = clampi(int(values.get("stipulation", Stipulation.STANDARD)), Stipulation.STANDARD, Stipulation.LADDER)
	return rules


func runtime_copy() -> MatchRules:
	return MatchRules.from_dictionary(to_dictionary())


func to_dictionary() -> Dictionary:
	return {
		"disqualifications_enabled": disqualifications_enabled,
		"count_outs_enabled": count_outs_enabled,
		"count_out_limit": count_out_limit,
		"action_clock_seconds": action_clock_seconds,
		"weapons_enabled": weapons_enabled,
		"pinfall_enabled": pinfall_enabled,
		"submission_enabled": submission_enabled,
		"stipulation": stipulation,
	}


func summary() -> String:
	return "DQ: %s  |  COUNT-OUT: %s%s  |  CLOCK: %ds  |  WEAPONS: %s" % [
		"ON" if disqualifications_enabled else "OFF",
		"ON" if count_outs_enabled else "OFF",
		" (%d)" % count_out_limit if count_outs_enabled else "",
		action_clock_seconds,
		"ILLEGAL" if disqualifications_enabled else "LEGAL",
	]


static func normalized_action_clock_seconds(value: int) -> int:
	return value if value in ACTION_CLOCK_OPTIONS else DEFAULT_ACTION_CLOCK_SECONDS


func is_outside_area(area: int) -> bool:
	return area in [
		WrestlerResource.Area.APRON,
		WrestlerResource.Area.OUTSIDE,
		WrestlerResource.Area.RAMP,
	]


func weapon_attack_causes_disqualification(weapon: WeaponResource) -> bool:
	return (
		disqualifications_enabled
		and weapon != null
		and weapon.is_illegal_under_normal_rules
	)
