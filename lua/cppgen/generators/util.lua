local ast = require('cppgen.ast')
local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------------------------------

-- Return name, value and type of enum constant.
local function enum_value_and_kind(node)
    log.trace("enum_value_and_kind:", ast.details(node))

    local v = nil
    local k = nil
    ast.visit_children(node,
        function(n)
            if n.kind == "IntegerLiteral" or n.kind == "CharacterLiteral" then
                v, k = n.detail, n.kind
            else
                v, k = enum_value_and_kind(n)
            end
            return v == nil and k == nil
        end
    )
    return v, k
end

-- Return name, value and type of enum constant.
local function enum_record(node)
    log.trace("enum_record:", ast.details(node))

    local v, k = enum_value_and_kind(node)
    return {label=ast.name(node), value=v, kind=k}
end

local M = {}

---------------------------------------------------------------------------------------------------
-- Collect names, values and types of enum type node.
---------------------------------------------------------------------------------------------------
function M.enum_records(node)
    log.trace("enum_records:", ast.details(node))

    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                table.insert(records, enum_record(n))
            end
            return true
        end
    )
    return records
end

---------------------------------------------------------------------------------------------------
-- Convert snake_case to CamelCase.
---------------------------------------------------------------------------------------------------
function M.camelize(s)
    local function capitalize(s)
        return (string.gsub(s, '^%l', string.upper))
    end
    s = string.gsub(s, '^%a_', '')
    return (string.gsub(s, '%W*(%w+)', capitalize))
end

---------------------------------------------------------------------------------------------------
-- Convert table of tables of items into a table of items.
---------------------------------------------------------------------------------------------------
function M.flatten(...)
    local items = {}
    for _,t in ipairs({...}) do
        for _,i in ipairs(t) do
            table.insert(items, i)
        end
    end
    return items
end

return M
