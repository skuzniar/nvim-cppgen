local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
-- Context capture module
---------------------------------------------------------------------------------------------------
local M = {}

--- Editing context captured for each buffer
local ctx = {}

--- Callback invoked when the LSP client has been attache to the buffer
function M.attached(client, bufnr)
    --log.info("attached: " .. tostring(client.id) .. ":" .. tostring(bufnr))
end

--- Callback invoked when we enter insert mode in the buffer attached to an LSP client
function M.insert_enter(client, bufnr)
	ctx[bufnr] = vim.api.nvim_win_get_cursor(0)
    log.info("insert_enter: " .. tostring(client.id) .. ":" .. tostring(bufnr) .. " line=" .. tostring(ctx[bufnr][1]))
end

--- Callback invoked when we leave insert mode in the buffer attached to an LSP client
function M.insert_leave(client, bufnr)
	ctx[bufnr] = vim.api.nvim_win_get_cursor(0)
    log.info("insert_leave: " .. tostring(client.id) .. ":" .. tostring(bufnr) .. " line=" .. tostring(ctx[bufnr][1]))
end

-- Generate output stream shift operator for a given AST node.
function M.context(bufnr)
	return ctx[bufnr]
end

return M
