extends Node2D
class_name MatchPitch

@export var field_size := GameSettings.FIELD_SIZE
@export var goal_mouth_height := GameSettings.GOAL_MOUTH_HEIGHT
@export var wall_thickness := GameSettings.WALL_THICKNESS
@export var goal_depth := GameSettings.GOAL_DEPTH

@onready var walls_root: Node2D = $Walls


func _ready() -> void:
	_rebuild_walls()
	queue_redraw()


func _draw() -> void:
	var field_rect := Rect2(-field_size * 0.5, field_size)
	var outer_rect := field_rect.grow(84.0)
	draw_rect(outer_rect, GameSettings.COLOR_FIELD_OUTER)
	draw_rect(field_rect, GameSettings.COLOR_FIELD_LIGHT)

	var stripe_count := 10
	var stripe_width := field_size.x / float(stripe_count)
	for i in range(-2, stripe_count + 2):
		var x0 := field_rect.position.x + float(i) * stripe_width
		var points := PackedVector2Array([
			Vector2(x0, field_rect.position.y),
			Vector2(x0 + stripe_width * 0.62, field_rect.position.y),
			Vector2(x0 + stripe_width * 1.16, field_rect.position.y + field_size.y),
			Vector2(x0 + stripe_width * 0.54, field_rect.position.y + field_size.y)
		])
		draw_colored_polygon(points, GameSettings.COLOR_FIELD_DARK if i % 2 == 0 else GameSettings.COLOR_FIELD_LIGHT)

	draw_rect(field_rect, GameSettings.COLOR_FIELD_LINE, false, 7.0)
	draw_line(Vector2(0.0, -field_size.y * 0.5), Vector2(0.0, field_size.y * 0.5), GameSettings.COLOR_FIELD_LINE, 5.0)
	draw_arc(Vector2.ZERO, 118.0, 0.0, TAU, 96, GameSettings.COLOR_FIELD_LINE, 5.0)
	draw_circle(Vector2.ZERO, 6.0, GameSettings.COLOR_FIELD_LINE)

	var side_x := field_size.x * 0.5
	var mouth_half := goal_mouth_height * 0.5
	draw_line(Vector2(-side_x, -field_size.y * 0.5), Vector2(-side_x, -mouth_half), GameSettings.COLOR_FIELD_LINE, 5.0)
	draw_line(Vector2(-side_x, mouth_half), Vector2(-side_x, field_size.y * 0.5), GameSettings.COLOR_FIELD_LINE, 5.0)
	draw_line(Vector2(side_x, -field_size.y * 0.5), Vector2(side_x, -mouth_half), GameSettings.COLOR_FIELD_LINE, 5.0)
	draw_line(Vector2(side_x, mouth_half), Vector2(side_x, field_size.y * 0.5), GameSettings.COLOR_FIELD_LINE, 5.0)

	draw_rect(outer_rect, Color(0.0, 0.0, 0.0, 0.18), false, 4.0)


func _rebuild_walls() -> void:
	for child in walls_root.get_children():
		child.queue_free()

	var outer_width := field_size.x + goal_depth * 2.0
	_create_wall("TopWall", Vector2(0.0, -field_size.y * 0.5 - wall_thickness * 0.5), Vector2(outer_width, wall_thickness))
	_create_wall("BottomWall", Vector2(0.0, field_size.y * 0.5 + wall_thickness * 0.5), Vector2(outer_width, wall_thickness))

	var side_height := (field_size.y - goal_mouth_height) * 0.5
	var side_y := goal_mouth_height * 0.25 + field_size.y * 0.25
	_create_wall("LeftUpper", Vector2(-field_size.x * 0.5 - wall_thickness * 0.5, -side_y), Vector2(wall_thickness, side_height))
	_create_wall("LeftLower", Vector2(-field_size.x * 0.5 - wall_thickness * 0.5, side_y), Vector2(wall_thickness, side_height))
	_create_wall("RightUpper", Vector2(field_size.x * 0.5 + wall_thickness * 0.5, -side_y), Vector2(wall_thickness, side_height))
	_create_wall("RightLower", Vector2(field_size.x * 0.5 + wall_thickness * 0.5, side_y), Vector2(wall_thickness, side_height))


func _create_wall(node_name: String, wall_position: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.collision_layer = 1
	wall.collision_mask = 0
	walls_root.add_child(wall)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	wall.position = wall_position
