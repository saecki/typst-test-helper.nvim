---@class Test
---@field line_idx integer
---@field line_len integer
---@field name string
---@field html boolean
---@field pdftags boolean
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


local ns = vim.api.nvim_create_namespace("typst-test-helper")

---@type table<integer,Test>
local cache = {}
---@type integer?
local term_win = nil
---@type integer?
local diff_win = nil
---@type string[]
local last_test_args = nil

---@param ... string
local function run_test(...)
    last_test_args = { ... }

    local cmd = { "cargo", "test", "--workspace", "--test=tests", "--", ... }

    if term_win and vim.api.nvim_win_is_valid(term_win) then
        vim.api.nvim_set_current_win(term_win)
    else
        vim.cmd.split()
        term_win = vim.api.nvim_get_current_win()
    end
    vim.cmd.term(cmd)
end

---@param name string
---@return string
---@return string
local function image_paths(name)
    local root_dir = vim.fs.root(0, ".git")
    local ref_path = vim.fs.joinpath(root_dir, string.format("tests/ref/%s.png", name))
    local live_path = vim.fs.joinpath(root_dir, string.format("tests/store/render/%s.png", name))
    return ref_path, live_path
end

---@param name string
---@return string
---@return string
local function html_paths(name)
    local root_dir = vim.fs.root(0, ".git")
    local ref_path = vim.fs.joinpath(root_dir, string.format("tests/ref/html/%s.html", name))
    local live_path = vim.fs.joinpath(root_dir, string.format("tests/store/html/%s.html", name))
    return ref_path, live_path
end

---@param name string
---@return string
---@return string
local function pdftags_paths(name)
    local root_dir = vim.fs.root(0, ".git")
    local ref_path = vim.fs.joinpath(root_dir, string.format("tests/ref/pdftags/%s.yml", name))
    local live_path = vim.fs.joinpath(root_dir, string.format("tests/store/pdftags/%s.yml", name))
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
            elseif attr == "pdftags" then
                test.pdftags = true
            elseif attr == "render" then
                test.render = true
            elseif attr == "large" then
                -- ignored for now
            else
                goto continue
            end
            attributes = string.sub(attributes, end_pos)
        end
        if not (test.html or test.pdftags) then
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
        if test.pdftags then
            msg = msg .. " "
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

---@return Test?
local function require_test_at_cursor()
    local test = get_test_at_cursor()
    if test then
        return test
    end
    vim.notify("no typst test found at cursor location")
end

---@param cmd string|string[]
function M.open_render(cmd)
    local test = require_test_at_cursor()
    if not test then return end

    if not test.render then
        vim.notify("not a rendered test")
        return
    end

    local ref_path, live_path = image_paths(test.name)

    if type(cmd) == "string" then
        cmd = vim.deepcopy(cfg.programs[cmd])
    end
    table.insert(cmd, ref_path)
    table.insert(cmd, live_path)
    vim.system(cmd, { detach = true })
end

---@param cmd string|string[]
function M.map_open_render(cmd)
    return function()
        M.open_render(cmd)
    end
end

---@param ref_path string
---@param live_path string
local function open_diff(ref_path, live_path)
    vim.cmd.diffoff({ bang = true })

    local cur_win = vim.api.nvim_get_current_win()
    vim.cmd.edit(ref_path)
    vim.cmd.diffthis()

    if diff_win and vim.api.nvim_win_is_valid(diff_win) then
        vim.api.nvim_set_current_win(diff_win)
        vim.cmd.edit(live_path)
        vim.cmd.diffthis()
    else
        vim.cmd.vsplit(live_path)
        vim.cmd.diffthis()
        diff_win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_set_current_win(cur_win)
end

function M.open_html()
    local test = require_test_at_cursor()
    if not test then return end

    if not test.html then
        vim.notify("no `html` attribute")
        return
    end

    local ref_path, live_path = html_paths(test.name)
    open_diff(ref_path, live_path)
end

function M.open_pdftags()
    local test = require_test_at_cursor()
    if not test then return end

    if not test.pdftags then
        vim.notify("no `pdftags` attribute")
        return
    end

    local ref_path, live_path = pdftags_paths(test.name)
    open_diff(ref_path, live_path)
end

---@param args string[]?
function M.run_test(args)
    local test = require_test_at_cursor()
    if not test then return end

    run_test("--exact", test.name, unpack(args or {}))
end

---@param args string[]?
function M.run_all_tests(args)
    run_test(unpack(args or {}))
end

function M.run_last_test()
    if not last_test_args then
        vim.notify("no last test")
        return
    end
    run_test(unpack(last_test_args))
end

---@param args string[]?
---@return fun()
function M.map_run_test(args)
    return function()
        M.run_test(args)
    end
end

local cli_args = {
    "--update",
    "--scale=",
    "--extended",
    "--pdf",
    "--svg",
    "--syntax",
    "--compact",
    "--verbose",
    "--parser-compare=",
}

---@param arglead string
---@param line string
---@return string[]
local function complete_command(arglead, line)
    local words = vim.iter(vim.split(line, "%s+"))
    words:next()

    local cmd = words:next()
    if cmd == nil then
        return {}
    end

    local args = words:totable()
    if #args == 0 then
        local cmds = {
            "run-test",
            "run-all-tests",
            "run-last-test",
            "open-render",
            "open-html",
            "open-pdftags",
        }
        return vim.iter(cmds)
            :filter(function(c) return vim.startswith(c, arglead) end)
            :totable()
    end

    if cmd == "run-test" then
        return vim.iter(cli_args)
            :filter(function(arg) return vim.startswith(arg, arglead) end)
            :filter(function(arg) return not vim.tbl_contains(args, arg) end)
            :totable()
    elseif cmd == "run-all-test" then
        return vim.iter(cli_args)
            :filter(function(arg) return vim.startswith(arg, arglead) end)
            :filter(function(arg) return not vim.tbl_contains(args, arg) end)
            :totable()
    elseif cmd == "run-last-test" then
        return {}
    elseif cmd == "open-render" then
        if #args == 1 then
            return vim.iter(cfg.programs)
                :map(function(prg, _) return prg end)
                :filter(function(prg) return vim.startswith(prg, arglead) end)
                :totable()
        end
    end

    return {}
end

---@param params table<string,any>
local function exec_command(params)
    local words = vim.iter(vim.split(params.args, "%s+"))

    local cmd = words:next()
    if cmd == nil then
        print(string.format("missing sub command"))
        return
    end

    if cmd == "run-test" then
        local args = words:totable()
        M.run_test(args)
    elseif cmd == "run-all-tests" then
        local args = words:totable()
        M.run_all_tests(args)
    elseif cmd == "run-last-test" then
        M.run_last_test()
    elseif cmd == "open-render" then
        local prg = words:next()
        if not cfg.programs[prg] then
            print(string.format("invalid program `%s`", prg))
            return
        end
        M.open_render(prg)
    elseif cmd == "open-html" then
        M.open_html()
    elseif cmd == "open-pdftags" then
        M.open_pdftags()
    else
        print(string.format("unknown sub command `%s`", cmd))
    end
end

function M.register()
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

    vim.api.nvim_create_user_command("TypstTest", exec_command, {
        nargs = 1,
        range = true,
        complete = complete_command,
    })
end

return M
