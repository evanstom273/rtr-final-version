extends Control

@export_range(2, 50) var segments: int = 20:
	set(value):
		segments = max(2, value)
		queue_redraw()

@export var line_color: Color = Color(0, 0, 0, 0.28):
	set(value):
		line_color = value
		queue_redraw()

@export_range(1.0, 3.0, 0.5) var line_width: float = 1.0:
	set(value):
		line_width = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return

	for i in range(1, segments):
		var x := (w * float(i)) / float(segments)
		draw_line(Vector2(x, 0.0), Vector2(x, h), line_color, line_width)
