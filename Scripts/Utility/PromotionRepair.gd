@tool
extends EditorScript
class_name PromotionReferenceRepairFromFolders

const PROMOTION_ROOT: String = "res://Promotions"
const WRESTLER_ROOT: String = "res://Wrestlers"

func _run() -> void:
	var grouped_wrestlers: Dictionary = _load_wrestlers_grouped_by_promotion_folder(WRESTLER_ROOT)
	if grouped_wrestlers.is_empty():
		push_error("No wrestler resources found under %s" % WRESTLER_ROOT)
		return

	var promotion_paths: Array[String] = []
	_collect_promotion_paths(PROMOTION_ROOT, promotion_paths)

	if promotion_paths.is_empty():
		push_error("No promotion resources found under %s" % PROMOTION_ROOT)
		return

	for promotion_path: String in promotion_paths:
		var promotion: PromotionResource = load(promotion_path) as PromotionResource
		if promotion == null:
			push_warning("Could not load promotion: %s" % promotion_path)
			continue

		var initials: String = promotion.promotion_initials.strip_edges().to_lower()

		if not grouped_wrestlers.has(initials):
			push_warning("No wrestler folder group found for promotion: %s" % promotion.promotion_initials)
			promotion.mens_division = []
			promotion.womens_division = []

			var empty_save_result: Error = ResourceSaver.save(promotion, promotion.resource_path)
			if empty_save_result != OK:
				push_error("Failed to save empty divisions for %s. Error: %s" % [promotion.promotion_initials, str(empty_save_result)])
			continue

		var wrestler_group: Array = grouped_wrestlers[initials]
		var men: Array[WrestlerResource] = []
		var women: Array[WrestlerResource] = []

		for wrestler_variant in wrestler_group:
			var wrestler: WrestlerResource = wrestler_variant as WrestlerResource
			if wrestler == null:
				continue

			match wrestler.wrestler_gender:
				WrestlerResource.WrestlerGender.MALE:
					men.append(wrestler)
				WrestlerResource.WrestlerGender.FEMALE:
					women.append(wrestler)
				_:
					push_warning("Invalid gender on wrestler: %s" % wrestler.wrestler_name)

		promotion.mens_division = men
		promotion.womens_division = women

		var save_result: Error = ResourceSaver.save(promotion, promotion.resource_path)
		if save_result != OK:
			push_error("Failed to save promotion %s. Error: %s" % [promotion.promotion_initials, str(save_result)])
			continue

		print("Repaired %s | Men: %s | Women: %s" % [
			promotion.promotion_initials,
			str(men.size()),
			str(women.size())
		])


func _load_wrestlers_grouped_by_promotion_folder(root_path: String) -> Dictionary:
	var wrestler_paths: Array[String] = []
	_collect_wrestler_paths(root_path, wrestler_paths)

	var grouped: Dictionary = {}

	for wrestler_path: String in wrestler_paths:
		var wrestler: WrestlerResource = load(wrestler_path) as WrestlerResource
		if wrestler == null:
			continue

		var promotion_folder: String = _extract_promotion_folder_from_path(wrestler_path)
		if promotion_folder.is_empty():
			push_warning("Could not determine promotion folder from wrestler path: %s" % wrestler_path)
			continue

		if not grouped.has(promotion_folder):
			grouped[promotion_folder] = []

		grouped[promotion_folder].append(wrestler)

	return grouped


func _extract_promotion_folder_from_path(path: String) -> String:
	var trimmed: String = path.trim_prefix("res://Wrestlers/")
	var parts: PackedStringArray = trimmed.split("/")

	# Expected:
	# res://Wrestlers/Promotion/Region/Disposition/Gender/file.tres
	if parts.size() < 5:
		return ""

	return parts[0].to_lower()


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
			var resource: Resource = load(full_path)
			if resource is WrestlerResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()


func _collect_promotion_paths(dir_path: String, results: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("Could not open promotion directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var item_name: String = dir.get_next()

	while item_name != "":
		if item_name.begins_with("."):
			item_name = dir.get_next()
			continue

		var full_path: String = dir_path.path_join(item_name)

		if dir.current_is_dir():
			_collect_promotion_paths(full_path, results)
		elif item_name.get_extension().to_lower() == "tres":
			var resource: Resource = load(full_path)
			if resource is PromotionResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()
