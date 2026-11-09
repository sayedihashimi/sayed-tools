-- WezTerm config. The PowerShell profile points WEZTERM_CONFIG_FILE at this
-- file, and machine setup copies it to ~/.wezterm.lua for the first launch.
local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- New tabs and panes open PowerShell 7 instead of cmd.exe.
config.default_prog = { 'pwsh.exe', '-NoLogo' }

-- Keep more output than the default 3500 lines.
config.scrollback_lines = 20000

-- The default (fancy) tab bar is kept: the retro one draws tab names at the
-- terminal font size. The tab bar stays visible with a single tab, so its +
-- button and the workspace name are always there.
config.tab_max_width = 32

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

-- Tab colors. WezTerm has no per-tab color setting (colors.tab_bar applies to
-- every tab), so format-tab-title draws the colored tabs. A tab's color is
-- kept in wezterm.GLOBAL under its tab id: it survives a config reload, but
-- not a WezTerm restart. Pick a color with Ctrl+Shift+K, or from PowerShell
-- with Set-TabColor, which sets the TAB_COLOR user variable.
local tab_colors = {
  { name = 'Red', bg = '#DC2626', fg = '#FFFFFF' },
  { name = 'Green', bg = '#16A34A', fg = '#000000' },
  { name = 'Blue', bg = '#2563EB', fg = '#FFFFFF' },
  { name = 'Yellow', bg = '#EAB308', fg = '#000000' },
  { name = 'Purple', bg = '#9333EA', fg = '#FFFFFF' },
  { name = 'Orange', bg = '#EA580C', fg = '#000000' },
}
local tab_color_by_name = {}
local tab_color_choices = {}
for _, color in ipairs(tab_colors) do
  tab_color_by_name[color.name:lower()] = color
  table.insert(tab_color_choices, { id = color.name, label = color.name .. '  ' .. color.bg })
end
table.insert(tab_color_choices, { id = 'Reset', label = 'Reset (default colors)' })

local function tab_color_key(tab_id)
  return 'tab_color_' .. tostring(tab_id)
end

-- Sets a tab's color by name. 'Reset' or an unknown name clears it.
local function set_tab_color(tab_id, name)
  local color = name and tab_color_by_name[name:lower()]
  wezterm.GLOBAL[tab_color_key(tab_id)] = color and color.name or nil
end

wezterm.on('user-var-changed', function(_, pane, name, value)
  if name ~= 'TAB_COLOR' then
    return
  end
  local tab = pane:tab()
  if tab then
    set_tab_color(tab:tab_id(), value)
  end
end)

-- Uncolored tabs return nothing, so WezTerm draws them as usual.
wezterm.on('format-tab-title', function(tab, _, _, conf, _, max_width)
  local name = wezterm.GLOBAL[tab_color_key(tab.tab_id)]
  local color = name and tab_color_by_name[name:lower()]
  if not color then
    return nil
  end
  local title = tab.tab_title
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  if conf.show_tab_index_in_tab_bar then
    local index = tab.tab_index + (conf.tab_and_split_indices_are_zero_based and 0 or 1)
    title = index .. ': ' .. title
  end
  title = wezterm.truncate_right(title, math.max(max_width - 2, 1))
  -- The active colored tab is bold and underlined so it stands out.
  return {
    { Background = { Color = color.bg } },
    { Foreground = { Color = color.fg } },
    { Attribute = { Intensity = tab.is_active and 'Bold' or 'Normal' } },
    { Attribute = { Underline = tab.is_active and 'Single' or 'None' } },
    { Text = ' ' .. title .. ' ' },
  }
end)

-- The active workspace name is shown on the right of the tab bar.
local function show_workspace_status(window)
  window:set_right_status(' ' .. window:active_workspace() .. ' ')
end
wezterm.on('update-status', show_workspace_status)

-- WezTerm redraws the tab bar only when a tab, pane, user variable or status
-- changes, so a color picked from the menu wouldn't show until the next one.
-- Changing the status redraws the tab bar right away.
local function redraw_tab_bar(window)
  window:set_right_status('')
  show_workspace_status(window)
end

-- Right click pastes from the clipboard. Selecting text with the mouse copies
-- it to the clipboard (WezTerm's default), and Ctrl+Shift+C / Ctrl+Shift+V keep
-- their default copy and paste. Mouse bindings don't apply to the tab bar.
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.PasteFrom 'Clipboard',
  },
}

config.keys = {
  -- Alt+D splits the current pane, opening the new pane on the right.
  -- (This takes Alt+D from PSReadLine's DeleteWord; Ctrl+Delete still works.)
  {
    key = 'd',
    mods = 'ALT',
    action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  -- Alt+S splits the current pane, opening the new pane below.
  {
    key = 's',
    mods = 'ALT',
    action = act.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  -- Alt+Shift+S also splits the current pane, opening the new pane below.
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

  -- Ctrl+Shift+Q closes the current pane (moved from Ctrl+Shift+W).
  {
    key = 'q',
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
  -- Ctrl+Shift+K picks a background color for the current tab (replaces
  -- WezTerm's default Ctrl+Shift+K, which clears the scrollback).
  {
    key = 'K',
    mods = 'CTRL|SHIFT',
    action = act.InputSelector {
      title = 'Tab color',
      choices = tab_color_choices,
      action = wezterm.action_callback(function(window, _, id)
        if id then
          set_tab_color(window:active_tab():tab_id(), id)
          redraw_tab_bar(window)
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

  -- Ctrl+Shift+W picks a workspace to switch to.
  {
    key = 'w',
    mods = 'CTRL|SHIFT',
    action = act.ShowLauncherArgs { title = 'Workspaces', flags = 'FUZZY|WORKSPACES' },
  },
  -- Ctrl+Alt+1..4 switch to a project workspace, creating it on first use.
  { key = '1', mods = 'CTRL|ALT', action = act.SwitchToWorkspace { name = 'rider' } }, -- Switch to the rider workspace.
  { key = '2', mods = 'CTRL|ALT', action = act.SwitchToWorkspace { name = 'dotcover' } }, -- Switch to the dotcover workspace.
  { key = '3', mods = 'CTRL|ALT', action = act.SwitchToWorkspace { name = 'dotultimate' } }, -- Switch to the dotultimate workspace.
  { key = '4', mods = 'CTRL|ALT', action = act.SwitchToWorkspace { name = 'general' } }, -- Switch to the general workspace.
}

return config
