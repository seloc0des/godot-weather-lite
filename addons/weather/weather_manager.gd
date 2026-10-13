extends Node

# Autoload: WeatherManager
#
# Weather is a property of the world, not of a scene — same reasoning that makes
# TimeManager an autoload in the Day/Night pack. This owns what the weather IS;
# the Weather2D / Weather3D drivers only read it and draw.
#
# Public API:
#   WeatherManager.get_state() -> String
#   WeatherManager.get_intensity() -> float          # 0..1, ramped not snapped
#   WeatherManager.set_state(state, blend_seconds)
#   WeatherManager.register_state(id, vis_floor, traction_floor, precipitating)
#   WeatherManager.force_clear()
#   WeatherManager.set_paused(bool) / set_change_scale(float)
#   WeatherManager.get_visibility_factor() -> float  # 1.0 clear .. 0.25 fog
#   WeatherManager.get_traction_factor() -> float    # 1.0 dry .. 0.6 snow
#

signal state_changed(state: String, intensity: float)
signal intensity_changed(intensity: float)
signal state_registered(state: String)

# Strings, not an enum, so a buyer can add "ashfall" without editing the addon.
# The registry below is what makes that true rather than merely stylish.
const STATE_CLEAR := "clear"
const STATE_CLOUDY := "cloudy"
const STATE_RAIN := "rain"
const STATE_STORM := "storm"
const STATE_SNOW := "snow"
const STATE_FOG := "fog"

## The six shipped states. Wind is deliberately NOT here — it's an axis every
## state carries, because "windy rain" has to be representable.
const DEFAULT_STATES: Array[String] = [
	STATE_CLEAR, STATE_CLOUDY, STATE_RAIN, STATE_STORM, STATE_SNOW, STATE_FOG,
]

## How far each factor falls at FULL intensity. 1.0 means the state never costs
## anything. Cloudy barely dents sight; fog is what blinds you.
const DEFAULT_VISIBILITY_FLOOR := {
	STATE_CLEAR: 1.0, STATE_CLOUDY: 0.85, STATE_RAIN: 0.6,
	STATE_STORM: 0.4, STATE_SNOW: 0.35, STATE_FOG: 0.25,
}
const DEFAULT_TRACTION_FLOOR := {
	STATE_CLEAR: 1.0, STATE_CLOUDY: 1.0, STATE_RAIN: 0.8,
	STATE_STORM: 0.75, STATE_SNOW: 0.6, STATE_FOG: 1.0,
}
const DEFAULT_PRECIPITATING: Array[String] = [STATE_RAIN, STATE_STORM, STATE_SNOW]

## Project settings the chooser's "Whole game" outcome writes: how weather behaves
## when the game starts. No-code, baked into project.godot, re-editable any time.
## Read once at _ready; a save-loaded state overrides it.
const STARTUP_STATE_SETTING := "weather/startup_state"        # "dynamic" | a state id
const STARTUP_INTENSITY_SETTING := "weather/startup_intensity"
const STARTUP_CLIMATE_SETTING := "weather/climate"
const MODE_DYNAMIC := "dynamic"

## What can follow what, and how likely. Snow is absent from the temperate table
## on purpose — a desert that randomly snows reads as a bug, so cold weather is
## something you opt into rather than something that ambushes you.

## Intensity a state aims for when it arrives. Clear means clear.
const DEFAULT_INTENSITY_RANGE := {
	STATE_CLEAR: [0.0, 0.0], STATE_CLOUDY: [0.3, 0.7], STATE_RAIN: [0.35, 0.9],
	STATE_STORM: [0.7, 1.0], STATE_SNOW: [0.3, 0.9], STATE_FOG: [0.4, 1.0],
}

@export var start_state: String = STATE_CLEAR
@export_range(0.0, 1.0) var start_intensity: float = 0.0
## Hard freeze: nothing moves, including an intensity ramp already in flight. If
## you want the weather held but a commanded set_state to still fade in, use
## change_scale = 0 instead.
@export var paused: bool = false
## Multiplier on how fast weather moves ON to the next forecast entry. 1 = normal,
## 0 = held. Unlike `paused` this leaves the intensity ramp running, so a
## set_state() you asked for still arrives.
@export var change_scale: float = 1.0
## How many steps ahead the queue is rolled. This IS the forecast horizon.
## 0 randomizes. Set it to anything else for a reproducible weather history.
@export var rng_seed: int = 0
## Mirror state changes onto Events.custom_event so Quests and Achievements can
## react ("survive a blizzard") with no glue. Off by default.

@export var intensity_ramp_per_second: float = 0.25


@export_group("Wind (an axis, not a state)")
## Compass direction the wind blows, in degrees. Drivers tilt precipitation by it.
@export_range(0.0, 360.0) var wind_direction_degrees: float = 0.0
@export_range(0.0, 1.0) var wind_strength: float = 0.2

var _state: String = STATE_CLEAR
var _intensity: float = 0.0
var _target_intensity: float = 0.0

# The pre-rolled future. Entries are {state, intensity, duration}.

# The registry. Instance state, not consts, so register_state() can extend it —
# and hoisted off the hot path, because the drivers and the AI sight check read
# the factors below every frame.
var _states: Array[String] = DEFAULT_STATES.duplicate()
var _visibility_floor: Dictionary = DEFAULT_VISIBILITY_FLOOR.duplicate()
var _traction_floor: Dictionary = DEFAULT_TRACTION_FLOOR.duplicate()
var _precipitating: Array[String] = DEFAULT_PRECIPITATING.duplicate()
var _intensity_range: Dictionary = DEFAULT_INTENSITY_RANGE.duplicate()
var _custom_states: Array[Dictionary] = []   # replayed on load

# The ramp rate actually in force. set_state(blend) aims it for ONE transition;
# it must never overwrite the exported default, or a single blended call
# silently re-paces every storm for the rest of the game.
var _active_ramp: float = 0.25

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_apply_startup_setting()   # "Whole game" chooser outcome, before anything reads these
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	if start_state not in _states:
		push_warning("WeatherManager: start_state '%s' is not a known state; starting clear instead." % start_state)
		start_state = STATE_CLEAR
	_state = start_state
	_intensity = clampf(start_intensity, 0.0, 1.0)
	_target_intensity = _intensity
	# The clock has to be cached before the first _roll_duration(), or that roll
	# uses the standalone seconds base while every queued entry uses game-hours —
	# and the opening weather sits there for four in-game days.
	_active_ramp = intensity_ramp_per_second


# "Whole game" from the chooser: read how weather should behave at startup and set
# start_state / start_intensity / paused to match. Dynamic keeps rolling; a pinned
# Pure setting read, no side effects beyond our own exports.
func _apply_startup_setting() -> void:
	if not ProjectSettings.has_setting(STARTUP_STATE_SETTING):
		return
	var want := String(ProjectSettings.get_setting(STARTUP_STATE_SETTING, MODE_DYNAMIC))
	var intensity := float(ProjectSettings.get_setting(STARTUP_INTENSITY_SETTING, start_intensity))
	if is_finite(intensity):
		start_intensity = clampf(intensity, 0.0, 1.0)
	if want == MODE_DYNAMIC:
		paused = false
		return
	if want in _states:
		start_state = want
		paused = true      # pinned: this weather and no other
	else:
		push_warning("WeatherManager: startup state '%s' is not a known state; running dynamic instead." % want)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or paused:
		return
	# The ramp is visual smoothing, so change_scale (which paces how fast weather
	# MOVES ON) must not strand a half-finished fade.
	_advance_ramp(delta)


func _roll_intensity(state: String) -> float:
	var r: Array = _intensity_range.get(state, [0.3, 0.9])
	return _rng.randf_range(float(r[0]), float(r[1]))


func _advance_ramp(delta: float) -> void:
	if is_equal_approx(_intensity, _target_intensity):
		return
	var rate := _active_ramp if _active_ramp > 0.0 else intensity_ramp_per_second
	var stepped := move_toward(_intensity, _target_intensity, rate * delta)
	if not is_equal_approx(stepped, _intensity):
		_intensity = stepped
		intensity_changed.emit(_intensity)


# ---- the registry ---------------------------------------------------------

## Add a weather state of your own — "ashfall", "acid_rain", "sandstorm" —
## without editing the addon. Tell it how far it drags visibility and traction
## at full intensity (1.0 = costs nothing) and whether it counts as
## precipitation. Returns false if the id is empty or already taken.
func register_state(id: String, visibility_floor: float = 1.0,
		traction_floor: float = 1.0, precipitating: bool = false) -> bool:
	var key := id.strip_edges()
	if key == "":
		push_error("WeatherManager: register_state needs a non-empty id; ignoring.")
		return false
	if key in _states:
		push_warning("WeatherManager: state '%s' is already registered; ignoring." % key)
		return false
	if not is_finite(visibility_floor) or not is_finite(traction_floor):
		push_error("WeatherManager: register_state('%s') got a non-finite floor; ignoring." % key)
		return false
	var vis := clampf(visibility_floor, 0.0, 1.0)
	var trac := clampf(traction_floor, 0.0, 1.0)
	_states.append(key)
	_visibility_floor[key] = vis
	_traction_floor[key] = trac
	if precipitating:
		_precipitating.append(key)
	# Kept so save/load can replay them — a buyer's custom state must survive a
	# reload even though the registry itself is runtime state.
	_custom_states.append({
		"id": key, "visibility_floor": vis, "traction_floor": trac,
		"precipitating": precipitating,
	})
	state_registered.emit(key)
	return true


func is_state_registered(id: String) -> bool:
	return id in _states


## Every state this game knows, shipped plus registered. A copy — mutating the
## returned array must not quietly reshape the registry.
func get_states() -> Array[String]:
	return _states.duplicate()


# ---- public read API ------------------------------------------------------

func get_state() -> String:
	return _state

func get_intensity() -> float:
	return _intensity

## What the current weather is ramping toward. Drivers that want the settled
## look rather than the live one read this.
func get_target_intensity() -> float:
	return _target_intensity

func is_precipitating() -> bool:
	return _state in _precipitating

func get_wind_direction_degrees() -> float:
	return wind_direction_degrees

func get_wind_strength() -> float:
	return wind_strength

## 1.0 clear, falling toward the state's floor as intensity rises. Enemy AI
## reads this for sight range.
func get_visibility_factor() -> float:
	return lerpf(1.0, float(_visibility_floor.get(_state, 1.0)), _intensity)

## 1.0 dry, falling toward the state's floor as intensity rises. The controller
## reads this for friction.
func get_traction_factor() -> float:
	return lerpf(1.0, float(_traction_floor.get(_state, 1.0)), _intensity)


# ---- public write API -----------------------------------------------------

## Force the weather. blend_seconds <= 0 snaps; anything higher sets the ramp
## rate so the change reads as weather rolling in rather than teleporting.
func set_state(state: String, blend_seconds: float = 2.0) -> void:
	if state not in _states:
		push_error("WeatherManager: unknown weather state '%s'; ignoring. Register it first with register_state()." % state)
		return
	if not is_finite(blend_seconds):
		push_error("WeatherManager: set_state got a non-finite blend (%s); using an instant change." % blend_seconds)
		blend_seconds = 0.0
	var target := _roll_intensity(state)
	# Aim the ramp for this transition only. A zero delta would compute a zero
	# rate and freeze every future ramp, so fall back to the export instead.
	var delta_i := absf(target - _intensity)
	_active_ramp = (delta_i / blend_seconds) if blend_seconds > 0.0 and delta_i > 0.0 \
		else intensity_ramp_per_second
	_apply(state, target, blend_seconds <= 0.0)


func set_intensity(value: float) -> void:
	# A non-finite intensity poisons every driver reading it, once per frame,
	# forever — and it always comes from a divide-by-zero upstream.
	if not is_finite(value):
		push_error("WeatherManager: set_intensity called with a non-finite value (%s); ignoring." % value)
		return
	var v := clampf(value, 0.0, 1.0)
	_target_intensity = v
	if is_equal_approx(v, _intensity):
		return
	_intensity = v
	intensity_changed.emit(_intensity)


func set_paused(value: bool) -> void:
	paused = value


func set_change_scale(value: float) -> void:
	if not is_finite(value):
		push_error("WeatherManager: set_change_scale called with a non-finite value (%s); ignoring." % value)
		return
	change_scale = maxf(0.0, value)


func force_clear() -> void:
	# Intensity first, then state. The other order announces
	# state_changed("clear", 1.0) — clear weather at full strength — and a driver
	# sizing its emission off that payload flashes for a frame before the
	# intensity catches up. Dropping to zero under the old state draws nothing,
	# which is what we want mid-transition.
	set_intensity(0.0)
	set_state(STATE_CLEAR, 0.0)


# One coherent announcement. State and intensity change together during a
# transition, so pushing them through two independent setters would let a driver
# read a pair that was never true.
func _apply(state: String, target: float, snap: bool = false) -> void:
	var changed := state != _state
	_state = state
	_target_intensity = clampf(target, 0.0, 1.0)
	if snap:
		_intensity = _target_intensity
	if changed:
		state_changed.emit(_state, _intensity)
	if snap:
		intensity_changed.emit(_intensity)


