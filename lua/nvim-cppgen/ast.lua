local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
--- AST utilities
---------------------------------------------------------------------------------------------------
local M = {}

--- Return node details - name and range, adjusted for line numbers starting from one.
function M.details(node)
    if node then
        if node.range then
            return node.role .. ' ' .. node.kind .. ' ' .. (node.detail or "<???>") .. '[' .. node.range['start'].line .. ',' .. node.range['end'].line .. ']'
        else
            return node.role .. ' ' .. node.kind .. ' ' .. (node.detail or "<???>") .. '[]'
        end
    else
        return 'nil'
    end
end

--- Return node name.
function M.name(node)
    if node then
        return (node.detail or "<???>")
    else
        return 'nil'
    end
end

--- Depth first traversal over AST tree with descend filter, pre and post order operations.
function M.dfs(node, filt, pref, posf)
    pref(node)
    if filt(node) then
        if node.children then
            for _, child in ipairs(node.children) do
	            M.dfs(child, filt, pref, posf)
		    end
	    end
    end
    if posf then
        posf(node)
    end
end

--- Visit immediate children of a given node.
function M.visit_children(node, f)
    if node.children then
        for _, child in ipairs(node.children) do
            f(child)
		end
    end
end

--- Count immediate children of a given node that satisfy the predicate.
function M.count_children(node, p)
    local cnt = 0
    if node.children then
        for _, child in ipairs(node.children) do
            if p(child) then
               cnt = cnt + 1
            end
		end
    end
    return cnt
end

--- Returns true if the cursor line position is within the node's range
function M.encloses(node, line)
    return not node.range or node.range['start'].line < line and node.range['end'].line > line
end

--- Returns true if the cursor line position is past the node's range
function M.precedes(node, line)
    return node.range ~= nil and node.range['end'].line < line
end

--- Returns true if two nodes perfectly overlay each other
function M.overlay(nodea, nodeb)
    return nodea and nodeb and nodea.range and nodeb.range and nodea.range['end'].line == nodeb.range['end'].line and nodea.range['start'].line == nodeb.range['start'].line
end

--- Returns true if the node has zero range
function M.phantom(node)
    return node.range ~= nil and node.range['end'].line == node.range['start'].line
end

return M
