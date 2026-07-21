extends RefCounted
class_name MatchEnvironmentState

const MAX_LIVE_OBJECTS := 6

var instances: Array[MatchWeaponInstance] = []
var _next_instance_id: int = 1


func reset() -> void:
	instances.clear()
	_next_instance_id = 1


func can_retrieve(weapon: WeaponResource) -> bool:
	if weapon == null or not weapon.can_be_retrieved_from_under_ring:
		return false
	if live_count() >= MAX_LIVE_OBJECTS:
		return false
	return live_count_for_weapon(weapon.weapon_id) < weapon.maximum_live_instances


func create_held_instance(weapon: WeaponResource, side: int, area: int, durability: int) -> MatchWeaponInstance:
	if not can_retrieve(weapon):
		return null
	var instance := MatchWeaponInstance.new()
	instance.instance_id = _next_instance_id
	_next_instance_id += 1
	instance.weapon = weapon
	instance.durability = clampi(durability, 1, 4)
	instance.lifecycle = MatchWeaponInstance.Lifecycle.HELD
	instance.holder_side = side
	instance.area = area
	instances.append(instance)
	return instance


func get_instance(instance_id: int) -> MatchWeaponInstance:
	for instance in instances:
		if instance != null and instance.instance_id == instance_id:
			return instance
	return null


func held_by(side: int) -> MatchWeaponInstance:
	for instance in instances:
		if instance != null and instance.is_live() and instance.is_held() and instance.holder_side == side:
			return instance
	return null


func live_count() -> int:
	var count := 0
	for instance in instances:
		if instance != null and instance.is_live():
			count += 1
	return count


func live_count_for_weapon(weapon_id: StringName) -> int:
	var count := 0
	for instance in instances:
		if (
			instance != null
			and instance.is_live()
			and instance.weapon != null
			and instance.weapon.weapon_id == weapon_id
		):
			count += 1
	return count


func instances_in_area(area: int, lifecycles: Array = []) -> Array[MatchWeaponInstance]:
	var result: Array[MatchWeaponInstance] = []
	for instance in instances:
		if instance == null or not instance.is_live() or instance.area != area:
			continue
		if not lifecycles.is_empty() and instance.lifecycle not in lifecycles:
			continue
		result.append(instance)
	return result


func find_setup(kind: int, area: int, lifecycle: int = -1) -> MatchWeaponInstance:
	for instance in instances:
		if (
			instance != null
			and instance.is_live()
			and instance.weapon != null
			and instance.weapon.weapon_kind == kind
			and instance.area == area
			and (lifecycle < 0 or instance.lifecycle == lifecycle)
		):
			return instance
	return null


func drop(instance: MatchWeaponInstance, area: int) -> void:
	if instance == null or not instance.is_live():
		return
	instance.lifecycle = MatchWeaponInstance.Lifecycle.DROPPED
	instance.area = area
	instance.holder_side = 0
	instance.ladder_climber_side = 0
	instance.ladder_climb_stage = 0
	instance.clear_positioning()


func hold(instance: MatchWeaponInstance, side: int, area: int) -> void:
	if instance == null or not instance.is_live():
		return
	instance.lifecycle = MatchWeaponInstance.Lifecycle.HELD
	instance.holder_side = side
	instance.area = area
	instance.ladder_climber_side = 0
	instance.ladder_climb_stage = 0
	instance.clear_positioning()


func consume(instance: MatchWeaponInstance, broken: bool = false) -> void:
	if instance == null:
		return
	instance.lifecycle = MatchWeaponInstance.Lifecycle.BROKEN if broken else MatchWeaponInstance.Lifecycle.CONSUMED
	instance.holder_side = 0
	instance.ladder_climber_side = 0
	instance.ladder_climb_stage = 0
	instance.clear_positioning()


func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance in instances:
		if instance != null and instance.is_live():
			result.append(instance.snapshot())
	return result

