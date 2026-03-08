if vim.g.loaded_eye_tracker then
  return
end
vim.g.loaded_eye_tracker = true

vim.api.nvim_create_user_command("EyeTrackerEnable", function()
  require("eye-tracker").enable()
end, { desc = "Enable eye tracking" })

vim.api.nvim_create_user_command("EyeTrackerDisable", function()
  require("eye-tracker").disable()
end, { desc = "Disable eye tracking" })

vim.api.nvim_create_user_command("EyeTrackerToggle", function()
  require("eye-tracker").toggle()
end, { desc = "Toggle eye tracking" })

vim.api.nvim_create_user_command("EyeTrackerCalibrate", function()
  require("eye-tracker").calibrate()
end, { desc = "Calibrate eye tracker" })

vim.api.nvim_create_user_command("EyeTrackerStatus", function()
  require("eye-tracker").status()
end, { desc = "Show eye tracker status" })
