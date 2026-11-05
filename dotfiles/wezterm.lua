-- WezTerm config. The PowerShell profile points WEZTERM_CONFIG_FILE at this
-- file, and machine setup copies it to ~/.wezterm.lua for the first launch.
local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- New tabs and panes open PowerShell 7 instead of cmd.exe.
config.default_prog = { 'pwsh.exe', '-NoLogo' }

-- Keep more output than the default 3500 lines.
config.scrollback_lines = 20000

-- Shells to choose from in the launcher (right-click the + tab button).
-- WSL distributions are added to the launcher automatically.
config.launch_menu = {
  { label = 'PowerShell 7', args = { 'pwsh.exe', '-NoLogo' } },
  { label = 'Windows PowerShell', args = { 'powershell.exe', '-NoLogo' } },
  { label = 'Command Prompt', args = { 'cmd.exe' } },
}
local git_bash = 'C:\\Program Files\\Git\\bin\\bash.exe'
local git_bash_file = io.open(git_bash, 'r')
if git_bash_file then
  git_bash_file:close()
  table.insert(config.launch_menu, { label = 'Git Bash', args = { git_bash, '-i', '-l' } })
end

-- A local session server. Panes attached to it keep running after the
-- window closes. Attach with Ctrl+Shift+G or `wezterm connect unix`.
config.unix_domains = {
  { name = 'unix' },
}

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
  -- Ctrl+Shift+A labels each pane with a letter; type one to jump to it.
  {
    key = 'A',
    mods = 'CTRL|SHIFT',
    action = act.PaneSelect,
  },
  -- Ctrl+Shift+S picks a pane to swap places with the current one.
  {
    key = 'S',
    mods = 'CTRL|SHIFT',
    action = act.PaneSelect { mode = 'SwapWithActive' },
  },
  -- Ctrl+Shift+O rotates the panes in the tab clockwise.
  {
    key = 'O',
    mods = 'CTRL|SHIFT',
    action = act.RotatePanes 'Clockwise',
  },
  -- Ctrl+Shift+E renames the current tab. An empty name restores the default.
  {
    key = 'E',
    mods = 'CTRL|SHIFT',
    action = act.PromptInputLine {
      description = 'Tab name:',
      action = wezterm.action_callback(function(window, _, line)
        if line then
          window:active_tab():set_title(line)
        end
      end),
    },
  },
  -- Ctrl+Shift+G attaches to the persistent session server.
  {
    key = 'G',
    mods = 'CTRL|SHIFT',
    action = act.AttachDomain 'unix',
  },
  -- Ctrl+Shift+D detaches from the session server; its panes keep running.
  {
    key = 'D',
    mods = 'CTRL|SHIFT',
    action = act.DetachDomain { DomainName = 'unix' },
  },
}

return config
