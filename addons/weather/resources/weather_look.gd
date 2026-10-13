class_name WeatherLook
extends Resource

# How one weather state looks. Every field has a usable value out of the box, so
# a buyer can restyle a single state without authoring the other five.
#
# Counts and densities here are the FULL-INTENSITY values. The drivers scale
# them by the live intensity, so a light drizzle and a downpour are the same
# look at different strengths rather than two separate states.

## Falling particles at full intensity. 0 means this state doesn't precipitate.
@export_range(0, 20000) var particle_count: int = 0
@export var particle_color: Color = Color(0.6, 0.7, 0.85, 0.8)
## Metres per second. Rain falls hard, snow drifts.
@export var fall_speed: float = 10.0
## Quad size. Rain wants a thin streak, snow wants a fleck.
@export var particle_size: Vector2 = Vector2(0.03, 0.4)
## How much the wind axis pushes this precipitation sideways.
@export_range(0.0, 8.0) var wind_bias: float = 1.0
## The sprite each particle draws. Left null the drivers fall back to an untextured
## quad, which still works but reads as hard-edged. The shipped textures are white
## with a soft alpha, so particle_color above does the colouring.
@export var texture: Texture2D = null

@export_group("Atmosphere")
## Environment fog density at full intensity. 0 leaves fog alone.
@export_range(0.0, 1.0) var fog_density: float = 0.0
@export var fog_color: Color = Color(0.6, 0.62, 0.66)
## Multiplied over the view by both drivers. White leaves the scene as it is; a
## storm's blue-grey darkens it without touching your lights.
@export var tint: Color = Color(1, 1, 1)

@export_group("Audio")
## Left empty on purpose. The Audio pack (#18) is the intended source; drop any
## AudioStream here and the driver loops it while this state is active.
@export var ambient_audio: AudioStream = null
@export_range(-40.0, 6.0) var audio_db: float = -6.0
