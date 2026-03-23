extends Node2D
class_name GoalZone

signal goal_scored(scoring_team: int, defending_team: int)

@export var defending_team := GameEnums.TeamId.RED
@export var goal_id := "left_goal"
@export var is_left_goal := true
@export var goal_mouth_height := GameSettings.GOAL_MOUTH_HEIGHT
@export var goal_depth := GameSettings.GOAL_DEPTH
@export var wall_thickness := GameSettings.WALL_THICKNESS

@onready var goal_area: Area2D = $GoalArea
@onready var goal_area_shape: CollisionShape2D = $GoalArea/CollisionShape2D
@onready var back_wall: StaticBody2D = $BackWall
@onready var back_wall_shape: CollisionShape2D = $BackWall/CollisionShape2D
@onready var top_post: StaticBody2D = $TopPost
@onready var top_post_shape: CollisionShape2D = $TopPost/CollisionShape2D
@onready var bottom_post: StaticBody2D = $BottomPost
@onready var bottom_post_shape: CollisionShape2D = $BottomPost/CollisionShape2D

var scoring_enabled := false


func _ready() -> void:
	goal_area.collision_mask = 4
	goal_area.collision_layer = 0
	goal_area.body_entered.connect(_on_goal_area_body_entered)
	_rebuild_shapes()
	queue_redraw()


func set_scoring_enabled(value: bool) -> void:
	scoring_enabled = value
	goal_area.monitoring = value


func _rebuild_shapes() -> void:
	var post_radius := wall_thickness * 0.42
	var area_shape := RectangleShape2D.new()
	area_shape.size = Vector2(goal_depth - post_radius, goal_mouth_height - post_radius * 2.0)
	goal_area_shape.shape = area_shape
	goal_area.position = Vector2((-goal_depth * 0.55 if is_left_goal else goal_depth * 0.55), 0.0)

	var back_shape := RectangleShape2D.new()
	back_shape.size = Vector2(wall_thickness, goal_mouth_height - post_radius)
	back_wall_shape.shape = back_shape
	back_wall.position = Vector2((-goal_depth - wall_thickness * 0.5 if is_left_goal else goal_depth + wall_thickness * 0.5), 0.0)
	back_wall.collision_layer = 1
	back_wall.collision_mask = 0

	var post_shape := CircleShape2D.new()
	post_shape.radius = post_radius
	top_post_shape.shape = post_shape
	bottom_post_shape.shape = post_shape.duplicate()
	top_post.position = Vector2(0.0, -goal_mouth_height * 0.5)
	bottom_post.position = Vector2(0.0, goal_mouth_height * 0.5)
	top_post_shape.rotation_degrees = 0.0
	bottom_post_shape.rotation_degrees = 0.0
	for post in [top_post, bottom_post]:
		post.collision_layer = 1
		post.collision_mask = 0


func _on_goal_area_body_entered(body: Node) -> void:
	if not scoring_enabled:
		return
	if body is MatchBall:
		scoring_enabled = false
		var scoring_team := GameEnums.TeamId.BLUE if defending_team == GameEnums.TeamId.RED else GameEnums.TeamId.RED
		goal_scored.emit(scoring_team, defending_team)


func _draw() -> void:
	var outline_color := Color("111111")
	var post_color := Helpers.team_color(defending_team)
	var side_sign := -1.0 if is_left_goal else 1.0
	var mouth_top := -goal_mouth_height * 0.5
	var mouth_bottom := goal_mouth_height * 0.5
	var back_x := side_sign * goal_depth
	draw_line(Vector2(0.0, mouth_top), Vector2(back_x, mouth_top), outline_color, 6.0)
	draw_line(Vector2(0.0, mouth_bottom), Vector2(back_x, mouth_bottom), outline_color, 6.0)
	draw_line(Vector2(back_x, mouth_top + 12.0), Vector2(back_x, mouth_bottom - 12.0), outline_color, 6.0)
	draw_circle(Vector2(0.0, mouth_top), 14.0, post_color)
	draw_circle(Vector2(0.0, mouth_bottom), 14.0, post_color)

	for i in range(1, 6):
		var t := float(i) / 6.0
		var net_x := lerpf(0.0, back_x, t)
		var offset := absf(back_x) * 0.08
		draw_line(
			Vector2(net_x, mouth_top + 10.0),
			Vector2(net_x + side_sign * offset, mouth_bottom - 10.0),
			Color(1.0, 1.0, 1.0, 0.18),
			1.5
		)
	for i in range(1, 6):
		var t := float(i) / 6.0
		var y := lerpf(mouth_top + 8.0, mouth_bottom - 8.0, t)
		draw_line(
			Vector2(side_sign * 8.0, y),
			Vector2(back_x, y),
			Color(1.0, 1.0, 1.0, 0.15),
			1.2
		)
