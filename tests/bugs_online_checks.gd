extends SceneTree
# Known online bugs on the client side, written as checks of the CORRECT behaviour: every "Bxx" check fails while
# its bug is present and passes once it is fixed; "control:" checks pass today and show the harness is right.
# Worker-side checks are in cloudflare/online/test/known_bugs.test.js.
# Run with a temporary XDG_DATA_HOME: godot --headless --path . -s tests/bugs_online_checks.gd
# Real OnlineSession, WebSocketTransport, online.gd, table and GameServer code; only the room end is scripted.
class ErrorCounter extends Logger:
 var count = 0
 var lines: Array = []
 func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _traces: Array[ScriptBacktrace]) -> void:
  if error_type == ERROR_TYPE_WARNING: return
  count += 1
  if lines.size() < 500: lines.append(("%s:%d %s %s" % [file.get_file(), line, code, rationale]).strip_edges().left(240))
 func since(start: int) -> String: return " | ".join(lines.slice(start))
 func between(start: int, end: int) -> String: return " | ".join(lines.slice(start, end)) if start >= 0 and end >= start else "table never became ready"
class FakeAPI extends Node:
 # online.gd's REST boundary: nothing in this file may reach the network.
 func request(method, _path, _body = {}):
  if method == HTTPClient.METHOD_GET: return {"status": 200, "data": {"rooms": []}}
  return {"status": 503, "data": {"error": "maintenance"}}
class SeatServer extends Node:
 # Stands in for the Worker's /ws/room/CODE endpoint on localhost. `plan` scripts how each upgrade is answered,
 # the way the real Room answers it (the last entry repeats):
 # refuse = HTTP 401 {error:"token"} for an unknown or revoked token (index.js:159-161);
 # remove = accept, then close 1000 "removed" as the host's Remove seat does (index.js:224);
 # drop = accept, then lose the connection; keep = accept and stay open;
 # over = accept a room whose game has finished, then send {t:"over"}.
 var tcp = TCPServer.new()
 var port = 0
 var attempts = 0
 var plan: Array = ["refuse"]
 var waiting: Array = []
 var peers: Array = []
 func listen() -> bool:
  if tcp.listen(0, "127.0.0.1") != OK: return false
  port = tcp.get_local_port()
  return true
 func _process(_delta):
  while tcp.is_connection_available():
   var stream = tcp.take_connection()
   var action = plan[mini(attempts, plan.size() - 1)]
   attempts += 1
   if action == "refuse": waiting.append({"stream": stream, "request": PackedByteArray()})
   else:
    var peer = WebSocketPeer.new()
    if peer.accept_stream(stream) == OK: peers.append({"peer": peer, "action": action, "opened": -1})
  for item in waiting.duplicate():
   var stream: StreamPeerTCP = item.stream
   stream.poll()
   if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
    waiting.erase(item)
    continue
   var available = stream.get_available_bytes()
   if available > 0: item.request.append_array(stream.get_data(available)[1])
   if item.request.get_string_from_utf8().contains("\r\n\r\n"):
    var body = "{\"error\":\"token\"}"
    stream.put_data(("HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.length(), body]).to_utf8_buffer())
    stream.disconnect_from_host()
    waiting.erase(item)
  for item in peers.duplicate():
   var peer: WebSocketPeer = item.peer
   peer.poll()
   var state = peer.get_ready_state()
   if state == WebSocketPeer.STATE_CLOSED:
    peers.erase(item)
   elif state == WebSocketPeer.STATE_OPEN and item.opened < 0:
    item.opened = Engine.get_process_frames()
    peer.send_text(JSON.stringify({"t": "room", "code": "ABCD", "deck_roll": [], "banned": [], "seats": [{"name": "Host", "hero": "", "bot": false, "difficulty": 0, "connected": true, "deck": null}, {"name": "Guest", "hero": "", "bot": false, "difficulty": 0, "connected": true, "deck": null}], "host_seat": 0, "started": item.action == "over", "public": false, "card_pool": "2026", "starting_life": 0, "bot_pace": 0.5}))
    if item.action == "remove": peer.close(1000, "removed")
    elif item.action == "over": peer.send_text(JSON.stringify({"t": "over", "winner": 0}))
   elif state == WebSocketPeer.STATE_OPEN and item.action == "drop" and Engine.get_process_frames() - item.opened >= 5:
    peer.close(-1)
 func shutdown():
  for item in peers: item.peer.close(-1)
  for item in waiting: item.stream.disconnect_from_host()
  peers.clear()
  waiting.clear()
  tcp.stop()
class PoolRoom extends Node:
 # online_ui_checks.gd's FakeRoom with a chosen card set: a real GameServer behind a loopback room socket.
 var server: GameServer
 var socket
 var bridge
 var started = false
 var pool = "2026"
 var deck: Dictionary = {}
 var ready_ok = false
 func _ready():
  server = GameServer.new()
  add_child(server)
  ready_ok = server.setup([{"name": "Host", "bot": false}, {"name": "Bot", "bot": true}], pool, 20, 42, [], 0.5, deck)
 func connect_seat():
  var pair = LoopbackTransport.pair()
  socket = pair[1]
  socket.received.connect(receive)
  send_room.call_deferred()
  if started: authenticate.call_deferred()
  return pair[0]
 func send_room():
  socket.send({"t": "room", "code": "ABCD", "deck_roll": [], "banned": [], "seats": [{"name": "Host", "hero": "", "bot": false, "difficulty": 0, "connected": true, "deck": null}, {"name": "Bot", "hero": "", "bot": true, "difficulty": 1, "connected": true, "deck": null}], "host_seat": 0, "started": started, "public": false, "card_pool": pool, "starting_life": 20, "bot_pace": 0.5})
 func receive(data):
  if data.get("t") == "lobby" and data.get("action") == "start":
   started = true
   send_room()
   socket.send({"t": "server", "status": "restarting"})
   server.start()
   authenticate()
  elif data.get("t") in ["action", "answer"]: bridge.send(data)
 func authenticate():
  if bridge != null: bridge.close()
  var pair = LoopbackTransport.pair()
  bridge = pair[0]
  server.attach(pair[1])
  bridge.received.connect(func(data): socket.send(data))
  # The trusted room authenticates internally; the client socket never sends hello.
  bridge.send({"t": "hello", "seat": 0, "token": server.tokens[0], "version": server.version()})
  socket.send({"t": "server", "status": "ok"})
 func drain():
  server.running = false
  server.engine.finish(null)
  for i in 200:
   for id in server.pending.keys(): await server._fallback(id)
   if server.pending.is_empty() and server.driving.is_empty() and server.locks.is_empty(): return
   await get_tree().process_frame
 func _exit_tree():
  if bridge != null: bridge.close()
  if socket != null: socket.close()

const USER_FILES = ["user://settings.cfg", "user://savegame.json", "user://stats.json", "user://decks.json"]
const TOKEN = "0123456789abcdef0123456789abcdef"
var errors = ErrorCounter.new()
var checks = 0
var failures = 0
var user_backups = {}
func _initialize():
 for path in USER_FILES:
  user_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
 call_deferred("run")
func _finalize():
 for path in user_backups:
  if user_backups[path] == null:
   if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
  else:
   var file = FileAccess.open(path, FileAccess.WRITE)
   file.store_buffer(user_backups[path])
func verify(ok, message):
 checks += 1
 if not ok:
  failures += 1
  print("FAIL: ", message)
func frames(n = 5):
 for i in n: await process_frame
func until(predicate: Callable, limit: int = 600) -> bool:
 for i in limit:
  if predicate.call(): return true
  await process_frame
 return predicate.call()
func button(node, text):
 for child in node.get_children():
  if child is Button and child.text == text: return child
  var found = button(child, text)
  if found != null: return found
 return null
func new_online(factory: Callable) -> Control:
 var online = load("res://scripts/ui/online.gd").new()
 online.api = FakeAPI.new()
 online.add_child(online.api)
 online.session = OnlineSession.new()
 online.add_child(online.session)
 online.session.transport_factory = factory
 root.add_child(online)
 current_scene = online
 return online

func run():
 OS.add_logger(errors)
 root.get_node("Sfx").visual_effects = false
 root.get_node("Sfx").auto_end_turn = false
 await check_refused_socket()
 await check_removed_seat()
 await check_dropped_socket()
 await check_over_message()
 for pool in ["2026", "2026mog", "custom"]: await check_table_pool(pool)
 # Let paced bot coroutines of the freed game servers run out before quitting.
 await create_timer(1.5).timeout
 print("Online bug checks: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)

# ---- B03 and the client half of B02: a real OnlineSession and WebSocketTransport against SeatServer ----
func seat_server(plan: Array) -> SeatServer:
 var server = SeatServer.new()
 server.plan = plan
 root.add_child(server)
 if server.listen(): return server
 print("SKIP: TCP sockets are unavailable here; WebSocket checks skipped")
 server.queue_free()
 return null
func seat_session(server: SeatServer) -> OnlineSession:
 var session = OnlineSession.new()
 root.add_child(session)
 session.start({"server": "http://127.0.0.1:%d" % server.port, "code": "ABCD", "seat": 1, "token": TOKEN})
 return session
func run_clock(session: OnlineSession, server: SeatServer, limit: int):
 # Time passes on the session's own clock (_process delta), so each reconnect backoff elapses at once.
 for i in 3000:
  await process_frame
  if server.attempts >= limit: return
  if session.retry > 0: session._process(16.0)
 # Below the limit: let more time pass to show no further attempt comes.
 for i in 60:
  await process_frame
  if session.retry > 0: session._process(16.0)
func finish(session: OnlineSession, server: SeatServer):
 session.disconnect_game()
 session.queue_free()
 server.shutdown()
 server.queue_free()
 await frames(3)
 OnlineAPI.remember({})
func check_refused_socket():
 var server = seat_server(["refuse"])
 if server == null: return
 var session = seat_session(server)
 await until(func(): return server.attempts >= 1 and not session.transport.active)
 verify(session.transport.close_code == -1, "control: a refused upgrade (HTTP 401) reaches OnlineSession as close code -1")
 await run_clock(session, server, 30)
 # 30 attempts is about seven minutes of 15-second backoff; where exactly to give up is a design choice.
 verify(server.attempts < 30, "B03 a socket the server refuses again and again stops retrying within 30 attempts (made %d)" % server.attempts)
 verify(OnlineAPI.remembered().is_empty(), "B03 a seat the server keeps refusing is forgotten")
 await finish(session, server)
func check_removed_seat():
 # After Remove seat the token is gone, so every later reconnect is refused (index.js:224-225, 161).
 var server = seat_server(["remove", "refuse"])
 if server == null: return
 var session = seat_session(server)
 await until(func(): return server.attempts >= 1 and not session.transport.active)
 verify(session.transport.close_code == 1000 and session.transport.close_reason == "removed", "control: Remove seat's close reaches OnlineSession as code 1000 'removed'")
 await run_clock(session, server, 30)
 verify(server.attempts < 30, "B03 a seat closed with 1000 'removed' by the host's Remove seat does not reconnect forever (made %d attempts)" % server.attempts)
 await finish(session, server)
func check_dropped_socket():
 var server = seat_server(["drop", "keep"])
 if server == null: return
 var session = seat_session(server)
 await run_clock(session, server, 2)
 await until(func(): return session.status == "Connected" and session.transport.active)
 verify(server.attempts == 2 and session.status == "Connected" and not session.stopped, "control: after one dropped connection OnlineSession reconnects and stays connected")
 await finish(session, server)
func check_over_message():
 # B02 is on the Worker: a reconnect to a finished room never gets `over`. This shows the client side is ready.
 var server = seat_server(["over"])
 if server == null: return
 var session = seat_session(server)
 var finished = []
 session.finished.connect(func(winner): finished.append(winner))
 await until(func(): return not finished.is_empty())
 verify(finished == [0] and OnlineAPI.remembered().is_empty(), "control: an over message after reconnecting finishes OnlineSession and forgets the seat")
 await finish(session, server)

# ---- B05: online games in other card sets open the table in the wrong set ----
func check_table_pool(pool: String):
 var db = root.get_node("CardDB")
 var room = PoolRoom.new()
 room.pool = pool
 if pool == "custom": room.deck = JSON.parse_string(FileAccess.get_file_as_string("res://data/starter_decks.json"))[0]
 root.add_child(room)
 if not room.ready_ok:
  verify(false, "setup: GameServer refused the %s game: %s" % [pool, room.server.setup_error])
  room.queue_free()
  return
 var online = new_online(room.connect_seat)
 await frames()
 online.enter({"server": "http://127.0.0.1:9", "code": "ABCD", "seat": 0, "token": TOKEN})
 await frames()
 # Observe the table from entering the tree until _ready returns. That stretch is synchronous client code
 # (table._ready -> setup_online), so errors from the in-process GameServer can't land in it. CardDB is read at
 # ready because the next view re-selects the game's set (net_view.gd:66) after setup_online already ran.
 var pool_at_ready = [""]
 var errors_at = [-1, -1]
 var catch_table = func(node):
  if node.get_script() != null and node.get_script().resource_path == "res://scripts/ui/table.gd":
   errors_at[0] = errors.count
   var at_ready = func():
    pool_at_ready[0] = db.selected_pool
    errors_at[1] = errors.count
   node.ready.connect(at_ready, CONNECT_ONE_SHOT)
 root.child_entered_tree.connect(catch_table)
 room.receive({"t": "lobby", "action": "start"})
 var opened = await until(func(): return is_instance_valid(current_scene) and current_scene != online and current_scene.get("online_session") != null)
 root.child_entered_tree.disconnect(catch_table)
 await frames(5)
 if not opened:
  verify(false, "setup: the online %s table never opened" % pool)
  online.queue_free()
  await room.drain()
  room.queue_free()
  return
 var table = current_scene
 var launch_errors = errors_at[1] - errors_at[0] if errors_at[1] >= 0 else -1
 var problems = errors.between(errors_at[0], errors_at[1])
 var redrawn = [false]
 table.auto_view_received.connect(func(): redrawn[0] = true)
 room.server.dirty = true
 await until(func(): return redrawn[0], 120)
 if pool == "2026":
  verify(pool_at_ready[0] == pool and launch_errors == 0 and redrawn[0], "control: an online 2026 game opens the table on its card set, without engine errors, following new views (CardDB %s, %d errors: %s)" % [pool_at_ready[0], launch_errors, problems])
 else:
  verify(pool_at_ready[0] == pool, "B05 an online %s game opens the table with CardDB on that card set (CardDB was on %s)" % [pool, pool_at_ready[0]])
  verify(launch_errors == 0, "B05 opening the online %s table raises no engine errors (%d: %s)" % [pool, launch_errors, problems])
  verify(redrawn[0], "B05 the online %s table still redraws when a new view arrives" % pool)
 table.queue_free()
 await frames(3)
 await room.drain()
 room.queue_free()
 await frames(3)
 OnlineAPI.remember({})
