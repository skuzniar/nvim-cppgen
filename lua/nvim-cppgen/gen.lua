local ast = require('nvim-cppgen.ast')
local ctx = require('nvim-cppgen.ctx')
local log = require('nvim-cppgen.log')


---------------------------------------------------------------------------------------------------
-- Collection of code generators. Gathers code completion items from specialized generators.
---------------------------------------------------------------------------------------------------

local G = {
    require('nvim-cppgen.gen.oss'),
    require('nvim-cppgen.gen.cnv')
}

--- Exported functions
local M = {}

--- Returns true if any of the given nodes is of interest to any of the generators we manage
local function interesting(preceding, enclosing)
    for _,g in pairs(G) do
        if g.interesting(preceding, enclosing) then
            return true
        end
    end
    return false
end

--- Return true if the code generation is available in the current context - buffer and cursor position
function M.can_generate(bufnr)
	local cursor = ctx.context(bufnr)
    if cursor then
	    local line = cursor[1] - 1
	    local nodes = ast.relevant_nodes(bufnr, line)
	    if interesting(nodes.preceding, nodes.enclosing) then
            log.debug("Can generate code in buffer", bufnr, "line", line)
            return true
        end
    end
    log.debug("Can not generate code in buffer", bufnr)
    return false
end

--- Generate code completion items appropriate for the given context
function M.generate(bufnr)
	local cursor = ctx.context(bufnr)
    if cursor then
	    local line = cursor[1] - 1
        log.info("Generating code in buffer", bufnr, "line", line)
        local total = {}
	    local nodes = ast.relevant_nodes(bufnr, line)
        for _,g in pairs(G) do
            local items = g.completion_items(nodes.preceding, nodes.enclosing);
            for _,i in ipairs(items) do
                table.insert(total, i)
            end
        end
        log.info("Collected", #total, "completion items")
        return total
    end
end

return M
