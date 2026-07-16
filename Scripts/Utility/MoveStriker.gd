@tool
extends EditorScript
class_name MoveStrikerStyleTagFixer

const MOVE_ROOT: String = "res://Moves"


func _run() -> void:
	var move_paths: Array[String] = []
	_collect_move_paths(MOVE_ROOT, move_paths)

	if move_paths.is_empty():
		push_error("No move resources found under %s" % MOVE_ROOT)
		return

	var changed_count: int = 0
	var checked_count: int = 0

	for move_path: String in move_paths:
		var res: Resource = load(move_path)
		if not (res is MoveResource):
			continue

		var move: MoveResource = res as MoveResource
		checked_count += 1

		if _should_add_striker_style(move):
			if not move.class_preferrence.has(WrestlerResource.WrestlerClass.STRIKER):
				move.class_preferrence.append(WrestlerResource.WrestlerClass.STRIKER)

				var save_result: int = ResourceSaver.save(move, move_path)
				if save_result == OK:
					changed_count += 1
					print("Added STRIKER style tag: %s" % move.move_name)
				else:
					push_warning("Failed to save %s" % move_path)

	print("")
	print("========================================")
	print("Move striker-style tag fix complete")
	print("Checked: %s" % str(checked_count))
	print("Changed: %s" % str(changed_count))
	print("========================================")


func _should_add_striker_style(move: MoveResource) -> bool:
	if move == null:
		return false

	if move.is_strike:
		return false

	if move.is_finisher:
		return false

	if move.is_submission:
		return _is_striker_submission_name(move.move_name)

	return _is_striker_non_strike_name(move.move_name)


func _is_striker_non_strike_name(move_name: String) -> bool:
	var n: String = move_name.strip_edges().to_lower()

	var exact_names: Array[String] = [
		"arm drag",
		"hip toss",
		"snapmare",
		"victory roll",
		"schoolboy roll",
		"o'connor roll",

		"ddt",
		"reverse ddt",
		"running ddt",
		"rebound ddt",
		"rebound floatover ddt",
		"rebound swinging ddt",
		"running tornado ddt",
		"running tornado reverse ddt",
		"corner tornado ddt",

		"sto",
		"reverse sto",
		"running sto",
		"running reverse sto",
		"swinging reverse sto",

		"front facebuster",
		"face crusher",
		"running facebuster",
		"rebound facebuster",
		"corner facebuster",

		"swinging neckbreaker",
		"running neckbreaker",
		"rebound neckbreaker",
		"corner neckbreaker",

		"russian leg sweep",
		"dragon screw",
		"rebound dragon screw",

		"rear mat return",
		"rear waistlock takedown",
		"sleeper hold takedown",
		"rear chinlock takeover",

		"running drop toe hold",
		"rebound drop toe hold",
		"corner drop toe hold",

		"running snapmare",
		"corner snapmare",

		"running crucifix driver",
		"running rolling crucifix",
		"rebound sunset flip",
		"rebound victory roll",

		"rebound arm drag",
		"rebound bulldog",
		"corner bulldog",
		"corner arm drag",

		"running bulldog",
		"running wheelbarrow facebuster",
		"rebound wheelbarrow facebuster"
	]

	if exact_names.has(n):
		return true

	var striker_keywords: Array[String] = [
		"ddt",
		"sto",
		"facebuster",
		"neckbreaker",
		"snapmare",
		"drop toe hold",
		"arm drag",
		"hip toss",
		"victory roll",
		"schoolboy",
		"o'connor",
		"rear mat",
		"waistlock takedown",
		"dragon screw",
		"bulldog",
		"crucifix",
		"sunset flip"
	]

	for keyword: String in striker_keywords:
		if n.contains(keyword):
			return true

	return false


func _is_striker_submission_name(move_name: String) -> bool:
	var n: String = move_name.strip_edges().to_lower()

	var exact_names: Array[String] = [
		"armbar",
		"triangle hold",
		"side headlock",
		"grounded headlock",
		"grounded front facelock",
		"front facelock",
		"body scissors",
		"sleeper hold takedown",
		"rear naked choke takedown",
		"rear chinlock takeover"
	]

	if exact_names.has(n):
		return true

	var allowed_keywords: Array[String] = [
		"armbar",
		"triangle",
		"headlock",
		"front facelock",
		"sleeper",
		"chinlock",
		"body scissors"
	]

	for keyword: String in allowed_keywords:
		if n.contains(keyword):
			return true

	return false


func _collect_move_paths(dir_path: String, results: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("Could not open move directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var item_name: String = dir.get_next()

	while item_name != "":
		if item_name.begins_with("."):
			item_name = dir.get_next()
			continue

		var full_path: String = dir_path.path_join(item_name)

		if dir.current_is_dir():
			_collect_move_paths(full_path, results)
		elif item_name.get_extension().to_lower() == "tres":
			var res: Resource = load(full_path)
			if res is MoveResource:
				results.append(full_path)

		item_name = dir.get_next()

	dir.list_dir_end()
