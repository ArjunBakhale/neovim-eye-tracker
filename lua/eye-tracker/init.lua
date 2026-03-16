local M = {}

local timer = nil
local enabled = false

function M.setup(opts)
  local config = require("eye-tracker.config")
  config.setup(opts)

  local cfg = config.get()

  -- Register keybindings
  if cfg.keybindings.toggle then
    vim.keymap.set("n", cfg.keybindings.toggle, function()
      M.toggle()
    end, { desc = "Toggle eye tracking" })
  end

  if cfg.keybindings.calibrate then
    vim.keymap.set("n", cfg.keybindings.calibrate, function()
      M.calibrate()
    end, { desc = "Calibrate eye tracker" })
  end

  -- Load saved calibration if available
  local calibration = require("eye-tracker.calibration")
  if calibration.load() then
    vim.notify("[eye-tracker] loaded saved calibration", vim.log.levels.INFO)
  end

  -- Auto-start if configured
  if cfg.auto_start then
    vim.defer_fn(function()
      M.enable()
    end, 100)
  end
end

function M.enable()
  if enabled then
    vim.notify("[eye-tracker] already enabled", vim.log.levels.INFO)
    return
  end

  local tracker = require("eye-tracker.tracker")
  local cursor = require("eye-tracker.cursor")
  local config = require("eye-tracker.config")

  tracker.start()

  local cfg = config.get()
  local interval = math.floor(1000 / cfg.polling_rate)

  timer = vim.uv.new_timer()
  timer:start(interval, interval, vim.schedule_wrap(function()
    local gaze = tracker.poll()
    if gaze then
      cursor.move_to_gaze(gaze)
    end
  end))

  enabled = true
  vim.notify("[eye-tracker] enabled (polling at " .. cfg.polling_rate .. " Hz)", vim.log.levels.INFO)
end

function M.disable()
  if not enabled then
    vim.notify("[eye-tracker] already disabled", vim.log.levels.INFO)
    return
  end

  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  local tracker = require("eye-tracker.tracker")
  tracker.stop()

  local cursor = require("eye-tracker.cursor")
  cursor.reset()

  enabled = false
  vim.notify("[eye-tracker] disabled", vim.log.levels.INFO)
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.calibrate()
  local calibration = require("eye-tracker.calibration")
  calibration.open(function(result)
    if result and result.success then
      vim.notify("[eye-tracker] calibration saved", vim.log.levels.INFO)
    end
  end)
end

function M.status()
  local tracker = require("eye-tracker.tracker")
  local info = tracker.get_info()
  local config = require("eye-tracker.config")

  local lines = {
    "eye-tracker status:",
    "  enabled:   " .. tostring(enabled),
    "  backend:   " .. info.name,
    "  connected: " .. tostring(info.connected),
    "  status:    " .. info.status,
  }

  if config.is_setup() then
    local cfg = config.get()
    table.insert(lines, "  polling:   " .. cfg.polling_rate .. " Hz")
    table.insert(lines, "  smoothing: " .. cfg.smoothing.method .. " (factor " .. cfg.smoothing.factor .. ")")
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
