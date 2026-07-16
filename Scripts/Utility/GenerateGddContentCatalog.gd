@tool
extends SceneTree

const DOCUMENT_PATH := "res://docs/RISE_TO_RELEVANCE_GDD_TAD.md"
const START_MARKER := "<!-- GENERATED_CONTENT_CATALOG_START -->"
const END_MARKER := "<!-- GENERATED_CONTENT_CATALOG_END -->"

const CLASS_NAMES := ["High Flyer", "Powerhouse", "Technician", "Striker", "Hardcore"]
const REGION_NAMES := ["Not Set", "North America", "South America", "Asia", "Africa", "Oceania", "Europe"]
const GENDER_NAMES := ["Not Set", "Male", "Female"]
const DISPOSITION_NAMES := ["Not Set", "Face", "Heel"]
const POSITION_NAMES := ["Not Set", "Standing", "Grounded", "In Corner", "Running", "Rope Rebound", "Top Rope", "Apron"]
const MOVE_TYPE_NAMES := ["None", "Standing Front", "Standing Behind", "Running", "Rope Rebound", "Grounded", "Springboard", "Corner", "Diving Standing", "Diving Grounded"]
const TARGET_NAMES := ["None", "Head", "Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]
const TARGETING_MODE_NAMES := ["Fixed Parts", "Choose Arm", "Choose Leg", "Both Arms", "Both Legs"]
const STRIKE_WEIGHT_NAMES := ["Weak", "Medium", "Heavy"]
const INTERACTION_NAMES := ["Auto", "Timing Strike", "Timing Aerial", "Control Meter (legacy HOLD_POWER)", "Submission Lock-In"]

var _promotions: Array[PromotionResource] = []
var _wrestlers: Array[WrestlerResource] = []
var _moves: Array[MoveResource] = []
var _titles: Array[TitleResource] = []
var _promotion_by_wrestler_path: Dictionary = {}
var _division_by_wrestler_path: Dictionary = {}
var _promotion_by_title_path: Dictionary = {}
var _wrestler_by_promotion_and_id: Dictionary = {}
var _move_users: Dictionary = {}
var _titles_by_wrestler_path: Dictionary = {}


func _initialize() -> void:
	var error_message := _generate_catalogue()
	if error_message.is_empty():
		print("GDD content catalogue generated successfully.")
		quit(0)
	else:
		push_error(error_message)
		quit(1)


func _generate_catalogue() -> String:
	_load_resources()
	if _wrestlers.size() != 400:
		return "Expected 400 wrestlers, found %d." % _wrestlers.size()
	if _moves.size() != 626:
		return "Expected 626 moves, found %d." % _moves.size()
	if _titles.size() != 33:
		return "Expected 33 titles, found %d." % _titles.size()
	if _promotions.size() != 11:
		return "Expected 11 promotions, found %d." % _promotions.size()

	_build_relationship_maps()
	var existing := FileAccess.get_file_as_string(DOCUMENT_PATH)
	if existing.is_empty():
		return "Could not read %s." % DOCUMENT_PATH

	var prefix := existing.rstrip("\n")
	var suffix := ""
	var start_index := existing.find(START_MARKER)
	if start_index >= 0:
		prefix = existing.substr(0, start_index).rstrip("\n")
		while prefix.ends_with("---"):
			prefix = prefix.trim_suffix("---").rstrip("\n")
		var end_index := existing.find(END_MARKER, start_index)
		if end_index >= 0:
			suffix = existing.substr(end_index + END_MARKER.length()).strip_edges()

	var sections := PackedStringArray()
	sections.append(prefix)
	sections.append("")
	sections.append("---")
	sections.append("")
	sections.append(START_MARKER)
	sections.append("")
	sections.append(_generate_catalogue_introduction())
	sections.append(_generate_promotion_catalogue())
	sections.append(_generate_title_catalogue())
	sections.append(_generate_move_catalogue())
	sections.append(_generate_roster_catalogue())
	sections.append(END_MARKER)
	if not suffix.is_empty():
		sections.append("")
		sections.append(suffix)

	var output := "\n".join(sections).rstrip("\n") + "\n"
	var file := FileAccess.open(DOCUMENT_PATH, FileAccess.WRITE)
	if file == null:
		return "Could not open %s for writing." % DOCUMENT_PATH
	file.store_string(output)
	file.close()
	return ""


func _load_resources() -> void:
	for path in _find_tres("res://Promotions"):
		var resource := ResourceLoader.load(path)
		if resource is PromotionResource:
			_promotions.append(resource as PromotionResource)
		elif resource is TitleResource:
			_titles.append(resource as TitleResource)

	for path in _find_tres("res://Wrestlers"):
		var resource := ResourceLoader.load(path)
		if resource is WrestlerResource:
			_wrestlers.append(resource as WrestlerResource)

	for path in _find_tres("res://Moves"):
		var resource := ResourceLoader.load(path)
		if resource is MoveResource:
			_moves.append(resource as MoveResource)

	_promotions.sort_custom(_promotion_less)
	_titles.sort_custom(_title_less)
	_wrestlers.sort_custom(_wrestler_less)
	_moves.sort_custom(_move_less)


func _find_tres(root: String) -> PackedStringArray:
	var paths := PackedStringArray()
	var directory := DirAccess.open(root)
	if directory == null:
		return paths
	for file_name in DirAccess.get_files_at(root):
		if file_name.get_extension().to_lower() == "tres":
			paths.append(root.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(root):
		paths.append_array(_find_tres(root.path_join(directory_name)))
	return paths


func _build_relationship_maps() -> void:
	for promotion in _promotions:
		var roster_by_id: Dictionary = {}
		for wrestler in promotion.mens_division:
			_register_wrestler_promotion(wrestler, promotion, "Men's Division", roster_by_id)
		for wrestler in promotion.womens_division:
			_register_wrestler_promotion(wrestler, promotion, "Women's Division", roster_by_id)
		_wrestler_by_promotion_and_id[promotion.promotion_id] = roster_by_id
		for title in promotion.titles:
			if title != null:
				_promotion_by_title_path[title.resource_path] = promotion

	for wrestler in _wrestlers:
		var wrestler_label := _wrestler_reference(wrestler)
		for move in wrestler.move_set:
			if move == null:
				continue
			if not _move_users.has(move.resource_path):
				_move_users[move.resource_path] = PackedStringArray()
			var users: PackedStringArray = _move_users[move.resource_path]
			users.append(wrestler_label)
			_move_users[move.resource_path] = users

	for title in _titles:
		if title.current_holder_id <= 0:
			continue
		var holder := _find_title_holder(title, title.current_holder_id)
		if holder == null:
			continue
		if not _titles_by_wrestler_path.has(holder.resource_path):
			_titles_by_wrestler_path[holder.resource_path] = PackedStringArray()
		var title_names: PackedStringArray = _titles_by_wrestler_path[holder.resource_path]
		title_names.append(title.title_name)
		_titles_by_wrestler_path[holder.resource_path] = title_names


func _register_wrestler_promotion(wrestler: WrestlerResource, promotion: PromotionResource, division: String, roster_by_id: Dictionary) -> void:
	if wrestler == null:
		return
	_promotion_by_wrestler_path[wrestler.resource_path] = promotion
	_division_by_wrestler_path[wrestler.resource_path] = division
	roster_by_id[wrestler.wrestler_id] = wrestler


func _generate_catalogue_introduction() -> String:
	var lines := PackedStringArray()
	lines.append("## Appendix E - Complete generated content catalogue")
	lines.append("")
	lines.append("This appendix is generated directly from the project's live `.tres` resources by `Scripts/Utility/GenerateGddContentCatalog.gd`. It is an exhaustive content snapshot, not a representative sample.")
	lines.append("")
	lines.append("Snapshot totals:")
	lines.append("")
	lines.append("| Resource family | Loaded records |")
	lines.append("|---|---:|")
	lines.append("| Promotions | %d |" % _promotions.size())
	lines.append("| Titles | %d |" % _titles.size())
	lines.append("| Wrestlers | %d |" % _wrestlers.size())
	lines.append("| Moves | %d |" % _moves.size())
	lines.append("")
	lines.append("Catalogue conventions:")
	lines.append("")
	lines.append("- `None`, `Empty`, and zero values are deliberately printed. They identify unpopulated schema fields rather than hiding them.")
	lines.append("- Resource paths and UIDs provide an exact link back to the authored source.")
	lines.append("- Enum integers are rendered as their current Godot enum labels.")
	lines.append("- Global popularity is the live computed average of the six regional popularity values.")
	lines.append("- Wrestler promotion/division and move users are derived from promotion rosters and wrestler movesets.")
	lines.append("- Title-holder names are resolved within the title's promotion because wrestler IDs are promotion-local in the current content.")
	lines.append("- Baseline match-condition fields describe resource defaults, not the result of a played match.")
	lines.append("- Full movesets preserve their authored array order.")
	lines.append("")
	return "\n".join(lines)


func _generate_promotion_catalogue() -> String:
	var lines := PackedStringArray()
	lines.append("## Appendix F - Complete promotion catalogue")
	lines.append("")
	lines.append("The promotion catalogue is included because it is the authoritative ownership layer for wrestlers and titles.")
	lines.append("")
	for index in _promotions.size():
		var promotion := _promotions[index]
		lines.append("### F.%d %s (%s)" % [index + 1, _heading(promotion.promotion_name), _heading(promotion.promotion_initials)])
		lines.append("")
		lines.append("| Field | Authored value |")
		lines.append("|---|---|")
		lines.append(_row("Resource", _resource_link(promotion.resource_path)))
		lines.append(_row("UID", _resource_uid(promotion.resource_path)))
		lines.append(_row("Promotion ID", str(promotion.promotion_id)))
		lines.append(_row("Name", promotion.promotion_name))
		lines.append(_row("Initials", promotion.promotion_initials))
		lines.append(_row("Home", _promotion_home(promotion)))
		lines.append(_row("Preferred styles", _class_names(promotion.preferred_styles)))
		lines.append(_row("Independent promotion", _yes_no(promotion.is_indie)))
		lines.append(_row("Bank balance", _money(promotion.bank_balance)))
		lines.append(_row("Computed global popularity", _number(promotion.global_popularity)))
		lines.append(_row("North America popularity", _number(promotion.pop_north_america)))
		lines.append(_row("South America popularity", _number(promotion.pop_south_america)))
		lines.append(_row("Europe popularity", _number(promotion.pop_europe)))
		lines.append(_row("Asia popularity", _number(promotion.pop_asia)))
		lines.append(_row("Africa popularity", _number(promotion.pop_africa)))
		lines.append(_row("Oceania popularity", _number(promotion.pop_oceania)))
		lines.append(_row("Men's division", "%d wrestlers" % promotion.mens_division.size()))
		lines.append(_row("Women's division", "%d wrestlers" % promotion.womens_division.size()))
		lines.append(_row("Titles", "%d titles" % promotion.titles.size()))
		lines.append("")
		lines.append("**Men's division:** %s" % _wrestler_name_list(promotion.mens_division))
		lines.append("")
		lines.append("**Women's division:** %s" % _wrestler_name_list(promotion.womens_division))
		lines.append("")
		lines.append("**Titles:** %s" % _title_name_list(promotion.titles))
		lines.append("")
	return "\n".join(lines)


func _generate_title_catalogue() -> String:
	var lines := PackedStringArray()
	lines.append("## Appendix G - Complete title catalogue")
	lines.append("")
	lines.append("Every `TitleResource` is listed below with every serialized field and its resolved ownership/holder context.")
	lines.append("")
	var title_number := 0
	for promotion in _promotions:
		var promotion_titles: Array[TitleResource] = []
		for title in _titles:
			if title.promotion_id == promotion.promotion_id:
				promotion_titles.append(title)
		promotion_titles.sort_custom(_title_less)
		if promotion_titles.is_empty():
			continue
		lines.append("### %s (%s) titles" % [_heading(promotion.promotion_name), _heading(promotion.promotion_initials)])
		lines.append("")
		for title in promotion_titles:
			title_number += 1
			lines.append("#### G.%d %s" % [title_number, _heading(title.title_name)])
			lines.append("")
			lines.append("| Field | Authored/resolved value |")
			lines.append("|---|---|")
			lines.append(_row("Resource", _resource_link(title.resource_path)))
			lines.append(_row("UID", _resource_uid(title.resource_path)))
			lines.append(_row("Title name", title.title_name))
			lines.append(_row("Promotion ID", str(title.promotion_id)))
			lines.append(_row("Promotion", "%s (%s)" % [promotion.promotion_name, promotion.promotion_initials]))
			lines.append(_row("Gender division", _enum_name(title.gender, ["Invalid", "Male", "Female"])))
			lines.append(_row("Current holder ID", str(title.current_holder_id)))
			lines.append(_row("Current holder", _title_holder_label(title, title.current_holder_id)))
			lines.append(_row("Weeks held", str(title.weeks_held)))
			lines.append(_row("Previous holder IDs", _int_array(title.previous_holder_ids)))
			lines.append(_row("Previous holders", _previous_holder_names(title)))
			lines.append(_row("Current status", "Vacant" if title.current_holder_id <= 0 else "Active reign"))
			lines.append("")
	return "\n".join(lines)


func _generate_move_catalogue() -> String:
	var lines := PackedStringArray()
	lines.append("## Appendix H - Complete move catalogue")
	lines.append("")
	lines.append("All 626 move resources are listed individually. Target arrays are the authored damage candidates; targeting mode and default side determine how selectable/bilateral limbs resolve at runtime.")
	lines.append("")
	var move_number := 0
	for move_type in range(1, MOVE_TYPE_NAMES.size()):
		var type_moves: Array[MoveResource] = []
		for move in _moves:
			if move.move_type == move_type:
				type_moves.append(move)
		type_moves.sort_custom(_move_name_less)
		lines.append("### %s moves (%d)" % [MOVE_TYPE_NAMES[move_type], type_moves.size()])
		lines.append("")
		for move in type_moves:
			move_number += 1
			lines.append("#### H.%d %s" % [move_number, _heading(move.move_name)])
			lines.append("")
			lines.append("| Field | Authored/derived value |")
			lines.append("|---|---|")
			lines.append(_row("Resource", _resource_link(move.resource_path)))
			lines.append(_row("UID", _resource_uid(move.resource_path)))
			lines.append(_row("Move name", move.move_name))
			lines.append(_row("Move type/category", _enum_name(move.move_type, MOVE_TYPE_NAMES)))
			lines.append(_row("Impact", "%d / 10" % move.move_impact))
			lines.append(_row("Class preference", _class_names(move.class_preferrence)))
			lines.append(_row("Authored target parts", _target_names(move.move_target_parts)))
			lines.append(_row("Targeting mode", _enum_name(move.targeting_mode, TARGETING_MODE_NAMES)))
			lines.append(_row("Default side target", _enum_name(move.default_side_target, TARGET_NAMES)))
			lines.append(_row("Required attacker position", _enum_name(move.required_attacker_position, POSITION_NAMES)))
			lines.append(_row("Required target position", _enum_name(move.required_target_position, POSITION_NAMES)))
			lines.append(_row("Resulting attacker position", _enum_name(move.resulting_attacker_position, POSITION_NAMES)))
			lines.append(_row("Resulting target position", _enum_name(move.resulting_target_position, POSITION_NAMES)))
			lines.append(_row("Finisher", _yes_no(move.is_finisher)))
			lines.append(_row("Submission", _yes_no(move.is_submission)))
			lines.append(_row("Flash pin", _yes_no(move.is_flash_pin)))
			lines.append(_row("Strike", _yes_no(move.is_strike)))
			lines.append(_row("Strike weight", _enum_name(move.strike_weight, STRIKE_WEIGHT_NAMES) if move.is_strike else "Not applicable"))
			lines.append(_row("Interaction override", _enum_name(move.interaction_override, INTERACTION_NAMES)))
			var users: PackedStringArray = _move_users.get(move.resource_path, PackedStringArray())
			users.sort()
			lines.append(_row("Wrestler usage", "%d wrestler(s)" % users.size()))
			lines.append("")
			lines.append("**Used by:** %s" % (", ".join(users) if not users.is_empty() else "No authored wrestler moveset"))
			lines.append("")
	return "\n".join(lines)


func _generate_roster_catalogue() -> String:
	var lines := PackedStringArray()
	lines.append("## Appendix I - Complete wrestler roster and movesets")
	lines.append("")
	lines.append("Every wrestler is listed with all WrestlerResource fields, derived promotion/title relationships, and the complete authored moveset in its original array order.")
	lines.append("")
	var wrestler_number := 0
	for promotion in _promotions:
		lines.append("### %s (%s) roster" % [_heading(promotion.promotion_name), _heading(promotion.promotion_initials)])
		lines.append("")
		for division_name in ["Men's Division", "Women's Division"]:
			var division: Array[WrestlerResource] = []
			var source_division: Array[WrestlerResource] = promotion.mens_division if division_name == "Men's Division" else promotion.womens_division
			for wrestler in source_division:
				if wrestler != null:
					division.append(wrestler)
			division.sort_custom(_wrestler_less)
			lines.append("#### %s (%d)" % [division_name, division.size()])
			lines.append("")
			for wrestler in division:
				wrestler_number += 1
				lines.append("##### I.%d %s" % [wrestler_number, _heading(wrestler.wrestler_name)])
				lines.append("")
				lines.append(_wrestler_identity_table(wrestler, promotion, division_name))
				lines.append(_wrestler_attribute_table(wrestler))
				lines.append(_wrestler_popularity_table(wrestler))
				lines.append(_wrestler_condition_table(wrestler))
				lines.append(_wrestler_relationships(wrestler))
				lines.append(_wrestler_moveset(wrestler))
	return "\n".join(lines)


func _wrestler_identity_table(wrestler: WrestlerResource, promotion: PromotionResource, division: String) -> String:
	var lines := PackedStringArray()
	lines.append("**Identity and authored data**")
	lines.append("")
	lines.append("| Field | Authored/resolved value |")
	lines.append("|---|---|")
	lines.append(_row("Resource", _resource_link(wrestler.resource_path)))
	lines.append(_row("UID", _resource_uid(wrestler.resource_path)))
	lines.append(_row("Wrestler ID", str(wrestler.wrestler_id)))
	lines.append(_row("Name", wrestler.wrestler_name))
	lines.append(_row("Gimmick name", wrestler.gimmick_name if not wrestler.gimmick_name.is_empty() else "Empty"))
	lines.append(_row("Gimmick description", wrestler.gimmick_description if not wrestler.gimmick_description.is_empty() else "Empty"))
	lines.append(_row("Promotion", "%s (%s), ID %d" % [promotion.promotion_name, promotion.promotion_initials, promotion.promotion_id]))
	lines.append(_row("Division", division))
	lines.append(_row("Current titles", _current_titles(wrestler)))
	lines.append(_row("Class(es)", _class_names(wrestler.wrestler_class)))
	lines.append(_row("Gender", _enum_name(wrestler.wrestler_gender, GENDER_NAMES)))
	lines.append(_row("Disposition", _enum_name(wrestler.wrestler_disposition, DISPOSITION_NAMES)))
	lines.append(_row("Age", str(wrestler.Age)))
	lines.append(_row("Height", wrestler.wrestler_height))
	lines.append(_row("Weight", "%d lb" % wrestler.wrestler_weight))
	lines.append(_row("Birthplace", _wrestler_birthplace(wrestler)))
	lines.append(_row("Traits", _trait_summary(wrestler.wrestler_traits)))
	lines.append(_row("Current contract", _contract_summary(wrestler.current_contract)))
	lines.append(_row("Contract history", _contract_history_summary(wrestler.contract_history)))
	lines.append(_row("Bank balance", _money(wrestler.bank_balance)))
	lines.append("")
	return "\n".join(lines)


func _wrestler_attribute_table(wrestler: WrestlerResource) -> String:
	var lines := PackedStringArray()
	lines.append("**Attributes**")
	lines.append("")
	lines.append("| Strength | Speed | Stamina | Skill | Striking | Charisma |")
	lines.append("|---:|---:|---:|---:|---:|---:|")
	lines.append("| %s | %s | %s | %s | %s | %s |" % [_number(wrestler.strength), _number(wrestler.speed), _number(wrestler.stamina), _number(wrestler.skill), _number(wrestler.striking), _number(wrestler.charisma)])
	lines.append("")
	return "\n".join(lines)


func _wrestler_popularity_table(wrestler: WrestlerResource) -> String:
	var lines := PackedStringArray()
	lines.append("**Popularity**")
	lines.append("")
	lines.append("| Global (computed) | North America | South America | Europe | Asia | Africa | Oceania |")
	lines.append("|---:|---:|---:|---:|---:|---:|---:|")
	lines.append("| %s | %s | %s | %s | %s | %s | %s |" % [_number(wrestler.global_popularity), _number(wrestler.pop_north_america), _number(wrestler.pop_south_america), _number(wrestler.pop_europe), _number(wrestler.pop_asia), _number(wrestler.pop_africa), _number(wrestler.pop_oceania)])
	lines.append("")
	return "\n".join(lines)


func _wrestler_condition_table(wrestler: WrestlerResource) -> String:
	var lines := PackedStringArray()
	lines.append("**Serialized baseline match condition**")
	lines.append("")
	lines.append("| Fatigue | Head HP | Body HP | Left Arm HP | Right Arm HP | Left Leg HP | Right Leg HP | Momentum | Runtime start position |")
	lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|---|")
	lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [_number(wrestler.fatigue), _number(wrestler.head_hp), _number(wrestler.body_hp), _number(wrestler.left_arm_hp), _number(wrestler.right_arm_hp), _number(wrestler.left_leg_hp), _number(wrestler.right_leg_hp), _number(wrestler.momentum), _enum_name(wrestler.position, POSITION_NAMES)])
	lines.append("")
	return "\n".join(lines)


func _wrestler_relationships(wrestler: WrestlerResource) -> String:
	var finishers := 0
	var submissions := 0
	var strikes := 0
	var flash_pins := 0
	var type_counts: Dictionary = {}
	for move in wrestler.move_set:
		if move == null:
			continue
		finishers += 1 if move.is_finisher else 0
		submissions += 1 if move.is_submission else 0
		strikes += 1 if move.is_strike else 0
		flash_pins += 1 if move.is_flash_pin else 0
		type_counts[move.move_type] = int(type_counts.get(move.move_type, 0)) + 1
	var breakdown := PackedStringArray()
	for type_id in range(1, MOVE_TYPE_NAMES.size()):
		if type_counts.has(type_id):
			breakdown.append("%s %d" % [MOVE_TYPE_NAMES[type_id], type_counts[type_id]])
	var lines := PackedStringArray()
	lines.append("**Moveset summary:** %d moves; %d finishers; %d submissions; %d strikes; %d explicit flash pins." % [wrestler.move_set.size(), finishers, submissions, strikes, flash_pins])
	lines.append("")
	lines.append("**Category distribution:** %s" % (", ".join(breakdown) if not breakdown.is_empty() else "No moves"))
	lines.append("")
	return "\n".join(lines)


func _wrestler_moveset(wrestler: WrestlerResource) -> String:
	var lines := PackedStringArray()
	lines.append("**Complete authored moveset**")
	lines.append("")
	lines.append("| Slot | Move | Type | Impact | Flags | Targets | Targeting | Resource |")
	lines.append("|---:|---|---|---:|---|---|---|---|")
	for index in wrestler.move_set.size():
		var move := wrestler.move_set[index]
		if move == null:
			lines.append("| %d | Missing/null resource | - | - | - | - | - | - |" % (index + 1))
			continue
		lines.append("| %d | %s | %s | %d | %s | %s | %s | %s |" % [
			index + 1,
			_md(move.move_name),
			_md(_enum_name(move.move_type, MOVE_TYPE_NAMES)),
			move.move_impact,
			_md(_move_flags(move)),
			_md(_target_names(move.move_target_parts)),
			_md(_enum_name(move.targeting_mode, TARGETING_MODE_NAMES)),
			_resource_link(move.resource_path),
		])
	if wrestler.move_set.is_empty():
		lines.append("| - | No authored moves | - | - | - | - | - | - |")
	lines.append("")
	return "\n".join(lines)


func _move_flags(move: MoveResource) -> String:
	var flags := PackedStringArray()
	if move.is_finisher:
		flags.append("Finisher")
	if move.is_submission:
		flags.append("Submission")
	if move.is_flash_pin:
		flags.append("Flash Pin")
	if move.is_strike:
		flags.append("%s Strike" % _enum_name(move.strike_weight, STRIKE_WEIGHT_NAMES))
	if move.interaction_override != MoveResource.InteractionOverride.AUTO:
		flags.append(_enum_name(move.interaction_override, INTERACTION_NAMES))
	return ", ".join(flags) if not flags.is_empty() else "Standard"


func _promotion_less(a: PromotionResource, b: PromotionResource) -> bool:
	return a.promotion_initials.naturalnocasecmp_to(b.promotion_initials) < 0


func _title_less(a: TitleResource, b: TitleResource) -> bool:
	if a.promotion_id != b.promotion_id:
		return a.promotion_id < b.promotion_id
	return a.title_name.naturalnocasecmp_to(b.title_name) < 0


func _wrestler_less(a: WrestlerResource, b: WrestlerResource) -> bool:
	return a.wrestler_name.naturalnocasecmp_to(b.wrestler_name) < 0


func _move_less(a: MoveResource, b: MoveResource) -> bool:
	if a.move_type != b.move_type:
		return a.move_type < b.move_type
	return a.move_name.naturalnocasecmp_to(b.move_name) < 0


func _move_name_less(a: MoveResource, b: MoveResource) -> bool:
	return a.move_name.naturalnocasecmp_to(b.move_name) < 0


func _enum_name(value: int, names: Array) -> String:
	if value >= 0 and value < names.size():
		return str(names[value])
	return "Unknown (%d)" % value


func _class_names(values: Array) -> String:
	var names := PackedStringArray()
	for value in values:
		names.append(_enum_name(int(value), CLASS_NAMES))
	return ", ".join(names) if not names.is_empty() else "None"


func _target_names(values: Array) -> String:
	var names := PackedStringArray()
	for value in values:
		names.append(_enum_name(int(value), TARGET_NAMES))
	return ", ".join(names) if not names.is_empty() else "None"


func _promotion_home(promotion: PromotionResource) -> String:
	return "%s - %s" % [_enum_name(promotion.home_region, REGION_NAMES), _country_for_region(promotion.home_region, promotion)]


func _wrestler_birthplace(wrestler: WrestlerResource) -> String:
	return "%s - %s" % [_enum_name(wrestler.birthplace, REGION_NAMES), _country_for_region(wrestler.birthplace, wrestler)]


func _country_for_region(region: int, source: Object) -> String:
	match region:
		1:
			return _enum_name(source.north_american_country, ["USA", "Canada", "Mexico", "Other"])
		2:
			return _enum_name(source.south_american_country, ["Brazil", "Argentina", "Chile", "Other"])
		3:
			return _enum_name(source.asia_country, ["Japan", "China", "South Korea", "India", "Other"])
		4:
			return _enum_name(source.africa_country, ["Ghana", "Nigeria", "Egypt", "South Africa", "Other"])
		5:
			return _enum_name(source.oceania_country, ["Australia", "New Zealand", "Samoa", "Other"])
		6:
			return _enum_name(source.europe_country, ["UK", "Germany", "France", "Italy", "Spain", "Other"])
	return "Not Set"


func _wrestler_name_list(values: Array) -> String:
	var names := PackedStringArray()
	for wrestler in values:
		if wrestler != null:
			names.append(wrestler.wrestler_name)
	return _md(", ".join(names)) if not names.is_empty() else "None"


func _title_name_list(values: Array) -> String:
	var names := PackedStringArray()
	for title in values:
		if title != null:
			names.append(title.title_name)
	return _md(", ".join(names)) if not names.is_empty() else "None"


func _wrestler_reference(wrestler: WrestlerResource) -> String:
	var promotion: PromotionResource = _promotion_by_wrestler_path.get(wrestler.resource_path)
	if promotion != null:
		return "%s (%s, ID %d)" % [wrestler.wrestler_name, promotion.promotion_initials, wrestler.wrestler_id]
	return "%s (Unassigned, ID %d)" % [wrestler.wrestler_name, wrestler.wrestler_id]


func _find_title_holder(title: TitleResource, wrestler_id: int) -> WrestlerResource:
	var roster: Dictionary = _wrestler_by_promotion_and_id.get(title.promotion_id, {})
	return roster.get(wrestler_id) as WrestlerResource


func _title_holder_label(title: TitleResource, wrestler_id: int) -> String:
	if wrestler_id <= 0:
		return "Vacant / none assigned"
	var holder := _find_title_holder(title, wrestler_id)
	return "%s (ID %d)" % [holder.wrestler_name, wrestler_id] if holder != null else "Unresolved wrestler ID %d" % wrestler_id


func _previous_holder_names(title: TitleResource) -> String:
	if title.previous_holder_ids.is_empty():
		return "None"
	var names := PackedStringArray()
	for wrestler_id in title.previous_holder_ids:
		names.append(_title_holder_label(title, wrestler_id))
	return ", ".join(names)


func _current_titles(wrestler: WrestlerResource) -> String:
	var titles: PackedStringArray = _titles_by_wrestler_path.get(wrestler.resource_path, PackedStringArray())
	return ", ".join(titles) if not titles.is_empty() else "None"


func _trait_summary(traits: Array) -> String:
	if traits.is_empty():
		return "None"
	var summaries := PackedStringArray()
	for trait_resource in traits:
		if trait_resource == null:
			summaries.append("Missing/null trait")
			continue
		var flags := PackedStringArray()
		for property_name in ["refuses_to_job", "demands_creative_control", "locker_room_cancer", "locker_room_leader", "carry_artist", "stiff_worker", "safe_worker", "mainstream_draw", "cult_following"]:
			if bool(trait_resource.get(property_name)):
				flags.append(property_name.replace("_", " ").capitalize())
		var summary := "%s: %s" % [trait_resource.trait_name, trait_resource.trait_description]
		if not flags.is_empty():
			summary += " [%s]" % ", ".join(flags)
		summaries.append(summary)
	return "; ".join(summaries)


func _contract_summary(contract: ContractResource) -> String:
	if contract == null:
		return "None"
	var clauses := PackedStringArray()
	if contract.clause_creative_control:
		clauses.append("Creative control")
	if contract.clause_iron_clad:
		clauses.append("Iron clad")
	if contract.clause_title_shot:
		clauses.append("Title shot by week %s" % _number(contract.title_shot_deadline_week))
	if contract.clause_medical_care:
		clauses.append("Medical care")
	return "Wrestler ID %d; promotion ID %d; %s weeks; salary %s; %s to %s; clauses: %s" % [contract.wrestler_id, contract.promotion_id, _number(contract.length_weeks), _money(contract.salary), contract.start_date, contract.end_date, ", ".join(clauses) if not clauses.is_empty() else "None"]


func _contract_history_summary(contracts: Array) -> String:
	if contracts.is_empty():
		return "None"
	var summaries := PackedStringArray()
	for contract in contracts:
		summaries.append(_contract_summary(contract))
	return "<br>".join(summaries)


func _resource_link(path: String) -> String:
	return "`%s`" % _md(path)


func _resource_uid(path: String) -> String:
	var uid := ResourceLoader.get_resource_uid(path)
	return ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else "None"


func _row(label: String, value: String) -> String:
	return "| %s | %s |" % [_md(label), _md(value)]


func _md(value: Variant) -> String:
	return str(value).replace("|", "\\|").replace("\r\n", "<br>").replace("\n", "<br>")


func _heading(value: String) -> String:
	return value.replace("\n", " ").strip_edges()


func _yes_no(value: bool) -> String:
	return "Yes" if value else "No"


func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value


func _money(value: float) -> String:
	return "$%s" % _number(value)


func _int_array(values: Array) -> String:
	if values.is_empty():
		return "None"
	var strings := PackedStringArray()
	for value in values:
		strings.append(str(value))
	return ", ".join(strings)
