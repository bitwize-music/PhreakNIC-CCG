extends SceneTree
var checks = 0
var failures = 0
func _initialize(): run.call_deferred()
func verify(ok: bool, description: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(description)
func move_card(engine, card, player, zone: String):
 engine.gain_owner(card, player)
 engine.move(card, player.get(zone), zone)
func scenario(poll_server: bool) -> Dictionary:
 var server = GameServer.new()
 root.add_child(server)
 server.set_process(false)
 server.clock = func(): return 0.0
 server.setup([{"name":"Host","bot":false},{"name":"Bot","bot":true,"difficulty":1},{"name":"Guest","bot":false}], "2026", 100, 91, [], 0.25)
 var pair = LoopbackTransport.pair(false)
 server.attach(pair[0])
 var client = NetClient.new()
 root.add_child(client)
 client.connect_to(pair[1], 0, server.tokens[0])
 pair[0].pump()
 pair[1].pump()
 await server.start()
 await server.engine.start_turn(0)
 var engine = server.engine
 var host = engine.state.players[0]
 var bot = engine.state.players[1]
 for card in bot.hand.duplicate(): engine.move(card, bot.deck, "deck")
 var cover = engine.state.all_cards().filter(func(c): return c.id == "TOCTOU")[0]
 move_card(engine, cover, bot, "hand")
 for card in bot.deck.filter(func(c): return c.id == "Hacking").slice(0, 3): engine.move(card, bot.hand, "hand")
 var attack = engine.state.all_cards().filter(func(c): return c.id == "Damage" and c.owner == 0)[0]
 move_card(engine, attack, host, "hand")
 # A legal row the starter deck cannot buy or afford to reserve this turn.
 # Move existing cards only, retaining card conservation.
 engine.state.center_deck.append_array(engine.state.center_row.filter(func(c): return c != null))
 engine.state.center_row.fill(null)
 var expensive = engine.state.center_deck.filter(func(c): return engine.effective_cost(bot, c) > 5)
 for i in 5:
  engine.state.center_deck.erase(expensive[i])
  engine.state.center_row[i] = expensive[i]
 verify(engine.state.conservation_ok(), "control: reaction fixture conserves all physical cards")
 bot.life = 1
 var plays = []
 var endings = []
 engine.card_played.connect(func(p, _card):
  if p == bot: plays.append(Time.get_ticks_msec()))
 engine.turn_ended.connect(func(p):
  if p == bot: endings.append(true))
 server.set_process(poll_server)
 client.send_action("play", attack.uid)
 pair[0].pump()
 var began = Time.get_ticks_msec()
 while Time.get_ticks_msec() - began < 5000:
  await process_frame
  if (engine.reaction_depth == 0 and not engine.busy) or endings.size() >= 3: break
 var paced = true
 for i in range(1, plays.size()):
  if plays[i] - plays[i-1] < 200: paced = false
 var result = {"covered": cover in engine.state.removed, "returned": engine.reaction_depth == 0 and engine.active() == host, "endings": endings.size(), "played": plays.size(), "paced": paced, "conserved": engine.state.conservation_ok()}
 print("Reaction evidence (server polling=%s): %s; play timestamps=%s" % [str(poll_server), str(result), str(plays)])
 server.running = false
 server.set_process(false)
 engine.finish(null)
 await create_timer(0.35).timeout
 client.queue_free()
 server.queue_free()
 await process_frame
 return result
func run():
 var control = await scenario(false)
 verify(control.covered and control.returned and control.endings == 1, "control: the same reaction with only its own bot driver completes normally")
 verify(control.paced and control.played == 3 and control.conserved, "control: one driver plays the three-card hand once, at the selected pace")
 var actual = await scenario(true)
 verify(actual.covered and actual.conserved, "control: live-server scenario uses TOCTOU and conserves physical cards")
 # A correct shared guard also appears in server.driving. Assert the gameplay outcome instead.
 verify(actual.played == 3, "ON31-03: the reaction must play only its original three-card hand")
 verify(actual.endings == 1, "ON31-03: a single reaction must end only once, without drawing and replaying extra hands")
 verify(actual.returned, "ON31-03: reaction returns to the interrupted player")
 verify(actual.paced, "ON31-03: bot actions respect the selected 250 ms pace")
 print("Online reaction hunt: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
