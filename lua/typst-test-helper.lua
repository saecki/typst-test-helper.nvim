---@class Test
---@field line_idx integer
---@field name string

local M = {}

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
        local test_name = line:match("^%-%-%- ([%d%w-]+) %-%-%-$")
        if test_name then
            table.insert(tests, {
                line_idx = line_nr - 1,
                line_len = #line,
                name = test_name,
            })
        end
    end

    cache[buf] = tests

    local diagnostics = {}
    for _, test in ipairs(tests) do
        table.insert(diagnostics, {
            bufnr = buf,
            lnum = test.line_idx,
            col = 0,
            end_col = test.line_len,
            severity = vim.diagnostic.severity.HINT,
            message = "[typst-test]"
        })
    end
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local opts = {
        signs = {
            text = {
                [vim.diagnostic.severity.HINT] = "T",
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

function M.open_identity()
    local current_test = get_test_at_cursor()
    if not current_test then
        vim.notify("no typst test found at cursor location")
        return
    end

    local ref_path, live_path = image_paths(current_test.name)
    local cmd = { "flatpak", "run", "--file-forwarding", "org.gnome.gitlab.YaLTeR.Identity", "@@", ref_path, live_path }
    vim.system(cmd, { detach = true })
end

function M.setup(cfg)
    local group = vim.api.nvim_create_augroup("typst-test-helper", {})
    vim.api.nvim_create_autocmd("BufRead", {
        group = group,
        pattern = "tests/**/*.typ",
        callback = function(ev)
            if cfg and cfg.on_attach then
                cfg.on_attach(ev.buf)
            end
            update(ev.buf)
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
