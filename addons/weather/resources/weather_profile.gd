class_name WeatherProfile
extends Resource

# The look of the weather, per state. Mirrors DayNightProfile's contract from the
# Day/Night pack: every field is optional, sensible defaults are built lazily, so
# the drivers look right with a null profile and a buyer overrides only what they
# care about.
#
# Author a look for one state and leave the rest alone — get_look() falls through
# to the built-in for anything you haven't overridden.

## state id -> WeatherLook. Only the states you want to restyle need an entry.
@export var looks: Dictionary = {}

## Hard ceiling on particles regardless of what a look asks for. Precipitation is
## a fullscreen effect and a buyer's low-end target has to survive it.
@export_range(0, 40000) var max_particles: int = 4000

## Built by tools/gen_particles.gd, so the pack carries no third-party art.
const RAIN_TEXTURE := "res://addons/weather/textures/rain_streak.png"
const SNOW_TEXTURE := "res://addons/weather/textures/snow_flake.png"

var _defaults: Dictionary = {}
var _texture_cache: Dictionary = {}


func get_look(state: String) -> WeatherLook:
	var authored: Variant = looks.get(state)
	if authored is WeatherLook:
		return authored
	return _default_for(state)


## Particles for this state at this intensity, ceiling applied. The scale is what
## makes a drizzle and a downpour one state rather than two.
func get_particle_count(state: String, intensity: float) -> int:
	var look := get_look(state)
	var scaled := int(round(float(look.particle_count) * clampf(intensity, 0.0, 1.0)))
	return clampi(scaled, 0, max_particles)


func get_fog_density(state: String, intensity: float) -> float:
	return get_look(state).fog_density * clampf(intensity, 0.0, 1.0)


## Fades from untinted toward the look's tint as the weather sets in.
func get_tint(state: String, intensity: float) -> Color:
	return Color(1, 1, 1).lerp(get_look(state).tint, clampf(intensity, 0.0, 1.0))


func get_fall_velocity(state: String) -> float:
	return get_look(state).fall_speed


# ---- defaults (built once, lazily) ----------------------------------------

# Loaded once and shared. A missing file returns null rather than throwing, so a
# buyer who deleted the textures gets untextured quads instead of a broken pack.
func _texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = t
	return t


func _default_for(state: String) -> WeatherLook:
	if _defaults.has(state):
		return _defaults[state]
	var l := WeatherLook.new()
	match state:
		"cloudy":
			l.particle_count = 0
			l.fog_density = 0.004
			l.tint = Color(0.86, 0.88, 0.92)
		"rain":
			l.texture = _texture(RAIN_TEXTURE)
			l.particle_count = 1200
			l.particle_color = Color(0.55, 0.68, 0.88, 0.75)
			l.fall_speed = 14.0
			l.particle_size = Vector2(0.02, 0.45)
			l.wind_bias = 1.4
			l.fog_density = 0.012
			l.tint = Color(0.72, 0.78, 0.88)
		"storm":
			l.texture = _texture(RAIN_TEXTURE)
			l.particle_count = 2200
			l.particle_color = Color(0.5, 0.6, 0.8, 0.8)
			l.fall_speed = 19.0
			l.particle_size = Vector2(0.02, 0.6)
			l.wind_bias = 2.6
			l.fog_density = 0.03
			# Dark, or a storm over a sunny scene reads as a bright haze
			l.fog_color = Color(0.3, 0.33, 0.4)
			l.tint = Color(0.55, 0.6, 0.72)
		"snow":
			l.texture = _texture(SNOW_TEXTURE)
			l.particle_count = 900
			l.particle_color = Color(0.95, 0.97, 1.0, 0.9)
			l.fall_speed = 2.2
			l.particle_size = Vector2(0.07, 0.07)
			l.wind_bias = 3.2
			l.fog_density = 0.02
			l.tint = Color(0.88, 0.92, 0.98)
		"fog":
			l.particle_count = 0
			l.fog_density = 0.09
			l.fog_color = Color(0.7, 0.72, 0.75)
			l.tint = Color(0.8, 0.82, 0.85)
		_:  # clear, and anything a buyer registered without authoring a look
			l.particle_count = 0
			l.fog_density = 0.0
			l.tint = Color(1, 1, 1)
	_defaults[state] = l
	return l
