extends SceneTree
## Known engine and card bugs, verified on v0.27/v0.28. Every "Bxx" check asserts the
## CORRECT behaviour, so it fails until that bug is fixed. "control:" checks run the same
## harness where the bug does not apply and must pass. Situations are set up through real
## engine calls (play_card, buy_card, activate, end_turn) from reachable states; cards are
## taken from the Center Deck as if bought or drawn earlier.
class ErrorCounter extends Logger:
	var count = 0
	func _log_error(_f: String, _file: String, _line: int, _code: String, _rationale: String, _notify: bool, _type: int, _traces: Array[ScriptBacktrace]) -> void: count += 1
class Scripted extends Decider:
	var yes: bool = true
	var want: Array = []
	func confirm(_player, _prompt: String) -> bool: return yes
	func choose_option(_player, _prompt: String, _options: Array[String]) -> int: return 0
	func choose_cards(_player, _prompt: String, cards: Array, min_n: int, _max_n: int) -> Array:
		for id in want:
			for c in cards:
				if c.id == id: return [c]
		return cards.slice(0, min_n)
const SEED = 991
var errors = ErrorCounter.new()
var checks = 0
var failures = 0
var e
func _initialize(): call_deferred("run")
func verify(ok, message):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func run():
	OS.add_logger(errors)
	await b01_mog_printings()
	await b04_nested_reactions()
	await b08_rookie_numbers()
	await b09_stolen_attachments()
	await b23_toctou_in_simultaneous_loss()
	await b24_stolen_grass()
	await b30_jousterl()
	await b31_free_buy()
	await b32_what_is_truth()
	await b33_egg_in_your_soup()
	await b34_reshuffle_signals()
	if e != null:
		root.remove_child(e)
		e.free()
	verify(errors.count == 0, "control: no script errors (%d)" % errors.count)
	print("Engine bug checks: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------- harness
func fixture(pool: String, active: int, levels: Array = [2, 2], deck: Dictionary = {}):
	if e != null:
		root.remove_child(e)
		e.free()
	e = GameEngine.new()
	root.add_child(e)
	var deciders: Array = []
	for i in levels.size(): deciders.append(Scripted.new())
	# Starting life 50 is an ordinary game setting; scenarios lower it where they need to.
	if not e.setup(levels, SEED, deciders, pool, 50, [], deck): print("harness: setup failed for ", pool)
	clear_rickrolls()
	await e.start_turn(active)
func player(seat: int): return e.state.players[seat]
func dec(seat: int): return e.deciders[seat]
## A forced Rickroll buy at the start of a turn would add noise: keep Rickrolls out of the row.
func clear_rickrolls():
	for attempt in 10:
		var roll = null
		for c in e.state.center_row:
			if c != null and CustomDeck.rules_id(c.id) == "Rickroll": roll = c
		if roll == null: return
		e.detach(roll)
		e.state.center_deck.push_front(roll)
## A card from the Center Deck, as if bought (zone discard) or bought and drawn (zone hand).
func card(id: String, zone: String = "hand", seat: int = 0):
	for c in e.state.center_deck + e.state.center_row:
		if c != null and c.id == id:
			e.gain_owner(c, player(seat))
			e.move(c, player(seat).get(zone), zone)
			clear_rickrolls()
			return c
	print("harness: no card ", id)
	return null
## Put a Center Deck card into a Center Row slot (the row is random, so any card can be there).
func to_row(id: String, slot: int = 0):
	for c in e.state.center_row:
		if c != null and c.id == id: return c
	for c in e.state.center_deck:
		if c.id == id:
			e.state.center_deck.erase(c)
			var displaced = e.state.center_row[slot]
			e.state.center_row[slot] = c
			if displaced != null: e.state.center_deck.push_front(displaced)
			return c
	print("harness: no row card ", id)
	return null
## Make a Center Deck card the next one dealt into the row.
func next_refill(id: String):
	for c in e.state.center_deck:
		if c.id == id:
			e.state.center_deck.erase(c)
			e.state.center_deck.push_back(c)
			return c
	return null
## A starter card (Hacking/Damage) from hand, or drawn from the deck.
func starter(p, id: String):
	for c in p.hand:
		if c.id == id: return c
	for c in p.deck:
		if c.id == id:
			e.move(c, p.hand, "hand")
			return c
	return null
## Earn Hacking by playing Hacking cards.
func hack(p, n: int):
	var target = p.hacking + n
	for i in 10:
		if p.hacking >= target: return
		var h = starter(p, "Hacking")
		if h == null: return
		await e.play_card(p, h)
func frames(n: int):
	for i in n: await process_frame
## Let any reaction turn still waiting for a human finish, so the engine can be freed.
func settle():
	for i in 20:
		if e.reaction_depth == 0: break
		var p = e.active()
		if not p.is_bot and e.is_turn(p): e.end_turn(p)
		await process_frame
	await frames(2)
func shipped_deck(stem: String) -> Dictionary:
	var file = JSON.parse_string(FileAccess.get_file_as_string("res://decks/custom/%s.phreakdeck.json" % stem))
	return CustomDeck.decode(file.code)

# ---------------------------------------------------------------- B01
# Mog printings with IDENTICAL rules text lose effects that the engine checks by printed name.
func b01_mog_printings():
	var saga = shipped_deck("100-expansion-saga")
	saga.cards["heartsh8ped"] = 1   # partner card for the Mogmart check
	saga.cards["Bribery"] = 1       # a permanent that deals damage, for the CTF Bangers check
	verify(CustomDeck.validate(saga).is_empty(), "control: deck 100-expansion-saga plus heartsh8ped and Bribery is a valid custom deck")
	var runs = [
		{"pool": "2026", "suffix": "", "deck": {}, "label": "control: %s (2026)", "names": ["Grass", "CTF Bangers", "Walmart Parking Lot", "pTFS", "Makeshift Lectern"]},
		{"pool": "2026mog", "suffix": "", "deck": {}, "label": "B01 %s (2026mog)", "names": ["Touch Mog", "Mog's CTF Bangers", "Mogmart Parking Lot", "pTFMOG", "Mog's Makeshift Lectern"]},
		{"pool": "custom", "suffix": "@mog", "deck": saga, "label": "B01 %s (custom game, @mog printing)", "names": ["Touch Mog", "Mog's CTF Bangers", "Mogmart Parking Lot", "pTFMOG", "Mog's Makeshift Lectern"]},
	]
	for setup_case in runs:
		var sfx = setup_case.suffix
		# Grass: "Players may not buy cards."
		await fixture(setup_case.pool, 0, [2, 2], setup_case.deck)
		var p = player(0)
		await e.play_card(p, card("Touch Grass" + sfx))
		var target = null
		for c in e.state.center_row:
			if c != null and (target == null or e.effective_cost(p, c) < e.effective_cost(p, target)): target = c
		var price = e.effective_cost(p, target)
		await hack(p, price)
		var affordable = p.hacking >= price
		var bought = await e.buy_card(p, target)
		verify(affordable and not bought and target in e.state.center_row, setup_case.label % ("%s blocks buying" % setup_case.names[0]))
		# CTF Bangers: "Whenever a permanent you control would deal damage, it deals 1 extra damage."
		await fixture(setup_case.pool, 0, [2, 2], setup_case.deck)
		p = player(0)
		var q = player(1)
		await e.play_card(p, card("CTF Bangers" + sfx))
		var bribery = card("Bribery")
		await e.play_card(p, bribery)
		await hack(p, 2)
		var before = q.life
		var used = await e.activate(p, bribery, 0)
		verify(used and before - q.life == 2, setup_case.label % ("%s adds 1 to Bribery's 1 damage" % setup_case.names[1]))
		# Walmart Parking Lot: "If you have played a card named heartsh8ped this turn, you may buy this card for free."
		await fixture(setup_case.pool, 0, [2, 2], setup_case.deck)
		p = player(0)
		var lot = to_row("Walmart Parking Lot" + sfx, 0)
		await e.play_card(p, card("heartsh8ped"))
		bought = await e.buy_card(p, lot)
		verify(bought and lot in p.discard, setup_case.label % ("%s is free after heartsh8ped" % setup_case.names[2]))
		# pTFS: "You may buy pTFS Heros for free."
		await fixture(setup_case.pool, 0, [2, 2], setup_case.deck)
		p = player(0)
		await e.play_card(p, card("pTFS" + sfx))
		var hero = to_row("Venaul", 0)
		bought = await e.buy_card(p, hero)
		verify(bought and hero not in e.state.center_row, setup_case.label % ("%s makes a pTFS Hero (Venaul) free" % setup_case.names[3]))
		# Makeshift Lectern: "On your turn, hero cards cost 1 less."
		await fixture(setup_case.pool, 0, [2, 2], setup_case.deck)
		p = player(0)
		await e.play_card(p, card("Makeshift Lectern" + sfx))
		hero = to_row("Venaul", 0)
		await hack(p, 2)
		bought = await e.buy_card(p, hero)
		verify(bought and hero not in e.state.center_row, setup_case.label % ("%s lets 2 Hacking buy a 3-cost Hero" % setup_case.names[4]))

# ---------------------------------------------------------------- B04
# TOCTOU: "pause the current player's turn, and take an extra turn immediately. After the
# extra turn, return play to the paused turn." A human's extra turn lasts until they end it.
func b04_nested_reactions():
	var chaos = shipped_deck("082-max-chaos")   # 3 TOCTOU
	# Control: a single human TOCTOU turn.
	await fixture("custom", 1, [-1, 2], chaos)
	var human = player(0)
	var bot = player(1)
	human.life = 1
	card("TOCTOU", "hand", 0)
	e.play_card(bot, starter(bot, "Damage"))   # paused while the human takes the TOCTOU turn
	await frames(3)
	verify(e.active() == human and e.reaction_depth == 1 and e.is_turn(human), "control: a human's TOCTOU turn lasts until the human ends it")
	e.end_turn(human)
	await frames(3)
	verify(e.active() == bot and e.reaction_depth == 0 and human.alive, "control: ending the human's TOCTOU turn returns play to the paused turn")
	await settle()
	# H1: the human's TOCTOU turn kills a bot that takes its own TOCTOU turn.
	await fixture("custom", 1, [-1, 2, 2], chaos)
	human = player(0)
	bot = player(1)
	var other = player(2)
	human.life = 1
	other.life = 1
	card("TOCTOU", "hand", 0)
	var other_toctou = card("TOCTOU", "hand", 2)
	e.turn_driver = func(p): await e.end_turn(p)   # bots end their TOCTOU turn at once
	e.play_card(bot, starter(bot, "Damage"))
	await frames(3)
	e.play_card(human, starter(human, "Damage"))
	await frames(3)
	verify(other_toctou in e.state.removed, "control: the bot took a TOCTOU turn inside the human's TOCTOU turn")
	verify(e.active() == human and e.reaction_depth == 1 and e.is_turn(human), "B04 human's TOCTOU turn continues after a nested bot TOCTOU turn ends")
	await settle()
	# H1b: two humans (online); the inner human ends their TOCTOU turn.
	await fixture("custom", 2, [-1, -1, 2], chaos)
	var outer = player(0)
	var inner = player(1)
	bot = player(2)
	outer.life = 1
	inner.life = 1
	card("TOCTOU", "hand", 0)
	card("TOCTOU", "hand", 1)
	e.play_card(bot, starter(bot, "Damage"))
	await frames(3)
	e.play_card(outer, starter(outer, "Damage"))
	await frames(3)
	verify(e.active() == inner and e.reaction_depth == 2, "control: a second human's TOCTOU turn starts inside the first")
	e.end_turn(inner)
	await frames(3)
	verify(e.active() == outer and e.reaction_depth == 1 and e.is_turn(outer), "B04 outer human's TOCTOU turn continues after a nested human TOCTOU turn ends")
	await settle()

# ---------------------------------------------------------------- B08
# Rookie Numbers: "If any player's discard pile contains a card with "Mog" in the name, that
# player loses 2 life." One effect hits every such player at once, like r0nk; Ruling 7: if
# every remaining player is eliminated at the same time, the game is a draw.
func b08_rookie_numbers():
	for seat in [0, 1]:
		await fixture("2026", seat)
		card("mog", "discard", 0)
		card("Mogs Pancake Breakfast", "discard", 1)
		var caster = player(seat)
		var other = player(1 - seat)
		var rookie = card("Rookie Numbers", "hand", seat)
		caster.life = 2   # loses 2
		other.life = 4    # takes the 2 {D}, then loses 2
		await e.play_card(caster, rookie)
		verify(e.state.finished and e.state.winner == null, "B08 Rookie Numbers dropping both players to 0 is a draw (seat %d casts)" % seat)
	await fixture("2026", 0)
	player(0).life = 1
	player(1).life = 1
	await e.play_card(player(0), card("r0nk"))
	verify(e.state.finished and e.state.winner == null, "control: r0nk dropping both players to 0 is a draw")

# ---------------------------------------------------------------- B09
# Cards that come off a stolen pTFS / The Book into the new controller's hand or deck are
# theirs: played or discarded, they go to that player's discard pile.
func b09_stolen_attachments():
	for steal in [false, true]:
		await fixture("2026", 0)
		var p0 = player(0)
		var p1 = player(1)
		var org = card("pTFS")
		await e.play_card(p0, org)
		var hero = to_row("Altk3y", 0)
		await hack(p0, 3)
		await e.buy_card(p0, hero)   # "Store bought hero on pTFS?" yes
		var holder = p0
		if steal:
			var fingers = card("Sticky Fingers", "hand", 1)
			await e.end_turn(p0)
			dec(1).want = ["pTFS"]
			await e.play_card(p1, fingers)
			await e.end_turn(p1)
			holder = p1
		else:
			await e.end_turn(p0)
		await e.end_turn(e.active())   # pTFS's controller starts a turn: its heroes go to their hand
		var in_hand = hero in holder.hand
		await e.play_card(holder, hero)
		if steal: verify(in_hand and hero in p1.discard, "B09 hero from a stolen pTFS goes to the new controller's discard after they play it")
		else: verify(in_hand and hero in p0.discard, "control: hero from your own pTFS goes to your discard after you play it")
	for steal in [false, true]:
		await fixture("2026", 0)
		var p0 = player(0)
		var p1 = player(1)
		await e.play_card(p0, card("The Book"))
		await e.end_turn(p0)
		var titor = card("John Titor", "hand", 0)   # drawn into seat 0's new hand
		dec(0).want = ["John Titor"]
		dec(0).yes = not steal   # with a steal coming, seat 0 keeps John Titor attached
		await e.end_turn(p1)   # seat 0: The Book attaches John Titor and plays it
		var holder = p0
		if steal:
			var fingers = card("Sticky Fingers", "hand", 1)
			await e.end_turn(p0)
			dec(1).want = ["The Book"]
			await e.play_card(p1, fingers)
			dec(1).want = []
			await e.end_turn(p1)
			await e.end_turn(p0)   # seat 1: the stolen Book plays John Titor; seat 1 shuffles it into its deck
			holder = p1
		var shuffled = titor in holder.deck
		while titor in holder.deck: e.draw(holder, 1)
		dec(holder.seat).yes = false
		await e.play_card(holder, titor)
		if steal: verify(shuffled and titor in p1.discard, "B09 John Titor shuffled into the new controller's deck by a stolen The Book stays theirs")
		else: verify(shuffled and titor in p0.discard, "control: John Titor shuffled in by your own The Book stays yours")

# ---------------------------------------------------------------- B23
# "A player at 0 life is out. Last player alive wins." Seat 0 dies during seat 1's TOCTOU
# turn, not at the same time as anyone else, so seat 1 wins then and there.
func b23_toctou_in_simultaneous_loss():
	for after in ["r0nk", "Attack"]:
		await fixture("2026", 0)
		var p0 = player(0)
		var p1 = player(1)
		p0.life = 2 if after == "r0nk" else 1
		p1.life = 1
		card("TOCTOU", "hand", 1)
		var opener = card("r0nk") if after == "r0nk" else starter(p0, "Damage")
		var hit = starter(p1, "Damage")
		var seen = {}
		e.turn_driver = func(p):
			await e.play_card(p, hit)   # kills seat 0
			seen.over = e.state.finished
			seen.winner = e.state.winner
			if not e.state.finished: await e.end_turn(p)
		await e.play_card(p0, opener)
		var ok = seen.get("over", false) and seen.get("winner") == p1
		if after == "r0nk": verify(ok, "B23 game ends when the TOCTOU player kills the last opponent during a TOCTOU turn that interrupted r0nk")
		else: verify(ok, "control: game ends when the TOCTOU player kills the last opponent during a TOCTOU turn after an Attack")
	var chaos = shipped_deck("082-max-chaos")   # 3 TOCTOU, 3 r0nk
	await fixture("custom", 0, [2, 2], chaos)
	var caster = player(0)
	var survivor = player(1)
	caster.life = 2
	survivor.life = 1
	card("TOCTOU", "hand", 1)
	var first = card("r0nk", "hand", 0)
	var second = card("r0nk", "hand", 1)
	var kill = starter(survivor, "Damage")
	e.turn_driver = func(p):
		await e.play_card(p, kill)     # seat 0 is out: seat 1 is the last player alive
		await e.play_card(p, second)   # a game that is over refuses this; today it kills seat 1
		if p.alive and not e.state.finished: await e.end_turn(p)
	await e.play_card(caster, first)
	verify(e.state.finished and e.state.winner == survivor, "B23 seat 1 wins, not a draw, after outliving seat 0 and then playing its own r0nk (deck 082)")

# ---------------------------------------------------------------- B24
# Grass: "At the end of your next turn, remove this card from the game." Whichever turn that
# means after a steal, Grass is gone once the stealer's next turn has ended.
func b24_stolen_grass():
	# Control: no steal.
	await fixture("2026", 0)
	var grass = card("Touch Grass")
	await e.play_card(player(0), grass)
	await e.end_turn(player(0))
	await e.end_turn(player(1))
	var survived_first = e.in_play("Grass")
	await e.end_turn(player(0))
	verify(survived_first and grass in e.state.removed, "control: Grass is removed at the end of its controller's next turn")
	for extra in [false, true]:
		await fixture("2026", 0)
		var p0 = player(0)
		var p1 = player(1)
		if extra:
			var tt = card("Time Travel")
			await e.play_card(p0, tt)
			await e.activate(p0, tt)   # extra turn after this one
			await e.end_turn(p0)
		grass = card("Touch Grass")
		await e.play_card(p0, grass)
		var fingers = card("Sticky Fingers", "hand", 1)
		await e.end_turn(p0)
		dec(1).want = ["Touch Grass"]
		await e.play_card(p1, fingers)
		var stolen = grass in p1.play_area
		await e.end_turn(p1)   # the steal turn
		await e.end_turn(p0)
		await e.end_turn(p1)   # the stealer's next turn
		if extra: verify(stolen and not e.in_play("Grass"), "B24 Grass stolen after its owner's Time Travel turn is gone by the end of the stealer's next turn")
		else: verify(stolen and not e.in_play("Grass"), "control: stolen Grass (no extra turns) is gone by the end of the stealer's next turn")

# ---------------------------------------------------------------- B30
# JousterL: "you may put a card from your discard pile on top of your deck." The bought
# JousterL is already in the discard pile. (G4nd4lf says "another card".)
func b30_jousterl():
	for id in ["JousterL", "G4nd4lf"]:
		await fixture("2026", 0)
		var p = player(0)
		await hack(p, int(e.db().get_card(id).cost))   # the Hacking cards played are in the discard pile too
		var bought = to_row(id, 0)
		dec(0).want = [id]
		await e.buy_card(p, bought)
		var on_top = not p.deck.is_empty() and p.deck.back() == bought
		if id == "JousterL": verify(on_top, "B30 JousterL can put itself on top of the deck")
		else: verify(not on_top and bought in p.discard, "control: G4nd4lf ('another card') can't put itself on top of the deck")

# ---------------------------------------------------------------- B31
# Clarion Inn Staff: "You may buy a card with "Clarion" in its name for free this turn."
# Assumption: the fix asks Decider.confirm whether to use the free buy, like other "may" effects.
func b31_free_buy():
	await fixture("2026", 0)
	var p = player(0)
	var staff = card("Clarion Inn Staff")
	to_row("The Clarion Inn", 0)
	await e.play_card(p, staff)
	var inn = e.state.center_row[0]
	var bought = await e.buy_card(p, inn)
	verify(bought and inn in p.discard and p.hacking == 1, "control: Clarion Inn Staff makes The Clarion Inn free")
	await fixture("2026", 0)
	p = player(0)
	staff = card("Clarion Inn Staff")
	var breakfast = to_row("Clarion Inn Breakfast", 0)
	next_refill("The Clarion Inn")   # unseen until Breakfast leaves the row
	await e.play_card(p, staff)
	await hack(p, 1)                 # 2 Hacking: enough to pay for Breakfast
	dec(0).yes = false               # pay for Breakfast and keep the free buy
	await e.buy_card(p, breakfast)
	dec(0).yes = true
	inn = e.state.center_row[0]
	bought = false
	if inn != null and inn.id == "The Clarion Inn": bought = await e.buy_card(p, inn)
	verify(breakfast in p.discard and bought, "B31 a player who pays for Clarion Inn Breakfast keeps Clarion Inn Staff's free buy for The Clarion Inn")

# ---------------------------------------------------------------- B32
# Walmart's free buy is for "this card"; What is Truth? has every name but not Walmart's text.
func b32_what_is_truth():
	for pool in ["2026", "2026mog"]:
		await fixture(pool, 0)
		var p = player(0)
		var truth = to_row("What is Truth", 0)
		await e.play_card(p, card("heartsh8ped"))   # +1 Hacking
		await hack(p, 1)
		var bought = await e.buy_card(p, truth)
		verify(bought and p.hacking == 0, "B32 %s still costs 2 after heartsh8ped (%s)" % [e.db().get_card(truth.id).name, pool])

# ---------------------------------------------------------------- B33
# Egg in Your Soup: "If you have a card named "The Sandwich Factory" in play, add 2 ICE
# Counters to it." With two Factories, one of them (the player's pick) gets the 2 counters.
func b33_egg_in_your_soup():
	var soup = shipped_deck("009-soup-and-sandwiches")   # 4 Sandwich Factory, 4 Egg in Your Soup
	for count in [1, 2]:
		await fixture("custom", 0, [2, 2], soup)
		var p = player(0)
		var factories: Array = []
		for i in count:
			var f = card("The Sandwich Factory")
			await e.play_card(p, f)
			factories.append(f)
		var before = factories.reduce(func(sum, f): return sum + f.counters, 0)
		await e.play_card(p, card("Egg in Your Soup"))
		var added = factories.reduce(func(sum, f): return sum + f.counters, 0) - before
		if count == 1: verify(added == 2, "control: Egg in Your Soup adds 2 ICE counters to your Sandwich Factory")
		else: verify(added == 2, "B33 Egg in Your Soup adds 2 ICE counters in total with two Sandwich Factories (added %d)" % added)

# ---------------------------------------------------------------- B34
# draw() emits card_moved(card, "discard", "deck") for every card it reshuffles; the table
# plays the shuffle sound from it. Other discard-into-deck shuffles should do the same.
func b34_reshuffle_signals():
	for id in ["Lightning Talks", "LAN Party", "Speakers Needed"]:
		await fixture("2026", 0)
		await e.end_turn(player(0))
		await e.end_turn(player(1))   # after one round both decks are empty, hands discarded
		var shuffled = player(1) if id == "LAN Party" else player(0)
		var expected = shuffled.discard.size()
		var moved = {"n": 0}
		e.card_moved.connect(func(c, origin, destination):
			if origin == "discard" and destination == "deck" and c.owner == shuffled.seat: moved.n += 1)
		await e.play_card(player(0), card(id))
		var ok = shuffled.deck.size() + shuffled.hand.size() >= 1 and expected == 5 and moved.n == expected
		match id:
			"Lightning Talks": verify(ok, "control: drawing from an empty deck emits discard->deck card_moved for each reshuffled card")
			"LAN Party": verify(ok, "B34 CRT LAN Party reshuffling an opponent's discard pile emits card_moved for each card (%d of %d)" % [moved.n, expected])
			"Speakers Needed": verify(ok, "B34 Speakers Needed shuffling your discard pile into your deck emits card_moved for each card (%d of %d)" % [moved.n, expected])
