---
name: token-saver
description: Work in this project while spending as few tokens as possible. Use at the start of every task in this repo, and whenever a task involves reading big files, screenshots, logs or long tool output.
---

# Token saver

The context budget is shared by everything: messages, file reads, tool output,
images. Spend it on decisions, not on re-reading.

## Reading
- Never Read a whole big script. `player_controller.gd` (~1900 lines),
  `zombie_enemy.gd` (~1350), `game_hud.gd` (~1100), `bunker_arena.gd`,
  `wave_manager.gd`: `grep -n` for the function, then Read with offset/limit
  (30–80 lines).
- Read a file once. Don't re-read after Edit/Write; the tools fail loudly.
- Prefer one Bash call with several greps over many small reads.

## Tool output
- Pipe noisy commands through filters: Godot runs through
  `grep -vE "\.NET|dotnet|hostfxr|GodotSharp|NativeInterop|CSharp|^\s*$"` and
  `| tail -20`; Blender through `grep -E "Exported|Error|Traceback"`.
- Cap listings with `head`. Use `wc -l`/`du -sh` instead of full listings.
- Long jobs (Blender, Godot import): run in background, don't poll.

## Images
- Screenshots cost a lot. Take only the shots needed, look at each once,
  and use 1280x720 or smaller. Combine several into one contact sheet.

## Edits
- Use Edit with small unique snippets; batch independent edits in one turn.
- For many mechanical replacements, one Python script beats many Edits.

## Messages
- Short updates: what changed, what's next. No recaps of earlier work,
  no repeating file contents or plans back to the user.
- Final message: outcome first, a few bullets, no essays.

## Subagents
- Don't spawn agents for work that a few greps can do.
