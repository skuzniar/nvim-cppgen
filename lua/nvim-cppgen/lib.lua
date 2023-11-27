local ast = require('nvim-cppgen.ast')
local ctx = require('nvim-cppgen.ctx')
local log = require('nvim-cppgen.log')

local oss = require('nvim-cppgen.gen.oss')


--- Exported functions
local M = {}

--- Return true if the code generation is available in the current context - buffer and cursor position
function M.code_gen_available(bufnr)
	local ctxcrs = ctx.context(bufnr)
	local curcrs = vim.api.nvim_win_get_cursor(0)
    if ctxcrs and curcrs then
        local ldif = curcrs[1] - ctxcrs[1];
        local node = ast.enclosing_node(bufnr, ctxcrs)
        if node then
            log.info("code_gen_available: " .. tostring(node ~= nil) .. " for ctx line=" .. ctxcrs[1] .. " delta=" .. ldif .. " " .. ast.details(node))
        else
            log.info("code_gen_available: " .. tostring(node ~= nil) .. " for ctx line=" .. ctxcrs[1] .. " delta=" .. ldif)
        end
        return node ~= nil
    end
    return false
end

--- Generate code snippet(s) appropriate for the given context
function M.code_gen(bufnr, cursor)
    log.info("code_gen: Trying to refresh AST node...")
    ast.request_ast(bufnr, 1000)

	local ctxcrs = ctx.context(bufnr)
    if ctxcrs then
        local node = ast.enclosing_node(bufnr, ctxcrs)
        if node then
            log.info("code_gen: has node=" .. tostring(node ~= nil) .. " for context cursor at line=" .. ctxcrs[1])
            return
            {
                oss.snippets(node, cursor)
            }
        end
    end
end

return M
