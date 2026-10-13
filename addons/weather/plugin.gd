@tool
extends EditorPlugin

# Registers the shared Events bus (only if a sibling RPG addon hasn't already)
# and the global WeatherManager singleton. Weather is a property of the world,
# so the manager IS an autoload — same call as TimeManager next door.

const EVENTS_NAME := "Events"
const EVENTS_PATH := "res://addons/rpg_core/events.gd"
const MANAGER_NAME := "WeatherManager"
const MANAGER_PATH := "res://addons/weather/weather_manager.gd"
const META_SECTION := "weather_lite"
const META_ADDED := "added_autoload"
const CHOOSER_SCRIPT := preload("res://addons/weather/editor/21-weather_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/weather/editor/weather_dock.gd")

var _chooser: Control
var _dock: Control


func _enable_plugin() -> void:
	_ensure_manager()


# Only take away a WeatherManager this plugin put there. A project that declares it
# itself keeps it, and closing the editor never touches it.
func _disable_plugin() -> void:
	var es := EditorInterface.get_editor_settings()
	if es.get_project_metadata(META_SECTION, META_ADDED, false) and ProjectSettings.has_setting("autoload/" + MANAGER_NAME):
		remove_autoload_singleton(MANAGER_NAME)
	es.set_project_metadata(META_SECTION, META_ADDED, false)


func _enter_tree() -> void:
	_ensure_manager()

	# Chooser first so a non-coder lands on it; the tuner tab below is the
	# profile slider-wall for designers.
	_chooser = CHOOSER_SCRIPT.new()
	# Named here, not only in the dock's _ready: Godot 4.5 reads the tab title
	# the moment the dock is added, before _ready has run.
	_chooser.name = "Weather · Setup"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chooser)
	_dock = DOCK_SCRIPT.new()
	_dock.name = "Weather"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _chooser:
		remove_control_from_docks(_chooser)
		_chooser.free()
		_chooser = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null


func _ensure_manager() -> void:
	if not ProjectSettings.has_setting("autoload/" + MANAGER_NAME):
		add_autoload_singleton(MANAGER_NAME, MANAGER_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)
