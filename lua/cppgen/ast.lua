local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
--- AST utilities
---------------------------------------------------------------------------------------------------
local M = {}

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
            if not f(child) then
                return
            end
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

--- Return node line span.
function M.span(node)
    if node and node.range then
        return { first = node.range['start'].line, last = node.range['end'].line }
    end
    return nil
end

--- Return node name.
function M.name(node)
    if node then
        return (node.detail or "<???>")
    else
        return 'nil'
    end
end

-- Attempt to find the node type
function M.type(node)
    local result = nil
    M.dfs(node,
        function(_)
            return not result
        end,
        function(n)
            if n.role == "type" and n.detail ~= nil then
                result = n.detail
            end
        end
        )
    return result
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

function M.is_enum(node)
    return node and node.role == "declaration" and node.kind == "Enum" and not string.find(node.detail, "unnamed ")
end

function M.is_class(node)
    return node and node.role == "declaration" and (node.kind == "CXXRecord" or node.kind == "ClassTemplate")
end

function M.is_class_template(node)
    return node and node.role == "declaration" and node.kind == "ClassTemplate"
end

return M
