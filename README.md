# typst-test-helper.nvim

## Setup

```lua
local tth = require("typst-test-helper")

local function on_attach(buf)
    local function opts(desc)
        return { buffer = buf, desc = desc }
    end
    vim.keymap.set("n", "<leader>tt", tth.run_test,                    opts("Run typst test"))
    vim.keymap.set("n", "<leader>tu", tth.update_ref,                  opts("Update typst test ref"))
    vim.keymap.set("n", "<leader>tr", tth.map_open_render("identity"), opts("Open typst test render"))
    vim.keymap.set("n", "<leader>th", tth.open_html,                   opts("Open typst test html"))
    vim.keymap.set("n", "<leader>tp", tth.open_pdftags,                opts("Open typst test pdftags"))
end

tth.setup({
    on_attach = on_attach,
    programs = {
        -- Define custom commands to open two images in an external program.
        -- The two image paths will be appended to the command.
        my_program = { "my-program", "--some-option", "--split-view" },
    },
})

-- Your custom command can then be used like this.
tth.open_render("my-program")
```
