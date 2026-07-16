@tool
extends EditorScript
class_name WrestlerDuplicateCleanup

const WRESTLER_ROOT: String = "res://Wrestlers"

func _run() -> void:
	_delete_if_exists("res://Wrestlers/tcg/Oceania/Face/Male/malosi_sikoa.tres")
	_delete_if_exists("res://Wrestlers/tcg/Oceania/Heel/Male/malosi_sikoa.tres")

	var nolan_fraser: WrestlerResource = _make_wrestler({
		"wrestler_name": "Nolan Fraser",
		"gimmick_name": "The Atlantic Avalanche",
		"gimmick_description": "Powerful Canadian bruiser with East Coast force and a heavy forward drive",
		"wrestler_id": 20,
		"wrestler_class": [WrestlerResource.WrestlerClass.POWERHOUSE, WrestlerResource.WrestlerClass.STRIKER],
		"wrestler_gender": WrestlerResource.WrestlerGender.MALE,
		"wrestler_disposition": WrestlerResource.WrestlerDisposition.FACE,
		"Age": 30,
		"wrestler_height": "6'2",
		"wrestler_weight": 268,
		"birthplace": WrestlerResource.Region.NORTH_AMERICA,
		"north_american_country": WrestlerResource.NA_Countries.CANADA,
		"strength": 84, "speed": 48, "stamina": 72,
		"skill": 52, "striking": 80, "charisma": 68,
		"pop_north_america": 58, "pop_south_america": 35, "pop_europe": 42, "pop_asia": 35, "pop_africa": 35, "pop_oceania": 40
	})
	_save_wrestler(
		nolan_fraser,
		"res://Wrestlers/tcg/North_America/Face/Male/nolan_fraser.tres"
	)

	var malosi_sikoa: WrestlerResource = _make_wrestler({
		"wrestler_name": "Malosi Sikoa",
		"gimmick_name": "The Island Destroyer",
		"gimmick_description": "Brutal Samoan powerhouse enforcer",
		"wrestler_id": 27,
		"wrestler_class": [WrestlerResource.WrestlerClass.POWERHOUSE],
		"wrestler_gender": WrestlerResource.WrestlerGender.MALE,
		"wrestler_disposition": WrestlerResource.WrestlerDisposition.HEEL,
		"Age": 32,
		"wrestler_height": "6'2",
		"wrestler_weight": 285,
		"birthplace": WrestlerResource.Region.OCEANIA,
		"oceania_country": WrestlerResource.Oceania_Countries.SAMOA,
		"strength": 94, "speed": 40, "stamina": 72,
		"skill": 45, "striking": 82, "charisma": 70,
		"pop_north_america": 45, "pop_south_america": 30, "pop_europe": 50, "pop_asia": 60, "pop_africa": 25, "pop_oceania": 90
	})
	_save_wrestler(
		malosi_sikoa,
		"res://Wrestlers/nwgp/Oceania/Heel/Male/malosi_sikoa.tres"
	)

	var nefisa_zahra: WrestlerResource = _make_wrestler({
		"wrestler_name": "Nefisa Zahra",
		"gimmick_name": "The Golden Matriarch",
		"gimmick_description": "Egyptian ace whose regal composure and precise striking define the division",
		"wrestler_id": 29,
		"wrestler_class": [WrestlerResource.WrestlerClass.TECHNICIAN, WrestlerResource.WrestlerClass.STRIKER],
		"wrestler_gender": WrestlerResource.WrestlerGender.FEMALE,
		"wrestler_disposition": WrestlerResource.WrestlerDisposition.FACE,
		"Age": 30,
		"wrestler_height": "5'8",
		"wrestler_weight": 146,
		"birthplace": WrestlerResource.Region.AFRICA,
		"africa_country": WrestlerResource.Africa_Countries.EGYPT,
		"strength": 51, "speed": 84, "stamina": 85,
		"skill": 91, "striking": 86, "charisma": 88,
		"pop_north_america": 17, "pop_south_america": 11, "pop_europe": 42, "pop_asia": 25, "pop_africa": 82, "pop_oceania": 13
	})
	_save_wrestler(
		nefisa_zahra,
		"res://Wrestlers/aawa/Africa/Face/Female/nefisa_zahra.tres"
	)

	print("Duplicate cleanup complete.")
	print("Next step: run the promotion repair-from-folders script again.")


func _make_wrestler(data: Dictionary) -> WrestlerResource:
	var wrestler: WrestlerResource = WrestlerResource.new()

	wrestler.wrestler_name = data["wrestler_name"]
	wrestler.gimmick_name = data["gimmick_name"]
	wrestler.gimmick_description = data["gimmick_description"]
	wrestler.wrestler_id = data["wrestler_id"]

	var typed_classes: Array[WrestlerResource.WrestlerClass] = []
	for c: WrestlerResource.WrestlerClass in data["wrestler_class"]:
		typed_classes.append(c)
	wrestler.wrestler_class = typed_classes

	wrestler.wrestler_gender = data["wrestler_gender"]
	wrestler.wrestler_disposition = data["wrestler_disposition"]
	wrestler.Age = data["Age"]
	wrestler.wrestler_height = data["wrestler_height"]
	wrestler.wrestler_weight = data["wrestler_weight"]

	wrestler.wrestler_traits = []
	wrestler.current_contract = null
	wrestler.contract_history = []
	wrestler.bank_balance = 0
	wrestler.move_set = []

	wrestler.birthplace = data["birthplace"]
	_assign_country(wrestler, data)

	wrestler.strength = data["strength"]
	wrestler.speed = data["speed"]
	wrestler.stamina = data["stamina"]
	wrestler.skill = data["skill"]
	wrestler.striking = data["striking"]
	wrestler.charisma = data["charisma"]

	wrestler.pop_north_america = data["pop_north_america"]
	wrestler.pop_south_america = data["pop_south_america"]
	wrestler.pop_europe = data["pop_europe"]
	wrestler.pop_asia = data["pop_asia"]
	wrestler.pop_africa = data["pop_africa"]
	wrestler.pop_oceania = data["pop_oceania"]

	return wrestler


func _assign_country(wrestler: WrestlerResource, data: Dictionary) -> void:
	match wrestler.birthplace:
		WrestlerResource.Region.NORTH_AMERICA:
			wrestler.north_american_country = data.get("north_american_country", WrestlerResource.NA_Countries.OTHER)
		WrestlerResource.Region.SOUTH_AMERICA:
			wrestler.south_american_country = data.get("south_american_country", WrestlerResource.SA_Countries.OTHER)
		WrestlerResource.Region.EUROPE:
			wrestler.europe_country = data.get("europe_country", WrestlerResource.Europe_Countries.OTHER)
		WrestlerResource.Region.ASIA:
			wrestler.asia_country = data.get("asia_country", WrestlerResource.Asia_Countries.OTHER)
		WrestlerResource.Region.AFRICA:
			wrestler.africa_country = data.get("africa_country", WrestlerResource.Africa_Countries.OTHER)
		WrestlerResource.Region.OCEANIA:
			wrestler.oceania_country = data.get("oceania_country", WrestlerResource.Oceania_Countries.OTHER)


func _save_wrestler(wrestler: WrestlerResource, save_path: String) -> void:
	_ensure_dir(save_path.get_base_dir())

	var result: Error = ResourceSaver.save(wrestler, save_path)
	if result != OK:
		push_error("Failed to save wrestler '%s' to %s. Error code: %s" % [
			wrestler.wrestler_name, save_path, str(result)
		])
	else:
		print("Saved: ", save_path)


func _delete_if_exists(path: String) -> void:
	if ResourceLoader.exists(path):
		var result: Error = DirAccess.remove_absolute(path)
		if result == OK:
			print("Deleted: ", path)
		else:
			push_warning("Could not delete: %s | Error: %s" % [path, str(result)])


func _ensure_dir(path: String) -> void:
	var trimmed: String = path.trim_prefix("res://").trim_suffix("/")
	if trimmed.is_empty():
		return

	var parts: PackedStringArray = trimmed.split("/")
	var current_path: String = "res://"

	for part: String in parts:
		current_path += part
		if not DirAccess.dir_exists_absolute(current_path):
			var make_result: Error = DirAccess.make_dir_absolute(current_path)
			if make_result != OK and make_result != ERR_ALREADY_EXISTS:
				push_error("Failed to create directory: %s" % current_path)
				return
		current_path += "/"
