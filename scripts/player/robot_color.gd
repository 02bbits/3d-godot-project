class_name RobotColor
extends RefCounted

## Player robot colors. The KayKit dummy is textured from one palette atlas;
## its shell is the gray swatch (atlas column 2 of 8, top row). Each color gets
## a copy of the atlas with only that swatch tinted, applied to the six body
## meshes — joints, trim, leg markers and the accessories (helmet, back target)
## keep their original colors.

const PALETTE: Array[Color] = [
	Color("#FFC933"), Color("#FF9A3C"), Color("#FF6A5C"), Color("#FF7BC8"),
	Color("#A77BFF"), Color("#4DA2FE"), Color("#3FD6C8"), Color("#7ADF7C"),
	Color("#F4EEE2"), Color("#5A6474"),
]
const BODY_MESHES := [
	"Dummy_Body", "Dummy_Head", "Dummy_ArmLeft", "Dummy_ArmRight",
	"Dummy_LegLeft", "Dummy_LegRight",
]
# mid luminance of the gray shell swatch: shading above/below it brightens or
# darkens the tint, so the swatch's gradient survives the recolor
const SHELL_MID_LUMA := 0.55

static var _materials := {} # html color -> StandardMaterial3D


static func apply(model: Node, color: Color) -> void:
	for mesh_name in BODY_MESHES:
		var mesh := model.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh == null:
			continue
		var material := _material_for(mesh, color)
		if material != null:
			mesh.set_surface_override_material(0, material)


static func _material_for(mesh: MeshInstance3D, color: Color) -> Material:
	var key := color.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var base := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if base == null or base.albedo_texture == null:
		return null
	var image := base.albedo_texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	# ponytail: CPU recolor of one 128x256 swatch, cached per color; a shader
	# mask would avoid the copy if many colors per match ever matter.
	var w := image.get_width()
	var h := image.get_height()
	for y in range(0, int(h * 0.25)):
		for x in range(int(w * 0.25), int(w * 0.375)):
			var texel := image.get_pixel(x, y)
			var k := texel.get_luminance() / SHELL_MID_LUMA
			image.set_pixel(x, y, Color(minf(color.r * k, 1.0), minf(color.g * k, 1.0),
					minf(color.b * k, 1.0), texel.a))
	image.generate_mipmaps()
	var material := base.duplicate() as StandardMaterial3D
	material.albedo_texture = ImageTexture.create_from_image(image)
	_materials[key] = material
	return material
