extends Node

const SCHEMA_VERSION := 1
const ARCHIVE_DIRECTORY := "user://match_history"
const REPORTS_DIRECTORY := "user://match_history/reports"
const INDEX_PATH := "user://match_history/index.json"

var _index: Array[Dictionary] = []
var _loaded := false
var _archive_directory := ARCHIVE_DIRECTORY
var _reports_directory := REPORTS_DIRECTORY
var _index_path := INDEX_PATH


func _ready() -> void:
	_ensure_loaded()


func configure_storage_root(root_path: String) -> void:
	if _loaded or root_path.strip_edges().is_empty():
		return
	_archive_directory = root_path.trim_suffix("/")
	_reports_directory = "%s/reports" % _archive_directory
	_index_path = "%s/index.json" % _archive_directory


func save_completed_match(report: Dictionary) -> Dictionary:
	_ensure_loaded()
	var stored := report.duplicate(true)
	var report_id := str(stored.get("report_id", "")).strip_edges()
	if report_id.is_empty():
		report_id = _new_report_id()
	stored["schema_version"] = SCHEMA_VERSION
	stored["report_id"] = report_id
	if str(stored.get("completed_at_utc", "")).is_empty():
		stored["completed_at_utc"] = Time.get_datetime_string_from_system(true, true)
	var report_path := "%s/%s.json" % [_reports_directory, report_id]
	if FileAccess.file_exists(report_path):
		return {"ok": true, "report_id": report_id, "path": report_path, "duplicate": true}
	if not _ensure_directories():
		return {"ok": false, "error": "Could not create the match history directory."}
	if not _write_json_atomic(report_path, stored):
		return {"ok": false, "error": "Could not save the completed match report."}
	var entry := _index_entry_from_report(stored)
	_index.append(entry)
	if not _write_json_atomic(_index_path, {"schema_version": SCHEMA_VERSION, "entries": _index}):
		_index.pop_back()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(report_path))
		return {"ok": false, "error": "The report was written, but the archive index could not be updated."}
	return {"ok": true, "report_id": report_id, "path": report_path, "duplicate": false}


func query_index(filters: Dictionary = {}, sort_mode: String = "newest") -> Array:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	var search := str(filters.get("search", "")).strip_edges().to_lower()
	var wrestler_id := str(filters.get("wrestler_id", ""))
	var winner_id := str(filters.get("winner_id", ""))
	var loser_id := str(filters.get("loser_id", ""))
	var match_type := str(filters.get("match_type", ""))
	var stipulation := str(filters.get("stipulation", ""))
	var minimum_rating := float(filters.get("minimum_rating", 0.0))
	var maximum_rating := float(filters.get("maximum_rating", 5.0))
	for entry in _index:
		var stars := float(entry.get("stars", 0.0))
		if stars < minimum_rating or stars > maximum_rating:
			continue
		var participant_ids: Array = entry.get("participant_ids", [])
		if not wrestler_id.is_empty() and wrestler_id not in participant_ids:
			continue
		if not winner_id.is_empty() and str(entry.get("winner_id", "")) != winner_id:
			continue
		if not loser_id.is_empty() and str(entry.get("loser_id", "")) != loser_id:
			continue
		if not match_type.is_empty() and str(entry.get("match_type_id", "")) != match_type:
			continue
		if not stipulation.is_empty() and str(entry.get("stipulation_id", "")) != stipulation:
			continue
		if not search.is_empty() and search not in str(entry.get("search_text", "")).to_lower():
			continue
		result.append(entry.duplicate(true))
	_sort_entries(result, sort_mode)
	return result


func load_report(report_id: String) -> Dictionary:
	if report_id.strip_edges().is_empty():
		return {}
	var path := "%s/%s.json" % [_reports_directory, report_id]
	return _read_json_dictionary(path)


func rebuild_index() -> Dictionary:
	_index.clear()
	if not _ensure_directories():
		return {"ok": false, "error": "Could not open the match history directory."}
	var directory := DirAccess.open(_reports_directory)
	if directory == null:
		return {"ok": false, "error": "Could not scan saved match reports."}
	directory.list_dir_begin()
	var file_name := directory.get_next()
	var rejected := 0
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var report := _read_json_dictionary("%s/%s" % [_reports_directory, file_name])
			if report.is_empty() or str(report.get("report_id", "")).is_empty():
				rejected += 1
			else:
				_index.append(_index_entry_from_report(report))
		file_name = directory.get_next()
	directory.list_dir_end()
	_sort_entries(_index, "newest")
	var ok := _write_json_atomic(_index_path, {"schema_version": SCHEMA_VERSION, "entries": _index})
	return {"ok": ok, "entries": _index.size(), "rejected": rejected}


func get_wrestler_history(participant_id: String) -> Dictionary:
	_ensure_loaded()
	var matches: Array[Dictionary] = []
	for entry in _index:
		if participant_id in (entry.get("participant_ids", []) as Array):
			matches.append(entry)
	if matches.is_empty():
		return {
			"participant_id": participant_id, "name": "Unknown Wrestler", "matches": 0,
			"wins": 0, "losses": 0, "draws": 0, "win_percentage": 0.0,
			"average_rating": 0.0, "total_time_seconds": 0,
		}
	var wins := 0
	var losses := 0
	var draws := 0
	var rating_total := 0.0
	var time_total := 0
	var opponent_counts: Dictionary = {}
	var opponent_names: Dictionary = {}
	var wrestler_name := participant_id
	for entry in matches:
		rating_total += float(entry.get("stars", 0.0))
		time_total += int(entry.get("duration_seconds", 0))
		if str(entry.get("winner_id", "")) == participant_id:
			wins += 1
		elif str(entry.get("loser_id", "")) == participant_id:
			losses += 1
		else:
			draws += 1
		var ids: Array = entry.get("participant_ids", [])
		var names: Array = entry.get("participant_names", [])
		for index in ids.size():
			if str(ids[index]) == participant_id:
				if index < names.size():
					wrestler_name = str(names[index])
			else:
				var opponent_id := str(ids[index])
				opponent_counts[opponent_id] = int(opponent_counts.get(opponent_id, 0)) + 1
				opponent_names[opponent_id] = str(names[index]) if index < names.size() else opponent_id
	var highest := matches[0]
	var longest := matches[0]
	var shortest := matches[0]
	for entry in matches:
		if float(entry.get("stars", 0.0)) > float(highest.get("stars", 0.0)):
			highest = entry
		if int(entry.get("duration_seconds", 0)) > int(longest.get("duration_seconds", 0)):
			longest = entry
		if int(entry.get("duration_seconds", 0)) < int(shortest.get("duration_seconds", 0)):
			shortest = entry
	var most_common_id := ""
	for candidate in opponent_counts:
		if (
			most_common_id.is_empty()
			or int(opponent_counts[candidate]) > int(opponent_counts[most_common_id])
			or (
				int(opponent_counts[candidate]) == int(opponent_counts[most_common_id])
				and str(opponent_names[candidate]).naturalnocasecmp_to(str(opponent_names[most_common_id])) < 0
			)
		):
			most_common_id = str(candidate)
	return {
		"participant_id": participant_id,
		"name": wrestler_name,
		"matches": matches.size(),
		"wins": wins,
		"losses": losses,
		"draws": draws,
		"win_percentage": float(wins) / float(matches.size()) * 100.0,
		"average_rating": rating_total / float(matches.size()),
		"highest_rated": highest.duplicate(true),
		"longest": longest.duplicate(true),
		"shortest": shortest.duplicate(true),
		"most_common_opponent": str(opponent_names.get(most_common_id, "None")),
		"most_common_opponent_id": most_common_id,
		"total_time_seconds": time_total,
	}


func get_filter_catalogue() -> Dictionary:
	_ensure_loaded()
	var participants: Dictionary = {}
	var match_types: Dictionary = {}
	var stipulations: Dictionary = {}
	for entry in _index:
		var ids: Array = entry.get("participant_ids", [])
		var names: Array = entry.get("participant_names", [])
		for index in ids.size():
			participants[str(ids[index])] = str(names[index]) if index < names.size() else str(ids[index])
		match_types[str(entry.get("match_type_id", "singles"))] = str(entry.get("match_type", "Singles"))
		stipulations[str(entry.get("stipulation_id", "standard"))] = str(entry.get("stipulation", "Standard"))
	return {"participants": participants, "match_types": match_types, "stipulations": stipulations}


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not _ensure_directories():
		return
	var index_data := _read_json_dictionary(_index_path)
	var raw_entries: Array = index_data.get("entries", [])
	if index_data.is_empty():
		rebuild_index()
		return
	for raw_entry in raw_entries:
		if raw_entry is Dictionary:
			_index.append((raw_entry as Dictionary).duplicate(true))


func _ensure_directories() -> bool:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_reports_directory))
	return error == OK or error == ERR_ALREADY_EXISTS


func _write_json_atomic(path: String, value: Variant) -> bool:
	var temporary_path := "%s.tmp" % path
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", false))
	file.close()
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return false
	var rename_error := DirAccess.rename_absolute(absolute_temporary, absolute_path)
	return rename_error == OK


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _new_report_id() -> String:
	var timestamp := Time.get_datetime_string_from_system(true, true).replace("-", "").replace(":", "").replace("T", "_")
	return "%s_%d" % [timestamp, Time.get_ticks_usec()]


func _index_entry_from_report(report: Dictionary) -> Dictionary:
	var participants: Array = report.get("participants", [])
	var participant_ids: Array[String] = []
	var participant_names: Array[String] = []
	for raw_participant in participants:
		if raw_participant is Dictionary:
			var participant := raw_participant as Dictionary
			participant_ids.append(str(participant.get("id", "")))
			participant_names.append(str(participant.get("name", "Unknown")))
	var winner := str(report.get("winner", "No Winner"))
	var loser := str(report.get("loser", "None"))
	var search_text := " ".join(PackedStringArray([
		" ".join(PackedStringArray(participant_names)),
		winner,
		loser,
		str(report.get("match_type", "Singles")),
		str(report.get("stipulation", "Standard")),
		str(report.get("result", "")),
		str(report.get("finish_move", "")),
		str(report.get("completed_at_utc", "")),
	]))
	var rating: Dictionary = report.get("rating", {})
	return {
		"report_id": str(report.get("report_id", "")),
		"completed_at_utc": str(report.get("completed_at_utc", "")),
		"date_display": str(report.get("date_display", "")),
		"participant_ids": participant_ids,
		"participant_names": participant_names,
		"winner": winner,
		"loser": loser,
		"winner_id": str(report.get("winner_id", "")),
		"loser_id": str(report.get("loser_id", "")),
		"duration_seconds": int(report.get("duration_seconds", 0)),
		"final_time": str(report.get("final_time", "00:00")),
		"match_type_id": str(report.get("match_type_id", "singles")),
		"match_type": str(report.get("match_type", "Singles")),
		"stipulation_id": str(report.get("stipulation_id", "standard")),
		"stipulation": str(report.get("stipulation", "Standard")),
		"result": str(report.get("result", "")),
		"finish_move": str(report.get("finish_move", "")),
		"stars": float(rating.get("stars", 0.0)),
		"search_text": search_text,
	}


func _sort_entries(entries: Array, sort_mode: String) -> void:
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		match sort_mode:
			"oldest":
				return str(left.get("completed_at_utc", "")) < str(right.get("completed_at_utc", ""))
			"highest":
				if not is_equal_approx(float(left.get("stars", 0.0)), float(right.get("stars", 0.0))):
					return float(left.get("stars", 0.0)) > float(right.get("stars", 0.0))
			"lowest":
				if not is_equal_approx(float(left.get("stars", 0.0)), float(right.get("stars", 0.0))):
					return float(left.get("stars", 0.0)) < float(right.get("stars", 0.0))
			"longest":
				if int(left.get("duration_seconds", 0)) != int(right.get("duration_seconds", 0)):
					return int(left.get("duration_seconds", 0)) > int(right.get("duration_seconds", 0))
			"shortest":
				if int(left.get("duration_seconds", 0)) != int(right.get("duration_seconds", 0)):
					return int(left.get("duration_seconds", 0)) < int(right.get("duration_seconds", 0))
		return str(left.get("completed_at_utc", "")) > str(right.get("completed_at_utc", ""))
	)
