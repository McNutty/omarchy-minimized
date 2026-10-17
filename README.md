# Minimized windows (Omarchy bar widget)

Per-workspace minimize for Omarchy (Hyprland + Quickshell). A keybinding hides
the active window; the bar shows icons for the windows hidden from the
workspace you're looking at, and clicking one brings it back.

## How it works

- Minimizing moves the window to the hidden Hyprland workspace
  `special:min-<workspace id>` without following it.
- The widget (`thord.minimized`) reads the workspace its own monitor shows and
  lists the windows on the matching `special:min-<id>`. Other workspaces'
  minimized windows stay out of view. Hover for the title, click to move the
  window back and focus it.
- Hyprland holds all state, so a shell restart or plugin reload loses nothing.
  The widget takes no space when the list is empty.

## Install

```bash
ln -s ~/Code/personal/omarchy-minimized ~/.config/omarchy/plugins/thord.minimized
omarchy plugin enable thord.minimized --section left --after thord.workspaces
```

Bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + M", "Minimize window", function()
  local win = hl.get_active_window()
  if not (win and win.workspace) or win.workspace.special then return end
  hl.dispatch(hl.dsp.window.move({ workspace = "special:min-" .. win.workspace.id, follow = false }))
end)
```
