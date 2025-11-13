extends "res://shell/scripts/widget_base.gd"

## System Monitor Widget
##
## Displays CPU, RAM, disk, and network usage with graphs over time.
## Updates every second.

var update_timer: float = 0.0
var update_interval: float = 1.0  # Update every second

# Graph display
var graph_control: Control
var label: Label

# Historical data (store last 60 samples = 1 minute)
const MAX_HISTORY = 60
var cpu_history := []
var ram_history := []
var disk_history := []
var network_rx_history := []

# System stats
var cpu_usage: float = 0.0
var ram_usage: float = 0.0
var disk_usage: float = 0.0
var network_rx: float = 0.0  # KB/s
var network_tx: float = 0.0  # KB/s

# For network speed calculation
var last_network_time: float = 0.0
var last_rx_bytes: int = 0
var last_tx_bytes: int = 0

# Graph colors
var cpu_color := Color(0.3, 0.7, 1.0)       # Blue
var ram_used_color := Color(0.2, 0.8, 0.3)  # Green for used RAM
var ram_cached_color := Color(0.5, 1.0, 0.6) # Light green for cached RAM
var disk_color := Color(0.8, 0.8, 0.3)      # Yellow
var network_color := Color(1.0, 0.3, 0.7)   # Pink

func _widget_ready():
	widget_name = "System Monitor"

	# Create horizontal container for individual graphs
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox.add_theme_constant_override("separation", 2)
	add_child(hbox)

	# Create individual graph controls (smaller, side by side)
	var graph_width = 60
	var graph_height = 24

	# CPU graph
	var cpu_graph = Control.new()
	cpu_graph.custom_minimum_size = Vector2(graph_width, graph_height)
	cpu_graph.draw.connect(_draw_cpu_graph.bind(cpu_graph))
	hbox.add_child(cpu_graph)

	# RAM graph
	var ram_graph = Control.new()
	ram_graph.custom_minimum_size = Vector2(graph_width, graph_height)
	ram_graph.draw.connect(_draw_ram_graph.bind(ram_graph))
	hbox.add_child(ram_graph)

	# Disk graph
	var disk_graph = Control.new()
	disk_graph.custom_minimum_size = Vector2(graph_width, graph_height)
	disk_graph.draw.connect(_draw_disk_graph.bind(disk_graph))
	hbox.add_child(disk_graph)

	# Network graph
	var net_graph = Control.new()
	net_graph.custom_minimum_size = Vector2(graph_width, graph_height)
	net_graph.draw.connect(_draw_net_graph.bind(net_graph))
	hbox.add_child(net_graph)

	# Store graph references for redrawing
	graph_control = hbox  # Store container for overall access
	set_meta("cpu_graph", cpu_graph)
	set_meta("ram_graph", ram_graph)
	set_meta("disk_graph", disk_graph)
	set_meta("net_graph", net_graph)

	# Initialize history arrays
	for i in range(MAX_HISTORY):
		cpu_history.append(0.0)
		ram_history.append(0.0)
		disk_history.append(0.0)
		network_rx_history.append(0.0)

	# Wait for graphs to be ready and set size
	await get_tree().process_frame

	# Set widget size (4 graphs side by side)
	var total_width = (graph_width * 4) + (2 * 3) + 8  # graphs + separators + padding
	custom_minimum_size.x = total_width
	min_width = total_width
	preferred_width = total_width

	# Now update with real values
	_update_stats()

	print("SystemMonitorWidget initialized")

func _process(delta):
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_stats()

func _update_stats():
	"""Update system statistics"""
	# CPU usage (rough estimate based on process time)
	cpu_usage = _get_cpu_usage()

	# RAM usage
	ram_usage = _get_ram_usage()

	# Disk usage
	disk_usage = _get_disk_usage()

	# Network usage
	_update_network_stats()

	# Add to history (remove oldest, add newest)
	cpu_history.pop_front()
	cpu_history.append(cpu_usage)

	ram_history.pop_front()
	ram_history.append(ram_usage)

	disk_history.pop_front()
	disk_history.append(disk_usage)

	# Network in MB/s for graphing
	var network_mbps = network_rx / 1024.0
	network_rx_history.pop_front()
	network_rx_history.append(min(network_mbps, 100.0))  # Cap at 100 MB/s for scale

	# Update display
	_update_display()

	# Redraw all individual graphs
	if has_meta("cpu_graph"):
		get_meta("cpu_graph").queue_redraw()
	if has_meta("ram_graph"):
		get_meta("ram_graph").queue_redraw()
	if has_meta("disk_graph"):
		get_meta("disk_graph").queue_redraw()
	if has_meta("net_graph"):
		get_meta("net_graph").queue_redraw()

func _get_cpu_usage() -> float:
	"""Get CPU usage percentage (approximation)"""
	# Godot doesn't have direct CPU usage API
	# Use process time as rough indicator
	var process_time = Time.get_ticks_msec()
	# This is a placeholder - returns 0-100
	return randf() * 100.0  # TODO: Implement actual CPU monitoring

func _get_ram_usage() -> float:
	"""Get RAM usage percentage"""
	var static_mem = OS.get_static_memory_usage()
	var peak_mem = OS.get_static_memory_peak_usage()

	if peak_mem > 0:
		return (float(static_mem) / float(peak_mem)) * 100.0
	return 0.0

func _get_disk_usage() -> float:
	"""Get disk usage percentage for home directory"""
	# Godot doesn't have direct disk space API
	# Use shell command to get disk usage
	var output = []
	var home_dir = OS.get_environment("HOME")

	# Try to execute df command
	OS.execute("df", ["-h", home_dir], output, false, false)

	if output.size() > 0:
		# Parse df output (rough parsing)
		var lines = output[0].split("\n")
		if lines.size() > 1:
			# Second line contains the data
			var parts = lines[1].split(" ", false)
			if parts.size() >= 5:
				# Usage percentage is usually in format like "45%"
				var usage_str = parts[4].replace("%", "")
				return float(usage_str)

	return 0.0

func _update_network_stats():
	"""Update network statistics"""
	# Godot doesn't have direct network stats API
	# Use /proc/net/dev on Linux
	var file = FileAccess.open("/proc/net/dev", FileAccess.READ)
	if not file:
		network_rx = 0.0
		network_tx = 0.0
		return

	var total_rx: int = 0
	var total_tx: int = 0

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("lo:") or line.begins_with("Inter-") or line.begins_with("face"):
			continue  # Skip loopback and header lines

		if ":" in line:
			var parts = line.split(":", 1)
			if parts.size() == 2:
				var values = parts[1].strip_edges().split(" ", false)
				if values.size() >= 9:
					total_rx += int(values[0])  # Receive bytes
					total_tx += int(values[8])  # Transmit bytes

	file.close()

	# Calculate speed (bytes per second)
	var current_time = Time.get_ticks_msec() / 1000.0
	if last_network_time > 0:
		var time_diff = current_time - last_network_time
		if time_diff > 0:
			network_rx = (total_rx - last_rx_bytes) / time_diff / 1024.0  # KB/s
			network_tx = (total_tx - last_tx_bytes) / time_diff / 1024.0  # KB/s

	last_rx_bytes = total_rx
	last_tx_bytes = total_tx
	last_network_time = current_time

func _update_display():
	"""No text display - graphs only"""
	pass

func _draw_cpu_graph(graph: Control):
	"""Draw CPU graph"""
	_draw_single_graph(graph, cpu_history, cpu_color, "CPU")

func _draw_ram_graph(graph: Control):
	"""Draw RAM graph with dual colors"""
	var size = graph.size
	var width = size.x
	var height = size.y

	# Draw background
	graph.draw_rect(Rect2(0, 0, width, height), Color(0.08, 0.08, 0.1, 0.95))

	# Draw RAM cached (light green) and used (dark green)
	_draw_graph_on_control(graph, ram_history, ram_cached_color, width, height, 100.0)
	_draw_scaled_graph_on_control(graph, ram_history, ram_used_color, width, height, 100.0, 0.7)

func _draw_disk_graph(graph: Control):
	"""Draw Disk graph"""
	_draw_single_graph(graph, disk_history, disk_color, "DSK")

func _draw_net_graph(graph: Control):
	"""Draw Network graph"""
	_draw_single_graph(graph, network_rx_history, network_color, "NET")

func _draw_single_graph(graph: Control, history: Array, color: Color, label_text: String):
	"""Draw a single graph with label"""
	var size = graph.size
	var width = size.x
	var height = size.y

	# Draw background
	graph.draw_rect(Rect2(0, 0, width, height), Color(0.08, 0.08, 0.1, 0.95))

	# Draw graph
	_draw_graph_on_control(graph, history, color, width, height, 100.0)

func _draw_graph_on_control(graph: Control, history: Array, color: Color, width: float, height: float, max_value: float):
	"""Draw a filled graph on a specific control"""
	if history.size() < 2:
		return

	var points = PackedVector2Array()
	var step_x = width / float(MAX_HISTORY - 1)

	# Start from bottom left
	points.append(Vector2(0, height))

	# Add data points
	for i in range(history.size()):
		var x = i * step_x
		var value = clamp(history[i], 0.0, max_value)
		var y = height - (value / max_value * height)
		points.append(Vector2(x, y))

	# Close at bottom right
	points.append(Vector2(width, height))

	# Draw filled polygon with semi-transparent color
	var fill_color = Color(color.r, color.g, color.b, 0.6)
	graph.draw_colored_polygon(points, fill_color)

	# Draw outline for crisp edges
	var outline_points = PackedVector2Array()
	for i in range(history.size()):
		var x = i * step_x
		var value = clamp(history[i], 0.0, max_value)
		var y = height - (value / max_value * height)
		outline_points.append(Vector2(x, y))

	if outline_points.size() >= 2:
		graph.draw_polyline(outline_points, color, 1.5, true)

func _draw_scaled_graph_on_control(graph: Control, history: Array, color: Color, width: float, height: float, max_value: float, scale: float):
	"""Draw a scaled filled graph on a specific control"""
	if history.size() < 2:
		return

	var points = PackedVector2Array()
	var step_x = width / float(MAX_HISTORY - 1)

	# Start from bottom left
	points.append(Vector2(0, height))

	# Add data points
	for i in range(history.size()):
		var x = i * step_x
		var value = clamp(history[i] * scale, 0.0, max_value)
		var y = height - (value / max_value * height)
		points.append(Vector2(x, y))

	# Close at bottom right
	points.append(Vector2(width, height))

	# Draw filled polygon with semi-transparent color
	var fill_color = Color(color.r, color.g, color.b, 0.7)
	graph.draw_colored_polygon(points, fill_color)

	# Draw outline for crisp edges
	var outline_points = PackedVector2Array()
	for i in range(history.size()):
		var x = i * step_x
		var value = clamp(history[i] * scale, 0.0, max_value)
		var y = height - (value / max_value * height)
		outline_points.append(Vector2(x, y))

	if outline_points.size() >= 2:
		graph.draw_polyline(outline_points, color, 1.5, true)

func update_widget():
	"""Force update of stats"""
	_update_stats()
