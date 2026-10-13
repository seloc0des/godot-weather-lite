extends Node2D

# Paces across the street so the demo has something the weather can slow down.

@export var speed: float = 140.0


func _ready() -> void:
	var body := ColorRect.new()
	body.size = Vector2(26, 54)
	body.position = Vector2(-13, -54)
	body.color = Color(0.88, 0.66, 0.34)
	add_child(body)
