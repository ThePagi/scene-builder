@tool
extends Button
class_name ParentNodeSelector

signal path_selected(path: NodePath)

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	# pressing the button clears the selection
	path_selected.emit("")

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# can only drop if the data is a dictionary with a single node selected
	return (
		(typeof(data) == TYPE_DICTIONARY and data.get("type") == "nodes" and data.get("nodes"))
		and data.get("nodes").size() == 1
	)

func _drop_data(_position: Vector2, data: Variant) -> void:
	path_selected.emit(data.get("nodes")[0])

func set_node_info(node_name: String, node_icon: Texture2D):
	# Set the button text to the node name
	text = node_name
	tooltip_text = node_name
	icon = node_icon
	if not icon:
		modulate = Color.RED
	else:
		modulate = Color.AQUAMARINE
