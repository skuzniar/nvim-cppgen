local ast = require('nvim-cppgen.ast')
local ctx = require('nvim-cppgen.ctx')
local src = require('nvim-cppgen.src')
local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
-- Code generation module. Forwards events to the ast module. Acts as a completion source.
---------------------------------------------------------------------------------------------------
local M = {}

--- Callback invoked when the LSP client has been attache to the buffer
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
	ast.attached(client, bufnr)
	ctx.attached(client, bufnr)
end

--- Callback invoked when we enter insert mode in the buffer attached to a LSP client
function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode in buffer", bufnr)
	ast.insert_enter(client, bufnr)
	ctx.insert_enter(client, bufnr)
end

--- Callback invoked when we leave insert mode in the buffer attached to a LSP client
function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode in buffer", bufnr)
	ast.insert_leave(client, bufnr)
	ctx.insert_leave(client, bufnr)
end

--- Generator is a source for the code completion engine
function M.source()
    log.trace("source")
    return src.new()
end

return M
