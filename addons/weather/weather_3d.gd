class_name Weather3D
extends Node3D

# Drop this into a 3D scene, point it at your camera, and it draws whatever the
# WeatherManager says the weather is: precipitation, fog, wind push, and storm
# lightning. No other wiring.
#
# The emitter rides above the camera with local_coords OFF, which is the detail
# every free rain tutorial gets wrong: with local coords on, the drops are
# parented to the emitter and drag along with the player instead of falling
# through the world. Move sideways and the rain moves with you like a shower
# curtain. Off, they fall where they were born.

signal lightning_struck(strength: float)

@export_node_path("Camera3D") var camera_path: NodePath
@export_node_path("WorldEnvironment") var environment_path: NodePath
## Optional. Lightning flashes from the direction this light points.
@export_node_path("DirectionalLight3D") var sun_path: NodePath
@export var profile: WeatherProfile

@export_group("Emitter")
## Metres above the camera the precipitation spawns.
@export var spawn_height: float = 9.0
## Side length of the spawn box. Wider covers a faster camera, costs fill rate.
@export var area_size: float = 22.0

@export_group("Optional drivers")
@export var drive_fog: bool = true
## Multiplies each state's tint over the view, like Weather2D, so a storm darkens a
## sunlit scene without touching its lights. A HUD on the default canvas, or on any
## CanvasLayer at 0 or above, isn't tinted.
@export var drive_tint: bool = true
@export var enable_lightning: bool = true
## Average seconds between strikes at full storm intensity.
@export var lightning_interval: float = 4.0
## How bright the flash is, on Weather's own light rather than the scene's sun.
@export_range(0.0, 32.0, 0.1) var lightning_energy: float = 4.0
@export var lightning_color: Color = Color(0.85, 0.9, 1.0)
@export_range(0.02, 1.0, 0.01) var lightning_flash_time: float = 0.12

var _cam: Camera3D
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _particles: GPUParticles3D
var _process_mat: ParticleProcessMaterial
var _quad: QuadMesh
var _quad_mat: StandardMaterial3D
var _audio: AudioStreamPlayer
var _wm: Node

var _base_fog_enabled: bool = false
var _base_fog_density: float = 0.0

var _state: String = "clear"
var _intensity: float = 0.0
var _strike_in: float = 0.0
var _armed: bool = false
var _flash_left: float = 0.0
## Weather's own light for the flash. See _ensure_flash_light for why the shared
## sun cannot be used.
var _flash_light: DirectionalLight3D = null
var _flash_peak: float = 0.0
var _tint_layer: CanvasLayer
var _tint: ColorRect
var _rng := RandomNumberGenerator.new()


# Volumetric fog is a Forward+ feature. Plain depth fog works everywhere, so the
# driver uses depth fog as the baseline and layers volumetric on top only where
# it exists — rather than skipping fog entirely on the catalog's default renderer.
static func supports_volumetric_fog() -> bool:
	if RenderingServer.get_rendering_device() == null:
		return false
	return String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "forward_plus"


func _ready() -> void:
	_rng.randomize()
	if profile == null:
		profile = WeatherProfile.new()
	# NodePaths are resolved here, so anything wiring this node has to set them
	# BEFORE add_child or the lookup silently finds nothing.
	if camera_path != NodePath(""):
		_cam = get_node_or_null(camera_path) as Camera3D
	if environment_path != NodePath(""):
		_env = get_node_or_null(environment_path) as WorldEnvironment
	if _env != null and _env.environment != null:
		# Whatever fog the buyer already set up is the baseline. Weather adds to
		# it; clear skies return to it. Forcing fog_enabled=false on clear would
		# switch off atmosphere they authored themselves.
		_base_fog_enabled = _env.environment.fog_enabled
		_base_fog_density = _env.environment.fog_density
	if sun_path != NodePath(""):
		_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if _cam == null:
		_cam = get_viewport().get_camera_3d()

	_build_emitter()
	_build_tint()
	_audio = AudioStreamPlayer.new()
	add_child(_audio)

	_wm = get_node_or_null("/root/WeatherManager")
	if _wm != null:
		if _wm.has_signal("state_changed"):
			_wm.state_changed.connect(_on_state_changed)
		if _wm.has_signal("intensity_changed"):
			_wm.intensity_changed.connect(_on_intensity_changed)
		_state = String(_wm.get_state())
		_intensity = float(_wm.get_intensity())
	_apply()


func _build_emitter() -> void:
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(area_size * 0.5, 0.1, area_size * 0.5)
	_process_mat.direction = Vector3(0, -1, 0)
	_process_mat.spread = 0.0
	_process_mat.gravity = Vector3.ZERO

	_quad_mat = StandardMaterial3D.new()
	_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_quad = QuadMesh.new()
	_quad.material = _quad_mat

	_particles = GPUParticles3D.new()
	_particles.process_material = _process_mat
	_particles.draw_pass_1 = _quad
	_particles.local_coords = false      # the thing the tutorials get wrong
	_particles.position = Vector3(0, spawn_height, 0)
	_particles.emitting = false
	add_child(_particles)


# ---- manager hookup -------------------------------------------------------

func _on_state_changed(state: String, intensity: float) -> void:
	_state = state
	_intensity = intensity
	_apply()


func _on_intensity_changed(intensity: float) -> void:
	_intensity = intensity
	_apply_intensity()   # the ramp fires this every frame; never rebuild here


func _process(delta: float) -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
	if _cam != null:
		# Follow on X/Z only. Riding the camera's Y would make rain spawn below
		# the ground the moment the player walks downhill.
		global_position = Vector3(_cam.global_position.x, global_position.y, _cam.global_position.z)
	_tick_lightning(delta)


# ---- the look -------------------------------------------------------------

func _apply() -> void:
	_apply_state()
	_apply_intensity()


# Everything that only changes when the WEATHER changes. Assigning amount,
# lifetime or preprocess reallocates the particle buffer, so this must not run
# on the per-frame intensity ramp.
func _apply_state() -> void:
	if _particles == null:
		return
	var look := profile.get_look(_state)
	# amount is the state's FULL count; live density rides amount_ratio below.
	_particles.amount = maxi(1, profile.get_particle_count(_state, 1.0))
	_particles.lifetime = _lifetime_for(look)
	# Pre-fill the air. Without this the emitter starts empty and precipitation
	# rains down from the top of the sky — snow falls at ~2 m/s, so switching to
	# it would give the player three seconds of clear sky before the first flake
	# reaches eye level.
	_particles.preprocess = _particles.lifetime

	_quad.size = look.particle_size
	_quad_mat.albedo_color = look.particle_color
	# The shipped sprites are white with a soft alpha, so albedo_color above does
	# all the colouring and one texture serves rain, storm and anything a buyer
	# registers. Null is fine: a bare quad still draws, just hard-edged.
	_quad_mat.albedo_texture = look.texture

	_process_mat.initial_velocity_min = look.fall_speed * 0.85
	_process_mat.initial_velocity_max = look.fall_speed * 1.15
	_process_mat.emission_box_extents = Vector3(area_size * 0.5, 0.1, area_size * 0.5)

	# Wind pushes sideways along its compass heading, scaled by how much this
	# kind of precipitation catches the wind. Snow blows, rain mostly falls.
	var wind_dir := 0.0
	var wind_str := 0.0
	if _wm != null:
		wind_dir = deg_to_rad(float(_wm.get_wind_direction_degrees()))
		wind_str = float(_wm.get_wind_strength())
	var push := wind_str * look.wind_bias * look.fall_speed * 0.5
	_process_mat.gravity = Vector3(sin(wind_dir) * push, -look.fall_speed * 0.25, cos(wind_dir) * push)
	_fit_visibility(look, push)
	_apply_audio(look)


# The cheap path, safe to run every frame while intensity ramps. amount_ratio
# scales live emission WITHOUT reallocating, which is exactly what amount cannot do.
func _apply_intensity() -> void:
	if _particles == null:
		return
	var look := profile.get_look(_state)
	var full := profile.get_particle_count(_state, 1.0)
	var ratio := 0.0 if full <= 0 else clampf(float(profile.get_particle_count(_state, _intensity)) / float(full), 0.0, 1.0)
	_particles.amount_ratio = ratio
	var on := ratio > 0.0
	_particles.emitting = on
	_particles.visible = on
	_apply_fog(look)
	_apply_tint()


# Drops need to live long enough to fall past the camera, or they vanish at eye
# level. Derived rather than exported so a buyer can't accidentally cut it short.
func _lifetime_for(look: WeatherLook) -> float:
	return clampf((spawn_height + 6.0) / maxf(0.5, look.fall_speed), 0.4, 30.0)


# GPUParticles3D culls against visibility_aabb, which defaults to a small box
# around the emitter. This emitter rides the camera, so that default box sits
# above and behind the view and the renderer culls the entire system — emitting,
# visible and amount all read correct while nothing draws. The box has to cover
# where the particles actually GO, not where they are born.
func _fit_visibility(look: WeatherLook, side_push: float) -> void:
	var life := _particles.lifetime
	var reach := look.fall_speed * 1.15 * life + absf(_process_mat.gravity.y) * life * life
	var half := area_size * 0.5 + absf(side_push) * life + 2.0
	_particles.visibility_aabb = AABB(
		Vector3(-half, -reach - 2.0, -half),
		Vector3(half * 2.0, reach + 4.0, half * 2.0))


func _apply_fog(look: WeatherLook) -> void:
	if not drive_fog or _env == null or _env.environment == null:
		return
	var env: Environment = _env.environment
	var density := profile.get_fog_density(_state, _intensity)
	env.fog_enabled = _base_fog_enabled or density > 0.0
	env.fog_density = _base_fog_density + density
	if density > 0.0:
		env.fog_light_color = _fog_light(look)
	# Volumetric is the Forward+ bonus layer on top of the depth fog above.
	if supports_volumetric_fog():
		env.volumetric_fog_enabled = density > 0.0
		env.volumetric_fog_density = density * 0.5


# Weather2D's trick: a full-screen multiply. Layer -1 draws over the 3D world and
# under the default canvas, so a HUD made of plain Controls stays clean.
func _build_tint() -> void:
	_tint_layer = CanvasLayer.new()
	_tint_layer.layer = -1
	add_child(_tint_layer)
	_tint = ColorRect.new()
	_tint.color = Color(1, 1, 1)
	_tint.visible = false
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_tint.material = mat
	_tint_layer.add_child(_tint)


func _apply_tint() -> void:
	if _tint == null:
		return
	var c := profile.get_tint(_state, _intensity).lerp(Color(1, 1, 1), _flash_k())
	_tint.color = c
	# white multiplies to nothing, so don't draw it
	_tint.visible = drive_tint and not c.is_equal_approx(Color(1, 1, 1))


func _apply_audio(look: WeatherLook) -> void:
	if _audio == null:
		return
	if look.ambient_audio == null:
		if _audio.playing:
			_audio.stop()
		_audio.stream = null
		return
	if _audio.stream != look.ambient_audio:
		_audio.stream = look.ambient_audio
		_audio.play()
	_audio.volume_db = look.audio_db


# ---- lightning ------------------------------------------------------------

func _tick_lightning(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_light != null:
			if _flash_left <= 0.0:
				_flash_light.visible = false
			else:
				# Decays rather than cutting. A flash that vanishes between two
				# frames is the one thing an eye always catches.
				_flash_light.light_energy = _flash_peak * (_flash_left / maxf(lightning_flash_time, 0.0001))
		_show_flash()
	if not enable_lightning or _state != "storm" or _intensity <= 0.0:
		# Disarm on the way out, or the next storm walks straight into the
		# already-expired countdown and opens with an instant strike.
		_strike_in = 0.0
		_armed = false
		return
	if not _armed:
		# Arm on entering the storm. Gating this on the previous flash having
		# faded meant a storm arriving right after a strike skipped arming and
		# walked into an expired countdown.
		_armed = true
		_strike_in = _rng.randf_range(lightning_interval * 0.4, lightning_interval * 1.6)
	_strike_in -= delta * _intensity
	if _strike_in > 0.0:
		return
	_strike_in = _rng.randf_range(lightning_interval * 0.4, lightning_interval * 1.6)
	strike()


## Fire a strike now. Exposed so a cutscene or a quest can call for thunder.
func strike(strength: float = 1.0) -> void:
	_flash_left = lightning_flash_time
	_flash_peak = lightning_energy * strength
	_show_flash()
	var light := _ensure_flash_light()
	if light != null:
		# Point it wherever the scene's sun points, so the flash lights the world
		# from a direction that already makes sense. With no sun to copy, steeply
		# overhead, which is where lightning comes from anyway.
		light.global_rotation = _sun.global_rotation if _sun != null else Vector3(-1.2, 0.4, 0.0)
		light.light_energy = _flash_peak
		light.visible = true
	lightning_struck.emit(strength)


# A strike lights the fog and lifts the tint while it lasts. In a storm the fog is
# most of what's on screen, so a flash that only lit the ground went unnoticed.
func _flash_k() -> float:
	return clampf(_flash_left / maxf(lightning_flash_time, 0.0001), 0.0, 1.0)


func _show_flash() -> void:
	_flash_fog()
	_apply_tint()


func _fog_light(look: WeatherLook) -> Color:
	return look.fog_color.lerp(lightning_color, _flash_k() * 0.85)


# Only fog the weather is driving. A storm look authored with no fog leaves the
# buyer's own fog colour alone.
func _flash_fog() -> void:
	if not drive_fog or _env == null or _env.environment == null:
		return
	if profile.get_fog_density(_state, _intensity) <= 0.0:
		return
	_env.environment.fog_light_color = _fog_light(profile.get_look(_state))


## Weather owns the light it flashes, and never touches the scene's sun.
##
## It used to add energy to the sun and put it back afterwards. That works alone
## and fails the moment anything else drives the same light: the Day/Night pack
## rewrites the sun every tick, so the flash survived one frame at most and a
## storm looked like it had no lightning at all. Nobody files that as a bug,
## because there is nothing to see.
func _ensure_flash_light() -> DirectionalLight3D:
	if _flash_light != null and is_instance_valid(_flash_light):
		return _flash_light
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "LightningFlash"
	_flash_light.light_color = lightning_color
	_flash_light.light_energy = 0.0
	# No shadows. Godot really only does one directional shadow well, and a
	# second one popping in for an eighth of a second costs more than it adds.
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	add_child(_flash_light)
	return _flash_light
