# eye-tracker.nvim

Move around Neovim with your eyeballs. Gaze-based cursor control using external eye-tracking hardware.

## Features

- Gaze-to-cursor mapping with configurable smoothing and dead zones
- Pluggable backend architecture for different eye-tracking SDKs
- Built-in calibration UI (5-point, fullscreen)
- Edge scrolling when gaze moves near window borders
- Health check integration (`:checkhealth eye-tracker`)

## Requirements

- Neovim >= 0.9
- Supported eye-tracking hardware + backend module

## Installation

### lazy.nvim

```lua
{
  "arjunbakhale/neovim-eye-tracker",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "arjunbakhale/neovim-eye-tracker",
  config = function()
    require("eye-tracker").setup()
  end,
}
```

## Configuration

```lua
require("eye-tracker").setup({
  polling_rate = 60,          -- Hz (1-240)
  sensitivity = 1.0,          -- gaze sensitivity multiplier
  smoothing = {
    method = "exponential",   -- "exponential" or "window"
    factor = 0.3,             -- EMA factor (0-1, lower = smoother)
    window_size = 5,          -- sliding window size (for "window" method)
  },
  dead_zone = {
    radius = 15,              -- ignore movements smaller than this (pixels)
  },
  backend = "auto",           -- backend name or "auto" to detect
  keybindings = {
    toggle = "<leader>et",    -- toggle tracking
    calibrate = "<leader>ec", -- open calibration
  },
  cursor = {
    scope = "editor",
    edge_scroll = {
      enabled = true,
      margin = 20,
      speed = 3,
    },
  },
  auto_start = false,
})
```

## Commands

| Command | Description |
| --- | --- |
| `:EyeTrackerEnable` | Start eye tracking |
| `:EyeTrackerDisable` | Stop eye tracking |
| `:EyeTrackerToggle` | Toggle on/off |
| `:EyeTrackerCalibrate` | Open calibration UI |
| `:EyeTrackerStatus` | Show tracking status |

## Writing a Backend

Backends live at `lua/eye-tracker/backends/<name>.lua` and must export:

```lua
return {
  name = "my-backend",
  start = function() end,
  stop = function() end,
  poll = function()
    -- Return GazeData: { x, y, ts, valid }
    -- x, y: screen coordinates in pixels
    -- ts: monotonic timestamp in ms
    -- valid: boolean
    return { x = 0, y = 0, ts = 0, valid = true }
  end,
  calibrate = function(callback)
    callback({ success = true })
  end,
  is_connected = function()
    return true
  end,
}
```

Set `backend = "my-backend"` in your config, or implement detection logic so `"auto"` finds it.

## Health Check

```
:checkhealth eye-tracker
```

Verifies Neovim version, plugin setup, backend status, and external SDK availability.

## License

GPL-3.0
