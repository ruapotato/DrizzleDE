extends Node3D

## Displays X11 windows on 3D quads in the scene

@export var compositor_path: NodePath
@export var camera_path: NodePath
@export var window_spacing := 1.5
@export var update_rate := 60.0  # Updates per second
@export var spawn_distance := 3.0  # Distance from player to spawn new windows
@export var pixels_per_world_unit := 400.0  # Conversion factor: 400 pixels = 1 world unit

var compositor: Node
var camera: Camera3D
var window_quads := {}  # Maps window_id -> MeshInstance3D
var update_timer := 0.0
var next_z_offset := 0.0  # Z offset for each window to prevent Z-fighting

# Application grouping - tracks where each app's windows are located
var app_zones := {}  # Maps app_class -> {center: Vector3, window_ids: Array}

func _ready():
    if compositor_path:
        compositor = get_node(compositor_path)
    else:
        # Try to find X11Compositor in the scene
        compositor = get_node_or_null("/root/Main/X11Compositor")

    if camera_path:
        camera = get_node(camera_path)
    else:
        camera = get_viewport().get_camera_3d()

    if not compositor:
        push_error("X11Compositor not found!")
        return

    if not camera:
        push_warning("Camera not found - windows will spawn at origin")

    print("WindowDisplay ready, connected to compositor: ", compositor.get_display_name())

func _process(delta):
    if not compositor or not compositor.is_initialized():
        return

    update_timer += delta
    if update_timer < 1.0 / update_rate:
        return
    update_timer = 0.0

    # Get all current window IDs
    var window_ids = compositor.get_window_ids()

    # Remove quads for windows that no longer exist
    var ids_to_remove = []
    for window_id in window_quads.keys():
        if window_id not in window_ids:
            ids_to_remove.append(window_id)

    for window_id in ids_to_remove:
        remove_window_quad(window_id)

    # Create or update quads for each window
    for window_id in window_ids:
        var quad: MeshInstance3D

        if window_id in window_quads:
            quad = window_quads[window_id]
        else:
            quad = create_window_quad_spatial(window_id)
            window_quads[window_id] = quad

        # Update the texture
        update_window_texture(quad, window_id)

func create_window_quad(window_id: int, index: int) -> MeshInstance3D:
    var quad = MeshInstance3D.new()
    add_child(quad)

    # Create quad mesh
    var mesh = QuadMesh.new()
    mesh.size = Vector2(1, 1)  # Will be scaled by window size
    quad.mesh = mesh

    # Create material with texture
    var material = StandardMaterial3D.new()
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1, 1, 1, 1)  # White (will be modulated by texture)
    quad.material_override = material

    # Add collision shape for raycasting
    var static_body = StaticBody3D.new()
    quad.add_child(static_body)

    var collision_shape = CollisionShape3D.new()
    static_body.add_child(collision_shape)

    var box_shape = BoxShape3D.new()
    box_shape.size = Vector3(1, 1, 0.01)  # Thin box matching quad size
    collision_shape.shape = box_shape

    # Store window ID as metadata for identification
    quad.set_meta("window_id", window_id)
    static_body.set_meta("window_id", window_id)

    # Position the quad - in front of the reference plane
    # Camera is at z=3, looking at -Z. Reference plane is at z=-2.
    # Put windows at z=-1 (closer to camera than the reference plane)
    quad.position = Vector3(index * window_spacing, 1.5, -1)

    print("Created window quad ", window_id, " at position ", quad.position)

    return quad

func update_window_texture(quad: MeshInstance3D, window_id: int):
    var image = compositor.get_window_buffer(window_id)
    if not image:
        return

    var size = compositor.get_window_size(window_id)
    if size.x <= 0 or size.y <= 0:
        return

    # Update quad scale based on actual pixel size
    # Convert pixels to world units using our conversion factor
    var width_world = float(size.x) / pixels_per_world_unit
    var height_world = float(size.y) / pixels_per_world_unit
    quad.scale = Vector3(width_world, height_world, 1)

    # Update collision shape to match new size
    var static_body = quad.get_node_or_null("StaticBody3D")
    if static_body:
        var collision_shape = static_body.get_node_or_null("CollisionShape3D")
        if collision_shape and collision_shape.shape is BoxShape3D:
            var box_shape = collision_shape.shape as BoxShape3D
            # BoxShape3D size is the full size, and the quad is 1x1 before scaling
            # So the collision box should match the quad size (which is now scaled)
            box_shape.size = Vector3(1, 1, 0.01)

    # Create texture from image
    var texture = ImageTexture.create_from_image(image)

    # Update material
    var material = quad.material_override as StandardMaterial3D
    if material:
        material.albedo_texture = texture

## Spatial window management

func create_window_quad_spatial(window_id: int) -> MeshInstance3D:
    var app_class = compositor.get_window_class(window_id)
    var window_title = compositor.get_window_title(window_id)

    # Calculate spawn position based on application grouping
    var spawn_pos = get_spawn_position(window_id, app_class)

    var quad = MeshInstance3D.new()
    add_child(quad)

    # Create quad mesh
    var mesh = QuadMesh.new()
    mesh.size = Vector2(1, 1)
    quad.mesh = mesh

    # Create material
    var material = StandardMaterial3D.new()
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1, 1, 1, 1)
    quad.material_override = material

    # Add collision shape for raycasting
    var static_body = StaticBody3D.new()
    quad.add_child(static_body)

    var collision_shape = CollisionShape3D.new()
    static_body.add_child(collision_shape)

    var box_shape = BoxShape3D.new()
    box_shape.size = Vector3(1, 1, 0.01)
    collision_shape.shape = box_shape

    # Store window ID and app class as metadata
    quad.set_meta("window_id", window_id)
    quad.set_meta("app_class", app_class)
    static_body.set_meta("window_id", window_id)

    # Position the quad with Z offset to prevent Z-fighting
    quad.position = spawn_pos

    # Check if this is a popup window - if so, position in front of parent
    var parent_id = compositor.get_parent_window_id(window_id)
    if parent_id != -1 and parent_id in window_quads:
        # Popup window - position in front of parent (closer to camera = higher Z)
        var parent_quad = window_quads[parent_id]
        quad.position.z = parent_quad.position.z + 0.05  # Clearly in front of parent
    else:
        # Normal window - use incremental offset
        quad.position.z += next_z_offset
        next_z_offset += 0.01  # Small offset for each window to prevent flickering

    # Update app zone tracking
    add_window_to_zone(window_id, app_class, spawn_pos)

    print("Created window quad ", window_id, ": ", window_title, " [", app_class, "] at ", quad.position)

    return quad

func get_spawn_position(window_id: int, app_class: String) -> Vector3:
    # Check if this is a popup window (has a parent)
    var parent_id = compositor.get_parent_window_id(window_id)
    if parent_id != -1 and parent_id in window_quads:
        # This is a popup - position it relative to the parent window
        var parent_quad = window_quads[parent_id]
        var parent_pos = parent_quad.global_position

        # Position popup slightly to the right and down from parent
        # This roughly matches where Firefox shows its dropdown menus
        var popup_offset = Vector3(0.2, -0.3, 0)

        print("  Positioning popup window ", window_id, " relative to parent ", parent_id)
        return parent_pos + popup_offset

    # If this app already has windows, spawn near them
    if app_class != "" and app_class in app_zones:
        var zone = app_zones[app_class]
        var zone_center = zone.center
        var window_count = zone.window_ids.size()

        # Spawn in a grid pattern around the zone center
        var offset_x = (window_count % 3) * window_spacing
        var offset_y = (window_count / 3) * window_spacing

        return zone_center + Vector3(offset_x - window_spacing, offset_y, 0)

    # New app - spawn near the player's current position
    if camera:
        # Spawn in front of the camera
        var forward = -camera.global_transform.basis.z
        forward.y = 0  # Keep on same height
        forward = forward.normalized()

        var spawn_pos = camera.global_position + forward * spawn_distance
        spawn_pos.y = camera.global_position.y  # Same height as camera

        return spawn_pos

    # Fallback: spawn at origin
    return Vector3(0, 1.5, -1)

func add_window_to_zone(window_id: int, app_class: String, position: Vector3):
    if app_class == "":
        return

    if app_class not in app_zones:
        # Create new zone
        app_zones[app_class] = {
            "center": position,
            "window_ids": [window_id]
        }
    else:
        # Add to existing zone
        app_zones[app_class].window_ids.append(window_id)
        update_zone_center(app_class)

func remove_window_quad(window_id: int):
    if window_id not in window_quads:
        return

    var quad = window_quads[window_id]

    # Remove from app zone tracking
    if quad.has_meta("app_class"):
        var app_class = quad.get_meta("app_class")
        remove_window_from_zone(window_id, app_class)

    # Free the quad
    quad.queue_free()
    window_quads.erase(window_id)

func remove_window_from_zone(window_id: int, app_class: String):
    if app_class == "" or app_class not in app_zones:
        return

    var zone = app_zones[app_class]
    var idx = zone.window_ids.find(window_id)
    if idx != -1:
        zone.window_ids.remove_at(idx)

    # If no more windows in this zone, remove it
    if zone.window_ids.is_empty():
        app_zones.erase(app_class)
    else:
        update_zone_center(app_class)

func update_zone_center(app_class: String):
    if app_class not in app_zones:
        return

    var zone = app_zones[app_class]
    var center = Vector3.ZERO
    var count = 0

    # Calculate average position of all windows in this zone
    for wid in zone.window_ids:
        if wid in window_quads:
            center += window_quads[wid].global_position
            count += 1

    if count > 0:
        zone.center = center / count
