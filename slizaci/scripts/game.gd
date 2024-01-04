extends Node

@export var server_game_phase = "loading"
#loading		- Loading map at new level

#warmup 		- pre game phase with freeroam around the map
#			 	- players can spawn

#round_start	- short phase before round start
#				- players are frozen in place and waiting for round to start
#			 	- players can spawn

#round_play 	- actual game play phase
#				- players can spawn based on gamemode

#round_end 		- short phase at the end of a round
#				- players can not spawn

#game_end 		- post game phase, 
#				- players are forzen in place
#				- players can not spawn


const DEFAULT_WARMUP_TIME = 120.0
const DEFAULT_ROUND_START_TIME = 10.0
const DEFAULT_ROUND_PLAY_TIME = 300.0
const DEFAULT_ROUND_END_TIME = 5.0
const DEFAULT_GAME_END_TIME = 30.0


signal game_loaded
signal game_ended
signal team_select


var number_of_rounds = 1
var current_round_number = 0

@export var can_players_spawn = false
var player_spawned = false

var map = "res://scenes/levels/test_01.tscn"
var minimal_player_size = 2
var max_team_players = 8
var round_time = 300.0

var player_info = {"name" = PlayerSettings.player_name, 
	"color" = PlayerSettings.player_color, 
	"team" = -1, #0 = spactate, 1 or more = actual teams 
	"kills" = 0, 
	"deaths" = 0}

@export var players = {}

var number_of_teams = 2
var team_info = {"is_full" = false,
	 "max_players" = 1,
	 "players" = 0,
	 "can_join" = true}

@export var teams = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	MultiplayerManager.connection_lost.connect(connection_lost)
	MultiplayerManager.player_disconnected.connect(player_disconnected)
	MultiplayerManager.succeded_to_connect.connect(succeded_to_connect)
	$/root/Main/%TeamSelect.team_selected.connect(team_selected)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if !player_info.team == 0 and !player_spawned and can_players_spawn:
		spawn_player.rpc_id(1)
		player_spawned = true
	

func connection_lost():
	GameManager.game_status = "menu"
	player_info.team = 0
	player_spawned = false
	players = {}
	teams = {}
	can_players_spawn = false
	
	var level = %Level
	for c in level.get_children():
		c.queue_free()
	
	player_spawned = false
	var players = %Players
	for c in players.get_children():
		c.queue_free()
		
	game_ended.emit()


func succeded_to_connect():
	GameManager.game_status = "loading_game"

	
func player_disconnected(id, _info):
	var nd = get_tree().get_nodes_in_group("id"+str(id))
	for c in nd:
		c.queue_free()
	
	
func server_load_game(map, player_size, time):
	GameManager.game_status = "loading"
	server_game_phase = "loading"
	self.map = map
	max_team_players = player_size
	round_time = time
		
	var game_load = load(map).instantiate()
	%Level.add_child(game_load, true)
	

@rpc("any_peer", "call_local", "reliable", 1)
func peer_loaded():
	if multiplayer.is_server():
		if multiplayer.get_remote_sender_id() == 1:
			server_set_warmup(DEFAULT_WARMUP_TIME)
			
			
func on_game_loaded():
	player_info["name"] = PlayerSettings.player_name	
	player_info["color"] = PlayerSettings.player_color
	
	teams[0] = team_info.duplicate()
	teams[0]["max_players"] = 99

	for i in number_of_teams:
		teams[i+1] = team_info.duplicate()
	
	GameManager.game_status = "in_game"
	players_info_changed.rpc_id(1, player_info)
	emit_signal("game_loaded")
	team_select.emit()
	team_selected(0)
	

@rpc("any_peer", "call_local",  "reliable", 1)
func players_info_changed(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	
	
func team_selected(team):
	if teams[team]["can_join"] and !teams[team]["is_full"]:
		team_changed.rpc(team)
		player_info.team = team
		players_info_changed.rpc(player_info)
		
		
@rpc("any_peer", "call_local",  "reliable", 1)
func team_changed(team):
	var id = multiplayer.get_remote_sender_id()
	
	if !players[id]["team"] == -1:
		var old_team = players[id]["team"]
		teams[old_team]["players"] -= 1
		if teams[old_team]["players"] <= teams[old_team]["max_players"]:
			teams[old_team]["is_full"] = false
	
	teams[team]["players"] += 1
	if teams[team]["players"] >= teams[team]["max_players"]:
		teams[team]["is_full"] = true
		
	players[id]["team"] = team
	

@rpc("any_peer", "call_local", "reliable", 7)
func spawn_player():
	var player = preload("res://scenes/player.tscn").instantiate()
	player.id = multiplayer.get_remote_sender_id()

	var spawn_points = get_tree().get_nodes_in_group("player_spawn_point_team_"+str(players[multiplayer.get_remote_sender_id()]["team"]))

	if spawn_points.is_empty():
		return
		
	if spawn_points.size() == 1:
		player.position = spawn_points[0].position
	else:
		var rng = RandomNumberGenerator.new()
		var my_random_number = rng.randf_range(0, spawn_points.size()-1)
		player.position = spawn_points[my_random_number].position
	
	%Players.add_child(player, true)
	

func server_set_warmup(time):
	server_game_phase = "warmup"
	can_players_spawn = true
	
	if time == 0:
		%PhaseTimer.wait_time = DEFAULT_WARMUP_TIME
	else:
		%PhaseTimer.wait_time = time
	
	%PhaseTimer.start()	
	

func server_set_round_start(time):
	server_game_phase = "round_start"
	can_players_spawn = true
	
	if time == 0:
		%PhaseTimer.wait_time = DEFAULT_ROUND_START_TIME
	else:
		%PhaseTimer.wait_time = time
	
	%PhaseTimer.start()	
	
	
func server_set_round_play(time):
	server_game_phase = "round_play"
	can_players_spawn = true
	
	if time == 0:
		%PhaseTimer.wait_time = DEFAULT_ROUND_PLAY_TIME
	else:
		%PhaseTimer.wait_time = time
	
	%PhaseTimer.start()	
	
	
func server_set_round_end(time):
	server_game_phase = "round_end"
	can_players_spawn = false
	
	if time == 0:
		%PhaseTimer.wait_time = DEFAULT_ROUND_END_TIME
	else:
		%PhaseTimer.wait_time = time
		
	%PhaseTimer.start()	


func server_set_game_end(time):
	server_game_phase = "game_end"
	can_players_spawn = false

	if time == 0:
		%PhaseTimer.wait_time = DEFAULT_GAME_END_TIME
	else:
		%PhaseTimer.wait_time = time

	%PhaseTimer.start()	


func _on_game_timer_timeout():
	match server_game_phase:
		"warmup":
			current_round_number = 1
			server_set_round_start(DEFAULT_ROUND_START_TIME)
		"round_start":
			server_set_round_play(DEFAULT_ROUND_PLAY_TIME)
		"round_play":
			server_set_round_end(DEFAULT_ROUND_END_TIME)
		"round_end":
			if current_round_number == number_of_rounds:
				server_set_game_end(DEFAULT_GAME_END_TIME)
			else:
				current_round_number += 1
				server_set_round_start(DEFAULT_ROUND_START_TIME)
		"game_end":
			server_load_game(map, max_team_players, round_time)
		
	
func _input(event):
	if event.is_action_pressed("team_select"):
		team_select.emit()
