extends SceneTree
# Whole-project hunt reproductions; use a fresh XDG_DATA_HOME.
var checks = 0
var failures = 0
class PreferSecond extends Decider:
 var choices: Array = []
 func choose_option(_p, prompt: String, options: Array[String]) -> int:
  choices.append({"prompt":prompt, "options":options.duplicate()})
  return mini(1, options.size() - 1)
func _initialize(): run.call_deferred()
func verify(ok: bool, description: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(description)
func named_button(node: Node, prefix: String):
 if node is Button and node.text.begins_with(prefix): return node
 for child in node.get_children():
  var found = named_button(child, prefix)
  if found != null: return found
 return null
func duplicate_triggers(danger_first: bool):
 var e = GameEngine.new()
 root.add_child(e)
 var deck = JSON.parse_string(FileAccess.get_file_as_string("res://data/starter_decks.json"))[0]
 deck.cards["The Juice"] = 2
 verify(CustomDeck.validate(deck).is_empty(), "control: two copies of The Juice are valid in this custom deck")
 var choice = PreferSecond.new()
 e.setup([-1, 0], 91, [choice, Decider.new()], "custom", 20, [], deck)
 var juices = e.state.all_cards().filter(func(c): return c.id == "The Juice")
 var p = e.state.players[0]
 var q = e.state.players[1]
 for i in 2:
  var c = juices[i]
  e.gain_owner(c, p)
  e.move(c, p.play_area, "play_area")
  c.counters = (4 if i == 0 else 0) if danger_first else (0 if i == 0 else 4)
 q.life = 1
 # Remove any unrelated opening Rickroll trigger without creating/destroying cards.
 for c in e.state.center_row.duplicate():
  if c != null and c.id == "Rickroll": e.remove(c)
 verify(e.state.conservation_ok(), "control: simultaneous-trigger fixture conserves all cards")
 await e.start_turn(0)
 var result = {"winner":e.state.winner.seat if e.state.winner != null else -1, "choices":choice.choices.size()}
 print("Duplicate-trigger evidence: dangerous copy first=%s, result=%s" % [danger_first, result])
 e.free()
 return result
func custom_avatar_save():
 var settings = root.get_node("Sfx")
 settings.card_pool = "custom"
 var menu = load("res://scenes/menu.tscn").instantiate()
 root.add_child(menu)
 var hero = "JousterL@mog"
 verify(hero in load("res://scripts/ui/style.gd").heroes(), "control: the real custom-set Hero picker offers MogsterL")
 menu.select_hero(hero)
 var base = named_button(menu, "Base Set —")
 verify(base != null, "control: the real menu offers the base-set switch")
 base.pressed.emit()
 verify(settings.card_pool == "2025" and settings.hero_id == hero, "control: switching set preserves the chosen custom Hero ID")
 menu.launch()
 var table = current_scene
 table.auto_drive = false
 await process_frame
 await table.engine.start_turn(0)
 await process_frame
 verify(table.can_save() and table.engine.state.conservation_ok(), "control: a normal local game reaches a valid save point")
 verify(table.save_game(), "control: Save game reports a successful disk write")
 var first = SaveGame.read()
 var raw = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
 verify(SaveGame.restore(raw.game) != null and SaveGame.valid_match_stats(raw.table), "control: saved rules state and match statistics are valid")
 print("Custom Hero save evidence: pool=%s, hero=%s, saved=%s, readable=%s" % [table.engine.state.card_pool, table.seat_heroes[0], FileAccess.file_exists(SaveGame.PATH), not first.is_empty()])
 verify(not first.is_empty(), "W31-02: a Hero chosen in the UI must not make subsequent base-set saves unreadable")
 # Isolate the avatar metadata: same live game, same stats, same save implementation.
 table.seat_heroes[0] = "JousterL"
 verify(table.save_game() and not SaveGame.read().is_empty(), "control: changing only the avatar ID to its original printing makes the save readable")
 table.queue_free()
 await process_frame
func run():
 root.get_node("Sfx").visual_effects = false
 root.get_node("Sfx").auto_end_turn = false
 var control = await duplicate_triggers(false)
 verify(control.winner == 0, "control: resolving the low-counter Juice first wins before the fifth-counter loss")
 var actual = await duplicate_triggers(true)
 verify(actual.choices == 1, "W31-03: different-state copies must offer the active player a simultaneous-trigger order")
 verify(actual.winner == 0, "W31-03: the player's chosen winning order must not be replaced by play-area insertion order")
 await custom_avatar_save()
 print("Project hunt: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
