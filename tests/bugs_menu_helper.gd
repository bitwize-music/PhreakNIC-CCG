extends SceneTree
## Subprocess for tests/bugs_menu_checks.gd (B12, B13, B55). Some of these inputs make the game call
## get_tree().quit() or hang, which would also end or stall the calling suite, so each scenario runs in its own
## process. It prints MARKER only if the game is still running after the input; the suite reads the output.
## The suite points XDG_DATA_HOME at an empty scratch directory and restores user:// files afterwards.
## Guards, so a hang can never stall CI or flood a disk:
##  - LoopGuard ends the process at the 50th error: an endless error loop never yields, but logs synchronously.
##  - A 20 s SceneTree timer quits a scenario that keeps running frames but never finishes.
##  - The knockout scenarios add a watchdog thread that kills the process after 25 s, even with no errors.
const MARKER = "BUGS_MENU_HELPER ALIVE"
class LoopGuard extends Logger:
 var count = 0
 func _log_error(_f: String, _file: String, _line: int, _code: String, _rationale: String, _notify: bool, _type: int, _traces: Array[ScriptBacktrace]) -> void:
  count += 1
  if count == 50:
   printerr("BUGS_MENU_HELPER LOOP")
   OS.kill(OS.get_process_id())
var guard = LoopGuard.new()
var watchdog: Thread
var watchdog_stop = false
func _initialize(): call_deferred("run")
func frames(n = 4):
 for i in n: await process_frame
func find_button(node, text):
 if node is Button and node.text == text and node.is_visible_in_tree(): return node
 for child in node.get_children():
  var found = find_button(child, text)
  if found != null: return found
 return null
## Android Back as the engine delivers it: Window::_propagate_window_notification notifies the window, then
## every child in order (internal ones too), skipping native sub-windows. Unlike Node.propagate_notification
## it does not lock the tree, so handlers may add or free nodes.
func deliver_back(node: Node):
 node.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
 var i = 0
 while i < node.get_child_count(true):
  var child = node.get_child(i, true)
  if not (child is Window and not child.is_embedded()): deliver_back(child)
  i += 1
func escape():
 for down in [true, false]:
  var event = InputEventKey.new()
  event.keycode = KEY_ESCAPE
  event.physical_keycode = KEY_ESCAPE
  event.pressed = down
  Input.parse_input_event(event)
## A real mouse click: queued like OS input, so it is handled before the next frame's process_frame.
func tap(control: Control):
 var point = control.get_global_rect().get_center()
 for down in [true, false]:
  var event = InputEventMouseButton.new()
  event.button_index = MOUSE_BUTTON_LEFT
  event.pressed = down
  event.position = point
  event.global_position = point
  Input.parse_input_event(event)
func start_watchdog(seconds: float):
 watchdog = Thread.new()
 watchdog.start(func():
  var deadline = Time.get_ticks_msec() + int(seconds * 1000)
  while not watchdog_stop and Time.get_ticks_msec() < deadline: OS.delay_msec(100)
  if not watchdog_stop:
   printerr("BUGS_MENU_HELPER WATCHDOG")
   OS.kill(OS.get_process_id()))
func stop_watchdog():
 if watchdog != null and watchdog.is_started():
  watchdog_stop = true
  watchdog.wait_to_finish()
func finish(code: int):
 stop_watchdog()
 quit(code)
func run():
 OS.add_logger(guard)
 create_timer(20.0).timeout.connect(func(): print("BUGS_MENU_HELPER TIMEOUT"); finish(3))
 var args = OS.get_cmdline_user_args()
 var scenario = args[0] if not args.is_empty() else ""
 print("BUGS_MENU_HELPER START ", scenario)
 var style = load("res://scripts/ui/style.gd")
 root.get_node("Sfx").visual_effects = false
 root.size = Vector2i(1920, 1080)
 if scenario.begins_with("knockout"):
  await knockout(scenario == "knockout-slow")
  finish(0)
  return
 # Android phones use the phone layout; the web check is a desktop browser.
 style.compact_override = scenario == "stats-back"
 # The browser build, switched on the way tests/v07_checks.gd does it.
 style.web_override = true if scenario == "web-escape" else null
 var menu = load("res://scenes/menu.tscn").instantiate()
 root.add_child(menu)
 current_scene = menu
 await frames()
 match scenario:
  "stats-back":
   find_button(menu, "Stats").pressed.emit()
   await frames()
   deliver_back(root)
   await frames()
   print(MARKER, " stats_open=", menu.has_node("LifetimeStats"))
  "web-escape":
   var quit_button = menu.find_children("*", "Button", true, false).filter(func(b): return b.text == "Quit")
   print("BUGS_MENU_HELPER WEB quit_visible=", not quit_button.is_empty() and quit_button[0].visible)
   escape()
   await frames()
   print(MARKER)
  "controls":
   find_button(menu, "Stats").pressed.emit()
   await frames()
   escape()
   await frames()
   var stats_open = menu.has_node("LifetimeStats")
   find_button(menu, "Decks (experimental)").pressed.emit()
   await frames()
   deliver_back(root)
   await frames()
   var builder_open = menu.get_children().any(func(child): return child.get_script() == load("res://scripts/ui/deck_builder.gd") and not child.is_queued_for_deletion())
   print(MARKER, " stats_open=", stats_open, " builder_open=", builder_open)
  "quit-button":
   find_button(menu, "Quit").pressed.emit()
   await frames()
   print(MARKER)
 finish(0)
## B55: knocked out of a 3-player offline game with Bot pace Instant, then Menu > Main menu > Leave.
## With slow = true the player first picks the slowest Bot pace in the same menu (the control).
func knockout(slow: bool):
 start_watchdog(25.0)
 var sfx = root.get_node("Sfx")
 sfx.auto_end_turn = false
 sfx.confirm_end_turn = false
 sfx.auto_activate.clear()
 sfx.bot_pace = 0.0 # Bot pace: Instant
 var table = load("res://scenes/table.tscn").instantiate()
 table.player_count = 3
 table.difficulty = 1 # Phreak bots aim at the opponent with the least life
 table.seed_value = 11
 root.add_child(table)
 current_scene = table
 var human = table.engine.state.players[0]
 for i in 600:
  if table.available(): break
  await process_frame
 # Fast-forward: you have been worn down to 1 life. End your turn and the bots knock you out.
 human.life = 1
 table.engine.state_changed.emit()
 table.end_button.pressed.emit()
 for i in 1500:
  if not human.alive or table.engine.state.finished: break
  await process_frame
 print("BUGS_MENU_HELPER KNOCKED_OUT ", not human.alive and not table.engine.state.finished)
 table.menu_button.pressed.emit()
 await frames(2)
 if slow:
  var pace = table.game_menu.find_children("BotPace", "OptionButton", true, false)[0]
  pace.select(pace.item_count - 1)
  pace.item_selected.emit(pace.item_count - 1)
  await frames(3)
 find_button(table.game_menu, "Main menu").pressed.emit()
 await frames(2)
 var leave = find_button(table, "Leave")
 if leave != null: tap(leave)
 await frames(10)
 print(MARKER, " main_menu=", current_scene != null and current_scene.get_script() == load("res://scripts/ui/menu.gd"))
