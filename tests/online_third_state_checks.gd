extends SceneTree
# Third-pass reproductions: assert intended behavior on stock v0.31.
# Run with a fresh XDG_DATA_HOME; the restore case deliberately enables stats writes.
class CaptureLink extends LinkServer:
 var sent: Array = []
 func _send(message: Dictionary): sent.append(message.duplicate(true))
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
 time = 0
 var server = GameServer.new()
 root.add_child(server)
 server.set_process(false)
 server.clock = func(): return time
 server.setup([{"name":"Host","bot":false},{"name":"Guest","bot":false}], "2025", 20, 91, ["Rickroll"], 0.25)
 server.engine.state.active_seat = 0
 return server
func connect_session(server, seat: int) -> Dictionary:
 var session = OnlineSession.new()
 session.set_process(false)
 session.client.set_process(false)
 var pair = LoopbackTransport.pair(false)
 server.attach(pair[0])
 session.transport = pair[1]
 session.client.connect_to(pair[1], seat, server.tokens[seat])
 pair[1].received.connect(session._message)
 pair[0].pump()
 pair[1].pump()
 session.room = {"code":"AB23CD", "started":true, "started_at":123}
 return {"session":session, "pair":pair}
func open_table(connection):
 var table = load("res://scenes/table.tscn").instantiate()
 table.online_session = connection.session
 table.add_child(connection.session)
 root.add_child(table)
 return table
func labels(node: Node) -> Array:
 var result = []
 if node is Label: result.append(node.text)
 for child in node.get_children(): result.append_array(labels(child))
 return result
func choice_button(node: Node, uid: int):
 if node is Button and node.get_meta("uid", -1) == uid: return node
 for child in node.get_children():
  var found = choice_button(child, uid)
  if found != null: return found
 return null
func named_button(node: Node, prefix: String):
 if node is Button and node.text.begins_with(prefix): return node
 for child in node.get_children():
  var found = named_button(child, prefix)
  if found != null: return found
 return null
func stale_purchase():
 var server = make_server()
 server.bot_pace = 0.0
 await server.start()
 var e = server.engine
 var host = e.state.players[0]
 # A legal board with one affordable purchase and an empty hand. Move existing cards only.
 for card in host.hand.duplicate(): e.move(card, host.deck, "deck")
 host.hacking = 6
 e.state.center_deck.append_array(e.state.center_row.filter(func(c): return c != null))
 e.state.center_row.fill(null)
 var target = e.state.center_deck.filter(func(c): return c.id == "The Clarion Inn")[0]
 var row = [target] + e.state.center_deck.filter(func(c): return e.effective_cost(host, c) > 6).slice(0, 4)
 for i in row.size():
  e.state.center_deck.erase(row[i])
  e.state.center_row[i] = row[i]
 verify(row.size() == 5 and e.state.conservation_ok(), "control: stale-purchase fixture has a legal conserved board")
 var connection = connect_session(server, 0)
 var guest = connect_session(server, 1)
 var table = open_table(connection)
 var mirror = table.engine.state.center_row.filter(func(c): return c != null and c.uid == target.uid)[0]
 table.inspect_card(mirror, true)
 var buy = named_button(table.inspect_overlay, "Buy —")
 verify(buy != null and not buy.disabled, "control: ordinary card inspector offers an affordable Buy button")
 server._idle_tick()
 time = 180
 server._process(0)
 # The real inactivity policy finishes this turn while the inspector remains open.
 var until = Time.get_ticks_msec() + 5000
 while e.active().seat != 1 and Time.get_ticks_msec() < until:
  await process_frame
  server._process(0)
  connection.pair[1].pump()
  guest.pair[1].pump()
 verify(e.active().seat == 1 and target not in e.state.center_row, "control: idle bot bought the inspected card and ended the turn")
 await process_frame
 server._process(0)
 connection.pair[1].pump()
 guest.pair[1].pump()
 guest.session.client.send_action("end_turn")
 guest.pair[0].pump()
 await process_frame
 server._process(0)
 connection.pair[1].pump()
 guest.pair[1].pump()
 verify(e.active().seat == 0 and server.available(0) and table.available(), "control: the human has control again on the next turn")
 verify(is_instance_valid(table.inspect_overlay) and not buy.disabled, "control: the old Buy button remains enabled across both turn changes")
 # Press the original UI button, not a fabricated invalid network action.
 buy.pressed.emit()
 connection.pair[0].pump()
 connection.pair[1].pump()
 await process_frame
 server._process(0)
 connection.pair[1].pump()
 print("Stale purchase evidence: server available=%s, client available=%s, error=%s, dirty=%s" % [server.available(0), table.available(), table.notice_text, server.dirty])
 verify(server.available(0) and e.state.conservation_ok(), "control: rejected stale purchase leaves the authoritative game playable")
 verify(table.available(), "ON31-12: rejecting a stale inspector action must not disable every action for the rest of the turn")
 verify(table.notice_text == "illegal action", "control: the refused action's error reached the actual UI")
 connection.pair[1].close()
 var reconnected = LoopbackTransport.pair(false)
 server.attach(reconnected[0])
 connection.session.transport = reconnected[1]
 connection.session.client.connect_to(reconnected[1], 0, server.tokens[0])
 reconnected[1].received.connect(connection.session._message)
 reconnected[0].pump()
 reconnected[1].pump()
 verify(table.available(), "control: a real authenticated reconnect recovers the blocked client")
 reconnected[1].close()
 guest.pair[1].close()
 guest.session.free()
 table.queue_free()
 server.queue_free()
 await process_frame
func prompt_inspection():
 var server = make_server()
 await server.start()
 var e = server.engine
 var host = e.state.players[0]
 var guest = e.state.players[1]
 var exploit = e.state.all_cards().filter(func(c): return c.id == "Sticky Fingers")[0]
 var ice = e.state.all_cards().filter(func(c): return c.id == "The Clarion Inn")[0]
 e.gain_owner(exploit, host)
 e.move(exploit, host.hand, "hand")
 e.gain_owner(ice, guest)
 e.move(ice, guest.play_area, "play_area")
 ice.counters = 3
 verify(e.state.conservation_ok(), "control: target-choice fixture conserves all physical cards")
 var connection = connect_session(server, 0)
 var table = open_table(connection)
 var mirror = table.engine.permanents().filter(func(c): return c.uid == ice.uid)[0]
 table.inspect_card(mirror)
 var board_labels = labels(table.inspect_overlay)
 verify(board_labels.any(func(s): return s.begins_with("ICE: 3")), "control: inspecting the board shows the permanent's remaining ICE")
 table.close_inspect()
 connection.session.client.send_action("play", exploit.uid)
 connection.pair[0].pump()
 connection.pair[1].pump()
 verify(table.pending and server.pending.size() == 1, "control: authenticated AI Fingers play opens a real target prompt")
 var payload = server.pending.values()[0].data
 verify(payload.cards[0].uid == ice.uid and payload.cards[0].counters == 3, "control: prompt payload contains the correct live ICE count")
 var button = choice_button(table, ice.uid)
 verify(button != null, "control: the choice dialog offers the permanent")
 var click = InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_RIGHT
 click.pressed = true
 button.gui_input.emit(click)
 var prompt_labels = labels(table.inspect_overlay)
 print("Target inspection evidence: board has ICE=%s; prompt has ICE=%s" % [board_labels.any(func(s): return s.begins_with("ICE:")), prompt_labels.any(func(s): return s.begins_with("ICE:"))])
 verify(prompt_labels.any(func(s): return s.begins_with("ICE: 3")), "ON31-09: inspecting an online target must show its live ICE count")
 table.close_inspect()
 table.answered.emit([0])
 connection.pair[0].pump()
 connection.pair[1].pump()
 verify(ice.controller == 0 and e.state.conservation_ok(), "control: selecting that target resolves the real effect correctly")
 connection.pair[1].close()
 table.queue_free()
 server.queue_free()
 await process_frame
func connection_countdowns():
 var server = make_server()
 await server.start()
 var host = connect_session(server, 0)
 var guest = connect_session(server, 1)
 var table = open_table(guest)
 var received: Array = []
 guest.session.client.message_received.connect(func(message):
  if message.get("t") == "view": received.append(message))
 # Flush the initial dirty view on a new frame, as production polling would.
 await process_frame
 server._process(0)
 host.pair[1].pump()
 guest.pair[1].pump()
 verify(not server.dirty and received[-1].timers.any(func(t): return t.seat == 0 and t.kind == "turn"), "control: guest has the active human's normal turn countdown")
 received.clear()
 time = 7
 host.pair[1].close()
 await process_frame
 server._process(0)
 guest.pair[1].pump()
 verify(server.timer_state().any(func(t): return t.seat == 0 and t.kind == "disconnected"), "control: server knows the active player is disconnected")
 print("Disconnect evidence: guest views=%d, guest timer kind=%s" % [received.size(), table.countdowns[0].kind])
 verify(table.countdowns[0].kind == "disconnected", "ON31-10: remaining players must receive the disconnect countdown")
 # Isolate the missing publication from countdown rendering or serialization.
 server.dirty = true
 await process_frame
 server._process(0)
 guest.pair[1].pump()
 verify(table.countdowns[0].kind == "disconnected", "control: publishing a view correctly updates the guest's countdown")
 received.clear()
 time = 12
 await process_frame
 var replacement = connect_session(server, 0)
 server._process(0)
 guest.pair[1].pump()
 verify(not server.disconnected.has(0) and server.available(0), "control: returning player authenticated and can act")
 print("Reconnect evidence: guest views=%d, guest timer kind=%s" % [received.size(), table.countdowns[0].kind])
 verify(table.countdowns[0].kind == "turn", "ON31-10: reconnect must replace other players' disconnect countdown")
 replacement.pair[1].close()
 guest.pair[1].close()
 host.session.free()
 replacement.session.free()
 table.queue_free()
 server.queue_free()
 await process_frame
func failed_restore_result():
 var stats = load("res://scripts/ui/lifetime_stats.gd").new()
 stats.reset()
 var server = make_server()
 await server.start()
 var connection = connect_session(server, 0)
 var table = open_table(connection)
 table.lifetime_test_enabled = true
 verify(not server.engine.state.finished and not table.match_stats.finished, "control: recovery begins with an unfinished game")
 var link = CaptureLink.new()
 root.add_child(link)
 link.set_process(false)
 var incompatible = server.last_snapshot.duplicate(true)
 incompatible.version = "incompatible-test-version"
 link._receive({"t":"restore", "room":"AB23CD", "snapshot":incompatible})
 verify(link.sent.size() == 1 and link.sent[0].get("reason") == "restore_failed", "control: real LinkServer rejects an incompatible snapshot")
 # Room forwards this terminal message to already-connected clients.
 connection.pair[0].send(link.sent[0])
 connection.pair[1].pump()
 await process_frame
 var saved = load("res://scripts/ui/lifetime_stats.gd").new().data
 print("Restore failure evidence: online_over=%s, headline=%s, lifetime games=%d, wins=%d, losses=%d" % [table.online_over, table.result_headline(null), saved.games, saved.wins, saved.losses])
 verify(connection.session.status.contains("couldn't be resumed"), "control: the client recognizes the server-recovery error")
 verify(saved.games == 0, "ON31-11: a failed recovery must not record an unfinished game as a draw")
 connection.pair[1].close()
 table.queue_free()
 server.queue_free()
 link.queue_free()
 await process_frame
func run():
 root.get_node("Sfx").visual_effects = false
 root.get_node("Sfx").auto_end_turn = false
 await prompt_inspection()
 await connection_countdowns()
 await failed_restore_result()
 await stale_purchase()
 print("Online third state: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
