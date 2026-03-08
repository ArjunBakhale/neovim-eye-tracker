local M = {}

M.name = "mock"

local running = false

function M.start()
  running = true
end

function M.stop()
  running = false
end

function M.poll()
  if not running then
    return nil
  end

  -- Return a mock gaze sample at the center of the screen
  return {
    x = 0,
    y = 0,
    ts = vim.uv.now(),
    valid = false, -- marked invalid so it doesn't move the cursor
  }
end

function M.calibrate(callback)
  vim.notify("[eye-tracker:mock] mock calibration complete", vim.log.levels.INFO)
  if callback then
    callback({ success = true })
  end
end

function M.is_connected()
  return running
end

return M
