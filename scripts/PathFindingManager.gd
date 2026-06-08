# PathfindingManager.gd
extends Node

var astar = AStar3D.new()
const MAX_DIST = 3.0

func _ready():
	_build_graph()

# Call this from your AI script
# Returns an array of Vector3 waypoints from 'from_pos' to 'to_pos'
func find_path(from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	var from_flat = Vector3(from_pos.x, 40.31046, from_pos.z)
	var to_flat = Vector3(to_pos.x, 40.31046, to_pos.z)
	var from_id = astar.get_closest_point(from_flat)
	var to_id   = astar.get_closest_point(to_flat)
	return astar.get_point_path(from_id, to_id)
	
func _wall_blocks(a: Vector3, b: Vector3) -> bool:
	for wall in GraphData.walls:
		for i in 4:
			var c1 = wall[i]
			var c2 = wall[(i + 1) % 4]
			if _segments_intersect(a, b, c1, c2):
				return true
	return false

func _segments_intersect(p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> bool:
	var d1 = Vector2(p2.x - p1.x, p2.z - p1.z)
	var d2 = Vector2(p4.x - p3.x, p4.z - p3.z)
	var d3 = Vector2(p3.x - p1.x, p3.z - p1.z)

	var cross = d1.cross(d2)

	if abs(cross) < 0.0001:
		return false

	var t = d3.cross(d2) / cross
	var u = d3.cross(d1) / cross

	return t > 0.0 and t < 1.0 and u > 0.0 and u < 1.0

func _build_graph():
	var points = GraphData.node_positions  # tune this to your scene scale

	for i in points.size():
		astar.add_point(i, points[i])
		
	for i in points.size():
		for j in range(i + 1, points.size()):
			# Skip pairs that are too far — no need to even check walls
			if points[i].distance_to(points[j]) > MAX_DIST:
				continue
			if not _wall_blocks(points[i], points[j]):
				astar.connect_points(i, j)
	
	print("Graph built! Points: ", astar.get_point_count())
	print("Connections: ", _count_connections())

func _count_connections() -> int:
	var total = 0
	for i in astar.get_point_count():
		total += astar.get_point_connections(i).size()
	return total / 2
