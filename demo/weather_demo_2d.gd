extends Node2D

# The 2D demo. Same controls as the 3D one: 1-6 force a state, 0 hands control
# back to the forecast. A CanvasModulate sits in the scene on purpose — it is
# what DayNight2D is, and this demo exists partly to show the two coexisting.

const WEATHER_2D := preload("res://addons/weather/weather_2d.gd")

const KEYS := {KEY_1: "clear", KEY_2: "cloudy", KEY_3: "rain",
	KEY_4: "storm", KEY_5: "snow", KEY_6: "fog"}

var _wm: Node
var _readout: Label
var _walker: Node2D
var _dir := 1.0


func _ready() -> void:
	_build_world()
	_wm = get_node_or_null("/root/WeatherManager")
	if _wm != null:
		_wm.set_state("rain", 0.0)
		_wm.set_intensity(0.85)
	set_process_unhandled_input(true)


func _build_world() -> void:
	var vs := get_viewport().get_visible_rect().size
	var sky := ColorRect.new()
	sky.color = Color(0.55, 0.68, 0.82)
	sky.size = vs
	add_child(sky)

	var colors := [Color(0.30, 0.34, 0.40), Color(0.24, 0.28, 0.34), Color(0.35, 0.39, 0.45)]
	for i in 9:
		var b := ColorRect.new()
		var h: float = 150.0 + float((i * 97) % 240)
		b.size = Vector2(110, h)
		b.position = Vector2(i * (vs.x / 9.0), vs.y - h - 90.0)
		b.color = colors[i % 3]
		add_child(b)

	var ground := ColorRect.new()
	ground.size = Vector2(vs.x, 90)
	ground.position = Vector2(0, vs.y - 90)
	ground.color = Color(0.19, 0.21, 0.19)
	add_child(ground)

	# DayNight2D IS a CanvasModulate. Weather2D is a CanvasLayer, so both work.
	var cm := CanvasModulate.new()
	cm.name = "StandInForDayNight2D"
	cm.color = Color(0.62, 0.60, 0.78)
	add_child(cm)

	_walker = Node2D.new()
	_walker.name = "Walker"
	_walker.set_script(preload("res://demo/demo_walker_2d.gd"))
	_walker.position = Vector2(vs.x * 0.5, vs.y - 118)
	add_child(_walker)

	var weather: Node = WEATHER_2D.new()
	weather.name = "Weather2D"
	add_child(weather)

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
	var vs := get_viewport().get_visible_rect().size
	if _walker != null:
		_walker.position.x += _walker.speed * _dir * delta
		if _walker.position.x < 60.0 or _walker.position.x > vs.x - 60.0:
			_dir = -_dir
			_walker.position.x = clampf(_walker.position.x, 60.0, vs.x - 60.0)
	if _wm == null or _readout == null:
		return
	_readout.text = "%s  %d%%\n1-6 pick weather" % [
		String(_wm.get_state()).to_upper(), int(round(_wm.get_intensity() * 100.0))]
