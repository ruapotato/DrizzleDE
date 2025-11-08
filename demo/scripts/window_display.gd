extends Node3D

## Displays Wayland windows on 3D quads in the scene

@export var compositor_path: NodePath
@export var window_spacing := 1.5
@export var update_rate := 60.0  # Updates per second

var compositor: Node
var window_quads := {}  # Maps window_id -> MeshInstance3D
var update_timer := 0.0

func _ready():
    if compositor_path:
        compositor = get_node(compositor_path)
    else:
        # Try to find WaylandCompositor in the scene
        compositor = get_node_or_null("/root/Main/WaylandCompositor")

    if not compositor:
        push_error("WaylandCompositor not found!")
        return

    print("WindowDisplay ready, connected to compositor: ", compositor.get_socket_name())

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
        window_quads[window_id].queue_free()
        window_quads.erase(window_id)

    # Create or update quads for each window
    var index = 0
    for window_id in window_ids:
        var quad: MeshInstance3D

        if window_id in window_quads:
            quad = window_quads[window_id]
        else:
            quad = create_window_quad(window_id, index)
            window_quads[window_id] = quad

        # Update the texture
        update_window_texture(quad, window_id)

        index += 1

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
    quad.material_override = material

    # Position the quad
    quad.position = Vector3(index * window_spacing, 0, -2)

    return quad

func update_window_texture(quad: MeshInstance3D, window_id: int):
    var image = compositor.get_window_buffer(window_id)
    if not image:
        return

    var size = compositor.get_window_size(window_id)
    if size.x <= 0 or size.y <= 0:
        return

    # Update quad scale to match window aspect ratio
    var aspect = float(size.x) / float(size.y)
    quad.scale = Vector3(aspect, 1, 1)

    # Create texture from image
    var texture = ImageTexture.create_from_image(image)

    # Update material
    var material = quad.material_override as StandardMaterial3D
    if material:
        material.albedo_texture = texture
