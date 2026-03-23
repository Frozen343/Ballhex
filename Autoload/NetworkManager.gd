extends Node

signal connection_established
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected
signal lobby_updated

const DEFAULT_PORT := 7000
const MAX_CLIENTS := 8

var is_online := false
var is_host_player := false
var lobby_players: Dictionary = {}

var _peer: ENetMultiplayerPeer


func host_game(port: int = DEFAULT_PORT) -> Error:
	_cleanup()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("NetworkManager: Failed to create server — %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = _peer
	is_online = true
	is_host_player = true
	lobby_players.clear()
	lobby_players[1] = {"name": GameSettings.player_name, "team": GameEnums.TeamId.NEUTRAL}
	_bind_signals()
	print("NetworkManager: Hosting on port %d" % port)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	_cleanup()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port)
	if error != OK:
		push_error("NetworkManager: Failed to connect — %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = _peer
	is_online = true
	is_host_player = false
	_bind_signals()
	print("NetworkManager: Joining %s:%d" % [address, port])
	return OK


func disconnect_game() -> void:
	_cleanup()


func is_host() -> bool:
	return not is_online or is_host_player


func change_player_team(peer_id: int, new_team: int) -> void:
	if not is_host():
		return
	if lobby_players.has(peer_id):
		lobby_players[peer_id]["team"] = new_team
		_broadcast_lobby()


func _bind_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Peer connected — id %d" % id)
	peer_connected.emit(id)
	if is_host_player:
		connection_established.emit()


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected — id %d" % id)
	if is_host_player:
		lobby_players.erase(id)
		_broadcast_lobby()
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server")
	_rpc_register_client.rpc_id(1, GameSettings.player_name)
	connection_established.emit()


func _on_connection_failed() -> void:
	push_warning("NetworkManager: Connection failed")
	connection_failed.emit()
	_cleanup()


func _on_server_disconnected() -> void:
	push_warning("NetworkManager: Server disconnected")
	server_disconnected.emit()
	_cleanup()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_register_client(player_name: String) -> void:
	if not is_host_player:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	lobby_players[sender_id] = {"name": player_name, "team": GameEnums.TeamId.NEUTRAL}
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	if not is_host_player:
		return
	_rpc_receive_lobby.rpc(lobby_players)
	lobby_updated.emit()


@rpc("authority", "reliable", "call_remote")
func _rpc_receive_lobby(new_lobby: Dictionary) -> void:
	if not is_host_player:
		lobby_players = new_lobby
		lobby_updated.emit()


func _cleanup() -> void:
	if _peer != null:
		multiplayer.multiplayer_peer = null
		_peer = null
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	is_online = false
	is_host_player = false
	lobby_players.clear()
