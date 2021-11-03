---@class Popup
---@field win integer|nil
---@field buf integer|nil
---@field namespace_id integer|nil
---@field type string|nil
---@field feat_ctx FeatureContext|nil

---@class FeatureContext
---@field buf integer
---@field crate Crate
---@field version Version
---@field history HistoryEntry[]
---@field history_index integer

---@class HistoryEntry
---@field feature Feature|nil
---@field line integer -- 1 indexed

---@class WinOpts
---@field focus boolean
---@field line integer -- 1 indexed

---@class HighlightText
---@field text string
---@field hi string

---@class LineCrateInfo
---@field pref string
---@field crate Crate
---@field versions Version[]
---@field newest Version|nil
---@field feature Feature|nil

---@type Popup
local M = {}

local core = require('crates.core')
local toml = require('crates.toml')
local Crate = toml.Crate
local util = require('crates.util')
local Range = require('crates.types').Range

local top_offset = 2

---@return LineCrateInfo
local function line_crate_info()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1
    local col = pos[2]

    local crates = util.get_lines_crates(Range.new(line, line + 1))
    if not crates or not crates[1] or not crates[1].versions then
        return nil
    end
    local crate = crates[1].crate
    local versions = crates[1].versions

    local avoid_pre = core.cfg.avoid_prerelease and not crate.req_has_suffix
    local newest = util.get_newest(versions, avoid_pre, crate.reqs)

    local info = {
        crate = crate,
        versions = versions,
        newest = newest,
    }

    local function versions_info()
        info.pref = "versions"
    end

    local function features_info()
        for _,cf in ipairs(crate.feats) do
            if cf.decl_col:contains(col - crate.feat_col.s) then
                info.feature = newest.features:get_feat(cf.name)
                break
            end
        end

        if info.feature then
            info.pref = "feature_details"
        else
            info.pref = "features"
        end
    end

    local function default_features_info()
        info.feature = info.newest.features:get_feat("default") or {
            name = "default",
            members = {},
        }
        info.pref = "feature_details"
    end

    if crate.syntax == "plain" then
        versions_info()
    elseif crate.syntax == "table" then
        if line == crate.feat_line then
            features_info()
        elseif line == crate.def_line then
            default_features_info()
        else
            versions_info()
        end
    elseif crate.syntax == "inline_table" then
        if crate.feat_text and line == crate.feat_line and crate.feat_decl_col:contains(col) then
            features_info()
        elseif crate.def_text and line == crate.def_line and crate.def_decl_col:contains(col) then
            default_features_info()
        else
            versions_info()
        end
    end

    return info
end

function M.show()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        M.focus()
        return
    end

    local info = line_crate_info()
    if not info then return end

    if info.pref == "versions" then
        M.open_versions(info.crate, info.versions)
    elseif info.pref == "features" then
        M.open_features(info.crate, info.newest)
    elseif info.pref == "feature_details" then
        M.open_feature_details(info.crate, info.newest, info.feature)
    end
end

function M.show_versions()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        if M.type == "versions" then
            M.focus()
            return
        else
            M.hide()
        end
    end

    local info = line_crate_info()
    if not info then return end

    M.open_versions(info.crate, info.versions)
end

function M.show_features()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        if M.type == "features" then
            M.focus()
            return
        else
            M.hide()
        end
    end

    local info = line_crate_info()
    if not info then return end

    if info.pref == "features" then
        M.open_features(info.crate, info.newest)
    elseif info.pref == "feature_details" then
        M.open_feature_details(info.crate, info.newest, info.feature)
    elseif info.newest then
        M.open_features(info.crate, info.newest)
    end
end

---@param line integer
function M.focus(line)
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_set_current_win(M.win)
        local l = math.min(line or 3, vim.api.nvim_buf_line_count(M.buf))
        vim.api.nvim_win_set_cursor(M.win, { l, 0 })
    end
end

function M.hide()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, false)
    end
    M.win = nil

    if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
        vim.api.nvim_buf_delete(M.buf, {})
    end
    M.buf = nil
    M.namespace_id = nil
    M.type = nil
end

---@param width integer
---@param height integer
local function create_win(width, height)
    -- create window
    local opts = {
        relative = "cursor",
        col = 0,
        row = 1,
        width = width,
        height = height,
        style = core.cfg.popup.style,
        border = core.cfg.popup.border,
    }
    M.win = vim.api.nvim_open_win(M.buf, false, opts)
end

---@param width integer
---@param height integer
---@param title string
---@param text HighlightText[]
---@param opts WinOpts
---@param configure fun()
local function open_win(width, height, title, text, opts, configure)
    M.buf = vim.api.nvim_create_buf(false, true)
    M.namespace_id = vim.api.nvim_create_namespace("crates.nvim.popup")

    -- add text and highlights
    vim.api.nvim_buf_set_lines(M.buf, 0, 2, false, { title, "" })
    vim.api.nvim_buf_add_highlight(M.buf, M.namespace_id, core.cfg.popup.highlight.title, 0, 0, -1)

    for i,v in ipairs(text) do
        vim.api.nvim_buf_set_lines(M.buf, top_offset + i - 1, top_offset + i, false, { v.text })
        vim.api.nvim_buf_add_highlight(M.buf, M.namespace_id, v.hi, top_offset + i - 1, 0, -1)
    end

    vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

    -- create window
    create_win(width, height)

    -- add key mappings
    local hide_cmd = ":lua require('crates.popup').hide()<cr>"
    for _,k in ipairs(core.cfg.popup.keys.hide) do
        vim.api.nvim_buf_set_keymap(M.buf, "n", k, hide_cmd, { noremap = true, silent = true })
    end

    if configure then
        configure()
    end

    -- autofocus
    if opts and opts.focus or core.cfg.popup.autofocus then
        M.focus(opts and opts.line)
    end
end


---@param crate Crate
---@param versions Version[]
---@param opts WinOpts
function M.open_versions(crate, versions, opts)
    M.type = "versions"
    local title = string.format(core.cfg.popup.text.title, crate.name)
    local num_versions = #versions
    local height = math.min(core.cfg.popup.max_height, num_versions + top_offset)
    local width = 0
    local versions_text = {}

    for _,v in ipairs(versions) do
        local text, hi
        if v.yanked then
            text = string.format(core.cfg.popup.text.yanked, v.num)
            hi = core.cfg.popup.highlight.yanked
        elseif v.parsed.suffix then
            text = string.format(core.cfg.popup.text.prerelease, v.num)
            hi = core.cfg.popup.highlight.prerelease
        else
            text = string.format(core.cfg.popup.text.version, v.num)
            hi = core.cfg.popup.highlight.version
        end


        table.insert(versions_text, { text = text, hi = hi })
        width = math.max(vim.fn.strdisplaywidth(text), width)
    end

    if core.cfg.popup.version_date then
        local orig_width = width

        for i,v in ipairs(versions_text) do
            local diff = orig_width - vim.fn.strdisplaywidth(v.text)
            local date = versions[i].created:display(core.cfg.date_format)
            local date_text = string.format(core.cfg.popup.text.date, date)
            v.text = v.text..string.rep(" ", diff)..date_text

            width = math.max(vim.fn.strdisplaywidth(v.text), orig_width)
        end
    end

    width = math.max(width, core.cfg.popup.min_width, vim.fn.strdisplaywidth(title))


    open_win(width, height, title, versions_text, opts, function()
        local select_cmd = string.format(
            ":lua require('crates.popup').select_version(%d, '%s', %s - %d)<cr>",
            util.current_buf(),
            crate.name,
            "vim.api.nvim_win_get_cursor(0)[1]",
            top_offset
        )
        for _,k in ipairs(core.cfg.popup.keys.select) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, select_cmd, { noremap = true, silent = true })
        end

        local select_dumb_cmd = string.format(
            ":lua require('crates.popup').select_version(%d, '%s', %s - %d, false)<cr>",
            util.current_buf(),
            crate.name,
            "vim.api.nvim_win_get_cursor(0)[1]",
            top_offset
        )
        for _,k in ipairs(core.cfg.popup.keys.select_dumb) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, select_dumb_cmd, { noremap = true, silent = true })
        end

        local copy_cmd = string.format(
            ":lua require('crates.popup').copy_version('%s', %s - %d)<cr>",
            crate.name,
            "vim.api.nvim_win_get_cursor(0)[1]",
            top_offset
        )
        for _,k in ipairs(core.cfg.popup.keys.copy_version) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, copy_cmd, { noremap = true, silent = true })
        end
    end)
end

---@param buf integer
---@param name string
---@param index integer
---@param smart boolean | nil
function M.select_version(buf, name, index, smart)
    local crates = core.crate_cache[buf]
    if not crates then return end

    local crate = crates[name]
    if not crate or not crate.reqs then return end

    local versions = core.vers_cache[name]
    if not versions then return end

    local version = versions[index]
    if not version then return end

    if smart == nil then
        smart = core.cfg.smart_insert
    end

    if smart then
        util.set_version_smart(buf, crate, version.parsed)
    else
        util.set_version(buf, crate, version.num)
    end

    -- update crate position
    local line = vim.api.nvim_buf_get_lines(buf, crate.req_line, crate.req_line + 1, false)[1]
    line = toml.trim_comments(line)
    local c = nil
    if crate.syntax == "table" then
        c = toml.parse_crate_table_req(line)
    elseif crate.syntax == "plain" then
        c = toml.parse_crate(line)
    elseif crate.syntax == "inline_table" then
        c = toml.parse_crate(line)
    end
    if c then
        crate.req_col = c.req_col
    end
end

---@param name string
---@param index integer
function M.copy_version(name, index)
    local versions = core.vers_cache[name]
    if not versions then return end

    if index <= 0 or index > #versions then
        return
    end
    local text = versions[index].num

    vim.fn.setreg(core.cfg.popup.copy_register, text)
end


---@param features_info table<string, FeatureInfo>
---@param feature Feature
---@return HighlightText
local function feature_text(features_info, feature)
    local text, hi
    local info = features_info[feature.name]
    if info.enabled then
        text = string.format(core.cfg.popup.text.enabled, feature.name)
        hi = core.cfg.popup.highlight.enabled
    elseif info.transitive then
        text = string.format(core.cfg.popup.text.transitive, feature.name)
        hi = core.cfg.popup.highlight.transitive
    else
        text = string.format(core.cfg.popup.text.feature, feature.name)
        hi = core.cfg.popup.highlight.feature
    end
    return { text = text, hi = hi }
end

---@param width integer
---@param height integer
---@param title string
---@param text HighlightText[]
---@param opts WinOpts
local function open_feat_win(width, height, title, text, opts)
    open_win(width, height, title, text, opts, function()
        local toggle_cmd = string.format(
            ":lua require('crates.popup').toggle_feature(%s - %d)<cr>",
            "vim.api.nvim_win_get_cursor(0)[1]",
            top_offset
        )
        for _,k in ipairs(core.cfg.popup.keys.toggle_feature) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, toggle_cmd, { noremap = true, silent = true })
        end

        local goto_cmd = string.format(
            ":lua require('crates.popup').goto_feature(%s - %d)<cr>",
            "vim.api.nvim_win_get_cursor(0)[1]",
            top_offset
        )
        for _,k in ipairs(core.cfg.popup.keys.goto_feature) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, goto_cmd, { noremap = true, silent = true })
        end

        local jump_forward_cmd = string.format(
            ":lua require('crates.popup').jump_forward_feature(%s)<cr>",
            "vim.api.nvim_win_get_cursor(0)[1]"
        )
        for _,k in ipairs(core.cfg.popup.keys.jump_forward_feature) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, jump_forward_cmd, { noremap = true, silent = true })
        end

        local jump_back_cmd = string.format(
            ":lua require('crates.popup').jump_back_feature(%s)<cr>",
            "vim.api.nvim_win_get_cursor(0)[1]"
        )
        for _,k in ipairs(core.cfg.popup.keys.jump_back_feature) do
            vim.api.nvim_buf_set_keymap(M.buf, "n", k, jump_back_cmd, { noremap = true, silent = true })
        end
    end)
end

---@param crate Crate
---@param version Version
---@param opts WinOpts
function M.open_features(crate, version, opts)
    M.type = "features"
    M.feat_ctx = {
        buf = util.current_buf(),
        crate = crate,
        version = version,
        history = {
            { feature = nil, line = opts and opts.line or 3 },
        },
        history_index = 1,
    }
    M._open_features(crate, version, opts)
end

---@param crate Crate
---@param version Version
---@param opts WinOpts
function M._open_features(crate, version, opts)
    local features = version.features
    local title = string.format(core.cfg.popup.text.title, crate.name.." "..version.num)
    local num_feats = #features
    local height = math.min(core.cfg.popup.max_height, num_feats + top_offset)
    local width = math.max(core.cfg.popup.min_width, title:len())
    local features_text = {}

    local features_info = util.features_info(crate, features)
    for _,f in ipairs(features) do
        local hi_text = feature_text(features_info, f)
        table.insert(features_text, hi_text)
        width = math.max(hi_text.text:len(), width)
    end

    open_feat_win(width, height, title, features_text, opts)
end

---@param crate Crate
---@param version Version
---@param feature Feature
---@param opts WinOpts
function M.open_feature_details(crate, version, feature, opts)
    M.type = "features"
    M.feat_ctx = {
        buf = util.current_buf(),
        crate = crate,
        version = version,
        history = {
            { feature = nil, line = 3 },
            { feature = feature, line = opts and opts.line or 3 },
        },
        history_index = 2,
    }
    M._open_feature_details(crate, version, feature, opts)
end

---@param crate Crate
---@param version Version
---@param feature Feature
---@param opts WinOpts
function M._open_feature_details(crate, version, feature, opts)
    local features = version.features
    local members = feature.members
    local title = string.format(core.cfg.popup.text.title, crate.name.." "..version.num.." "..feature.name)
    local num_members = #members
    local height = math.min(core.cfg.popup.max_height, num_members + top_offset)
    local width = math.max(core.cfg.popup.min_width, title:len())
    local features_text = {}

    local features_info = util.features_info(crate, features)
    for _,m in ipairs(members) do
        local f = features:get_feat(m) or {
            name = m,
            members = {},
        }

        local hi_text = feature_text(features_info, f)
        table.insert(features_text, hi_text)
        width = math.max(hi_text.text:len(), width)
    end

    open_feat_win(width, height, title, features_text, opts)
end

---@param index integer
function M.toggle_feature(index)
    if not M.feat_ctx then return end

    local buf = M.feat_ctx.buf
    local crate = M.feat_ctx.crate
    local version = M.feat_ctx.version
    local features = version.features
    local hist_index = M.feat_ctx.history_index
    local feature = M.feat_ctx.history[hist_index].feature

    local selected_feature = nil
    if feature then
        local m = feature.members[index]
        if m then
            selected_feature = features:get_feat(m)
        end
    else
        selected_feature = features[index]
    end
    if not selected_feature then return end

    local line_range
    local crate_feature = crate:get_feat(selected_feature.name)
    if selected_feature.name == "default" then
        if crate_feature or crate.def ~= false then
            line_range = util.disable_def_features(buf, crate, crate_feature)
        else
            line_range = util.enable_def_features(buf, crate)
        end
    else
        if crate_feature then
            line_range = util.disable_feature(buf, crate, crate_feature)
        else
            line_range = util.enable_feature(buf, crate, selected_feature)
        end
    end

    -- update crate
    local c = {}
    for l in line_range:iter() do
        local line = vim.api.nvim_buf_get_lines(buf, l, l + 1, false)[1]
        line = toml.trim_comments(line)
        if crate.syntax == "table" then
            local cr = toml.parse_crate_table_req(line)
            if cr then
                cr.req_line = l
                table.insert(c, cr)
            end
            local cf = toml.parse_crate_table_feat(line)
            if cf then
                cf.feat_line = l
                table.insert(c, cf)
            end
            local cd = toml.parse_crate_table_def(line)
            if cd then
                cd.def_line = l
                table.insert(c, cd)
            end
        elseif crate.syntax == "plain" or crate.syntax == "inline_table" then
            local cf = toml.parse_crate(line)
            if cf and cf.req_text then
                cf.req_line = l
            end
            if cf and cf.feat_text then
                cf.feat_line = l
            end
            if cf and cf.def_text then
                cf.def_line = l
            end
            table.insert(c, cf)
        end
    end
    M.feat_ctx.crate = Crate.new(vim.tbl_extend("force", crate, table.unpack(c)))
    crate = M.feat_ctx.crate

    -- update buffer
    local features_text = {}
    local features_info = util.features_info(crate, features)
    if feature then
        for _,m in ipairs(feature.members) do
            local f = features:get_feat(m) or {
                name = m,
                members = {},
            }

            local hi_text = feature_text(features_info, f)
            table.insert(features_text, hi_text)
        end
    else
        for _,f in ipairs(features) do
            local hi_text = feature_text(features_info, f)
            table.insert(features_text, hi_text)
        end
    end

    vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
    for i,v in ipairs(features_text) do
        vim.api.nvim_buf_set_lines(M.buf, top_offset + i - 1, top_offset + i, false, { v.text })
        vim.api.nvim_buf_add_highlight(M.buf, M.namespace_id, v.hi, top_offset + i - 1, 0, -1)
    end
    vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

---@param index integer
function M.goto_feature(index)
    if not M.feat_ctx then return end

    local crate = M.feat_ctx.crate
    local version = M.feat_ctx.version
    local hist_index = M.feat_ctx.history_index
    local feature = M.feat_ctx.history[hist_index].feature

    local selected_feature = nil
    if feature then
        local m = feature.members[index]
        if m then
            selected_feature = version.features:get_feat(m)
        end
    else
        selected_feature = version.features[index]
    end
    if not selected_feature then return end

    M.hide()
    M._open_feature_details(crate, version, selected_feature, { focus = true })

    -- update current entry
    local current = M.feat_ctx.history[hist_index]
    current.line = index + top_offset

    M.feat_ctx.history_index = hist_index + 1
    hist_index = M.feat_ctx.history_index
    for i=hist_index, #M.feat_ctx.history, 1 do
        M.feat_ctx.history[i] = nil
    end

    M.feat_ctx.history[hist_index] = {
        feature = selected_feature,
        line = 3,
    }
end

---@param line integer
function M.jump_back_feature(line)
    if not M.feat_ctx then return end

    local crate = M.feat_ctx.crate
    local version = M.feat_ctx.version
    local hist_index = M.feat_ctx.history_index

    if hist_index == 1 then
        M.hide()
        return
    end

    -- update current entry
    local current = M.feat_ctx.history[hist_index]
    current.line = line

    M.feat_ctx.history_index = hist_index - 1
    hist_index = M.feat_ctx.history_index

    if hist_index == 1 then
        M.hide()
        M._open_features(crate, version, {
            focus = true,
            line = M.feat_ctx.history[1].line,
        })
    else
        local entry = M.feat_ctx.history[hist_index]
        if not entry then return end

        M.hide()
        M._open_feature_details(crate, version, entry.feature, {
            focus = true,
            line = entry.line,
        })
    end
end

---@param line integer
function M.jump_forward_feature(line)
    if not M.feat_ctx then return end

    local crate = M.feat_ctx.crate
    local version = M.feat_ctx.version
    local hist_index = M.feat_ctx.history_index

    if hist_index == #M.feat_ctx.history then
        return
    end

    -- update current entry
    local current = M.feat_ctx.history[hist_index]
    current.line = line

    M.feat_ctx.history_index = hist_index + 1
    hist_index = M.feat_ctx.history_index

    local entry = M.feat_ctx.history[hist_index]
    if not entry then return end

    M.hide()
    M._open_feature_details(crate, version, entry.feature, {
        focus = true,
        line = entry.line,
    })
end

return M
