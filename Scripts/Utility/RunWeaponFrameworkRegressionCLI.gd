extends SceneTree

const CATALOGUE: WeaponCatalogueResource = preload("res://Weapons/weapon_catalogue.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	_run()
	if _failures.is_empty():
		print("WEAPON_FRAMEWORK_REGRESSION: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("WEAPON_FRAMEWORK_REGRESSION: %s" % failure)
	quit(1)


func _run() -> void:
	_check(CATALOGUE != null, "catalogue loads")
	if CATALOGUE == null:
		return
	var weapons := CATALOGUE.valid_weapons()
	_check(weapons.size() == 11, "catalogue contains eleven weapons")
	var expected_ids := [
		&"steel_chair", &"kendo_stick", &"baseball_bat", &"hockey_stick", &"shovel",
		&"light_tube", &"barbed_wire_bat", &"janice", &"table", &"ladder", &"thumbtacks",
	]
	var found_ids: Array[StringName] = []
	for weapon in weapons:
		found_ids.append(weapon.weapon_id)
		_check(weapon.minimum_durability >= 1 and weapon.maximum_durability <= 4, "%s durability is within 1-4" % weapon.display_name)
		_check(weapon.minimum_durability <= weapon.maximum_durability, "%s durability range is ordered" % weapon.display_name)
		if weapon.weapon_kind == WeaponResource.WeaponKind.THUMBTACKS:
			_check(weapon.attack_set.is_empty(), "thumbtacks are a setup hazard, not a direct attack")
		else:
			_check(weapon.attack_set.size() == 2, "%s has standing and grounded attacks" % weapon.display_name)
			var postures: Array[int] = []
			for attack in weapon.attack_set:
				if attack != null:
					postures.append(attack.target_posture)
			_check(WeaponAttackResource.TargetPosture.STANDING in postures, "%s has a standing attack" % weapon.display_name)
			_check(WeaponAttackResource.TargetPosture.GROUNDED in postures, "%s has a grounded attack" % weapon.display_name)
	for weapon_id in expected_ids:
		_check(weapon_id in found_ids, "catalogue contains %s" % String(weapon_id))
	var table := CATALOGUE.get_weapon(&"table")
	var ladder := CATALOGUE.get_weapon(&"ladder")
	var tacks := CATALOGUE.get_weapon(&"thumbtacks")
	var janice := CATALOGUE.get_weapon(&"janice")
	var tube := CATALOGUE.get_weapon(&"light_tube")
	_check(table != null and table.maximum_live_instances == 2 and table.can_stack, "table supports the two-instance stack exception")
	_check(ladder != null and ladder.can_be_climbed, "ladder climb capability is authored")
	_check(tacks != null and tacks.can_be_spread and tacks.maximum_durability == 1, "thumbtacks are a one-use spreadable hazard")
	_check(janice != null and janice.bleed_rating == 80.0 and janice.maximum_durability == 3, "Janice has the intended bleeding and durability identity")
	_check(tube != null and tube.minimum_durability == 1 and tube.maximum_durability == 1, "light tube always breaks after its committed use")
	_check(WrestlerResource.Position.PERCHED == 5 and WrestlerResource.Position.CLIMBING == 6, "position enum was appended without renumbering")
	_check(WrestlerResource.Area.TOP_ROPE == 6 and WrestlerResource.Area.LADDER == 7, "area enum was appended without renumbering")
	_test_environment_limits(table)


func _test_environment_limits(table: WeaponResource) -> void:
	var environment := MatchEnvironmentState.new()
	var chair := CATALOGUE.get_weapon(&"steel_chair")
	_check(environment.create_held_instance(chair, 1, WrestlerResource.Area.OUTSIDE, 1) != null, "first chair instance is allowed")
	_check(not environment.can_retrieve(chair), "second live chair is blocked")
	var first_table := environment.create_held_instance(table, 1, WrestlerResource.Area.OUTSIDE, 1)
	var second_table := environment.create_held_instance(table, 2, WrestlerResource.Area.OUTSIDE, 2)
	_check(first_table != null and second_table != null, "two live tables are allowed")
	_check(not environment.can_retrieve(table), "third live table is blocked")
	for weapon_id in [&"kendo_stick", &"baseball_bat", &"hockey_stick"]:
		environment.create_held_instance(CATALOGUE.get_weapon(weapon_id), 1, WrestlerResource.Area.OUTSIDE, 1)
	_check(environment.live_count() == MatchEnvironmentState.MAX_LIVE_OBJECTS, "global live-object cap is six")
	_check(not environment.can_retrieve(CATALOGUE.get_weapon(&"shovel")), "seventh live object is blocked")
	environment.consume(first_table, true)
	_check(environment.can_retrieve(CATALOGUE.get_weapon(&"shovel")), "broken object releases capacity")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
