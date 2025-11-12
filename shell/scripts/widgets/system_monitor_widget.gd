extends "res://shell/scripts/widget_base.gd"

## System Monitor Widget
##
## Displays CPU, RAM, disk, and network usage in a compact panel widget.
## Updates every second.

var update_timer: float = 0.0
var update_interval: float = 1.0  # Update every second

# Display label
var info_label: Label

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

func _widget_ready():
	widget_name = "System Monitor"
	min_width = 200
	preferred_width = 250

	# Create display label
	info_label = Label.new()
	info_label.text = "CPU: -- RAM: -- Disk: --"
	info_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	add_child(info_label)

	# Initial update
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

	# Update display
	_update_display()

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
	"""Update the display label with current stats"""
	var cpu_str = "CPU: %d%%" % int(cpu_usage)
	var ram_str = "RAM: %d%%" % int(ram_usage)
	var disk_str = "Disk: %d%%" % int(disk_usage)
	var net_str = "↓%.1fKB/s ↑%.1fKB/s" % [network_rx, network_tx]

	info_label.text = "%s | %s | %s | %s" % [cpu_str, ram_str, disk_str, net_str]

func update_widget():
	"""Force update of stats"""
	_update_stats()
