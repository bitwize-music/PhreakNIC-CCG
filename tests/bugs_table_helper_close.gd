extends SceneTree
# Subprocess for tests/bugs_table_checks.gd (B38). The table quits with get_tree().quit(), which a test can only
# observe from outside, so the main suite runs this script with OS.execute and reads its markers and exit code.
# Mode "noprompt" presses the window close button on a quiet turn of yours; mode "prompt" presses it while the
# End-turn confirmation is open. Markers: HELPER_PROMPT_OPEN, HELPER_CLOSE_SENT, HELPER_RESPONDED (a new dialog
# answered the close), HELPER_CLOSE_LOST (still running, nothing new on screen; exit 7), HELPER_WATCHDOG (exit 9).
# If the game quits, no marker follows HELPER_CLOSE_SENT and the exit code is 0.
var table
func _initialize(): call_deferred("run")
func frames(n = 4):
 for i in n: await process_frame
func buttons(node, found = []) -> Array:
 if node is Button: found.append(node)
 for child in node.get_children(): buttons(child, found)
 return found
func button(node, prefix: String):
 for b in buttons(node, []):
  if b.text.begins_with(prefix) and b.is_visible_in_tree(): return b
 return null
func prompts() -> Array:
 var found = []
 for child in table.get_children():
  if child is PanelContainer and child.is_in_group("touch_modal") and child.name != "MatchSummary" and not child.is_queued_for_deletion():
   var text = ""
   for label in child.find_children("*", "RichTextLabel", true, false): text += label.get_parsed_text()
   found.append(text)
 return found
# Delivers a window notification the way Window::_propagate_window_notification does: plain notification() down
# the tree, skipping sub-windows. (Node.propagate_notification blocks add_child while it runs; the real one doesn't.)
func deliver(node: Node, what: int):
 node.notification(what)
 var i = 0
 while i < node.get_child_count(true):
  var child = node.get_child(i, true)
  if not child is Window: deliver(child, what)
  i += 1
func responded(before: Array) -> bool:
 for text in prompts():
  if text not in before: return true
 return false
func run():
 create_timer(60).timeout.connect(func(): print("HELPER_WATCHDOG"); quit(9))
 var args = OS.get_cmdline_user_args()
 var mode = args[0] if not args.is_empty() else "prompt"
 load("res://scripts/ui/style.gd").compact_override = false
 root.size = Vector2i(1920, 1080)
 var settings = root.get_node("Sfx")
 settings.auto_end_turn = false
 settings.confirm_end_turn = true
 settings.visual_effects = false
 table = load("res://scenes/table.tscn").instantiate()
 table.auto_drive = false
 table.bot_pace = 0
 table.seed_value = 7
 root.add_child(table)
 current_scene = table
 await frames()
 while table.engine.active().is_bot: await table.drive_reaction(table.engine.active())
 await frames()
 var before = []
 if mode == "prompt":
  # A fresh hand still has playable cards, so End Turn asks "End your turn? ...".
  table.end_button.pressed.emit()
  await frames()
  before = prompts()
  print("HELPER_PROMPT_OPEN ", before)
 print("HELPER_CLOSE_SENT")
 # What the window manager's close button delivers: the root window passes the notification to every node.
 deliver(root, Node.NOTIFICATION_WM_CLOSE_REQUEST)
 await frames(10)
 if responded(before):
  print("HELPER_RESPONDED ", prompts())
  quit(0)
  return
 # Still here: the player answers the prompt that was open, as they would, and waits.
 var keep = button(table, "Keep playing")
 if keep != null:
  keep.pressed.emit()
  await frames(10)
  if responded([]):
   print("HELPER_RESPONDED ", prompts())
   quit(0)
   return
 print("HELPER_CLOSE_LOST ", prompts())
 quit(7)
