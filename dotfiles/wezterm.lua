-- WezTerm config. Machine setup copies this to ~/.wezterm.lua.
local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- Right click pastes from the clipboard.
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.PasteFrom 'Clipboard',
  },
}

config.keys = {
  -- Alt+S splits the current pane, opening the new pane on the right.
  {
    key = 's',
    mods = 'ALT',
    action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  -- Alt+Shift+S splits the current pane, opening the new pane below.
  -- (Alt+D is left free for PSReadLine's DeleteWord.)
  {
    key = 'S',
    mods = 'ALT|SHIFT',
    action = act.SplitVertical { domain = 'CurrentPaneDomain' },
  },

  -- Alt+Arrow moves to the pane in that direction.
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' }, -- Move to the pane on the left.
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' }, -- Move to the pane on the right.
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' }, -- Move to the pane above.
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' }, -- Move to the pane below.

  -- Ctrl+Alt+Arrow resizes the current pane by 5 cells.
  { key = 'LeftArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Left', 5 } }, -- Grow the pane to the left.
  { key = 'RightArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Right', 5 } }, -- Grow the pane to the right.
  { key = 'UpArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Up', 5 } }, -- Grow the pane upward.
  { key = 'DownArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Down', 5 } }, -- Grow the pane downward.

  -- Ctrl+Shift+W closes the current pane (WezTerm's default closes the tab).
  {
    key = 'w',
    mods = 'CTRL|SHIFT',
    action = act.CloseCurrentPane { confirm = true },
  },
  -- Ctrl+Shift+Z zooms the current pane to fill the tab, or unzooms it.
  {
    key = 'z',
    mods = 'CTRL|SHIFT',
    action = act.TogglePaneZoomState,
  },
}

return config
