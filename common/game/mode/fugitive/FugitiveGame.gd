extends GameMode
class_name FugitiveGame

onready var stateMachine := $StateMachine as FugitiveStateMachine

var map: FugitiveMap
var playersContainer: Node


var gameStarted := false
var winningTeam: int

func is_game_over() -> bool:
	return stateMachine == null or stateMachine.current_state.name == FugitiveStateMachine.STATE_GAME_OVER


func load_map():
	.load_map()
	
	map = GameData.currentMap
	
	playersContainer = map.get_players()
	
	var gameTimelimitTimer = map.get_timelimit_timer()
	gameTimelimitTimer.connect("timeout", self, "game_time_limit_exceeded")


# If a player has disconnected, remove them from the world
func remove_player(playerId: int):
	var playerNode = GameData.currentGame.get_player(playerId).playerController
	playerNode.queue_free()
	
	players.erase(playerId)


################################
# This is called by the GameMode class when it has decided
# the game is complete

# This will be overriden by ServerGame.
# The server will trigger the actual end-game functionality
# This makes the server authoratative about when the game ends
func finish_game(playerType: int):
	var hiders = get_tree().get_nodes_in_group(Hider.GROUP)
	var winZones := map.get_win_zones()
	
	for hider in hiders:
		if (not hider.frozen):
			for winZone in winZones:
				# If a hider is unfrozen and in any win zone, give them an "escaped" counter.
				if (winZone.overlaps_body(hider.playerBody)):
					FugitivePlayerDataUtility.increment_stat_for_player_id(hider.id, "hider_escaped")
					break

	rpc("on_finish_game", playerType)


remotesync func on_finish_game(playerType: int):
	var curState := stateMachine.current_state.name
	
	winningTeam = playerType
	
	if curState == FugitiveStateMachine.STATE_CONFIGURING:
		stateMachine.transition_by_name(FugitiveStateMachine.TRANS_END_GAME_ABORT_4)
	elif curState == FugitiveStateMachine.STATE_NOT_READY:
		stateMachine.transition_by_name(FugitiveStateMachine.TRANS_END_GAME_ABORT_3)
	elif curState == FugitiveStateMachine.STATE_READY:
		stateMachine.transition_by_name(FugitiveStateMachine.TRANS_END_GAME_ABORT_2)
	elif curState == FugitiveStateMachine.STATE_COUNTDOWN:
		stateMachine.transition_by_name(FugitiveStateMachine.TRANS_END_GAME_ABORT_1)
	elif curState == FugitiveStateMachine.STATE_PLAYING_HEADSTART:
		stateMachine.transition_by_name(FugitiveStateMachine.TRANS_END_GAME_EARLY)
	elif curState == FugitiveStateMachine.STATE_PLAYING:
		stateMachine.transition_by_name(FugitiveStateMachine.TRANS_END_GAME)
	else:
		print("FATAL! on_finish_game(): cannot finish game, in invalid state: %s " % curState)
		assert(false)


################################
# Pre-game configuration
# Create all of the players and entities
# This has to be completed on all clients before the game can start
# Once completed, notify the server that we are done
func pre_configure():
	.pre_configure()
	
	var sharedSeed = GameData.general[GameData.GENERAL_SEED]
	seed(sharedSeed)
	
	var sortedPlayers = []
	for playerId in GameData.players:
		sortedPlayers.push_back(playerId)
	
	sortedPlayers.sort()
	
	var hiderSpawns = map.get_hider_spawns()
	assert(not hiderSpawns.empty())
	# Randomize the spawn locations.
	# Due to the shared seed this will be the same
	# across all clients
	hiderSpawns.shuffle()
	
	var seekerSpawns = map.get_seeker_spawns()
	assert(not seekerSpawns.empty())
	seekerSpawns.shuffle()
	
	for playerId in sortedPlayers:
		spawn_player(playerId, hiderSpawns, seekerSpawns)
	
	# Randomly enable sensors
	var sensors = get_tree().get_nodes_in_group(Groups.MOTION_SENSORS)
	for sensor in sensors:
		# Random chance of being enabled
		if randi() % 6 == 0:
			sensor.set_enabled(true)
		else:
			sensor.set_enabled(false)


# Spawn an individual player for the local client
func spawn_player(playerId: int, hiderSpawns: Array, seekerSpawns: Array):
	print("Creating player game object")
	
	var localPlayerId := get_tree().get_network_unique_id()
	var localPlayerType: int
	if GameData.players.has(localPlayerId):
		localPlayerType = GameData.get_player(localPlayerId).get_type()
	else:
		localPlayerType = FugitiveTeamResolver.PlayerType.Unset
	
	# Extract the player data
	var player := GameData.get_player(playerId)
	var playerName := player.get_name()
	var playerType := player.get_type()
	
	# This is the node for the PlayerController
	var pcNode: Node
	var spawnPointNode: Spatial
	
	# Create the player controller for the local player
	if get_tree().get_network_unique_id() == playerId:
		match playerType:
			FugitiveTeamResolver.PlayerType.Seeker:
				pcNode = create_player_seeker_node()
				spawnPointNode = seekerSpawns.pop_front()
			FugitiveTeamResolver.PlayerType.Hider:
				pcNode = create_player_hider_node()
				spawnPointNode = hiderSpawns.pop_front()
	# Create the player controller for all remote players
	else:
		match playerType:
			FugitiveTeamResolver.PlayerType.Seeker:
				pcNode = create_remote_seeker_node()
				spawnPointNode = seekerSpawns.pop_front()
			FugitiveTeamResolver.PlayerType.Hider:
				pcNode = create_remote_hider_node()
				spawnPointNode = hiderSpawns.pop_front()
	
	pcNode.set_network_master(playerId)
	pcNode.set_name(str(playerId))
	
	# Add the PlayerController to the player's node in the game scene
	playersContainer.add_child(pcNode)
	
	# Final setup and config for the player
	var playerNode = pcNode.get_node("Player")
	playerNode.configure(playerName, playerId, localPlayerType)
	# Player listens to Game state changes
	stateMachine.connect("state_change", playerNode, "on_game_state_changed")
	
	# Add the player node to our list of players
	players[playerId] = playerNode
	
	# Move to the spawn point
	pcNode.global_transform = spawnPointNode.global_transform


remotesync func on_all_clients_configured():
	print("All clients are configured. Waiting for them to ready up.")
	get_tree().paused = false
	stateMachine.transition_by_name(FugitiveStateMachine.TRANS_CONFIGURED)


# When all clients have reported that they have finished setting up the gmae
# The server calls this on all clients telling them to start the game
remotesync func on_all_ready():
	print("All clients are ready. Starting the count down.")
	stateMachine.transition_by_name(FugitiveStateMachine.TRANS_START_COUNT)


####################################
# create_remote_xxx_node()
# These methods are used for creating players who are not
# localy controlled by this machine.
func create_remote_seeker_node() -> Node:
	var scene = preload("res://common/game/mode/fugitive/seeker/RemoteSeeker.tscn")
	return scene.instance()


func create_remote_hider_node() -> Node:
	var scene = preload("res://common/game/mode/fugitive/hider/RemoteHider.tscn")
	return scene.instance()


####################################
# create_player_xxx_node()
# These methods are used for creating players who are not
# localy controlled by this machine.
func create_player_seeker_node() -> Node:
	print("create_player_seeker_node() MUST BE OVERRIDEN")
	assert(false)
	return null


func create_player_hider_node() -> Node:
	print("create_player_hider_node() MUST BE OVERRIDEN")
	assert(false)
	return null

###################################


func _process(delta):
	if gameStarted and not is_game_over():
		process_hiders()
		check_win_conditions()


func process_hiders():
	var seekers = get_tree().get_nodes_in_group(Seeker.GROUP)
	var hiders = get_tree().get_nodes_in_group(Hider.GROUP)
	var lights = get_tree().get_nodes_in_group(Groups.LIGHTS)
	var cars = get_tree().get_nodes_in_group(Groups.CARS)
	var winZones := map.get_win_zones()
	
	var curPlayerType = GameData.get_current_player_type()
	
	# Process each hider, find if any have been seen
	for hider in hiders:
		# Re-hide Hiders every frame
		if not hider.frozen and hider.car == null:
			hider.current_visibility = 0.0
		# Frozen Hiders should always be vizible to Seekers
		else:
			hider.current_visibility = 1.0
			
		# If the hider is moving, make them a little visible
		# regaurdless of FOV/Distance
		var percent_visible = hider.current_visibility
		if hider.is_moving_fast():
			percent_visible += Seeker.SPRINT_VISIBILITY_PENALTY
		# Crouching should not make you visible at all
		elif hider.is_moving() and not hider.is_crouching:
			percent_visible += Seeker.MOVEMENT_VISIBILITY_PENALTY
		
		hider.current_visibility = clamp(percent_visible, 0.0, 1.0)
		
		for seeker in seekers:
			seeker.process_hider(hider)
		
		for light in lights:
			light.process_hider(hider)
		
		for car in cars:
			car.process_hider(hider)
			
		for winZone in winZones:
			# Now, check if this hider is in the win zone.
			if winZone.overlaps_body(hider.playerBody):
				hider.set_current_visibility(1.0)

func check_win_conditions():
	# Only the server will end the game
	if not get_tree().is_network_server():
		return
	
	var hiders = get_tree().get_nodes_in_group(Hider.GROUP)
	var seekers = get_tree().get_nodes_in_group(Seeker.GROUP)
	var winZones := map.get_win_zones()
	
	# Either all hiders are frozen OR
	# all non-frozen hiders are in a winzone
	var allHidersFrozen := true
	var allUnfrozenHidersInWinZone := true

	for hider in hiders:
		if (not hider.frozen):
			allHidersFrozen = false
			for winZone in winZones:
				# Now, check if this hider is in the win zone.
				if (not winZone.overlaps_body(hider.playerBody)):
					allUnfrozenHidersInWinZone = false
	
	if gameStarted and not is_game_over():
		if allHidersFrozen:
			finish_game(FugitiveTeamResolver.PlayerType.Seeker)
		elif allUnfrozenHidersInWinZone:
			finish_game(FugitiveTeamResolver.PlayerType.Hider)
		elif seekers.empty():
			finish_game(FugitiveTeamResolver.PlayerType.Hider)
		elif hiders.empty():
			finish_game(FugitiveTeamResolver.PlayerType.Seeker)


func game_time_limit_exceeded():
	print("Time ran out!")
	finish_game(FugitiveTeamResolver.PlayerType.Seeker)


func on_state_countdown(current_state: State, transition: Transition):
	print("Starting countdown")
	map.get_countdown_timer().start()


func on_state_playing_headstart(current_state: State, transition: Transition):
	print("Starting countdown")
	map.get_headstart_timer().start()


func on_state_game_over(current_state: State, transition: Transition):
	print("game is complete!")


remotesync func begin_game():
	print("Release the hiders!")
	stateMachine.transition_by_name(FugitiveStateMachine.TRANS_GAME_START)
	map.get_headstart_timer().start()
	map.get_timelimit_timer().start()
	gameStarted = true


remotesync func release_cops():
	print("Release the cops!")
	stateMachine.transition_by_name(FugitiveStateMachine.TRANS_COPS_RELEASED)


remotesync func on_go_to_lobby():
	print("on_go_to_lobby MUST BE OVERRIDEN")
	assert(false)


func start_lobby_timer():
	rpc("on_start_lobby_timer")


remote func on_start_lobby_timer():
	$ReturnToLobbyTimer.start()


func _on_ReturnToLobbyTimer_timeout():
	print("ReturnToLobbyTimer is up")
	on_go_to_lobby()


func go_to_lobby():
	# When the host goes to the lobby, everyone else has a timer start
	# which will force them back to the lobby
	if GameData.get_current_player().get_is_host():
		start_lobby_timer()
	
	on_go_to_lobby()

func get_team_name(teamId: int) -> String:
	return Maps.get_team_name(GameData.general[GameData.GENERAL_MAP], teamId)
