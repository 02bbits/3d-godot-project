class_name Modifier
extends Resource

# Data + optional behavior. Stat-only mods are pure .tres files; behavioral
# mods subclass this and override the hooks they need. Hooks receive the
# damage ctx (mutating it changes the pipeline outcome) and the owning player.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var tags: Array[StringName] = []
@export var rarity: int = 0 # 0 common, 1 rare, 2 chaos
@export var stackable: bool = false
@export var max_stacks: int = 1
@export var exclusive_group: StringName

@export var stat_adds: Dictionary = {}
@export var stat_mults: Dictionary = {}


func on_damage_dealt(_ctx: Dictionary, _me: Node) -> void:
	pass


func on_damage_taken(_ctx: Dictionary, _me: Node) -> void:
	pass


func on_kill(_ctx: Dictionary, _me: Node) -> void:
	pass


func on_round_start(_me: Node) -> void:
	pass
