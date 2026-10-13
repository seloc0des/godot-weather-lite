@tool
extends Control

# The "chooser" panel: a non-coder picks the weather, picks WHERE it applies, and
# hits Apply. Nothing here is a one-way street — re-pick and Apply again updates
# in place rather than duplicating, tweak the dropped node in the Inspector, or
# open the "Weather" tab below for the full look slider-wall.
#
# Dynamic keeps rolling through the forecast. Picking a state pins it. "Whole
# game" is a project setting the WeatherManager reads at startup (ships in
# project.godot, re-editable). "This 3D/2D scene" drops a driver owned by the
# scene root, so it bakes into the .tscn.
#
# "Show the weather to the player" adds the WeatherUI readout on its own
# CanvasLayer above the weather, so a buyer never has to set a layer by hand.

const MANAGER := preload("res://addons/weather/weather_manager.gd")
const W3D_SCRIPT := "res://addons/weather/weather_3d.gd"
const W2D_SCRIPT := "res://addons/weather/weather_2d.gd"
const UI_SCRIPT := "res://addons/weather/ui/weather_ui.gd"
# the readout's box: small, 16 px in from the bottom-right corner
const UI_HEIGHT := 36.0
const UI_MARGIN := 16.0

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { WHOLE_GAME, THREE_D, TWO_D }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _intensity: HSlider
var _intensity_row: Control
var _show_ui: CheckBox
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Weather · Setup"
	# The whole tab scrolls, so a short screen or a big editor scale can't push the
	# bottom off. Sideways it wraps instead.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	_scroll.add_child(root)

	root.add_child(_h("1.  Pick the weather"))
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	for id in _options():
		var b := Button.new()
		b.text = _pretty(id)
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		grid.add_child(b)
		_buttons[id] = b

	_intensity_row = HBoxContainer.new()
	root.add_child(_intensity_row)
	_intensity_row.add_child(_h("How heavy"))
	_intensity = HSlider.new()
	_intensity.min_value = 0.0
	_intensity.max_value = 1.0
	_intensity.step = 0.05
	_intensity.value = 0.8
	_intensity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intensity_row.add_child(_intensity)
	_intensity_row.visible = false


	root.add_child(_h("2.  Where should it apply?"))
	_scope = OptionButton.new()
	_scope.add_item("Whole game", Scope.WHOLE_GAME)
	_scope.add_item("This 3D scene", Scope.THREE_D)
	_scope.add_item("This 2D scene", Scope.TWO_D)
	root.add_child(_scope)
	_show_ui = CheckBox.new()
	_show_ui.text = "Show the weather to the player"
	_show_ui.tooltip_text = "Adds a small readout (\"Rain, heavy\") in the bottom-right corner, drawn above the weather."
	root.add_child(_show_ui)


	root.add_child(_h("3.  Apply"))
	root.add_child(_btn("Apply", _on_apply, true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game, change it any time: re-pick and Apply, tweak the node in the Inspector, or set the WeatherManager autoload directly. The Weather tab is the full look slider-wall."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	# long tick labels wrap onto a second line instead of widening the dock
	for c in root.get_children():
		if c is Button and not (c is OptionButton):
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	if _scroll == null:
		return Vector2.ZERO
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0)


func _options() -> Array:
	var out: Array = []
	for s in MANAGER.DEFAULT_STATES:
		out.append(s)
	return out


func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	# Intensity only means something for a pinned state; dynamic rolls its own.
	_intensity_row.visible = id != MANAGER.MODE_DYNAMIC
	_say("Picked %s. Choose where, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick the weather first.", WARN_COLOR)
		return
	match _scope.get_selected_id():
		Scope.WHOLE_GAME: _apply_whole_game()
		Scope.THREE_D: _apply_scene(true)
		Scope.TWO_D: _apply_scene(false)


func _apply_whole_game() -> void:
	write_startup(_chosen, _intensity.value, _lite_climate())
	var extra := ""
	if _show_ui.button_pressed:
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			extra = " Open a scene to add the weather readout to it."
		else:
			extra = _readout(root)
			EditorInterface.mark_scene_as_unsaved()
	_say("Whole game → %s (saved to project settings). It starts this way in every scene; re-pick any time. Drop a Weather3D/2D per scene to see it.%s" % [_pretty(_chosen), extra], OK_COLOR)


func _apply_scene(is_3d: bool) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a %s scene first (Scene → New/Open)." % ("3D" if is_3d else "2D"), ERR_COLOR)
		return
	# A pinned state is whole-game (it's the clock, not the visual), so persist it
	# too or the driver renders whatever the forecast rolled instead.
	if _chosen != MANAGER.MODE_DYNAMIC:
		write_startup(_chosen, _intensity.value, _lite_climate())
	var cls := "Weather3D" if is_3d else "Weather2D"
	var existed := _find(root, cls) != null
	var node := wire_3d(root) if is_3d else wire_2d(root)
	var extra := _readout(root) if _show_ui.button_pressed else ""
	_select(node)
	_say("This %s scene → %s.%s%s Tweak it in the Inspector; re-pick here any time." % [
		"3D" if is_3d else "2D", _pretty(_chosen), driver_note(cls, existed), extra], OK_COLOR)


# A second Apply reuses the driver that's there, so say that rather than "Added".
func driver_note(cls: String, existed: bool) -> String:
	return (" Updated the existing %s." if existed else " Added a %s.") % cls


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Each is re-entrant: it updates the existing node rather than duplicating.

func wire_3d(root: Node) -> Node:
	var node := _ensure(root, "Weather3D", W3D_SCRIPT)
	var cam := _find(root, "Camera3D")
	if cam != null:
		node.set("camera_path", node.get_path_to(cam))
	var env := _find(root, "WorldEnvironment")
	if env != null:
		node.set("environment_path", node.get_path_to(env))
	var sun := _find(root, "DirectionalLight3D")
	if sun != null:
		node.set("sun_path", node.get_path_to(sun))
	return node


func wire_2d(root: Node) -> Node:
	# Weather2D is a CanvasLayer, NOT a CanvasModulate — so it sits alongside a
	# DayNight2D instead of fighting it for the one canvas tint.
	return _ensure(root, "Weather2D", W2D_SCRIPT)


# The WeatherUI readout on its own CanvasLayer, one above every Weather2D so the
# tint never sits over it. Re-entrant: a second call re-pins the one that's there.
func wire_ui(root: Node) -> Node:
	var ui := _find(root, "WeatherUI")
	if ui == null:
		var layer := CanvasLayer.new()
		layer.name = "WeatherUILayer"
		root.add_child(layer, true)
		layer.owner = root
		ui = _inert(load(UI_SCRIPT))
		ui.name = "WeatherUI"
		layer.add_child(ui, true)
		ui.owner = root
	# one the buyer moved into their own HUD stays where they put it
	var host := _readout_layer(ui)
	if host != null:
		host.layer = layer_above_weather(root)
		_pin_corner(ui as Control)
	return ui


# The CanvasLayer the readout sits on by itself. Weather2D is a CanvasLayer too,
# and raising that one would just drag the tint up with it.
func _readout_layer(ui: Node) -> CanvasLayer:
	var host := ui.get_parent() as CanvasLayer
	if host == null or _is_cls(host, "Weather2D"):
		return null
	return host


# Never below 2, so a Weather2D added later at its default layer 1 stays under it.
func layer_above_weather(root: Node) -> int:
	var top := 1
	for n in root.find_children("*", "", true, false):
		if _is_cls(n, "Weather2D"):
			top = maxi(top, int(n.get("layer")))
	return top + 1


func ui_note(root: Node, ui: Node, added: bool) -> String:
	if _readout_layer(ui) == null:
		return " This scene already has a weather readout at %s, so it was left where it is." % root.get_path_to(ui)
	if added:
		return " Added a weather readout in the bottom-right corner, drawn above the weather."
	return " The weather readout is in the bottom-right corner, drawn above the weather."


func _readout(root: Node) -> String:
	var added := _find(root, "WeatherUI") == null
	return ui_note(root, wire_ui(root), added)


func _pin_corner(ui: Control) -> void:
	ui.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ui.offset_left = -UI_MARGIN - _ui_width()
	ui.offset_top = -UI_MARGIN - UI_HEIGHT
	ui.offset_right = -UI_MARGIN
	ui.offset_bottom = -UI_MARGIN
	ui.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui.grow_vertical = Control.GROW_DIRECTION_BEGIN


# Pro's readout carries the forecast too ("Rain, heavy    Next: Storm"), so its box is wider.
func _ui_width() -> float:
	return 220.0


func write_startup(state: String, intensity: float, climate: String) -> void:
	ProjectSettings.set_setting(MANAGER.STARTUP_STATE_SETTING, state)
	ProjectSettings.set_setting(MANAGER.STARTUP_INTENSITY_SETTING, clampf(intensity, 0.0, 1.0))
	# Persisting is the editor's job. A headless caller (the self-test) that saves
	# here rewrites project.godot's config/features to whatever engine is running,
	# which bumps the 4.5 floor and locks out buyers on older Godot.
	if Engine.is_editor_hint():
		ProjectSettings.save()


# ---- helpers -------------------------------------------------------------



# Reads the climate picker in Pro. Lite has no transition table to pick for, so
# it always writes the temperate id and the setting is simply inert.
func _lite_climate() -> String:
	return "temperate"


func _ensure(root: Node, cls: String, script_path: String) -> Node:
	var found := _find(root, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n := _inert(load(script_path))
	n.name = cls  # else the Scene tree shows an engine name like @Node3D@19885
	root.add_child(n, true)
	n.owner = root
	return n


# A runtime script's .new() is a live instance, so Weather3D's game code used to run in
# the editor: it followed the camera, and that position plus a default profile it made
# were saved into the buyer's scene. A plain native node with the script attached is the
# inert placeholder a hand-added node gets. Outside the editor it's a normal instance.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


# Scoped to nodes THIS scene owns. A node inside an instanced child scene
# (owner != root) is skipped — editing it wouldn't serialize into the buyer's
# scene, so we'd silently no-op.
func _find(root: Node, cls: String) -> Node:
	return _find_owned(root, root, cls)


func _find_owned(node: Node, root: Node, cls: String) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, cls):
		return node
	for c in node.get_children():
		var f := _find_owned(c, root, cls)
		if f != null:
			return f
	return null


# Deliberately NOT scoped to owned nodes, unlike _find. What we are looking for is
# a target to POINT AT, and the thing that moves the player usually lives inside an
# instanced player scene. Where the component is PARENTED is the part that has to
# be serializable, and _serializable_host handles that.
func _find_with_speed(node: Node, root: Node) -> Node:
	if node != root:
		var v: Variant = node.get("speed")
		if v is float or v is int:
			return node
	for c in node.get_children():
		var f := _find_with_speed(c, root)
		if f != null:
			return f
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true
	var scr: Script = node.get_script()
	return scr != null and scr.get_global_name() == cls


func _select(n: Node) -> void:
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _pretty(id: String) -> String:
	if id == MANAGER.MODE_DYNAMIC:
		return "Dynamic"
	return id.capitalize()


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
