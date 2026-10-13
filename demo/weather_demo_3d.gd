extends Node3D

# The 3D demo. Press 1-6 to force a state, 0 to hand control back to the forecast,
# and watch the patrolling block: it is driven by a WeatherEffect, so it visibly
# slows in snow. That is the point of the pack — the weather changes what moves,
# not just what the sky looks like.

const WEATHER_3D := preload("res://addons/weather/weather_3d.gd")

const KEYS := {KEY_1: "clear", KEY_2: "cloudy", KEY_3: "rain",
	KEY_4: "storm", KEY_5: "snow", KEY_6: "fog"}

var _wm: Node
var _readout: Label
var _walker: Node3D
var _walker_dir := 1.0


func _ready() -> void:
	_build_world()
	_wm = get_node_or_null("/root/WeatherManager")
	if _wm != null:
		_wm.set_state("rain", 0.0)
		_wm.set_intensity(0.8)
	set_process_unhandled_input(true)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.36, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.38, 0.46)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "WorldEnvironment"
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.24, 0.21)
	plane.material = gm
	ground.mesh = plane
	add_child(ground)

	for i in 8:
		var b := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.8, 2.0 + float((i * 53) % 5), 1.8)
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.44 - i * 0.02, 0.42, 0.40)
		box.material = bm
		b.mesh = box
		b.position = Vector3(-9.0 + i * 2.6, box.size.y * 0.5, -6.0 - float((i % 3) * 3))
		add_child(b)

	# The thing that proves the point: it moves, and the weather owns how fast.
	_walker = Node3D.new()
	_walker.name = "Walker"
	_walker.set_script(preload("res://demo/demo_walker.gd"))
	add_child(_walker)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.4, 8.4)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	add_child(cam)

	var weather: Node = WEATHER_3D.new()
	weather.name = "Weather3D"
	add_child(weather)
	weather._cam = cam
	weather._env = we
	weather._sun = sun

	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_readout = Label.new()
	_readout.position = Vector2(18, 14)
	_readout.add_theme_color_override("font_color", Color(1, 1, 1))
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_readout.add_theme_constant_override("outline_size", 6)
	layer.add_child(_readout)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _wm == null:
		return
	var code: int = (event as InputEventKey).keycode
	if KEYS.has(code):
		# change_scale, NOT paused. Pausing is a hard freeze that stops the
		# intensity ramp too, so the state name would change while the rain never
		# actually arrived. change_scale only stops the forecast moving on.
		_wm.set_change_scale(0.0)
		_wm.set_state(KEYS[code], 1.5)


func _process(delta: float) -> void:
	if _walker != null:
		# bounce between the posts; speed is whatever the weather left it
		_walker.position.x += _walker.speed * _walker_dir * delta
		if absf(_walker.position.x) > 7.0:
			_walker_dir = -_walker_dir
			_walker.position.x = clampf(_walker.position.x, -7.0, 7.0)
	if _wm == null or _readout == null:
		return
	_readout.text = "%s  %d%%\n1-6 pick weather" % [
		String(_wm.get_state()).to_upper(), int(round(_wm.get_intensity() * 100.0))]
