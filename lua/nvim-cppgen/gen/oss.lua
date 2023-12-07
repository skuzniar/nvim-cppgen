local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Output stream shift operators.
---------------------------------------------------------------------------------------------------
local M = {}

--- Returns true if the cursor position is within the node's range
local function encloses(node, cursor)
    local line = cursor.line - 1
    return node.range and node.range['start'].line <= line and node.range['end'].line >= line
end

--- Returns true if the cursor position is past the node's range
local function precedes(node, cursor)
    local line = cursor.line - 1
    return node.range and node.range['end'].line < line
end

-- Calculate the number of children and the longest length of the childe's name
local function maxlen(node)
    local cnt = 0
    local len = 0

    ast.dfs(node,
        function(n)
            return true
        end,
        function(n)
            if n.kind == "EnumConstant" or n.kind == "Field" then
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
    local ind = string.rep(' ', P.ind)
    local pad = string.rep(' ', P.len - string.len(nam))
    local spc = P.spc
    local res = format

    res = string.gsub(res, "<spc>", spc)
    res = string.gsub(res, "<nam>", nam)
    res = string.gsub(res, "<ind>", ind)
    res = string.gsub(res, "<pad>", pad)
    return res;
end

-- Generate friend output stream shift operator for a class type node.
local function shift_class_impl(node)
    log.trace("shift_class_impl: " .. ast.details(node))
    P.cnt, P.len = maxlen(node)
    P.ind = 4

    local lines = {}

    table.insert(lines, apply('<spc> std::ostream& operator<<(std::ostream& s, const <nam>& o)', node))
    table.insert(lines, apply('{', node))
    table.insert(lines, apply('<ind>// clang-format off', node))

    ast.dfs(node,
        function(n)
            return true
        end,
        function(n)
            if n.kind == "Field" then
                table.insert(lines, apply([[<ind>s << "<nam>:"<pad> << ' ' << o.<nam><pad> << ' ';]], n))
            end
        end
    )

    table.insert(lines, apply('<ind>// clang-format on', node))
    table.insert(lines, apply('<ind>return s;', node))
    table.insert(lines, apply('}', node))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate friend output stream shift operator for a class type node.
local function friend_shift_class(node)
    log.trace("friend_shift_class:", ast.details(node))
    P.spc = 'friend'
    return shift_class_impl(node)
end

-- Generate global output stream shift operator for a class type node.
local function global_shift_class(node)
    log.trace("global_shift_class:", ast.details(node))
    P.spc = 'inline'
    return shift_class_impl(node)
end

-- Generate global output stream shift operator for an enum type node.
local function global_shift_enum(node)
    log.trace("global_shift_enum:", ast.details(node))
    P.cnt, P.len = maxlen(node)
    P.spc = ''
    P.ind = 4

    local lines = {}

    table.insert(lines, apply('inline std::ostream& operator<<(std::ostream& s, <nam> o)', node))
    table.insert(lines, apply('{', node))
    table.insert(lines, apply('<ind>switch(o)', node))
    table.insert(lines, apply('<ind>{', node))
    table.insert(lines, apply('<ind><ind>// clang-format off', node))

    ast.dfs(node,
        function(n)
            return true
        end,
        function(n)
            if n.kind == "EnumConstant" then
                table.insert(lines, apply('<ind><ind>case ' .. ast.name(node) .. [[::<nam>:<pad> s << "<nam>";<pad> break;]], n))
            end
        end
    )

    table.insert(lines, apply('<ind><ind>// clang-format on', node))
    table.insert(lines, apply('<ind>};', node))

    table.insert(lines, apply('<ind>return s;', node))
    table.insert(lines, apply('}', node))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate plain output stream shift operator for a class type node.
local function shift_class(node, cursor)
    log.trace("shift_class:", ast.details(node))

    if encloses(node, cursor) then
        log.debug("shift_class: generation code for enclosing node")
        return
        {
            label            = 'friend',
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = friend_shift_class(node)
        }
    elseif precedes(node, cursor) then
        log.debug("shift_class: generation code for preceding node")
        return
        {
            label            = 'inline',
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = global_shift_class(node)
        }
    end
end

-- Generate plain output stream shift operator for a class type node.
local function shift_enum(node, cursor)
    log.trace("shift_enum:", ast.details(node))

    if precedes(node, cursor) then
        log.debug("shift_enum: generation code for preceding node")
        return
        {
            label            = 'inline',
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = global_shift_enum(node)
        }
    end
end

-- Generate plain output stream shift operator for a class type node.
function M.completion_items(node, cursor)
    log.trace("completion_items:", ast.details(node))

    if node.kind == "CXXRecord" then
        return shift_class(node, cursor)
    end
    if node.kind == "Enum" then
        return shift_enum(node, cursor)
    end
end

return M
