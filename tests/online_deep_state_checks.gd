extends SceneTree
# Deep-hunt reproductions. Assert intended behavior; several fail on upstream v0.31.
# Run with a fresh XDG_DATA_HOME. These are not part of normal CI.
var checks = 0
var failures = 0
var time = 0.0
func _initialize(): run.call_deferred()
func verify(ok: bool, description: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(description)
func make_server():
 var server = GameServer.new()
 root.add_child(server)
 server.set_process(false)
 server.clock = func(): return time
 # Banning Rickroll avoids an unrelated initial-row start trigger.
 server.setup([{"name":"Host","bot":false},{"name":"Guest","bot":false}], "2025", 20, 91, ["Rickroll"], 0.25)
 server.engine.state.active_seat = 0
 return server
func connect_client(server, seat: int):
 var pair = LoopbackTransport.pair(false)
 server.attach(pair[0])
 var client = NetClient.new()
 root.add_child(client)
 client.set_process(false)
 client.connect_to(pair[1], seat, server.tokens[seat])
 pair[0].pump()
 pair[1].pump()
 return client
func dispose(server, clients: Array):
 server.running = false
 for client in clients:
  if client.transport != null: client.transport.close()
  client.free()
 server.free()
func reconnect_case(outage: float) -> bool:
 time = 0
 var server = make_server()
 var clients = [connect_client(server, 0), connect_client(server, 1)]
 await server.start()
 server._idle_tick()
 time = 100
 server._idle_tick()
 clients[0].transport.close()
 time += outage
 server._idle_tick()
 verify(not server._takeover(0), "control: outage is shorter than the 120-second disconnected takeover")
 clients.append(connect_client(server, 0))
 verify(server.available(0), "control: authenticated reconnect initially restores human control")
 server._idle_tick()
 var retained = server.available(0)
 print("Reconnect evidence: outage=%s, connected idle=100, available=%s, idle_bot=%s" % [outage, retained, server.idle_bot])
 dispose(server, clients)
 return retained
func restore_case(snapshot: Dictionary, uptime: float) -> Dictionary:
 time = uptime
 var server = GameServer.new()
 root.add_child(server)
 server.set_process(false)
 server.clock = func(): return time
 verify(server.restore(snapshot), "control: authoritative snapshot restores")
 var clients = [connect_client(server, 0), connect_client(server, 1)]
 verify(server.available(0), "control: restored active seat can act before the first tick")
 server._idle_tick()
 var result = {"available":server.available(0), "charged":server.turn_used, "idle":time - server.idle_at}
 print("Restore evidence: process uptime=%s, result=%s" % [uptime, result])
 dispose(server, clients)
 return result
func timer_checks():
 verify(await reconnect_case(40), "control: shorter reconnect remains playable")
 verify(await reconnect_case(85), "ON31-05: offline time must not trigger connected-idle takeover on reconnect")
 time = 0
 var original = make_server()
 await original.start()
 var snapshot = original.last_snapshot.duplicate(true)
 original.free()
 var fresh = restore_case(snapshot, 0)
 verify(fresh.available and fresh.charged == 0, "control: a fresh process does not charge time before restore")
 var old = restore_case(snapshot, 700)
 verify(old.available and old.charged == 0, "ON31-06: restoring in a long-running process must not spend the entire turn allowance")
func find_button(node: Node, title: String):
 for child in node.get_children():
  if child is Button and child.text == title: return child
  var found = find_button(child, title)
  if found != null: return found
 return null
func result_checks():
 time = 0
 var server = make_server()
 var session = OnlineSession.new()
 session.set_process(false)
 var pair = LoopbackTransport.pair(false)
 server.attach(pair[0])
 session.transport = pair[1]
 session.client.connect_to(pair[1], 0, server.tokens[0])
 pair[1].received.connect(session._message)
 pair[0].pump()
 pair[1].pump()
 await server.start()
 var host = server.engine.state.players[0]
 var guest = server.engine.state.players[1]
 var attack = (host.hand + host.deck).filter(func(c): return c.id == "Damage")[0]
 if attack not in host.hand: server.engine.move(attack, host.hand, "hand")
 guest.life = 1
 verify(server.engine.state.conservation_ok(), "control: lethal-attack fixture conserves physical cards")
 # Send the pre-lethal view, then pause polling to model the documented delayed final view.
 server.view_frames.clear()
 server._view(0)
 pair[1].pump()
 var table = load("res://scenes/table.tscn").instantiate()
 table.online_session = session
 table.add_child(session)
 session.room = {"code":"AB23CD", "started":true}
 root.add_child(table)
 verify(table.engine.state.players[0].deck.all(func(c): return c.id == "hidden"), "control: own deck order remains hidden during play")
 session.client.send_action("play", attack.uid)
 pair[0].pump()
 pair[1].pump()
 verify(server.engine.state.finished and server.engine.state.winner == host, "control: real authenticated lethal attack ends the game")
 var first = table.match_stats.seats[1].final_life
 verify(first == 0, "control: game_over carries the correct final life before the final view")
 # The Room sends this second message after its stats/storage/container shutdown awaits.
 session._message({"t":"over", "winner":0})
 var second = table.match_stats.seats[1].final_life
 print("Result evidence: authoritative life=%s, first final total=%s, after Room.over=%s" % [guest.life, first, second])
 verify(second == guest.life, "ON31-04: duplicate completion must preserve authoritative final totals")
 # Even a delivered, fully up-to-date final view never supplies the winner's deck identities.
 server.view_frames.clear()
 server._view(0)
 pair[1].pump()
 await process_frame
 var final_deck = table.final_deck()
 var masked = final_deck.filter(func(c): return c.id == "hidden").size()
 var deck_button = find_button(table, "View final deck")
 verify(table.engine.state.finished and deck_button != null, "control: completed online game offers the final-deck viewer")
 print("Final deck evidence: %d/%d cards are still hidden after the final view" % [masked, final_deck.size()])
 verify(masked == 0, "ON31-08: View final deck must identify the player's own cards after the game")
 deck_button.pressed.emit()
 verify(table.pending, "control: final-deck button opens the actual card viewer")
 table.answered.emit(null)
 pair[1].close()
 table.queue_free()
 server.queue_free()
 await process_frame
func run():
 root.get_node("Sfx").visual_effects = false
 root.get_node("Sfx").auto_end_turn = false
 await timer_checks()
 await result_checks()
 print("Online deep state: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
