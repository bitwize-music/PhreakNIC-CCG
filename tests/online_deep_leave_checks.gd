extends SceneTree
# Client half of ON31-07. The paired Worker test produces the busy response used here.
var checks = 0
var failures = 0
class FakeAPI extends Node:
 func request(_method, _path, _body = {}): return {"status":200, "data":{"rooms":[]}}
func _initialize(): run.call_deferred()
func verify(ok: bool, description: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(description)
func run():
 root.get_node("Sfx").visual_effects = false
 var screen = load("res://scripts/ui/online.gd").new()
 screen.api = FakeAPI.new()
 screen.add_child(screen.api)
 root.add_child(screen)
 current_scene = screen
 var session = OnlineSession.new()
 screen.add_child(session)
 session.set_process(false)
 screen.session = session
 session.credential = {"server":"http://127.0.0.1", "code":"AB23CD", "token":"b".repeat(32), "seat":1}
 OnlineAPI.remember(session.credential)
 session.room = {"started":false, "host_seat":0}
 var pair = LoopbackTransport.pair(false)
 session.transport = pair[1]
 session.client.bind_transport(pair[1])
 pair[1].received.connect(session._message)
 var sent = []
 pair[0].received.connect(func(m):
  sent.append(m)
  pair[0].send({"t":"error", "reason":"busy"}))
 verify(not OnlineAPI.remembered().is_empty(), "control: guest has a saved reconnect token")
 screen.leave_lobby()
 pair[0].pump()
 pair[1].pump()
 verify(sent == [{"t":"lobby", "action":"leave"}], "control: actual Leave action reaches the room transport")
 verify(session.status == OnlineAPI.error_text(503, {"error":"busy"}), "control: refusal reaches the real session before leaving")
 for i in 4: await process_frame
 print("Leave evidence: remembered credential=%s, screen alive=%s" % [OnlineAPI.remembered(), is_instance_valid(screen)])
 verify(not OnlineAPI.remembered().is_empty(), "ON31-07: a refused Leave must preserve the guest's only reconnect token")
 if current_scene != null: current_scene.queue_free()
 pair[0].close()
 await process_frame
 print("Online deep leave: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
