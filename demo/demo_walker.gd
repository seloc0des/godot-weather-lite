extends Node3D

# A block that paces back and forth. It exists so the demo has something whose
# speed the weather can visibly take away — the WeatherEffect on it drives this
# property, and nothing else in the demo touches it.

@export var speed: float = 3.2


func _ready() -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 1.7, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.62, 0.32)
	box.material = mat
	m.mesh = box
	m.position.y = 0.85
	add_child(m)
