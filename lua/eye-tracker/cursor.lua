local M = {}

local smoothing_state = {
  x = nil,
  y = nil,
  window = {},
}

local last_cursor_pos = nil

function M.move_to_gaze(gaze)
  if not gaze or not gaze.valid then
    return
  end

  local config = require("eye-tracker.config").get()

  -- Step 1: smooth
  local sx, sy = M._smooth(gaze.x, gaze.y, config)

  -- Step 2: dead zone check
  if M._in_dead_zone(sx, sy, config) then
    return
  end

  -- Step 3: screen-to-buffer mapping
  local win, row, col = M._screen_to_buffer(sx, sy)
  if not win then
    return
  end

  -- Step 4: edge scrolling
  M._edge_scroll(win, sx, sy, config)

  -- Step 5: move cursor
  vim.api.nvim_win_set_cursor(win, { row, col })
  last_cursor_pos = { x = sx, y = sy }
end

function M._smooth(x, y, config)
  local method = config.smoothing.method

  if method == "exponential" then
    return M._smooth_exponential(x, y, config.smoothing.factor)
  elseif method == "window" then
    return M._smooth_window(x, y, config.smoothing.window_size)
  end

  return x, y
end

function M._smooth_exponential(x, y, factor)
  if smoothing_state.x == nil then
    smoothing_state.x = x
    smoothing_state.y = y
    return x, y
  end

  smoothing_state.x = smoothing_state.x + factor * (x - smoothing_state.x)
  smoothing_state.y = smoothing_state.y + factor * (y - smoothing_state.y)

  return smoothing_state.x, smoothing_state.y
end

function M._smooth_window(x, y, window_size)
  table.insert(smoothing_state.window, { x = x, y = y })

  if #smoothing_state.window > window_size then
    table.remove(smoothing_state.window, 1)
  end

  local sum_x, sum_y = 0, 0
  for _, pt in ipairs(smoothing_state.window) do
    sum_x = sum_x + pt.x
    sum_y = sum_y + pt.y
  end

  local n = #smoothing_state.window
  return sum_x / n, sum_y / n
end

function M._in_dead_zone(x, y, config)
  if not last_cursor_pos then
    return false
  end

  local dx = x - last_cursor_pos.x
  local dy = y - last_cursor_pos.y
  local dist = math.sqrt(dx * dx + dy * dy)

  return dist < config.dead_zone.radius
end

function M._screen_to_buffer(screen_x, screen_y)
  -- Convert screen pixels to terminal cell coordinates.
  -- This is a rough approximation; accurate conversion requires
  -- knowing terminal cell dimensions (from terminal geometry or
  -- an external helper). For now, assume a basic mapping.
  -- TODO: integrate terminal geometry detection for pixel-accurate mapping.

  local cell_width = 8   -- approximate pixel width of a terminal cell
  local cell_height = 16 -- approximate pixel height of a terminal cell

  local col_cell = math.floor(screen_x / cell_width)
  local row_cell = math.floor(screen_y / cell_height)

  local win = M._find_window_at(col_cell, row_cell)
  if not win then
    return nil, nil, nil
  end

  local win_pos = vim.api.nvim_win_get_position(win)
  local win_row = win_pos[1]
  local win_col = win_pos[2]

  local buf_row = row_cell - win_row + 1
  local buf_col = col_cell - win_col

  -- Account for scroll offset
  local topline = vim.fn.getwininfo(win)[1].topline or 1
  buf_row = buf_row + topline - 1

  -- Clamp to buffer bounds
  local buf = vim.api.nvim_win_get_buf(win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  buf_row = math.max(1, math.min(buf_row, line_count))

  local line = vim.api.nvim_buf_get_lines(buf, buf_row - 1, buf_row, false)[1] or ""
  buf_col = math.max(0, math.min(buf_col, #line))

  return win, buf_row, buf_col
end

function M._find_window_at(col, row)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    -- Skip floating windows
    if cfg.relative == "" then
      local pos = vim.api.nvim_win_get_position(win)
      local win_row = pos[1]
      local win_col = pos[2]
      local height = vim.api.nvim_win_get_height(win)
      local width = vim.api.nvim_win_get_width(win)

      if row >= win_row and row < win_row + height and col >= win_col and col < win_col + width then
        return win
      end
    end
  end
  return nil
end

function M._edge_scroll(win, screen_x, screen_y, config)
  if not config.cursor.edge_scroll.enabled then
    return
  end

  local pos = vim.api.nvim_win_get_position(win)
  local height = vim.api.nvim_win_get_height(win)
  local width = vim.api.nvim_win_get_width(win)

  local cell_width = 8
  local cell_height = 16
  local margin = config.cursor.edge_scroll.margin
  local speed = config.cursor.edge_scroll.speed

  local col_cell = math.floor(screen_x / cell_width)
  local row_cell = math.floor(screen_y / cell_height)

  local rel_row = row_cell - pos[1]
  local rel_col = col_cell - pos[2]

  -- Scroll vertically
  if rel_row < margin then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. speed .. "\\<C-y>")
    end)
  elseif rel_row > height - margin then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. speed .. "\\<C-e>")
    end)
  end

  -- Scroll horizontally
  if rel_col < margin then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. speed .. "zh")
    end)
  elseif rel_col > width - margin then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. speed .. "zl")
    end)
  end
end

function M.reset()
  smoothing_state.x = nil
  smoothing_state.y = nil
  smoothing_state.window = {}
  last_cursor_pos = nil
end

return M
