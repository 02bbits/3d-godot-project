extends Control

## One draft offer (scenes/ui/mods/mod_card.tscn), filled entirely from the
## Modifier's data: rarity header, type chip, icon, name, per-pick stat lines,
## level pips (owned / this pick / empty) and a tag. Emits `chosen` on click.

signal chosen(mod: Modifier)

const LIFT := -10.0
const DIMMED := 0.35
const VALUE_STYLES := {
	Modifier.TONE_GOOD: &"ModValueGood",
	Modifier.TONE_BAD: &"ModValueBad",
	Modifier.TONE_NEUTRAL: &"ModValue",
}

@onready var button: Button = $Button
@onready var header: Control = %Header
@onready var rarity_label: Label = %Rarity
@onready var type_icon: TextureRect = %TypeIcon
@onready var type_label: Label = %TypeName
@onready var icon: Control = %Icon
@onready var name_label: Label = %Name
@onready var desc_label: Label = %Desc
@onready var stats: VBoxContainer = %Stats
@onready var pips: HBoxContainer = %Pips
@onready var tag: PanelContainer = %Tag
@onready var tag_label: Label = %TagLabel

var offer: Modifier
var _lift_tween: Tween


func _ready() -> void:
	button.pressed.connect(func() -> void: chosen.emit(offer))
	for hover_signal in [button.mouse_entered, button.mouse_exited,
			button.focus_entered, button.focus_exited]:
		hover_signal.connect(_update_lift, CONNECT_DEFERRED)


## `owned`: the level the player already has (0 = not owned)
func set_offer(mod: Modifier, owned: int) -> void:
	offer = mod
	var rarity: Dictionary = ModRules.RARITIES[mod.rarity]
	var type: Dictionary = ModRules.TYPES[mod.type]
	header.self_modulate = rarity.color
	rarity_label.text = rarity.name
	type_icon.texture = type.icon
	type_label.text = type.name
	icon.set_mod(mod, owned + 1)
	name_label.text = mod.display_name.to_upper()
	desc_label.text = mod.description
	var lines := mod.describe(1)
	NodeUtil.fit_children(stats, lines.size())
	for i in lines.size():
		var row := stats.get_child(i)
		row.get_node("Label").text = lines[i].label
		var value: Label = row.get_node("Value")
		value.text = lines[i].value
		value.theme_type_variation = VALUE_STYLES[lines[i].tone]
	# owned levels and the one this pick adds are filled; this pick is ringed
	NodeUtil.fit_children(pips, mod.max_level)
	for i in mod.max_level:
		var fill: Control = pips.get_child(i).get_node("Fill")
		var filled := i <= owned
		fill.theme_type_variation = &"ModPipOn" if filled else &"ModPip"
		fill.self_modulate = rarity.color if filled else Color.WHITE
		pips.get_child(i).get_node("Ring").visible = i == owned
	var text := "LEVEL %d" % (owned + 1)
	if mod.max_level == 1:
		text = "SINGLE USE"
	elif owned + 1 >= mod.max_level:
		text = "MAX LEVEL"
	elif owned == 0:
		text = "NEW"
	tag.theme_type_variation = &"ModTagMax" if text == "MAX LEVEL" else &"ModTag"
	tag_label.text = text
	# a fresh offer: clickable, full opacity, resting
	modulate.a = 1.0
	button.disabled = false
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.set_pressed_no_signal(false)
	_update_lift()


## After the pick: the choice stays lifted and ringed, the rest fade out.
func lock(is_choice: bool) -> void:
	button.set_pressed_no_signal(is_choice)
	button.disabled = not is_choice
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.release_focus()
	modulate.a = 1.0 if is_choice else DIMMED
	_update_lift()


func _update_lift() -> void:
	var up := button.button_pressed or (not button.disabled
			and button.mouse_filter != Control.MOUSE_FILTER_IGNORE
			and (button.is_hovered() or button.has_focus()))
	if _lift_tween != null:
		_lift_tween.kill()
	_lift_tween = create_tween()
	_lift_tween.tween_property(button, "position:y", LIFT if up else 0.0, 0.12)
