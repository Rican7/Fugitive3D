extends Control
class_name Lobby

export(NodePath) var playerListPath: NodePath
onready var playerList := get_node(playerListPath) as VBoxContainer

var is_host := false
var is_starting := false

func _ready():
	ClientNetwork.connect("create_player", self, "create_player")
	ClientNetwork.connect("update_player", self, "update_player")
	ClientNetwork.connect("remove_player", self, "remove_player")
	
	call_deferred("update_ui")


func create_player(playerId: int):
	var existingPlayer := find_player_node(playerId)
	if existingPlayer != null:
		return
	
	print("Creating player in lobby")
	
	var player = GameData.players[playerId]
	
	var playerListItem = preload("res://common/lobby/PlayerListItem.tscn")
	
	var playerNode = playerListItem.instance()
	playerNode.set_network_master(playerId)
	playerNode.set_name(str(playerId))
	playerNode.populate(player, is_starting, is_host)
	
	playerList.add_child(playerNode)
	
	update_host(playerId)
	update_ui()


func find_player_node(playerId: int) -> Control:
	var playerNode: Control = null
	
	var nodeName := str(playerId)
	for child in playerList.get_children():
		if child.name == nodeName:
			playerNode = child
			break
	
	return playerNode


func update_player(playerId: int):
	var player = GameData.players[playerId]
	
	var node := find_player_node(playerId)
	if node != null:
		node.populate(player, is_starting, is_host)
	else:
		print("update_player() - Failed to get player node")
	
	update_host(playerId)
	update_ui()


func remove_player(playerId: int):
	var node := find_player_node(playerId)
	if node != null:
		playerList.remove_child(node)
	else:
		print("Lobby: remove_player: failed to find node for player: %d" % playerId)
	
	update_ui()


func update_all_players():
	if not GameData.players.empty():
		for playerId in GameData.players:
			update_player(playerId)


func can_start() -> bool:
	var canStart := false
	
	var numSeekers := 0
	var numHiders := 0
	
	var players = GameData.get_players()
	
	if not players.empty():
		for player in players:
			if player[GameData.PLAYER_TYPE] == GameData.PlayerType.Hider:
				numHiders += 1
			elif player[GameData.PLAYER_TYPE] == GameData.PlayerType.Seeker:
				numSeekers += 1
	
	canStart = (numHiders > 0 and numSeekers > 0)
	
	return canStart


func update_host(playerId: int):
	if playerId == get_tree().get_network_unique_id():
		var player = GameData.players[playerId]
		is_host = player[GameData.PLAYER_HOST]


func update_ui():
	pass


remotesync func start_timer():
	is_starting = true
	update_all_players()
