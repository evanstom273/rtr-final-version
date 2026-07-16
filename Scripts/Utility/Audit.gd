@tool
extends EditorScript
class_name WrestlerFolderAuditPretty

const WRESTLER_ROOT: String = "res://Wrestlers"
const OUTPUT_PATH: String = "res://wrestler_folder_audit_pretty.txt"

func _run() -> void:
	var grouped: Dictionary = {}
	_collect_wrestlers_grouped_by_promotion(WRESTLER_ROOT, grouped)

	if grouped.is_empty():
		push_error("No wrestler resources found under %s" % WRESTLER_ROOT)
		return

	var promotion_keys: Array[String] = []
	for key_variant in grouped.keys():
		promotion_keys.append(str(key_variant))
	promotion_keys.sort()

	var lines: Array[String] = []
	var summary_rows: Array[Dictionary] = []

	var grand_total: int = 0
	var grand_male: int = 0
	var grand_female: int = 0
	var grand_face: int = 0
	var grand_heel: int = 0

	lines.append(_line("="))
	lines.append(_center("WRESTLER FOLDER AUDIT"))
	lines.append(_line("="))
	lines.append("")
	lines.append("Root Folder : %s" % WRESTLER_ROOT)
	lines.append("Output File : %s" % OUTPUT_PATH)
	lines.append("")

	for promotion_key: String in promotion_keys:
		var wrestler_entries: Array = grouped[promotion_key]
		wrestler_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _entry_sort_value(a) < _entry_sort_value(b)
		)

		var male_count: int = 0
		var female_count: int = 0
		var face_count: int = 0
		var heel_count: int = 0

		for entry_variant in wrestler_entries:
			var entry: Dictionary = entry_variant
			var wrestler: WrestlerResource = entry["wrestler"]

			match wrestler.wrestler_gender:
				WrestlerResource.WrestlerGender.MALE:
					male_count += 1
				WrestlerResource.WrestlerGender.FEMALE:
					female_count += 1

			match wrestler.wrestler_disposition:
				WrestlerResource.WrestlerDisposition.FACE:
					face_count += 1
				WrestlerResource.WrestlerDisposition.HEEL:
					heel_count += 1

		var total_count: int = wrestler_entries.size()

		grand_total += total_count
		grand_male += male_count
		grand_female += female_count
		grand_face += face_count
		grand_heel += heel_count

		summary_rows.append({
			"promotion": promotion_key,
			"total": total_count,
			"male": male_count,
			"female": female_count,
			"face": face_count,
			"heel": heel_count
		})

		lines.append(_line("-"))
		lines.append("PROMOTION: %s" % promotion_key.to_upper())
		lines.append(_line("-"))
		lines.append("Total: %-3s   Men: %-3s   Women: %-3s   Faces: %-3s   Heels: %-3s" % [
			str(total_count), str(male_count), str(female_count), str(face_count), str(heel_count)
		])
		lines.append("")

		var current_block: String = ""

		for entry_variant in wrestler_entries:
			var entry: Dictionary = entry_variant
			var wrestler: WrestlerResource = entry["wrestler"]
			var path: String = entry["path"]

			var block_name: String = "%s / %s" % [
				_gender_to_string(wrestler.wrestler_gender),
				_disposition_to_string(wrestler.wrestler_disposition)
			]

			if block_name != current_block:
				current_block = block_name
				lines.append("  [%s]" % current_block)

			lines.append("    • %-28s | Age %-2s | %-4s | %slb" % [
				wrestler.wrestler_name,
				str(wrestler.Age),
				wrestler.wrestler_height,
				str(wrestler.wrestler_weight)
			])
			lines.append("      Class: %s" % _class_array_to_string(wrestler.wrestler_class))
			lines.append("      Path : %s" % path)

		lines.append("")
		lines.append("")

	lines.append(_line("="))
	lines.append(_center("SYSTEM SUMMARY"))
	lines.append(_line("="))
	lines.append("")
	lines.append("Total wrestler files : %s" % str(grand_total))
	lines.append("Total male wrestlers : %s" % str(grand_male))
	lines.append("Total female wrestlers : %s" % str(grand_female))
	lines.append("Total faces : %s" % str(grand_face))
	lines.append("Total heels : %s" % str(grand_heel))
	lines.append("")

	lines.append(_line("-"))
	lines.append("PER-PROMOTION SUMMARY")
	lines.append(_line("-"))
	lines.append(_pad("Promotion", 12) + _pad("Total", 8) + _pad("Men", 8) + _pad("Women", 8) + _pad("Faces", 8) + _pad("Heels", 8))
	lines.append(_line("-"))

	for row_variant in summary_rows:
		var row: Dictionary = row_variant
		lines.append(
			_pad(str(row["promotion"]).to_upper(), 12) +
			_pad(str(row["total"]), 8) +
			_pad(str(row["male"]), 8) +
			_pad(str(row["female"]), 8) +
			_pad(str(row["face"]), 8) +
			_pad(str(row["heel"]), 8)
		)

	lines.append("")

	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open output file for writing: %s" % OUTPUT_PATH)
		return

	file.store_string("\n".join(lines))
	file.close()

	print("Pretty wrestler folder audit written to: ", OUTPUT_PATH)


func _collect_wrestlers_grouped_by_promotion(dir_path: String, grouped: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("Could not open directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var item_name: String = dir.get_next()

	while item_name != "":
		if item_name.begins_with("."):
			item_name = dir.get_next()
			continue

		var full_path: String = dir_path.path_join(item_name)

		if dir.current_is_dir():
			_collect_wrestlers_grouped_by_promotion(full_path, grouped)
		elif item_name.get_extension().to_lower() == "tres":
			var resource: Resource = load(full_path)
			if resource is WrestlerResource:
				var wrestler: WrestlerResource = resource as WrestlerResource
				var promotion_folder: String = _extract_promotion_folder_from_path(full_path)

				if promotion_folder.is_empty():
					push_warning("Could not determine promotion folder from: %s" % full_path)
				else:
					if not grouped.has(promotion_folder):
						grouped[promotion_folder] = []

					grouped[promotion_folder].append({
						"name": wrestler.wrestler_name,
						"path": full_path,
						"wrestler": wrestler
					})

		item_name = dir.get_next()

	dir.list_dir_end()


func _extract_promotion_folder_from_path(path: String) -> String:
	var trimmed: String = path.trim_prefix("res://Wrestlers/")
	var parts: PackedStringArray = trimmed.split("/")

	if parts.size() < 5:
		return ""

	return parts[0]


func _entry_sort_value(entry: Dictionary) -> String:
	var wrestler: WrestlerResource = entry["wrestler"]
	return "%s|%s|%s" % [
		_gender_sort_key(wrestler.wrestler_gender),
		_disposition_sort_key(wrestler.wrestler_disposition),
		wrestler.wrestler_name.to_lower()
	]


func _gender_sort_key(gender: WrestlerResource.WrestlerGender) -> String:
	match gender:
		WrestlerResource.WrestlerGender.MALE:
			return "0"
		WrestlerResource.WrestlerGender.FEMALE:
			return "1"
		_:
			return "2"


func _disposition_sort_key(disposition: WrestlerResource.WrestlerDisposition) -> String:
	match disposition:
		WrestlerResource.WrestlerDisposition.FACE:
			return "0"
		WrestlerResource.WrestlerDisposition.HEEL:
			return "1"
		_:
			return "2"


func _gender_to_string(gender: WrestlerResource.WrestlerGender) -> String:
	match gender:
		WrestlerResource.WrestlerGender.MALE:
			return "Male"
		WrestlerResource.WrestlerGender.FEMALE:
			return "Female"
		_:
			return "Unknown"


func _disposition_to_string(disposition: WrestlerResource.WrestlerDisposition) -> String:
	match disposition:
		WrestlerResource.WrestlerDisposition.FACE:
			return "Face"
		WrestlerResource.WrestlerDisposition.HEEL:
			return "Heel"
		_:
			return "Unknown"


func _class_array_to_string(classes: Array[WrestlerResource.WrestlerClass]) -> String:
	var names: Array[String] = []

	for c: WrestlerResource.WrestlerClass in classes:
		match c:
			WrestlerResource.WrestlerClass.HIGH_FLYER:
				names.append("High Flyer")
			WrestlerResource.WrestlerClass.POWERHOUSE:
				names.append("Powerhouse")
			WrestlerResource.WrestlerClass.TECHNICIAN:
				names.append("Technician")
			WrestlerResource.WrestlerClass.STRIKER:
				names.append("Striker")
			WrestlerResource.WrestlerClass.HARDCORE:
				names.append("Hardcore")
			_:
				names.append("Unknown")

	return ", ".join(names)


func _line(character: String, width: int = 100) -> String:
	return character.repeat(width)


func _center(text: String, width: int = 100) -> String:
	if text.length() >= width:
		return text

	var total_padding: int = width - text.length()
	var left: int = floori(float(total_padding) / 2.0)
	return " ".repeat(left) + text


func _pad(text: String, width: int) -> String:
	if text.length() >= width:
		return text.substr(0, width - 1) + " "
	return text + " ".repeat(width - text.length())
