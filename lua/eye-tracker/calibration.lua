local M = {}

local state = {
  buf = nil,
  win = nil,
  points = {},
  current = 0,
  collected = {},
  callback = nil,
  sample_timer = nil,
  current_samples = {},
}

-- Calibration coefficients: nil means uncalibrated
-- Each is a table of 6 coefficients for degree-2 polynomial:
--   val = c[1] + c[2]*rx + c[3]*ry + c[4]*rx*ry + c[5]*rx^2 + c[6]*ry^2
local coeffs_x = nil
local coeffs_y = nil

-- 9-point calibration pattern: center, 4 corners, 4 edge midpoints
-- Expressed as fractions (0-1) of the screen area
local CALIBRATION_POINTS = {
  { x = 0.5, y = 0.5 },  -- center
  { x = 0.1, y = 0.1 },  -- top-left
  { x = 0.9, y = 0.1 },  -- top-right
  { x = 0.1, y = 0.9 },  -- bottom-left
  { x = 0.9, y = 0.9 },  -- bottom-right
  { x = 0.5, y = 0.1 },  -- top-center
  { x = 0.5, y = 0.9 },  -- bottom-center
  { x = 0.1, y = 0.5 },  -- left-center
  { x = 0.9, y = 0.5 },  -- right-center
}

--- Get the calibration data file path.
local function get_calibration_path()
  return vim.fn.stdpath("data") .. "/eye-tracker-calibration.json"
end

--- Solve a linear system Ax = b using Gaussian elimination with partial pivoting.
--- A is n*n (row-major tables), b is length-n. Returns x or nil on failure.
local function solve_linear(A, b)
  local n = #b
  -- Augmented matrix
  local aug = {}
  for i = 1, n do
    aug[i] = {}
    for j = 1, n do
      aug[i][j] = A[i][j]
    end
    aug[i][n + 1] = b[i]
  end

  -- Forward elimination with partial pivoting
  for col = 1, n do
    -- Find pivot
    local max_val = math.abs(aug[col][col])
    local max_row = col
    for row = col + 1, n do
      local val = math.abs(aug[row][col])
      if val > max_val then
        max_val = val
        max_row = row
      end
    end

    if max_val < 1e-12 then
      return nil -- Singular
    end

    -- Swap rows
    if max_row ~= col then
      aug[col], aug[max_row] = aug[max_row], aug[col]
    end

    -- Eliminate below
    for row = col + 1, n do
      local factor = aug[row][col] / aug[col][col]
      for j = col, n + 1 do
        aug[row][j] = aug[row][j] - factor * aug[col][j]
      end
    end
  end

  -- Back substitution
  local x = {}
  for i = n, 1, -1 do
    local sum = aug[i][n + 1]
    for j = i + 1, n do
      sum = sum - aug[i][j] * x[j]
    end
    x[i] = sum / aug[i][i]
  end

  return x
end

--- Fit a degree-2 polynomial to calibration data.
--- points: list of {rx, ry, target} where target is the screen coordinate.
--- Returns 6 coefficients [a0, a1, a2, a3, a4, a5] or nil on failure.
local function fit_polynomial(points)
  local n = #points
  if n < 6 then
    return nil
  end

  -- Build normal equations: (A^T * A) * x = A^T * b
  -- Design matrix row: [1, rx, ry, rx*ry, rx^2, ry^2]
  local ncols = 6
  local ATA = {}
  local ATb = {}
  for i = 1, ncols do
    ATA[i] = {}
    for j = 1, ncols do
      ATA[i][j] = 0
    end
    ATb[i] = 0
  end

  for _, pt in ipairs(points) do
    local rx, ry, target = pt.rx, pt.ry, pt.target
    local row = { 1, rx, ry, rx * ry, rx * rx, ry * ry }

    for i = 1, ncols do
      for j = 1, ncols do
        ATA[i][j] = ATA[i][j] + row[i] * row[j]
      end
      ATb[i] = ATb[i] + row[i] * target
    end
  end

  return solve_linear(ATA, ATb)
end

--- Evaluate a degree-2 polynomial at (rx, ry).
local function eval_polynomial(coeffs, rx, ry)
  return coeffs[1]
    + coeffs[2] * rx
    + coeffs[3] * ry
    + coeffs[4] * rx * ry
    + coeffs[5] * rx * rx
    + coeffs[6] * ry * ry
end

--- Apply calibration transform to raw gaze ratios.
--- Returns (screen_x, screen_y) or (nil, nil) if uncalibrated.
function M.apply(rx, ry)
  if not coeffs_x or not coeffs_y then
    return nil, nil
  end
  return eval_polynomial(coeffs_x, rx, ry), eval_polynomial(coeffs_y, rx, ry)
end

--- Check if calibration data is loaded.
function M.is_calibrated()
  return coeffs_x ~= nil and coeffs_y ~= nil
end

--- Save calibration coefficients to disk.
local function save_calibration()
  if not coeffs_x or not coeffs_y then
    return false
  end
  local data = vim.json.encode({ coeffs_x = coeffs_x, coeffs_y = coeffs_y })
  local path = get_calibration_path()
  local f = io.open(path, "w")
  if not f then
    vim.notify("[eye-tracker] failed to save calibration to " .. path, vim.log.levels.ERROR)
    return false
  end
  f:write(data)
  f:close()
  return true
end

--- Load calibration coefficients from disk.
function M.load()
  local path = get_calibration_path()
  local f = io.open(path, "r")
  if not f then
    return false
  end
  local content = f:read("*a")
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data or not data.coeffs_x or not data.coeffs_y then
    return false
  end

  -- Validate coefficient arrays
  if #data.coeffs_x ~= 6 or #data.coeffs_y ~= 6 then
    return false
  end

  coeffs_x = data.coeffs_x
  coeffs_y = data.coeffs_y
  return true
end

function M.open(callback)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.notify("[eye-tracker] calibration already in progress", vim.log.levels.WARN)
    return
  end

  -- Try to load existing calibration on first open
  if not coeffs_x then
    M.load()
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
    M._start_sampling()
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

--- Start collecting multiple samples for the current calibration point.
function M._start_sampling()
  local tracker = require("eye-tracker.tracker")
  local backend = tracker._get_backend()
  if not backend or not backend.poll_raw then
    vim.notify("[eye-tracker] backend does not support raw polling", vim.log.levels.ERROR)
    return
  end

  local config = require("eye-tracker.config").get()
  local samples_per_point = (config.calibration and config.calibration.samples_per_point) or 20
  local sample_interval = (config.calibration and config.calibration.sample_interval_ms) or 25

  state.current_samples = {}

  -- Update instruction to show sampling
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local width = vim.api.nvim_win_get_width(state.win)
    local sampling_text = "  Sampling... keep looking at [+]"
    if #sampling_text < width then
      sampling_text = sampling_text .. string.rep(" ", width - #sampling_text)
    end
    vim.api.nvim_buf_set_lines(state.buf, 0, 1, false, { sampling_text })
  end

  local collected = 0
  state.sample_timer = vim.uv.new_timer()
  state.sample_timer:start(0, sample_interval, vim.schedule_wrap(function()
    local raw = backend.poll_raw()
    if raw then
      table.insert(state.current_samples, raw)
    end
    collected = collected + 1

    if collected >= samples_per_point then
      if state.sample_timer then
        state.sample_timer:stop()
        state.sample_timer:close()
        state.sample_timer = nil
      end
      M._advance()
    end
  end))
end

function M._advance()
  -- Average the collected samples
  local samples = state.current_samples
  if #samples == 0 then
    -- No valid samples; try using a single poll as fallback
    local tracker = require("eye-tracker.tracker")
    local backend = tracker._get_backend()
    if backend and backend.poll_raw then
      local raw = backend.poll_raw()
      if raw then
        samples = { raw }
      end
    end
  end

  local avg_rx, avg_ry = 0, 0
  if #samples > 0 then
    for _, s in ipairs(samples) do
      avg_rx = avg_rx + s.rx
      avg_ry = avg_ry + s.ry
    end
    avg_rx = avg_rx / #samples
    avg_ry = avg_ry / #samples
  end

  table.insert(state.collected, {
    target = CALIBRATION_POINTS[state.current],
    gaze = { rx = avg_rx, ry = avg_ry },
    num_samples = #samples,
  })

  state.current = state.current + 1
  state.current_samples = {}

  if state.current > #CALIBRATION_POINTS then
    M._finish()
    return
  end

  M._render_point()
end

function M._finish()
  -- Compute polynomial regression from collected calibration data.
  -- Map raw gaze ratios (rx, ry) to screen pixel coordinates.
  local cell_w = 8
  local cell_h = 16
  local screen_w = vim.o.columns * cell_w
  local screen_h = vim.o.lines * cell_h

  local points_x = {}
  local points_y = {}

  for _, entry in ipairs(state.collected) do
    local target_px_x = entry.target.x * screen_w
    local target_px_y = entry.target.y * screen_h

    table.insert(points_x, { rx = entry.gaze.rx, ry = entry.gaze.ry, target = target_px_x })
    table.insert(points_y, { rx = entry.gaze.rx, ry = entry.gaze.ry, target = target_px_y })
  end

  local cx = fit_polynomial(points_x)
  local cy = fit_polynomial(points_y)

  local success = false
  if cx and cy then
    coeffs_x = cx
    coeffs_y = cy
    success = save_calibration()
    if success then
      vim.notify("[eye-tracker] calibration complete and saved (" .. #state.collected .. " points)", vim.log.levels.INFO)
    else
      vim.notify("[eye-tracker] calibration computed but failed to save", vim.log.levels.WARN)
    end
  else
    vim.notify("[eye-tracker] calibration failed: could not fit polynomial (insufficient data?)", vim.log.levels.ERROR)
  end

  local result = {
    points = state.collected,
    success = success or (cx ~= nil and cy ~= nil),
  }

  local cb = state.callback
  M.close()

  if cb then
    cb(result)
  end
end

function M.close()
  if state.sample_timer then
    state.sample_timer:stop()
    state.sample_timer:close()
    state.sample_timer = nil
  end
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
  state.current_samples = {}
  state.callback = nil
end

return M
