@tool
extends Control
class_name SceneBuilderDock

@export var config: SceneBuilderConfig

var plugin: EditorPlugin

# Paths
var data_dir: String = ""
var path_to_collection_names: String
var editor: EditorInterface
var undo_redo: EditorUndoRedoManager

# Constants

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var toolbox: SceneBuilderToolbox = SceneBuilderToolbox.new()


# Godot controls
var base_control: Control
var btn_use_local_space: Button

# SceneBuilderDock controls
var btns_collection_tabs: Array = [] # set in _enter_tree()
var commands: SceneBuilderCommands
# Options
var btn_use_surface_normal: CheckButton
var btn_surface_normal_x: CheckBox
var btn_surface_normal_y: CheckBox
var btn_surface_normal_z: CheckBox
var btn_parent_node_selector: ParentNodeSelector
var btn_group_surface_orientation: ButtonGroup
var btn_reload_all_items: Button
var menu_command_popup: MenuButton
var btn_cmd_create_items: Button
var icon_size: HSlider
var btn_replace_overlapping: CheckButton
# Path3D
var spinbox_separation_distance: SpinBox
var spinbox_jitter_x: SpinBox
var spinbox_jitter_y: SpinBox
var spinbox_jitter_z: SpinBox
var spinbox_y_offset: SpinBox
var btn_place_fence: Button

# Indicators
var lbl_indicator_x: Label
var lbl_indicator_y: Label
var lbl_indicator_z: Label
var lbl_indicator_scale: Label

# Updated with selected_parent()
var physics_space: PhysicsDirectSpaceState3D
var world3d: World3D
var viewport: Viewport
var camera: Camera3D

# Updated when reloading all collections
var collections: CollectionNames
var collection_names: Array[String] = []
var collection_colors: Array[Color] = []

# Also updated on tab button click
var selected_collection_id: int = 0
var items: Array[SceneBuilderItem] = []
var highlighters: Array[NinePatchRect] = []
# Also updated on item click
var selected_item_id: int = -1
var preview_instance: Node3D = null
var preview_instance_rid_array: Array[RID] = []

enum TransformMode {
	NONE,
	POSITION_X,
	POSITION_Y, 
	POSITION_Z,
	ROTATION_X,
	ROTATION_Y,
	ROTATION_Z,
	SCALE
}

var placement_mode_enabled: bool = false
var current_transform_mode: TransformMode = TransformMode.NONE

func is_transform_mode_enabled() -> bool:
	return current_transform_mode != TransformMode.NONE

# Preview item
var original_preview_basis: Basis = Basis.IDENTITY
var original_mouse_position: Vector2 = Vector2.ONE
var original_preview_scale: Vector3 = Vector3.ONE
var original_position_offset: Vector3
var position_offset: Vector3
var random_offset_y: float = 0
var preview_temp_parent: Node3D # Used as a parent to the preview item

var prev_parent: Node3D = null

func snap(pos: Vector3) -> Vector3:
	return (pos).snapped(items[selected_item_id].snap_to_grid)
func snap_rot(euler: Vector3) -> Vector3:
	return euler.snapped(Vector3.ONE*deg_to_rad(items[selected_item_id].snap_rotation))
func selected_parent()->Node3D:
	var sel = EditorInterface.get_selection().get_selected_nodes()
	#if len(sel) == 0:
	#	EditorInterface.get_selection().add_node(EditorInterface.get_edited_scene_root())
	#	sel = EditorInterface.get_selection().get_selected_nodes()
	if len(sel) == 1:
		if sel[0] is not Node3D:
			if btn_parent_node_selector:
				btn_parent_node_selector.set_node_info("A Node3D must be selected!", null)
			return null
		viewport = EditorInterface.get_editor_viewport_3d()
		world3d = viewport.find_world_3d()
		physics_space = world3d.direct_space_state
		camera = viewport.get_camera_3d()
		
		var node = sel[0]
		var node_name := node.get_class().split(".")[-1]
		var base = plugin.get_editor_interface().get_base_control()
		var node_icon := base.get_theme_icon(node_name, "EditorIcons")
		
		if node_icon == base.get_theme_icon("invalid icon", "EditorIcons"):
			node_icon = base.get_theme_icon("Node", "EditorIcons")
		if btn_parent_node_selector:
			btn_parent_node_selector.set_node_info(node.name, node_icon)
		return node
	else:
		if btn_parent_node_selector:
			btn_parent_node_selector.set_node_info("A Node3D must be selected!", null)
		return null

func init(p: EditorPlugin, cmd: SceneBuilderCommands, cfg: SceneBuilderConfig):
	plugin = p
	undo_redo = plugin.get_undo_redo()
	editor = plugin.get_editor_interface()
	commands = cmd
	config = cfg
	
# ---- Notifications -----------------------------------------------------------

func _enter_tree() -> void:
	path_to_collection_names = config.root_dir + "collection_names.tres"
	
	
	base_control = EditorInterface.get_base_control()

	# Found using: https://github.com/Zylann/godot_editor_debugger_plugin
	var _panel : Panel = editor.get_base_control()
	var _vboxcontainer15 : VBoxContainer = _panel.get_child(0)
	var _vboxcontainer26 : VBoxContainer = _vboxcontainer15.get_child(1).get_child(1).get_child(1).get_child(0)
	var _main_screen : VBoxContainer = _vboxcontainer26.get_child(0).get_child(0).get_child(0).get_child(1).get_child(0)
	var _hboxcontainer11486 : HBoxContainer = _main_screen.get_child(1).get_child(0).get_child(0).get_child(0)
	
	btn_use_local_space = _hboxcontainer11486.get_child(13)
	if !btn_use_local_space:
		printerr("[SceneBuilderDock] Unable to find use local space button")

	#region Initialize controls for the SceneBuilderDock
	
	var path : String = SceneBuilderToolbox.find_resource_with_dynamic_path("scene_builder_dock.tscn")
	if path == "":
		printerr("[SceneBuilderDock] scene_builder_dock.tscn was not found")
		return	

	# Options tab
	btn_use_surface_normal = %UseSurfaceNormal
	btn_surface_normal_x = %Orientation/X
	btn_surface_normal_y = %Orientation/Y
	btn_surface_normal_z = %Orientation/Z
	
	btn_parent_node_selector = %ParentNodeSelector
	
	#
	btn_group_surface_orientation = ButtonGroup.new()
	btn_surface_normal_x.button_group = btn_group_surface_orientation
	btn_surface_normal_y.button_group = btn_group_surface_orientation
	btn_surface_normal_z.button_group = btn_group_surface_orientation
	#
	btn_reload_all_items = ($"Settings/Tab/Options/Bottom/ReloadAllItems")
	btn_reload_all_items.pressed.connect(reload_all_items)
	menu_command_popup = ($"Settings/Tab/Options/Bottom/CommandsPopup")
	commands.fill_popup(menu_command_popup.get_popup())
	btn_cmd_create_items = ($"Settings/Tab/Options/QuickCommands/CreateItems")
	btn_cmd_create_items.pressed.connect(commands.create_scene_builder_items)
	icon_size = ($"Settings/Tab/Options/FirstRow/HBox/IconSize")
	icon_size.value_changed.connect(resize_icons)
	btn_replace_overlapping = ($"Settings/Tab/Options/FirstRow/HBox/ReplaceOverlapping")
	# Path3D tab
	spinbox_separation_distance = ($"Settings/Tab/Path3D/Separation/SpinBox")
	spinbox_jitter_x = ($"Settings/Tab/Path3D/Jitter/X")
	spinbox_jitter_y = ($"Settings/Tab/Path3D/Jitter/Y")
	spinbox_jitter_z = ($"Settings/Tab/Path3D/Jitter/Z")
	spinbox_y_offset = ($"Settings/Tab/Path3D/YOffset/Value")
	btn_place_fence = ($"Settings/Tab/Path3D/PlaceFence")
	btn_place_fence.pressed.connect(place_fence)

	# Indicators
	lbl_indicator_x = ($"Settings/Indicators/1")
	lbl_indicator_y = ($"Settings/Indicators/2")
	lbl_indicator_z = ($"Settings/Indicators/3")
	lbl_indicator_scale = ($"Settings/Indicators/4")

	#endregion

	# Collection tabs
	load_or_make_collections()
	select_collection(0)


func resize_icons(value: float):
	for c in ($"Collection/Scroll/Grid").get_children():
		(c as Control).custom_minimum_size = Vector2(value, value)


func _process(_delta: float) -> void:
	var sel_parent = selected_parent()
	if prev_parent != sel_parent:
		end_placement_mode()
		if sel_parent:
			prev_parent = sel_parent
	# Update preview item position
	if placement_mode_enabled and not is_transform_mode_enabled():
		populate_preview_instance_rid_array(preview_instance)
		var result = perform_raycast_with_exclusion(preview_instance_rid_array)
		if result and result.position:
			var p = result.position
			if preview_temp_parent.get_parent_node_3d():
				p = preview_temp_parent.get_parent_node_3d().to_local(p)
			var new_position: Vector3 = snap(p-items[selected_item_id].snap_offset)+items[selected_item_id].snap_offset
			# This offset prevents z-fighting when placing overlapping quads
			if items[selected_item_id].use_random_vertical_offset:
				new_position.y += random_offset_y

			preview_temp_parent.position = new_position + position_offset
			if btn_use_surface_normal.button_pressed:
				preview_temp_parent.basis = align_up(preview_temp_parent.global_transform.basis, result.normal)
				var quaternion = Quaternion(preview_temp_parent.basis.orthonormalized())
				if btn_surface_normal_x.button_pressed:
					quaternion = quaternion * Quaternion(Vector3(1, 0, 0), deg_to_rad(90))
				elif btn_surface_normal_z.button_pressed:
					quaternion = quaternion * Quaternion(Vector3(0, 0, 1), deg_to_rad(90))

func forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> EditorPlugin.AfterGUIInput:
	if event is InputEventMouseMotion:
		if placement_mode_enabled:
			var relative_motion: float
			if abs(event.relative.x) > abs(event.relative.y):
				relative_motion = event.relative.x
			else:
				relative_motion = -event.relative.y
			relative_motion *= 0.01 # Sensitivity factor

			match current_transform_mode:
				TransformMode.POSITION_X:
					preview_temp_parent.position.x += relative_motion
					position_offset.x += relative_motion
				TransformMode.POSITION_Y:
					preview_temp_parent.position.y += relative_motion
					position_offset.y += relative_motion
				TransformMode.POSITION_Z:
					preview_temp_parent.position.z += relative_motion
					position_offset.z += relative_motion
				TransformMode.ROTATION_X:
					if btn_use_local_space.button_pressed:
						preview_temp_parent.rotate_object_local(Vector3(1, 0, 0), relative_motion)
					else:
						preview_temp_parent.rotate_x(relative_motion)
				TransformMode.ROTATION_Y:
					if btn_use_local_space.button_pressed:
						preview_temp_parent.rotate_object_local(Vector3(0, 1, 0), relative_motion)
					else:
						preview_temp_parent.rotate_y(relative_motion)
				TransformMode.ROTATION_Z:
					if btn_use_local_space.button_pressed:
						preview_temp_parent.rotate_object_local(Vector3(0, 0, 1), relative_motion)
					else:
						preview_temp_parent.rotate_z(relative_motion)
				TransformMode.SCALE:
					var new_scale: Vector3 = preview_temp_parent.scale * (1 + relative_motion)
					if is_zero_approx(new_scale.x) or is_zero_approx(new_scale.y) or is_zero_approx(new_scale.z):
						new_scale = original_preview_scale
					preview_temp_parent.scale = new_scale

	if event is InputEventMouseButton:
		if event.is_pressed() and !event.is_echo():
			if placement_mode_enabled:
				var mouse_pos = viewport.get_mouse_position()
				if mouse_pos.x >= 0 and mouse_pos.y >= 0:
					if mouse_pos.x <= viewport.size.x and mouse_pos.y <= viewport.size.y:
						if event.button_index == MOUSE_BUTTON_LEFT:
							if is_transform_mode_enabled():
								# Confirm changes
								#original_preview_basis = preview_instance.basis
								original_position_offset = position_offset
								original_preview_scale = preview_temp_parent.scale
								original_preview_basis = Basis.from_euler(snap_rot(preview_temp_parent.basis.get_euler()))
								original_preview_basis = original_preview_basis.scaled(preview_temp_parent.basis.get_scale())
								preview_temp_parent.basis = original_preview_basis
								end_transform_mode()
								viewport.warp_mouse(original_mouse_position)
							else:
								instantiate_selected_item_at_position()
							return EditorPlugin.AFTER_GUI_INPUT_STOP

						elif event.button_index == MOUSE_BUTTON_RIGHT:
							if is_transform_mode_enabled():
								# Revert preview transformations
								print("[SceneBuilderDock] warping to: ", original_mouse_position)
								position_offset = original_position_offset
								preview_temp_parent.basis = original_preview_basis
								preview_temp_parent.scale = original_preview_scale
								end_transform_mode()
								viewport.warp_mouse(original_mouse_position)
								return EditorPlugin.AFTER_GUI_INPUT_STOP
							else:
								end_placement_mode()
								return EditorPlugin.AFTER_GUI_INPUT_STOP

	elif event is InputEventKey and placement_mode_enabled:
		if event.is_pressed() and !event.is_echo():
			if !event.alt_pressed and !event.ctrl_pressed:
				if event.shift_pressed:
					if event.keycode == config.x_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.POSITION_X:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.POSITION_X)
						else:
							start_transform_mode(TransformMode.POSITION_X)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.y_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.POSITION_Y:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.POSITION_Y)
						else:
							start_transform_mode(TransformMode.POSITION_Y)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.z_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.POSITION_Z:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.POSITION_Z)
						else:
							start_transform_mode(TransformMode.POSITION_Z)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
				else:
					if event.keycode == config.x_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.ROTATION_X:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.ROTATION_X)
						else:
							start_transform_mode(TransformMode.ROTATION_X)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.y_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.ROTATION_Y:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.ROTATION_Y)
						else:
							start_transform_mode(TransformMode.ROTATION_Y)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.z_axis:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.ROTATION_Z:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.ROTATION_Z)
						else:
							start_transform_mode(TransformMode.ROTATION_Z)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_4:
						if is_transform_mode_enabled():
							if current_transform_mode == TransformMode.SCALE:
								end_transform_mode()
							else:
								end_transform_mode()
								start_transform_mode(TransformMode.SCALE)
						else:
							start_transform_mode(TransformMode.SCALE)
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_5:
						if is_transform_mode_enabled():
							end_transform_mode()
						reroll_preview_instance_transform()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == config.rotate_90:
						preview_temp_parent.rotate_y(deg_to_rad(90))
						return EditorPlugin.AFTER_GUI_INPUT_STOP
				if event.keycode == KEY_ESCAPE:
					end_placement_mode()
					return EditorPlugin.AFTER_GUI_INPUT_STOP

			if placement_mode_enabled:
				if event.shift_pressed:
					if event.keycode == KEY_LEFT:
						select_previous_item()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_RIGHT:
						select_next_item()
						return EditorPlugin.AFTER_GUI_INPUT_STOP

				if event.alt_pressed:
					if event.keycode == KEY_LEFT:
						select_previous_collection()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
					elif event.keycode == KEY_RIGHT:
						select_next_collection()
						return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

# ---- Buttons -----------------------------------------------------------------


func select_collection(tab_index: int) -> void:
	end_placement_mode()
	for c in ($"Collection/Panel/Cats").get_children():
		(c as Button).modulate = Color.WHITE
	if tab_index < 0 or tab_index >= len(collection_names):
		print("Selected collection out of bounds")
		return
	($"Collection/Panel/Cats").get_child(tab_index).modulate = Color.AQUAMARINE
	selected_collection_id = tab_index
	reload_all_items()

func on_item_icon_clicked(item_id: int) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if item_id < 0 or item_id >= len(items):
			print("Item ", item_id, " doesn't exist, can't select.")
			return
		EditorInterface.edit_resource(items[item_id])
		var tabs = EditorInterface.get_inspector().get_parent().get_parent() as TabContainer
		tabs.current_tab = tabs.get_tab_idx_from_control(EditorInterface.get_inspector().get_parent())
		return

	if selected_item_id != item_id:
		select_item(item_id)
	elif placement_mode_enabled:
		end_placement_mode()

func reload_all_items() -> void:
	load_or_make_collections()
	var grid = ($"Collection/Scroll/Grid")
	for c in grid.get_children():
		c.queue_free()
	if selected_collection_id >= len(collection_names):
		print("Collection doesn't exist!")
		return
	if DirAccess.dir_exists_absolute(config.root_dir + "/%s" % collection_names[selected_collection_id]):
		load_items_from_collection_folder_on_disk(collection_names[selected_collection_id])
		for i in len(items):
			var item = items[i]
			var texture_button: TextureButton = TextureButton.new()
			texture_button.toggle_mode = true
			texture_button.texture_normal = item.texture
			texture_button.tooltip_text = item.item_name
			texture_button.ignore_texture_size = true
			texture_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
			texture_button.custom_minimum_size = Vector2(icon_size.value, icon_size.value)
			texture_button.pressed.connect(on_item_icon_clicked.bind(i))
			texture_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
			texture_button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
			grid.add_child(texture_button)

			var nine_patch: NinePatchRect = NinePatchRect.new()
			nine_patch.texture = CanvasTexture.new()
			nine_patch.draw_center = false
			nine_patch.set_anchors_preset(Control.PRESET_FULL_RECT)
			nine_patch.patch_margin_left = 4
			nine_patch.patch_margin_top = 4
			nine_patch.patch_margin_right = 4
			nine_patch.patch_margin_bottom = 4
			nine_patch.modulate.a = 0
			nine_patch.self_modulate = Color("000000") # black  # 6a9d2e green
			highlighters.push_back(nine_patch)
			texture_button.add_child(nine_patch)


# ---- Helpers -----------------------------------------------------------------

func align_up(node_basis, normal) -> Basis:
	var result: Basis = Basis()
	var scale: Vector3 = node_basis.get_scale()
	var orientation: String = btn_group_surface_orientation.get_pressed_button().name

	var arbitrary_vector: Vector3 = Vector3(1, 0, 0) if abs(normal.dot(Vector3(1, 0, 0))) < 0.999 else Vector3(0, 1, 0)
	var cross1: Vector3
	var cross2: Vector3

	match orientation:
		"X":
			cross1 = normal.cross(node_basis.y).normalized()
			if cross1.length_squared() < 0.001:
				cross1 = normal.cross(arbitrary_vector).normalized()
			cross2 = cross1.cross(normal).normalized()
			result = Basis(normal, cross2, cross1)
		"Y":
			cross1 = normal.cross(node_basis.z).normalized()
			if cross1.length_squared() < 0.001:
				cross1 = normal.cross(arbitrary_vector).normalized()
			cross2 = cross1.cross(normal).normalized()
			result = Basis(cross1, normal, cross2)
		"Z":
			arbitrary_vector = Vector3(0, 0, 1) if abs(normal.dot(Vector3(0, 0, -1))) < 0.99 else Vector3(-1, 0, 0)
			cross1 = normal.cross(node_basis.x).normalized()
			if cross1.length_squared() < 0.001:
				cross1 = normal.cross(arbitrary_vector).normalized()
			cross2 = cross1.cross(normal).normalized()
			result = Basis(cross2, cross1, normal)

	result = result.orthonormalized()
	result.x *= scale.x
	result.y *= scale.y
	result.z *= scale.z

	return result

func clear_preview_instance() -> void:
	if preview_instance:
		preview_instance.free()
	preview_instance_rid_array = []

func create_preview_instance() -> void:

	clear_preview_instance()

	preview_instance = make_item_instance(items[selected_item_id])
	preview_temp_parent.add_child(preview_instance)
	preview_instance.owner = EditorInterface.get_edited_scene_root()
	preview_instance.position = items[selected_item_id].snap_offset
	preview_instance.rotation = Vector3.ZERO
	reroll_preview_instance_transform()

	# Instantiating a node automatically selects it, which is annoying.
	# Let's re-select scene_root instead,
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(preview_temp_parent.get_parent())

func end_placement_mode() -> void:
	clear_preview_instance()
	end_transform_mode()
	if preview_temp_parent:
		preview_temp_parent.free()
	if prev_parent:
		prev_parent.remove_meta("_edit_lock_")
	placement_mode_enabled = false

	if selected_item_id >= 0 and selected_item_id < len(items):
		var selected_nine_path: NinePatchRect = highlighters[selected_item_id]
		selected_nine_path.modulate.a = 0
		selected_nine_path.self_modulate = Color.BLACK
	selected_item_id = -1

func end_transform_mode() -> void:
	current_transform_mode = TransformMode.NONE
	reset_indicators()

func load_items_from_collection_folder_on_disk(_collection_name: String):
	
	items.clear()
	highlighters.clear()
	var dir = DirAccess.open(config.root_dir + _collection_name)
	if dir:
		var paths:Array[String] = []
		dir.list_dir_begin()
		var item_filename = dir.get_next()
		while item_filename != "":
			var item_path = config.root_dir + _collection_name + "/" + item_filename
			paths.push_back(item_path)
			ResourceLoader.load_threaded_request(item_path, "Resource", false, 1)
			item_filename = dir.get_next()	
		dir.list_dir_end()
		for path in paths:
			var resource = ResourceLoader.load_threaded_get(path)
			if resource and resource is SceneBuilderItem:
				#print("[SceneBuilderDock] Loaded item: ", item_filename)
				items.push_back(resource)
			else:
				print("[SceneBuilderDock] The resource is not a SceneBuilderItem or failed to load, item_path: ", path)

func get_all_node_names(_node) -> Array[String]:
	var _all_node_names = []
	for _child in _node.get_children():
		_all_node_names.append(_child.name)
		if _child.get_child_count() > 0:
			var _result = get_all_node_names(_child)
			for _item in _result:
				_all_node_names.append(_item)
	return _all_node_names

func _get_merged_aabb(node: Node, node_depth: int) -> AABB:
	var aabb := AABB()
	
	if node is GeometryInstance3D:
		aabb = node.global_transform * node.get_aabb()
	
	if node_depth > 0:
		for child in node.get_children():
			var child_aabb = _get_merged_aabb(child, node_depth - 1)
			if aabb == AABB():
				aabb = child_aabb
			elif child_aabb != AABB(): # this was fucking with the volume for some reason
				aabb = aabb.merge(child_aabb)
	
	return aabb

func _get_root_ancestor(child: Node, anc: Node) -> Node:
	var p = child.get_parent()
	if p:
		if p == anc:
			return child
		return _get_root_ancestor(p, anc)
	else:
		return null

func instantiate_selected_item_at_position() -> void:
	if preview_instance == null or selected_item_id < 0 or selected_item_id >= len(items):
		printerr("[SceneBuilderDock] Preview instance or selected item is null")
		return

	populate_preview_instance_rid_array(preview_instance)
	var result = perform_raycast_with_exclusion(preview_instance_rid_array)
	var instance = make_item_instance(items[selected_item_id])
	var parent = selected_parent()
	if not parent:
		printerr("Valid parent not selected.")
		return
	parent.add_child(instance)
	instance.owner = EditorInterface.get_edited_scene_root()
	initialize_node_name(instance, items[selected_item_id].item_name)

	instance.transform = preview_temp_parent.transform*preview_instance.transform
	#print("[SceneBuilderDock] pos_offset_y: ", pos_offset_y)
	#instance.basis = preview_instance.basis
	#instance.basis = Basis.from_euler(snap_rot(preview_instance.basis.get_euler()))
	#instance.basis = instance.basis.scaled(preview_instance.basis.get_scale())
	undo_redo.create_action("Instantiate selected item")
	undo_redo.add_undo_method(parent, "remove_child", instance)
	if btn_replace_overlapping.button_pressed  and "collider" in result:
		var hit_ancestor = _get_root_ancestor(result.collider, parent)
		if hit_ancestor:
			var old_aabb = _get_merged_aabb(result.collider, 5)
			var new_aabb = _get_merged_aabb(instance, 5)
			var cross = old_aabb.intersection(new_aabb)
			if cross.get_volume()/max(old_aabb.get_volume()+0.01,new_aabb.get_volume()) > 0.85\
				and (old_aabb.size-new_aabb.size).length_squared() < 1:
				parent.remove_child(hit_ancestor)
				undo_redo.add_undo_method(parent, "add_child", hit_ancestor)
	undo_redo.add_do_reference(instance)
	undo_redo.commit_action()
	reroll_preview_instance_transform()

func initialize_node_name(node: Node3D, new_name: String) -> void:
	var all_names = toolbox.get_all_node_names(selected_parent())
	node.name = toolbox.increment_name_until_unique(new_name, all_names)

func perform_raycast_with_exclusion(exclude_rids: Array = []) -> Dictionary:
	var mouse_pos = viewport.get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * 1000
	var query = PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = end
	query.exclude = exclude_rids
	var mode = %PlaneMode.selected
	var res = physics_space.intersect_ray(query)
	if not %EnablePlane.button_pressed:
		return res
	var pres = {}
	var plane = Plane(Vector3.UP, %PlaneYPos.value)
	pres.position = plane.intersects_ray(origin, (end-origin).normalized())
	if pres.position == null:
		return res
	match mode:
		0: # prefer colliders
			if res and res.position:
				return res
			return pres
		1: # closest wins
			if res and res.position and \
			(res.position-origin).length_squared() < (pres.position-origin).length_squared():
				return res
			return pres
		2: #ignore colliders
			return pres
	return pres

## This function prevents us from trying to raycast against our preview item.
func populate_preview_instance_rid_array(instance: Node) -> void:
	if instance is PhysicsBody3D:
		preview_instance_rid_array.append(instance.get_rid())

	for child in instance.get_children():
		populate_preview_instance_rid_array(child)

func load_or_make_collections() -> void:
	print("[SceneBuilderDock] Refreshing collection names")

	if !DirAccess.dir_exists_absolute(config.root_dir):
		DirAccess.make_dir_recursive_absolute(config.root_dir)
		print("[SceneBuilderDock] Creating a new data folder: ", config.root_dir)
	print(path_to_collection_names)
	if !ResourceLoader.exists(path_to_collection_names):
		print("file not found")
		var _collection_names: CollectionNames = CollectionNames.new()
		print("[SceneBuilderDock] path_to_collection_names: ", path_to_collection_names)
		var save_result = ResourceSaver.save(_collection_names, path_to_collection_names)
		if save_result != OK:
			printerr("[SceneBuilderDock] We were unable to create a CollectionNames resource at location: ", path_to_collection_names)
			return
	var _cols: CollectionNames = load(path_to_collection_names)
	_cols.check_new_collections()
	if _cols == null:
		printerr("Collection names can't be loaded")
		return
	collections = _cols
	collection_names.clear()
	collection_colors.clear()
	var cat_parent = ($"Collection/Panel/Cats")
	for c in cat_parent.get_children():
		c.queue_free()
	var names = collections.names_and_colors.keys().duplicate()
	names.sort()
	for n in names:
		var i = len(collection_names)
		collection_names.push_back(n)
		collection_colors.push_back(collections.names_and_colors[n])
		var butt = Button.new()
		butt.name = n
		butt.text = n
		butt.add_theme_color_override("font_color", collection_colors[i])
		butt.pressed.connect(select_collection.bind(i))
		cat_parent.add_child(butt)
	#endregion

# ---- Shortcut ----------------------------------------------------------------

func place_fence():
	var selection: EditorSelection = EditorInterface.get_selection()
	var selected_nodes: Array[Node] = selection.get_selected_nodes()

	if selected_nodes.size() != 1:
		printerr("[SceneBuilderDock] Exactly one node sould be selected in the scene")
		return

	if not selected_nodes[0] is Path3D:
		printerr("[SceneBuilderDock] The selected node should be of type Node3D")
		return

	undo_redo.create_action("Make a fence")

	var path: Path3D = selected_nodes[0]

	var path_length: float = path.curve.get_baked_length()

	for distance in range(0, path_length, spinbox_separation_distance.value):

		var transform: Transform3D = path.curve.sample_baked_with_rotation(distance)
		var position: Vector3 = transform.origin
		var basis: Basis = transform.basis.rotated(Vector3(0, 1, 0), deg_to_rad(spinbox_y_offset.value))

		var chosen_item: SceneBuilderItem = items.pick_random()
		var instance = make_item_instance(chosen_item)
		var p = selected_parent()
		undo_redo.add_do_method(p, "add_child", instance)
		undo_redo.add_do_method(instance, "set_owner", p)
		undo_redo.add_do_method(instance, "set_global_transform", Transform3D(
			basis.rotated(Vector3(1, 0, 0), randf() * deg_to_rad(spinbox_jitter_x.value))
				 .rotated(Vector3(0, 1, 0), randf() * deg_to_rad(spinbox_jitter_y.value))
				 .rotated(Vector3(0, 0, 1), randf() * deg_to_rad(spinbox_jitter_z.value)),
			position
		))

		undo_redo.add_undo_method(p, "remove_child", instance)

	print("[SceneBuilderDock] Commiting action")
	undo_redo.commit_action()

func reroll_preview_instance_transform() -> void:
	if preview_instance == null:
		printerr("[SceneBuilderDock] preview_instance is null inside reroll_preview_instance_transform()")
		return
		
	random_offset_y = rng.randf_range(items[selected_item_id].random_offset_y_min, items[selected_item_id].random_offset_y_max)

	if items[selected_item_id].use_random_scale:
		var random_scale: float = rng.randf_range(items[selected_item_id].random_scale_min, items[selected_item_id].random_scale_max)
		original_preview_scale = Vector3(random_scale, random_scale, random_scale)

	preview_temp_parent.scale = original_preview_scale

	if items[selected_item_id].use_random_rotation:
		var x_rot: float = rng.randf_range(0, items[selected_item_id].random_rot_x)
		var y_rot: float = rng.randf_range(0, items[selected_item_id].random_rot_y)
		var z_rot: float = rng.randf_range(0, items[selected_item_id].random_rot_z)
		preview_temp_parent.rotation = snap_rot(Vector3(deg_to_rad(x_rot), deg_to_rad(y_rot), deg_to_rad(z_rot)))
		original_preview_basis = preview_temp_parent.basis

	original_preview_basis = preview_temp_parent.basis

func select_item(item_id: int) -> void:
	end_placement_mode()
	if len(EditorInterface.get_selection().get_selected_nodes()) == 0:
		EditorInterface.get_selection().add_node(EditorInterface.get_edited_scene_root())
	var base_parent = selected_parent()
	if not base_parent:
		print("A Node3D parent not selected in the scene tree!")
		return
	base_parent.set_meta("_edit_lock_", true)
	preview_temp_parent = Node3D.new()
	preview_temp_parent.name = "_PreviewTempParent"
	base_parent.add_child(preview_temp_parent)
	preview_temp_parent.owner = EditorInterface.get_edited_scene_root()
	if item_id < 0 or item_id >= len(items):
		print("Item ", item_id, " doesn't exist, can't select.")
		return
	var nine_patch: NinePatchRect = highlighters[item_id]
	nine_patch.modulate.a = 1
	nine_patch.self_modulate = Color.DARK_ORANGE
	selected_item_id = item_id
	placement_mode_enabled = true; # absically start_placement_mode
	create_preview_instance()

func select_first_item() -> void:
	select_item(0)

func select_next_collection() -> void:
	var new_col = (selected_collection_id + 1) % len(collection_names)
	select_collection(new_col)
	select_first_item()

func select_next_item() -> void:
	var id = (selected_item_id + 1) % len(items)
	select_item(id)

func select_previous_item() -> void:
	var id = (len(items) + selected_item_id - 1) % len(items)
	select_item(id)

func select_previous_collection() -> void:
	end_placement_mode()
	var id = (len(collection_names) + selected_collection_id - 1) % len(collection_names)
	select_collection(id)
	select_first_item()

func start_transform_mode(mode: TransformMode) -> void:
	original_mouse_position = viewport.get_mouse_position()
	current_transform_mode = mode
	
	match mode:
		TransformMode.POSITION_X, TransformMode.POSITION_Y, TransformMode.POSITION_Z:
			original_position_offset = position_offset
		TransformMode.ROTATION_X, TransformMode.ROTATION_Y, TransformMode.ROTATION_Z:
			original_preview_basis = preview_instance.basis
		TransformMode.SCALE:
			original_preview_scale = preview_instance.scale
	
	reset_indicators()
	match mode:
		TransformMode.POSITION_X, TransformMode.ROTATION_X:
			lbl_indicator_x.self_modulate = Color.GREEN
		TransformMode.POSITION_Y, TransformMode.ROTATION_Y:
			lbl_indicator_y.self_modulate = Color.GREEN
		TransformMode.POSITION_Z, TransformMode.ROTATION_Z:
			lbl_indicator_z.self_modulate = Color.GREEN
		TransformMode.SCALE:
			lbl_indicator_scale.self_modulate = Color.GREEN


func make_item_instance(item: SceneBuilderItem) -> Node3D:

	if not item.prefab or item.prefab is not PackedScene or not item.prefab.can_instantiate():
		printerr("Item scene not a PackedScene, is it missing?")
		return null
	return item.prefab.instantiate()

# --

func reset_indicators() -> void:
	lbl_indicator_x.self_modulate = Color.WHITE
	lbl_indicator_y.self_modulate = Color.WHITE
	lbl_indicator_z.self_modulate = Color.WHITE
	lbl_indicator_scale.self_modulate = Color.WHITE
