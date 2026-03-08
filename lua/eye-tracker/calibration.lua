local M = {}

local state = {
  buf = nil,
  win = nil,
  points = {},
  current = 0,
  collected = {},
  callback = nil,
}

-- 5-point calibration pattern: center + 4 corners
-- Expressed as fractions (0-1) of the screen area
local CALIBRATION_POINTS = {
  { x = 0.5, y = 0.5 },  -- center
  { x = 0.1, y = 0.1 },  -- top-left
  { x = 0.9, y = 0.1 },  -- top-right
  { x = 0.1, y = 0.9 },  -- bottom-left
  { x = 0.9, y = 0.9 },  -- bottom-right
}

function M.open(callback)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.notify("[eye-tracker] calibration already in progress", vim.log.levels.WARN)
    return
  end

  state.callback = callback
  state.current = 1
  state.collected = {}

  local width = vim.o.columns
  local height = vim.o.lines - 1 -- account for cmdline

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = 0,
    col = 0,
    style = "minimal",
    border = "none",
    zindex = 100,
  })

  -- Fill buffer with blank lines
  local lines = {}
  for _ = 1, height do
    table.insert(lines, string.rep(" ", width))
  end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

  -- Set up keymaps
  vim.keymap.set("n", "<CR>", function()
    M._advance()
  end, { buffer = state.buf, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, { buffer = state.buf, nowait = true })

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = state.buf, nowait = true })

  -- Render first point
  M._render_point()

  vim.notify("[eye-tracker] calibration started - look at [+] and press <Enter>", vim.log.levels.INFO)
end

function M._render_point()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local width = vim.api.nvim_win_get_width(state.win)
  local height = vim.api.nvim_win_get_height(state.win)

  -- Clear buffer
  local lines = {}
  for _ = 1, height do
    table.insert(lines, string.rep(" ", width))
  end

  local point = CALIBRATION_POINTS[state.current]
  if not point then
    return
  end

  local col = math.floor(point.x * (width - 3))
  local row = math.floor(point.y * (height - 1)) + 1

  row = math.max(1, math.min(row, height))
  col = math.max(0, math.min(col, width - 3))

  -- Place the marker
  local marker = "[+]"
  local line = string.rep(" ", col) .. marker .. string.rep(" ", math.max(0, width - col - #marker))
  lines[row] = line

  -- Add instruction text at top
  local instruction = string.format("  Calibration point %d/%d - Look at [+] and press <Enter>  (q/Esc to cancel)",
    state.current, #CALIBRATION_POINTS)
  if #instruction < width then
    lines[1] = instruction .. string.rep(" ", width - #instruction)
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
end

function M._advance()
  -- Collect gaze data for current point
  local tracker = require("eye-tracker.tracker")
  local gaze = tracker.poll()

  table.insert(state.collected, {
    target = CALIBRATION_POINTS[state.current],
    gaze = gaze,
  })

  state.current = state.current + 1

  if state.current > #CALIBRATION_POINTS then
    M._finish()
    return
  end

  M._render_point()
end

function M._finish()
  -- TODO: compute correction transform from collected calibration data
  -- For now, just notify success and invoke callback
  local result = {
    points = state.collected,
    success = true,
  }

  M.close()

  vim.notify("[eye-tracker] calibration complete (" .. #result.points .. " points collected)", vim.log.levels.INFO)

  if state.callback then
    state.callback(result)
  end
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.current = 0
  state.collected = {}
  state.callback = nil
end

return M
