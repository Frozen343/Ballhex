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
var available_lobbies: Array = []
var active_lobby_id := ""
var active_lobby_name := ""

var _peer: ENetMultiplayerPeer
var _webrtc_peer: WebRTCMultiplayerPeer
var _rtc_connection: WebRTCPeerConnection
var _signaling_socket: WebSocketPeer
var _signaling_was_open := false
var _suppress_socket_close := false
var _local_web_peer_id := 1
var _pending_ice_candidates: Array = []


func _process(_delta: float) -> void:
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


func host_game(port: int = DEFAULT_PORT, lobby_name: String = "") -> Error:
	if uses_web_lobbies():
		_start_web_host_flow(lobby_name)
		return OK

	_cleanup()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("NetworkManager: Failed to create server on port %d - %s" % [port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = _peer
	is_online = true
	is_host_player = true
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
	_bind_signals()
	print("NetworkManager: Joining %s:%d" % [address, port])
	return OK


func refresh_lobbies() -> void:
	if not uses_web_lobbies():
		return
	matchmaking_status_changed.emit("Lobiler yenileniyor...")
	_refresh_lobbies_async.call_deferred()


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


func _start_web_host_flow(lobby_name: String) -> void:
	_cleanup()
	var error := _create_web_host_peer()
	if error != OK:
		_fail_matchmaking("Web host baslatilamadi.", true)
		return

	active_lobby_name = _sanitize_lobby_name(lobby_name)
	matchmaking_status_changed.emit("Lobi olusturuluyor...")
	_host_lobby_async.call_deferred(active_lobby_name)


func _start_web_join_flow(lobby_id: String) -> void:
	_cleanup()
	_local_web_peer_id = randi_range(2, 2147483647)
	var error := _create_web_client_peer(_local_web_peer_id)
	if error != OK:
		_fail_matchmaking("Web client baslatilamadi.", true)
		return

	active_lobby_id = lobby_id
	active_lobby_name = ""
	matchmaking_status_changed.emit("Lobiye baglaniliyor...")
	var signaling_error := _connect_signaling(_build_signaling_url(lobby_id, false, _local_web_peer_id))
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


func _host_lobby_async(lobby_name: String) -> void:
	var response := await _request_json(
		HTTPClient.METHOD_POST,
		_build_http_url(WEB_LOBBIES_PATH),
		{"name": lobby_name}
	)
	if not response.get("ok", false):
		_fail_matchmaking("Lobi olusturulamadi.", true)
		return

	var data: Dictionary = response.get("data", {})
	active_lobby_id = str(data.get("id", ""))
	active_lobby_name = str(data.get("name", lobby_name))
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
			matchmaking_status_changed.emit("Lobby yayinlandi")
		"guest_ready":
			matchmaking_status_changed.emit("Host baglantisi bekleniyor...")
		"guest_joined":
			_on_guest_joined_for_webrtc(int(message.get("peerId", 2)))
		"guest_left":
			_on_guest_left()
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

	var offer_error := _rtc_connection.create_offer()
	if offer_error != OK:
		_fail_matchmaking("WebRTC offer olusturulamadi.", true)
		return

	matchmaking_status_changed.emit("Oyuncuya teklif gonderiliyor...")


func _handle_webrtc_signal(message: Dictionary) -> void:
	var kind := str(message.get("kind", ""))

	match kind:
		"offer":
			_on_webrtc_offer(message)
		"answer":
			_on_webrtc_answer(message)
		"ice":
			_on_webrtc_ice_candidate(message)


func _on_webrtc_offer(message: Dictionary) -> void:
	var error := _ensure_rtc_connection(1)
	if error != OK:
		_fail_matchmaking("WebRTC istemci baglantisi hazirlanamadi.", true)
		return

	var sdp_type := str(message.get("sdpType", "offer"))
	var sdp := str(message.get("sdp", ""))
	var remote_error := _rtc_connection.set_remote_description(sdp_type, sdp)
	if remote_error != OK:
		_fail_matchmaking("Host teklifi uygulanamadi.", true)
		return
	_flush_pending_ice_candidates()
	matchmaking_status_changed.emit("Host ile el sikisiliyor...")


func _on_webrtc_answer(message: Dictionary) -> void:
	if _rtc_connection == null:
		_fail_matchmaking("WebRTC answer icin aktif baglanti yok.", true)
		return

	var sdp_type := str(message.get("sdpType", "answer"))
	var sdp := str(message.get("sdp", ""))
	var remote_error := _rtc_connection.set_remote_description(sdp_type, sdp)
	if remote_error != OK:
		_fail_matchmaking("WebRTC cevap uygulanamadi.", true)
		return
	_flush_pending_ice_candidates()
	matchmaking_status_changed.emit("Oyuncu baglantisi tamamlaniyor...")


func _on_webrtc_ice_candidate(message: Dictionary) -> void:
	var candidate := {
		"mid": str(message.get("mid", "")),
		"index": int(message.get("index", 0)),
		"sdp": str(message.get("sdp", ""))
	}

	if _rtc_connection == null:
		_pending_ice_candidates.append(candidate)
		return

	_apply_ice_candidate(candidate)


func _ensure_rtc_connection(peer_id: int) -> Error:
	if _rtc_connection != null:
		return OK

	_rtc_connection = WebRTCPeerConnection.new()
	var initialize_error := _rtc_connection.initialize({
		"iceServers": [
			{
				"urls": WEB_STUN_SERVERS
			}
		]
	})
	if initialize_error != OK:
		return initialize_error

	_rtc_connection.session_description_created.connect(_on_session_description_created.bind(peer_id))
	_rtc_connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(peer_id))
	return _webrtc_peer.add_peer(_rtc_connection, peer_id)


func _on_session_description_created(sdp_type: String, sdp: String, peer_id: int) -> void:
	if _rtc_connection == null or _signaling_socket == null:
		return

	_rtc_connection.set_local_description(sdp_type, sdp)
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


func _apply_ice_candidate(candidate: Dictionary) -> void:
	if _rtc_connection == null:
		return
	_rtc_connection.add_ice_candidate(
		str(candidate.get("mid", "")),
		int(candidate.get("index", 0)),
		str(candidate.get("sdp", ""))
	)


func _flush_pending_ice_candidates() -> void:
	if _rtc_connection == null:
		return
	for candidate in _pending_ice_candidates:
		_apply_ice_candidate(candidate)
	_pending_ice_candidates.clear()


func _on_guest_left() -> void:
	if _webrtc_peer != null and remote_peer_id >= 0:
		_webrtc_peer.remove_peer(remote_peer_id)
	if _rtc_connection != null:
		_rtc_connection.close()
		_rtc_connection = null
	remote_peer_id = -1
	matchmaking_status_changed.emit("Lobby acik, yeni oyuncu bekleniyor...")


func _sanitize_lobby_name(lobby_name: String) -> String:
	var cleaned := lobby_name.strip_edges()
	if cleaned.is_empty():
		cleaned = "%s %02d" % [DEFAULT_LOBBY_NAME, randi_range(10, 99)]
	if cleaned.length() > 32:
		cleaned = cleaned.substr(0, 32)
	return cleaned


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
	remote_peer_id = id
	print("NetworkManager: Peer connected - id %d" % id)
	peer_connected.emit(id)
	if is_host_player:
		connection_established.emit()


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Peer disconnected - id %d" % id)
	peer_disconnected.emit(id)
	remote_peer_id = -1


func _on_connected_to_server() -> void:
	if remote_peer_id < 0:
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

	if _rtc_connection != null:
		_rtc_connection.close()
		_rtc_connection = null

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
	active_lobby_id = ""
	active_lobby_name = ""
	_local_web_peer_id = 1
	_pending_ice_candidates.clear()


func _close_signaling_socket() -> void:
	if _signaling_socket == null:
		return

	_suppress_socket_close = true
	if _signaling_socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_signaling_socket.close()
	_signaling_socket = null
	_signaling_was_open = false
