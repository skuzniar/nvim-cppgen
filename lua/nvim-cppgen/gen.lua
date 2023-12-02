local ast = require('nvim-cppgen.ast')
local ctx = require('nvim-cppgen.ctx')
local log = require('nvim-cppgen.log')


---------------------------------------------------------------------------------------------------
-- Collection of code generators. Gathers code completion items from specialized generators.
---------------------------------------------------------------------------------------------------

local G = {
    require('nvim-cppgen.gen.oss')
}

--- Exported functions
local M = {}

--- Return true if the code generation is available in the current context - buffer and cursor position
function M.can_generate(bufnr)
	local ctxcrs = ctx.context(bufnr)
	local curcrs = vim.api.nvim_win_get_cursor(0)
    if ctxcrs and curcrs then
        local ldif = curcrs[1] - ctxcrs[1];
        local node = ast.relevant_node(bufnr, ctxcrs)
        if node then
            log.info("can_generate: " .. tostring(node ~= nil) .. " for ctx line=" .. ctxcrs[1] .. " delta=" .. ldif .. " " .. ast.details(node))
        else
            log.info("can_generate: " .. tostring(node ~= nil) .. " for ctx line=" .. ctxcrs[1] .. " delta=" .. ldif)
        end
        return node ~= nil
    end
    return false
end

--- Generate code completion itemss appropriate for the given context
function M.generate(bufnr, cursor)
    log.info("generate: Trying to refresh AST node...")
    ast.request_ast(bufnr, 1000)

	local ctxcrs = ctx.context(bufnr)
    if ctxcrs then
        local node = ast.relevant_node(bufnr, ctxcrs)
        if node then
            log.info("generate: has relevant node=" .. ast.details(node) .. " for context cursor at line=" .. ctxcrs[1])

            -- Collect completion items from all registered code generators
            local total = {}
            for _, g in ipairs(G) do
                local items = g.completion_items(node, cursor);
                if items then
                    table.insert(total, items)
                end
            end
            return total
        end
    end
end

return M
