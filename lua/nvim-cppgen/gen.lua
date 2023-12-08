local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')


---------------------------------------------------------------------------------------------------
-- Collection of code generators. Gathers code completion items from specialized generators.
---------------------------------------------------------------------------------------------------

local G = {
    require('nvim-cppgen.gen.oss')
}

--- Exported functions
local M = {}

--- Returns true if the node, enclosing or immediately preceding, is of interest to any of the generators we manage
local function interesting(node, enclosing)
    for _, g in ipairs(G) do
        if g.interesting(node, enclosing) then
            log.debug((enclosing and "Enclosing" or "Preceding"), ast.details(node), "is interesting")
            return true
        end
    end
    return false
end

--- Given a pair of preceding and enclosing nodes, return one that we want to generete code for
local function select_node(nodes, line)
    -- We can generate code if we are inside of an interesting node
    if nodes.enclosing and interesting(nodes.enclosing, true) then
        log.debug("Can generate code for enclosing node", ast.details(nodes.enclosing))
        return nodes.enclosing
    end
    -- We can also generate code if we have an interesting preceding node and we are not inside of a node
    if not nodes.enclosing and nodes.preceding and interesting(nodes.preceding, false) then
        log.debug("Can generate code for preceding node", ast.details(nodes.preceding))
        return nodes.preceding
    end
    return nil
end

--- Return true if the code generation is available in the current context - buffer and cursor position
function M.can_generate(bufnr)
	local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    log.debug("Checking if can generate code in buffer", bufnr, "line", line)
	local node = select_node(ast.relevant_nodes(bufnr, line), line)
    if node then
        log.info("Can generate code in buffer", bufnr, "line", line, "using node", ast.details(node))
        return true
    end
    log.info("Can not generate code in buffer", bufnr, "line", line)
    return false
end

--- Generate code completion itemss appropriate for the given context
function M.generate(bufnr, cursor)
    log.info("Refreshing AST data synchronously and trying to generate code at line", cursor.line)
    ast.request_ast(bufnr, 1000)

    local node = select_node(ast.relevant_nodes(bufnr, cursor.line), cursor.line)
    if node then
        log.info("Found relevant node", ast.details(node))
        -- Collect completion items from all registered code generators
        local total = {}
        for _, g in ipairs(G) do
            local items = g.completion_items(node, cursor);
            if items then
                table.insert(total, items)
            end
        end
        log.info("Collected", #total, "completion items for node", ast.details(node))
        return total
    else
        log.info("Did not find relevant node to generate code at line", cursor.line)
    end
end

return M
