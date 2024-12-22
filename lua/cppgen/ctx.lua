local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
--- Context capture module. Captures cursor position when entering insert mode.
---------------------------------------------------------------------------------------------------
local M = {}

--- Current cursor position.
local ctx = {}

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
end

function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)
    ctx[bufnr] = vim.api.nvim_win_get_cursor(0)
end

function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
    ctx[bufnr] = nil
end

function M.context( bufnr)
    log.trace("Retrieving context for buffer", bufnr)
    return ctx[bufnr]
end

return M
