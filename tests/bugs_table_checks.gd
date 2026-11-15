extends SceneTree
# Known table UI bugs, found on v0.28. Every check labelled Bnn asserts the CORRECT behaviour, so it fails while that
# bug is present and passes once it is fixed. Checks labelled "control:" pass today; they show the harness really
# reaches the state it claims (and that a fix keeps what already works).
# The UI is driven like input: button signals, InputEvents pushed through the viewport, OS notifications.
# Run with XDG_DATA_HOME pointing at a scratch dir. Every file under user:// is backed up and restored.
# Add "-- --verbose" to print passing checks too.
class ErrorCounter extends Logger:
 var count = 0
 var section = ""
 var by_section: Dictionary = {}
 var messages: Dictionary = {}
 func _log_error(_f: String, file: String, line: int, code: String, rationale: String, _notify: bool, _type: int, _traces: Array[ScriptBacktrace]) -> void:
  count += 1
  by_section[section] = by_section.get(section, 0) + 1
  var text = "[%s] %s:%d %s %s" % [section, file, line, code, rationale]
  messages[text] = messages.get(text, 0) + 1
var errors = ErrorCounter.new()
var checks = 0
var failures = 0
var verbose = "--verbose" in OS.get_cmdline_user_args()
var style # loaded in run(): style.gd needs the autoloads, which don't exist yet while members initialise
var settings
var table
var moves = 0
func _initialize(): call_deferred("run")
func verify(ok, message):
 checks += 1
 if not ok: failures += 1; print("FAIL: ", message)
 elif verbose: print("PASS: ", message)

# ---------- harness ----------
func frames(n = 4):
 for i in n: await process_frame
# Waits for a condition; the limit only stops a broken run from hanging, it is never what a check asserts.
func wait_until(condition: Callable, limit_ms: int = 10000) -> bool:
 var deadline = Time.get_ticks_msec() + limit_ms
 while not condition.call():
  if Time.get_ticks_msec() > deadline: return false
  await process_frame
 return true
func user_files() -> Dictionary:
 var files = {}
 var dir = DirAccess.open("user://")
 if dir != null:
  for name in dir.get_files(): files[name] = FileAccess.get_file_as_bytes("user://" + name)
 return files
func restore_user_files(files: Dictionary):
 var dir = DirAccess.open("user://")
 if dir == null: return
 for name in dir.get_files():
  if not files.has(name): dir.remove(name)
 for name in files:
  if FileAccess.file_exists("user://" + name) and FileAccess.get_file_as_bytes("user://" + name) == files[name]: continue
  var file = FileAccess.open("user://" + name, FileAccess.WRITE)
  file.store_buffer(files[name])
  file.close()
func buttons(node, found = []) -> Array:
 if node == null: return found
 if node is Button: found.append(node)
 for child in node.get_children(): buttons(child, found)
 return found
func button(node, prefix: String):
 for b in buttons(node, []):
  if b.text.begins_with(prefix) and b.is_visible_in_tree(): return b
 return null
func texts(node) -> String:
 var text = ""
 for label in node.find_children("*", "RichTextLabel", true, false): text += label.get_parsed_text() + "\n"
 for label in node.find_children("*", "Label", true, false): text += label.text + "\n"
 return text
# Open decision dialogs (card pickers, viewers, confirmations).
func dialogs() -> Array:
 var found = []
 if not is_instance_valid(table): return found
 for child in table.get_children():
  if child is PanelContainer and child.is_in_group("touch_modal") and child.name != "MatchSummary" and not child.is_queued_for_deletion(): found.append(child)
 return found
func dialog_with(text: String):
 for d in dialogs():
  if text in texts(d): return d
 return null
# The card sheet (inspect view) is a CanvasLayer overlay on the table.
func sheet():
 if not is_instance_valid(table): return null
 for child in table.get_children():
  if child is CanvasLayer and child.is_in_group("touch_modal") and not child.is_queued_for_deletion(): return child
 return null
func card_button(zone: String, uid: int = -1):
 for b in buttons(table, []):
  var box = b.get_parent()
  if box != null and box.get_meta("zone", "") == zone and (uid < 0 or box.get_meta("card_uid", -1) == uid) and b.is_visible_in_tree(): return b
 return null
func is_auto(b) -> bool:
 return b is Button and (b.name == "AutoActivate" or b.text.begins_with("Auto:"))
func autos(node) -> Array:
 return buttons(node, []).filter(func(b): return is_auto(b) and b.is_visible_in_tree())
func raw_tokens(text: String) -> bool:
 return "{H}" in text or "{D}" in text
func key(code: Key):
 for pressed in [true, false]:
  var event = InputEventKey.new()
  event.keycode = code
  event.physical_keycode = code
  event.pressed = pressed
  root.push_input(event)
# Delivers a window notification the way Window::_propagate_window_notification does: plain notification() down
# the tree, skipping sub-windows. (Node.propagate_notification blocks add_child while it runs; the real one doesn't.)
func deliver(node: Node, what: int):
 node.notification(what)
 var i = 0
 while i < node.get_child_count(true):
  var child = node.get_child(i, true)
  if not child is Window: deliver(child, what)
  i += 1
func back_button():
 deliver(root, Node.NOTIFICATION_WM_GO_BACK_REQUEST)
func hover(point: Vector2):
 var event = InputEventMouseMotion.new()
 event.position = point
 event.global_position = point
 root.push_input(event)
func right_click(point: Vector2):
 hover(point)
 for pressed in [true, false]:
  var event = InputEventMouseButton.new()
  event.button_index = MOUSE_BUTTON_RIGHT
  event.position = point
  event.global_position = point
  event.pressed = pressed
  root.push_input(event)
func new_table(options: Dictionary = {}):
 table = load("res://scenes/table.tscn").instantiate()
 table.auto_drive = false
 table.bot_pace = 0
 table.seed_value = options.get("seed", 7)
 table.tutorial_mode = options.get("tutorial", false)
 root.add_child(table)
 current_scene = table
 await frames(6)
 while not table.tutorial_mode and table.engine.active().is_bot: await table.drive_reaction(table.engine.active())
 await frames()
func clear_scene():
 for node in root.get_children():
  if not ProjectSettings.has_setting("autoload/" + node.name): node.queue_free()
 current_scene = null
 table = null
 await frames(4)
# Reachable state for TOCTOU: you are at 1 life, your next hand is TOCTOU + 4 Hackers, and the bot holds an Attack.
func toctou_setup(base_uid: int):
 var p = table.engine.state.players[0]
 p.life = 1
 p.deck.assign([CardInstance.new(base_uid, "TOCTOU", 0)] + range(1, 5).map(func(i): return CardInstance.new(base_uid + i, "Hacking", 0)))
 table.engine.state.players[1].hand.assign([CardInstance.new(base_uid + 9, "Damage", 1)])

# ---------- checks ----------
func run():
 OS.add_logger(errors)
 var started = Time.get_ticks_msec()
 var backup = user_files()
 style = load("res://scripts/ui/style.gd")
 settings = root.get_node("Sfx")
 root.size = Vector2i(1920, 1080)
 settings.visual_effects = false
 settings.auto_end_turn = false
 settings.confirm_end_turn = true
 b38_close_request(backup)
 await b15_settings_reads(backup)
 await b10_b42_permanents()
 await b25_log_names(backup)
 await b14_summary_back()
 await b28_tutorial_back()
 await b29_reaction_viewers()
 await b17_stacked_dialogs()
 await b43_connections()
 style.compact_override = null
 restore_user_files(backup)
 errors.section = "end"
 if errors.count > 0:
  print("Engine/script errors logged: %d, by section %s" % [errors.count, errors.by_section])
  for text in errors.messages: print("  %dx %s" % [errors.messages[text], text])
 print("Table bug checks: %d checks, %d failures (%.1f s)" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
 quit(1 if failures else 0)

# B38: the window close button while a prompt is open. get_tree().quit() ends the process, so a helper runs the
# table in a subprocess. Fix-agnostic: quitting at once, asking first, or acting once the prompt is answered all
# pass; only "still running with nothing new on screen after the prompt is answered" fails.
func helper(mode: String) -> Dictionary:
 var output = []
 var code = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/bugs_table_helper_close.gd", "--", mode], output, true)
 return {"code": code, "text": "\n".join(output)}
func b38_close_request(backup: Dictionary):
 errors.section = "B38"
 var quiet = helper("noprompt")
 restore_user_files(backup)
 verify(quiet.code == 0 and "HELPER_CLOSE_SENT" in quiet.text and not ("HELPER_CLOSE_LOST" in quiet.text or "HELPER_RESPONDED" in quiet.text or "HELPER_WATCHDOG" in quiet.text), "control: with no prompt open, the window close button quits the game")
 var busy = helper("prompt")
 restore_user_files(backup)
 verify("HELPER_PROMPT_OPEN [\"End your turn?" in busy.text, "control: the close helper had the End-turn prompt open when it pressed close")
 verify("HELPER_CLOSE_SENT" in busy.text and not "HELPER_CLOSE_LOST" in busy.text and not "HELPER_WATCHDOG" in busy.text, "B38 The window close button isn't silently dropped while a prompt is open (the game quits or asks, at the latest once the prompt is answered)")

# B15: UIStyle.compact() opens and parses user://settings.cfg on every call, hundreds of times per phone redraw.
# Fix-agnostic and timing-free: count read(2)-family syscalls (/proc/self/io "syscr", Linux) across one redraw
# caused by the toolbar Log button. Today ~2,400; a redraw that doesn't re-read the file per node needs a handful.
# Any cache must still follow the in-game Layout picker, which the controls check.
func read_calls() -> int:
 var file = FileAccess.open("/proc/self/io", FileAccess.READ)
 if file == null: return -1
 while not file.eof_reached():
  var line = file.get_line()
  if line.begins_with("syscr:"): return int(line.get_slice(":", 1).strip_edges())
 return -1
func pick_layout(index: int):
 table.menu_button.pressed.emit()
 await frames()
 var picker = null
 for node in table.game_menu.find_children("*", "OptionButton", true, false):
  if node.item_count == 3 and node.get_item_text(2) == "Layout: Phone": picker = node
 picker.select(index)
 picker.item_selected.emit(index)
 button(table.game_menu, "Resume").pressed.emit()
 await frames()
# One redraw from a real button: Log opens the log drawer (and redraws); a second press puts it back.
func log_redraw_reads() -> int:
 var log_button = button(table, "Log")
 var before = read_calls()
 log_button.pressed.emit()
 await frames(2)
 var used = read_calls() - before
 log_button.pressed.emit()
 await frames(2)
 return used
func b15_settings_reads(backup: Dictionary):
 errors.section = "B15"
 style.compact_override = null
 await new_table()
 table.engine.state.players[0].play_area.append(CardInstance.new(99001, "Botnet", 0))
 table.redraw()
 await frames()
 await pick_layout(2)
 var reads = await log_redraw_reads()
 verify(button(table, "Rig: 1") != null, "control: Layout: Phone in the in-game menu switches the table to the phone board")
 if reads < 0: print("SKIP B15: /proc/self/io is not readable on this system")
 else:
  verify(reads < 100, "B15 A phone-layout redraw doesn't re-read settings.cfg for every node (%d read calls for one redraw)" % reads)
  style.compact_override = true
  var held = await log_redraw_reads()
  style.compact_override = null
  verify(held < 100, "control: with the layout held in memory, the same redraw makes few read calls (%d)" % held)
 await pick_layout(1)
 table.redraw()
 await frames()
 verify(button(table, "Rig: 1") == null and card_button("permanent", 99001) != null, "control: Layout: Desktop in the in-game menu switches the table back")
 await clear_scene()
 restore_user_files(backup)

# B10 + B42: a permanent with an Auto toggle and abilities whose text has {H}/{D} (Botnet, F.O.T.T.R. Greatest Hits).
func ability_buttons() -> Array:
 return buttons(sheet(), []).filter(func(b): return b.is_visible_in_tree() and b.text != "Close" and not is_auto(b))
# The small ability buttons under each permanent in the desktop rig (everything in the card's box but its art and Auto).
func rig_ability_buttons() -> Array:
 var found = []
 for box in table.find_children("*", "Control", true, false):
  if box.get_meta("zone", "") != "permanent": continue
  for b in buttons(box, []):
   if b != box.get_child(0) and not is_auto(b) and b.is_visible_in_tree(): found.append(b)
 return found
func b10_b42_permanents():
 errors.section = "B10/B42"
 style.compact_override = false
 await new_table()
 var p = table.engine.state.players[0]
 p.play_area.append(CardInstance.new(99101, "Botnet", 0))
 p.play_area.append(CardInstance.new(99102, "FOTTR Greatest Hits", 0))
 table.redraw()
 await frames()
 verify(not autos(table).is_empty(), "control: the desktop rig shows Botnet's Auto toggle")
 var tooltips = rig_ability_buttons().map(func(b): return b.tooltip_text)
 verify(tooltips.size() == 2 and not tooltips.any(raw_tokens), "B42 The rig's ability buttons (Activate) show no raw {H}/{D} tokens in their tooltips")
 var labels = []
 for uid in [99101, 99102]:
  card_button("permanent", uid).pressed.emit()
  await frames()
  labels.append_array(ability_buttons().map(func(b): return b.text))
  if sheet() != null: button(sheet(), "Close").pressed.emit()
  await frames()
 verify(labels.size() == 2, "control: clicking Botnet and F.O.T.T.R. Greatest Hits in the desktop rig opens sheets with their ability buttons")
 verify(not labels.is_empty() and not labels.any(raw_tokens), "B42 Ability buttons in the card sheet show no raw {H}/{D} tokens (desktop)")
 style.compact_override = true
 table.redraw()
 await frames()
 var on_table = not autos(table).is_empty()
 button(table, "Rig: 2").pressed.emit()
 await frames()
 var viewer = dialog_with("Your rig & reserved")
 var viewer_opened = viewer != null
 var in_viewer = viewer_opened and not autos(viewer).is_empty()
 if viewer_opened:
  for b in buttons(viewer, []):
   if b.has_meta("uid") and b.get_meta("uid") == 99101: b.pressed.emit(); break
 await frames()
 var in_sheet = sheet() != null and not autos(sheet()).is_empty()
 var phone_labels = ability_buttons().map(func(b): return b.text) if sheet() != null else []
 verify(viewer_opened and sheet() != null and not phone_labels.is_empty(), "control: on the phone, Open board opens the viewer and tapping Botnet opens its sheet")
 verify(on_table or in_viewer or in_sheet, "B10 Phone layout: Botnet's Auto toggle can be reached on the table, in the Open board viewer or in its card sheet")
 verify(not phone_labels.is_empty() and not phone_labels.any(raw_tokens), "B42 Ability buttons in the card sheet show no raw {H}/{D} tokens (phone)")
 await clear_scene()

# B25: append_log swaps "Seat %d" for names one seat at a time, so a handle like "Seat 1" is rewritten again.
func log_lines() -> Array:
 return Array(table.log_view.get_parsed_text().split("\n", false)).map(func(line): return line.trim_prefix("> ").strip_edges())
func b25_log_names(backup: Dictionary):
 errors.section = "B25"
 style.compact_override = false
 var old_handle = settings.handle
 var old_hero = settings.hero_id
 for handle in ["Neo", "Seat 1"]:
  # Type the handle into the main menu's handle field.
  var menu = load("res://scenes/menu.tscn").instantiate()
  root.add_child(menu)
  await frames()
  for field in menu.find_children("*", "LineEdit", true, false):
   if field.placeholder_text == "You":
    field.text = handle
    field.text_changed.emit(handle)
  menu.queue_free()
  await frames()
  await new_table()
  var p = table.engine.state.players[0]
  var seen = log_lines().size()
  var hacker = p.hand.filter(func(c): return c.id == "Hacking")[0]
  card_button("hand", hacker.uid).pressed.emit()
  await frames()
  var played = log_lines().slice(seen).filter(func(line): return "plays Hacker" in line)
  var shown = played[0] if not played.is_empty() else "(nothing logged)"
  if handle == "Neo": verify(shown == "Neo plays Hacker", "control: with the handle Neo, your Hacker is logged as \"Neo plays Hacker\" (got \"%s\")" % shown)
  else: verify(shown == "Seat 1 plays Hacker", "B25 With the handle \"Seat 1\", your Hacker is logged under your name, not a bot's (got \"%s\")" % shown)
  await clear_scene()
 settings.handle = old_handle
 settings.hero_id = old_hero
 restore_user_files(backup)

# B14: Escape / Back on the end-of-game summary opens the in-game menu at z 0 under the summary (z 50). Godot routes
# clicks by tree order, not z_index, so the invisible menu takes them. Fix-agnostic: whatever the pointer reaches over
# a summary button must be drawn at or above the summary (no menu, a menu on top, or leaving all pass).
func draw_rank(item) -> Vector2i:
 var layer = 0
 var z = 0
 var relative = true
 var node = item
 while node != null:
  if node is CanvasLayer:
   layer = node.layer
   break
  if node is CanvasItem and relative:
   z += node.z_index
   relative = node.z_as_relative
  node = node.get_parent()
 return Vector2i(layer, z)
func drawn_over(item, summary) -> bool:
 if item == null or not is_instance_valid(summary) or not summary.is_inside_tree(): return true
 if item == summary or summary.is_ancestor_of(item): return true
 var a = draw_rank(item)
 var b = draw_rank(summary)
 return a.x > b.x or (a.x == b.x and a.y >= b.y)
func pointer_target(point: Vector2):
 hover(point)
 await frames(2)
 return root.gui_get_hovered_control()
# Plays to the end-of-game summary: the bot is down to 1 life and your Attack knocks it out (moved into your hand
# from your own deck if the opening hand has none). Returns the summary, or null.
func summary_on_screen():
 await new_table()
 var p = table.engine.state.players[0]
 table.engine.state.players[1].life = 1
 var attack = p.hand.filter(func(c): return c.id == "Damage")
 if attack.is_empty():
  attack = p.deck.filter(func(c): return c.id == "Damage") + p.discard.filter(func(c): return c.id == "Damage")
  for pile in [p.deck, p.discard]: pile.erase(attack[0])
  p.hand.append(attack[0])
  table.redraw()
  await frames()
 card_button("hand", attack[0].uid).pressed.emit()
 await frames(8)
 return table.get_node_or_null("MatchSummary")
func b14_summary_back():
 errors.section = "B14"
 style.compact_override = false
 for way in ["Escape", "Back"]:
  var summary = await summary_on_screen()
  var target = button(summary, "View final deck") if summary != null else null
  var point = target.get_global_rect().get_center() if target != null else Vector2.ZERO
  var reached = null
  if target != null: reached = await pointer_target(point)
  verify(target != null and (reached == target or target.is_ancestor_of(reached)), "control: knocking out the last bot shows the summary, and the pointer over View final deck reaches it (before %s)" % way)
  if way == "Escape": key(KEY_ESCAPE)
  else: back_button()
  await frames()
  var after = null
  if target != null: after = await pointer_target(point)
  verify(target != null and drawn_over(after, summary), "B14 %s on the match summary doesn't open a hidden menu that takes the summary's clicks" % way)
  await clear_scene()

# B28: in the tutorial, Back / Escape skips the coach before it closes an open card or prompt (table.gd go_back).
# Escape with nothing open skipping the tutorial is intended (tests/v15_checks.gd) and stays a control.
func coach():
 return table.tutorial_coach
# Follows the coach's own steps with real input until step 10 ("Open the log"), with the card opened at step 9.
func tutorial_to_card() -> bool:
 await new_table({"tutorial": true})
 for guard in 40:
  if sheet() != null or not coach().visible: break
  var caption = coach().caption.text
  var next = button(coach(), "Next")
  var hand = buttons(table, []).filter(func(b): return b.get_parent() != null and b.get_parent().get_meta("zone", "") == "hand" and b.is_visible_in_tree())
  if next != null and not next.disabled: next.pressed.emit()
  elif "Play a Hacker" in caption: hand[-1].pressed.emit()
  elif "Buy an affordable card" in caption:
   for b in buttons(table, []):
    if b.get_parent() != null and b.get_parent().get_meta("zone", "") == "market" and b.find_child("LegalBadge", false, false) != null:
     b.pressed.emit()
     await frames()
     button(sheet(), "Buy").pressed.emit()
     break
  elif "Inspect a card" in caption: right_click(hand[-1].get_global_rect().get_center())
  await frames(3)
 return sheet() != null and coach().visible and coach().caption.text.begins_with("10 / 13")
func b28_tutorial_back():
 errors.section = "B28"
 style.compact_override = false
 settings.confirm_end_turn = true
 await new_table()
 table.end_button.pressed.emit()
 await frames()
 var asked = dialog_with("End your turn?") != null
 key(KEY_ESCAPE)
 await frames()
 verify(asked and dialog_with("End your turn?") == null and table.banner.text.begins_with("Your turn"), "control: outside the tutorial, Escape answers the End-turn prompt with Keep playing")
 await clear_scene()
 await new_table({"tutorial": true})
 key(KEY_ESCAPE)
 await frames()
 verify(not coach().visible, "control: in the tutorial, Escape with nothing open still skips the tutorial")
 await clear_scene()
 var reached = await tutorial_to_card()
 verify(reached, "control: following the tutorial's steps (right-click a card at step 9) reaches step 10 with the card open")
 key(KEY_ESCAPE)
 await frames()
 verify(reached and sheet() == null and coach().visible, "B28 In the tutorial, Escape closes the open card first and keeps the tutorial going")
 await clear_scene()
 reached = await tutorial_to_card()
 if reached:
  button(sheet(), "Close").pressed.emit()
  await frames()
  button(coach(), "Next").pressed.emit()
  await frames()
  table.end_button.pressed.emit() # step 11 says "Tap End Turn now"; four Hackers are still playable
  await frames()
 var prompt = reached and dialog_with("End your turn?") != null and coach().caption.text.begins_with("11 / 13")
 verify(prompt, "control: at the tutorial's End Turn step, End Turn with cards left asks to confirm")
 key(KEY_ESCAPE)
 await frames()
 verify(prompt and dialog_with("End your turn?") == null and coach().visible, "B28 In the tutorial, Escape answers the open End-turn prompt and keeps the tutorial going")
 if dialog_with("End your turn?") != null: button(dialog_with("End your turn?"), "Keep playing").pressed.emit()
 await clear_scene()

# B29: TOCTOU's extra turn runs inside the bot's turn, so the table's "bot is playing" state stays set and the phone
# viewers refuse to open. Only the viewers are tested; auto-end being off in that turn is deliberate.
func b29_reaction_viewers():
 errors.section = "B29"
 style.compact_override = true
 settings.confirm_end_turn = false
 await new_table()
 var p = table.engine.state.players[0]
 toctou_setup(99300)
 p.play_area.append(CardInstance.new(99301, "Bribery", 0))
 p.reserve.append(CardInstance.new(99302, "c14ud3", 0))
 table.redraw()
 await frames()
 button(table, "Rig: 1").pressed.emit()
 await frames()
 verify(dialog_with("Your rig & reserved") != null, "control: on a normal turn, Open board opens your rig & reserved cards (phone)")
 key(KEY_ESCAPE)
 await frames()
 table.auto_drive = true
 table.end_button.pressed.emit()
 var asked = await wait_until(func(): return dialog_with("Use TOCTOU") != null)
 if asked: button(dialog_with("Use TOCTOU"), "Yes").pressed.emit()
 var saved = await wait_until(func(): return table.banner.text.begins_with("Your turn") and not table.end_button.disabled)
 verify(asked and saved, "control: TOCTOU saves you during the bot's turn and gives you a turn with End Turn enabled")
 button(table, "Rig: 1").pressed.emit()
 await frames()
 var board = dialog_with("Your rig & reserved")
 verify(saved and board != null, "B29 During a TOCTOU reaction turn, Open board opens your rig & reserved cards (phone)")
 if board != null: key(KEY_ESCAPE)
 await frames()
 button(table, "Deck ").pressed.emit()
 await frames()
 var pile = dialog_with("Your discard")
 verify(saved and pile != null, "B29 During a TOCTOU reaction turn, the Deck / Discard button opens your discard pile (phone)")
 if pile != null: key(KEY_ESCAPE)
 await frames()
 table.end_button.pressed.emit()
 await wait_until(func(): return not table.driving and not table.engine.busy)
 await clear_scene()

# B17: decision() has one shared "answered" signal and no guard, so a second dialog opened while one is waiting is
# answered together with it. Here: Leave without saving? is open during the bot's turn when the bot's Attack makes
# TOCTOU ask you. Assumes leaving mid-bot-turn keeps asking first, as it does today.
func b17_stacked_dialogs():
 errors.section = "B17"
 style.compact_override = false
 settings.confirm_end_turn = false
 await new_table()
 var p = table.engine.state.players[0]
 toctou_setup(99400)
 table.redraw()
 await frames()
 # Slow the bot to 1 s per card from the toolbar, so the menu can be opened while it plays.
 table.speed_button.pressed.emit()
 await frames()
 var pace = table.pace_popup.find_child("BotPace", true, false)
 pace.select(3)
 pace.item_selected.emit(3)
 table.auto_drive = true
 table.end_button.pressed.emit()
 await wait_until(func(): return "is hacking" in table.banner.text)
 await frames(2)
 table.menu_button.pressed.emit()
 await frames(1)
 button(table.game_menu, "Main menu").pressed.emit()
 await frames(1)
 verify(dialog_with("Leave without saving?") != null and p.alive and p.life == 1 and dialog_with("Use TOCTOU") == null, "control: during the bot's turn, Main menu asks Leave without saving? before the bot attacks")
 var asked = await wait_until(func(): return is_instance_valid(table) and dialog_with("Use TOCTOU") != null)
 var errors_before = errors.count
 if asked: button(dialog_with("Use TOCTOU"), "Yes").pressed.emit()
 await frames(6)
 var raised = errors.count - errors_before
 var stayed = is_instance_valid(table) and table.is_inside_tree() and current_scene == table
 verify(stayed, "B17 Answering TOCTOU's prompt doesn't also answer Leave without saving? (the game stays open)")
 verify(stayed and dialog_with("Leave without saving?") != null, "B17 Leave without saving? is still waiting after TOCTOU's prompt is answered")
 # Today the extra turn starts on a table that has already left the tree, and every redraw throws.
 verify(asked and raised == 0, "B17 Answering TOCTOU's prompt raises no script errors (%d logged)" % raised)
 if stayed:
  var stay = button(dialog_with("Leave without saving?"), "Stay") if dialog_with("Leave without saving?") != null else null
  if stay != null: stay.pressed.emit()
  await frames()
  table.bot_pace = 0
  if table.end_button != null and not table.end_button.disabled: table.end_button.pressed.emit()
  await wait_until(func(): return not table.driving and not table.engine.busy)
 await clear_scene()

# B43: every card move runs UIStyle.animation(banner), which connects a lambda to Sfx.visuals_changed that is only
# released when the banner (alive for the whole game) leaves the tree. Over 5 rounds of real play the count must
# stay bounded; live tweens (pulses, spotlights, turn bands) legitimately add a few, so the bound is generous.
func connections() -> int:
 return settings.get_signal_connection_list("visuals_changed").size()
func b43_connections():
 errors.section = "B43"
 style.compact_override = false
 settings.visual_effects = true
 settings.confirm_end_turn = false
 await new_table({"seed": 12345})
 var engine = table.engine
 # Prompts aimed at you during bot turns are answered by a bot decider; your own moves still come from the buttons.
 engine.deciders[0] = BotDecider.new(engine, 0)
 engine.card_moved.connect(func(_c, _from, _to): moves += 1)
 table.auto_drive = true
 var counts = []
 var moved = []
 for turn_index in 7:
  var mine = await wait_until(func(): return engine.state.finished or (table.banner.text.begins_with("Your turn") and not table.end_button.disabled and not table.driving and not engine.busy))
  if not mine or engine.state.finished: break
  await frames(2)
  counts.append(connections())
  moved.append(moves)
  table.play_button.pressed.emit()
  await wait_until(func(): return not table.acting)
  table.end_button.pressed.emit()
  await frames(2)
 var made = moved[-1] - moved[1] if moved.size() >= 3 else 0
 var grew = counts[-1] - counts[1] if counts.size() >= 3 else 0
 verify(made >= 150, "control: five rounds of real play move at least 150 cards (%d)" % made)
 verify(made >= 150 and grew < 50, "B43 Sfx.visuals_changed connections stay bounded over %d card moves (grew by %d)" % [made, grew])
 settings.visual_effects = false
 await clear_scene()
