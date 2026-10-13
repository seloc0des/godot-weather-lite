extends Node

# Headless test for Weather System (Lite): the Setup tab's "Show the weather to
# the player" wiring, and the readout it builds, played in a real scene.
# Run: godot --headless --path . res://tools/verify.tscn

const CHOOSER := preload("res://addons/weather/editor/21-weather_chooser_dock.gd")
const UI_SCRIPT := preload("res://addons/weather/ui/weather_ui.gd")

var _passes := 0
var _failures := 0


# Stands in for Dialogue Lite's autoload: the two signals and is_active() the
# readout listens for.
class _FakeTalk extends Node:
	signal dialogue_started(id: String)
	signal dialogue_finished(id: String)
	var active := false
	func is_active() -> bool:
		return active
	func talk(on: bool) -> void:
		active = on
		if on:
			dialogue_started.emit("probe")
		else:
			dialogue_finished.emit("probe")


func _ready() -> void:
	await get_tree().process_frame
	print("--- weather lite verify ---")
	_wiring_2d()
	_wiring_3d()
	await _played_2d()
	await _played_3d()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


func _count(root: Node, cls: String) -> int:
	var n := 0
	for c in root.find_children("*", "", true, false):
		var scr: Script = c.get_script()
		if c.get_class() == cls or (scr != null and scr.get_global_name() == cls):
			n += 1
	return n


func _window(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	add_child(vp)
	return vp


# Where a control anchored to the viewport lands in a window of this size.
func _rect_in(ui: Control, view: Vector2) -> Rect2:
	var left := view.x * ui.anchor_left + ui.offset_left
	var top := view.y * ui.anchor_top + ui.offset_top
	var right := view.x * ui.anchor_right + ui.offset_right
	var bottom := view.y * ui.anchor_bottom + ui.offset_bottom
	return Rect2(left, top, right - left, bottom - top)


func _wiring_2d() -> void:
	var dock = CHOOSER.new()
	var root := Node2D.new()
	root.name = "Level"
	dock.wire_2d(root)
	var ui: Node = dock.wire_ui(root)
	var w2d: Node = root.get_node_or_null("Weather2D")
	_assert(ui != null and ui.get_script() == UI_SCRIPT, "wire_ui adds a WeatherUI")
	var layer := ui.get_parent() as CanvasLayer
	_assert(layer != null and layer.get_parent() == root and String(layer.name) == "WeatherUILayer", "on its own CanvasLayer at the scene root, named WeatherUILayer")
	_assert(String(ui.name) == "WeatherUI" and ui.owner == root and layer.owner == root, "both owned by the root, so they save with the scene")
	_assert(w2d != null and layer.layer > int(w2d.get("layer")), "the readout's layer (%d) is above the Weather2D's (%d)" % [layer.layer, int(w2d.get("layer"))])
	var c := ui as Control
	_assert(is_equal_approx(c.anchor_left, 1.0) and is_equal_approx(c.anchor_top, 1.0) and is_equal_approx(c.anchor_right, 1.0) and is_equal_approx(c.anchor_bottom, 1.0), "anchored to the bottom-right corner")
	for view in [Vector2(1152, 648), Vector2(1280, 720)]:
		var r := _rect_in(c, view)
		_assert(r.size.x > 0.0 and r.size.y > 0.0 and r.size.x <= 260.0 and r.size.y <= 60.0, "small at %s (%s)" % [view, r.size])
		_assert(is_equal_approx(r.end.x, view.x - 16.0) and is_equal_approx(r.end.y, view.y - 16.0) and r.position.x > view.x * 0.5, "16 px in from the bottom-right corner at %s" % view)
	_assert(c.grow_horizontal == Control.GROW_DIRECTION_BEGIN and c.grow_vertical == Control.GROW_DIRECTION_BEGIN, "grows toward the middle, never off the edge")

	# re-entrant
	var again: Node = dock.wire_ui(root)
	_assert(again == ui and _count(root, "WeatherUI") == 1 and _count(root, "CanvasLayer") == 2, "a second Apply reuses the readout and its layer (%d readouts, %d CanvasLayers)" % [_count(root, "WeatherUI"), _count(root, "CanvasLayer")])
	_assert(dock.ui_note(root, again, false).begins_with(" The weather readout is in the bottom-right corner"), "status says where it is")
	_assert(dock.ui_note(root, ui, true).begins_with(" Added a weather readout in the bottom-right corner"), "status says it was added")
	_assert(dock.driver_note("Weather2D", false) == " Added a Weather2D." and dock.driver_note("Weather3D", true) == " Updated the existing Weather3D.", "Apply says Added the first time and Updated the existing driver after")

	# the buyer raised the weather's layer: Apply again follows it
	w2d.set("layer", 5)
	dock.wire_ui(root)
	_assert(layer.layer == 6, "re-Apply stays above a Weather2D raised to layer 5 (got %d)" % layer.layer)

	# moved into the buyer's own HUD: left where they put it
	var hud := Control.new()
	hud.name = "HUD"
	root.add_child(hud)
	hud.owner = root
	ui.owner = null
	ui.reparent(hud)
	ui.owner = root
	(ui as Control).offset_left = 10.0
	var kept: Node = dock.wire_ui(root)
	_assert(kept == ui and ui.get_parent() == hud and is_equal_approx((ui as Control).offset_left, 10.0), "a readout moved into the buyer's HUD is left alone")
	_assert(dock.ui_note(root, kept, false).contains("left where it is"), "and the status says so")
	# dragged under the Weather2D itself: the weather's own layer isn't touched
	var w2d_layer := int(w2d.get("layer"))
	ui.owner = null
	ui.reparent(w2d)
	ui.owner = root
	dock.wire_ui(root)
	_assert(int(w2d.get("layer")) == w2d_layer and ui.get_parent() == w2d, "a readout under the Weather2D doesn't drag the weather's layer up")
	root.free()

	# one inside an instanced sub-scene isn't hijacked
	var host := Node2D.new()
	var sub := Node2D.new()
	host.add_child(sub)
	sub.owner = host
	var inner: Node = dock.wire_ui(sub)
	var outer: Node = dock.wire_ui(host)
	_assert(outer != inner and outer.owner == host, "a readout owned by a sub-scene isn't hijacked")
	host.free()
	dock.free()


func _wiring_3d() -> void:
	var dock = CHOOSER.new()
	var root := Node3D.new()
	root.name = "Level3D"
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.owner = root
	dock.wire_3d(root)
	var ui: Node = dock.wire_ui(root)
	var layer := ui.get_parent() as CanvasLayer
	_assert(layer != null and layer.layer == 2, "3D: the readout gets its own layer 2, above a Weather2D added later at its default 1")
	var w2d: Node = dock.wire_2d(root)
	_assert(layer.layer > int(w2d.get("layer")), "3D: still above that Weather2D")
	root.free()
	dock.free()


# The scene the Setup tab builds (Apply "This 2D scene" with the box ticked),
# packed and played.
func _played_2d() -> void:
	var dock = CHOOSER.new()
	var level := Node2D.new()
	level.name = "Level"
	add_child(level)
	dock.wire_2d(level)
	var live: Node = dock.wire_ui(level)
	await get_tree().process_frame
	_assert(live.get_child_count() > 0, "played: a live readout builds its label")
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	dock.free()
	var state := ps.get_state()
	var labels := 0
	for i in state.get_node_count():
		if state.get_node_type(i) == &"Label":
			labels += 1
	_assert(labels == 0, "played: that label is built at runtime, never saved into the scene")

	# played in a window the size of a new Godot project's, not headless's 64x64
	var vp := _window(Vector2i(1152, 648))
	var talk := _FakeTalk.new()
	talk.name = "DialoguesLite"
	get_tree().root.add_child(talk)
	var game: Node = ps.instantiate()
	vp.add_child(game)
	_weather_manager().set_state("rain", 0.0)
	_weather_manager().set_intensity(0.9)
	await get_tree().process_frame
	await get_tree().process_frame
	var ui := game.get_node("WeatherUILayer/WeatherUI") as Control
	var label: Label = ui.get_child(0) as Label if ui.get_child_count() > 0 else null
	_assert(label != null and label.text.begins_with("Rain"), "played: it reads the weather (%s)" % (label.text if label != null else "no label"))
	var w2d := game.get_node("Weather2D") as CanvasLayer
	var layer := game.get_node("WeatherUILayer") as CanvasLayer
	_assert(layer.layer > w2d.layer, "played: drawn above the weather (%d over %d)" % [layer.layer, w2d.layer])
	var view := vp.get_visible_rect().size
	var r := ui.get_global_rect()
	_assert(is_equal_approx(r.end.x, view.x - 16.0) and is_equal_approx(r.end.y, view.y - 16.0) and r.position.x > view.x * 0.75 and r.position.y > view.y * 0.85, "played: it sits small in the bottom-right corner (%s in %s)" % [r, view])
	var lr := label.get_global_rect() if label != null else Rect2()
	_assert(label != null and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and lr.end.x <= view.x - 15.0 and lr.position.x >= r.position.x - 1.0, "played: the text hugs the right edge inside its box")
	_weather_manager().set_state("snow", 0.0)
	await get_tree().process_frame
	_assert(label != null and label.text.begins_with("Snow"), "played: it follows a change of weather (%s)" % (label.text if label != null else "no label"))

	# out of the dialogue box's way while a conversation is up
	_assert(label != null and label.visible, "played: showing before any conversation")
	talk.talk(true)
	_assert(label != null and not label.visible, "played: hidden while a conversation is on screen")
	talk.talk(false)
	_assert(label != null and label.visible, "played: back once it ends")
	talk.talk(true)
	var late: Control = UI_SCRIPT.new()
	vp.add_child(late)
	var late_label: Label = late.get_child(0) as Label
	_assert(late_label != null and not late_label.visible, "played: a readout that appears mid-conversation starts hidden")
	talk.talk(false)
	_assert(late_label != null and late_label.visible, "played: and shows when it ends")
	ui.set("hide_during_dialogue", false)
	talk.talk(true)
	_assert(label != null and label.visible, "played: hide_during_dialogue off keeps it up")
	talk.talk(false)
	talk.queue_free()
	vp.queue_free()
	await get_tree().process_frame


func _played_3d() -> void:
	var dock = CHOOSER.new()
	var level := Node3D.new()
	level.name = "Level3D"
	add_child(level)
	dock.wire_3d(level)
	dock.wire_ui(level)
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	dock.free()
	var vp := _window(Vector2i(1280, 720))
	var game: Node = ps.instantiate()
	vp.add_child(game)
	_weather_manager().set_state("fog", 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var ui := game.get_node("WeatherUILayer/WeatherUI") as Control
	var label: Label = ui.get_child(0) as Label if ui.get_child_count() > 0 else null
	var view := vp.get_visible_rect().size
	_assert(label != null and label.text.begins_with("Fog") and ui.get_global_rect().end.is_equal_approx(view - Vector2(16, 16)), "played 3D: the readout shows the weather in the corner (%s)" % (label.text if label != null else "no label"))
	vp.queue_free()
	await get_tree().process_frame


# WeatherManager is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const WEATHER_MANAGER := preload("res://addons/weather/weather_manager.gd")


static func _weather_manager() -> WEATHER_MANAGER:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"WeatherManager") as WEATHER_MANAGER
