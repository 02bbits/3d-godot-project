class_name NodeUtil
extends RefCounted

## Lists authored in scenes: the first child of `parent` is the template
## (styled in the editor); this grows or shrinks the children to `count` by
## duplicating it. The template itself stays, hidden, when `count` is 0.
static func fit_children(parent: Node, count: int) -> void:
	while parent.get_child_count() < count:
		parent.add_child(parent.get_child(0).duplicate())
	while parent.get_child_count() > maxi(count, 1):
		var last := parent.get_child(-1)
		parent.remove_child(last)
		last.queue_free()
	for child in parent.get_children():
		child.visible = count > 0
