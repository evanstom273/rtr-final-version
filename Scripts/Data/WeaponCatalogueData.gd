@tool
extends Resource
class_name WeaponCatalogueResource

@export var weapons: Array[WeaponResource] = []


func get_weapon(weapon_id: StringName) -> WeaponResource:
	for weapon in weapons:
		if weapon != null and weapon.weapon_id == weapon_id:
			return weapon
	return null


func valid_weapons() -> Array[WeaponResource]:
	var result: Array[WeaponResource] = []
	for weapon in weapons:
		if weapon != null and not weapon.weapon_id.is_empty() and weapon not in result:
			result.append(weapon)
	return result

