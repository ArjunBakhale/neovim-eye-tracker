local M = {}

local defaults = {
  polling_rate = 60,
  sensitivity = 1.0,
  smoothing = {
    method = "exponential",
    factor = 0.3,
    window_size = 5,
  },
  dead_zone = {
    radius = 15,
  },
  backend = "auto",
  keybindings = {
    toggle = "<leader>et",
    calibrate = "<leader>ec",
  },
  cursor = {
    scope = "editor",
    edge_scroll = {
      enabled = true,
      margin = 20,
      speed = 3,
    },
  },
  calibration = {
    samples_per_point = 20,
    sample_interval_ms = 25,
  },
  auto_start = false,
}

local config = nil

function M.setup(opts)
  config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  M._validate()
  return config
end

function M.get()
  if not config then
    error("[eye-tracker] setup() has not been called yet")
  end
  return config
end

function M.is_setup()
  return config ~= nil
end

function M._validate()
  if not config then
    return
  end

  if config.polling_rate < 1 or config.polling_rate > 240 then
    vim.notify("[eye-tracker] polling_rate out of range (1-240), got: " .. config.polling_rate, vim.log.levels.WARN)
  end

  if config.sensitivity < 0.1 or config.sensitivity > 10 then
    vim.notify("[eye-tracker] sensitivity out of range (0.1-10), got: " .. config.sensitivity, vim.log.levels.WARN)
  end

  if config.smoothing.factor < 0 or config.smoothing.factor > 1 then
    vim.notify("[eye-tracker] smoothing.factor out of range (0-1), got: " .. config.smoothing.factor, vim.log.levels.WARN)
  end

  if config.dead_zone.radius < 0 then
    vim.notify("[eye-tracker] dead_zone.radius must be >= 0, got: " .. config.dead_zone.radius, vim.log.levels.WARN)
  end
end

return M
