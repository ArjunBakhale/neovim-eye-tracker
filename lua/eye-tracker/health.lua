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

  -- Check Python dependencies for jeo-eyetracker backend
  M._check_python()

  -- Check for external SDKs
  M._check_sdk("Tobii Stream Engine", { "libtobii_stream_engine" })
  M._check_sdk("EyeWare Beam", { "eyeware_beam" })
end

function M._check_python()
  -- python3 executable
  if vim.fn.executable("python3") ~= 1 then
    vim.health.warn("python3 not found in PATH", {
      "Install Python 3 for jeo-eyetracker backend",
    })
    return
  end
  vim.health.ok("python3 found")

  -- numpy
  local numpy_out = vim.fn.system("python3 -c \"import numpy; print(numpy.__version__)\"")
  if vim.v.shell_error ~= 0 then
    vim.health.warn("numpy not installed", {
      "pip install 'numpy<2.0'",
    })
  else
    local version = vim.trim(numpy_out)
    local major = tonumber(version:match("^(%d+)"))
    if major and major >= 2 then
      vim.health.error("numpy " .. version .. " not supported (need < 2.0)", {
        "pip install 'numpy<2.0'",
      })
    else
      vim.health.ok("numpy " .. version)
    end
  end

  -- opencv
  local cv_out = vim.fn.system("python3 -c \"import cv2; print(cv2.__version__)\"")
  if vim.v.shell_error ~= 0 then
    vim.health.warn("opencv-python not installed", {
      "pip install 'opencv-python>=4.5'",
    })
  else
    vim.health.ok("opencv-python " .. vim.trim(cv_out))
  end
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
