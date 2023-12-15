local ast = require('nvim-cppgen.ast')
local cfg = require('nvim-cppgen.cfg')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Output stream shift operators.
---------------------------------------------------------------------------------------------------

local do_droppfix = false
local do_camelize = false

local function capitalize(s)
    return (string.gsub(s, '^%l', string.upper))
end

local function camelize(s)
    return (string.gsub(s, '%W*(%w+)', capitalize))
end

local function label(name)
    if do_droppfix then
        name = string.gsub(name, '^%a_', '')
    end
    if do_camelize then
        name = camelize(name)
    end

    return name
end

--- Returns true if the cursor position is within the node's range
local function encloses(node, cursor)
    return node.range and node.range['start'].line < cursor.line and node.range['end'].line > cursor.line
end

--- Returns true if the cursor position is past the node's range
local function precedes(node, cursor)
    return node.range and node.range['end'].line < cursor.line
end

-- Calculate the longest length of the childe's label and name
local function maxlen(node)
    local max_lab_len = 0
    local max_nam_len = 0

    ast.dfs(node,
        function(n)
            return true
        end,
        function(n)
            if n.kind == "EnumConstant" or n.kind == "Field" then
                max_lab_len = math.max(max_lab_len, string.len(label(ast.name(n))))
                max_nam_len = math.max(max_nam_len, string.len(ast.name(n)))
            end
        end
    )
    return max_lab_len, max_nam_len
end

---------------------------------------------------------------------------------------------------
-- Parameters
---------------------------------------------------------------------------------------------------
local P = {}

-- Apply node object to the format string 
local function apply(format, node)
    local name = ast.name(node)
    local labl = label(ast.name(node))
    local indt = string.rep(' ', P.indt)
    local lpad = string.rep(' ', P.llen - string.len(labl))
    local npad = string.rep(' ', P.nlen - string.len(name))
    local spec = P.spec or ''

    local result  = format

    result = string.gsub(result, "<spec>", spec)
    result = string.gsub(result, "<name>", name)
    result = string.gsub(result, "<labl>", labl)
    result = string.gsub(result, "<indt>", indt)
    result = string.gsub(result, "<lpad>", lpad)
    result = string.gsub(result, "<npad>", npad)
    return result;
end

-- Generate friend output stream shift operator for a class type node.
local function shift_class_impl(node)
    log.debug("shift_class_impl:", ast.details(node))
    P.llen, P.nlen = maxlen(node)
    P.indt = 4

    local lines = {}

    table.insert(lines, apply('<spec> std::ostream& operator<<(std::ostream& s, const <name>& o)', node))
    table.insert(lines, apply('{', node))
    table.insert(lines, apply('<indt>// clang-format off', node))

    ast.dfs(node,
        function(n)
            return true
        end,
        function(n)
            if n.kind == "Field" then
                table.insert(lines, apply([[<indt>s << "<labl>:"<lpad> << ' ' << o.<name><npad> << ' ';]], n))
            end
        end
    )

    table.insert(lines, apply('<indt>// clang-format on', node))
    table.insert(lines, apply('<indt>return s;', node))
    table.insert(lines, apply('}', node))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate friend output stream shift operator for a class type node.
local function friend_shift_class(node)
    log.trace("friend_shift_class:", ast.details(node))
    P.spec = 'friend'
    return shift_class_impl(node)
end

-- Generate global output stream shift operator for a class type node.
local function global_shift_class(node)
    log.trace("global_shift_class:", ast.details(node))
    P.spec = 'inline'
    return shift_class_impl(node)
end

-- Generate global output stream shift operator for an enum type node.
local function global_shift_enum(node)
    log.trace("global_shift_enum:", ast.details(node))
    P.llen, P.nlen = maxlen(node)
    P.indt = 4

    local lines = {}

    table.insert(lines, apply('inline std::ostream& operator<<(std::ostream& s, <name> o)', node))
    table.insert(lines, apply('{', node))
    table.insert(lines, apply('<indt>switch(o)', node))
    table.insert(lines, apply('<indt>{', node))
    table.insert(lines, apply('<indt><indt>// clang-format off', node))

    ast.dfs(node,
        function(n)
            return true
        end,
        function(n)
            if n.kind == "EnumConstant" then
                table.insert(lines, apply('<indt><indt>case ' .. ast.name(node) .. [[::<name>:<npad> s << "<name>";<npad> break;]], n))
            end
        end
    )

    table.insert(lines, apply('<indt><indt>// clang-format on', node))
    table.insert(lines, apply('<indt>};', node))

    table.insert(lines, apply('<indt>return s;', node))
    table.insert(lines, apply('}', node))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate plain output stream shift operator for a class type node.
local function shift_class(node, cursor)
    log.trace("shift_class:", ast.details(node))

    if encloses(node, cursor) then
        log.debug("Generation code for enclosing node")
        return
        {
            label            = 'friend',
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = friend_shift_class(node)
        }
    elseif precedes(node, cursor) then
        log.debug("Generation code for preceding node")
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
        log.debug("Generation code for preceding node")
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

local M = {}

--- Returns true if the node is of interest to us
function M.interesting(node, enclosing)
    -- We can generate shift operator for preceding enumeration node
    if not enclosing and node.role == "declaration" and node.kind == "Enum" then
        return true
    end
    -- We can generate shift operator for both preceding and enclosing class nodes
    if node.role == "declaration" and node.kind == "CXXRecord" then
        return true
    end

    return false
end

-- Generate plain output stream shift operator for a class type node.
function M.completion_items(node, cursor)
    log.trace("completion_items:", ast.details(node))

    -- Set options
    do_droppfix = cfg.options.oss and cfg.options.oss.drop_prefix
    do_camelize = cfg.options.oss and cfg.options.oss.camelize

    if node.kind == "CXXRecord" then
        return shift_class(node, cursor)
    end
    if node.kind == "Enum" then
        return shift_enum(node, cursor)
    end
end

return M
