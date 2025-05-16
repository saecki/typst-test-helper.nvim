---@class Test
---@field line_idx integer
---@field line_len integer
---@field name string
---@field html boolean
---@field render boolean

---@class Config
---@field on_attach fun(buf: integer)
---@field programs table<string,string[]>

local M = {}

local cfg = {
    programs = {
        identity = { "flatpak", "run", "--file-forwarding", "org.gnome.gitlab.YaLTeR.Identity", "@@" },
    }
}

---@type table<integer,Test>
local cache = {}

local ns = vim.api.nvim_create_namespace("typst-test-helper")

---@param name string
---@return string
---@return string
local function image_paths(name)
    local root_dir = vim.fs.root(0, ".git")
    local ref_path = vim.fs.joinpath(root_dir, string.format("tests/ref/%s.png", name))
    local live_path = vim.fs.joinpath(root_dir, string.format("tests/store/render/%s.png", name))

    return ref_path, live_path
end

---@param buf integer
local function update(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)

    local tests = {}
    for line_nr, line in ipairs(lines) do
        local test_name, attributes = line:match("^%-%-%- ([%d%w-]+)([%d%w%s-]-) %-%-%-$")
        if not test_name then
            goto continue
        end

        local test = {
            line_idx = line_nr - 1,
            line_len = #line,
            name = test_name,
        }

        -- parse test attributes
        while attributes ~= "" do
            local attr, end_pos = attributes:match("^ ([%d%w-]+)()")
            if attr == "html" then
                test.html = true
            elseif attr == "render" then
                test.render = true
            else
                goto continue
            end
            attributes = string.sub(attributes, end_pos)
        end
        if not test.html then
            -- if no attribute is specified, default to render
            test.render = true
        end

        table.insert(tests, test)

        ::continue::
    end

    cache[buf] = tests

    local diagnostics = {}
    for _, test in ipairs(tests) do
        local msg = ""
        if test.html then
            msg = msg .. "  "
        end
        if test.render then
            msg = msg .. "  "
        end
        table.insert(diagnostics, {
            bufnr = buf,
            lnum = test.line_idx,
            col = 0,
            end_col = test.line_len,
            severity = vim.diagnostic.severity.HINT,
            message = msg,
        })
    end
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local opts = {
        virtual_text = {
            prefix = "test",
        },
        signs = {
            text = {
                [vim.diagnostic.severity.HINT] = "",
            },
        },
    }
    vim.diagnostic.set(ns, buf, diagnostics, opts)
end

---@return Test?
local function get_test_at_cursor()
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_idx = cursor[1] - 1

    local tests = cache[buf]
    if not tests then
        return nil
    end

    for i, test in ipairs(tests) do
        if line_idx < test.line_idx then
            goto continue
        end
        local next_test = tests[i + 1]
        if not next_test or next_test.line_idx > line_idx then
            return test
        end

        ::continue::
    end
end

---@param cmd string|string[]
function M.open(cmd)
    local current_test = get_test_at_cursor()
    if not current_test then
        vim.notify("no typst test found at cursor location")
        return
    end

    local ref_path, live_path = image_paths(current_test.name)

    if type(cmd) == "string" then
        cmd = vim.deepcopy(cfg.programs[cmd])
    end
    table.insert(cmd, ref_path)
    table.insert(cmd, live_path)
    vim.system(cmd, { detach = true })
end

---@param cmd string|string[]
function M.map_open(cmd)
    return function()
        M.open(cmd)
    end
end

function M.setup(user_cfg)
    cfg = vim.tbl_deep_extend('force', cfg, user_cfg)

    local group = vim.api.nvim_create_augroup("typst-test-helper", {})
    vim.api.nvim_create_autocmd("BufRead", {
        group = group,
        pattern = "tests/**/*.typ",
        callback = function(ev)
            if cfg and cfg.on_attach then
                cfg.on_attach(ev.buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "tests/**/*.typ",
        callback = function(ev)
            update(ev.buf)
        end,
    })
    vim.api.nvim_create_autocmd("BufLeave", {
        group = group,
        pattern = "tests/**/*.typ",
        callback = function(ev)
            vim.api.nvim_buf_clear_namespace(ev.buf, ns, 0, -1)
            vim.diagnostic.set(ns, ev.buf, {}, {})
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group,
        pattern = "tests/**/*.typ",
        callback = function(ev)
            update(ev.buf)
        end,
    })
end

return M
