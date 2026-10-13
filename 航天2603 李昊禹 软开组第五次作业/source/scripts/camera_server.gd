extends Node

const PORT := 8080
var server := TCPServer.new()
var last_error := ""
var camera_viewport: SubViewport
var output_camera: Camera3D
var source_camera: Camera3D
var frame_id := 0
var pending_clients: Array[Dictionary] = []
var sending_clients: Array[Dictionary] = []


func _ready() -> void:
	build_camera_output()
	var error := server.listen(PORT, "127.0.0.1")
	if error != OK:
		last_error = "Port 8080 unavailable: %s" % error_string(error)
		push_warning(last_error)
	else:
		print("Camera/status server: http://127.0.0.1:8080/")


func build_camera_output() -> void:
	source_camera = get_node_or_null("../Infantry/GimbalYaw/GimbalPitch/Aimcamera")
	camera_viewport = SubViewport.new()
	camera_viewport.name = "RobotCameraOutput"
	camera_viewport.size = Vector2i(640, 360)
	camera_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	camera_viewport.world_3d = get_viewport().world_3d
	add_child(camera_viewport)
	output_camera = Camera3D.new()
	output_camera.name = "OutputCamera"
	camera_viewport.add_child(output_camera)
	output_camera.current = true
	if source_camera:
		output_camera.fov = source_camera.fov
		output_camera.global_transform = source_camera.global_transform


func _process(_delta: float) -> void:
	if source_camera and output_camera:
		output_camera.global_transform = source_camera.global_transform
		output_camera.fov = source_camera.fov
	frame_id += 1
	if not server.is_listening():
		return
	while server.is_connection_available():
		var new_peer := server.take_connection()
		if new_peer:
			pending_clients.append({"peer": new_peer, "started": Time.get_ticks_msec()})
	for i in range(pending_clients.size() - 1, -1, -1):
		var entry := pending_clients[i]
		var peer: StreamPeerTCP = entry.peer
		peer.poll()
		if peer.get_available_bytes() > 0:
			handle_request(peer, peer.get_utf8_string(peer.get_available_bytes()))
			pending_clients.remove_at(i)
		elif Time.get_ticks_msec() - int(entry.started) > 2000:
			pending_clients.remove_at(i)
	# Keep a strong reference while Windows flushes the TCP send buffer. Without
	# this, the peer may be freed directly after put_data(), leaving browser
	# fetch requests stuck even though very small health responses succeed.
	for i in range(sending_clients.size() - 1, -1, -1):
		var sent_entry := sending_clients[i]
		var sent_peer: StreamPeerTCP = sent_entry.peer
		sent_peer.poll()
		if sent_peer.get_status() == StreamPeerTCP.STATUS_NONE or Time.get_ticks_msec() - int(sent_entry.started) > 750:
			sent_peer.disconnect_from_host()
			sending_clients.remove_at(i)


func handle_request(peer: StreamPeerTCP, request: String) -> void:
	if request.begins_with("GET /frame.jpg"):
		serve_frame(peer)
	elif request.begins_with("GET /status"):
		serve_status(peer)
	elif request.begins_with("GET /health"):
		send_response(peer, "text/plain; charset=utf-8", "OK robot_gimbal 640x360".to_utf8_buffer())
	else:
		serve_index(peer)


func send_response(peer: StreamPeerTCP, content_type: String, data: PackedByteArray) -> void:
	var header := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store, no-cache, must-revalidate, max-age=0\r\nPragma: no-cache\r\nExpires: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [content_type, data.size()]
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(data)
	sending_clients.append({"peer": peer, "started": Time.get_ticks_msec()})


func serve_frame(peer: StreamPeerTCP) -> void:
	var image := camera_viewport.get_texture().get_image()
	var data := image.save_jpg_to_buffer(0.72)
	send_response(peer, "image/jpeg", data)


func serve_status(peer: StreamPeerTCP) -> void:
	var game := get_tree().current_scene
	var player := game.get_node_or_null("Infantry")
	var payload := {
		"time_left": game.get("time_left"),
		"red_score": game.get("red_score"),
		"blue_score": game.get("blue_score"),
		"health": player.get("health") if player else 0,
		"ammo": player.get("ammo") if player else 0,
		"barrel_heat": player.get("barrel_heat") if player else 0,
		"damage_multiplier": player.get("damage_multiplier") if player else 1.0,
		"energy_buff_seconds": game.get("buff_time_left"),
		"energy_progress": game.get("energy_progress"),
		"frame_id": frame_id,
		"camera": "robot_gimbal",
		"resolution": "640x360",
		"server_error": last_error,
		"position": {"x": player.global_position.x, "y": player.global_position.y, "z": player.global_position.z} if player else {}
	}
	send_response(peer, "application/json; charset=utf-8", JSON.stringify(payload).to_utf8_buffer())


func serve_index(peer: StreamPeerTCP) -> void:
	var html := """<!doctype html><html><head><meta charset='utf-8'><title>RM Robot Camera</title><style>body{margin:0;background:#071018;color:#dfefff;font:15px system-ui;text-align:center}.top{padding:12px;background:#0d2230;border-bottom:2px solid #20d9e8}.ok{color:#48ff9b}img{width:min(94vw,960px);aspect-ratio:16/9;object-fit:contain;margin-top:16px;border:2px solid #20d9e8;box-shadow:0 0 24px #20d9e855}pre{display:inline-block;text-align:left;min-width:420px;padding:12px;background:#0c1822;border-left:3px solid #ffbd28}</style></head><body><div class='top'><b>RM INFANTRY · ROBOT GIMBAL CAMERA</b>　<span class='ok'>● LIVE</span></div><img id='cameraImage' alt='waiting for robot camera'><br><pre id='statusBox'>LOADING FIRST CAMERA FRAME...</pre><script>const cameraImage=document.getElementById('cameraImage');const statusBox=document.getElementById('statusBox');let imageTimer=null;function loadNextFrame(){cameraImage.src='/frame.jpg?t='+Date.now()}cameraImage.onload=()=>{statusBox.dataset.image='ok';if(!statusBox.dataset.telemetry)statusBox.textContent='CONNECTED · CAMERA FRAME RECEIVED';clearTimeout(imageTimer);imageTimer=setTimeout(loadNextFrame,120)};cameraImage.onerror=()=>{statusBox.textContent='FRAME ERROR · retrying...';clearTimeout(imageTimer);imageTimer=setTimeout(loadNextFrame,800)};async function loadStatus(){try{const controller=new AbortController();setTimeout(()=>controller.abort(),1200);const x=await fetch('/status?t='+Date.now(),{cache:'no-store',signal:controller.signal}).then(r=>r.json());statusBox.dataset.telemetry='ok';statusBox.textContent='CONNECTED · FRAME '+x.frame_id+' · '+x.resolution+'\\nHP '+x.health+'   AMMO '+x.ammo+'   HEAT '+Math.round(x.barrel_heat)+'\\nBUFF x'+Number(x.damage_multiplier).toFixed(1)+' / '+Number(x.energy_buff_seconds).toFixed(1)+'s\\nPOSITION '+JSON.stringify(x.position)}catch(e){if(statusBox.dataset.image==='ok')statusBox.textContent='CONNECTED · CAMERA OK · telemetry retrying...'}}loadNextFrame();setInterval(loadStatus,1500);loadStatus();</script></body></html>"""
	send_response(peer, "text/html; charset=utf-8", html.to_utf8_buffer())


func _exit_tree() -> void:
	server.stop()
