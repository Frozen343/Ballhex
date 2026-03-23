extends Node

signal connection_established
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected

const DEFAULT_PORT := 7000
const MAX_CLIENTS := 1

var is_online := false
var is_host_player := false
var remote_peer_id := -1

var _peer: ENetMultiplayerPeer


func host_game(port: int = DEFAULT_PORT) -> Error:
	_cleanup()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("NetworkManager: Failed to create server on port %d — %s" % [port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = _peer
	is_online = true
	is_host_player = true
	_bind_signals()
	print("NetworkManager: Hosting on port %d" % port)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	_cleanup()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port)
	if error != OK:
		push_error("NetworkManager: Failed to connect to %s:%d — %s" % [address, port, error_string(error)])
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


func _bind_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	remote_peer_id = id
	print("NetworkManager: Peer connected — id %d" % id)
	peer_connected.emit(id)
	if is_host_player:
		connection_established.emit()


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected — id %d" % id)
	peer_disconnected.emit(id)
	remote_peer_id = -1


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server")
	connection_established.emit()


func _on_connection_failed() -> void:
	push_warning("NetworkManager: Connection failed")
	connection_failed.emit()
	_cleanup()


func _on_server_disconnected() -> void:
	push_warning("NetworkManager: Server disconnected")
	server_disconnected.emit()
	_cleanup()


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
	remote_peer_id = -1
