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
}

return config
