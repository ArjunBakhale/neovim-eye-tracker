local M = {}

--- GazeData type: { x: number, y: number, ts: number, valid: boolean }
--- x, y are screen pixel coordinates
--- ts is a monotonic timestamp in milliseconds
--- valid indicates whether the sample is usable

local backend = nil

function M.start()
  local config = require("eye-tracker.config").get()
  local name = config.backend

  if name == "auto" then
    name = M._detect_backend()
  end

  local ok, mod = pcall(require, "eye-tracker.backends." .. name)
  if not ok then
    vim.notify("[eye-tracker] backend '" .. name .. "' not found, falling back to mock", vim.log.levels.WARN)
    ok, mod = pcall(require, "eye-tracker.backends.mock")
    if not ok then
      error("[eye-tracker] failed to load mock backend: " .. mod)
    end
  end

  backend = mod
  backend.start()
end

function M.stop()
  if backend then
    backend.stop()
    backend = nil
  end
end

function M.poll()
  if not backend then
    return nil
  end
  return backend.poll()
end

function M.calibrate(callback)
  if not backend then
    vim.notify("[eye-tracker] no backend active, start tracking first", vim.log.levels.WARN)
    return
  end
  backend.calibrate(callback)
end

function M.is_connected()
  if not backend then
    return false
  end
  return backend.is_connected()
end

function M.get_info()
  if not backend then
    return { name = "none", connected = false, status = "stopped" }
  end
  return {
    name = backend.name or "unknown",
    connected = backend.is_connected(),
    status = "running",
  }
end

function M._detect_backend()
  -- Probe for jeo-eyetracker sidecar
  local script = M._find_plugin_root() .. "/scripts/eye_sidecar.py"
  if vim.fn.filereadable(script) == 1 and vim.fn.executable("python3") == 1 then
    return "jeo-eyetracker"
  end
  return "mock"
end

function M._get_backend()
  return backend
end

function M._find_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2) -- strip leading @
  -- source is <root>/lua/eye-tracker/tracker.lua
  return vim.fn.fnamemodify(source, ":h:h:h")
end

return M
