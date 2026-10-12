extends PanelContainer

## TAB details beside the scoreboard (scenes/player/hud/mod_list.tscn): each
## active modifier with its icon, name, summary at its level and level pips.
## Hidden while there are none.

@onready var rows: VBoxContainer = %Rows


func show_mods(mods: Array[Modifier]) -> void:
	visible = not mods.is_empty()
	NodeUtil.fit_children(rows, mods.size())
	for i in mods.size():
		var mod := mods[i]
		var row := rows.get_child(i)
		row.get_node("Icon").set_mod(mod)
		row.get_node("Text/Name").text = mod.display_name
		row.get_node("Text/Summary").text = mod.summary()
		var pips: HBoxContainer = row.get_node("Pips")
		NodeUtil.fit_children(pips, mod.max_level if mod.max_level > 1 else 0)
		for p in pips.get_child_count():
			var pip: Control = pips.get_child(p)
			pip.theme_type_variation = &"ModPipOn" if p < mod.level else &"ModPip"
			pip.self_modulate = ModRules.rarity_color(mod.rarity) if p < mod.level \
					else Color.WHITE
