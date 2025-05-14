# typst-test-helper.nvim

## Setup

```lua
local tth = require("typst-test-helper")

local function on_attach(buf)
    local function opts(desc)
        return { buffer = buf, desc = desc }
    end
    vim.keymap.set("n", "<leader>ot", tth.map_open("identity"), opts("Open typst test"))

    -- Use the your custom program definition when creating key mappings.
    vim.keymap.set("n", "<leader>ot", tth.map_open("my_program"), opts("Open typst test in my-program"))
end

tth.setup({
    on_attach = on_attach,
    programs = {
        -- Define custom commands to open two images in an external program.
        -- The two image paths will be appended to the command.
        my_program = { "my-program", "--some-option", "--split-view" },
    },
})
```
