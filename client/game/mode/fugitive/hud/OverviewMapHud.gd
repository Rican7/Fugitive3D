extends Control

onready var mapBackground := $Map as TextureRect

export(Font) var font: Font

const road_width := 20.0

var mapSize: Vector2
var mapStart: Vector2
var mapDrawn := false

onready var roads = GameData.currentMap.roads
var playerShape := PoolVector2Array()
const playerSize := 20.0

func _ready():
	var bb := AABB()
	
	for road in roads:
		var colShape = road.get_node("CollisionShape")
		var aabb := aabb_from_shape(colShape)
		bb = bb.merge(aabb)
	
	mapStart = Vector2(bb.position.x, bb.position.z)
	mapSize = Vector2(bb.size.x, bb.size.z)
	
	var halfSize := playerSize/2.0
	playerShape.append(Vector2(-halfSize, -halfSize))
	playerShape.append(Vector2(halfSize, -halfSize))
	playerShape.append(Vector2(0.0, playerSize))
	
	initialize_map_background()


func initialize_map_background():
	var imageTexture = ImageTexture.new()
	var image = Image.new()
	var curSize := get_rect().size
	image.create(curSize.x, curSize.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.9, 0.1, 0.5))
	imageTexture.create_from_image(image)
	mapBackground.texture = imageTexture
	
	mapBackground.update()


func _process(delta):
	if visible:
		update()


func to_map_scale(globalCoord: Vector3) -> Vector2:
	return Vector2(globalCoord.x, globalCoord.z) / mapSize


func to_map_coord(globalCoord: Vector3) -> Vector2:
	var marginFactor := 0.05
	var margin := rect_size * marginFactor
	
	var mapScale := (Vector2(globalCoord.x, globalCoord.z) - mapStart) / mapSize
	
	var marginReduction := 1.0 - (marginFactor * 2.0)
	var mapCoord := ((rect_size * marginReduction) * mapScale) + margin
	return mapCoord


func aabb_from_shape(colShape: CollisionShape) -> AABB:
	var boxShape := colShape.shape as BoxShape
	var pos := colShape.global_transform.origin
	var extents := boxShape.extents
	
	var newBB := AABB()
	newBB.position = pos - extents
	newBB.size = extents * 2.0
	
	return newBB


func _draw():
	var localPlayer := GameData.currentGame.localPlayer as FugitivePlayer
	
	# Draw this players team members
	var remotePlayers = null
	if localPlayer.playerType == FugitiveTeamResolver.PlayerType.Hider:
		remotePlayers = get_tree().get_nodes_in_group(Hider.GROUP)
	else:
		remotePlayers = get_tree().get_nodes_in_group(Seeker.GROUP)
	
	for remotePlayer in remotePlayers:
		if remotePlayer.id != localPlayer.id:
			var remotePos = remotePlayer.global_transform.origin
			var remoteCoord = to_map_coord(remotePos)
			draw_circle(remoteCoord, 10.0, Color.blue)
	
	# Draw the local player
	var globalTransform := localPlayer.global_transform
	var playerPos := globalTransform.origin
	var playerCoord = to_map_coord(playerPos)
	var angle = get_map_rotation(globalTransform)
	
	draw_set_transform(playerCoord, angle, Vector2(1.0, 1.0))
	draw_colored_polygon(playerShape, Color.red)
	draw_set_transform(Vector2(), 0.0, Vector2(1.0, 1.0))
	
	# Draw the cop cars if you are a cop
	if localPlayer.playerType == FugitiveTeamResolver.PlayerType.Seeker:
		var cars = get_tree().get_nodes_in_group(Groups.CARS)
		for car in cars:
			var carTransform = car.global_transform
			var carPos = carTransform.origin
			var carCoord = to_map_coord(carPos)
			var carAngle = get_map_rotation(carTransform)
			
			var carSize := Vector2(10.0, 20.0)
			var rect := Rect2(Vector2(-(carSize.x/2.0), -(carSize.y/2.0)), carSize)
			draw_set_transform(carCoord, carAngle, Vector2(1.0, 1.0))
			draw_rect(rect, Color.white)
			draw_set_transform(Vector2(), 0.0, Vector2(1.0, 1.0))


func get_map_rotation(globalTransform: Transform) -> float:
	return (globalTransform.basis.get_euler().y + deg2rad(180)) * -1.0


func _on_Map_draw():
	# First draw the eblows
	var elbowRadius := floor(road_width/2.0) - 1.0 # -1 so the elbows don't peak past the roads
	for road in roads:
		var fromCoord = null
		for node in road.get_children():
			if node is Position3D:
				var pos = node.global_transform.origin
				var coord := to_map_coord(pos)
				mapBackground.draw_circle(coord, elbowRadius, Color.black)
	
	# Then draw the main roads
	for road in roads:
		var fromCoord = null
		for node in road.get_children():
			if node is Position3D:
				var pos = node.global_transform.origin
				if fromCoord == null:
					fromCoord = to_map_coord(pos)
				else:
					var toCoord := to_map_coord(pos)
					mapBackground.draw_line(fromCoord, toCoord, Color.black, road_width)
					fromCoord = toCoord
	
	# Then draw the road lines
	for road in roads:
		var fromCoord = null
		for node in road.get_children():
			if node is Position3D:
				var pos = node.global_transform.origin
				if fromCoord == null:
					fromCoord = to_map_coord(pos)
				else:
					var toCoord := to_map_coord(pos)
					mapBackground.draw_line(fromCoord, toCoord, Color.white, 1.0)
					fromCoord = toCoord
	
	# Now draw the win zones
	for zone in GameData.currentMap.get_win_zones():
		var pos = zone.global_transform.origin
		var coord := to_map_coord(pos)
		var colSize = zone.get_node("CollisionShape").shape.extents
		colSize *= 4.0 # I don't understand why this is 4... it should be 2.0...
		var colSizeMap := to_map_scale(colSize) * mapSize
		coord = coord - (colSizeMap / 2.0)
		var rect := Rect2(coord, colSizeMap)
		
		mapBackground.draw_rect(rect, Color(0.0, 0.0, 1.0, 0.75))
	
	# Finally draw road names
	for road in roads:
		var namePos := to_map_coord(road.global_transform.origin)
		
		var textSize := font.get_string_size(road.street_name)
		
		var size = road.get_node("CollisionShape").shape.extents
		var rotation := 0.0
		if size.x < size.z:
			rotation = deg2rad(-90.0)
			namePos -= Vector2(textSize.x/8.0, -textSize.y*2.0)
		else:
			namePos -= Vector2(textSize.x/2.0, textSize.y)
			pass
		
		mapBackground.draw_set_transform(namePos, rotation, Vector2(1.0, 1.0))
		mapBackground.draw_string(font, Vector2(), road.street_name)
		mapBackground.draw_set_transform(Vector2(), 0.0, Vector2(1.0, 1.0))

