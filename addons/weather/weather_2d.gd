class_name Weather2D
extends CanvasLayer

# Drop this into a 2D scene and it draws whatever the WeatherManager says the
# weather is: precipitation over the viewport, plus a tint.
#
# IT IS A CanvasLayer, NOT A CanvasModulate, and that is deliberate. DayNight2D
# in the Day/Night pack IS a CanvasModulate, and a canvas only honours one — a
# second would fight it, last-one-in-the-tree wins, and a buyer who adds rain
# would watch their day/night cycle stop working. So the tint here is a
# full-screen ColorRect using a MULTIPLY blend, which composites over whatever
# tint Day/Night already applied instead of replacing it.
#
# Being a CanvasLayer also means the precipitation is screen-space: it covers the
# viewport at any camera zoom or position with no camera-following at all, which
# is both what 2D rain should look like and one fewer thing to get wrong.
#
# Put your HUD on a CanvasLayer with a higher `layer` than this one so the UI
# doesn't sit under the weather.

@export var profile: WeatherProfile
## How many pixels one metre of the profile's fall_speed is worth. Weather speeds
## are authored in metres for the 3D driver; this converts them for 2D.
@export var pixels_per_metre: float = 64.0
## Extra margin either side of the viewport, so wind-blown precipitation doesn't
## start or stop at a visible edge.
@export var edge_margin: float = 120.0

@export_group("Optional drivers")
@export var drive_tint: bool = true
## Turns each state's fog_density into a light haze over the scene. Without this
## 2D fog is only a slightly darker tint, which reads as nothing at all — a
## multiply tint can darken but it can never wash a scene out, and washing out
## is what fog actually looks like.
@export var drive_haze: bool = true
## Scales the profile's (3D-authored) fog_density into a 2D haze alpha.
@export_range(0.0, 20.0) var haze_scale: float = 6.0

var _particles: GPUParticles2D
var _process_mat: ParticleProcessMaterial
var _tint: ColorRect
var _haze: ColorRect
var _audio: AudioStreamPlayer
var _wm: Node

var _state: String = "clear"
var _intensity: float = 0.0
var _texture_cache: Dictionary = {}


func _ready() -> void:
	if profile == null:
		profile = WeatherProfile.new()
	_build()
	_wm = get_node_or_null("/root/WeatherManager")
	if _wm != null:
		if _wm.has_signal("state_changed"):
			_wm.state_changed.connect(_on_state_changed)
		if _wm.has_signal("intensity_changed"):
			_wm.intensity_changed.connect(_on_intensity_changed)
		_state = String(_wm.get_state())
		_intensity = float(_wm.get_intensity())
	get_viewport().size_changed.connect(_on_viewport_resized)
	_apply()


func _build() -> void:
	# Multiply blend, so this darkens what is already on screen rather than
	# painting over it. At white it is a no-op, which is what "clear" wants.
	_tint = ColorRect.new()
	_tint.color = Color(1, 1, 1)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_tint.material = mat
	add_child(_tint)

	# Drawn over the multiply tint and under the precipitation: the tint darkens,
	# the haze washes out, and rain still reads crisply on top of both.
	_haze = ColorRect.new()
	_haze.color = Color(1, 1, 1, 0)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_haze)

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.direction = Vector3(0, 1, 0)     # 2D screen space: +Y is down
	_process_mat.spread = 0.0
	_process_mat.gravity = Vector3.ZERO

	_particles = GPUParticles2D.new()
	_particles.process_material = _process_mat
	_particles.emitting = false
	add_child(_particles)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_resize()


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _on_viewport_resized() -> void:
	_resize()
	_apply_state()


func _resize() -> void:
	var vs := _viewport_size()
	_tint.position = Vector2.ZERO
	_tint.size = vs
	_haze.position = Vector2.ZERO
	_haze.size = vs
	# Spawn above the top edge so drops enter already moving, never popping in.
	_particles.position = Vector2(vs.x * 0.5, -edge_margin * 0.5)
	_process_mat.emission_box_extents = Vector3(vs.x * 0.5 + edge_margin, 1.0, 1.0)


# ---- manager hookup -------------------------------------------------------

func _on_state_changed(state: String, intensity: float) -> void:
	_state = state
	_intensity = intensity
	_apply()


func _on_intensity_changed(intensity: float) -> void:
	_intensity = intensity
	_apply_intensity()   # the ramp fires this every frame; never rebuild here


func _apply() -> void:
	_apply_state()
	_apply_intensity()


# Everything that only changes when the WEATHER changes. Assigning amount,
# lifetime or preprocess reallocates the particle buffer, so this must stay off
# the per-frame intensity path.
func _apply_state() -> void:
	if _particles == null:
		return
	var look := profile.get_look(_state)
	var vs := _viewport_size()
	var speed_px := maxf(1.0, look.fall_speed * pixels_per_metre)

	_particles.amount = maxi(1, profile.get_particle_count(_state, 1.0))
	_particles.lifetime = (vs.y + edge_margin * 2.0) / speed_px
	# Pre-fill, or precipitation falls in from the top of the screen on every
	# state change instead of already being there.
	_particles.preprocess = _particles.lifetime
	_particles.texture = look.texture if look.texture != null else _streak_texture(look)
	# The sprite is authored in pixels, so scale it to the size the profile asks
	# for rather than drawing it at whatever resolution it happens to be.
	var want_px := maxf(1.0, look.particle_size.y * pixels_per_metre)
	var tex_h := float(_particles.texture.get_height()) if _particles.texture != null else want_px
	var sc := clampf(want_px / maxf(1.0, tex_h), 0.01, 20.0)
	_process_mat.scale_min = sc
	_process_mat.scale_max = sc
	# Colour rides the node modulate, because the shipped sprites are white.
	_particles.modulate = look.particle_color if look.texture != null else Color(1, 1, 1)

	_process_mat.initial_velocity_min = speed_px * 0.85
	_process_mat.initial_velocity_max = speed_px * 1.15

	# Wind pushes sideways. In screen space that is simply +/- X.
	var wind_dir := 0.0
	var wind_str := 0.0
	if _wm != null:
		wind_dir = deg_to_rad(float(_wm.get_wind_direction_degrees()))
		wind_str = float(_wm.get_wind_strength())
	var push := sin(wind_dir) * wind_str * look.wind_bias * speed_px * 0.5
	_process_mat.gravity = Vector3(push, speed_px * 0.25, 0.0)

	_fit_visibility(push)
	_apply_audio(look)


# The cheap path, safe every frame while intensity ramps.
func _apply_intensity() -> void:
	if _particles == null:
		return
	var full := profile.get_particle_count(_state, 1.0)
	var ratio := 0.0 if full <= 0 else clampf(float(profile.get_particle_count(_state, _intensity)) / float(full), 0.0, 1.0)
	_particles.amount_ratio = ratio
	_particles.emitting = ratio > 0.0
	_particles.visible = ratio > 0.0
	if drive_tint and _tint != null:
		_tint.color = profile.get_tint(_state, _intensity)
		_tint.visible = true
	elif _tint != null:
		_tint.visible = false

	if drive_haze and _haze != null:
		var look := profile.get_look(_state)
		var a := clampf(profile.get_fog_density(_state, _intensity) * haze_scale, 0.0, 0.95)
		var c := look.fog_color
		c.a = a
		_haze.color = c
		_haze.visible = a > 0.0
	elif _haze != null:
		_haze.visible = false


# GPUParticles2D culls against visibility_rect exactly like the 3D node culls
# against its AABB, and the default is a small box around the emitter. The
# emitter sits above the top of the screen, so the default rect never reaches the
# viewport and the whole system is culled while emitting and amount read fine.
func _fit_visibility(side_push: float) -> void:
	var vs := _viewport_size()
	var drift := absf(side_push) * _particles.lifetime + edge_margin
	_particles.visibility_rect = Rect2(
		Vector2(-vs.x * 0.5 - drift, -edge_margin),
		Vector2(vs.x + drift * 2.0, vs.y + edge_margin * 3.0))


# A soft vertical streak, built rather than shipped, so the pack carries no image
# assets and no licensing surface. Phase 6 swaps in the nicer generated set.
func _streak_texture(look: WeatherLook) -> Texture2D:
	# pixels_per_metre is part of the SIZE, so it has to be part of the key —
	# otherwise changing it hands back a stale texture at the old scale.
	var key := "%d_%d_%d_%s" % [int(look.particle_size.x * 1000), int(look.particle_size.y * 1000),
		int(pixels_per_metre * 100), look.particle_color]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var w := maxi(1, int(round(look.particle_size.x * pixels_per_metre)))
	var h := maxi(1, int(round(look.particle_size.y * pixels_per_metre)))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		# fade the head and tail so drops read as motion rather than as sticks
		var a := sin((float(y) + 0.5) / float(h) * PI)
		for x in w:
			var c := look.particle_color
			c.a *= a
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


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
