extends Control

## A modifier's icon (scenes/ui/mods/mod_icon.tscn): rarity-coloured tile,
## type glyph and, for multi-level modifiers, a level badge that turns yellow
## at max level. Used by the draft cards, the HUD tray and the TAB list.

@export var show_badge := true

@onready var body: Control = $Body
@onready var ring: Control = $Body/Ring
@onready var tile: Control = $Body/Tile
@onready var glyph: TextureRect = $Body/Tile/Glyph
@onready var badge: Control = $Body/Badge
@onready var badge_label: Label = $Body/Badge/Label


## `level` < 0 shows the modifier's own (owned) level
func set_mod(mod: Modifier, level := -1) -> void:
	if level < 0:
		level = mod.level
	tile.self_modulate = ModRules.rarity_color(mod.rarity)
	glyph.texture = ModRules.TYPES[mod.type].icon
	badge.visible = show_badge and mod.max_level > 1
	badge.theme_type_variation = &"ModBadgeMax" if level >= mod.max_level else &"ModBadge"
	badge_label.text = str(level)


## a fresh pick: bounce in, highlight ring held for `hold` seconds
func pop(hold := 0.0) -> void:
	ring.visible = true
	body.scale = Vector2.ONE * 1.35
	var tween := create_tween()
	tween.tween_property(body, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_callback(ring.hide)
