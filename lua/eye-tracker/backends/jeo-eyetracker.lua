local M = {}

M.name = "jeo-eyetracker"

local handle = nil
local stdin_pipe = nil
local stdout_pipe = nil
local latest = { rx = 0, ry = 0, valid = false, confidence = 0 }
local line_buffer = ""

--- Find the plugin root directory by walking up from this file's location.
local function find_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2) -- strip leading @
  -- source is <root>/lua/eye-tracker/backends/jeo-eyetracker.lua
  return vim.fn.fnamemodify(source, ":h:h:h:h")
end

local function find_script_path()
  return find_plugin_root() .. "/scripts/eye_sidecar.py"
end

--- Find the best python3 to use: prefer the plugin's own venv.
local function find_python()
  local venv_python = find_plugin_root() .. "/.venv/bin/python3"
  if vim.fn.executable(venv_python) == 1 then
    return venv_python
  end
  return "python3"
end

--- Process a chunk of stdout data, handling partial lines.
local function on_stdout(err, data)
  if err then
    vim.notify("[eye-tracker:jeo] stdout error: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  if not data then
    -- EOF: process exited
    handle = nil
    return
  end

  line_buffer = line_buffer .. data

  while true do
    local newline_pos = line_buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = line_buffer:sub(1, newline_pos - 1)
    line_buffer = line_buffer:sub(newline_pos + 1)

    if #line > 0 then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and obj then
        if obj.status then
          -- Status message (ready/error)
          if obj.status == "error" then
            vim.notify("[eye-tracker:jeo] sidecar error: " .. (obj.message or "unknown"), vim.log.levels.ERROR)
          end
        else
          latest = obj
        end
      end
    end
  end
end

function M.start()
  if handle then
    return
  end

  local script = find_script_path()
  if vim.fn.filereadable(script) ~= 1 then
    vim.notify("[eye-tracker:jeo] sidecar script not found: " .. script, vim.log.levels.ERROR)
    return
  end

  local python = find_python()
  if vim.fn.executable(python) ~= 1 then
    vim.notify("[eye-tracker:jeo] python3 not found in PATH", vim.log.levels.ERROR)
    return
  end

  stdin_pipe = vim.uv.new_pipe(false)
  stdout_pipe = vim.uv.new_pipe(false)

  local script_dir = vim.fn.fnamemodify(script, ":h")

  handle = vim.uv.spawn(python, {
    args = { script },
    cwd = script_dir,
    stdio = { stdin_pipe, stdout_pipe, nil },
  }, function(code, signal)
    -- On exit callback
    handle = nil
    if stdout_pipe then
      stdout_pipe:close()
      stdout_pipe = nil
    end
    if stdin_pipe then
      stdin_pipe:close()
      stdin_pipe = nil
    end
  end)

  if not handle then
    vim.notify("[eye-tracker:jeo] failed to spawn sidecar", vim.log.levels.ERROR)
    if stdin_pipe then stdin_pipe:close(); stdin_pipe = nil end
    if stdout_pipe then stdout_pipe:close(); stdout_pipe = nil end
    return
  end

  line_buffer = ""
  latest = { rx = 0, ry = 0, valid = false, confidence = 0 }

  stdout_pipe:read_start(vim.schedule_wrap(on_stdout))
end

function M.stop()
  if not handle then
    return
  end

  -- Send quit command via stdin
  if stdin_pipe then
    pcall(function()
      stdin_pipe:write("quit\n")
    end)
  end

  -- Give it a moment, then force kill
  vim.defer_fn(function()
    if handle then
      pcall(function() handle:kill("sigterm") end)
    end
    -- Clean up pipes
    vim.defer_fn(function()
      if handle then
        pcall(function() handle:kill("sigkill") end)
        handle = nil
      end
      if stdout_pipe then
        pcall(function() stdout_pipe:close() end)
        stdout_pipe = nil
      end
      if stdin_pipe then
        pcall(function() stdin_pipe:close() end)
        stdin_pipe = nil
      end
    end, 500)
  end, 200)
end

function M.poll_raw()
  if not latest.valid then
    return nil
  end
  return { rx = latest.rx, ry = latest.ry, confidence = latest.confidence }
end

function M.poll()
  if not latest.valid then
    return { x = 0, y = 0, ts = vim.uv.now(), valid = false }
  end

  local calibration = require("eye-tracker.calibration")
  local sx, sy = calibration.apply(latest.rx, latest.ry)

  if sx then
    return {
      x = sx,
      y = sy,
      ts = vim.uv.now(),
      valid = true,
    }
  end

  -- Fallback: simple linear mapping if uncalibrated
  local cell_w = 8
  local cell_h = 16
  local screen_w = vim.o.columns * cell_w
  local screen_h = vim.o.lines * cell_h

  return {
    x = latest.rx * screen_w,
    y = latest.ry * screen_h,
    ts = vim.uv.now(),
    valid = true,
  }
end

function M.calibrate(callback)
  local calibration = require("eye-tracker.calibration")
  calibration.open(callback)
end

function M.is_connected()
  return handle ~= nil
end

return M
