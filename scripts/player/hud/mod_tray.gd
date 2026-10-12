extends HBoxContainer

## Bottom-left modifier tray (scenes/player/hud/mod_tray.tscn): the local
## player's modifiers as small icons, the first MAX_ICONS then "+N". A fresh
## pick pops its icon and shows a toast once gameplay resumes (the draft
## overlay hides the HUD until then).

const MAX_ICONS := 8
const TOAST_SECONDS := 3.0

@onready var icons: HBoxContainer = %Icons
@onready var more: Control = %More
@onready var more_label: Label = %MoreLabel
@onready var toast: Control = %Toast
@onready var toast_name: Label = %ToastName
@onready var toast_level: Label = %ToastLevel

var _mods: Array[Modifier] = []
var _pending: Modifier
var _toast_tween: Tween


func show_mods(mods: Array[Modifier]) -> void:
	_mods = mods
	var shown := mini(mods.size(), MAX_ICONS)
	NodeUtil.fit_children(icons, shown)
	for i in shown:
		icons.get_child(i).set_mod(mods[i])
	more.visible = mods.size() > MAX_ICONS
	more_label.text = "+%d" % (mods.size() - MAX_ICONS)


func celebrate(mod: Modifier) -> void:
	_pending = mod


func _process(_delta: float) -> void:
	if _pending == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or not is_visible_in_tree():
		return
	var mod := _pending
	_pending = null
	var index := _mods.find(mod)
	if index >= 0 and index < icons.get_child_count():
		icons.get_child(index).pop(TOAST_SECONDS)
	toast_name.text = mod.display_name.to_upper()
	toast_name.self_modulate = ModRules.rarity_color(mod.rarity)
	toast_level.text = "Level %d" % mod.level
	if mod.level >= mod.max_level:
		toast_level.text += " · MAX"
	toast.visible = true
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_callback(toast.hide)
