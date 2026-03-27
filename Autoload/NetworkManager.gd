extends Node

signal connection_established
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected
signal lobbies_updated(lobbies: Array)
signal lobby_hosted(lobby_id: String, lobby_name: String)
signal matchmaking_status_changed(message: String)
signal matchmaking_failed(message: String)

const DEFAULT_PORT := 7000
const MAX_CLIENTS := 1
const DEFAULT_LOBBY_NAME := "Hexball Lobby"
const DEFAULT_LOBBY_CAPACITY := 4
const SERVICE_ORIGIN_OVERRIDE := ""
const WEB_LOBBIES_PATH := "/api/lobbies"
const WEB_SIGNAL_PATH := "/ws"
const WEB_STUN_SERVERS := [
	"stun:stun.l.google.com:19302",
	"stun:stun1.l.google.com:19302"
]

var is_online := false
var is_host_player := false
var remote_peer_id := -1
var local_peer_id := 1
var lobby_max_players := 2
var available_lobbies: Array = []
var active_lobby_id := ""
var active_lobby_name := ""
var active_match_duration_seconds := GameSettings.MATCH_DURATION_SECONDS
var active_score_limit := GameSettings.DEFAULT_SCORE_LIMIT
var connected_peer_ids: Array[int] = []

var _peer: ENetMultiplayerPeer
var _webrtc_peer: WebRTCMultiplayerPeer
var _rtc_connections: Dictionary = {}
var _signaling_socket: WebSocketPeer
var _signaling_was_open := false
var _suppress_socket_close := false
var _pending_ice_candidates: Dictionary = {}


func _process(_delta: float) -> void:
	for connection in _rtc_connections.values():
		var rtc_connection := connection as WebRTCPeerConnection
		if rtc_connection != null:
			rtc_connection.poll()

	if _signaling_socket == null:
		return

	_signaling_socket.poll()
	var state := _signaling_socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not _signaling_was_open:
		_signaling_was_open = true
		_on_signaling_socket_open()

	if state == WebSocketPeer.STATE_OPEN:
		while _signaling_socket.get_available_packet_count() > 0:
			var payload := _signaling_socket.get_packet().get_string_from_utf8()
			var message = JSON.parse_string(payload)
			if typeof(message) != TYPE_DICTIONARY:
				continue
			_handle_signaling_message(message)
		return

	if state == WebSocketPeer.STATE_CLOSED and _signaling_was_open:
		var code := _signaling_socket.get_close_code()
		var reason := _signaling_socket.get_close_reason()
		_signaling_was_open = false
		_signaling_socket = null
		if not _suppress_socket_close:
			_handle_signaling_closed(code, reason)
		_suppress_socket_close = false


func uses_web_lobbies() -> bool:
	return OS.has_feature("web")


func get_local_peer_id() -> int:
	return local_peer_id


func get_connected_peer_ids() -> Array[int]:
	return connected_peer_ids.duplicate()


func get_lobby_capacity() -> int:
	return max(2, lobby_max_players)


func host_game(
	port: int = DEFAULT_PORT,
	lobby_name: String = "",
	max_players: int = DEFAULT_LOBBY_CAPACITY,
	match_duration_seconds: float = GameSettings.MATCH_DURATION_SECONDS,
	score_limit: int = GameSettings.DEFAULT_SCORE_LIMIT
) -> Error:
	var safe_match_duration_seconds := _sanitize_match_duration_seconds(match_duration_seconds)
	var safe_score_limit := _sanitize_score_limit(score_limit)
	var safe_lobby_name := _sanitize_lobby_name(lobby_name)
	if uses_web_lobbies():
		_start_web_host_flow(safe_lobby_name, max_players, safe_match_duration_seconds, safe_score_limit)
		return OK

	_cleanup()
	active_match_duration_seconds = safe_match_duration_seconds
	active_score_limit = safe_score_limit
	active_lobby_name = safe_lobby_name
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("NetworkManager: Failed to create server on port %d - %s" % [port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = _peer
	is_online = true
	is_host_player = true
	local_peer_id = 1
	lobby_max_players = 2
	_bind_signals()
	print("NetworkManager: Hosting on port %d" % port)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	if uses_web_lobbies():
		if address.strip_edges().is_empty():
			matchmaking_failed.emit("Once bir lobby sec.")
			return ERR_INVALID_PARAMETER
		_start_web_join_flow(address.strip_edges())
		return OK

	_cleanup()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port)
	if error != OK:
		push_error("NetworkManager: Failed to connect to %s:%d - %s" % [address, port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = _peer
	is_online = true
	is_host_player = false
	local_peer_id = 2
	lobby_max_players = 2
	_bind_signals()
	print("NetworkManager: Joining %s:%d" % [address, port])
	return OK


func refresh_lobbies() -> void:
	if not uses_web_lobbies():
		return
	matchmaking_status_changed.emit("Lobiler yenileniyor...")
	_refresh_lobbies_async.call_deferred()


func update_lobby_settings(match_duration_seconds: float, score_limit: int) -> void:
	active_match_duration_seconds = _sanitize_match_duration_seconds(match_duration_seconds)
	active_score_limit = _sanitize_score_limit(score_limit)
	if not uses_web_lobbies() or not is_host_player or active_lobby_id.is_empty():
		return
	_update_lobby_settings_async.call_deferred(active_lobby_id, active_match_duration_seconds, active_score_limit)


func disconnect_game() -> void:
	_cleanup()


func is_host() -> bool:
	return not is_online or is_host_player


func _bind_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _start_web_host_flow(lobby_name: String, max_players: int, match_duration_seconds: float, score_limit: int) -> void:
	_cleanup()
	local_peer_id = 1
	lobby_max_players = max(2, max_players)
	active_match_duration_seconds = _sanitize_match_duration_seconds(match_duration_seconds)
	active_score_limit = _sanitize_score_limit(score_limit)
	var error := _create_web_host_peer()
	if error != OK:
		_fail_matchmaking("Web host baslatilamadi.", true)
		return

	active_lobby_name = _sanitize_lobby_name(lobby_name)
	matchmaking_status_changed.emit("Lobi olusturuluyor...")
	_host_lobby_async.call_deferred(active_lobby_name, lobby_max_players, active_match_duration_seconds, active_score_limit)


func _start_web_join_flow(lobby_id: String) -> void:
	_cleanup()
	local_peer_id = randi_range(2, 2147483647)
	var error := _create_web_client_peer(local_peer_id)
	if error != OK:
		_fail_matchmaking("Web client baslatilamadi.", true)
		return

	active_lobby_id = lobby_id
	active_lobby_name = ""
	matchmaking_status_changed.emit("Lobiye baglaniliyor...")
	var signaling_error := _connect_signaling(_build_signaling_url(lobby_id, false, local_peer_id))
	if signaling_error != OK:
		_fail_matchmaking("Signaling sunucusuna baglanilamadi.", true)


func _create_web_host_peer() -> Error:
	_webrtc_peer = WebRTCMultiplayerPeer.new()
	var error := _webrtc_peer.create_server()
	if error != OK:
		return error
	multiplayer.multiplayer_peer = _webrtc_peer
	is_online = true
	is_host_player = true
	_bind_signals()
	return OK


func _create_web_client_peer(peer_id: int) -> Error:
	_webrtc_peer = WebRTCMultiplayerPeer.new()
	var error := _webrtc_peer.create_client(peer_id)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = _webrtc_peer
	is_online = true
	is_host_player = false
	_bind_signals()
	return OK


func _host_lobby_async(lobby_name: String, max_players: int, match_duration_seconds: float, score_limit: int) -> void:
	var response := await _request_json(
		HTTPClient.METHOD_POST,
		_build_http_url(WEB_LOBBIES_PATH),
		{
			"name": lobby_name,
			"maxPlayers": max_players,
			"matchDurationSeconds": match_duration_seconds,
			"scoreLimit": score_limit
		}
	)
	if not response.get("ok", false):
		_fail_matchmaking("Lobi olusturulamadi.", true)
		return

	var data: Dictionary = response.get("data", {})
	active_lobby_id = str(data.get("id", ""))
	active_lobby_name = str(data.get("name", lobby_name))
	lobby_max_players = int(data.get("maxPlayers", max_players))
	active_match_duration_seconds = _sanitize_match_duration_seconds(float(data.get("matchDurationSeconds", match_duration_seconds)))
	active_score_limit = _sanitize_score_limit(int(data.get("scoreLimit", score_limit)))
	if active_lobby_id.is_empty():
		_fail_matchmaking("Lobby kimligi alinamadi.", true)
		return

	matchmaking_status_changed.emit("Signaling baglantisi aciliyor...")
	var signaling_error := _connect_signaling(_build_signaling_url(active_lobby_id, true, 1))
	if signaling_error != OK:
		_fail_matchmaking("Signaling sunucusuna baglanilamadi.", true)


func _refresh_lobbies_async() -> void:
	var response := await _request_json(
		HTTPClient.METHOD_GET,
		_build_http_url(WEB_LOBBIES_PATH)
	)
	if not response.get("ok", false):
		available_lobbies = []
		lobbies_updated.emit(available_lobbies)
		matchmaking_failed.emit("Lobby listesi alinamadi.")
		return

	var data: Dictionary = response.get("data", {})
	var lobbies = data.get("lobbies", [])
	if typeof(lobbies) != TYPE_ARRAY:
		lobbies = []
	available_lobbies = lobbies
	lobbies_updated.emit(available_lobbies)
	matchmaking_status_changed.emit("Hazir")


func _update_lobby_settings_async(lobby_id: String, match_duration_seconds: float, score_limit: int) -> void:
	var response := await _request_json(
		HTTPClient.METHOD_PATCH,
		_build_http_url("%s/%s/settings" % [WEB_LOBBIES_PATH, lobby_id.uri_encode()]),
		{
			"matchDurationSeconds": match_duration_seconds,
			"scoreLimit": score_limit
		}
	)
	if not response.get("ok", false):
		return
	var data: Dictionary = response.get("data", {})
	active_match_duration_seconds = _sanitize_match_duration_seconds(float(data.get("matchDurationSeconds", match_duration_seconds)))
	active_score_limit = _sanitize_score_limit(int(data.get("scoreLimit", score_limit)))


func _request_json(method: HTTPClient.Method, url: String, body: Dictionary = {}) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := ""
	if not body.is_empty():
		payload = JSON.stringify(body)

	var request_error := request.request(url, headers, method, payload)
	if request_error != OK:
		request.queue_free()
		return {
			"ok": false,
			"error": request_error
		}

	var result: Array = await request.request_completed
	request.queue_free()

	var transport_result: int = result[0]
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	var response_text := response_body.get_string_from_utf8()
	var parsed = JSON.parse_string(response_text)
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"result": transport_result,
			"status": response_code
		}
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"status": response_code,
			"data": parsed if typeof(parsed) == TYPE_DICTIONARY else {}
		}

	return {
		"ok": true,
		"status": response_code,
		"data": parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	}


func _connect_signaling(url: String) -> Error:
	_signaling_socket = WebSocketPeer.new()
	_signaling_was_open = false
	_suppress_socket_close = false
	var error := _signaling_socket.connect_to_url(url)
	if error != OK:
		_signaling_socket = null
		return error
	return OK


func _on_signaling_socket_open() -> void:
	matchmaking_status_changed.emit("Lobby hazir")
	if is_host_player:
		lobby_hosted.emit(active_lobby_id, active_lobby_name)
	else:
		matchmaking_status_changed.emit("Host teklifi bekleniyor...")


func _handle_signaling_closed(code: int, reason: String) -> void:
	var close_message := "Signaling baglantisi kapandi."
	if code > 0:
		close_message = "%s (%d)" % [close_message, code]
	if not reason.is_empty():
		close_message = "%s %s" % [close_message, reason]

	if is_online:
		if is_host_player:
			_fail_matchmaking(close_message, true)
		else:
			_on_server_disconnected()


func _handle_signaling_message(message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))

	match message_type:
		"host_ready":
			var lobby_info: Dictionary = message.get("lobby", {})
			lobby_max_players = int(lobby_info.get("maxPlayers", lobby_max_players))
			active_match_duration_seconds = _sanitize_match_duration_seconds(float(lobby_info.get("matchDurationSeconds", active_match_duration_seconds)))
			active_score_limit = _sanitize_score_limit(int(lobby_info.get("scoreLimit", active_score_limit)))
			matchmaking_status_changed.emit("Lobby yayinlandi")
		"guest_ready":
			var ready_lobby: Dictionary = message.get("lobby", {})
			lobby_max_players = int(ready_lobby.get("maxPlayers", lobby_max_players))
			active_match_duration_seconds = _sanitize_match_duration_seconds(float(ready_lobby.get("matchDurationSeconds", active_match_duration_seconds)))
			active_score_limit = _sanitize_score_limit(int(ready_lobby.get("scoreLimit", active_score_limit)))
			matchmaking_status_changed.emit("Host baglantisi bekleniyor...")
		"guest_joined":
			_on_guest_joined_for_webrtc(int(message.get("peerId", 2)))
		"guest_left":
			_on_guest_left(int(message.get("peerId", -1)))
		"lobby_closed":
			_on_server_disconnected()
		"error":
			_fail_matchmaking(str(message.get("message", "Bilinmeyen hata.")), true)
		"signal":
			_handle_webrtc_signal(message)


func _on_guest_joined_for_webrtc(peer_id: int) -> void:
	if peer_id < 2:
		_fail_matchmaking("Gecersiz guest peer id.", true)
		return

	var error := _ensure_rtc_connection(peer_id)
	if error != OK:
		_fail_matchmaking("WebRTC baglantisi hazirlanamadi.", true)
		return

	var rtc_connection := _rtc_connections.get(peer_id) as WebRTCPeerConnection
	if rtc_connection == null:
		_fail_matchmaking("WebRTC oturumu bulunamadi.", true)
		return

	var offer_error: Error = rtc_connection.create_offer()
	if offer_error != OK:
		_fail_matchmaking("WebRTC offer olusturulamadi.", true)
		return

	matchmaking_status_changed.emit("Oyuncuya teklif gonderiliyor...")


func _handle_webrtc_signal(message: Dictionary) -> void:
	var kind := str(message.get("kind", ""))
	var peer_id := _get_connection_peer_id(int(message.get("peerId", 1)))

	match kind:
		"offer":
			_on_webrtc_offer(peer_id, message)
		"answer":
			_on_webrtc_answer(peer_id, message)
		"ice":
			_on_webrtc_ice_candidate(peer_id, message)


func _on_webrtc_offer(peer_id: int, message: Dictionary) -> void:
	var error := _ensure_rtc_connection(peer_id)
	if error != OK:
		_fail_matchmaking("WebRTC istemci baglantisi hazirlanamadi.", true)
		return

	var rtc_connection := _rtc_connections.get(peer_id) as WebRTCPeerConnection
	if rtc_connection == null:
		_fail_matchmaking("WebRTC baglantisi bulunamadi.", true)
		return

	var sdp_type := str(message.get("sdpType", "offer"))
	var sdp := str(message.get("sdp", ""))
	var remote_error := rtc_connection.set_remote_description(sdp_type, sdp)
	if remote_error != OK:
		_fail_matchmaking("Host teklifi uygulanamadi.", true)
		return

	_flush_pending_ice_candidates(peer_id)
	var answer_error: Error = rtc_connection.create_answer()
	if answer_error != OK:
		_fail_matchmaking("WebRTC cevap olusturulamadi.", true)
		return
	matchmaking_status_changed.emit("Host ile el sikisiliyor...")


func _on_webrtc_answer(peer_id: int, message: Dictionary) -> void:
	var rtc_connection := _rtc_connections.get(peer_id) as WebRTCPeerConnection
	if rtc_connection == null:
		_fail_matchmaking("WebRTC answer icin aktif baglanti yok.", true)
		return

	var sdp_type := str(message.get("sdpType", "answer"))
	var sdp := str(message.get("sdp", ""))
	var remote_error := rtc_connection.set_remote_description(sdp_type, sdp)
	if remote_error != OK:
		_fail_matchmaking("WebRTC cevap uygulanamadi.", true)
		return

	_flush_pending_ice_candidates(peer_id)
	matchmaking_status_changed.emit("Oyuncu baglantisi tamamlaniyor...")


func _on_webrtc_ice_candidate(peer_id: int, message: Dictionary) -> void:
	var candidate := {
		"mid": str(message.get("mid", "")),
		"index": int(message.get("index", 0)),
		"sdp": str(message.get("sdp", ""))
	}

	if not _rtc_connections.has(peer_id):
		if not _pending_ice_candidates.has(peer_id):
			_pending_ice_candidates[peer_id] = []
		var queue: Array = _pending_ice_candidates[peer_id]
		queue.append(candidate)
		_pending_ice_candidates[peer_id] = queue
		return

	_apply_ice_candidate(peer_id, candidate)


func _ensure_rtc_connection(peer_id: int) -> Error:
	if _rtc_connections.has(peer_id):
		return OK

	var rtc_connection := WebRTCPeerConnection.new()
	var initialize_error := rtc_connection.initialize({
		"iceServers": [
			{
				"urls": WEB_STUN_SERVERS
			}
		]
	})
	if initialize_error != OK:
		return initialize_error

	rtc_connection.session_description_created.connect(_on_session_description_created.bind(peer_id))
	rtc_connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(peer_id))
	_rtc_connections[peer_id] = rtc_connection
	if not _pending_ice_candidates.has(peer_id):
		_pending_ice_candidates[peer_id] = []
	return _webrtc_peer.add_peer(rtc_connection, peer_id)


func _on_session_description_created(sdp_type: String, sdp: String, peer_id: int) -> void:
	var rtc_connection := _rtc_connections.get(peer_id) as WebRTCPeerConnection
	if rtc_connection == null or _signaling_socket == null:
		return

	rtc_connection.set_local_description(sdp_type, sdp)
	_send_signaling_message({
		"type": "signal",
		"kind": sdp_type,
		"peerId": peer_id,
		"sdpType": sdp_type,
		"sdp": sdp
	})


func _on_ice_candidate_created(mid_name: String, index_name: int, sdp_name: String, peer_id: int) -> void:
	_send_signaling_message({
		"type": "signal",
		"kind": "ice",
		"peerId": peer_id,
		"mid": mid_name,
		"index": index_name,
		"sdp": sdp_name
	})


func _send_signaling_message(message: Dictionary) -> void:
	if _signaling_socket == null:
		return
	if _signaling_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_signaling_socket.send_text(JSON.stringify(message))


func _apply_ice_candidate(peer_id: int, candidate: Dictionary) -> void:
	var rtc_connection := _rtc_connections.get(peer_id) as WebRTCPeerConnection
	if rtc_connection == null:
		return
	rtc_connection.add_ice_candidate(
		str(candidate.get("mid", "")),
		int(candidate.get("index", 0)),
		str(candidate.get("sdp", ""))
	)


func _flush_pending_ice_candidates(peer_id: int) -> void:
	if not _pending_ice_candidates.has(peer_id):
		return
	var queue: Array = _pending_ice_candidates.get(peer_id, [])
	for candidate in queue:
		_apply_ice_candidate(peer_id, candidate)
	_pending_ice_candidates[peer_id] = []


func _on_guest_left(peer_id: int) -> void:
	_remove_rtc_peer(peer_id)
	matchmaking_status_changed.emit("Lobby acik, yeni oyuncu bekleniyor...")


func _remove_rtc_peer(peer_id: int) -> void:
	if peer_id < 0:
		return
	if not _rtc_connections.has(peer_id) and not connected_peer_ids.has(peer_id):
		return

	if _webrtc_peer != null and (_rtc_connections.has(peer_id) or connected_peer_ids.has(peer_id)):
		_webrtc_peer.remove_peer(peer_id)

	var rtc_connection := _rtc_connections.get(peer_id) as WebRTCPeerConnection
	if rtc_connection != null:
		rtc_connection.close()
	_rtc_connections.erase(peer_id)
	_pending_ice_candidates.erase(peer_id)
	connected_peer_ids.erase(peer_id)
	if remote_peer_id == peer_id:
		remote_peer_id = connected_peer_ids[0] if not connected_peer_ids.is_empty() else -1


func _sanitize_lobby_name(lobby_name: String) -> String:
	var cleaned := lobby_name.strip_edges()
	if cleaned.is_empty():
		cleaned = "%s %02d" % [DEFAULT_LOBBY_NAME, randi_range(10, 99)]
	if cleaned.length() > 32:
		cleaned = cleaned.substr(0, 32)
	return cleaned


func _sanitize_match_duration_seconds(duration_seconds: float) -> float:
	return clampf(duration_seconds, GameSettings.MIN_MATCH_DURATION_SECONDS, GameSettings.MAX_MATCH_DURATION_SECONDS)


func _sanitize_score_limit(score_limit: int) -> int:
	return maxi(GameSettings.MIN_SCORE_LIMIT, mini(GameSettings.MAX_SCORE_LIMIT, score_limit))


func _get_connection_peer_id(signaling_peer_id: int) -> int:
	if is_host_player:
		return signaling_peer_id
	return 1


func _build_http_url(path: String) -> String:
	return "%s%s" % [_get_service_origin(), path]


func _build_signaling_url(lobby_id: String, as_host: bool, peer_id: int) -> String:
	var origin := _get_service_origin()
	var protocol := "wss://"
	if origin.begins_with("http://"):
		protocol = "ws://"
	var host := origin.trim_prefix("https://").trim_prefix("http://")
	var role := "host" if as_host else "guest"
	var query := "lobbyId=%s&role=%s&peerId=%d" % [lobby_id.uri_encode(), role, peer_id]
	return "%s%s%s?%s" % [protocol, host, WEB_SIGNAL_PATH, query]


func _get_service_origin() -> String:
	if not SERVICE_ORIGIN_OVERRIDE.is_empty():
		return SERVICE_ORIGIN_OVERRIDE.trim_suffix("/")

	if OS.has_feature("web"):
		var web_origin = str(JavaScriptBridge.eval("window.location.origin"))
		if not web_origin.is_empty():
			return web_origin.trim_suffix("/")

	return "http://localhost:3000"


func _fail_matchmaking(message: String, emit_connection_failure: bool) -> void:
	push_warning("NetworkManager: %s" % message)
	matchmaking_failed.emit(message)
	if emit_connection_failure:
		connection_failed.emit()
	_cleanup()


func _on_peer_connected(id: int) -> void:
	if not connected_peer_ids.has(id):
		connected_peer_ids.append(id)
	connected_peer_ids.sort()
	if remote_peer_id < 0:
		remote_peer_id = id
	print("NetworkManager: Peer connected - id %d" % id)
	peer_connected.emit(id)
	if is_host_player:
		connection_established.emit()


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected - id %d" % id)
	_remove_rtc_peer(id)
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	if not connected_peer_ids.has(1):
		connected_peer_ids.append(1)
	connected_peer_ids.sort()
	remote_peer_id = 1
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
	_close_signaling_socket()

	for peer_id in _rtc_connections.keys():
		var rtc_connection := _rtc_connections[peer_id] as WebRTCPeerConnection
		if rtc_connection != null:
			rtc_connection.close()
	_rtc_connections.clear()
	_pending_ice_candidates.clear()

	if _webrtc_peer != null:
		_webrtc_peer.close()
		_webrtc_peer = null

	if _peer != null:
		_peer.close()
		_peer = null

	multiplayer.multiplayer_peer = null

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
	local_peer_id = 1
	lobby_max_players = 2
	active_lobby_id = ""
	active_lobby_name = ""
	active_match_duration_seconds = GameSettings.MATCH_DURATION_SECONDS
	active_score_limit = GameSettings.DEFAULT_SCORE_LIMIT
	connected_peer_ids.clear()


func _close_signaling_socket() -> void:
	if _signaling_socket == null:
		return

	_suppress_socket_close = true
	if _signaling_socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_signaling_socket.close()
	_signaling_socket = null
	_signaling_was_open = false
