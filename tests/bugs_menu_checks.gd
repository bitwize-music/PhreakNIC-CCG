extends SceneTree
## Known bugs in the main menu, lifetime stats and deck builder (B11-B13, B26, B27, B35, B37, B39-B41, B55).
## Every "Bnn ..." check asserts the correct behaviour, so it fails until that bug is fixed;
## "control: ..." checks show the harness itself works.
##   XDG_DATA_HOME=/tmp/phreak-test godot4.7.1 --headless --path . -s tests/bugs_menu_checks.gd
## Every user:// file the suite touches is backed up first and restored at the end (also on an early quit).
## B12/B13/B55 run in a subprocess (tests/bugs_menu_helper.gd) because the bug quits or hangs the game.
## Test-only hook: table.lifetime_test_enabled, because record_lifetime() skips headless runs without it.
## B36 (online custom-deck stats) is not covered: on v0.28 the client table of an online custom-deck game stops
## with a script error in setup_online (table.gd:2153) before it can finish or record the game.
class ErrorCounter extends Logger:
 var count = 0
 func _log_error(_f: String, _file: String, _line: int, _code: String, _rationale: String, _notify: bool, type: int, _traces: Array[ScriptBacktrace]) -> void:
  if type == Logger.ERROR_TYPE_SCRIPT: count += 1
const HELPER = "res://tests/bugs_menu_helper.gd"
const MARKER = "BUGS_MENU_HELPER ALIVE"
const USER_FILES = ["user://stats.json", "user://stats.json.tmp", "user://stats.json.bad", "user://decks.json", "user://decks.json.tmp", "user://savegame.json", "user://savegame.json.tmp", "user://settings.cfg"]
var checks = 0
var failures = 0
var backups = {}
var restored = false
var errors = ErrorCounter.new()
var helper_errors = 0
var style
var sfx
var Share
var BUILDER
var MENU
func _initialize(): call_deferred("run")
func _finalize(): restore()
func verify(ok, message):
 checks += 1
 if not ok:
  failures += 1
  print("FAIL: ", message)
func frames(n = 4):
 for i in n: await process_frame
func until(condition: Callable, limit: int) -> bool:
 for i in limit:
  if condition.call(): return true
  await process_frame
 return condition.call()

# ---------- user data ----------
func backup():
 for path in USER_FILES: backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
func restore():
 if restored or backups.size() != USER_FILES.size(): return
 restored = true
 for path in USER_FILES:
  if backups[path] == null:
   if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
  else:
   var file = FileAccess.open(path, FileAccess.WRITE)
   if file != null:
    file.store_buffer(backups[path])
    file.close()
func erase(path: String):
 for suffix in ["", ".tmp", ".bad"]:
  if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
func clean_slate():
 for path in ["user://stats.json", "user://decks.json", "user://savegame.json", "user://settings.cfg"]: erase(path)
 var config = ConfigFile.new()
 config.set_value("ui", "tutorial_seen", true) # a returning player: no first-run tutorial prompt
 config.save("user://settings.cfg")
 sfx.visual_effects = false
 sfx.auto_end_turn = false
 sfx.confirm_end_turn = false
 sfx.auto_activate.clear()
 sfx.bot_pace = 0.0
 sfx.difficulty = 0
 sfx.starting_life = 0
 sfx.card_pool = "2026"
 sfx.custom_deck_name = "Tag Team"
 sfx.hero_id = ""
 sfx.handle = "Neo" # a typed handle: no Hero picked
 sfx.music_volume = 0.35
 sfx.music_muted = false
 sfx.save()
 root.get_node("CardDB").select_pool("2026")
func saved_setting(section: String, key: String, fallback = null):
 var config = ConfigFile.new()
 if config.load("user://settings.cfg") != OK: return fallback
 return config.get_value(section, key, fallback)

# ---------- UI helpers ----------
func find_button(node, text):
 if node is Button and node.text == text and node.is_visible_in_tree(): return node
 for child in node.get_children():
  var found = find_button(child, text)
  if found != null: return found
 return null
func button_starting(node, prefix: String):
 for button in node.find_children("*", "Button", true, false):
  if button.text.begins_with(prefix) and button.is_visible_in_tree(): return button
 return null
func texts(node) -> Array:
 var found = []
 for child in node.find_children("*", "Control", true, false):
  if (child is Label or child is Button) and child.is_visible_in_tree(): found.append(child.text)
 return found
## Text of a node tree that isn't in the scene tree (the share card is rendered off-screen).
func all_texts(node) -> Array:
 return node.find_children("*", "Control", true, false).filter(func(c): return c is Label or c is Button).map(func(c): return c.text)
func has_text(node, text: String) -> bool:
 return texts(node).any(func(t): return text in t)
func click(control: Control):
 var point = control.get_global_rect().get_center()
 for down in [true, false]:
  var event = InputEventMouseButton.new()
  event.button_index = MOUSE_BUTTON_LEFT
  event.pressed = down
  event.position = point
  event.global_position = point
  root.push_input(event, true)
func wheel_up(control: Control):
 var point = control.get_global_rect().get_center()
 for down in [true, false]:
  var event = InputEventMouseButton.new()
  event.button_index = MOUSE_BUTTON_WHEEL_UP
  event.factor = 1.0
  event.pressed = down
  event.position = point
  event.global_position = point
  root.push_input(event, true)
func key(code: Key):
 for down in [true, false]:
  var event = InputEventKey.new()
  event.keycode = code
  event.physical_keycode = code
  event.pressed = down
  Input.parse_input_event(event)
## Android Back as the engine delivers it: Window::_propagate_window_notification notifies the window, then
## every child in order (internal ones too), skipping native sub-windows. It does not lock the tree.
func deliver_back(node: Node):
 node.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
 var i = 0
 while i < node.get_child_count(true):
  var child = node.get_child(i, true)
  if not (child is Window and not child.is_embedded()): deliver_back(child)
  i += 1
func open_menu():
 var menu = MENU.instantiate()
 root.add_child(menu)
 current_scene = menu
 await frames()
 return menu
func builder_of(menu):
 for child in menu.get_children():
  if child.get_script() == BUILDER and not child.is_queued_for_deletion(): return child
 return null
func open_builder(menu):
 find_button(menu, "Decks (experimental)").pressed.emit()
 await frames()
 return builder_of(menu)
## The Edit/Duplicate/Use deck button on a deck's row in the builder's list.
func entry_button(builder, deck_name: String, text: String):
 for label in builder.find_children("*", "Label", true, false):
  if label.text.begins_with(deck_name + " · ") and label.is_visible_in_tree(): return find_button(label.get_parent(), text)
 return null
## Typing a new name into the editor's name field.
func rename_in_editor(builder, old_name: String, new_name: String):
 for field in builder.find_children("*", "LineEdit", true, false):
  if field.text == old_name and field.is_visible_in_tree():
   field.text = new_name
   field.text_changed.emit(new_name)
   return
func share_node(node):
 for child in node.find_children("*", "Node", true, false):
  if child.get_script() == Share: return child
 return null
## One cell of a stats table ("Your record"), found by row title and column header; "" if the row isn't shown.
func record_cell(screen, row_title: String, column: String) -> String:
 for grid in screen.find_children("*", "GridContainer", true, false):
  var cells = grid.get_children().filter(func(c): return c is Label)
  var row = cells.map(func(c): return c.text).find(row_title)
  if row < 0: continue
  var col = cells.slice(0, grid.columns).map(func(c): return c.text).find(column)
  return cells[row + col].text if col >= 0 and row + col < cells.size() else ""
 return ""

# ---------- run ----------
func run():
 var started = Time.get_ticks_msec()
 OS.add_logger(errors)
 sfx = root.get_node("Sfx")
 style = load("res://scripts/ui/style.gd")
 Share = load("res://scripts/ui/result_share.gd")
 BUILDER = load("res://scripts/ui/deck_builder.gd")
 MENU = load("res://scenes/menu.tscn")
 backup()
 clean_slate()
 root.size = Vector2i(1920, 1080)
 style.compact_override = false
 helper_checks()
 await deck_editor_checks()
 await selection_checks()
 await music_checks()
 await player_count_checks(false)
 await player_count_checks(true)
 style.compact_override = false
 await stalemate_checks()
 await knocked_out_checks()
 await online_resume_checks()
 verify(errors.count == 0 and helper_errors == 0, "control: no script errors (suite %d, subprocesses %d)" % [errors.count, helper_errors])
 style.compact_override = null
 restore()
 print("Runtime: %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
 print("Menu bug checks: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)

# ---------- B12, B13: quitting, observed from a subprocess ----------
## Runs one helper scenario. Its script errors count toward the "no script errors" control unless they are
## the bug under test (B55's endless loop is made of them).
func helper(scenario: String, count_errors: bool = true) -> Dictionary:
 var output = []
 var code = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", HELPER, "--", scenario], output, true)
 var text = "\n".join(output)
 if count_errors: helper_errors += text.count("SCRIPT ERROR")
 return {"code": code, "text": text, "started": ("BUGS_MENU_HELPER START " + scenario) in text, "alive": MARKER in text}
func remove_tree(path: String):
 var dir = DirAccess.open(path)
 if dir == null: return
 dir.include_hidden = true
 for name in dir.get_files(): DirAccess.remove_absolute(path.path_join(name))
 for name in dir.get_directories(): remove_tree(path.path_join(name))
 DirAccess.remove_absolute(path)
func helper_checks():
 # The subprocess gets an empty user:// of its own, so it can't touch real data.
 var scratch = OS.get_user_data_dir().path_join("bug-checks-subprocess-%d" % OS.get_process_id())
 DirAccess.make_dir_recursive_absolute(scratch)
 var had_xdg = OS.has_environment("XDG_DATA_HOME")
 var old_xdg = OS.get_environment("XDG_DATA_HOME")
 OS.set_environment("XDG_DATA_HOME", scratch)
 var quit_button = helper("quit-button")
 var controls = helper("controls")
 var back = helper("stats-back")
 var web = helper("web-escape")
 var knockout_slow = helper("knockout-slow")
 var knockout = helper("knockout", false)
 if had_xdg: OS.set_environment("XDG_DATA_HOME", old_xdg)
 else: OS.unset_environment("XDG_DATA_HOME")
 remove_tree(scratch)
 verify(quit_button.started and quit_button.code == 0 and not quit_button.alive and not "TIMEOUT" in quit_button.text, "control: the subprocess harness sees quit() (desktop Quit button)")
 verify(controls.alive and "stats_open=false" in controls.text, "control: Escape on Stats only closes Stats")
 verify(controls.alive and "builder_open=false" in controls.text, "control: Android Back with the deck builder open closes it and keeps the app running")
 verify(back.started and back.alive and "stats_open=false" in back.text, "B12 Android Back on Stats closes Stats and keeps the app running")
 verify(web.started and "quit_visible=false" in web.text, "control: the web flag reaches the subprocess (Quit is hidden)")
 verify(web.started and web.alive, "B13 Escape on the web main menu keeps the game running")
 print("B55 helper output: %d bytes, exit code %d" % [knockout.text.length(), knockout.code])
 verify(knockout_slow.alive and "KNOCKED_OUT true" in knockout_slow.text and "main_menu=true" in knockout_slow.text and not "BUGS_MENU_HELPER LOOP" in knockout_slow.text, "control: after being knocked out, Menu > Main menu > Leave reaches the main menu at the slowest Bot pace")
 verify(knockout.started and "KNOCKED_OUT true" in knockout.text, "control: (B55 run) you are knocked out while two bots play on")
 verify(knockout.alive and "main_menu=true" in knockout.text and not "BUGS_MENU_HELPER LOOP" in knockout.text, "B55 With Bot pace Instant, Menu > Main menu > Leave after being knocked out reaches the main menu without hanging")

# ---------- B27: deck editor Back ----------
func new_deck_with_cards(builder):
 find_button(builder, "New").pressed.emit()
 await frames(2)
 var plus = builder.find_children("*", "Button", true, false).filter(func(b): return b.text == "+" and b.is_visible_in_tree())
 for button in plus.slice(0, 6): button.pressed.emit()
 await frames(2)
func editor_open(builder, deck_name: String) -> bool:
 return builder.find_children("*", "LineEdit", true, false).any(func(f): return f.text == deck_name and f.is_visible_in_tree())
func deck_kept(builder, deck_name: String) -> bool:
 return BUILDER.saved().any(func(d): return d.name == deck_name and CustomDeck.total(d) == 6) or has_text(builder, deck_name + " · 6 cards")
func deck_editor_checks():
 erase("user://decks.json")
 var menu = await open_menu()
 var builder = await open_builder(menu)
 await new_deck_with_cards(builder)
 find_button(builder, "Keep draft").pressed.emit()
 await frames(2)
 verify(deck_kept(builder, "New deck"), "control: Keep draft keeps an unfinished deck")
 builder.queue_free()
 for path in ["The Back button", "Escape", "Android Back"]:
  erase("user://decks.json")
  builder = await open_builder(menu)
  await new_deck_with_cards(builder)
  root.gui_release_focus()
  match path:
   "The Back button": find_button(builder, "Back").pressed.emit()
   "Escape": key(KEY_ESCAPE)
   "Android Back": deliver_back(root)
  await frames()
  # Correct: the 6 unsaved cards are not dropped silently. The editor stays open (for example behind a
  # "discard changes?" prompt) or the deck is kept as a draft; either way the cards survive.
  verify(editor_open(builder, "New deck") or deck_kept(builder, "New deck"), "B27 %s in the deck editor does not throw away an unsaved deck without asking" % path)
  builder.queue_free()
  await frames(2)
 menu.queue_free()
 await frames(2)
 erase("user://decks.json")

# ---------- B39: renaming the selected custom deck ----------
func selection_checks():
 erase("user://decks.json")
 sfx.card_pool = "2026"
 sfx.custom_deck_name = "Tag Team"
 sfx.save()
 var menu = await open_menu()
 var builder = await open_builder(menu)
 entry_button(builder, "Tag Team", "Duplicate").pressed.emit()
 await frames(2)
 rename_in_editor(builder, "Tag Team (2)", "Mine")
 find_button(builder, "Save").pressed.emit()
 await frames(2)
 find_button(builder, "Close").pressed.emit()
 await frames(2)
 button_starting(menu, "Custom deck (experimental)").pressed.emit()
 await frames(2)
 builder = builder_of(menu)
 entry_button(builder, "Mine", "Use deck").pressed.emit()
 await frames(2)
 verify(button_starting(menu, "Custom deck (experimental)").text.ends_with("Mine · 60 cards"), "control: Use deck selects the chosen custom deck")
 builder = await open_builder(menu)
 entry_button(builder, "Mine", "Edit").pressed.emit()
 await frames(2)
 rename_in_editor(builder, "Mine", "Mine v2")
 find_button(builder, "Save").pressed.emit()
 await frames(2)
 find_button(builder, "Close").pressed.emit()
 await frames(2)
 var tile = button_starting(menu, "Custom deck (experimental)").text
 verify(tile.ends_with("Mine v2 · 60 cards"), "B39 Renaming the selected custom deck keeps it selected (tile: %s)" % tile.replace("\n", " "))
 menu.queue_free()
 await frames(2)
 erase("user://decks.json")
 sfx.card_pool = "2026"
 sfx.custom_deck_name = "Tag Team"
 sfx.save()

# ---------- B41: music volume ----------
func music_slider(menu) -> HSlider:
 for slider in menu.find_children("*", "HSlider", true, false):
  if slider.is_visible_in_tree() and slider.get_parent().get_children().any(func(c): return c is CheckButton and c.text == "Music"): return slider
 return null
func music_checks():
 var menu = await open_menu()
 var slider = music_slider(menu)
 var before = slider.value
 wheel_up(slider)
 await frames()
 verify(slider.value > before, "control: the mouse wheel moves the music slider")
 verify(absf(float(saved_setting("sound", "music_volume", -1.0)) - slider.value) < 0.001, "B41 Music volume changed with the mouse wheel is saved")
 before = slider.value
 slider.grab_focus() # keyboard focus, as Tab navigation gives it
 key(KEY_RIGHT)
 await frames()
 verify(slider.value > before, "control: the Right arrow key moves the focused music slider")
 verify(absf(float(saved_setting("sound", "music_volume", -1.0)) - slider.value) < 0.001, "B41 Music volume changed with the keyboard is saved")
 slider.release_focus()
 # Press and release on the track: this is the path that does save.
 var rect = slider.get_global_rect()
 var point = rect.position + Vector2(rect.size.x * 0.25, rect.size.y * 0.5)
 for down in [true, false]:
  var event = InputEventMouseButton.new()
  event.button_index = MOUSE_BUTTON_LEFT
  event.pressed = down
  event.position = point
  event.global_position = point
  root.push_input(event, true)
 await frames()
 verify(slider.value < before and absf(float(saved_setting("sound", "music_volume", -1.0)) - slider.value) < 0.001, "control: clicking the music slider's track saves the volume")
 menu.queue_free()
 await frames(2)
 sfx.music_volume = 0.35
 sfx.save()

# ---------- B40: player count ----------
func seat_choice(menu) -> String:
 for n in [2, 3, 4]:
  var seat = find_button(menu, "%d players" % n)
  if seat != null and seat.button_pressed: return seat.text
 return ""
func player_count_checks(phone: bool):
 var layout = "phone layout" if phone else "desktop layout"
 style.compact_override = phone
 sfx.difficulty = 0
 sfx.visual_effects = false
 sfx.save()
 var menu = await open_menu()
 click(find_button(menu, "4 players"))
 click(button_starting(menu, BotDifficulty.DISPLAY_NAMES[1] + "\n"))
 await frames(2)
 verify(seat_choice(menu) == "4 players", "control: (%s) 4 players can be picked" % layout)
 # Reopen the main menu. Switching Visual effects rebuilds it with the same _ready() as coming back from a game.
 if phone:
  click(find_button(menu, "Settings"))
  await frames(2)
 var effects = null
 for toggle in menu.find_children("*", "CheckButton", true, false):
  if toggle.text == "Visual effects" and toggle.is_visible_in_tree(): effects = toggle
 click(effects)
 await frames(6)
 var again = current_scene
 var reopened = again != menu and is_instance_valid(again) and again.get_script() == load("res://scripts/ui/menu.gd")
 verify(reopened and button_starting(again, BotDifficulty.DISPLAY_NAMES[1] + "\n").button_pressed, "control: (%s) the reopened main menu keeps the chosen adversary" % layout)
 verify(reopened and seat_choice(again) == "4 players", "B40 (%s) The main menu remembers 4 players when it is reopened (shows: %s)" % [layout, seat_choice(again) if reopened else "no menu"])
 if is_instance_valid(again): again.queue_free()
 await frames(2)
 sfx.difficulty = 0
 sfx.visual_effects = false
 sfx.save()

# ---------- B35, B37: a stalemate, played by a player with no Hero ----------
## A fresh 2-player offline table where you move first (fixed seeds keep the run deterministic).
func offline_table() -> Control:
 for seed in range(1, 40):
  var table = load("res://scenes/table.tscn").instantiate()
  table.player_count = 2
  table.seed_value = seed
  table.auto_drive = false
  table.lifetime_test_enabled = true
  root.add_child(table)
  current_scene = table
  await frames(2)
  if table.engine.state.active_seat == 0 and table.available(): return table
  table.queue_free()
  await frames(1)
 return null
func stalemate_checks():
 erase("user://stats.json")
 erase("user://savegame.json")
 var table = await offline_table()
 var engine = table.engine
 # Fast-forward to an endgame: both players are down to 1 life and you have drawn r0nk
 # ("+2 Hacking. Each player loses 1 life (including yourself)"). You play it from your hand.
 for p in engine.state.players: p.life = 1
 var r0nk = engine.state.create("r0nk", 0)
 engine.state.players[0].hand.append(r0nk)
 engine.state_changed.emit()
 await frames(2)
 for box in table.find_children("*", "VBoxContainer", true, false):
  if box.get_meta("card_uid", -1) == r0nk.uid and box.get_meta("zone", "") == "hand": box.get_child(0).pressed.emit()
 await frames(8)
 var summary = table.find_child("MatchSummary", true, false)
 verify(summary != null and has_text(summary, "Stalemate"), "control: r0nk with everyone at 1 life ends in a Stalemate")
 if summary == null: table.queue_free(); return
 # What the summary's Copy text and Save image buttons use (headless has no clipboard).
 var details = share_node(table).data
 var text = Share.copy_text(details)
 verify(not " as —" in text, "B37 Copy text for a player with no Hero does not say 'as —' (%s)" % text)
 var card = Share.build_card(details)
 var card_text = "\n".join(all_texts(card))
 card.free()
 verify(not "as —" in card_text, "B37 The result card for a player with no Hero does not say 'as —'")
 find_button(summary, "Lifetime stats").pressed.emit()
 await frames()
 var screen = table.get_node_or_null("LifetimeStats")
 var losses = record_cell(screen, "Against bots", "Losses")
 # Only the loss count is asserted: whether a draw also ends a win streak is a design choice.
 verify(losses in ["", "0"], "B35 A stalemate is not counted as a loss (Against bots, Losses: %s)" % losses)
 var stats_text = Share.copy_text(share_node(screen).data)
 verify(not "favourite Hero No Hero" in stats_text, "B37 The stats share text for a player with no Hero does not say 'favourite Hero No Hero'")
 table.queue_free()
 await frames(2)
 erase("user://stats.json")
 erase("user://savegame.json")

# ---------- B11: knocked out of a 3-player offline game ----------
func knocked_out_checks():
 erase("user://savegame.json")
 erase("user://stats.json")
 var table = load("res://scenes/table.tscn").instantiate()
 table.player_count = 3
 table.difficulty = 1 # Phreak bots aim at the opponent with the least life (BotDecider.choose_player)
 table.seed_value = 11
 root.add_child(table)
 current_scene = table
 var human = table.engine.state.players[0]
 await until(func(): return table.available(), 600)
 # Fast-forward: you have been worn down to 1 life. Save from the in-game menu, then end your turn.
 human.life = 1
 table.engine.state_changed.emit()
 table.menu_button.pressed.emit()
 await frames(2)
 find_button(table.game_menu, "Save game").pressed.emit()
 find_button(table.game_menu, "Resume").pressed.emit()
 await frames(2)
 table.end_button.pressed.emit()
 await until(func(): return not human.alive or table.engine.state.finished, 1500)
 var bots_left = table.engine.state.players.filter(func(p): return p.alive and p.is_bot).size()
 verify(not human.alive and not table.engine.state.finished and bots_left == 2, "control: you are knocked out while two bots play on")
 # Leave: Menu > Main menu, answering "Leave without saving?" with Leave. First pick the slowest Bot pace in the
 # same menu, so no bot is mid-move when the scene changes: leaving during an Instant-pace bot move is a
 # different problem from B11.
 table.menu_button.pressed.emit()
 await frames(2)
 var pace = table.game_menu.find_children("BotPace", "OptionButton", true, false)[0]
 pace.select(pace.item_count - 1)
 pace.item_selected.emit(pace.item_count - 1)
 await frames(3)
 find_button(table.game_menu, "Main menu").pressed.emit()
 await frames(2)
 var leave = find_button(table, "Leave")
 if leave != null: leave.pressed.emit()
 await frames(6)
 var menu = current_scene
 verify(is_instance_valid(menu) and menu.get_script() == load("res://scripts/ui/menu.gd"), "control: Main menu after being knocked out returns to the main menu")
 var resume = find_button(menu, "Resume game") if is_instance_valid(menu) else null
 var alive_again = false
 if resume != null:
  resume.pressed.emit()
  await frames(6)
  var resumed = current_scene
  alive_again = is_instance_valid(resumed) and "engine" in resumed and resumed.engine.state.players[0].alive and not resumed.engine.state.finished
 # Asserted: Resume must not seat you again in the game you were knocked out of. Whether leaving also
 # records a loss is left open (lifetime stats skip unfinished games, v0.17), so a fix may choose either.
 verify(not alive_again, "B11 After being knocked out and leaving, Resume game does not bring you back alive")
 if is_instance_valid(current_scene): current_scene.queue_free()
 await frames(2)
 erase("user://savegame.json")
 erase("user://stats.json")

# ---------- B26: an online game rejoined mid-match ----------
## A client table for seat 0, connected the way the online tests connect it (loopback transport).
func online_table(server) -> Dictionary:
 var session = OnlineSession.new()
 root.add_child(session)
 var pair = LoopbackTransport.pair()
 server.attach(pair[0])
 session.client.connect_to(pair[1], 0, server.tokens[0])
 pair[1].received.connect(session._message)
 await frames(3)
 var table = load("res://scenes/table.tscn").instantiate()
 table.online_session = session
 table.lifetime_test_enabled = true
 root.add_child(table)
 await frames(3)
 return {"table": table, "session": session, "pair": pair}
func leave_online(game: Dictionary):
 game.session.disconnect_game()
 game.pair[1].close()
 game.table.queue_free()
 game.session.queue_free()
 await frames(3)
func online_resume_checks():
 erase("user://stats.json")
 var server = GameServer.new()
 root.add_child(server)
 server.setup([{"name": "Neo", "bot": false}, {"name": "Rival", "bot": true, "difficulty": 0}], "2026", 0, 26)
 await server.start()
 var you = server.engine.state.players[0]
 # You play from turn 1 and drop out (app closed) as your next turn begins. Dropping out that early means the
 # bot only ever plays starter cards, so nothing asks you a question and the run stays deterministic.
 var first = await online_table(server)
 var next_turn = func():
  if first.table.available() and server.engine.state.turn == 1: first.table.end_button.pressed.emit()
  return server.engine.state.turn > 1 and server.engine.active() == you and first.table.available()
 await until(next_turn, 1500)
 await leave_online(first)
 # Resume online game: a new table for the same seat. You end that turn, and win at the start of your next.
 var second = await online_table(server)
 await until(func(): return second.table.available(), 600)
 var turns_at_rejoin = you.turns
 second.table.end_button.pressed.emit()
 await until(func(): return you.turns > turns_at_rejoin and second.table.available(), 1500)
 var turns_played = you.turns
 # The server declares you the winner, as when your last attack lands.
 server.engine.finish(you)
 await frames(6)
 var summary = second.table.find_child("MatchSummary", true, false)
 verify(summary != null and has_text(summary, "Statistics since resume"), "control: the rejoined game's summary says 'Statistics since resume'")
 var fastest = -1
 if summary != null:
  find_button(summary, "Lifetime stats").pressed.emit()
  await frames()
  for line in texts(second.table.get_node("LifetimeStats")):
   if line.begins_with("Fastest win: "): fastest = int(line.trim_prefix("Fastest win: ").get_slice(" ", 0))
 # Correct: a win you only saw part of may count, but it can't set Fastest win below the turns you played.
 # 0 is the store's "no record yet" value, so a fix that skips partial games may still show it.
 verify(fastest <= 0 or fastest >= turns_played, "B26 A win after rejoining an online game does not set Fastest win below the turns you played (played %d, shows %d)" % [turns_played, fastest])
 await leave_online(second)
 server.queue_free()
 await frames(2)
 erase("user://stats.json")
