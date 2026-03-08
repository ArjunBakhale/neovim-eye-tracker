local M = {}

function M.check()
  vim.health.start("eye-tracker")

  -- Check Neovim version
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim >= 0.9 required", { "Update Neovim to 0.9 or later" })
  end

  -- Check if setup() has been called
  local config = require("eye-tracker.config")
  if config.is_setup() then
    vim.health.ok("setup() has been called")
  else
    vim.health.warn("setup() has not been called", {
      'Add require("eye-tracker").setup() to your config',
    })
  end

  -- Check backend status
  local tracker = require("eye-tracker.tracker")
  local info = tracker.get_info()
  if info.status == "running" then
    vim.health.ok("Backend '" .. info.name .. "' is active (connected: " .. tostring(info.connected) .. ")")
  else
    vim.health.info("No backend active (start with :EyeTrackerEnable)")
  end

  -- Check for external SDKs
  M._check_sdk("Tobii Stream Engine", { "libtobii_stream_engine" })
  M._check_sdk("EyeWare Beam", { "eyeware_beam" })
end

function M._check_sdk(name, lib_names)
  for _, lib in ipairs(lib_names) do
    local found = vim.fn.executable(lib) == 1
    if not found then
      -- Also check common library paths
      local paths = {
        "/usr/lib",
        "/usr/local/lib",
        "/opt/homebrew/lib",
      }
      for _, path in ipairs(paths) do
        if vim.fn.globpath(path, lib .. ".*") ~= "" then
          found = true
          break
        end
      end
    end

    if found then
      vim.health.ok(name .. " SDK found")
      return
    end
  end

  vim.health.info(name .. " SDK not found (optional)")
end

return M
