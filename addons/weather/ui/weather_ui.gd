class_name WeatherUI
extends Control

# Minimal "Rain, heavy. Next: storm" readout. Point it at nothing. It finds the
# WeatherManager autoload and updates itself when the weather or the forecast
# changes. "Show the weather to the player" in Weather · Setup adds one in the
# bottom-right corner on its own CanvasLayer above the weather. Placed by hand,
# keep its CanvasLayer above the Weather2D layer, or the tint sits over it.

@export var show_strength: bool = true
## Steps out of the way while a Dialogue (Lite or Pro) conversation is on screen,
## so it never sits over the dialogue box.
@export var hide_during_dialogue: bool = true

var _label: Label
var _wm: Node

# Dialogue Lite and Pro, looked up by name so neither pack is needed
const _DIALOGUE := ["/root/DialoguesLite", "/root/DialogueManager"]

const _WORD := {
	"clear": "Clear", "cloudy": "Overcast", "rain": "Rain",
	"storm": "Storm", "snow": "Snow", "fog": "Fog",
}


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	# readable over snow and fog alike
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	# Pinned to the right edge (the Setup tab's bottom-right box), the text hugs
	# that edge and grows leftwards instead of running off the screen.
	if anchor_left >= 0.5:
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_label)
	_wm = get_node_or_null("/root/WeatherManager")
	if _wm != null:
		if _wm.has_signal("state_changed"):
			_wm.state_changed.connect(_on_changed)
		if _wm.has_signal("intensity_changed"):
			_wm.intensity_changed.connect(_on_intensity)
	for path in _DIALOGUE:
		var d := get_node_or_null(path)
		if d == null:
			continue
		for sig in ["dialogue_started", "dialogue_finished"]:
			if d.has_signal(sig):
				d.connect(sig, _on_dialogue.unbind(1))
	_refresh()
	_on_dialogue()


func _on_changed(_state: String, _intensity: float) -> void:
	_refresh()


# The dialogue box runs along the bottom of the screen, so step out of its corner
# while a conversation is up and come back when it ends.
func _on_dialogue() -> void:
	if _label == null:
		return
	var talking := false
	for path in _DIALOGUE:
		var d := get_node_or_null(path)
		if d != null and d.has_method("is_active") and bool(d.call("is_active")):
			talking = true
	_label.visible = not (hide_during_dialogue and talking)


func _on_intensity(_intensity: float) -> void:
	_refresh()


## Title-case name for a state, falling back to the raw id for anything a buyer
## registered themselves.
func word_for(state: String) -> String:
	return String(_WORD.get(state, state.capitalize()))


## How heavy it is, in words rather than a number, because "0.62" means nothing
## to a player.
func strength_word(intensity: float) -> String:
	if intensity <= 0.01:
		return ""
	if intensity < 0.35:
		return "light"
	if intensity < 0.7:
		return "steady"
	return "heavy"


func _refresh() -> void:
	if _label == null:
		return
	if _wm == null:
		_label.text = "Clear"
		return
	var state := String(_wm.get_state())
	var text := word_for(state)
	if show_strength:
		var s := strength_word(float(_wm.get_intensity()))
		if s != "":
			text += ", " + s
	_label.text = text
