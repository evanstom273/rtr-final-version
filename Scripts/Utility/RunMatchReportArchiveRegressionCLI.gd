extends SceneTree


func _initialize() -> void:
	var failures: Array[String] = []
	_test_rating(failures)
	_test_scenes(failures)
	_test_archive(failures)
	if failures.is_empty():
		print("MATCH_REPORT_ARCHIVE_REGRESSION: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("MATCH_REPORT_ARCHIVE_REGRESSION: %s" % failure)
	quit(1)


func _test_rating(failures: Array[String]) -> void:
	var report := _sample_report()
	var first: Dictionary = MatchRatingCalculator.calculate(report, report.story_events)
	var second: Dictionary = MatchRatingCalculator.calculate(report, report.story_events)
	if first != second:
		failures.append("Rating calculation is not deterministic.")
	var stars := float(first.get("stars", -1.0))
	if stars < 0.0 or stars > 5.0 or not is_equal_approx(fmod(stars, 0.25), 0.0):
		failures.append("Rating is not a 0-5 quarter-star value: %s" % stars)
	var dull := report.duplicate(true)
	dull.duration_seconds = 2700
	dull.final_time = "45:00"
	dull.player.moves_landed = 2
	dull.ai.moves_landed = 1
	dull.player.move_variety = 1
	dull.ai.move_variety = 1
	dull.player.setup_actions = 25
	dull.ai.setup_actions = 24
	dull.story_events = []
	var dull_rating: Dictionary = MatchRatingCalculator.calculate(dull, [])
	if float(dull_rating.get("stars", 5.0)) >= stars:
		failures.append("A long inactive fixture rated at least as highly as the dramatic fixture.")


func _test_scenes(failures: Array[String]) -> void:
	for path in [
		"res://Scenes/Match/match_report_screen.tscn",
		"res://Scenes/UI/match_report_archive_screen.tscn",
	]:
		var scene := load(path) as PackedScene
		if scene == null:
			failures.append("Could not load %s." % path)
			continue
		var instance := scene.instantiate()
		if instance == null:
			failures.append("Could not instantiate %s." % path)
		else:
			instance.free()


func _test_archive(failures: Array[String]) -> void:
	var archive = preload("res://Scripts/Match/match_report_archive.gd").new()
	archive.configure_storage_root("res://.godot/match_archive_regression_data")
	root.add_child(archive)
	var report := _sample_report()
	report.report_id = "regression_match_report"
	report.rating = MatchRatingCalculator.calculate(report, report.story_events)
	report.rating_highlights = report.rating.highlights
	report.export_text = "Regression report\n"
	var saved: Dictionary = archive.save_completed_match(report)
	if not bool(saved.get("ok", false)):
		failures.append("Archive save failed: %s" % saved.get("error", "unknown error"))
		return
	var loaded: Dictionary = archive.load_report("regression_match_report")
	if loaded.is_empty():
		failures.append("Saved report could not be loaded.")
	var queried: Array = archive.query_index({"wrestler_id": "wrestler:a"}, "newest")
	if queried.is_empty():
		failures.append("Wrestler filtering did not find the saved report.")
	var history: Dictionary = archive.get_wrestler_history("wrestler:a")
	if int(history.get("matches", 0)) < 1 or int(history.get("wins", 0)) < 1:
		failures.append("Wrestler history did not aggregate the saved win.")
	archive.queue_free()


func _sample_report() -> Dictionary:
	return {
		"schema_version": 1,
		"report_id": "",
		"completed_at_utc": "2026-07-23T12:00:00Z",
		"date_display": "2026-07-23 13:00",
		"subtitle": "Alpha vs. Beta",
		"participants": [
			{"id": "wrestler:a", "name": "Alpha"},
			{"id": "wrestler:b", "name": "Beta"},
		],
		"winner": "Alpha",
		"loser": "Beta",
		"winner_id": "wrestler:a",
		"loser_id": "wrestler:b",
		"duration_seconds": 720,
		"final_time": "12:00",
		"match_type_id": "singles",
		"match_type": "Singles",
		"stipulation_id": "standard",
		"stipulation": "Standard",
		"result": "Pinfall",
		"finish_move": "Example Finisher",
		"player": {
			"moves_landed": 15, "damage_dealt": 72.0, "move_variety": 13,
			"reversals": 4, "kickouts": 2, "submission_escapes": 1,
			"submission_struggle_seconds": 9.0, "signatures_landed": 1,
			"finisher_attempts": 2, "finishers_landed": 1, "setup_actions": 4,
		},
		"ai": {
			"moves_landed": 13, "damage_dealt": 65.0, "move_variety": 11,
			"reversals": 3, "kickouts": 2, "submission_escapes": 0,
			"submission_struggle_seconds": 9.0, "signatures_landed": 1,
			"finisher_attempts": 1, "finishers_landed": 1, "setup_actions": 4,
		},
		"story_events": [
			{"type": "control_swing"}, {"type": "control_swing"},
			{"type": "control_swing"}, {"type": "near_fall"},
			{"type": "near_fall_late"}, {"type": "finisher_landed"},
		],
		"log_lines": ["00:00 — The bell rings.", "12:00 — THREE!"],
	}
