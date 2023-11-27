local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
-- Output stream shift operators.
---------------------------------------------------------------------------------------------------
local M = {}

-- Calculate the number of children and the longest length of the childe's name
local function maxlen(node)
    local cnt = 0
    local len = 0

    ast.dfs(node,
        function(n)
            return n.kind == "Field" or n.kind == "CXXRecord"
        end,
        function(n)
            if n ~= node then
                cnt = cnt + 1
                len = math.max(len, string.len(ast.name(n)))
            end
        end
    )
    return cnt, len
end


---------------------------------------------------------------------------------------------------
-- Parameters
---------------------------------------------------------------------------------------------------
local P = {}

-- Apply node object to the format string 
local function apply(format, node)
    local nam = ast.name(node)
    local off = string.rep(' ', P.off)
    local ind = "    "
    local pad = string.rep(' ', P.len - string.len(nam))
    local res = format

    res = string.gsub(res, "<nam>", nam)
    res = string.gsub(res, "<off>", off)
    res = string.gsub(res, "<ind>", ind)
    res = string.gsub(res, "<pad>", pad)
    return res;
end

-- Generate plain output stream shift operator for a class type node.
local function shift_friend(node, offset)
    P.cnt, P.len = maxlen(node)
    P.off = offset

    local lines = {}

    table.insert(lines, apply('friend std::ostream& operator<<(std::ostream& s, const <nam>& o)', node))
    table.insert(lines, apply('<off>{', node))
    table.insert(lines, apply('<off><ind>// clang-format off', node))

    ast.dfs(node,
        function(n)
            return n.kind == "Field" or n.kind == "CXXRecord"
        end,
        function(n)
            if n ~= node then
                table.insert(lines, apply([[<off><ind>s << "<nam>:"<pad> << ' ' << o.<nam><pad> << ' ';]], n))
            end
        end
    )

    table.insert(lines, apply('<off><ind>// clang-format on', node))
    table.insert(lines, apply('<off><ind>return s;', node))
    table.insert(lines, apply('<off>}', node))

    for i,l in ipairs(lines) do log.info(l) end

    return table.concat(lines,"\n")
end

-- Generate plain output stream shift operator for a class type node.
function M.snippets(node, cursor)
    log.info("snippet: " .. ast.details(node))
    return
    {
        label      = 'friend',
        insertText = shift_friend(node, cursor.character - 1)
    }
end

return M
