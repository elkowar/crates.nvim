local M = {}
































































local actions = require("crates.actions")
local config = require("crates.config")
local Config = config.Config
local core = require("crates.core")
local popup = require("crates.popup")
local state = require("crates.state")
local ui = require("crates.ui")
local util = require("crates.util")

function M.setup(cfg)
   state.cfg = config.build(cfg)

   local group = vim.api.nvim_create_augroup("Crates", {})
   if state.cfg.autoload then
      vim.api.nvim_create_autocmd("BufRead", {
         group = group,
         pattern = "Cargo.toml",
         callback = function()
            M.update()
         end,
      })
   end
   if state.cfg.autoupdate then
      local async = require("crates.async")
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
         group = group,
         pattern = "Cargo.toml",
         callback = async.throttle(function()
            M.update()
         end, state.cfg.autoupdate_throttle),
      })
   end

   vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      pattern = "Cargo.toml",
      callback = function()
         popup.hide()
      end,
   })

   if state.cfg.src.coq.enabled then
      require("crates.src.coq").setup(state.cfg.src.coq.name)
   end

   if state.cfg.null_ls.enabled then
      require("crates.null-ls").setup(state.cfg.null_ls.name)
   end

   vim.api.nvim_set_hl(0, "CratesNvimLoading", { default = true, link = "DiagnosticVirtualTextInfo" })
   vim.api.nvim_set_hl(0, "CratesNvimVersion", { default = true, link = "DiagnosticVirtualTextInfo" })
   vim.api.nvim_set_hl(0, "CratesNvimPreRelease", { default = true, link = "DiagnosticVirtualTextWarn" })
   vim.api.nvim_set_hl(0, "CratesNvimYanked", { default = true, link = "DiagnosticVirtualTextError" })
   vim.api.nvim_set_hl(0, "CratesNvimNoMatch", { default = true, link = "DiagnosticVirtualTextError" })
   vim.api.nvim_set_hl(0, "CratesNvimUpgrade", { default = true, link = "DiagnosticVirtualTextWarn" })
   vim.api.nvim_set_hl(0, "CratesNvimError", { default = true, link = "DiagnosticVirtualTextError" })

   vim.api.nvim_set_hl(0, "CratesNvimPopupTitle", { default = true, link = "Title" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupPillText", { default = true, ctermfg = 15, ctermbg = 242, fg = "#e0e0e0", bg = "#3a3a3a" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupPillBorder", { default = true, ctermfg = 242, fg = "#3a3a3a" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupDescription", { default = true, link = "Comment" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupLabel", { default = true, link = "Identifier" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupValue", { default = true, link = "String" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupUrl", { default = true, link = "Underlined" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupVersion", { default = true, link = "None" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupPreRelease", { default = true, link = "DiagnosticVirtualTextWarn" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupYanked", { default = true, link = "DiagnosticVirtualTextError" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupVersionDate", { default = true, link = "Comment" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupFeature", { default = true, link = "None" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupEnabled", { default = true, ctermfg = 2, fg = "#23ab49" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupTransitive", { default = true, ctermfg = 4, fg = "#238bb9" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupNormalDependenciesTitle", { default = true, link = "Statement" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupBuildDependenciesTitle", { default = true, link = "Statement" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupDevDependenciesTitle", { default = true, link = "Statement" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupDependency", { default = true, link = "None" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupOptional", { default = true, link = "Comment" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupDependencyVersion", { default = true, link = "String" })
   vim.api.nvim_set_hl(0, "CratesNvimPopupLoading", { default = true, link = "Special" })
end

function M.hide()
   state.visible = false
   for b, _ in pairs(state.buf_cache) do
      ui.clear(b)
   end
end

function M.show()
   state.visible = true


   local buf = util.current_buf()
   core.update(buf, false)

   for b, _ in pairs(state.buf_cache) do
      if b ~= buf then
         core.update(b, false)
      end
   end
end

function M.toggle()
   if state.visible then
      M.hide()
   else
      M.show()
   end
end

function M.update(buf)
   core.update(buf, false)
end

function M.reload(buf)
   core.update(buf, true)
end

M.upgrade_crate = actions.upgrade_crate
M.upgrade_crates = actions.upgrade_crates
M.upgrade_all_crates = actions.upgrade_all_crates
M.update_crate = actions.update_crate
M.update_crates = actions.update_crates
M.update_all_crates = actions.update_all_crates
M.open_homepage = actions.open_homepage
M.open_repository = actions.open_repository
M.open_documentation = actions.open_documentation
M.open_crates_io = actions.open_crates_io

M.popup_available = popup.available
M.show_popup = popup.show
M.show_crate_popup = popup.show_crate
M.show_versions_popup = popup.show_versions
M.show_features_popup = popup.show_features
M.show_dependencies_popup = popup.show_dependencies
M.focus_popup = popup.focus
M.hide_popup = popup.hide

return M
