@tool
extends Control

# The tuner tab: the WeatherProfile slider-wall, for a designer who wants to
# restyle a state rather than just pick one. Sits below the chooser.
#
# Pick a state, move the sliders, Save. The profile is a .tres in res://weather/,
# the same content contract every other dock in the catalog uses, so it's a real
# file the buyer owns rather than something hidden in an autoload.

const PROFILE_SCRIPT := preload("res://addons/weather/resources/weather_profile.gd")
const MANAGER := preload("res://addons/weather/weather_manager.gd")

const PROFILE_DIR := "res://weather"
const PROFILE_PATH := "res://weather/weather_profile.tres"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)

var profile: Resource
var _state_pick: OptionButton
var _count: HSlider
var _speed: HSlider
var _wind: HSlider
var _fog: HSlider
var _particle_color: ColorPickerButton
var _tint_color: ColorPickerButton
var _status: Label
var _loading := false
# A profile loaded from disk in the editor is an inert placeholder (the script isn't
# @tool), so its get_look() can't run. Read looks straight off it, and ask a live
# blank profile for the built-in ones.
var _builtin: Resource = PROFILE_SCRIPT.new()
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Weather"
	profile = _load_or_new()

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

	root.add_child(_h("Weather look"))
	_state_pick = OptionButton.new()
	for i in MANAGER.DEFAULT_STATES.size():
		_state_pick.add_item(String(MANAGER.DEFAULT_STATES[i]).capitalize(), i)
	_state_pick.item_selected.connect(_on_state_picked)
	root.add_child(_state_pick)

	_count = _slider(root, "Particles (at full strength)", 0.0, 6000.0, 25.0, "particle_count")
	_speed = _slider(root, "Fall speed", 0.2, 30.0, 0.1, "fall_speed")
	_wind = _slider(root, "Catches the wind", 0.0, 8.0, 0.1, "wind_bias")
	_fog = _slider(root, "Fog / haze", 0.0, 0.3, 0.002, "fog_density")

	var crow := HBoxContainer.new()
	root.add_child(crow)
	crow.add_child(_h("Particle"))
	_particle_color = ColorPickerButton.new()
	_particle_color.custom_minimum_size = Vector2(60, 24)
	_particle_color.color_changed.connect(_on_edited_color.bind("particle_color"))
	crow.add_child(_particle_color)
	crow.add_child(_h("Tint"))
	_tint_color = ColorPickerButton.new()
	_tint_color.custom_minimum_size = Vector2(60, 24)
	_tint_color.color_changed.connect(_on_edited_color.bind("tint"))
	crow.add_child(_tint_color)

	var brow := HBoxContainer.new()
	root.add_child(brow)
	brow.add_child(_btn("Save profile", _on_save, true))
	brow.add_child(_btn("Apply to scene", _on_apply_to_scene))
	root.add_child(_btn("Reset this state", _on_reset))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "Saves to %s. Leave a state untouched and it keeps the built-in look, so you only author what you care about." % PROFILE_PATH
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	_load_state_into_ui(_current_state())


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	if _scroll == null:
		return Vector2.ZERO
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0)


# ---- state <-> ui ---------------------------------------------------------

func _current_state() -> String:
	var i := 0 if _state_pick == null else _state_pick.get_selected_id()
	return String(MANAGER.DEFAULT_STATES[clampi(i, 0, MANAGER.DEFAULT_STATES.size() - 1)])


func _on_state_picked(_i: int) -> void:
	_load_state_into_ui(_current_state())


func _load_state_into_ui(state: String) -> void:
	# Guard the write-back handlers, or populating the widgets counts as edits and
	# authors an override for a state the buyer never touched.
	_loading = true
	var look: Resource = _look(state)
	_count.value = float(look.particle_count)
	_speed.value = look.fall_speed
	_wind.value = look.wind_bias
	_fog.value = look.fog_density
	_particle_color.color = look.particle_color
	_tint_color.color = look.tint
	_loading = false
	_say("Editing %s." % state.capitalize(), OK_COLOR)


func _look(state: String) -> Resource:
	var authored: Variant = profile.looks.get(state)
	return authored if authored is Resource else _builtin.get_look(state)


func _on_edited(v: float, field: String) -> void:
	_write_back(field, int(round(v)) if field == "particle_count" else v)


func _on_edited_color(c: Color, field: String) -> void:
	_write_back(field, c)


# Overrides are only created for states the buyer actually edits — an untouched
# state keeps falling through to the built-in look. Only the field that moved is
# written: the rest of the look may have changed in the Inspector since.
func _write_back(field: String, value: Variant) -> void:
	if _loading:
		return
	var state := _current_state()
	var look: Resource = profile.looks.get(state)
	if look == null:
		look = _look(state).duplicate()  # the built-in look, texture and all
		# copy, change, assign back: a loaded profile's empty looks can be read-only
		var looks: Dictionary = profile.looks.duplicate()
		looks[state] = look
		profile.looks = looks
	look.set(field, value)


func _on_reset() -> void:
	var state := _current_state()
	var looks: Dictionary = profile.looks.duplicate()
	looks.erase(state)
	profile.looks = looks
	_load_state_into_ui(state)
	_say("%s is back to the built-in look." % state.capitalize(), OK_COLOR)


# ---- save / apply ---------------------------------------------------------

func _load_or_new() -> Resource:
	if ResourceLoader.exists(PROFILE_PATH):
		var r := ResourceLoader.load(PROFILE_PATH)
		if r != null and r.has_method("get_look"):
			return r
	return PROFILE_SCRIPT.new()


func _on_save() -> void:
	var err := save_profile(profile)
	if err == OK:
		_adopt_file_copy()
		_say("Saved to %s." % PROFILE_PATH, OK_COLOR)
	else:
		_say("Could not save the profile (error %d)." % err, ERR_COLOR)


## Pure enough to test headlessly: makes the folder, writes the .tres.
func save_profile(p: Resource) -> int:
	if not DirAccess.dir_exists_absolute(PROFILE_DIR):
		DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	var err := ResourceSaver.save(p, PROFILE_PATH)
	if err == OK:
		_register_uid(PROFILE_PATH)
	return err


func _on_apply_to_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first.", ERR_COLOR)
		return
	if save_profile(profile) != OK:
		_say("Could not save the profile, so nothing was applied.", ERR_COLOR)
		return
	_adopt_file_copy()
	var n := assign_profile(root, ResourceLoader.load(PROFILE_PATH))
	if n == 0:
		_say("Saved, but this scene has no Weather3D or Weather2D yet — use the Setup tab above.", ERR_COLOR)
	else:
		# the drivers changed without the undo manager, so flag the scene for Play
		EditorInterface.mark_scene_as_unsaved()
		_say("Saved and applied to %d weather driver%s in this scene." % [n, "" if n == 1 else "s"], OK_COLOR)


# The Inspector and scenes load the file's own copy. Make that the one this tab
# edits, or the editor's next save writes their old copy back over this Save.
func _adopt_file_copy() -> void:
	if not ResourceLoader.has_cached(PROFILE_PATH):
		profile.take_over_path(PROFILE_PATH)  # nobody holds it yet
		return
	var cached: Resource = ResourceLoader.load(PROFILE_PATH)
	if cached == profile or not cached.has_method("get_look"):
		return
	for p in profile.get_property_list():
		var n: String = p.name
		if (int(p.usage) & PROPERTY_USAGE_STORAGE) and n != "script" and n != "resource_path":
			cached.set(n, profile.get(n))
	cached.emit_changed()
	profile = cached


## Assigns the profile to every weather driver this scene owns. Returns the count.
func assign_profile(root: Node, p: Resource) -> int:
	var n := 0
	for node in _drivers(root, root):
		node.set("profile", p)
		n += 1
	return n


func _drivers(node: Node, root: Node) -> Array:
	var out: Array = []
	if node == root or node.owner == root:
		var scr: Script = node.get_script()
		if scr != null and scr.get_global_name() in ["Weather3D", "Weather2D"]:
			out.append(node)
	for c in node.get_children():
		out.append_array(_drivers(c, root))
	return out


# ---- tiny ui helpers ------------------------------------------------------

func _slider(parent: Control, label: String, lo: float, hi: float, step: float, field: String) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	parent.add_child(row)
	row.add_child(_h(label))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(_on_edited.bind(field))
	row.add_child(s)
	return s


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


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
