extends SceneTree
## Known-bug checks for the bots and the build/CI configuration.
## Every "Bnn" check asserts the correct behaviour: it fails while the bug exists
## and passes once it is fixed. "control:" checks show the fixtures are sound.
## Run: godot4.7.1 --headless --path . -s tests/bugs_bots_checks.gd
## Touches no user:// files.
class ErrorCounter extends Logger:
	var count = 0
	func _log_error(_f: String, _file: String, _line: int, _code: String, _rationale: String, _notify: bool, _type: int, _traces: Array[ScriptBacktrace]) -> void: count += 1

## A human seat that takes `delay` seconds to answer, like a person thinking.
class SlowHuman extends Decider:
	var delay = 0.0
	var prompts = 0
	var waited_ms = 0
	func _init(seconds: float): delay = seconds
	func choose_cards(_p, _prompt: String, cards: Array, min_n: int, _max_n: int) -> Array:
		prompts += 1
		var started = Time.get_ticks_msec()
		if delay > 0.0: await Engine.get_main_loop().create_timer(delay).timeout
		waited_ms += Time.get_ticks_msec() - started
		return cards.slice(0, min_n)

## A human who plays O.P.R.A.H. and removes one Hacking card.
class OprahHuman extends Decider:
	func choose_cards(_p, prompt: String, cards: Array, min_n: int, _max_n: int) -> Array:
		if prompt.begins_with("Remove cards"):
			for c in cards:
				if c.id == "Hacking": return [c]
		return cards.slice(0, min_n)

const SLOW_ANSWER = 1.0 # Seconds; 12x DEFCON's 80 ms turn allowance.
# Lines or YAML scopes that test the event or ref run only for some pushes/PRs.
const GATED = "refs/heads/|github\\.ref|event_name|\\$\\{?EVENT\\b|\\$\\{?REF\\b"
var errors = ErrorCounter.new()
var checks = 0
var failures = 0
var expected_errors = 0

func _initialize(): call_deferred("run")
func verify(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)

func run():
	OS.add_logger(errors)
	await b06_defcon_target_with_human()
	await b07_slow_human_answer()
	await b48_oprah_hidden_draw()
	b18_export_versions()
	b20_ci_suites()
	verify(errors.count == expected_errors, "control: no engine errors outside the B06 step (%d unexpected)" % (errors.count - expected_errors))
	print("Bot bug checks: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Returns a real card from the Center Deck (else the row, which refills), or null.
func take(e, id: String):
	for c in e.state.center_deck:
		if c.id == id: return c
	for c in e.state.center_row:
		if c != null and c.id == id: return c
	return null

# --- B06: DEFCON's hostile target choice asks human seats' deciders for value() ---
func b06_game(human_decider) -> Dictionary:
	var e = GameEngine.new()
	root.add_child(e)
	# Three players: seat 0 human (an Elite bot in the control), seat 1 DEFCON, seat 2 Elite.
	e.setup([2 if human_decider == null else -1, 3, 2], 60606, [] if human_decider == null else [human_decider], "2025")
	await e.start_turn(0)
	# Seat 0 ends its first turn without playing: its hand goes to its public discard pile.
	await e.end_turn(e.state.players[0])
	var bot = e.active()
	var rick = take(e, "Rick Astley")
	var roll = take(e, "Rickroll")
	var result = {"fixture": bot.difficulty == 3 and rick != null and roll != null and not e.state.players[0].discard.is_empty(), "errors": -1, "target": -1, "killable": true}
	if result.fixture:
		e.gain_owner(rick, bot)
		e.move(rick, bot.hand, "hand")
		e.gain_owner(roll, bot)
		e.move(roll, bot.discard, "discard")
		# Rick Astley: deal 2 damage, then "Give Rickroll" to a chosen opponent (a hostile prompt).
		var before = errors.count
		await e.play_card(bot, rick)
		result.errors = errors.count - before
		for q in e.opponents(bot):
			if roll in q.discard and roll.owner == q.seat: result.target = q.seat
		result.killable = e.opponents(bot).any(func(q): return q.life + e.dec(bot).target_ice(q) <= e.dec(bot).hand_damage(bot))
	e.queue_free()
	await process_frame
	return result

func b06_defcon_target_with_human():
	var control = await b06_game(null)
	verify(control.fixture and not control.killable, "control: B06 fixture puts DEFCON before two healthy opponents with Rick Astley in hand and a Rickroll in its discard")
	verify(control.errors == 0 and control.target >= 0, "control: with only bot opponents DEFCON gives the Rickroll without engine errors (errors %d, target seat %d)" % [control.errors, control.target])
	# Decider stands in for HumanDecider (local) and RemoteDecider (online); none defines value().
	verify(not Decider.new().has_method("value") and not HumanDecider.new(null).has_method("value") and not RemoteDecider.new(null, 0).has_method("value"), "control: human seats' deciders (Decider, HumanDecider, RemoteDecider) define no value()")
	var human = await b06_game(Decider.new())
	expected_errors += maxi(0, human.errors)
	verify(human.fixture and not human.killable, "control: B06 fixture with a human seat 0 is reachable and nobody is killable")
	verify(human.errors == 0 and human.target >= 0, "B06 DEFCON picks a Rickroll target without engine errors when an opponent is human (errors %d, target seat %d)" % [human.errors, human.target])

# --- B07: DEFCON's 80 ms turn allowance counts time spent waiting for a human ---
func b07_turn(delay: float) -> Dictionary:
	var e = GameEngine.new()
	root.add_child(e)
	e.setup([3, -1], 4242, [], "2025")
	var human = SlowHuman.new(delay)
	e.deciders[1] = human
	await e.start_turn(0)
	var bot = e.state.players[0]
	var reason = take(e, "The Reason")
	var actions: Array = []
	if reason != null:
		# Fixture hand: The Reason ("+2 Hacking, each other player discards a card") and four Hacking.
		for c in bot.hand.duplicate(): e.move(c, bot.deck, "deck")
		for c in bot.deck.filter(func(x): return x.id == "Hacking").slice(0, 4): e.move(c, bot.hand, "hand")
		e.gain_owner(reason, bot)
		e.move(reason, bot.hand, "hand")
		e.card_played.connect(func(pl, c): if pl == bot: actions.append("play " + c.id))
		e.card_bought.connect(func(pl, c): if pl == bot: actions.append("buy " + c.id))
		e.card_reserved.connect(func(pl, c): if pl == bot: actions.append("reserve " + c.id))
		await BotPlayer.new(e).take_turn(bot)
	var result = {"fixture": reason != null, "actions": actions, "prompts": human.prompts, "waited_ms": human.waited_ms}
	e.queue_free()
	await process_frame
	return result

func b07_slow_human_answer():
	await b07_turn(0.0) # Warm-up: loads DEFCON's weights and compiles scripts outside the compared turns.
	var instant = await b07_turn(0.0)
	var slow = await b07_turn(SLOW_ANSWER)
	var plays = instant.actions.filter(func(a): return a.begins_with("play "))
	verify(instant.fixture and instant.prompts == 1 and plays.size() == 5, "control: with an instant human answer DEFCON plays all five cards (%s)" % ", ".join(instant.actions))
	verify(slow.prompts == 1 and slow.waited_ms >= SLOW_ANSWER * 900, "control: the slow human was asked once and answered after %d ms" % slow.waited_ms)
	# The human's thinking time must not change what DEFCON does with its turn.
	verify(slow.actions == instant.actions, "B07 DEFCON keeps playing after a slow human answer (slow: %s; instant: %s)" % [", ".join(slow.actions), ", ".join(instant.actions)])

# --- B48: the custom-deck planner learns O.P.R.A.H.'s hidden Center Deck draw ---
func oprah_world(swap_hidden_top: bool) -> Dictionary:
	var starters = JSON.parse_string(FileAccess.get_file_as_string("res://data/starter_decks.json"))
	var deck = {"name": "B48 fixture", "cards": starters[0].cards.duplicate()}
	deck.cards["O.P.R.A.H."] = 2
	var e = GameEngine.new()
	root.add_child(e)
	var ok = e.setup([-1, 2], 4848, [OprahHuman.new()], "2026", 0, [], deck)
	var planner = e.get_meta("custom_planner", null) if ok else null
	var result = {"fixture": false}
	if planner != null:
		await e.start_turn(0)
		var human = e.state.players[0]
		var oprah = take(e, "O.P.R.A.H.")
		e.gain_owner(oprah, human)
		e.move(oprah, human.hand, "hand")
		var pile = e.state.center_deck
		if swap_hidden_top:
			# Another world: same public state, a different card hidden on top of the Center Deck.
			for i in pile.size():
				if CustomDeck.base_id(pile[i].id) != CustomDeck.base_id(pile.back().id):
					var top = pile.back()
					pile[pile.size() - 1] = pile[i]
					pile[i] = top
					break
		var drawn = pile.back()
		var before = planner.census().duplicate()
		await e.play_card(human, oprah) # Removes one Hacking, draws the top Center Deck card into the hand.
		result = {"fixture": true, "before": before, "after": planner.census().duplicate(), "drawn": CustomDeck.base_id(drawn.id), "hidden": drawn in human.hand}
	e.queue_free()
	await process_frame
	return result

func count_diff(a: Dictionary, b: Dictionary) -> Array:
	var ids: Array = []
	for id in a.keys() + b.keys():
		if a.get(id, 0) != b.get(id, 0) and id not in ids: ids.append(id)
	return ids

func b48_oprah_hidden_draw():
	var a = await oprah_world(false)
	var b = await oprah_world(true)
	verify(a.fixture and b.fixture and a.hidden and b.hidden and a.drawn != b.drawn, "control: O.P.R.A.H. drew a different card into the human's hidden hand in each world (%s / %s)" % [a.get("drawn", "?"), b.get("drawn", "?")])
	if not (a.fixture and b.fixture): return
	verify(count_diff(a.before, b.before).is_empty(), "control: before O.P.R.A.H. the planner's census is the same in both worlds")
	# The bots' public census may not depend on which hidden card the human drew.
	var leaked = count_diff(a.after, b.after)
	verify(leaked.is_empty(), "B48 custom-deck planner learns nothing from O.P.R.A.H.'s hidden Center Deck draw (census differs for: %s)" % (", ".join(leaked) if not leaked.is_empty() else "none"))

# --- B18: export preset versions follow project.godot config/version ---
func b18_export_versions():
	var version = str(ProjectSettings.get_setting("application/config/version", ""))
	var parts = version.split(".")
	var cfg = ConfigFile.new()
	var loaded = cfg.load("res://export_presets.cfg") == OK
	var options = {}
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			options[str(cfg.get_value(section, "platform", ""))] = section + ".options"
	var readable = loaded and parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() and options.has("Android") and options.has("Windows Desktop")
	verify(readable, "control: read config/version %s and the Android and Windows export presets" % version)
	if not readable: return
	# Convention of every release since v0.04 (git log -p export_presets.cfg):
	# "0.09" -> Android version/name "0.09", version/code 9, Windows "0.0.9.0".
	var code = int(parts[0]) * 100 + int(parts[1])
	var windows = "%d.0.%d.0" % [int(parts[0]), int(parts[1])]
	var android = options["Android"]
	var desktop = options["Windows Desktop"]
	var version_name = str(cfg.get_value(android, "version/name", ""))
	verify(version_name == version, "B18 Android version/name is config/version %s (found %s)" % [version, version_name])
	var found_code = int(cfg.get_value(android, "version/code", -1))
	verify(found_code == code, "B18 Android version/code is %d for version %s (found %d)" % [code, version, found_code])
	for key in ["application/file_version", "application/product_version"]:
		var value = str(cfg.get_value(desktop, key, ""))
		verify(value == windows, "B18 Windows %s is %s for version %s (found %s)" % [key.get_slice("/", 1), windows, version, value])

# --- B20: CI runs the rules and bot suites on every push and pull request ---
func test_names() -> Array:
	var names: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.ends_with(".gd"): names.append(f.get_basename())
	return names

func strip_comment(line: String) -> String:
	for i in line.length():
		if line[i] == "#" and (i == 0 or line[i - 1] == " " or line[i - 1] == "\t"): return line.left(i)
	return line

func indent_of(line: String) -> int:
	return line.length() - line.lstrip(" ").length()

## Suites a workflow (or a tools/tests script it calls) runs on every push and PR:
## bare suite names, tests/<name>.gd paths and tests/ globs on lines that are not
## comments, not in a shell `if` on the event/ref, and not in a YAML step or job
## whose `if:` tests the event/ref.
func ci_suites(text: String, names: Array, yaml: bool = true) -> Dictionary:
	var gate = RegEx.create_from_string(GATED)
	var lines = text.split("\n")
	var gated: Array = []
	gated.resize(lines.size())
	gated.fill(false)
	if yaml:
		# Mark literal (run: |) content, then gate the YAML scope of each conditional `if:`.
		var literal: Array = []
		var literal_indent = -1
		for raw in lines:
			var stripped = raw.strip_edges()
			var inside = literal_indent >= 0 and (stripped.is_empty() or indent_of(raw) > literal_indent)
			literal.append(inside)
			if inside: continue
			literal_indent = -1
			var key = strip_comment(stripped).strip_edges()
			if key.ends_with("|") or key.ends_with("|-") or key.ends_with(">") or key.ends_with(">-"): literal_indent = indent_of(raw)
		for i in lines.size():
			var stripped = strip_comment(lines[i]).strip_edges()
			if literal[i] or not stripped.trim_prefix("- ").begins_with("if:") or gate.search(stripped) == null: continue
			var level = indent_of(lines[i]) + (2 if stripped.begins_with("- ") else 0)
			var first = i
			while first > 0 and not stripped.begins_with("- "):
				var previous = lines[first - 1]
				if previous.strip_edges().is_empty() or literal[first - 1]:
					first -= 1
					continue
				if previous.strip_edges().begins_with("- ") and indent_of(previous) + 2 == level:
					first -= 1
					break
				if indent_of(previous) < level: break
				first -= 1
			var last = i
			while last + 1 < lines.size() and (lines[last + 1].strip_edges().is_empty() or indent_of(lines[last + 1]) >= level): last += 1
			for j in range(first, last + 1): gated[j] = true
	var word = RegEx.create_from_string("[A-Za-z0-9_]+")
	var glob = RegEx.create_from_string("tests/[A-Za-z0-9_*?.-]*\\*[A-Za-z0-9_*?.-]*")
	var script_path = RegEx.create_from_string("(?:tools|tests|scripts)/[A-Za-z0-9_./-]+\\.(?:sh|py)")
	var found = {}
	var shell_depth = 0
	for i in lines.size():
		var line = strip_comment(lines[i])
		var stripped = line.strip_edges()
		if stripped.is_empty(): continue
		var skip = gated[i] or shell_depth > 0 or gate.search(line) != null
		if shell_depth > 0:
			if stripped.begins_with("if "): shell_depth += 1
			elif stripped == "fi" or stripped.begins_with("fi ") or stripped.begins_with("fi;"): shell_depth -= 1
		elif stripped.begins_with("if ") and gate.search(line) != null and not stripped.ends_with("fi"): shell_depth = 1
		if skip: continue
		for m in word.search_all(line):
			if m.get_string() in names: found[m.get_string()] = true
		for m in glob.search_all(line):
			for n in names:
				if ("tests/%s.gd" % n).match(m.get_string()): found[n] = true
		if yaml:
			for m in script_path.search_all(line):
				if FileAccess.file_exists("res://" + m.get_string()):
					found.merge(ci_suites(FileAccess.get_file_as_string("res://" + m.get_string()), names, false))
	return found

## Suites reachable from `start`: preload/load("res://tests/x.gd") and class_name references.
func reach(start: Array, names: Array) -> Dictionary:
	var sources = {}
	var classes = {}
	var class_re = RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z0-9_]+)")
	for n in names:
		sources[n] = FileAccess.get_file_as_string("res://tests/%s.gd" % n)
		var m = class_re.search(sources[n])
		if m != null: classes[m.get_string(1)] = n
	var path_re = RegEx.create_from_string("res://tests/([A-Za-z0-9_]+)\\.gd")
	var seen = {}
	var queue = start.duplicate()
	while not queue.is_empty():
		var n = queue.pop_back()
		if seen.has(n) or not sources.has(n): continue
		seen[n] = true
		for m in path_re.search_all(sources[n]): queue.append(m.get_string(1))
		for cls in classes:
			if classes[cls] != n and RegEx.create_from_string("\\b%s\\b" % cls).search(sources[n]) != null: queue.append(classes[cls])
	return seen

func triggers(text: String) -> Array:
	var found: Array = []
	var inside = false
	for raw in text.split("\n"):
		var line = strip_comment(raw)
		if line.strip_edges().is_empty(): continue
		if indent_of(line) == 0:
			inside = line.begins_with("on:")
			if inside:
				for event in ["push", "pull_request"]:
					if RegEx.create_from_string("\\b%s\\b" % event).search(line.trim_prefix("on:")) != null: found.append(event)
			continue
		if inside and indent_of(line) == 2: found.append(line.strip_edges().trim_suffix(":"))
	return found

func b20_ci_suites():
	var names = test_names()
	var sample = "\n".join([
		"jobs:",
		"  a:",
		"    steps:",
		"      - run: |",
		"          suites=\"v21_checks tests/v1*_checks.gd\" # bot_checks only in a comment",
		"          if [ \"$EVENT\" = push ] && [ \"$REF\" = refs/heads/main ]; then suites=\"$suites sim\"; fi",
		"          if [ \"$REF\" = refs/heads/main ]; then",
		"            suites=\"$suites bot_bench\"",
		"          fi",
		"      - name: Main only",
		"        if: github.ref == 'refs/heads/main'",
		"        run: godot -s tests/rules_checks_runner.gd",
		"  b:",
		"    if: github.event_name == 'push'",
		"    steps:",
		"      - run: godot -s tests/bot_checks.gd",
	])
	var parsed = ci_suites(sample, names)
	var parsed_ok = parsed.has("v21_checks") and parsed.has("v10_checks") and parsed.has("v18_checks")
	for n in ["sim", "bot_bench", "rules_checks_runner", "bot_checks"]: parsed_ok = parsed_ok and not parsed.has(n)
	verify(parsed_ok, "control: the workflow reader skips comments, event/ref-gated shell lines, steps and jobs, and expands globs (%s)" % ", ".join(parsed.keys()))
	verify(reach(["sim"], names).has("rules_checks") and reach(["sim"], names).has("rules_v08"), "control: sim runs rules_checks and rules_v08")
	var text = FileAccess.get_file_as_string("res://.github/workflows/tests.yml")
	var events = triggers(text)
	verify("push" in events and "pull_request" in events, "control: the Tests workflow runs on push and pull_request (%s)" % ", ".join(events))
	var suites = ci_suites(text, names)
	var reached = reach(suites.keys(), names)
	verify(suites.has("v21_checks") and reached.has("defcon_policy_checks"), "control: CI runs v21_checks on every pull request, and with it defcon_policy_checks")
	verify(reached.has("rules_checks") and reached.has("rules_v08"), "B20 CI runs the official-rulings checks (rules_checks, rules_v08) on every push and pull request")
	verify(reached.has("bot_checks"), "B20 CI runs bot_checks on every push and pull request")
