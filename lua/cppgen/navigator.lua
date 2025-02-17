local log = require('cppgen.log')
local val = require('cppgen.validator')

---------------------------------------------------------------------------------------------------
-- Generated code validator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
}

--- Exported functions
local M = {}

---------------------------------------------------------------------------------------------------
--- Initialization and lifecycle callbacks
---------------------------------------------------------------------------------------------------

--- Initialization callback
function M.setup(opts)
end

--- LSP client attached callback
function M.attached(client, bufnr)
    log.info("Attached client", client.id, "buffer", bufnr)
end

--- Entering insert mode.
function M.insert_enter(bufnr)
    log.debug("Entered insert mode buffer:", bufnr)
end

--- Exiting insert mode.
function M.insert_leave(bufnr)
    log.debug("Exited insert mode buffer:", bufnr)
end

--- Wrote buffer
function M.after_write(bufnr)
    log.trace("Wrote buffer:", bufnr)
end

--- Get the next snippet span relative to the cursor
function M.get_next_span()
    local span = nil
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for _,s in ipairs(val.results()) do
        span = s.span
        if s.span.first+1 > line then
            break
        end
    end
    return span
end

--- Get the previous snippet span relative to the cursor
function M.get_prev_span()
    local span = nil
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for _,s in ipairs(val.results()) do
        if s.span.first+1 >= line then
            break
        end
        span = s.span
    end
    return span
end

return M

