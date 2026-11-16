extends SceneTree
# Second online hunt: these assertions describe expected behavior and intentionally fail on v0.31.
var checks = 0
var failures = 0
class FakeAPI extends Node:
 func request(_method, _path, _body = {}):
  return {"status": 200, "data": {"rooms": []}}
func _initialize(): run.call_deferred()
func verify(ok: bool, description: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(description)
func button(node: Node, title: String):
 for child in node.get_children():
  if child is Button and child.text == title: return child
  var found = button(child, title)
  if found != null: return found
 return null
func player(name: String, bot: bool = false) -> Dictionary:
 return {"name": name, "hero": "", "bot": bot, "difficulty": 0, "connected": true}
func run():
 root.get_node("Sfx").visual_effects = false
 var screen = load("res://scripts/ui/online.gd").new()
 screen.api = FakeAPI.new()
 screen.add_child(screen.api)
 root.add_child(screen)
 var session = OnlineSession.new()
 screen.add_child(session)
 session.set_process(false)
 screen.session = session
 session.credential = {"server": "http://127.0.0.1", "code": "AB23CD", "token": "c".repeat(32), "seat": 2}
 OnlineAPI.remember(session.credential)
 session.room_changed.connect(screen.lobby)
 var state = {"t": "room", "code": "AB23CD", "host_seat": 0, "started": false, "public": true, "card_pool": "custom", "starting_life": 20, "bot_pace": 0.5, "seats": [player("Host"), player("Bot", true), player("Guest")]}
 session._message(state)
 verify(button(screen, "Submit deck") != null, "control: guest in seat 2 can submit a custom deck before removal")
 state = state.duplicate(true)
 state.seats.remove_at(1)
 session._message(state)
 verify(session.credential.seat == 1, "ON31-01: remaining guest's credential follows seat renumbering")
 verify(OnlineAPI.remembered().get("seat", -1) == 1, "ON31-01: remembered seat follows seat renumbering")
 verify(button(screen, "Submit deck") != null, "ON31-01: custom-deck lobby remains usable after a lower seat is removed")
 screen.queue_free()
 await process_frame
 print("Online hunt: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
